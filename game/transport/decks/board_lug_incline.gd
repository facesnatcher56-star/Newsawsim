@tool
class_name BoardLugIncline
extends Node3D

## board_lug_incline.gd
## Lug-chain incline that lifts edger boards from the landing chain deck's
## discharge up to the bin sorter's infeed table.
##
## Boards leave the edger landing deck broadside - long axis across local X,
## travelling along local +Z - and that is the attitude the sorter's infeed
## expects, so the incline only has to raise them. Four lug chains, laterally
## interleaved between the landing deck's five chains, rise from beneath that
## deck through pickup slots before continuing up a straight ramp and level crest. The lugs divide each chain into pockets,
## which is what keeps the boards apart: a board is pushed uphill by the lug
## behind it and, on the 26 degree ramp, slides back onto that lug whenever the
## chain stops, so it can never run down into the board below.
##
## The crest is level and its carrying plane is flush with the sorter's infeed
## rails, so the hand-over happens at the height the sorter's scanner zone
## expects. The sorter starts tracking the same dynamic rigid board once its
## centre enters that zone; physical sorter lugs then take over the push.
##
## Local origin is the deck-end crossing on the board carrying plane at world
## (50.803027, 0.2271245, 21.647045) in the mill prototype. The actual lower
## tangent is pickup_overlap metres back and below this point, under the landing
## deck. +Z is uphill, +X is across the boards.
## Keep the node scale at (1, 1, 1); the whole machine is built from the exports
## at runtime, so a level placement is all the scene has to provide.

# ── Exported geometry ────────────────────────────────────────────────────────
@export_group("Geometry")
## Ramp angle above horizontal. Lugs do the work, so this can be steep.
@export_range(10.0, 40.0, 0.5) var slope_angle_deg: float = 26.0
## Vertical climb of the carrying plane, ramp foot to crest.
@export_range(0.5, 6.0, 0.005) var rise: float = 2.785
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
@export_group("Drive")
## Chain speed in metres per second. Keep it a little under the sorter's
## infeed speed so a board released at the crest pulls clear of its lug.
@export_range(0.0, 3.0, 0.05) var chain_speed: float = 0.45
## Reverse the entire chain loop. Speed remains a positive, directly adjustable
## magnitude so operator controls do not need to rewrite it to change direction.
@export var reverse_direction: bool = false
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.5
@export var running: bool = true
## Stop input for a downstream interlock.
@export var external_stop: bool = false
## Distance between lug pockets along the chain loop.
@export_range(0.2, 2.0, 0.01) var lug_pitch: float = 0.74
## Vertical slack at the centre of the unloaded lower return. This creates the
## natural hanging catenary visible between the head and foot sprockets.
@export_range(0.05, 1.25, 0.01) var return_sag: float = 0.42

