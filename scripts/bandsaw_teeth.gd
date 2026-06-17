@tool
extends Node3D

@export var tooth_count: int = 28
@export var min_y: float = 0.46
@export var max_y: float = 3.34
@export var blade_speed: float = 3.35
@export var edge_x: float = -0.05
@export var tooth_direction: float = -1.0
@export var tooth_depth: float = 0.07
@export var tooth_height: float = 0.075
@export var tooth_thickness: float = 0.018

var _tooth_nodes: Array[MeshInstance3D] = []
var _travel_offset := 0.0
var _material: StandardMaterial3D

func _ready() -> void:
	_build_teeth()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_travel_offset = fposmod(_travel_offset + blade_speed * delta, max_y - min_y)
	_update_tooth_positions()

func _build_teeth() -> void:
	for child in get_children():
		child.queue_free()
	_tooth_nodes.clear()
	
	if tooth_count <= 0 or max_y <= min_y:
		return
	
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.86, 0.86, 0.9, 1.0)
	_material.metallic = 0.95
	_material.roughness = 0.16
	
	for i in range(tooth_count):
		var tooth = MeshInstance3D.new()
		tooth.name = "TravelingTooth%02d" % i
		tooth.mesh = _create_tooth_mesh()
		tooth.material_override = _material
		add_child(tooth)
		_tooth_nodes.append(tooth)
	
	_update_tooth_positions()

func _update_tooth_positions() -> void:
	var span := max_y - min_y
	var spacing := span / float(tooth_count)
	for i in range(_tooth_nodes.size()):
		var tooth := _tooth_nodes[i]
		var y_pos := min_y + fposmod(float(i) * spacing - _travel_offset, span)
		tooth.position = Vector3(0.0, y_pos, 0.0)

func _create_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	var half_h := tooth_height * 0.5
	var half_t := tooth_thickness * 0.5
	var back_x := edge_x
	var direction_sign: float = -1.0 if tooth_direction <= 0.0 else 1.0
	var tip_x: float = edge_x + tooth_depth * direction_sign
	
	var front := [
		Vector3(back_x, -half_h, half_t),
		Vector3(back_x, half_h, half_t),
		Vector3(tip_x, 0.0, half_t),
	]
	var back := [
		Vector3(back_x, -half_h, -half_t),
		Vector3(tip_x, 0.0, -half_t),
		Vector3(back_x, half_h, -half_t),
	]
	
	_add_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	_add_face(vertices, normals, indices, back, Vector3(0, 0, -1))
	_add_quad(vertices, normals, indices, front[0], back[0], back[2], front[1])
	_add_quad(vertices, normals, indices, front[1], back[2], back[1], front[2])
	_add_quad(vertices, normals, indices, front[2], back[1], back[0], front[0])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_face(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, points: Array, normal: Vector3) -> void:
	var start := vertices.size()
	for point in points:
		vertices.append(point)
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2]))

func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var start := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
