extends RigidBody3D

## cut_board.gd
## Represents a physically cut board that falls onto the outfeed conveyor.

@export var lifetime: float = 20.0

func _ready() -> void:
	# Add to a group if needed
	add_to_group("cut_boards")
	
	# Auto-destroy after lifetime to keep scene clean
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(_delta: float) -> void:
	# Safe fallback if it falls out of the world
	if global_position.y < -5.0:
		queue_free()
