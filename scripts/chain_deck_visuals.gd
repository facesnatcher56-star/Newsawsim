extends Node3D

@export var deck_length: float = 4.2
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

var _links: Array[Node3D] = []
var _base_z: Dictionary = {}
var _travel_offset: float = 0.0

func _ready() -> void:
	_collect_links(self)

func _process(delta: float) -> void:
	if _links.is_empty():
		return

	_travel_offset = fposmod(_travel_offset + chain_speed * delta, link_spacing)
	var half_length := deck_length * 0.5

	for link in _links:
		if not is_instance_valid(link):
			continue
		var z := float(_base_z.get(link, link.position.z)) - _travel_offset
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
