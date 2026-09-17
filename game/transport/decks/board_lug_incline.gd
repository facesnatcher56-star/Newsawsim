@tool
class_name BoardLugIncline
extends Node3D

## board_lug_incline.gd
## Lug-chain incline that lifts edger boards from the landing chain deck's
## discharge up to the bin sorter's infeed table.
##
## Boards leave the edger landing deck broadside - long axis across local X,
## travelling along local +Z - and that is the attitude the sorter's infeed
## expects, so the incline only has to raise them. Five lug chains run up a
## straight ramp and over a level crest. The lugs divide each chain into pockets,
## which is what keeps the boards apart: a board is pushed uphill by the lug
## behind it and, on the 26 degree ramp, slides back onto that lug whenever the
## chain stops, so it can never run down into the board below.
##
## The crest is level and its carrying plane is flush with the sorter's infeed
## rails, so the hand-over happens at the height the sorter's scanner zone
## expects. The sorter freezes and takes the board as soon as the board centre
## enters that zone, which the lugs push well clear of the ramp.
##
## Local origin is the board carrying plane at the bottom tangent, which is the
## point the landing deck's chain tops end at (world 50.803027, 0.2271245,
## 21.647045 in the mill prototype). +Z is uphill, +X is across the boards.
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
## Chain lane centres (local X). Five lanes carry a 16 ft board safely.
@export var track_x_positions: Array[float] = [-2.64, -1.32, 0.0, 1.32, 2.64]
## Local Y of the mill floor. Legs of the subframe stop here.
@export_range(-4.0, 1.0, 0.01) var floor_y: float = -1.54

# ── Drive ────────────────────────────────────────────────────────────────────
@export_group("Drive")
## Chain speed in metres per second. Keep it a little under the sorter's
## infeed speed so a board released at the crest pulls clear of its lug.
@export_range(0.05, 3.0, 0.05) var chain_speed: float = 0.45
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.5
@export var running: bool = true
## Stop input for a downstream interlock.
@export var external_stop: bool = false
## Distance between lug pockets along the chain loop.
@export_range(0.2, 2.0, 0.01) var lug_pitch: float = 0.74

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
const PLATE_D := 0.195
const ROLLER_R := 0.024
## Chain centre line sits this far below the carrying plane, so a link's roller
## tops out exactly flush with the boards and its plates sit just below them.
const CARRIER_DROP := 0.024
const SLOT_GAP := 0.16      # open channel each chain runs in
const STRIP_T := 0.12       # carrying strip thickness
const RAIL_W := 0.06
const RAIL_TOP := 0.22      # guide rail height above the carrying plane
const STRINGER_W := 0.08
const STRINGER_H := 0.18
const LUG_POST_W := 0.11
const LUG_POST_D := 0.11
const LUG_POST_H := 0.24
const LUG_SHOE_H := 0.05
const LUG_SHOE_D := 0.245
const HIDDEN_DROP := 0.72   # how far below the bed lugs ride on the return
const RAIL_FOOT_CLEAR := 0.09
const LEG_FOOT_CLEAR := 0.14
const LEG_SPACING := 1.55

# ── Runtime state ────────────────────────────────────────────────────────────
var actual_speed: float = 0.0
var _travel: float = 0.0
var _loop_len: float = 0.0
var _run_len: float = 0.0          # slope + crest, the driven carrying run
var _a: float = 0.0
var _run: float = 0.0
var _slope_len: float = 0.0
var _p0 := Vector2.ZERO            # carrying plane: bottom tangent
var _p1 := Vector2.ZERO            # carrying plane: ramp / crest kink
var _p2 := Vector2.ZERO            # carrying plane: crest end
var _top_centre := Vector2.ZERO
var _bot_centre := Vector2.ZERO
var _segments: Array[Dictionary] = []

var _parts: Node3D
var _stations: Array[AnimatableBody3D] = []
var _station_shapes: Array[Array] = []
var _slot: Array[float] = []
var _slot_visible: Array[bool] = []
var _sprockets: Array[Node3D] = []
var _shafts: Array[Node3D] = []
var _plates_mm: MultiMeshInstance3D
var _rollers_mm: MultiMeshInstance3D
var _num_links: int = 0

var _incline_area: Area3D
var _discharge_area: Area3D
var _sorter: Node
var _upstream: Node3D
var _link_retries: int = 120
var _holding: bool = false
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

