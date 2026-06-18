extends AnimatableBody3D

## log_stop.gd
## A physical cross-bar stop that rises to block logs queuing on the live deck,
## then folds flat below deck surface to let one log through to the tilter.

signal fully_extended
signal fully_retracted

@export var extended_angle_deg: float = 80.0    # Upright — blocking logs
@export var retracted_angle_deg: float = -10.0  # Flat below deck surface
@export var rotate_speed_deg: float = 90.0      # degrees per second

var _target_angle_deg: float = 80.0
var _current_angle_deg: float = 80.0
var _at_target: bool = true

func _ready() -> void:
	_current_angle_deg = extended_angle_deg
	_target_angle_deg = extended_angle_deg
	rotation_degrees.x = _current_angle_deg

func _physics_process(delta: float) -> void:
	if _at_target:
		return

	var prev := _current_angle_deg
	_current_angle_deg = move_toward(_current_angle_deg, _target_angle_deg, rotate_speed_deg * delta)
	rotation_degrees.x = _current_angle_deg

	if is_equal_approx(_current_angle_deg, _target_angle_deg):
		_at_target = true
		if is_equal_approx(_target_angle_deg, extended_angle_deg):
			fully_extended.emit()
		else:
			fully_retracted.emit()

func extend() -> void:
	_target_angle_deg = extended_angle_deg
	_at_target = false

func retract() -> void:
	_target_angle_deg = retracted_angle_deg
	_at_target = false

func is_extended() -> bool:
	return is_equal_approx(_current_angle_deg, extended_angle_deg)

func is_retracted() -> bool:
	return is_equal_approx(_current_angle_deg, retracted_angle_deg)
