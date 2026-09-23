class_name SorterCradleVisualBuilder
extends RefCounted

## Builds the orange tapered catch trays seen on industrial lumber bin sorters.
## Each bay gets four deep plate arms welded to a common cross-shaft assembly.

const FORK_Z: Array[float] = [-1.5, -0.5, 0.5, 1.5]
const CRADLE_DEPTH: float = 5.20
const PLATE_THICKNESS: float = 0.11


static func build(
		sorter: Node3D,
		imported_cradles: Array[Node3D],
		num_bays: int,
		bay_width: float,
		top_y: float
) -> Array[Node3D]:
	for imported: Node3D in imported_cradles:
		if is_instance_valid(imported):
			imported.visible = false

	var old_root: Node = sorter.get_node_or_null("CradleVisuals")
	if is_instance_valid(old_root):
		old_root.free()

	var root := Node3D.new()
	root.name = "CradleVisuals"
	sorter.add_child(root)

	var orange: StandardMaterial3D = _make_orange_material()
	var dark_steel: StandardMaterial3D = _make_steel_material()
	var plate_mesh: ArrayMesh = _make_tapered_plate_set(orange)
	var spine_mesh := BoxMesh.new()
	spine_mesh.size = Vector3(0.15, 0.18, CRADLE_DEPTH)
	spine_mesh.material = orange
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.070
	shaft_mesh.bottom_radius = 0.070
	shaft_mesh.height = CRADLE_DEPTH + 0.16
	shaft_mesh.radial_segments = 16
	shaft_mesh.material = dark_steel
	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = 0.125
	collar_mesh.bottom_radius = 0.125
	collar_mesh.height = 0.055
	collar_mesh.radial_segments = 16
	collar_mesh.material = orange

	# Four batched render objects replace 350 individual MeshInstance3D nodes.
	# The 50 marker roots remain independent so each physical bay can still index
	# vertically, while update_bay() copies that motion into these MultiMeshes.
	var plates_mm: MultiMeshInstance3D = _make_multimesh("TaperedForkPlates", plate_mesh, num_bays)
	var spines_mm: MultiMeshInstance3D = _make_multimesh("RearSpines", spine_mesh, num_bays)
	var shafts_mm: MultiMeshInstance3D = _make_multimesh("PivotShafts", shaft_mesh, num_bays)
	var collars_mm: MultiMeshInstance3D = _make_multimesh("PivotCollars", collar_mesh, num_bays * FORK_Z.size())
	root.add_child(plates_mm)
	root.add_child(spines_mm)
	root.add_child(shafts_mm)
	root.add_child(collars_mm)

	var replacements: Array[Node3D] = []
	for bay: int in range(num_bays):
		var cradle := Node3D.new()
		cradle.name = "OrangeCradle_%02d" % bay
		cradle.position = Vector3(float(bay) * bay_width + bay_width * 0.5, top_y, 0.0)
		root.add_child(cradle)
		replacements.append(cradle)
		update_bay(plates_mm, spines_mm, shafts_mm, collars_mm, bay, cradle.transform)

	return replacements


static func _make_multimesh(instance_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var visual := MultiMeshInstance3D.new()
	visual.name = instance_name
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	visual.multimesh = multimesh
	return visual


static func update_bay(
		plates: MultiMeshInstance3D,
		spines: MultiMeshInstance3D,
		shafts: MultiMeshInstance3D,
		collars: MultiMeshInstance3D,
		bay: int,
		cradle_transform: Transform3D
) -> void:
	plates.multimesh.set_instance_transform(bay, cradle_transform)
	spines.multimesh.set_instance_transform(
		bay, cradle_transform * Transform3D(Basis(), Vector3(-0.355, -0.13, 0.0)))
	var shaft_local := Transform3D(
		Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3(-0.355, -0.145, 0.0))
	shafts.multimesh.set_instance_transform(bay, cradle_transform * shaft_local)
	for fork_index: int in FORK_Z.size():
		var collar_local := Transform3D(
			Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)),
			Vector3(-0.355, -0.145, FORK_Z[fork_index]))
		collars.multimesh.set_instance_transform(
			bay * FORK_Z.size() + fork_index, cradle_transform * collar_local)


static func _make_orange_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Worn safety orange catch tray"
	material.albedo_color = Color(0.78, 0.19, 0.035, 1.0)
	material.metallic = 0.62
	material.roughness = 0.48
	return material


static func _make_steel_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Dark worn pivot steel"
	material.albedo_color = Color(0.105, 0.085, 0.070, 1.0)
	material.metallic = 0.88
	material.roughness = 0.42
	return material


static func _make_tapered_plate_set(material: Material) -> ArrayMesh:
	# Flat load edge with a deep heel and rounded, tapered nose. The plate hangs
	# below Y=0 so its bearing edge agrees with the existing cradle collision.
	var profile: Array[Vector2] = [
		Vector2(-0.42, 0.0),
		Vector2(0.28, 0.0),
		Vector2(0.38, -0.015),
		Vector2(0.43, -0.055),
		Vector2(0.41, -0.105),
		Vector2(0.30, -0.135),
		Vector2(-0.18, -0.245),
		Vector2(-0.42, -0.245),
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for fork_z: float in FORK_Z:
		_append_extruded_profile(vertices, normals, indices, profile, fork_z, PLATE_THICKNESS)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func _append_extruded_profile(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		indices: PackedInt32Array,
		profile: Array[Vector2],
		center_z: float,
		thickness: float
) -> void:
	var front_z: float = center_z + thickness * 0.5
	var back_z: float = center_z - thickness * 0.5
	# Front/back fans. The profile is convex enough for a stable fan around point 0.
	for i: int in range(1, profile.size() - 1):
		_append_triangle(vertices, normals, indices,
			Vector3(profile[0].x, profile[0].y, front_z),
			Vector3(profile[i + 1].x, profile[i + 1].y, front_z),
			Vector3(profile[i].x, profile[i].y, front_z))
		_append_triangle(vertices, normals, indices,
			Vector3(profile[0].x, profile[0].y, back_z),
			Vector3(profile[i].x, profile[i].y, back_z),
			Vector3(profile[i + 1].x, profile[i + 1].y, back_z))

	for i: int in range(profile.size()):
		var next_i: int = (i + 1) % profile.size()
		var a := Vector3(profile[i].x, profile[i].y, back_z)
		var b := Vector3(profile[next_i].x, profile[next_i].y, back_z)
		var c := Vector3(profile[next_i].x, profile[next_i].y, front_z)
		var d := Vector3(profile[i].x, profile[i].y, front_z)
		_append_quad(vertices, normals, indices, a, d, c, b)


static func _append_triangle(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		indices: PackedInt32Array,
		a: Vector3,
		b: Vector3,
		c: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var start: int = vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	indices.append_array(PackedInt32Array([start, start + 1, start + 2]))


static func _append_quad(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		indices: PackedInt32Array,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var start: int = vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
