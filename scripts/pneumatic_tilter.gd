extends AnimatableBody3D

## pneumatic_tilter.gd
## A pivoting tilter arm that sits below the live deck surface.
## When triggered it swings up to tip the front log off the deck
## in the +X direction (onto the carriage knees).
## Visual pneumatic cylinder extends/contracts as the arm moves.

signal tip_complete
signal retract_complete

@export var rest_angle_deg: float = -88.0    # Flat below deck surface
@export var tip_angle_deg: float = 40.0      # Raised — pushes log sideways
@export var tip_speed_deg: float = 55.0      # degrees per second (pneumatic feel)
@export var retract_speed_deg: float = 70.0

var _target_angle_deg: float = -88.0
var _current_angle_deg: float = -88.0
var _at_target: bool = true
var _tipping: bool = false

# Visual pneumatic cylinder references (set in _ready via node path)
@onready var _cylinder_visual: Node3D = get_node_or_null("CylinderVisual")

func _ready() -> void:
	_current_angle_deg = rest_angle_deg
	_target_angle_deg = rest_angle_deg
	rotation_degrees.x = _current_angle_deg

func _physics_process(delta: float) -> void:
	if _at_target:
		return

	var speed := tip_speed_deg if _tipping else retract_speed_deg
	_current_angle_deg = move_toward(_current_angle_deg, _target_angle_deg, speed * delta)
	rotation_degrees.x = _current_angle_deg

	# Animate cylinder extend/contract based on arm angle
	if _cylinder_visual:
		var t: float = (_current_angle_deg - rest_angle_deg) / maxf(tip_angle_deg - rest_angle_deg, 0.001)
		t = clamp(t, 0.0, 1.0)
		_cylinder_visual.scale.z = lerp(0.6, 1.0, t)

	if is_equal_approx(_current_angle_deg, _target_angle_deg):
		_at_target = true
		if _tipping:
			tip_complete.emit()
		else:
			retract_complete.emit()

func tip() -> void:
	_target_angle_deg = tip_angle_deg
	_tipping = true
	_at_target = false

func retract() -> void:
	_target_angle_deg = rest_angle_deg
	_tipping = false
	_at_target = false

func is_at_rest() -> bool:
	return is_equal_approx(_current_angle_deg, rest_angle_deg)
