@tool
extends StaticBody3D

const ChainTroughFrameBuilder := preload("res://game/transport/conveyors/builders/chain_trough_frame_builder.gd")
const ChainTroughChainBuilder := preload("res://game/transport/conveyors/builders/chain_trough_chain_builder.gd")

## chain_trough_conveyor.gd
##
## A conveyor with a V-trough bed, 4 parallel chains running along the bottom center,
## and an integrated 3-arm mechanical kicker shaft.
##
## The kicker arms look like a ">" shape pointing away from the conveyor when resting,
## and swing through slots in the left conveyor wall to kick logs.

# ── Exported Variables ────────────────────────────────────────────────────────
@export_group("Conveyor Physics")
@export var speed: float = 1.5:
	set(v):
		speed = v
		_update_velocity()
@export var direction: Vector3 = Vector3.FORWARD:
	set(v):
		direction = v
		_update_velocity()
## If assigned, this conveyor will stop if the downstream conveyor is full or blocked.
@export var downstream_conveyor: StaticBody3D
## Area3D at the end of THIS conveyor to detect if a log is waiting to move off.
@export var exit_sensor: Area3D

@export_group("Chain Geometry & Visuals")
@export var conveyor_length: float = 4.0:
	set(v):
		conveyor_length = v
		_rebuild_everything()
@export var conveyor_width: float = 1.2:
	set(v):
		conveyor_width = v
		_rebuild_everything()
@export var track_x_positions: Array[float] = [-0.15, -0.05, 0.05, 0.15]:
	set(v):
		track_x_positions = v
		_rebuild_everything()
@export var link_spacing: float = 0.24:
	set(v):
		link_spacing = v
		_rebuild_everything()
@export var sprocket_radius: float = 0.15:
	set(v):
		sprocket_radius = v
		_rebuild_everything()

@export_group("Kicker Configuration")
@export var kicker_enabled: bool = true
@export var kick_swing_speed: float = 220.0 ## Degrees per second for extending
@export var retract_speed: float = 180.0    ## Degrees per second for retracting
@export var hold_at_top: float = 0.3         ## Seconds to hold at full extension
@export var shaft_rotation_retracted: float = 0.0 ## Shaft rotation when retracted
@export var shaft_rotation_extended: float = 95.0  ## Shaft rotation when fully extended

# ── Constants ─────────────────────────────────────────────────────────────────
const BED_PLATE_T   := 0.05
const WALL_H        := 0.40
const WALL_T        := 0.02
const CHAIN_Y       := 0.04

# Sprocket
const SPROCKET_HUB_R:= 0.045
const SPROCKET_HUB_T:= 0.04
const SPROCKET_SEGS := 10

# Chain Link
const CHAIN_PLATE_W := 0.012
const CHAIN_PLATE_H := 0.035
const CHAIN_PLATE_D := 0.160
const CHAIN_SPAN    := 0.08
const CHAIN_ROLLER_R:= 0.018

# Kicker Arms
const ARM_COUNT := 3
const ARM_LOWER_L := 0.45
const ARM_UPPER_L := 0.45
const KICK_SHAFT_X := -0.55
const KICK_SHAFT_Y := -0.20

# ── State variables ───────────────────────────────────────────────────────────
enum KickerState { IDLE, KICKING, HOLDING, RETRACTING }
var _state: KickerState = KickerState.IDLE
var _hold_timer: float = 0.0
var _shaft_angle: float = shaft_rotation_retracted

var _is_stopped_by_backpressure: bool = false
var _log_area: Area3D = null
var _last_left_wall_x: float = 0.0
var _last_right_wall_x: float = 0.0

# Geometry tracking
var _sprocket_cy: float
var _loop_len: float
var _visuals_root: Node3D

# Chain links and rotating parts (animated in _process)
var _multimesh_plates: MultiMeshInstance3D
var _multimesh_rollers: MultiMeshInstance3D
var _num_links: int = 0
var _rotating_parts: Array[Node3D] = []
var _travel_distance: float = 0.0

