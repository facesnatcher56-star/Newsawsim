@tool
extends Node3D

@export var deck_length: float = 4.48
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

var _chains: Dictionary = {} # Dictionary of String -> Array[Node3D]
var _rotating_parts: Array[Node3D] = []
var _travel_distance: float = 0.0
var _conveyor: Node = null

func _ready() -> void:
	_collect_and_sort_chains()
	_collect_rotating_parts.call_deferred()
	var parent = get_parent()
	if parent:
		_conveyor = parent.get_parent()
		

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _chains.is_empty():
		return

	var speed = chain_speed
	var dir_z = -1.0

	if _conveyor and "speed" in _conveyor and "direction" in _conveyor:
		speed = _conveyor.speed
		dir_z = _conveyor.direction.z

	var scroll_speed = speed * dir_z
	if is_zero_approx(scroll_speed):
		return

	# Continuously scroll travel distance
	_travel_distance += scroll_speed * delta
	_update_positions(_travel_distance)
	
	if _rotating_parts.is_empty():
		_collect_rotating_parts()
	
	# Rotate sprockets and shafts: scroll_speed / radius matches the chain's angular velocity
	var rot_step = (scroll_speed / 0.20) * delta
	for part in _rotating_parts:
		if is_instance_valid(part):
			part.rotate_object_local(Vector3.UP, rot_step)

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
	
	var C_infeed_z: float = 2.24
	var C_discharge_z: float = -2.24
	
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
		
	var l_basis = Basis(Vector3(1, 0, 0), rot_x)
	return Transform3D(l_basis, Vector3(0.0, y, z))

func _collect_and_sort_chains() -> void:
	_chains.clear()
	var chains_node = find_child("Chains")
	if not chains_node:
		chains_node = self
		
	for container in chains_node.get_children():
		if not container is Node3D:
			continue
			
		var group_name = container.name
		var links: Array[Node3D] = []
		
		for child in container.get_children():
			if child is Node3D and child.name.begins_with("ChainLink"):
				links.append(child)
				
		if not links.is_empty():
			_sort_links_by_name(links)
			_chains[group_name] = links

func _collect_rotating_parts() -> void:
	_rotating_parts.clear()
	var visuals_node = get_parent()
	if not visuals_node:
		visuals_node = self
		
	for child in visuals_node.get_children():
		if child is CSGCylinder3D:
			if child.name.contains("Shaft") or child.name.contains("Sprocket"):
				_rotating_parts.append(child)

func _sort_links_by_name(arr: Array[Node3D]) -> void:
	var n = arr.size()
	for i in range(n):
		for j in range(0, n - i - 1):
			if arr[j].name > arr[j + 1].name:
				var temp = arr[j]
				arr[j] = arr[j + 1]
				arr[j + 1] = temp

