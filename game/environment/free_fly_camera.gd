extends Camera3D

## Standard 3D Free-Fly Spectator Camera
## - Press ESC key anytime to release mouse cursor.
## - Click inside game window to re-capture mouse.
## - W / S / A / D : Move forward / backward / left / right
## - E / Space     : Fly UP
## - Q / Ctrl      : Fly DOWN
## - Shift         : Boost fly speed (3x)

@export var move_speed: float = 10.0
@export var boost_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.15
@export var auto_capture_on_start: bool = true

var _pitch: float = 0.0
var _yaw: float = 0.0


func _ready() -> void:
	if auto_capture_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_pitch = rotation_degrees.x
	_yaw = rotation_degrees.y


func _unhandled_input(event: InputEvent) -> void:
	# Press ESC to release mouse cursor
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.is_action("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

	# Click inside window to re-capture mouse
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	# Mouse look when captured
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -89.0, 89.0)

		rotation_degrees.x = _pitch
		rotation_degrees.y = _yaw


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): dir -= Vector3.UP

	if dir.length_squared() > 0.0:
		global_position += dir.normalized() * speed * delta
