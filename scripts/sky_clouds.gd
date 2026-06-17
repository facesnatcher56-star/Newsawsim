extends Node3D

@export var cloud_count: int = 16
@export var sky_height: float = 22.0
@export var wind_speed: float = 0.4 # units per second
@export var area_size: float = 70.0 # boundaries for wrapping

var clouds: Array[Node3D] = []

func _ready() -> void:
	# Cool unshaded white material for clouds
	var cloud_mat = StandardMaterial3D.new()
	cloud_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Spawn cloud clusters
	for i in range(cloud_count):
		var cloud_root = Node3D.new()
		cloud_root.name = "Cloud_%d" % i
		
		# Distribute them randomly across the sky area
		var px = randf_range(-area_size/2.0, area_size/2.0)
		var pz = randf_range(-area_size/2.0, area_size/2.0)
		var py = sky_height + randf_range(-2.0, 2.0)
		cloud_root.position = Vector3(px, py, pz)
		
		# Build a low-poly fluffy cloud cluster using 3-6 flattened spheres
		var sphere_count = randi_range(3, 6)
		for j in range(sphere_count):
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = 1.0
			sphere_mesh.height = 2.0
			
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = sphere_mesh
			mesh_inst.material_override = cloud_mat
			
			# Fluffy cloud proportions
			var rx = randf_range(1.8, 3.8)
			var ry = randf_range(0.9, 1.6)
			var rz = randf_range(1.8, 3.8)
			mesh_inst.scale = Vector3(rx, ry, rz)
			
			# Offset spheres to form an organic cluster shape
			mesh_inst.position = Vector3(
				randf_range(-1.6, 1.6),
				randf_range(-0.4, 0.4),
				randf_range(-1.6, 1.6)
			)
			cloud_root.add_child(mesh_inst)
			
		add_child(cloud_root)
		clouds.append(cloud_root)

func _process(delta: float) -> void:
	for cloud in clouds:
		cloud.position.x += wind_speed * delta
		# Wrap clouds around boundaries
		if cloud.position.x > area_size/2.0:
			cloud.position.x = -area_size/2.0
			cloud.position.z = randf_range(-area_size/2.0, area_size/2.0)
