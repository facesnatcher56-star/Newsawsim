extends StaticBody3D

@export var speed: float = 1.4
@export var direction: Vector3 = Vector3(0.0, 0.447, -0.894) # Sloped towards -Z
@export var conveyor_length: float = 9.0
@export var link_spacing: float = 0.7
@export var link_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

@onready var visuals: Node3D = $Visuals/ChainContainer

var chain_links: Array[Node3D] = []
var offset: float = 0.0

func _ready() -> void:
	# constant_linear_velocity is in global coordinates in Godot 4
	constant_linear_velocity = direction.normalized() * speed
	
	if not visuals:
		return
		
	# Spawn visual chain links along local Z
	var num_links = int(conveyor_length / link_spacing) + 2
	
	# Materials for the chain
	var metal_mat = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.18, 0.18, 0.2, 1)
	metal_mat.metallic = 0.95
	metal_mat.roughness = 0.35
	
	# Pre-create meshes to share them among links for performance
	var plate_mesh = BoxMesh.new()
	plate_mesh.size = Vector3(0.04, 0.12, 0.75) # Slight overlap at link_spacing=0.7
	
	var roller_mesh = CylinderMesh.new()
	roller_mesh.top_radius = 0.06
	roller_mesh.bottom_radius = 0.06
	roller_mesh.height = 0.8
	
	var flight_mesh = BoxMesh.new()
	flight_mesh.size = Vector3(0.8, 0.08, 0.08)
	
	for i in range(num_links):
		var link = Node3D.new()
		link.name = "RollerLink_%d" % i
		link.scale = link_scale
		
		# Left plate
		var left_plate = MeshInstance3D.new()
		left_plate.mesh = plate_mesh
		left_plate.material_override = metal_mat
		left_plate.position = Vector3(-0.42, 0.06, 0.0)
		link.add_child(left_plate)
		
		# Right plate
		var right_plate = MeshInstance3D.new()
		right_plate.mesh = plate_mesh
		right_plate.material_override = metal_mat
		right_plate.position = Vector3(0.42, 0.06, 0.0)
		link.add_child(right_plate)
		
		# Center roller
		var roller = MeshInstance3D.new()
		roller.mesh = roller_mesh
		roller.material_override = metal_mat
		roller.rotation_degrees = Vector3(0, 0, 90) # Align cylinder along X-axis
		roller.position = Vector3(0.0, 0.06, 0.0)
		link.add_child(roller)
		
		# Pusher flight bar
		var flight = MeshInstance3D.new()
		flight.mesh = flight_mesh
		flight.material_override = metal_mat
		flight.position = Vector3(0.0, 0.12, 0.0)
		link.add_child(flight)
		
		visuals.add_child(link)
		chain_links.append(link)

func _process(delta: float) -> void:
	# Move the offset to represent flow along the conveyor length
	offset += speed * delta
	if offset > link_spacing:
		offset = fmod(offset, link_spacing)
		
	var half_len = conveyor_length / 2.0
	for i in range(chain_links.size()):
		var z_pos = -half_len + i * link_spacing + offset
		
		# Wrap around logic to loop chain links infinitely
		while z_pos < -half_len:
			z_pos += conveyor_length
		while z_pos > half_len:
			z_pos -= conveyor_length
			
		chain_links[i].position = Vector3(0.0, 0.08, z_pos)
