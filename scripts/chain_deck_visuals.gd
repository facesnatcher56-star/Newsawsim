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
		
	if Engine.is_editor_hint():
		# Position links once in their default layout in the editor
		_update_positions(0.0)

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

func _update_positions(travel_dist: float) -> void:
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
			
			# Apply offset and wrap it cleanly within [-half_loop, half_loop]
			var z = fposmod(nominal_z + travel_dist + half_loop, loop_length) - half_loop
			
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
			# Safe bubble-sort to avoid Engine lambda sort_custom crash bugs in editor thread
			_sort_links_by_name(links)
			_chains[group_name] = links

func _sort_links_by_name(arr: Array[Node3D]) -> void:
	var n = arr.size()
	for i in range(n):
		for j in range(0, n - i - 1):
			if arr[j].name > arr[j + 1].name:
				var temp = arr[j]
				arr[j] = arr[j + 1]
				arr[j + 1] = temp

