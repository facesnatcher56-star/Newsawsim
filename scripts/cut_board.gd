extends RigidBody3D

## cut_board.gd
## Represents a physically cut board that falls onto the outfeed conveyor.

@export var lifetime: float = 20.0
@export var product_length: float = 4.958

## When enabled, prints every physics contact (what the board is touching,
## the contact normal, and the push impulse) plus current velocity.
@export var debug_contacts: bool = false
@export var debug_interval: float = 0.25

var _debug_timer: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	_apply_product_length(product_length)

	# Thin lumber can move farther than its thickness in one physics step.
	continuous_cd = true
	linear_damp = 0.4
	angular_damp = 1.0
	mass = 50.0
	gravity_scale = 4.5
	can_sleep = false

	# Hold-down rollers read our colliding bodies to stop descending on touch.
	contact_monitor = true
	max_contacts_reported = 8

	input_ray_pickable = true
	input_event.connect(_on_board_input_event)

	# Add to a group if needed
	add_to_group("cut_boards")
	if scene_file_path.ends_with("cut_slab.tscn") or name.to_lower().contains("slab"):
		add_to_group("cut_slabs")


func _on_board_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_inspect_board()


func _inspect_board() -> void:
	var gpos: Vector3 = global_position
	var rot_deg := Vector3(rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z))
	var vel := linear_velocity
	var colliding := get_colliding_bodies()

	print("\n==================================================")
	print(" 🔍 [BOARD INSPECTION] Node: '%s'" % name)
	print(" Global Position: (X: %.3f, Y: %.3f, Z: %.3f)" % [gpos.x, gpos.y, gpos.z])
	print(" Rotation (Deg):  (X: %.1f°, Y: %.1f°, Z: %.1f°)" % [rot_deg.x, rot_deg.y, rot_deg.z])
	print(" Linear Velocity: (X: %.2f, Y: %.2f, Z: %.2f) m/s" % [vel.x, vel.y, vel.z])
	print(" Colliding Bodies (%d):" % colliding.size())
	for body in colliding:
		if is_instance_valid(body):
			print("   - Touching: '%s' (%s) at pos %s" % [body.name, body.get_class(), _fmt_vec(body.global_position)])
	print("==================================================\n")

	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if is_instance_valid(mi):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.1)
		mat.emission_energy_multiplier = 2.5
		mi.material_override = mat
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(mi):
				mi.material_override = null
		)
	
	# Auto-destroy after lifetime to keep scene clean (disabled for now)
	# get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(_delta: float) -> void:
	# Safe fallback if it falls out of the world
	if global_position.y < -5.0:
		queue_free()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not debug_contacts:
		return
	_debug_timer += state.step
	if _debug_timer < debug_interval:
		return
	_debug_timer = 0.0

	# Velocity change since last report reveals scripted pushes (conveyor code
	# using apply_force / setting velocity) that never appear as contacts.
	var vel := state.linear_velocity
	var accel := (vel - _prev_velocity) / debug_interval
	_prev_velocity = vel

	var lines := PackedStringArray()
	lines.append("[%s] vel=%s accel=%s contacts=%d" % [
		name, _fmt_vec(vel), _fmt_vec(accel), state.get_contact_count()])
	for i in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(i)
		var collider_desc := "<unknown>"
		if collider is Node:
			collider_desc = "%s (%s)" % [(collider as Node).name, collider.get_class()]
		var normal := state.get_contact_local_normal(i)
		var impulse := state.get_contact_impulse(i)
		lines.append("    touching %s | normal=%s | impulse=%s |%.3f|" % [
			collider_desc, _fmt_vec(normal), _fmt_vec(impulse), impulse.length()])
	print("\n".join(lines))

static func _fmt_vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

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
