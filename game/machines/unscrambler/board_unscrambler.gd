## board_unscrambler.gd
## Steel board unscrambler / singulator.
## Side profile: entry flat → V-notch → upward sweep → exit flat platform.
## Two steel side plates are extruded from this profile with structural
## cross members between them.
@tool
extends StaticBody3D

const UnscramblerFrameBuilder := preload("res://game/machines/unscrambler/builders/unscrambler_frame_builder.gd")
const UnscramblerChainBuilder := preload("res://game/machines/unscrambler/builders/unscrambler_chain_builder.gd")

## Width of the machine (board-length direction, Z axis).
@export var machine_width: float = 5.7:
	set(v): machine_width = v; _rebuild()
## Thickness of the steel side plates (visual).
@export var plate_thickness: float = 0.018:
	set(v): plate_thickness = v; _rebuild()
## Overall scale factor.
@export var profile_scale: float = 1.0:
	set(v): profile_scale = v; _rebuild()
@export var chain_spacing: float = 0.5:
	set(v): chain_spacing = v; _rebuild()
@export var set_gap: float = 0.1:
	set(v): set_gap = v; _rebuild()
@export var flight_spacing: float = 1.4:
	set(v): flight_spacing = v; _rebuild()
@export var flight_height: float = 0.1:
	set(v): flight_height = v; _rebuild()
@export var chain_diameter: float = 0.048:
	set(v): chain_diameter = v; _rebuild()
@export_range(0.01, 0.2, 0.005) var flight_diameter: float = 0.05:
	set(v): flight_diameter = v; _rebuild()
@export var chain_overhang: float = 0.35:
	set(v): chain_overhang = v; _rebuild()

## Speed of the conveyor (m/s). Boards are pushed in the +X direction.
@export var speed: float = 3.0:
	set(v):
		speed = v
		if is_inside_tree():
			constant_linear_velocity = CONVEYOR_DIR * speed

const CONVEYOR_DIR := Vector3.RIGHT

const MAT_STEEL_COLOR  := Color(0.28, 0.30, 0.33)
const MAT_FLOOR_COLOR  := Color(0.22, 0.24, 0.26)
const _CHAIN_GROUP := &"_unscrambler_chains"

var _mat_plate: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_chain: StandardMaterial3D
var _mat_flight: StandardMaterial3D

# Flight animation state (populated by _build_chains_and_flights)
var _anim_path_pts: Array[Vector2] = []
var _anim_path_al: Array[float] = []
var _anim_path_total: float = 0.0
var _anim_offset: float = 0.0
var _anim_flights: Array[AnimatableBody3D] = []
var _anim_flight_dists: Array[float] = []
var _anim_flight_zs: Array[float] = []
var _anim_flight_perp: float = 0.0  # perpendicular offset from path (scaled_flight_h)

# Chain link animation state (populated by _build_chains_and_flights)
var _anim_links: Array[Node3D] = []
var _anim_link_dists: Array[float] = []
var _anim_link_zs: Array[float] = []
var _anim_link_recede: float = 0.0  # perpendicular recede for chain links
var _rebuild_pending: bool = false

# ── Profile definition ───────────────────────────────────────────────────────
# Points describe the OUTER (top) edge of one side plate.
# X = horizontal (left = entry, right = exit), Y = vertical.
# A closed polygon is formed by appending the INNER (bottom) edge in reverse.
const _OUTER: Array[Vector2] = [
	Vector2(-1.50,  0.00),  # entry far left
	Vector2(-0.60,  0.00),  # before V-notch
	Vector2(-0.33, -0.28),  # V apex
	Vector2(-0.04,  0.02),  # back up from notch
	Vector2( 0.22,  0.36),  # curve begins
	Vector2( 0.50,  0.72),  # curve mid
	Vector2( 0.78,  0.98),  # curve upper
	Vector2( 1.00,  1.10),  # entry to exit flat
	Vector2( 2.50,  1.10),  # exit far right
]
# Plate thickness in 2D = offset perpendicular to each segment.
# Approximate by offsetting uniformly downward along Y; close enough for
# a fabricated steel plate with consistent thickness.
const _INNER_OFFSETS: Array[Vector2] = [
	Vector2(-1.50, -0.16),
	Vector2(-0.60, -0.16),
	Vector2(-0.33, -0.44),
	Vector2(-0.04, -0.15),
	Vector2( 0.22,  0.19),
	Vector2( 0.50,  0.55),
	Vector2( 0.78,  0.81),
	Vector2( 1.00,  0.93),
	Vector2( 2.50,  0.93),
]

