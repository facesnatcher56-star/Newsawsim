extends Node3D

@export var deck_length: float = 4.2
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

var _links: Array[Node3D] = []
var _base_z: Dictionary = {}
var _travel_offset: float = 0.0
var _conveyor: Node = null

func _ready() -> void:
	_collect_links(self)
	_conveyor = get_parent().get_parent()

func _process(delta: float) -> void:
	if _links.is_empty():
		return

	var speed = chain_speed
	var dir_z = -1.0 # default/fallback to original negative direction

	if _conveyor and "speed" in _conveyor and "direction" in _conveyor:
		speed = _conveyor.speed
		dir_z = _conveyor.direction.z

	var scroll_speed = speed * dir_z
	if is_zero_approx(scroll_speed):
		return

	_travel_offset = fposmod(_travel_offset + abs(scroll_speed) * delta, link_spacing)
	var half_length := deck_length * 0.5
	var scroll_dir = sign(scroll_speed)

	for link in _links:
		if not is_instance_valid(link):
			continue
		var base_z: float = _base_z.get(link, link.position.z)
		var z = base_z + scroll_dir * _travel_offset
		if scroll_dir >= 0.0:
			if z > half_length:
				z -= deck_length
		else:
			if z < -half_length:
				z += deck_length
		link.position.z = z

func _collect_links(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D:
			if child.name.begins_with("ChainLink"):
				_links.append(child)
				_base_z[child] = child.position.z
			_collect_links(child)