## The chain loop is a closed polyline of two straight runs on the ramp, two on
## the crest, the two sprocket wraps and the return runs below the bed. Every
## position is (z, y) in machine-local space and the second value returned is the
## rotation about X that puts a link's local +Z along the direction of travel.
func _build_path() -> void:
	_a = deg_to_rad(slope_angle_deg)
	_run = rise / tan(_a)
	_slope_len = rise / sin(_a)
	_p0 = Vector2(0.0, 0.0)
	_p1 = Vector2(_run, rise)
	_p2 = Vector2(_run + level_length, rise)

	var n0 := Vector2(-sin(_a), cos(_a))                 # ramp plane normal
	var d0 := Vector2(cos(_a), sin(_a))                  # ramp uphill direction
	var level := Vector2(1.0, 0.0)                       # crest direction

	# Chain centre line: the carrying plane dropped by CARRIER_DROP.
	var a0 := _p0 - n0 * CARRIER_DROP
	var a2 := Vector2(_p2.x, rise - CARRIER_DROP)
	var a1 := Vector2(
		a0.x + (a2.y - a0.y) / sin(_a) * cos(_a),
		a2.y)

	_top_centre = a2 + Vector2(0.0, -SPR)
	_bot_centre = _p0 - n0 * (CARRIER_DROP + SPR)

	var ret_top := a2 + Vector2(0.0, -2.0 * SPR)          # return run, under the crest
	var ret_foot := _p0 - n0 * (CARRIER_DROP + 2.0 * SPR) # return run tangent at the foot
	var ret_kink := ret_foot + d0 * ((ret_top.y - ret_foot.y) / sin(_a))

	_segments = [
		{"kind": "line", "start": a0, "dir": d0, "len": a1.distance_to(a0)},
		{"kind": "line", "start": a1, "dir": level, "len": a2.x - a1.x},
		{"kind": "arc", "centre": _top_centre, "radius": SPR, "angle": PI * 0.5, "sweep": -PI, "len": PI * SPR},
		{"kind": "line", "start": ret_top, "dir": -level, "len": ret_top.x - ret_kink.x},
		{"kind": "line", "start": ret_kink, "dir": -d0, "len": ret_kink.distance_to(ret_foot)},
		{"kind": "arc", "centre": _bot_centre, "radius": SPR,
			"angle": atan2(ret_foot.y - _bot_centre.y, ret_foot.x - _bot_centre.x), "sweep": -PI, "len": PI * SPR},
	]

	_loop_len = 0.0
	for segment in _segments:
		_loop_len += float(segment["len"])
	_run_len = float(_segments[0]["len"]) + float(_segments[1]["len"])


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
	return "%s|%s|%s|%s|%s|%s" % [
		str(slope_angle_deg), str(rise), str(level_length), str(bed_width),
		str(track_x_positions), str(floor_y)]


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
	_num_links = int(ceil(_loop_len / LINK_PITCH)) + 2
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
	var inner_x := LINK_SPAN * 0.5 + PLATE_W * 0.5
	var plate_index := 0
	var roller_index := 0
	for track_x: float in track_x_positions:
		for j in _num_links:
			var sample := _sample(float(j) * LINK_PITCH + _travel)
			var point: Vector2 = sample[0]
			var link := Transform3D(Basis(Vector3.RIGHT, float(sample[1])), Vector3(track_x, point.y, point.x))
			for side: float in [-1.0, 1.0]:
				_plates_mm.multimesh.set_instance_transform(
					plate_index, link * Transform3D(Basis(), Vector3(side * inner_x, 0.0, 0.0)))
				plate_index += 1
			_rollers_mm.multimesh.set_instance_transform(
				roller_index, link * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
			roller_index += 1


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

	# Bottom drive enclosure. It covers the foot sprockets and, with them, the
	# landing deck's own end sprockets, which sit at the same station.
	var housing := _material(Color(0.24, 0.25, 0.27), 0.72, 0.55)
	_mesh_box(_parts, Vector3(bed_width - 0.12, 0.66, 0.78),
		Vector3(0.0, -0.42, 0.07), 0.0, housing, "DriveEnclosure")
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
## The stations ride the carrying run and are dropped out of sight - collisions
## disabled - while they travel the return run back to the foot.
func _build_stations() -> void:
	var count: int = maxi(2, int(round(_loop_len / maxf(lug_pitch, 0.05))))
	var pitch := _loop_len / float(count)
	var steel := _material(Color(0.11, 0.10, 0.09), 0.82, 0.58)

	for i in count:
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

			# Fabricated pusher: shoe riding the chain, post standing on the bed.
			# The shoe tops out flush with the carrying plane so nothing but the
			# post stands proud of the boards.
			_add_mesh(station, Vector3(LUG_POST_W * 1.35, LUG_SHOE_H, LUG_SHOE_D),
				Vector3(track_x, CARRIER_DROP - LUG_SHOE_H * 0.5, 0.04), steel)
			_add_mesh(station, Vector3(LUG_POST_W, LUG_POST_H, LUG_POST_D),
				Vector3(track_x, CARRIER_DROP + LUG_POST_H * 0.5, LUG_POST_D * 0.5), steel)
			for brace_x: float in [-0.032, 0.032]:
				_add_mesh(station, Vector3(0.022, 0.20, 0.05),
					Vector3(track_x + brace_x, CARRIER_DROP + 0.115, -0.055), steel,
					Vector3(deg_to_rad(30.0), 0.0, 0.0))

		_stations.append(station)
		_station_shapes.append(shapes)
		_slot.append(float(i) * pitch)
		_slot_visible.append(false)
		# Start hidden: only stations on the carrying run may push.
		_set_station_shapes(i, false)
		_place_station(i)


func _add_mesh(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _place_station(index: int) -> void:
	var station := _stations[index]
	var s := _slot[index]
	if s < _run_len:
		var sample := _sample(s)
		var point: Vector2 = sample[0]
		station.transform = Transform3D(Basis(Vector3.RIGHT, float(sample[1])), Vector3(0.0, point.y, point.x))
		if not _slot_visible[index]:
			_slot_visible[index] = true
			_set_station_shapes(index, true)
	else:
		var t := (s - _run_len) / maxf(_loop_len - _run_len, 0.001)
		var below_head := Vector2(_p2.x, rise - HIDDEN_DROP)
		var below_foot := Vector2(sin(_a) * HIDDEN_DROP, -cos(_a) * HIDDEN_DROP)
		var point := below_head.lerp(below_foot, t)
		station.transform = Transform3D(Basis(Vector3.RIGHT, -_a), Vector3(0.0, point.y, point.x))
		if _slot_visible[index]:
			_slot_visible[index] = false
			_set_station_shapes(index, false)


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
	if is_instance_valid(_upstream):
		_upstream.set("external_stop", _holding)

	var target: float = chain_speed if (running and not external_stop and not _holding) else 0.0
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
	for i in _stations.size():
		_slot[i] = fposmod(_slot[i] + advance, _loop_len)
		_place_station(i)
	_place_chain_links()


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
