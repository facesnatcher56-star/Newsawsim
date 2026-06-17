extends RigidBody3D

@export var lifetime: float = 12.0

func _ready() -> void:
	add_to_group("bark_pieces")
	
	# Randomize scale slightly for visual variety
	var random_scale = randf_range(0.7, 1.3)
	scale = Vector3(
		random_scale * randf_range(0.8, 1.2),
		random_scale * randf_range(0.8, 1.2),
		random_scale * randf_range(0.8, 1.2)
	)
	
	# Start a timer to free the object
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(_delta: float) -> void:
	# Clean up if it falls off the map
	if global_position.y < -5.0:
		queue_free()
