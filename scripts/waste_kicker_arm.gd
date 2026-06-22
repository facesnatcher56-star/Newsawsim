## waste_kicker_arm.gd
## Attached to KickerShaft. Rotates the shaft around its local Z axis to sweep
## all arm bodies from home to the kick position, then retracts. The
## AnimatableBody3D arm bodies physically push logs via sync_to_physics.
extends Node3D

## Degrees the shaft rotates during the kick stroke.
## Positive sweeps one way, negative the other — flip if arms go the wrong way.
@export var kick_angle_deg: float = 75.0
## Seconds for the outward kick stroke.
@export var kick_duration: float = 0.5
## Seconds for the retract stroke.
@export var retract_duration: float = 0.8
## Debug only: auto-triggers kick() on scene start for testing.
@export var debug_kick_on_ready: bool = false

var _home_rotation_z: float = 0.0
var _is_kicking: bool = false
var _tween: Tween = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_home_rotation_z = rotation.z
	# Make all AnimatableBody3D arm bodies sync with the physics server so they
	# push RigidBody3D logs when the shaft sweeps through them.
	for pivot in get_children():
		if not pivot is Node3D:
			continue
		for child in pivot.get_children():
			if child is AnimatableBody3D:
				child.sync_to_physics = true
	if debug_kick_on_ready:
		kick.call_deferred()

func kick() -> void:
	if _is_kicking:
		return
	_is_kicking = true
	if _tween:
		_tween.kill()
	var kick_z := _home_rotation_z + deg_to_rad(kick_angle_deg)
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "rotation:z", kick_z, kick_duration) \
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "rotation:z", _home_rotation_z, retract_duration) \
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func(): _is_kicking = false, CONNECT_ONE_SHOT)