# ── Line interlock ───────────────────────────────────────────────────────────
@export_group("Line interlock")
## Bin sorter to hand off to. Left empty, the first node able to answer
## can_accept_board() in the running scene is used.
@export var sorter_path: NodePath
## Landing deck feeding this incline. Left empty, a sibling named
## landing_deck* is used. It is held whenever this machine is holding boards.
@export var upstream_deck_path: NodePath
## Depth of the crest zone watched for boards waiting to be accepted.
@export_range(0.2, 3.0, 0.05) var hold_zone_length: float = 1.0

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
const RAIL_W := 0.06
const RAIL_TOP := 0.22      # guide rail height above the carrying plane
const HOLD_DOWN_CLEARANCE := 0.065
const HOLD_DOWN_HEIGHT := 0.05
const HOLD_DOWN_WIDTH := 0.08
const HOLD_DOWN_X: Array[float] = [-1.375, 0.0, 1.375]
const STRINGER_W := 0.08
const STRINGER_H := 0.18
const LUG_POST_W := 0.11
const LUG_POST_D := 0.11
const LUG_POST_H := 0.24
const LUG_SHOE_H := 0.05
const LUG_SHOE_D := 0.245
const RAIL_FOOT_CLEAR := 0.09
const LEG_FOOT_CLEAR := 0.14
const LEG_SPACING := 1.55
## Boards narrower than this are assumed to be half this wide along the chain.
const MIN_BOARD_WIDTH: float = 0.12
## Extra clearance beyond a board's thickness before a lug may meet it.
const PICKUP_PUSH_MARGIN: float = 0.02
## Slack allowed below the emergence point before a lug counts as standing out of
## its slot, so a stopping chain cannot coast a lug up into a board's path.
const LUG_PICKUP_CLEARANCE: float = 0.15
## Top of the pickup corridor: past this a lug is climbing the exposed ramp.
const PICKUP_CORRIDOR_TOP: float = 0.20
## How far short of the corridor a delivered board is stopped while the corridor
## is cleared of lugs. Long enough that a board braking at deck acceleration comes
## to rest outside the corridor.
const PICKUP_APPROACH: float = 0.45
## Slack added to the corridor when spacing the lugs, so the gap between two lugs
## is comfortably longer than the corridor a board has to cross.
const PICKUP_GAP_MARGIN: float = 0.15

# ── Runtime state ────────────────────────────────────────────────────────────
var actual_speed: float = 0.0
var _travel: float = 0.0
var _loop_len: float = 0.0
var _run_len: float = 0.0          # slope + crest, the driven carrying run
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
var _slot_visible: Array[bool] = []
var _sprockets: Array[Node3D] = []
var _shafts: Array[Node3D] = []
var _plates_mm: MultiMeshInstance3D
var _rollers_mm: MultiMeshInstance3D
var _lug_shoes_mm: MultiMeshInstance3D
var _lug_posts_mm: MultiMeshInstance3D
var _lug_braces_mm: MultiMeshInstance3D
var _num_links: int = 0
var _link_spacing: float = LINK_PITCH

var _incline_area: Area3D
var _discharge_area: Area3D
var _sorter: Node
var _upstream: Node3D
var _link_retries: int = 120
var _visual_update_elapsed: float = 0.0
var _holding: bool = false
var _pickup_held: bool = false
var _pickup_handed_over: bool = false
var _deck_held: bool = false
var _pickup_committed: bool = false
var _park_phase: float = 0.0
var _parking_braking: bool = false
var _geometry_stamp: String = ""


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	_resolve_line_links()


## Line partners live beside this machine in the level, so retry for a couple of
## seconds in case they are added to the tree after this node is.
func _resolve_line_links() -> void:
	if _sorter == null or not is_instance_valid(_sorter):
		_sorter = _resolve_sorter()
	if not is_instance_valid(_upstream):
		_upstream = _resolve_upstream()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# Rebuild while an export is being tuned in the inspector.
	if _stamp() != _geometry_stamp:
		_rebuild()


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

	_segments = [
		{"kind": "line", "start": pickup_chain, "dir": d0, "len": a1.distance_to(pickup_chain)},
		{"kind": "line", "start": a1, "dir": level, "len": a2.x - a1.x},
		{"kind": "arc", "centre": _top_centre, "radius": SPR, "angle": PI * 0.5, "sweep": -PI, "len": PI * SPR},
	]
	_run_len = float(_segments[0]["len"]) + float(_segments[1]["len"])
	_return_start_s = _run_len + float(_segments[2]["len"])

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
	_slot_visible.clear()
	_sprockets.clear()
	_shafts.clear()

	_build_bed()
	_build_chain_runs()
	_build_drive()
	_build_stations()
	_build_zones()
	_place_chain_links()


func _stamp() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(slope_angle_deg), str(rise), str(level_length), str(bed_width),
		str(track_x_positions), str(pickup_overlap), str(floor_y), str(return_sag)]


