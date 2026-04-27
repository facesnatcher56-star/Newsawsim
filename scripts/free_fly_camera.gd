extends Camera3D

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.002

var rotation_x: float = 0.0
var rotation_y: float = 0.0

func _ready() -> void:
	# Capture the mouse for smooth looking
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Initialize rotation variables from current transform
	var rot = quaternion.get_euler()
	rotation_x = rot.x
	rotation_y = rot.y

func _input(event: InputEvent) -> void:
	# Toggle mouse capture with ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Handle mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, deg_to_rad(-90), deg_to_rad(90))
		
		transform.basis = Basis.from_euler(Vector3(rotation_x, rotation_y, 0))

func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
		
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_E): input_dir.y += 1
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1
	
	# Move relative to the camera's rotation
	var forward = transform.basis.z
	var right = transform.basis.x
	var up = Vector3.UP
	
	var direction = (forward * input_dir.z + right * input_dir.x + up * input_dir.y).normalized()
	global_translate(direction * move_speed * delta)
