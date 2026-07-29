extends Camera3D

## Free-Fly 3D Camera Script
## - Press ESC key anytime to release mouse cursor to click outside window.
## - Left-Click or Right-Click in window to re-capture mouse for flying.

@export var move_speed: float = 8.0
@export var mouse_sensitivity: float = 0.002
@export var auto_capture_on_start: bool = true

var rotation_x: float = 0.0
var rotation_y: float = 0.0


func _ready() -> void:
	if auto_capture_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var rot := quaternion.get_euler()
	rotation_x = rot.x
	rotation_y = rot.y


func _unhandled_input(event: InputEvent) -> void:
	# Release mouse cursor when ESC is pressed so user can click outside game window
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.is_action("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

	# Re-capture mouse when user clicks inside game window
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	# Mouse look when captured
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clampf(rotation_x, deg_to_rad(-90.0), deg_to_rad(90.0))

		transform.basis = Basis.from_euler(Vector3(rotation_x, rotation_y, 0.0))


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if Input.is_key_pressed(KEY_E): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1.0

	var forward := transform.basis.z
	var right := transform.basis.x
	var up := Vector3.UP

	var direction := (forward * input_dir.z + right * input_dir.x + up * input_dir.y).normalized()
	global_translate(direction * move_speed * delta)