func _material(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _build_bed() -> void:
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.20
	pm.rough = false
	frame.physics_material_override = pm
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
	var d0 := Vector2(cos(_a), sin(_a))
	var rail_mid := (_p0 + _p1) * 0.5 + n0 * ((RAIL_TOP - STRIP_T) * 0.5) + d0 * (RAIL_FOOT_CLEAR * 0.5)
	var rail_len := _slope_len - RAIL_FOOT_CLEAR
	for side: float in [-1.0, 1.0]:
		var rx := side * (half_w - RAIL_W * 0.5)
		_mesh_box(frame, Vector3(RAIL_W, RAIL_TOP + STRIP_T, rail_len),
			Vector3(rx, rail_mid.y, rail_mid.x), -_a, steel, "Rail")
		_col_box(frame, Vector3(RAIL_W, RAIL_TOP + STRIP_T, rail_len),
			Vector3(rx, rail_mid.y, rail_mid.x), -_a)
		_mesh_box(frame, Vector3(RAIL_W, RAIL_TOP + STRIP_T, level_length),
			Vector3(rx, rise + (RAIL_TOP - STRIP_T) * 0.5, _p1.x + level_length * 0.5), 0.0, steel, "Rail")
		_col_box(frame, Vector3(RAIL_W, RAIL_TOP + STRIP_T, level_length),
			Vector3(rx, rise + (RAIL_TOP - STRIP_T) * 0.5, _p1.x + level_length * 0.5), 0.0)

	# ── Low hold-down skids keep thin boards flat while the lugs push their rear
	# edge uphill. They sit between lug lanes, with 27 mm clearance over a 2-inch
	# board, so they provide containment only when a nose or tail starts to lift.
	# Without them a real rigid board can rotate onto its 286 mm edge at the crest.
	var hold_start: Vector2 = Vector2(0.80, _plane_y(0.80))
	var hold_ramp_length: float = hold_start.distance_to(_p1)
	var lead_start: Vector2 = Vector2(0.0, 0.35)
	var lead_end: Vector2 = hold_start + Vector2(0.0, HOLD_DOWN_CLEARANCE)
	var lead_delta: Vector2 = lead_end - lead_start
	var lead_angle: float = atan2(lead_delta.y, lead_delta.x)
	var lead_normal: Vector2 = Vector2(-sin(lead_angle), cos(lead_angle))
	var lead_mid: Vector2 = (lead_start + lead_end) * 0.5 + lead_normal * HOLD_DOWN_HEIGHT * 0.5
	for hold_x: float in HOLD_DOWN_X:
		# A high, shallow entry converges onto the low skid. It accepts a board
		# arriving unsettled from the pickup, then physically presses it flat.
		_mesh_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, lead_delta.length()),
			Vector3(hold_x, lead_mid.y, lead_mid.x), -lead_angle, steel, "HoldDownLeadIn")
		_col_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, lead_delta.length()),
			Vector3(hold_x, lead_mid.y, lead_mid.x), -lead_angle)
		var ramp_hold_mid: Vector2 = (hold_start + _p1) * 0.5 + n0 * (HOLD_DOWN_CLEARANCE + HOLD_DOWN_HEIGHT * 0.5)
		_mesh_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, hold_ramp_length),
			Vector3(hold_x, ramp_hold_mid.y, ramp_hold_mid.x), -_a, steel, "HoldDownSkid")
		_col_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, hold_ramp_length),
			Vector3(hold_x, ramp_hold_mid.y, ramp_hold_mid.x), -_a)
		_mesh_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, level_length),
			Vector3(hold_x, rise + HOLD_DOWN_CLEARANCE + HOLD_DOWN_HEIGHT * 0.5, _p1.x + level_length * 0.5), 0.0, steel, "HoldDownSkid")
		_col_box(frame, Vector3(HOLD_DOWN_WIDTH, HOLD_DOWN_HEIGHT, level_length),
			Vector3(hold_x, rise + HOLD_DOWN_CLEARANCE + HOLD_DOWN_HEIGHT * 0.5, _p1.x + level_length * 0.5), 0.0)

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
			_col_box(frame, Vector3(0.12, height, 0.12), Vector3(lx, floor_y + height * 0.5, z), 0.0)
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


