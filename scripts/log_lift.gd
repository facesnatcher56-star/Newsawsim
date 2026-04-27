extends AnimatableBody3D

## LogLift.gd
## Moves the lift up the incline along its own local X-axis.
## Resets once it passes the ReleaseZone threshold.

@export var speed: float = 0.2
@export var direction_multiplier: float = -1.0
@export var reset_threshold_z: float = 4.38
var start_position: Vector3
var is_paused: bool = false

func _ready() -> void:
	start_position = global_position
	# Add to a group for easy access
	add_to_group("log_lifts")
	print("[LOG LIFT] Initialized at: ", start_position)

func _physics_process(delta: float) -> void:
	if is_paused:
		return
		
	# Move along its LOCAL X-axis, flipped if necessary
	var move_vec = transform.basis.x * (speed * direction_multiplier) * delta
	global_position += move_vec
	
	# Loop the lift: If it passes the ReleaseZone (MarkerYellow), reset to start.
	if global_position.z > reset_threshold_z:
		global_position = start_position