# Kicker arm parts
var _kicker_shaft_node: Node3D = null
var _kicker_pivots: Array[Node3D] = []
var _kicker_upper_bodies: Array[AnimatableBody3D] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_sprocket_cy = CHAIN_Y - sprocket_radius
	_loop_len = 2.0 * conveyor_length + 2.0 * PI * sprocket_radius

	_log_area = get_node_or_null("LogArea")
	_update_velocity()

	# Rebuild geometry and collisions
	_build_visuals()
	_rebuild_collision()

	# In runtime, set up kicker shaft to starting position
	_update_kicker_arms()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Handle conveyor backpressure
	var blocked = false
	if is_instance_valid(downstream_conveyor):
		var downstream_busy = false
		if downstream_conveyor.has_method("is_full") and downstream_conveyor.is_full():
			downstream_busy = true
		elif downstream_conveyor.get("speed") == 0.0 or downstream_conveyor.get("_is_stopped_by_backpressure") == true:
			downstream_busy = true
			
		if downstream_busy and is_instance_valid(exit_sensor) and exit_sensor.has_overlapping_bodies():
			blocked = true
	
	if blocked != _is_stopped_by_backpressure:
		_is_stopped_by_backpressure = blocked
		_update_velocity()

	# Lock log rotations and lateral drift to keep them centered on the chains
	if _log_area != null:
		var fwd := direction.normalized()
		for body in _log_area.get_overlapping_bodies():
			if body is RigidBody3D and body.is_in_group("logs"):
				body.angular_velocity = Vector3.ZERO
				var v: Vector3 = body.linear_velocity
				body.linear_velocity = fwd * v.dot(fwd) + Vector3(0.0, v.y, 0.0)

	# Handle kicker state machine
	if kicker_enabled:
		_process_kicker(delta)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		var left_wall_node = get_node_or_null("LeftWall")
		var right_wall_node = get_node_or_null("RightWall")
		var left_x = left_wall_node.position.x if left_wall_node else -conveyor_width * 0.5
		var right_x = right_wall_node.position.x if right_wall_node else conveyor_width * 0.5
		if not is_equal_approx(left_x, _last_left_wall_x) or not is_equal_approx(right_x, _last_right_wall_x):
			_last_left_wall_x = left_x
			_last_right_wall_x = right_x
			_rebuild_everything()
		return

	# Animate chain links and sprockets — always run at the editor-set speed,
	# regardless of backpressure (backpressure only stops log physics, not animation).
	# Chains are laid out along the local Z axis, so scroll speed is derived
	# from the Z component of direction. If direction has no Z component
	# (e.g. direction = Vector3(1,0,0) for X-aligned conveyors), fall back
	# to the X component, then default to positive speed.
	var dir_norm := direction.normalized()
	var scroll_speed = speed * dir_norm.z
	if is_zero_approx(scroll_speed):
		scroll_speed = speed * dir_norm.x
	if is_zero_approx(scroll_speed):
		scroll_speed = speed
	if not is_zero_approx(scroll_speed):
		_travel_distance += scroll_speed * delta
		_update_chain_positions(_travel_distance)
		
		# Rotate sprockets and shafts
		var rot_step = (scroll_speed / sprocket_radius) * delta
		for part in _rotating_parts:
			if is_instance_valid(part):
				part.rotate_object_local(Vector3.UP, rot_step)


# ── Conveyor Logic ────────────────────────────────────────────────────────────

func is_full() -> bool:
	return is_instance_valid(exit_sensor) and exit_sensor.has_overlapping_bodies()


func _update_velocity() -> void:
	var current_speed = 0.0 if _is_stopped_by_backpressure else speed
	constant_linear_velocity = direction.normalized() * current_speed


# ── Kicker Logic ──────────────────────────────────────────────────────────────

func kick() -> void:
	if not kicker_enabled or _state != KickerState.IDLE:
		return
	_state = KickerState.KICKING


func is_kicker_idle() -> bool:
	return _state == KickerState.IDLE


func _process_kicker(delta: float) -> void:
	match _state:
		KickerState.IDLE:
			_shaft_angle = shaft_rotation_retracted
			_update_kicker_arms()

		KickerState.KICKING:
			_shaft_angle = move_toward(_shaft_angle, shaft_rotation_extended, kick_swing_speed * delta)
			_update_kicker_arms()
			if is_equal_approx(_shaft_angle, shaft_rotation_extended):
				_state = KickerState.HOLDING
				_hold_timer = hold_at_top

		KickerState.HOLDING:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_state = KickerState.RETRACTING

		KickerState.RETRACTING:
			_shaft_angle = move_toward(_shaft_angle, shaft_rotation_retracted, retract_speed * delta)
			_update_kicker_arms()
			if is_equal_approx(_shaft_angle, shaft_rotation_retracted):
				_state = KickerState.IDLE


func _update_kicker_arms() -> void:
	# Rotate the kicker shaft node (which has the arms attached as children)
	if is_instance_valid(_kicker_shaft_node):
		_kicker_shaft_node.rotation_degrees.z = _shaft_angle

	# Update the physics upper arm sync_to_physics
	# In Godot 4, changing AnimatableBody3D rotation will correctly sweep physics objects
	# since they are parented to the rotating shaft. No extra steps needed!


# ── Geometry Generation ────────────────────────────────────────────────────────