## One carrying strip: a mesh and a collision box, top face on the carrying plane.
func _add_strip(frame: StaticBody3D, mat: Material, centre_x: float, width: float, hint: String) -> void:
	var mid := (_p0 + _p1) * 0.5
	var n0 := Vector2(-sin(_a), cos(_a))
	var ramp_centre := mid - n0 * (STRIP_T * 0.5)
	_mesh_box(frame, Vector3(width, STRIP_T, _slope_len),
		Vector3(centre_x, ramp_centre.y, ramp_centre.x), -_a, mat, hint)
	_col_box(frame, Vector3(width, STRIP_T, _slope_len),
		Vector3(centre_x, ramp_centre.y, ramp_centre.x), -_a)
	_mesh_box(frame, Vector3(width, STRIP_T, level_length),
		Vector3(centre_x, rise - STRIP_T * 0.5, _p1.x + level_length * 0.5), 0.0, mat, hint)
	_col_box(frame, Vector3(width, STRIP_T, level_length),
		Vector3(centre_x, rise - STRIP_T * 0.5, _p1.x + level_length * 0.5), 0.0)


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


func _col_box(parent: Node3D, size: Vector3, pos: Vector3, rot_x: float) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	col.rotation.x = rot_x
	parent.add_child(col)
	return col


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

## One AnimatableBody3D per lug station carrying a pusher on every chain lane.
## Stations follow the same closed loop as the roller links. Their fabricated
## lugs remain visible on the return, but collision is enabled only on the run.
func _build_stations() -> void:
	var count: int = maxi(2, int(round(_loop_len / maxf(lug_pitch, 0.05))))
	# The pickup is only ever handed to a board at an instant when no lug is out of
	# its slot in the corridor, which cannot happen unless the lugs are spaced
	# wider than the corridor itself. Wide enough, and there is always a gap in the
	# chain long enough to carry a board across bare deck.
	var corridor_span: float = PICKUP_CORRIDOR_TOP - _lug_emergence_z() + LUG_PICKUP_CLEARANCE
	count = maxi(2, mini(count, int(_loop_len / (corridor_span + PICKUP_GAP_MARGIN))))
	var pitch: float = _loop_len / float(count)
	# Phase the empty machine at build time: the next lug waits just below its
	# slot, while the following lug is beyond the board's pickup corridor. The
	# landing deck can feed a board straight in without waiting for a moving lug.
	var park_z: float = _lug_emergence_z() - LUG_PICKUP_CLEARANCE - 0.04
	_park_phase = (park_z - _pickup_point.x) / cos(_a)
	_travel = _park_phase
	var steel: StandardMaterial3D = _material(Color(0.11, 0.10, 0.09), 0.82, 0.58)
	var instance_count: int = count * track_x_positions.size()

	# All fabricated lug pieces share three MultiMeshes. The old implementation
	# created four MeshInstance3D children per lane per station (about 480 moving
	# render objects), which multiplied again in every directional-shadow cascade.
	_lug_shoes_mm = _make_lug_multimesh(
		"LugShoes", Vector3(LUG_POST_W * 1.35, LUG_SHOE_H, LUG_SHOE_D),
		instance_count, steel)
	_lug_posts_mm = _make_lug_multimesh(
		"LugPosts", Vector3(LUG_POST_W, LUG_POST_H, LUG_POST_D),
		instance_count, steel)
	_lug_braces_mm = _make_lug_multimesh(
		"LugBraces", Vector3(0.022, 0.20, 0.05),
		instance_count * 2, steel)

	for i: int in count:
		var station := AnimatableBody3D.new()
		station.name = "LugStation_%02d" % i
		station.sync_to_physics = true
		_parts.add_child(station)

		var shapes: Array[CollisionShape3D] = []
		for track_x: float in track_x_positions:
			var post := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(LUG_POST_W, LUG_POST_H, LUG_POST_D)
			post.shape = box
			post.position = Vector3(track_x, CARRIER_DROP + LUG_POST_H * 0.5, LUG_POST_D * 0.5)
			station.add_child(post)
			shapes.append(post)

		_stations.append(station)
		_station_shapes.append(shapes)
		_slot.append(float(i) * pitch + _travel)
		_slot_visible.append(false)
		# Start hidden: only stations on the carrying run may push.
		_set_station_shapes(i, false)
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
	station.transform = Transform3D(Basis(Vector3.RIGHT, float(sample[1])), Vector3(0.0, point.y, point.x))
	if update_visuals:
		_place_station_visuals(index, station.transform)

	# Lugs stay visibly bolted to the roller chain around both sprockets and along
	# the sagging return. Only their collision is disabled off the carrying run.
	var on_carrying_run: bool = s < _run_len
	if _slot_visible[index] != on_carrying_run:
		_slot_visible[index] = on_carrying_run
		_set_station_shapes(index, on_carrying_run)


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


