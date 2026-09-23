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
			constant_linear_velocity = global_basis.x.normalized() * speed if _running else Vector3.ZERO

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

# Chain link animation state (populated by _build_chains_and_flights).
# The links of all eleven rails live in one MultiMesh, so the deck only has to
# place its instances — there is no node per link.
var _anim_link_visuals: MultiMeshInstance3D
var _anim_link_slots: PackedFloat32Array = PackedFloat32Array()
var _anim_link_zs: PackedFloat32Array = PackedFloat32Array()
var _anim_link_perp: float = 0.0  # perpendicular recede for chain links
var _rebuild_pending: bool = false
const IDLE_DELAY := 2.0
var _running: bool = false
var _empty_time: float = 0.0
var _surface_sensor: Area3D

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
	constant_linear_velocity = Vector3.ZERO
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
	for child: Node in get_children():
		if Engine.is_editor_hint():
			remove_child(child)
			child.queue_free()
		else:
			child.free()
	_clear_animation_data()
	_surface_sensor = null
	_running = false
	_empty_time = 0.0
	constant_linear_velocity = Vector3.ZERO

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
	_anim_link_visuals = null
	_anim_link_slots = PackedFloat32Array()
	_anim_link_zs = PackedFloat32Array()
	_anim_path_pts.clear()
	_anim_path_al.clear()
	_anim_path_total = 0.0
	_anim_offset = 0.0
	_anim_flight_perp = 0.0
	_anim_link_perp = 0.0



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
	var board_on_surface := false
	if is_instance_valid(_surface_sensor):
		for body in _surface_sensor.get_overlapping_bodies():
			if body is RigidBody3D and body.is_in_group("cut_boards") and not body.is_in_group("cut_slabs") and not body.freeze:
				board_on_surface = true
				break
	if board_on_surface:
		_empty_time = 0.0
		_running = true
	elif _running:
		_empty_time += delta
		if _empty_time >= IDLE_DELAY:
			_running = false
	constant_linear_velocity = global_basis.x.normalized() * speed if _running else Vector3.ZERO
	if not _running or (_anim_flights.is_empty() and not is_instance_valid(_anim_link_visuals)) or _anim_path_total < 0.001:
		return
	_anim_offset = fmod(_anim_offset + speed * delta, _anim_path_total)
	
	# Animate flights (AnimatableBody3D — physically push boards)
	var p := _anim_flight_perp
	for i in _anim_flights.size():
		var fd := fmod(_anim_flight_dists[i] + _anim_offset, _anim_path_total)
		_tween_node_along_path(_anim_flights[i], fd, _anim_flight_zs[i], p)
	
	# Animate the chain links by writing MultiMesh instances directly rather
	# than pushing a Node3D per link through the scene tree every frame.
	_update_chain_links()


## Re-place every chain-link instance along the loop at the current travel.
## All eleven rails follow the same path, so the path is walked once per link
## slot and the result is replicated across the rails.
func _update_chain_links() -> void:
	if not is_instance_valid(_anim_link_visuals):
		return
	var mm: MultiMesh = _anim_link_visuals.multimesh
	if mm == null:
		return
	var index: int = 0
	for slot_index in range(_anim_link_slots.size()):
		var link := _link_transform(slot_index)
		for z in _anim_link_zs:
			mm.set_instance_transform(
				index, Transform3D(link.basis, Vector3(link.origin.x, link.origin.y, float(z))))
			index += 1


## Transform of one link of a rail at the current travel, in machine space and
## before the rail's Z offset is applied. Kept separate from the MultiMesh write
## so the placement itself can be checked without a rendering device.
func _link_transform(slot_index: int) -> Transform3D:
	var dist: float = fposmod(_anim_link_slots[slot_index] + _anim_offset, _anim_path_total)
	var here: Vector2 = _get_path_point_at_dist(dist, _anim_path_pts, _anim_path_al)
	var ahead: Vector2 = _get_path_point_at_dist(dist + 0.001, _anim_path_pts, _anim_path_al)
	var dir: Vector2 = (ahead - here).normalized()
	if dir.length_squared() < 0.0001:
		return Transform3D(Basis(), Vector3(here.x, here.y, 0.0))
	var normal := Vector2(-dir.y, dir.x)
	var recede: float = -_anim_link_perp
	return Transform3D(
		Basis(Vector3.BACK, atan2(dir.y, dir.x)),
		Vector3(here.x + normal.x * recede, here.y + normal.y * recede, 0.0))
