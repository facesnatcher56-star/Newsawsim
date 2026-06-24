extends RigidBody3D

## cut_board.gd
## Represents a physically cut board that falls onto the outfeed conveyor.

@export var lifetime: float = 20.0

func _ready() -> void:
	# Thin lumber can move farther than its thickness in one physics step.
	# Continuous collision detection prevents tunneling into roller geometry.
	continuous_cd = true

	# Add to a group if needed
	add_to_group("cut_boards")
	if scene_file_path.ends_with("cut_slab.tscn") or name.to_lower().contains("slab"):
		add_to_group("cut_slabs")
	
	# Auto-destroy after lifetime to keep scene clean (disabled for now)
	# get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(_delta: float) -> void:
	# Safe fallback if it falls out of the world
	if global_position.y < -5.0:
		queue_free()