func _ready() -> void:
	constant_linear_velocity = CONVEYOR_DIR * speed
	if Engine.is_editor_hint():
		_rebuild()
	else:
		_do_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_do_rebuild()
		return
	if _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	_do_rebuild()

func _do_rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()
	_clear_animation_data()

	constant_linear_velocity = CONVEYOR_DIR * speed

	_mat_plate = StandardMaterial3D.new()
	_mat_plate.albedo_color = MAT_STEEL_COLOR
	_mat_plate.metallic = 0.85
	_mat_plate.roughness = 0.30

	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = MAT_FLOOR_COLOR
	_mat_floor.metallic = 0.80
	_mat_floor.roughness = 0.40

	_mat_chain = StandardMaterial3D.new()
	_mat_chain.albedo_color = Color(0.18, 0.19, 0.21)
	_mat_chain.metallic = 0.90
	_mat_chain.roughness = 0.35

	_mat_flight = StandardMaterial3D.new()
	_mat_flight.albedo_color = Color(0.85, 0.55, 0.05)
	_mat_flight.metallic = 0.60
	_mat_flight.roughness = 0.40

	var frame_builder := UnscramblerFrameBuilder.new(self)
	frame_builder.build_side_plates()
	frame_builder.build_cross_members()
	frame_builder.build_working_surface()
	UnscramblerChainBuilder.new(self).build_chains_and_flights()

func _clear_animation_data() -> void:
	_anim_flights.clear()
	_anim_flight_dists.clear()
	_anim_flight_zs.clear()
	_anim_links.clear()
	_anim_link_dists.clear()
	_anim_link_zs.clear()
	_anim_path_pts.clear()
	_anim_path_al.clear()
	_anim_path_total = 0.0
	_anim_offset = 0.0
	_anim_flight_perp = 0.0
	_anim_link_recede = 0.0



func _get_path_point_at_dist(dist: float, pts: Array[Vector2], pts_al: Array[float]) -> Vector2:
	var total := pts_al[pts_al.size() - 1]
	dist = fmod(dist, total)
	if dist < 0.0:
		dist += total
	var idx := 0
	while idx < pts_al.size() - 2 and pts_al[idx + 1] < dist:
		idx += 1
	var t := (dist - pts_al[idx]) / (pts_al[idx + 1] - pts_al[idx]) if pts_al[idx + 1] > pts_al[idx] else 0.0
	return pts[idx].lerp(pts[idx + 1], clampf(t, 0.0, 1.0))

func _tween_node_along_path(node: Node3D, dist: float, z: float, perp: float) -> void:
	var pos_here := _get_path_point_at_dist(dist, _anim_path_pts, _anim_path_al)
	var pos_ahead := _get_path_point_at_dist(dist + 0.001, _anim_path_pts, _anim_path_al)
	var dir := (pos_ahead - pos_here).normalized()
	if dir.length_squared() < 0.0001:
		return
	var n := Vector2(-dir.y, dir.x)
	var ang := atan2(dir.y, dir.x)
	node.position = Vector3(pos_here.x + n.x * perp, pos_here.y + n.y * perp, z)
	node.rotation = Vector3(0.0, 0.0, ang)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if (_anim_flights.is_empty() and _anim_links.is_empty()) or _anim_path_total < 0.001:
		return
	_anim_offset = fmod(_anim_offset + speed * delta, _anim_path_total)
	
	# Animate flights (AnimatableBody3D — physically push boards)
	var p := _anim_flight_perp
	for i in _anim_flights.size():
		var fd := fmod(_anim_flight_dists[i] + _anim_offset, _anim_path_total)
		_tween_node_along_path(_anim_flights[i], fd, _anim_flight_zs[i], p)
	
	# Animate chain links (Node3D — visual only, follows path with recede offset)
	var rc := _anim_link_recede
	for i in _anim_links.size():
		var fd := fmod(_anim_link_dists[i] + _anim_offset, _anim_path_total)
		_tween_node_along_path(_anim_links[i], fd, _anim_link_zs[i], -rc)
