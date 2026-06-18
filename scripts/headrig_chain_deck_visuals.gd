@tool
extends Node3D

@export var deck_length: float = 2.0
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

var _chains: Dictionary = {} # Dictionary of String -> Array[Node3D]
var _travel_distance: float = 0.0
var _conveyor: Node = null

func _ready() -> void:
	_spawn_chains()
	var parent = get_parent()
	if parent:
		_conveyor = parent.get_parent()
		
	if Engine.is_editor_hint():
		_update_positions(0.0)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _chains.is_empty():
		return

	var speed = chain_speed
	var dir_z = 1.0

	if _conveyor and "speed" in _conveyor and "direction" in _conveyor:
		speed = _conveyor.speed
		dir_z = _conveyor.direction.z

	var scroll_speed = speed * dir_z
	if is_zero_approx(scroll_speed):
		return

	# Continuously scroll travel distance
	_travel_distance += scroll_speed * delta
	_update_positions(_travel_distance)

func _update_positions(travel_dist: float) -> void:
	for group_name in _chains:
		var links: Array = _chains[group_name]
		var num_links = links.size()
		if num_links == 0:
			continue
			
		var loop_length = num_links * link_spacing
		
		for idx in range(num_links):
			var link = links[idx]
			if not is_instance_valid(link):
				continue
				
			# Nominal distance of this link along the loop
			var nominal_d = idx * link_spacing
			
			# Calculate wrapped transform along the Y-Z loop path
			var local_t = _get_loop_transform(nominal_d + travel_dist, loop_length)
			
			link.transform.basis = local_t.basis
			link.position.y = local_t.origin.y
			link.position.z = local_t.origin.z

func _get_loop_transform(d: float, loop_length: float) -> Transform3D:
	d = fposmod(d, loop_length)
	
	var R: float = 0.20
	var pi_R: float = PI * R
	var L: float = (loop_length - 2.0 * pi_R) * 0.5
	
	# Sprocket center points are at L/2 and -L/2
	var C_infeed_z: float = L * 0.5
	var C_discharge_z: float = -L * 0.5
	
	var y: float = 1.15
	var z: float = 0.0
	var rot_x: float = 0.0
	
	if d < L:
		# Top Run (moving towards positive Z)
		z = C_discharge_z + d
		y = 1.15
		rot_x = 0.0
	elif d < L + pi_R:
		# Infeed sprocket wrap
		var theta = (d - L) / R
		z = C_infeed_z + R * sin(theta)
		y = 0.95 + R * cos(theta)
		rot_x = theta - 2.0 * PI
	elif d < 2.0 * L + pi_R:
		# Bottom Run (moving towards negative Z)
		var d_bottom = d - (L + pi_R)
		z = C_infeed_z - d_bottom
		y = 0.75
		rot_x = -PI
	else:
		# Discharge sprocket wrap
		var theta = (d - (2.0 * L + pi_R)) / R
		z = C_discharge_z - R * sin(theta)
		y = 0.95 - R * cos(theta)
		rot_x = theta - PI
		
	var basis = Basis(Vector3(1, 0, 0), rot_x)
	return Transform3D(basis, Vector3(0.0, y, z))

func _spawn_chains() -> void:
	# Clean up any existing children first
	for child in get_children():
		child.queue_free()
	_chains.clear()
	
	var runs = {
		"LeftOuterLinks": -0.9,
		"LeftInnerLinks": -0.3,
		"RightInnerLinks": 0.3,
		"RightOuterLinks": 0.9
	}
	
	var chain_mat = StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.3, 0.32, 0.35, 1)
	chain_mat.metallic = 0.95
	chain_mat.roughness = 0.35
	
	# Pre-create shared meshes
	var sidebar_mesh = BoxMesh.new()
	sidebar_mesh.size = Vector3(0.02, 0.08, 0.36)
	sidebar_mesh.material = chain_mat
	
	var pin_mesh = BoxMesh.new()
	pin_mesh.size = Vector3(0.20, 0.04, 0.04)
	pin_mesh.material = chain_mat
	
	var barrel_mesh = BoxMesh.new()
	barrel_mesh.size = Vector3(0.12, 0.06, 0.20)
	barrel_mesh.material = chain_mat
	
	var R: float = 0.20
	var loop_len_target = 2.0 * deck_length + 2.0 * PI * R
	var num_links = int(round(loop_len_target / link_spacing))
	if num_links % 2 != 0:
		num_links += 1
		
	for run_name in runs:
		var x_offset = runs[run_name]
		var run_node = Node3D.new()
		run_node.name = run_name
		add_child(run_node)
		
		var links: Array[Node3D] = []
		
		for i in range(num_links):
			var link = Node3D.new()
			link.name = "ChainLink_%02d" % i
			run_node.add_child(link)
			links.append(link)
			
			link.position.x = x_offset
			
			if i % 2 == 0:
				var l_sidebar = MeshInstance3D.new()
				l_sidebar.mesh = sidebar_mesh
				l_sidebar.position = Vector3(-0.10, 0.04, 0)
				link.add_child(l_sidebar)
				
				var r_sidebar = MeshInstance3D.new()
				r_sidebar.mesh = sidebar_mesh
				r_sidebar.position = Vector3(0.10, 0.04, 0)
				link.add_child(r_sidebar)
				
				var f_pin = MeshInstance3D.new()
				f_pin.mesh = pin_mesh
				f_pin.position = Vector3(0, 0.04, -0.16)
				link.add_child(f_pin)
				
				var b_pin = MeshInstance3D.new()
				b_pin.mesh = pin_mesh
				b_pin.position = Vector3(0, 0.04, 0.16)
				link.add_child(b_pin)
			else:
				var l_sidebar = MeshInstance3D.new()
				l_sidebar.mesh = sidebar_mesh
				l_sidebar.position = Vector3(-0.07, 0.04, 0)
				link.add_child(l_sidebar)
				
				var r_sidebar = MeshInstance3D.new()
				r_sidebar.mesh = sidebar_mesh
				r_sidebar.position = Vector3(0.07, 0.04, 0)
				link.add_child(r_sidebar)
				
				var barrel = MeshInstance3D.new()
				barrel.mesh = barrel_mesh
				barrel.position = Vector3(0, 0.04, 0)
				link.add_child(barrel)
				
		_chains[run_name] = links
