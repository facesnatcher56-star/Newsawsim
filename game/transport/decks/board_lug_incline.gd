@tool
class_name BoardLugIncline
extends Node3D

## board_lug_incline.gd
## Lug-chain incline that lifts boards from the edger landing deck up to the bin sorter.
##
## Boards leave the landing deck broadside (long edge across local X) and travel along
## local +Z, up a 26 degree ramp and over a level crest. Four chains with lugs push them up.
##
## Collision lives in these scene nodes:
##  - InclineBottom / InclineTop: solid floors the boards are dragged across (grip tuner on each).
##  - InclineStartTrigger: a thin zone over the end of the landing deck. The chain stays still
##    until a board touches it (see Wait For Board).
##  - InclineLug: the template lug box. It is copied onto every lug on every chain, and each
##    copy rides with its visible lug. Edit this one box (size, position) to change them all.
## The ramp, rails, legs, chains and lug pictures are drawn by this script from the exports below.
##
## Local origin is the deck-end crossing on the board carrying plane (world 50.803, 0.227,
## 21.647 in the mill). +Z is uphill, +X is across the boards. Keep the scale at (1, 1, 1).

# ── Exported geometry ────────────────────────────────────────────────────────
@export_group("Geometry")
## Ramp angle above horizontal. Lugs do the work, so this can be steep.
@export_range(10.0, 40.0, 0.5) var slope_angle_deg: float = 26.0
## Vertical climb of the carrying plane, ramp foot to crest.
@export_range(0.5, 6.0, 0.005) var rise: float = 2.785
## How round the bend is where the ramp meets the flat top, in metres. Bigger = a longer, gentler curve.
## 0 = a sharp corner. Keep it under about 5 or the curve will not fit the ramp.
@export_range(0.0, 8.0, 0.1) var ramp_blend_radius: float = 3.0
## Length of the level crest that delivers onto the sorter infeed rails.
@export_range(0.2, 6.0, 0.005) var level_length: float = 2.153
## Overall bed width.
@export_range(1.0, 8.0, 0.01) var bed_width: float = 5.56
## Chain lane centres (local X). These four lanes sit midway between the landing
## deck's five chains, so the two independent loops physically interleave rather
## than trying to occupy the same lane at the pickup.
@export var track_x_positions: Array[float] = [-2.0625, -0.6875, 0.6875, 2.0625]
## Distance the inclined carrying run extends backward beneath the landing deck.
## Lugs rise through matching slots over this distance and collect a board while
## it is still supported by the landing deck chains.
@export_range(0.35, 1.5, 0.05) var pickup_overlap: float = 0.80
## Local Y of the mill floor. Legs of the subframe stop here.
@export_range(-4.0, 1.0, 0.01) var floor_y: float = -1.54

# ── Drive ────────────────────────────────────────────────────────────────────
@export_group("Chain and lugs")
## When ticked, the incline stays completely still until a board reaches the start zone
## (the InclineStartTrigger box in this scene, over the end of the landing deck). Once a board
## touches that zone the chain starts. Untick to have the chain run all the time.
@export var wait_for_board: bool = true
## Turns the chain (and the lugs that push the boards) on or off. When switched off they slow to a stop.
@export var running: bool = true
## How fast the chain and its lugs travel, in metres per second. 0.5 is a slow walking pace.
## Bigger numbers = the lugs push boards up the ramp faster.
@export_range(0.0, 3.0, 0.05) var chain_speed: float = 0.45
## Makes the chain run backwards (lugs travel down the ramp instead of up). Tick to reverse.
@export var reverse_direction: bool = false
## How quickly the chain gets up to speed when it starts or slows down when it stops, in metres per second every second.
## Small number = gentle start and stop. Big number = nearly instant.
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.5
## How much the lugs grip the board they are pushing. 0 = like ice (the board slides off the lug).
## Higher = the board is held and pushed firmly.
@export_range(0.0, 5.0, 0.05) var lug_grip: float = 0.5
## The gap between one lug and the next along the chain, in metres. Bigger = fewer lugs, more space for a board between them.
@export_range(0.2, 2.0, 0.01) var lug_pitch: float = 0.74
## How much the empty lower part of the chain sags between the two end wheels (looks only, no effect on the boards).
@export_range(0.05, 1.25, 0.01) var return_sag: float = 0.42