func _set_station_shapes(index: int, enabled: bool) -> void:
	for shape in _station_shapes[index]:
		(shape as CollisionShape3D).disabled = not enabled


# ─────────────────────────────────────────────────────────────────────────────
#  ZONES
# ─────────────────────────────────────────────────────────────────────────────

func _build_zones() -> void:
	var n0 := Vector2(-sin(_a), cos(_a))
	var ramp_mid := (_p0 + _p1) * 0.5 + n0 * 0.30
	_incline_area = _make_area("OnInclineArea")
	_add_area_box(_incline_area, Vector3(bed_width + 0.5, 0.8, _slope_len),
		Vector3(0.0, ramp_mid.y, ramp_mid.x), -_a)
	_add_area_box(_incline_area, Vector3(bed_width + 0.5, 0.8, level_length),
		Vector3(0.0, rise + 0.30, _p1.x + level_length * 0.5), 0.0)

	_discharge_area = _make_area("DischargeZone")
	var discharge_centre := _p2.x - hold_zone_length * 0.5
	_add_area_box(_discharge_area, Vector3(bed_width + 0.5, 0.8, hold_zone_length + 0.2),
		Vector3(0.0, rise + 0.30, discharge_centre), 0.0)


func _make_area(area_name: String) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1
	_parts.add_child(area)
	return area


func _add_area_box(area: Area3D, size: Vector3, pos: Vector3, rot_x: float) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	col.rotation.x = rot_x
	area.add_child(col)


# ─────────────────────────────────────────────────────────────────────────────
#  RUN
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _link_retries > 0:
		_link_retries -= 1
		_resolve_line_links()

	_holding = _hold_required()
	_scan_pickup()

	# The normal pickup is already parked before the board arrives. The deck
	# continues feeding it until its trailing edge is ready for a full-face push;
	# only sorter backpressure (or an unexpected unparked pickup) stops the deck.
	if is_instance_valid(_upstream):
		_upstream.set("external_stop", _holding or _deck_held)
		_upstream.set("downstream_takeover", _pickup_handed_over)

	var commanded_speed: float = -chain_speed if reverse_direction else chain_speed
	var target: float = commanded_speed if (running and not external_stop and not _holding and not _pickup_held) else 0.0
	# After the last board leaves the carrying run, index the empty chain to
	# the same clear pickup gap it starts with. Begin braking before the index
	# mark: unlike waiting for the next board, this happens while the deck is
	# empty, so a delivery normally never has to wait for lugs to clear.
	if _board_on_run() or reverse_direction:
		_parking_braking = false
	elif target > 0.0:
		var pitch: float = _loop_len / float(_stations.size())
		var phase: float = fposmod(_slot[0] - _park_phase, pitch)
		var to_mark: float = fposmod(pitch - phase, pitch)
		var mark_error: float = minf(to_mark, pitch - to_mark)
		var stopping_distance: float = actual_speed * actual_speed / (2.0 * maxf(acceleration, 0.01))
		if not _parking_braking and to_mark <= stopping_distance + maxf(actual_speed, 0.0) * delta + 0.01:
			_parking_braking = true
		if _parking_braking:
			if absf(actual_speed) < 0.01 and (mark_error > 0.09 or not _pickup_lug_positions().is_empty()):
				_parking_braking = false # missed the window; index to the next one
			else:
				target = 0.0
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


