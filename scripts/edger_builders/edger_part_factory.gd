@tool
extends RefCounted

## Low-level CSG/mesh/node factory used by the edger builders to construct
## procedurally generated parts. Holds the naming/editor-group bookkeeping
## that used to live on SawmillEdger itself.

var edger: SawmillEdger

var _generated_name_counts: Dictionary = {}
var _editor_group_stack: Array[Node3D] = []
var _preserved_editor_group_transforms: Dictionary = {}


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func _preserve_editor_group_transforms() -> void:
	_preserved_editor_group_transforms.clear()
	for child in edger.get_children():
		if child is Node3D and child.get_meta("edger_editor_group", false):
			_preserved_editor_group_transforms[child.name] = child.transform


func _push_editor_group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	group.set_meta("edger_editor_group", true)
	if _preserved_editor_group_transforms.has(group_name):
		group.transform = _preserved_editor_group_transforms[group_name]
	_current_part_parent().add_child(group)
	_adopt_new_node(group)
	_editor_group_stack.append(group)
	return group


func _pop_editor_group() -> void:
	if not _editor_group_stack.is_empty():
		_editor_group_stack.pop_back()


func _current_part_parent() -> Node:
	if _editor_group_stack.is_empty():
		return edger
	return _editor_group_stack.back()


func _add_infeed_chain_link(node_name: String, local_position: Vector3, index: int) -> Node3D:
	var link_root := Node3D.new()
	link_root.name = node_name
	link_root.position = local_position
	_current_part_parent().add_child(link_root)
	_adopt_new_node(link_root)

	var link_length := SawmillEdger.CHAIN_LINK_LENGTH * 0.72
	var side_plate_width := SawmillEdger.CHAIN_LINK_WIDTH * 0.22
	var side_plate_z := SawmillEdger.CHAIN_LINK_WIDTH * 0.5 - side_plate_width * 0.5
	_add_box_child(link_root, "OuterPlate_L", Vector3(0.0, 0.0, -side_plate_z), Vector3(link_length, SawmillEdger.CHAIN_LINK_THICKNESS, side_plate_width), edger._mat_dark)
	_add_box_child(link_root, "OuterPlate_R", Vector3(0.0, 0.0, side_plate_z), Vector3(link_length, SawmillEdger.CHAIN_LINK_THICKNESS, side_plate_width), edger._mat_dark)
	_add_box_child(link_root, "CenterPad", Vector3(0.0, SawmillEdger.CHAIN_LINK_THICKNESS * 0.18, 0.0), Vector3(link_length * 0.54, SawmillEdger.CHAIN_LINK_THICKNESS * 0.55, SawmillEdger.CHAIN_LINK_WIDTH * 0.42), edger._mat_chain_grip)
	_add_cylinder_child(link_root, "CrossPin", Vector3(0.0, -SawmillEdger.CHAIN_LINK_THICKNESS * 0.05, 0.0), 0.011, SawmillEdger.CHAIN_LINK_WIDTH + 0.02, edger._mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 10)

	var tooth_mesh := _create_chain_grip_tooth_mesh()
	var tooth_xs: Array[float] = [-link_length * 0.22, link_length * 0.22]
	for tooth_i in range(tooth_xs.size()):
		var tooth := MeshInstance3D.new()
		tooth.name = "GripTooth_%02d" % (tooth_i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = edger._mat_chain_grip
		tooth.position = Vector3(tooth_xs[tooth_i], SawmillEdger.CHAIN_LINK_THICKNESS * 0.5, 0.0)
		tooth.rotation.y = PI if (index + tooth_i) % 2 == 1 else 0.0
		tooth.scale.y = 0.4030368
		link_root.add_child(tooth)
		_adopt_new_node(tooth)

	return link_root


func _add_box_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material, collision: bool = true) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = local_position
	box.size = size
	box.material = material
	box.use_collision = collision
	parent.add_child(box)
	_adopt_new_node(box)
	return box