# ── Geometry constants ───────────────────────────────────────────────────────
const SPR := 0.145          # sprocket pitch radius
const LINK_PITCH := 0.24    # chain link spacing along the loop
const LINK_SPAN := 0.10     # gap between the inner faces of a link's side plates
const PLATE_W := 0.014
const PLATE_H := 0.042
const PLATE_D := 0.255  # spans pin-to-pin with overlap at both roller joints
const ROLLER_R := 0.024
## Chain centre line sits this far below the carrying plane, so a link's roller
## tops out exactly flush with the boards and its plates sit just below them.
const CARRIER_DROP := 0.024
const SLOT_GAP := 0.16      # open channel each chain runs in
const STRIP_T := 0.12       # carrying strip thickness
const STRINGER_W := 0.08
const STRINGER_H := 0.18
const LUG_POST_W := 0.11
const LUG_POST_D := 0.11
const LUG_POST_H := 0.24
const LUG_SHOE_H := 0.05
const LUG_SHOE_D := 0.245
const LEG_FOOT_CLEAR := 0.14
const LEG_SPACING := 1.55

# ── Runtime state ────────────────────────────────────────────────────────────
var actual_speed: float = 0.0
var _travel: float = 0.0
var _loop_len: float = 0.0
var _run_len: float = 0.0          # slope + bend + crest, the driven carrying run
var _blend_radius: float = 0.0     # radius of the chain path round the bend (0 = sharp corner)
var _blend_centre := Vector2.ZERO  # centre of that bend, (z, y); the deck surface bends around the same centre
var _a: float = 0.0
var _run: float = 0.0
var _slope_len: float = 0.0
var _p0 := Vector2.ZERO            # deck-end crossing at the landing chain-top plane
var _pickup_point := Vector2.ZERO  # lower tangent beneath the landing deck
var _p1 := Vector2.ZERO            # carrying plane: ramp / crest kink
var _p2 := Vector2.ZERO            # carrying plane: crest end
var _top_centre := Vector2.ZERO
var _bot_centre := Vector2.ZERO
var _segments: Array[Dictionary] = []
var _ret_top := Vector2.ZERO
var _ret_foot := Vector2.ZERO
var _return_start_s: float = 0.0
var _return_len: float = 0.0

var _parts: Node3D
var _stations: Array[AnimatableBody3D] = []
var _station_shapes: Array[Array] = []
var _slot: Array[float] = []
var _slot_on_run: Array[bool] = []
var _sprockets: Array[Node3D] = []
var _shafts: Array[Node3D] = []
var _plates_mm: MultiMeshInstance3D
var _rollers_mm: MultiMeshInstance3D
var _lug_shoes_mm: MultiMeshInstance3D
var _lug_posts_mm: MultiMeshInstance3D
var _lug_braces_mm: MultiMeshInstance3D
var _num_links: int = 0
var _link_spacing: float = LINK_PITCH

var _visual_update_elapsed: float = 0.0
var _park_phase: float = 0.0
var _geometry_stamp: String = ""
var _board_has_arrived: bool = false


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	var trigger := get_node_or_null("InclineStartTrigger") as Area3D
	if trigger != null:
		trigger.body_entered.connect(_on_start_zone_entered)


func _on_start_zone_entered(body: Node3D) -> void:
	if body.is_in_group("cut_boards"):
		_board_has_arrived = true


## Editor: rebuild while an export is being tuned in the inspector.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _stamp() != _geometry_stamp:
		_rebuild()


## Game: advance the chain and lugs every physics tick, so the lugs push boards smoothly.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var commanded_speed: float = -chain_speed if reverse_direction else chain_speed
	var may_run: bool = running and (_board_has_arrived or not wait_for_board)
	var target: float = commanded_speed if may_run else 0.0
	actual_speed = move_toward(actual_speed, target, acceleration * delta)

	var advance := actual_speed * delta
	if is_zero_approx(advance):
		return

	_travel = fposmod(_travel + advance, _loop_len)
	for shaft in _shafts:
		if is_instance_valid(shaft):
			(shaft as Node3D).rotate(Vector3.RIGHT, advance / SPR)
	for sprocket in _sprockets:
		if is_instance_valid(sprocket):
			(sprocket as Node3D).rotate(Vector3.RIGHT, advance / SPR)
	_visual_update_elapsed += delta
	var update_visuals: bool = _visual_update_elapsed >= (1.0 / 30.0)
	if update_visuals:
		_visual_update_elapsed = fmod(_visual_update_elapsed, 1.0 / 30.0)
	for i: int in _stations.size():
		_slot[i] = fposmod(_slot[i] + advance, _loop_len)
		_place_station(i, update_visuals)
	if update_visuals:
		_place_chain_links()


