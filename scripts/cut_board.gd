extends RigidBody3D

## cut_board.gd
## Represents a physically cut board that falls onto the outfeed conveyor.

@export var lifetime: float = 20.0
@export var product_length: float = 4.958

func _ready() -> void:
	_apply_product_length(product_length)

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

func configure_length(length: float) -> void:
	product_length = maxf(length, 0.1)
	if is_inside_tree():
		_apply_product_length(product_length)

func _apply_product_length(length: float) -> void:
	var half_length := length * 0.5
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
		if collision_shape.shape is BoxShape3D:
			var box_shape := collision_shape.shape as BoxShape3D
			box_shape.size.x = length
		elif collision_shape.shape is ConvexPolygonShape3D:
			var convex_shape := collision_shape.shape as ConvexPolygonShape3D
			var points := convex_shape.points
			for i in range(points.size()):
				if not is_zero_approx(points[i].x):
					points[i].x = signf(points[i].x) * half_length
			convex_shape.points = points

	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh is BoxMesh:
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
		var box_mesh := mesh_instance.mesh as BoxMesh
		box_mesh.size.x = length

	var slab_cylinder := get_node_or_null("CSGCombiner3D/Cylinder") as CSGCylinder3D
	if slab_cylinder != null:
		slab_cylinder.height = length

	var slab_cut_box := get_node_or_null("CSGCombiner3D/CutBox") as CSGBox3D
	if slab_cut_box != null:
		slab_cut_box.size.x = length + 0.5
