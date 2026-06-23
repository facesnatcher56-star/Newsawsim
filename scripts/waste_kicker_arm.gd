## waste_kicker_arm.gd
## Attached to KickerShaft. Simulates a proper log-kicker linkage:
##   - LowerArm is welded to the shaft and rotates with it.
##   - UpperArmBody is pinned to the LowerArm tip (pin joint) and constrained
##     by a roller in a guide slot — it translates with the pin and tips
##     independently, NOT rotating as a rigid unit with the lower arm.
extends Node3D

## How far the shaft rotates during the kick. Flip sign if arms go wrong way.
@export var kick_angle_deg: float = 75.0
## How much the upper arm tips during the kick (roller guide constraint effect).
## Flip sign if arm tips away from the log instead of toward it.
@export var upper_tip_deg: float = 30.0
## Seconds for the outward kick stroke.
@export var kick_duration: float = 0.6
## Seconds for the retract stroke.
@export var retract_duration: float = 1.0
## Debug only: auto-triggers kick() at scene start for testing.
@export var debug_kick_on_ready: bool = false

const LOWER_ARM_LENGTH := 0.66866636

var _lower_arms: Array[Node3D] = []
var _upper_bodies: Array[AnimatableBody3D] = []
var _lower_arm_home_rots: Array[float] = []
var _upper_body_home_bases: Array[Basis] = []
var _upper_body_home_positions: Array[Vector3] = []
var _pin_to_upper_offsets: Array[Vector3] = []
var _shaft_axis: Vector3

var _is_kicking := false
var _retracting := false
var _tween: Tween = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_shaft_axis = global_transform.basis.z.normalized()

	for child in get_children():
		if not child is Node3D or child is MeshInstance3D:
			continue
		var lower := child.get_node_or_null("LowerArm") as Node3D
		if lower == null:
			continue
		var upper: AnimatableBody3D = null
		for c in child.get_children():
			if c is AnimatableBody3D:
				upper = c
				break
		if upper == null:
			continue
		_lower_arms.append(lower)
		_upper_bodies.append(upper)

	# Capture editor-defined home state immediately — no physics frame needed.
	# The editor positions are the authority for where the arms should rest.
	for i in _lower_arms.size():
		_lower_arm_home_rots.append(_lower_arms[i].rotation.z)
		_upper_body_home_bases.append(_upper_bodies[i].global_transform.basis)
		_upper_body_home_positions.append(_upper_bodies[i].global_transform.origin)
		# Offset from the lower arm tip (pin joint) to the upper arm origin.
		# Stored so position tracking works regardless of exact scene geometry.
		var pin_home := _lower_arms[i].to_global(Vector3(0.0, LOWER_ARM_LENGTH, 0.0))
		_pin_to_upper_offsets.append(_upper_bodies[i].global_transform.origin - pin_home)
		_upper_bodies[i].sync_to_physics = true

	if debug_kick_on_ready:
		kick()

func kick() -> void:
	if _is_kicking:
		return
	_is_kicking = true
	if _tween:
		_tween.kill()
	_retracting = false
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_method(_apply_fraction, 0.0, 1.0, kick_duration) \
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_begin_retract)
	_tween.tween_method(_apply_fraction, 1.0, 0.0, retract_duration) \
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_end_retract)

func _begin_retract() -> void:
	_retracting = true
	for b in _upper_bodies:
		if is_instance_valid(b):
			b.sync_to_physics = false

func _end_retract() -> void:
	_retracting = false
	_is_kicking = false
	for b in _upper_bodies:
		if is_instance_valid(b):
			b.sync_to_physics = true

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _lower_arms.is_empty():
		return
	if not _is_kicking:
		_apply_fraction(0.0)

func _apply_fraction(f: float) -> void:
	var shaft_rad := deg_to_rad(kick_angle_deg) * f
	var tip_rad   := deg_to_rad(upper_tip_deg) * f

	for i in _lower_arms.size():
		# Lower arm: rotates with the shaft
		_lower_arms[i].rotation.z = _lower_arm_home_rots[i] + shaft_rad

		# Pin world position = lower arm tip, with stored offset to upper arm origin
		var pin_world := _lower_arms[i].to_global(Vector3(0.0, LOWER_ARM_LENGTH, 0.0))
		var upper_pos := pin_world + _pin_to_upper_offsets[i]

		# Upper arm: tracks pin position, tips by roller-guide amount
		var tipped_basis := _upper_body_home_bases[i].rotated(_shaft_axis, tip_rad)
		_upper_bodies[i].global_transform = Transform3D(tipped_basis, upper_pos)