# ─────────────────────────────────────────────────────────────────────────────
#  PATH
# ─────────────────────────────────────────────────────────────────────────────

## The chain loop is closed: carrying ramp and crest, head-sprocket wrap, a
## slack catenary return, and the foot-sprocket wrap. Every position is (z, y)
## in machine-local space and the second value returned is the rotation about X
## that puts a link's local +Z along the direction of travel.
func _build_path() -> void:
	_a = deg_to_rad(slope_angle_deg)
	_run = rise / tan(_a)
	_slope_len = rise / sin(_a)
	_p0 = Vector2(0.0, 0.0)
	_pickup_point = Vector2(-pickup_overlap, -pickup_overlap * tan(_a))
	_p1 = Vector2(_run, rise)
	_p2 = Vector2(_run + level_length, rise)

	var n0 := Vector2(-sin(_a), cos(_a))                 # ramp plane normal
	var d0 := Vector2(cos(_a), sin(_a))                  # ramp uphill direction
	var level := Vector2(1.0, 0.0)                       # crest direction

	# The carrying run begins below and behind the deck-end crossing. Its lugs
	# climb through the deck's pickup slots before the chain reaches local z=0.
	# From there the same straight tangent continues up the exposed incline.
	var pickup_chain := _pickup_point - n0 * CARRIER_DROP
	var a2 := Vector2(_p2.x, rise - CARRIER_DROP)
	var a1 := Vector2(
		pickup_chain.x + (a2.y - pickup_chain.y) / sin(_a) * cos(_a),
		a2.y)

	_top_centre = a2 + Vector2(0.0, -SPR)
	_bot_centre = _pickup_point - n0 * (CARRIER_DROP + SPR)

	_ret_top = a2 + Vector2(0.0, -2.0 * SPR)
	_ret_foot = _pickup_point - n0 * (CARRIER_DROP + 2.0 * SPR)

	# The ramp meets the flat top through a round bend instead of a sharp corner.
	# The bend's tangent length is radius * tan(half the slope angle); clamp it so it
	# always fits inside both the ramp and the flat top.
	var ramp_chain_len: float = a1.distance_to(pickup_chain)
	var level_chain_len: float = a2.x - a1.x
	var tangent_len: float = 0.0
	_blend_radius = 0.0
	if ramp_blend_radius > 0.05:
		tangent_len = ramp_blend_radius * tan(_a * 0.5)
		tangent_len = minf(tangent_len, minf(ramp_chain_len * 0.5, level_chain_len * 0.8))
		_blend_radius = tangent_len / tan(_a * 0.5)
		_blend_centre = Vector2(a1.x + tangent_len, a1.y - _blend_radius)

	_segments = [
		{"kind": "line", "start": pickup_chain, "dir": d0, "len": ramp_chain_len - tangent_len},
	]
	if tangent_len > 0.0:
		_segments.append({"kind": "arc", "centre": _blend_centre, "radius": _blend_radius,
			"angle": PI * 0.5 + _a, "sweep": -_a, "len": _blend_radius * _a})
	_segments.append({"kind": "line", "start": a1 + level * tangent_len, "dir": level, "len": level_chain_len - tangent_len})
	_run_len = 0.0
	for segment: Dictionary in _segments:
		_run_len += float(segment["len"])
	_segments.append({"kind": "arc", "centre": _top_centre, "radius": SPR, "angle": PI * 0.5, "sweep": -PI, "len": PI * SPR})
	_return_start_s = _run_len + PI * SPR

	# The unloaded lower strand is deliberately not stretched parallel to the
	# bed. A sampled catenary gives it real visual weight while preserving an
	# arc-length path for rigid, evenly spaced roller links in either direction.
	_return_len = 0.0
	var previous: Vector2 = _ret_top
	const RETURN_STEPS := 32
	for step: int in range(1, RETURN_STEPS + 1):
		var t: float = float(step) / float(RETURN_STEPS)
		var point: Vector2 = _return_curve_point(t)
		var distance: float = previous.distance_to(point)
		_segments.append({"kind": "line", "start": previous, "dir": (point - previous) / distance, "len": distance})
		_return_len += distance
		previous = point

	_segments.append({"kind": "arc", "centre": _bot_centre, "radius": SPR,
		"angle": atan2(_ret_foot.y - _bot_centre.y, _ret_foot.x - _bot_centre.x), "sweep": -PI, "len": PI * SPR})

	_loop_len = 0.0
	for segment: Dictionary in _segments:
		_loop_len += float(segment["len"])


