@tool
extends Node3D

@export var deck_length: float = 4.48
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

var _chains: Dictionary = {} # Dictionary of String -> Array[Node3D]
var _travel_distance: float = 0.0
var _conveyor: Node = null

func _ready() -> void:
	_collect_and_sort_chains()
	var parent = get_parent()
	if parent:
		_conveyor = parent.get_parent()

func _process(delta: float) -> void:
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

	# Animate each chain group
	for group_name in _chains:
		var links: Array = _chains[group_name]
		var num_links = links.size()
		if num_links == 0:
			continue
			
		var loop_length = num_links * link_spacing
		var half_loop = loop_length * 0.5
		
		for idx in range(num_links):
			var link = links[idx]
			if not is_instance_valid(link):
				continue
				
			# Calculate nominal initial position of this link along the loop
			# Distributed evenly centered around Z = 0
			var nominal_z = -half_loop + (idx * link_spacing)
			
			# Apply continuous offset and wrap it cleanly within [-half_loop, half_loop]
			var z = fposmod(nominal_z + _travel_distance + half_loop, loop_length) - half_loop
			
			link.position.z = z

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
			# Sort links by name (e.g. LO00, LO01...) to preserve the alternating sequence order
			links.sort_custom(func(a, b): return a.name < b.name)
			_chains[group_name] = links