## Hold the chain while the landing deck is still carrying a board across the
## slots this machine's lugs rise through, so that no lug ever climbs out of a
## slot underneath a board.
##
## A lug's post is 0.24 m tall, so it leaves its slot where the recessed run is
## that far below the deck's carrying plane. A board lying on the deck that
## straddles that point gets levered up on the lug and tips over - the board ends
## up on its edge instead of riding the ramp flat. Waiting until the board has
## either reached the end of the deck chain run or come to rest up-slope of the
## slot crossing means every lug that appears under the deck is behind its board,
## where it pushes the trailing face as the deck hands over. A fixed-width hold
## here is what turns the deck's delivery into a clean hand-over.
## Incline-local Z where a lug's post has climbed out of its slot and reached the
## landing deck's carrying plane. Behind this the post is still below the deck.
func _lug_emergence_z() -> float:
	return (CARRIER_DROP * (1.0 / cos(_a) - 1.0) - LUG_POST_H) / tan(_a)


## Incline-local Z a board's trailing edge has to reach before this chain may run.
##
## A lug only pushes a board properly once its post stands a full board thickness
## proud of the deck, so the contact is a face push over the whole edge. A lug that
## reaches the trailing edge earlier touches the board's bottom corner with a push
## angled up the ramp, which levers the tail up and tips the board onto its edge.
func _pushable_trailing_z(thickness: float) -> float:
	return _lug_emergence_z() + (thickness + PICKUP_PUSH_MARGIN) / tan(_a)


## Chain height at which a lug's post has climbed out of its slot and reached the
## landing deck's carrying plane.
func _lug_emergence_y() -> float:
	return -(LUG_POST_H + CARRIER_DROP)


## Incline-local Z of every lug post standing out of its slot in the pickup
## corridor, where it can meet a board lying on the landing deck.
##
## Height matters as much as position: the unloaded return strand runs back under
## the bed at the same Z values as the carrying run, so a Z test alone counts the
## whole return as lugs blocking the corridor and the pickup then waits forever.
func _pickup_lug_positions() -> Array[float]:
	var out: Array[float] = []
	var lowest_z: float = _lug_emergence_z() - LUG_PICKUP_CLEARANCE
	var lowest_y: float = _lug_emergence_y() - LUG_PICKUP_CLEARANCE * tan(_a)
	for station: AnimatableBody3D in _stations:
		if not is_instance_valid(station):
			continue
		var at: Vector3 = station.position
		if at.y < lowest_y:
			continue
		if at.z < lowest_z or at.z > PICKUP_CORRIDOR_TOP:
			continue
		out.append(at.z)
	return out


## A board past the pickup still needs its lugs all the way up the hill. Do not
## index the empty-chain parking mark until the last board has left the crest.
func _board_on_run() -> bool:
	if _pickup_handed_over:
		return true
	for node: Node in get_tree().get_nodes_in_group("cut_boards"):
		var body: RigidBody3D = node as RigidBody3D
		if not is_instance_valid(body) or body.freeze:
			continue
		var at: Vector3 = to_local(body.global_position)
		if absf(at.x) < bed_width * 0.5 + 0.5 and at.z >= 0.0 and at.z <= _p2.x + 0.15:
			if absf(at.y - _plane_y(clampf(at.z, 0.0, _p2.x))) < 0.8:
				return true
	return false