func _build_visuals() -> void:
	# Clean old visuals
	var old_visuals = get_node_or_null("Visuals")
	if old_visuals:
		if Engine.is_editor_hint():
			remove_child(old_visuals)
		old_visuals.queue_free()

	_visuals_root = Node3D.new()
	_visuals_root.name = "Visuals"
	add_child(_visuals_root)

	_rotating_parts.clear()

	# 1. Build Trough Bed
	_build_trough_bed()

	# 2. Build Sprockets, Shafts, and Chains
	_build_shafts_and_sprockets()
	_build_chains()

	# 3. Build Kicker Shaft and Arms
	_build_kicker_hardware()


func _build_trough_bed() -> void:
	ChainTroughFrameBuilder.new(self).build_trough_bed()


func _build_shafts_and_sprockets() -> void:
	ChainTroughChainBuilder.new(self).build_shafts_and_sprockets()


func _build_chains() -> void:
	ChainTroughChainBuilder.new(self).build_chains()


func _get_loop_transform(d: float, loop_length: float) -> Transform3D:
	d = fposmod(d, loop_length)
	var pi_R := PI * sprocket_radius
	var L := (loop_length - 2.0 * pi_R) * 0.5
	var half_z := conveyor_length * 0.5
	var y := 0.0
	var z := 0.0
	var rot_x := 0.0

	if d < L:
		z = -half_z + d
		y = CHAIN_Y
	elif d < L + pi_R:
		var theta := (d - L) / sprocket_radius
		z = half_z + sprocket_radius * sin(theta)
		y = _sprocket_cy + sprocket_radius * cos(theta)
		rot_x = theta - 2.0 * PI
	elif d < 2.0 * L + pi_R:
		z = half_z - (d - (L + pi_R))
		y = _sprocket_cy - sprocket_radius
		rot_x = -PI
	else:
		var theta := (d - (2.0 * L + pi_R)) / sprocket_radius
		z = -half_z - sprocket_radius * sin(theta)
		y = _sprocket_cy - sprocket_radius * cos(theta)
		rot_x = theta - PI
	return Transform3D(Basis(Vector3.RIGHT, rot_x), Vector3(0.0, y, z))


func _update_chain_positions(travel_dist: float) -> void:
	if not is_instance_valid(_multimesh_plates) or not is_instance_valid(_multimesh_rollers):
		return
	var num_tracks := track_x_positions.size()
	var inner_x := CHAIN_SPAN * 0.5 + CHAIN_PLATE_W * 0.5
	
	var plate_idx := 0
	var roller_idx := 0
	
	for xi in num_tracks:
		var tx := track_x_positions[xi]
		for j in _num_links:
			var slot0 := float(j) * link_spacing + travel_dist
			var xf := _get_loop_transform(slot0, _loop_len)
			var link_pos := Vector3(tx, xf.origin.y, xf.origin.z)
			var link_xf := Transform3D(xf.basis, link_pos)
			
			# Left Plate
			var lp_xf := link_xf * Transform3D(Basis(), Vector3(-inner_x, 0.0, 0.0))
			_multimesh_plates.multimesh.set_instance_transform(plate_idx, lp_xf)
			plate_idx += 1
			
			# Right Plate
			var rp_xf := link_xf * Transform3D(Basis(), Vector3(inner_x, 0.0, 0.0))
			_multimesh_plates.multimesh.set_instance_transform(plate_idx, rp_xf)
			plate_idx += 1
			
			# Joint Roller
			var ro_xf := link_xf * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3.ZERO)
			_multimesh_rollers.multimesh.set_instance_transform(roller_idx, ro_xf)
			roller_idx += 1


func _build_kicker_hardware() -> void:
	# Reference existing KickerShaft in the scene
	_kicker_shaft_node = get_node_or_null("KickerShaft")
	_kicker_pivots.clear()
	_kicker_upper_bodies.clear()

	if _kicker_shaft_node:
		# Extract upper arm bodies for physics updates
		for child in _kicker_shaft_node.get_children():
			if child.name.begins_with("ArmPivot"):
				_kicker_pivots.append(child)
				var upper = child.get_node_or_null("UpperArmBody")
				if not upper:
					for gchild in child.get_children():
						if gchild.name.begins_with("UpperArmBody"):
							upper = gchild
							break
				if upper:
					_kicker_upper_bodies.append(upper)


func _rebuild_everything() -> void:
	_sprocket_cy = CHAIN_Y - sprocket_radius
	_loop_len = 2.0 * conveyor_length + 2.0 * PI * sprocket_radius
	if is_node_ready():
		_build_visuals()
		_rebuild_collision()


func _rebuild_collision() -> void:
	ChainTroughFrameBuilder.new(self).rebuild_collision()