func _return_curve_point(t: float) -> Vector2:
	var catenary_k: float = 1.35
	var shape: float = (cosh(catenary_k) - cosh(catenary_k * (2.0 * t - 1.0))) / (cosh(catenary_k) - 1.0)
	return _ret_top.lerp(_ret_foot, t) + Vector2(0.0, -return_sag * shape)


## Sample the loop at arc length s. Returns [Vector2(z, y), rotation about X].
func _sample(s: float) -> Array:
	s = fposmod(s, _loop_len)
	for segment in _segments:
		var seg_len: float = segment["len"]
		if s <= seg_len:
			if segment["kind"] == "line":
				var dir: Vector2 = segment["dir"]
				var point: Vector2 = (segment["start"] as Vector2) + dir * s
				return [point, atan2(-dir.y, dir.x)]
			var centre: Vector2 = segment["centre"]
			var radius: float = segment["radius"]
			var spin: float = signf(segment["sweep"])
			var theta: float = float(segment["angle"]) + spin * (s / radius)
			var on_arc: Vector2 = centre + radius * Vector2(cos(theta), sin(theta))
			var tangent: Vector2 = spin * Vector2(-sin(theta), cos(theta))
			return [on_arc, atan2(-tangent.y, tangent.x)]
		s -= seg_len
	return [_p0, 0.0]


# ─────────────────────────────────────────────────────────────────────────────
#  BUILD
# ─────────────────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	_geometry_stamp = _stamp()
	_build_path()

	var old := get_node_or_null("RuntimeParts")
	if old != null:
		old.free()

	_parts = Node3D.new()
	_parts.name = "RuntimeParts"
	add_child(_parts)

	_stations.clear()
	_station_shapes.clear()
	_slot.clear()
	_slot_on_run.clear()
	_sprockets.clear()
	_shafts.clear()

	_build_bed()
	_build_chain_runs()
	_build_drive()
	_build_stations()
	_place_chain_links()


func _stamp() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(slope_angle_deg), str(rise), str(level_length), str(bed_width),
		str(track_x_positions), str(pickup_overlap), str(floor_y), str(return_sag), str(ramp_blend_radius)]


