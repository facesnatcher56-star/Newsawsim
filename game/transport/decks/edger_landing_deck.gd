@tool
class_name EdgerLandingDeck
extends Node3D

## Edger landing deck: visuals only. Local +X entry; signed local Z carry.
## Origin is chain top at the landing lane center. Keep scale at (1,1,1).
##
## The deck has no collision of its own. Boards are carried by collision boxes you
## place in the level; this script just animates the chains and sprocket shafts.

@export_range(0.0, 3.0, 0.05) var chain_speed: float = 0.55
@export var running: bool = true
@export var reverse_direction: bool = false
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.2

const TRACKS: Array[float] = [-2.75, -1.375, 0.0, 1.375, 2.75]
const RUN := 4.0
const RADIUS := 0.145
const LOOP: float = 2.0 * RUN + TAU * RADIUS
const LINK_COUNT: int = 104
const PITCH: float = (2.0 * RUN + TAU * RADIUS) / 104.0

## Current chain speed (eases towards chain_speed when running).
var actual_speed: float = 0.0
var _travel: float = 0.0
var _chains: MultiMeshInstance3D
var _shafts: Array[Node] = []
var _chain_link_nodes: Array[Array] = []


func _ready() -> void:
	_chain_link_nodes.clear()
	var frame_node := get_node_or_null("BlenderFrame")
	if not frame_node:
		frame_node = self
	_shafts = frame_node.find_children("DriveShaft_*", "Node3D", true, false)
	for t in TRACKS.size():
		var track_links: Array[Node3D] = []
		for i in LINK_COUNT:
			var link_node := frame_node.get_node_or_null("Chain_%d_Link_%03d" % [t, i]) as Node3D
			if link_node:
				track_links.append(link_node)
		if not track_links.is_empty():
			_chain_link_nodes.append(track_links)
	var old := get_node_or_null("RuntimeParts")
	if old:
		old.free()
	var parts := Node3D.new()
	parts.name = "RuntimeParts"
	add_child(parts)
	var link_scene := load("res://game/assets/models/edger_landing_deck/roller_chain_link.glb") as PackedScene
	if link_scene:
		var model := link_scene.instantiate()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			_chains = MultiMeshInstance3D.new()
			_chains.name = "AnimatedRollerChains"
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = (meshes[0] as MeshInstance3D).mesh
			mm.instance_count = LINK_COUNT * TRACKS.size()
			_chains.multimesh = mm
			if not _chain_link_nodes.is_empty():
				_chains.visible = false
			parts.add_child(_chains)
			_update_links()
		model.free()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target: float = chain_speed * (-1.0 if reverse_direction else 1.0) if running else 0.0
	actual_speed = move_toward(actual_speed, target, acceleration * delta)
	if is_zero_approx(actual_speed):
		return
	_travel = fposmod(_travel + actual_speed * delta, LOOP)
	for shaft in _shafts:
		(shaft as Node3D).rotate_x(actual_speed * delta / RADIUS)
	_update_links()


func _pin_pos(s: float) -> Vector2:
	var r := fposmod(s, LOOP)
	if r < RUN:
		return Vector2(-0.018, -0.65 + r)
	r -= RUN
	var arc := PI * RADIUS
	if r < arc:
		var ang := r / RADIUS
		return Vector2(-0.163 + RADIUS * cos(ang), 3.35 + RADIUS * sin(ang))
	r -= arc
	if r < RUN:
		return Vector2(-0.308, 3.35 - r)
	r -= RUN
	var ang := PI + r / RADIUS
	return Vector2(-0.163 + RADIUS * cos(ang), -0.65 + RADIUS * sin(ang))

func _update_links() -> void:
	for t in TRACKS.size():
		for i in LINK_COUNT:
			var s0: float = float(i) * PITCH + _travel
			var s1: float = s0 + PITCH
			var p0: Vector2 = _pin_pos(s0)
			var p1: Vector2 = _pin_pos(s1)
			var dy: float = p1.x - p0.x
			var dz: float = p1.y - p0.y
			var angle: float = atan2(-dy, dz)
			var basis: Basis = Basis(Vector3.RIGHT, angle)
			var pos: Vector3 = Vector3(TRACKS[t], p0.x, p0.y)
			if t < _chain_link_nodes.size() and i < _chain_link_nodes[t].size():
				_chain_link_nodes[t][i].transform = Transform3D(basis, pos)
			if is_instance_valid(_chains) and is_instance_valid(_chains.multimesh):
				_chains.multimesh.set_instance_transform(t * LINK_COUNT + i, Transform3D(basis, pos))
