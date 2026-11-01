extends RigidBody3D

## Loose bark chunk (RigidBody3D) that despawns after `lifetime` seconds.

## Long enough to ride the debarker's bark belt up into the bin, which collects it.
@export var lifetime: float = 30.0

## Physics layer 6, bark only (the bark bin's area looks for it).
const BARK_LAYER := 1 << 5

func _ready() -> void:
	add_to_group("bark_pieces")
	# Bark has a layer of its own and only collides with the world (layer 1), not with other
	# bark: dozens of chunks heaped on the bark belt were a large share of the physics step.
	collision_layer = BARK_LAYER
	collision_mask = 1
	
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
