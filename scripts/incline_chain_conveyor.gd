extends StaticBody3D

@export var speed: float = 1.4
@export var direction: Vector3 = Vector3(0.0, 0.447, -0.894) # Sloped towards -Z
@export var conveyor_length: float = 9.0
@export var link_spacing: float = 0.7
@export var link_scale: Vector3 = Vector3(0.32, 0.18, 0.55)

@onready var visuals: Node3D = $Visuals/ChainContainer

var chain_links: Array[MeshInstance3D] = []
var offset: float = 0.0

func _ready() -> void:
	# constant_linear_velocity is in global coordinates in Godot 4
	constant_linear_velocity = direction.normalized() * speed
	
	if not visuals:
		return
		
	# Spawn visual chain links along local Z
	var num_links = int(conveyor_length / link_spacing) + 2
	
	# Create a simple Torus mesh for the links
	var link_mesh = TorusMesh.new()
	link_mesh.inner_radius = 0.14
	link_mesh.outer_radius = 0.28
	
	var link_mat = StandardMaterial3D.new()
	link_mat.albedo_color = Color(0.18, 0.18, 0.2, 1)
	link_mat.metallic = 0.95
	link_mat.roughness = 0.35
	
	for i in range(num_links):
		var link = MeshInstance3D.new()
		link.mesh = link_mesh
		link.material_override = link_mat
		link.scale = link_scale
		
		# Alternate link orientations (horizontal vs vertical) to form a chain
		if i % 2 == 0:
			link.rotation_degrees = Vector3(0, 0, 0)
		else:
			link.rotation_degrees = Vector3(0, 90, 90)
			
		visuals.add_child(link)
		chain_links.append(link)

func _process(delta: float) -> void:
	# Move the offset to represent flow along the conveyor length
	# Since local +Z is now the high end (left), the chain links should move towards local +Z!
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
