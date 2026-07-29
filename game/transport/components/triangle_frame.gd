@tool
extends MeshInstance3D

## TriangleFrame.gd
## Procedurally generates a triangular metal frame.

@export var height: float = 2.0:
	set(v): height = v; _generate_mesh()
@export var width: float = 2.0:
	set(v): width = v; _generate_mesh()
@export var thickness: float = 0.2:
	set(v): thickness = v; _generate_mesh()
@export var depth: float = 0.2:
	set(v): depth = v; _generate_mesh()

func _ready() -> void:
	_generate_mesh()

func _generate_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Material setup (Silver/Metal look)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.45)
	mat.metallic = 1.0
	mat.roughness = 0.3
	material_override = mat

	# Define 3 points of the triangle
	var p1 = Vector3(-width/2, 0, 0)
	var p2 = Vector3(width/2, 0, 0)
	var p3 = Vector3(0, height, 0)
	
	# Add the three beams
	_add_beam(st, p1, p2)
	_add_beam(st, p2, p3)
	_add_beam(st, p3, p1)
	
	st.generate_normals()
	mesh = st.commit()

func _add_beam(st: SurfaceTool, start: Vector3, end: Vector3) -> void:
	var dir = (end - start).normalized()
	var length = (end - start).length()
	
	# Create a simple box mesh and transform it to look like a beam
	var box = BoxMesh.new()
	box.size = Vector3(thickness, length, depth)
	
	var mesh_data = MeshDataTool.new()
	var temp_mesh = ArrayMesh.new()
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mesh_data.create_from_surface(temp_mesh, 0)
	
	# Transform vertices to align with the triangle edge
	var mid_point = (start + end) / 2.0
	var l_basis = Basis()
	var up = dir
	var right = up.cross(Vector3.FORWARD).normalized()
	if right.length() < 0.1: right = up.cross(Vector3.RIGHT).normalized()
	var forward = right.cross(up).normalized()
	l_basis = Basis(right, up, forward)
	
	for i in range(mesh_data.get_vertex_count()):
		var v = mesh_data.get_vertex(i)
		v = (l_basis * v) + mid_point
		mesh_data.set_vertex(i, v)
	
	# Commit back to surface tool
	mesh_data.commit_to_surface(temp_mesh)
	st.append_from(temp_mesh, 0, Transform3D.IDENTITY)