func _scan_pickup() -> void:
	_pickup_held = false
	_pickup_handed_over = false
	_deck_held = false
	var awaiting := false
	var approaching := false
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var body := node as RigidBody3D
		if not is_instance_valid(body) or body.freeze:
			continue
		var local: Vector3 = to_local(body.global_position)
		if local.z < _pickup_point.x - PICKUP_APPROACH or local.z > PICKUP_CORRIDOR_TOP:
			continue
		if local.y < _pickup_point.y - 0.25 or local.y > 0.70:
			continue
		var width: float = maxf(float(body.get("board_width")), MIN_BOARD_WIDTH)
		var thickness: float = float(body.get("board_thickness"))
		if local.z < _pickup_point.x:
			approaching = true
		elif local.z - width * 0.5 >= _pushable_trailing_z(thickness):
			_pickup_handed_over = true
		else:
			awaiting = true

	if _pickup_handed_over:
		# Far enough up-slope for a lug to meet the trailing face squarely: the
		# chain runs, and the deck lets go so the two cannot shear the board.
		_pickup_committed = false
		return
	if not awaiting and not approaching:
		# Nothing is crossing the slots, so the chain is free to run and any lug
		# standing in the corridor climbs out of it.
		_pickup_committed = false
		return

	# The corridor is only ever as clear as it is at the instant the board is let
	# in, so that decision is latched: a chain stopping can coast a lug back into
	# the zone the check watches, and re-deciding every frame would then start the
	# chain again under a board that is already crossing.
	if not _pickup_committed:
		if not _pickup_lug_positions().is_empty():
			# Only the chain can clear a lug that is part way out of its slot, and a
			# lug left standing is a ramp a leading edge rides up or a lever under a
			# tail. The board waits on the deck, short of the corridor, because a
			# board stopped inside it would be swept by the very lugs clearing it.
			_deck_held = true
			return
		_pickup_committed = true

	_pickup_held = true


## Hold the chain while a board is waiting on the crest and the sorter cannot
## take it, rather than pushing it off the end onto the infeed bed.
func _hold_required() -> bool:
	if _sorter == null or not is_instance_valid(_sorter):
		return false
	if _discharge_area == null:
		return false
	for body in _discharge_area.get_overlapping_bodies():
		if not _is_board(body):
			continue
		# The sorter refuses duplicate acceptance for a board it already owns.
		# That is not backpressure: keeping the incline parked in that case
		# strands the board at the crest while the sorter's idle lugs spin up.
		if _sorter.has_method("is_tracking_board") and bool(_sorter.call("is_tracking_board", body)):
			continue
		if not bool(_sorter.call("can_accept_board", body)):
			return true
	return false


static func _is_board(node: Node) -> bool:
	if not (node is RigidBody3D):
		return false
	var body := node as RigidBody3D
	return body.is_in_group("cut_boards") and not body.freeze


func boards_on_incline() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if _incline_area == null:
		return out
	for body in _incline_area.get_overlapping_bodies():
		if _is_board(body) and not out.has(body as RigidBody3D):
			out.append(body as RigidBody3D)
	return out


func is_holding() -> bool:
	return _holding


## True while the chain is waiting for the landing deck to finish carrying a
## board across this machine's pickup slots.
func is_pickup_held() -> bool:
	return _pickup_held


func _resolve_sorter() -> Node:
	if sorter_path != NodePath():
		var named := get_node_or_null(sorter_path)
		if named != null and named.has_method("can_accept_board"):
			return named
	for node in get_tree().root.find_children("*", "", true, false):
		if node.has_method("can_accept_board"):
			return node
	return null


func _resolve_upstream() -> Node3D:
	if upstream_deck_path != NodePath():
		return get_node_or_null(upstream_deck_path) as Node3D
	for node in get_tree().root.find_children("*", "", true, false):
		if node is Node3D and String(node.name).begins_with("landing_deck"):
			return node as Node3D
	return null