func _material(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _build_bed() -> void:
	var frame := Node3D.new()
	frame.name = "Frame"
	_parts.add_child(frame)

	var steel := _material(Color(0.20, 0.21, 0.23), 0.85, 0.45)
	var deck := _material(Color(0.19, 0.38, 0.22), 0.62, 0.52)

	var n0 := Vector2(-sin(_a), cos(_a))
	var half_w := bed_width * 0.5

	# ── Carrying surface: strips with an open channel for each chain lane, so
	# the chains show in their slots and their rollers end flush with the boards.
	var edges: Array[float] = []
	for track_x in track_x_positions:
		edges.append(track_x - SLOT_GAP * 0.5)
		edges.append(track_x + SLOT_GAP * 0.5)
	var left := -half_w
	var strip_index := 0
	for i in range(0, edges.size(), 2):
		var strip_w := edges[i] - left
		if strip_w > 0.001:
			_add_strip(frame, deck, left + strip_w * 0.5, strip_w, "DeckStrip_%d" % strip_index)
			strip_index += 1
		left = edges[i + 1]
	if half_w - left > 0.001:
		_add_strip(frame, deck, left + (half_w - left) * 0.5, half_w - left, "DeckStrip_%d" % strip_index)

	# ── Guide rails on the outer edges, proud of the boards. The ramp rail starts
	# just uphill of the bottom tangent so its square-cut foot does not run back
	# into the landing deck's end sprockets.
	# ── Subframe: stringers under the strips, cross ties, legs to the floor.
	var ramp_drop := STRIP_T / cos(_a)
	for side: float in [-1.0, 1.0]:
		var sx := side * (half_w - STRINGER_W * 0.5 - 0.03)
		var stringer := (_p0 + _p1) * 0.5 - n0 * (ramp_drop + STRINGER_H * 0.5)
		_mesh_box(frame, Vector3(STRINGER_W, STRINGER_H, _slope_len),
			Vector3(sx, stringer.y, stringer.x), -_a, steel, "Stringer")
		_mesh_box(frame, Vector3(STRINGER_W, STRINGER_H, level_length),
			Vector3(sx, rise - STRIP_T - STRINGER_H * 0.5, _p1.x + level_length * 0.5), 0.0, steel, "Stringer")

	var ties := maxi(2, int(ceil((_run + level_length) / 1.1)))
	for i in range(ties + 1):
		var z := minf(float(i) * ((_run + level_length) / float(ties)), _run + level_length)
		var y := _plane_y(z) - _bed_drop_at(z) - STRINGER_H * 0.55
		_mesh_box(frame, Vector3(bed_width + 0.06, STRINGER_H * 0.5, 0.05),
			Vector3(0.0, y, z), 0.0, steel, "Tie")

	for z in _leg_positions():
		var under := _plane_y(z) - _bed_drop_at(z) - STRINGER_H
		var height := under - floor_y
		if height <= 0.05:
			continue
		for side: float in [-1.0, 1.0]:
			var lx := side * (half_w - 0.22)
			_mesh_box(frame, Vector3(0.12, height, 0.12),
				Vector3(lx, floor_y + height * 0.5, z), 0.0, steel, "Leg")
		var brace := under - 0.9
		if brace > floor_y + 0.2:
			_mesh_box(frame, Vector3(bed_width - 0.3, 0.07, 0.07), Vector3(0.0, brace, z), 0.0, steel, "Brace")


## Local Y of the carrying plane at local Z.
func _plane_y(z: float) -> float:
	if z <= _run:
		return z * tan(_a)
	return rise


## Vertical drop from the carrying plane to the underside of the deck at local Z.
func _bed_drop_at(z: float) -> float:
	return STRIP_T / cos(_a) if z <= _run else STRIP_T


## Leg stations along the bed. The first stands just uphill of the bottom
## tangent: the landing deck's frame already carries that station, and a leg
## there would pass straight through its end cross member.
func _leg_positions() -> Array[float]:
	var out: Array[float] = []
	var total := _run + level_length
	var span := maxf(total - LEG_FOOT_CLEAR, 0.1)
	var steps := maxi(2, int(round(span / LEG_SPACING)))
	for i in range(steps + 1):
		out.append(minf(LEG_FOOT_CLEAR + float(i) * (span / float(steps)), total))
	return out


## Tangent length of the bend on the deck surface: where the straight ramp ends and the curve begins.
func _blend_plane_tangent() -> float:
	if _blend_radius <= 0.0:
		return 0.0
	return (_blend_radius + CARRIER_DROP) * tan(_a * 0.5)


## One carrying strip (visual): straight ramp, round bend, flat crest. Top face on the carrying plane.
func _add_strip(frame: Node3D, mat: Material, centre_x: float, width: float, hint: String) -> void:
	var n0 := Vector2(-sin(_a), cos(_a))
	var d0 := Vector2(cos(_a), sin(_a))
	var plane_t: float = _blend_plane_tangent()
	var ramp_len: float = _slope_len - plane_t
	var ramp_centre := _p0 + d0 * (ramp_len * 0.5) - n0 * (STRIP_T * 0.5)
	_mesh_box(frame, Vector3(width, STRIP_T, ramp_len),
		Vector3(centre_x, ramp_centre.y, ramp_centre.x), -_a, mat, hint)
	_add_bend(frame, mat, width, STRIP_T, -STRIP_T * 0.5, centre_x, hint)
	var crest_start_z: float = _p1.x + plane_t
	var crest_len: float = _p2.x - crest_start_z
	_mesh_box(frame, Vector3(width, STRIP_T, crest_len),
		Vector3(centre_x, rise - STRIP_T * 0.5, crest_start_z + crest_len * 0.5), 0.0, mat, hint)


## The round bend between ramp and crest, built from thin slices that turn a little each.
## `offset` is how far above (+) or below (-) the carrying surface the slab's middle sits.
func _add_bend(parent: Node3D, mat: Material, width: float, thickness: float, offset: float, centre_x: float, hint: String) -> void:
	if _blend_radius <= 0.0:
		return
	var slices: int = maxi(4, int(ceil(rad_to_deg(_a) / 2.0)))
	var step: float = _a / float(slices)
	var radius: float = _blend_radius + CARRIER_DROP + offset
	for i in slices:
		var heading: float = _a - (float(i) + 0.5) * step
		var on_arc := _blend_centre + radius * Vector2(cos(PI * 0.5 + heading), sin(PI * 0.5 + heading))
		# A touch longer than the chord so neighbouring slices overlap with no gap.
		var slice_len: float = 2.0 * radius * sin(step * 0.5) * 1.06
		_mesh_box(parent, Vector3(width, thickness, slice_len),
			Vector3(centre_x, on_arc.y, on_arc.x), -heading, mat, hint)


func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, rot_x: float, mat: Material, hint: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = hint
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = rot_x
	parent.add_child(mi)
	return mi


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN LINKS
# ─────────────────────────────────────────────────────────────────────────────

func _build_chain_runs() -> void:
	# Use an integer count and derive the exact spacing from the final loop. This
	# closes the roller chain cleanly with no doubled links or oversized seam.
	_num_links = maxi(8, int(round(_loop_len / LINK_PITCH)))
	_link_spacing = _loop_len / float(_num_links)
	var mat := _material(Color(0.21, 0.21, 0.24), 0.93, 0.30)
	var tracks := track_x_positions.size()

	_plates_mm = MultiMeshInstance3D.new()
	_plates_mm.name = "ChainPlates"
	var plates := MultiMesh.new()
	plates.transform_format = MultiMesh.TRANSFORM_3D
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(PLATE_W, PLATE_H, PLATE_D)
	plates.mesh = plate_mesh
	plates.instance_count = _num_links * tracks * 2
	_plates_mm.multimesh = plates
	_plates_mm.material_override = mat
	_parts.add_child(_plates_mm)

	_rollers_mm = MultiMeshInstance3D.new()
	_rollers_mm.name = "ChainRollers"
	var rollers := MultiMesh.new()
	rollers.transform_format = MultiMesh.TRANSFORM_3D
	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = ROLLER_R
	roller_mesh.bottom_radius = ROLLER_R
	roller_mesh.height = LINK_SPAN + PLATE_W * 2.0 + 0.01
	roller_mesh.radial_segments = 6
	rollers.mesh = roller_mesh
	rollers.instance_count = _num_links * tracks
	_rollers_mm.multimesh = rollers
	_rollers_mm.material_override = mat
	_parts.add_child(_rollers_mm)


func _place_chain_links() -> void:
	if not is_instance_valid(_plates_mm) or not is_instance_valid(_rollers_mm):
		return
	var plate_index := 0
	var roller_index := 0
	for track_x: float in track_x_positions:
		for j in _num_links:
			var slot: float = float(j) * _link_spacing + _travel
			var sample: Array = _sample(slot)
			var point: Vector2 = sample[0]

			# A roller sits at every pin. Each pair of side plates bridges this pin
			# to the next one; centering plates on a pin left visible disconnected
			# gaps. Alternating inner/outer offsets overlap at the articulated joint.
			for side: float in [-1.0, 1.0]:
				_plates_mm.multimesh.set_instance_transform(
					plate_index, _chain_plate_transform(slot, track_x, j, side))
				plate_index += 1

			var roller_link := Transform3D(
				Basis(Vector3.RIGHT, float(sample[1])),
				Vector3(track_x, point.y, point.x))
			_rollers_mm.multimesh.set_instance_transform(
				roller_index,
				roller_link * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
			roller_index += 1


func _chain_plate_transform(slot: float, track_x: float, link_index: int, side: float) -> Transform3D:
	var point: Vector2 = _sample(slot)[0]
	var next_point: Vector2 = _sample(slot + _link_spacing)[0]
	var chord: Vector2 = next_point - point
	var midpoint: Vector2 = (point + next_point) * 0.5
	var plate_rotation: float = atan2(-chord.y, chord.x)
	var inner_x: float = LINK_SPAN * 0.5 + PLATE_W * 0.5
	var lateral_offset: float = inner_x + (PLATE_W * 1.15 if link_index % 2 == 1 else 0.0)
	return Transform3D(
		Basis(Vector3.RIGHT, plate_rotation),
		Vector3(track_x + side * lateral_offset, midpoint.y, midpoint.x))


# ─────────────────────────────────────────────────────────────────────────────
#  DRIVE
# ─────────────────────────────────────────────────────────────────────────────

func _build_drive() -> void:
	var steel := _material(Color(0.28, 0.26, 0.24), 0.90, 0.38)
	var hub_mat := _material(Color(0.35, 0.32, 0.28), 0.88, 0.42)
	var half_w := bed_width * 0.5

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.055
	shaft_mesh.bottom_radius = 0.055
	shaft_mesh.height = bed_width + 0.34
	var sprocket_mesh := CylinderMesh.new()
	sprocket_mesh.top_radius = SPR
	sprocket_mesh.bottom_radius = SPR
	sprocket_mesh.height = 0.045
	sprocket_mesh.radial_segments = 10
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.055
	hub_mesh.bottom_radius = 0.055
	hub_mesh.height = 0.075
	hub_mesh.radial_segments = 8

	for centre: Vector2 in [_bot_centre, _top_centre]:
		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft"
		shaft.mesh = shaft_mesh
		shaft.material_override = hub_mat
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, centre.y, centre.x)
		_parts.add_child(shaft)
		_shafts.append(shaft)

		for track_x: float in track_x_positions:
			var root := Node3D.new()
			root.name = "Sprocket"
			root.rotation_degrees.z = 90.0
			root.position = Vector3(track_x, centre.y, centre.x)
			_parts.add_child(root)
			var rim := MeshInstance3D.new()
			rim.mesh = sprocket_mesh
			rim.material_override = steel
			root.add_child(rim)
			var hub := MeshInstance3D.new()
			hub.mesh = hub_mesh
			hub.material_override = hub_mat
			root.add_child(hub)
			_sprockets.append(root)

	# Bottom drive enclosure sits beneath the landing deck at the recessed foot.
	# The chain and lugs leave it uphill through the open pickup slots.
	var housing := _material(Color(0.24, 0.25, 0.27), 0.72, 0.55)
	_mesh_box(_parts, Vector3(bed_width - 0.12, 0.66, 0.78),
		Vector3(0.0, _bot_centre.y - 0.24, _bot_centre.x), 0.0, housing, "DriveEnclosure")
	_mesh_box(_parts, Vector3(bed_width - 0.12, 0.30, 0.55),
		Vector3(0.0, rise - STRIP_T - 0.15, _p2.x - 0.16), 0.0, housing, "HeadBearingBlock")
	# Primary drive, hung on the near side at the foot where the line is open.
	_mesh_box(_parts, Vector3(0.45, 0.60, 0.70),
		Vector3(-half_w - 0.28, -0.30, 0.95), 0.0, housing, "Gearbox")
	_mesh_box(_parts, Vector3(0.38, 0.38, 0.50),
		Vector3(-half_w - 0.28, 0.16, 0.95), 0.0, housing, "Motor")


# ─────────────────────────────────────────────────────────────────────────────
#  LUGS
# ─────────────────────────────────────────────────────────────────────────────

## One node per lug station carrying a pusher on every chain lane (visual only).
## Stations follow the same closed loop as the roller links; their lugs stay visible
## on the return as well.
func _build_stations() -> void:
	var count: int = maxi(2, int(round(_loop_len / maxf(lug_pitch, 0.05))))
	var pitch: float = _loop_len / float(count)
	_park_phase = 0.0
	_travel = _park_phase
	var steel: StandardMaterial3D = _material(Color(0.11, 0.10, 0.09), 0.82, 0.58)
	var instance_count: int = count * track_x_positions.size()

	# All fabricated lug pieces share three MultiMeshes (one draw each instead of
	# hundreds of moving render objects).
	_lug_shoes_mm = _make_lug_multimesh(
		"LugShoes", Vector3(LUG_POST_W * 1.35, LUG_SHOE_H, LUG_SHOE_D),
		instance_count, steel)
	_lug_posts_mm = _make_lug_multimesh(
		"LugPosts", Vector3(LUG_POST_W, LUG_POST_H, LUG_POST_D),
		instance_count, steel)
	_lug_braces_mm = _make_lug_multimesh(
		"LugBraces", Vector3(0.022, 0.20, 0.05),
		instance_count * 2, steel)

	# The lug collision box you placed in the scene ("InclineLug") is the template.
	# It was placed over the first lug, so its position relative to that lug is copied
	# onto every lug on every chain lane.
	var lug_material := PhysicsMaterial.new()
	lug_material.friction = lug_grip
	lug_material.bounce = 0.0
	var template := get_node_or_null("InclineLug") as CollisionShape3D
	var lug_shape: Shape3D = null
	var offset := Transform3D(Basis(), Vector3(0.0, CARRIER_DROP + LUG_POST_H * 0.5, LUG_POST_D * 0.5))
	if template != null and template.shape != null:
		lug_shape = template.shape
		var first_lug: Array = _sample(0.0)
		var first_point: Vector2 = first_lug[0]
		var first_frame := Transform3D(Basis(Vector3.RIGHT, float(first_lug[1])), Vector3(0.0, first_point.y, first_point.x))
		offset = first_frame.affine_inverse() * template.transform
	else:
		var default_box := BoxShape3D.new()
		default_box.size = Vector3(LUG_POST_W, LUG_POST_H, LUG_POST_D)
		lug_shape = default_box

	for i: int in count:
		var station := AnimatableBody3D.new()
		station.name = "LugStation_%02d" % i
		station.sync_to_physics = true
		station.physics_material_override = lug_material
		_parts.add_child(station)

		var shapes: Array[CollisionShape3D] = []
		for track_x: float in track_x_positions:
			var post := CollisionShape3D.new()
			post.shape = lug_shape
			post.transform = Transform3D(offset.basis, Vector3(track_x, offset.origin.y, offset.origin.z))
			station.add_child(post)
			shapes.append(post)

		_stations.append(station)
		_station_shapes.append(shapes)
		_slot.append(float(i) * pitch + _travel)
		_slot_on_run.append(false)
		_place_station(i)


func _make_lug_multimesh(
		instance_name: String,
		size: Vector3,
		instance_count: int,
		material: Material
) -> MultiMeshInstance3D:
	var visual := MultiMeshInstance3D.new()
	visual.name = instance_name
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = size
	multimesh.mesh = mesh
	multimesh.instance_count = instance_count
	visual.multimesh = multimesh
	visual.material_override = material
	_parts.add_child(visual)
	return visual


func _place_station(index: int, update_visuals: bool = true) -> void:
	var station: AnimatableBody3D = _stations[index]
	var s: float = _slot[index]
	var sample: Array = _sample(s)
	var point: Vector2 = sample[0]
	var station_transform := Transform3D(Basis(Vector3.RIGHT, float(sample[1])), Vector3(0.0, point.y, point.x))
	station.transform = station_transform
	# Draw the lugs from the position just calculated, not from station.transform: a physics
	# body does not report its new position until the next physics step, which left every
	# lug drawn at the origin when the machine loaded.
	if update_visuals:
		_place_station_visuals(index, station_transform)

	# Lugs stay visible all the way round the chain, but only the ones on the
	# carrying run (the ramp and crest) can push a board.
	var on_run: bool = s < _run_len
	if _slot_on_run[index] != on_run:
		_slot_on_run[index] = on_run
		for shape in _station_shapes[index]:
			(shape as CollisionShape3D).disabled = not on_run


func _place_station_visuals(index: int, station_transform: Transform3D) -> void:
	if not is_instance_valid(_lug_shoes_mm):
		return
	var tracks: int = track_x_positions.size()
	for track_index: int in tracks:
		var track_x: float = track_x_positions[track_index]
		var instance_index: int = index * tracks + track_index
		var shoe_local := Transform3D(Basis(), Vector3(
			track_x, CARRIER_DROP - LUG_SHOE_H * 0.5, 0.04))
		var post_local := Transform3D(Basis(), Vector3(
			track_x, CARRIER_DROP + LUG_POST_H * 0.5, LUG_POST_D * 0.5))
		_lug_shoes_mm.multimesh.set_instance_transform(instance_index, station_transform * shoe_local)
		_lug_posts_mm.multimesh.set_instance_transform(instance_index, station_transform * post_local)
		for brace_index: int in 2:
			var brace_x: float = -0.032 if brace_index == 0 else 0.032
			var brace_local := Transform3D(
				Basis.from_euler(Vector3(deg_to_rad(30.0), 0.0, 0.0)),
				Vector3(track_x + brace_x, CARRIER_DROP + 0.115, -0.055))
			_lug_braces_mm.multimesh.set_instance_transform(
				instance_index * 2 + brace_index, station_transform * brace_local)