func _add_cylinder_child(parent: Node3D, node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = node_name
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	parent.add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _add_physics_box(node_name: String, local_position: Vector3, size: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = _friendly_part_name(node_name, local_position)
	body.position = local_position
	body.rotation = local_rotation
	body.sync_to_physics = false
	_current_part_parent().add_child(body)
	_adopt_new_node(body)
	_add_box_contact_child(body, "Visual", Vector3.ZERO, size, material)
	return body


func _add_physics_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = _friendly_part_name(node_name, local_position)
	body.position = local_position
	body.rotation = local_rotation
	body.sync_to_physics = false
	_current_part_parent().add_child(body)
	_adopt_new_node(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	_adopt_new_node(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	_adopt_new_node(collision)
	return body


func _add_box_contact_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	_adopt_new_node(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = node_name + "Collision"
	collision.position = local_position
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	_adopt_new_node(collision)
	return mesh_instance


func _create_chain_grip_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var half_l := SawmillEdger.CHAIN_GRIP_TOOTH_LENGTH * 0.5
	var half_w := SawmillEdger.CHAIN_GRIP_TOOTH_WIDTH * 0.5
	var front := [
		Vector3(-half_l, 0.0, half_w),
		Vector3(half_l, 0.0, half_w),
		Vector3(half_l * 0.35, SawmillEdger.CHAIN_GRIP_TOOTH_HEIGHT, half_w),
		Vector3(-half_l * 0.75, SawmillEdger.CHAIN_GRIP_TOOTH_HEIGHT * 0.28, half_w),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_w))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_saw_teeth(node_name: String, center: Vector3, radius: float) -> Node3D:
	var teeth_root := Node3D.new()
	teeth_root.name = node_name
	teeth_root.position = center
	_current_part_parent().add_child(teeth_root)
	_adopt_new_node(teeth_root)

	var tooth_mesh := _create_saw_tooth_mesh()
	var tooth_count := 48
	var tooth_root_radius := radius - 0.012
	for i in range(tooth_count):
		var angle := TAU * float(i) / float(tooth_count)
		var tooth := MeshInstance3D.new()
		tooth.name = "Tooth_%02d" % (i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = edger._mat_blade
		tooth.position = Vector3(cos(angle) * tooth_root_radius, sin(angle) * tooth_root_radius, 0.0)
		tooth.rotation = Vector3(0.0, 0.0, angle)
		teeth_root.add_child(tooth)
		_adopt_new_node(tooth)
	return teeth_root


func _create_saw_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var tooth_depth := 0.055
	var tangential_root := 0.026
	var tangential_tip := 0.006
	var half_thickness := 0.018
	var front := [
		Vector3(0.0, -tangential_root, half_thickness),
		Vector3(tooth_depth * 0.70, -tangential_tip, half_thickness),
		Vector3(tooth_depth, tangential_tip, half_thickness),
		Vector3(0.0, tangential_root, half_thickness),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_thickness))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh_face(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, points: Array, normal: Vector3) -> void:
	var start := vertices.size()
	for point in points:
		vertices.append(point)
		normals.append(normal)
	for i in range(1, points.size() - 1):
		indices.append_array(PackedInt32Array([start, start + i, start + i + 1]))


func _add_mesh_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var start := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _add_box(node_name: String, local_position: Vector3, size: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO, collision: bool = true) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = _friendly_part_name(node_name, local_position)
	box.position = local_position
	box.rotation = local_rotation
	box.size = size
	box.material = material
	box.use_collision = collision
	_current_part_parent().add_child(box)
	_adopt_new_node(box)
	return box


func _add_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = _friendly_part_name(node_name, local_position)
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	_current_part_parent().add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _adopt_new_node(node: Node) -> void:
	if not Engine.is_editor_hint() or not edger.expose_generated_parts or not edger.is_inside_tree():
		return
	if not node.get_meta("edger_editor_group", false):
		return
	var scene_root := edger.get_tree().edited_scene_root
	if scene_root == null or scene_root != edger:
		return
	if node != scene_root:
		node.owner = scene_root


func _friendly_part_name(base_name: String, local_position: Vector3) -> String:
	var node_name_str := "%s_%s" % [base_name, _position_name_suffix(local_position)]
	node_name_str = node_name_str.replace("__", "_").strip_edges(false, true)
	var used_count := int(_generated_name_counts.get(node_name_str, 0)) + 1
	_generated_name_counts[node_name_str] = used_count
	if used_count > 1:
		node_name_str = "%s_%02d" % [node_name_str, used_count]
	return node_name_str


func _position_name_suffix(local_position: Vector3) -> String:
	var parts: Array[String] = []
	if local_position.x < -0.18:
		parts.append("Infeed")
	elif local_position.x > 0.18:
		parts.append("Outfeed")
	else:
		parts.append("CenterX")

	if local_position.z < -0.08:
		parts.append("Front")
	elif local_position.z > 0.08:
		parts.append("Back")
	else:
		parts.append("CenterZ")

	if local_position.y < edger.working_height - 0.12:
		parts.append("Lower")
	elif local_position.y > edger.working_height + 0.32:
		parts.append("Upper")
	else:
		parts.append("Mid")

	return "_".join(PackedStringArray(parts))
