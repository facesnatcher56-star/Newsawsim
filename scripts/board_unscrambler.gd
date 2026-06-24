## board_unscrambler.gd
## Steel board unscrambler / singulator.
## Side profile: entry flat → V-notch → upward sweep → exit flat platform.
## Two steel side plates are extruded from this profile with structural
## cross members between them.
@tool
extends StaticBody3D

## Width of the machine (board-length direction, Z axis).
@export var machine_width: float = 4.2:
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

	_build_side_plate(0.0)
	_build_side_plate(machine_width)
	_build_cross_members()
	_build_working_surface()
	_build_chains_and_flights()

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

# ── Side plate ───────────────────────────────────────────────────────────────

func _build_side_plate(z_pos: float) -> void:
	var poly := PackedVector2Array()
	var s := profile_scale
	for pt in _OUTER:
		poly.append(pt * s)
	for i in range(_INNER_OFFSETS.size() - 1, -1, -1):
		poly.append(_INNER_OFFSETS[i] * s)

	var csg := CSGPolygon3D.new()
	csg.name = "SidePlate_Z%d" % int(z_pos * 100)
	csg.polygon = poly
	csg.mode = CSGPolygon3D.MODE_DEPTH
	csg.depth = plate_thickness
	csg.position = Vector3(0.0, 0.0, z_pos - plate_thickness * 0.5)
	csg.material = _make_plate_material()
	csg.use_collision = true
	add_child(csg)

func _make_plate_material() -> StandardMaterial3D:
	return _mat_plate

# ── Cross structural members ─────────────────────────────────────────────────

func _build_cross_members() -> void:
	var s := profile_scale
	# Positions along the profile where cross beams sit (X, Y midpoints of outer edge)
	var beam_positions: Array[Vector2] = [
		Vector2(-1.20, -0.08),   # entry zone bottom
		Vector2(-0.33, -0.36),   # inside the V-notch
		Vector2( 0.36,  0.54),   # mid curve
		Vector2( 0.91,  1.03),   # upper curve / arc zone
		Vector2( 1.78,  1.083),  # exit flat mid
	]
	for bp in beam_positions:
		var pos := bp * s
		pos.y -= 0.08 * s
		_add_beam(pos, Vector3(0.06, 0.06, machine_width + plate_thickness))

func _add_beam(profile_pos: Vector2, size: Vector3) -> void:
	var box := CSGBox3D.new()
	box.name = "Beam"
	box.size = size
	box.position = Vector3(
		profile_pos.x,
		profile_pos.y,
		machine_width * 0.5
	)
	box.material = _mat_plate
	box.use_collision = true
	add_child(box)

# ── Working surface (steel tray along the profile) ───────────────────────────

func _build_working_surface() -> void:
	var s := profile_scale
	# Thin steel tray panels that follow the profile segments segment-by-segment
	var segments: Array[Array] = [
		# [from_outer_index, to_outer_index]  — profile now has 9 points (0-8)
		[0, 1],   # entry flat
		[1, 2],   # V left slope  (down to apex)
		[2, 3],   # V right slope (up from apex)
		[3, 4],   # lower curve
		[4, 5],   # curve mid
		[5, 6],   # curve upper
		[6, 7],   # near-flat approach
		[7, 8],   # exit flat
	]
	for seg in segments:
		var a: Vector2 = _OUTER[seg[0]] * s
		var b: Vector2 = _OUTER[seg[1]] * s
		var mid := (a + b) * 0.5
		var diff := b - a
		var length := diff.length()
		if length < 0.01:
			continue
		var angle := atan2(diff.y, diff.x)

		# Make plates thicker (0.06m) so we can cut out grooves for the chains
		var surface_thickness := 0.06 * s
		var offset_dist := (surface_thickness - 0.010) * 0.5
		var n_dir := Vector2(-sin(angle), cos(angle))

		var tray := CSGBox3D.new()
		tray.name = "Surface"
		tray.size = Vector3(length, surface_thickness, machine_width - plate_thickness * 2.2)
		tray.position = Vector3(
			mid.x - n_dir.x * offset_dist,
			mid.y - n_dir.y * offset_dist,
			machine_width * 0.5
		)
		tray.rotation.z = angle
		tray.material = _mat_floor
		tray.use_collision = true

		var is_v_notch: bool = (seg[0] == 1 and seg[1] == 2)
		var is_groove_needed: bool = (seg[0] >= 1)

		if is_groove_needed:
			var zc_center := machine_width * 0.5
			var scale_factor: float = (chain_diameter / 0.048) * s
			var outer_z := (0.052 + 0.014) * scale_factor
			var slot_w := (outer_z * 2.0 + 0.014 * scale_factor) * 1.15
			var plate_h := 0.042 * scale_factor

			# Generate 8 evenly spaced chains
			var s_dist := chain_spacing
			var total_width := 7.0 * s_dist
			var start_z := (machine_width - total_width) * 0.5
			var chain_zs: Array[float] = []
			for i in range(8):
				chain_zs.append(start_z + i * s_dist)

			if is_v_notch:
				# Cut 4 small slots at the bottom end of the downhill slope for the flights and chains
				var slot_len := 0.15 * s
				for k in range(4):
					var zc_k := start_z + (2 * k + 0.5) * s_dist
					var slot := CSGBox3D.new()
					slot.name = "Slot"
					slot.operation = CSGShape3D.OPERATION_SUBTRACTION
					var slot_w_flight := s_dist + 2.0 * outer_z + 0.02
					slot.size = Vector3(slot_len, surface_thickness + 0.05, slot_w_flight)
					# Position at the very bottom end of the downhill slope segment (local X end)
					slot.position = Vector3(length * 0.5 - slot_len * 0.5, 0.0, zc_k - zc_center)
					tray.add_child(slot)
			else:
				# Groove only recedes the chain (depth = plate_h * 1.1)
				for cz in chain_zs:
					var slot := CSGBox3D.new()
					slot.name = "Groove"
					slot.operation = CSGShape3D.OPERATION_SUBTRACTION
					var groove_depth := plate_h * 1.1
					slot.size = Vector3(length + 0.1, groove_depth, slot_w)
					slot.position = Vector3(0.0, surface_thickness * 0.5 - groove_depth * 0.5, cz - zc_center)
					tray.add_child(slot)

		add_child(tray)

# ── Chains & Flights ─────────────────────────────────────────────────────────

func _build_chains_and_flights() -> void:
	var s := profile_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.9
	mat.roughness = 0.25

	# Build path: V-notch to exit + overhang, closed loop return underneath
	var raw: Array[Vector2] = [
		# Forward path on top of the slide
		Vector2(-0.22, -0.28),  # V-notch bottom flat
		Vector2(-0.04,  0.02),  # back up from notch
		Vector2( 0.22,  0.36),  # curve begins
		Vector2( 0.50,  0.72),  # curve mid
		Vector2( 0.78,  0.98),  # curve upper
		Vector2( 1.00,  1.10),  # entry to exit flat
		Vector2( 2.50,  1.10),  # exit far right
		Vector2( 2.50 + chain_overhang, 1.10), # sprocket top
	]

	# Sample return path using quadratic Bezier curve to create natural droop
	var p0 := Vector2(2.50 + chain_overhang, 0.70)
	var p1 := Vector2(1.2, -0.9)
	var p2 := Vector2(-0.22, -0.48)

	var num_bezier_pts := 15
	for i in range(num_bezier_pts):
		var t := float(i) / float(num_bezier_pts - 1)
		var pt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		raw.append(pt)

	# Finally close the loop
	raw.append(Vector2(-0.22, -0.28))

	# Arc-length param
	var al: Array[float] = [0.0]
	for i in range(1, raw.size()):
		al.append(al[al.size() - 1] + (raw[i] * s).distance_to(raw[i - 1] * s))
	var total := al[al.size() - 1]
	if total < 0.001:
		return

	var steps := 100
	var pts: Array[Vector2] = []
	var si := 0
	for step_idx in range(steps):
		var tgt := step_idx * total / float(steps - 1)
		while si < al.size() - 2 and al[si + 1] < tgt:
			si += 1
		var t := (tgt - al[si]) / (al[si + 1] - al[si]) if al[si + 1] > al[si] else 0.0
		pts.append((raw[si] * s).lerp(raw[si + 1] * s, clampf(t, 0.0, 1.0)))
	if pts.size() < 2:
		return

	var zw: float = machine_width
	var s_dist := chain_spacing
	var total_width := 7.0 * s_dist
	var start_z := (zw - total_width) * 0.5

	# Scale diameter, pitch and dimensions relative to Level Deck chain links
	# Level deck references: pitch = 0.2032, plate length = 0.25, plate height = 0.042,
	# plate width = 0.014, plate Z offset = 0.052, roller radius = 0.024, roller height = 0.128.
	# Scale factor based on custom chain_diameter compared to default level deck roller diameter (0.048).
	var scale_factor: float = (chain_diameter / 0.048) * s

	var link_len := 0.2032 * s
	var plate_len := 0.25 * s

	# Cumulative distance along pts
	var pts_al: Array[float] = [0.0]
	for i in range(1, pts.size()):
		pts_al.append(pts_al[pts_al.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total_path_len := pts_al[pts_al.size() - 1]

	var num_links := int(total_path_len / link_len)
	var actual_step := total_path_len / float(num_links)

	# Use actual_step for placing and sizing the link plates to avoid gaps
	var effective_link_len := actual_step
	var effective_plate_len := plate_len * (actual_step / link_len)

	var plate_h := 0.042 * scale_factor
	var plate_w := 0.014 * scale_factor
	var inner_z := 0.052 * scale_factor
	var outer_z := inner_z + plate_w
	var roller_r := 0.024 * scale_factor

	# Calculate offset sidebar chain plate segments
	var straight_len := effective_plate_len * 0.5 - effective_link_len * 0.05
	var straight_center_x := (effective_plate_len * 0.5 + effective_link_len * 0.05) * 0.5

	var dx := effective_link_len * 0.1
	var dz := outer_z - inner_z
	var jog_len := sqrt(dx * dx + dz * dz)
	var jog_ang := -atan2(dz, dx)

	# Shared meshes for chain links
	var straight_plate_mesh := BoxMesh.new()
	straight_plate_mesh.size = Vector3(straight_len, plate_h, plate_w)

	var jog_plate_mesh := BoxMesh.new()
	jog_plate_mesh.size = Vector3(jog_len, plate_h, plate_w)

	var roller_width := inner_z * 2.0 - plate_w
	var cyl_m := CylinderMesh.new()
	cyl_m.top_radius = roller_r
	cyl_m.bottom_radius = roller_r
	cyl_m.height = roller_width
	cyl_m.radial_segments = 8

	var pin_m := CylinderMesh.new()
	pin_m.top_radius = roller_r * 0.5
	pin_m.bottom_radius = roller_r * 0.5
	pin_m.height = outer_z * 2.0 + plate_w * 1.5
	pin_m.radial_segments = 6

	# Chain rails (8 chains total, evenly spaced)
	var chain_zs: Array[float] = []
	for i in range(8):
		chain_zs.append(start_z + i * s_dist)
	_anim_link_recede = plate_h * 0.5
	for z in chain_zs:
		for j in range(num_links):
			var d_start := j * actual_step
			var d_end := (j + 1) * actual_step
			
			var start_pt := _get_path_point_at_dist(d_start, pts, pts_al)
			var end_pt := _get_path_point_at_dist(d_end, pts, pts_al)
			
			var p := (start_pt + end_pt) * 0.5
			var d := (end_pt - start_pt).normalized()
			var ang := atan2(d.y, d.x)

			var link := Node3D.new()
			link.name = "Link"

			# Recede the chain inside the plates
			var recede_dist := plate_h * 0.5
			var n_dir := Vector2(-d.y, d.x)
			var p_receded := p - n_dir * recede_dist

			link.position = Vector3(p_receded.x, p_receded.y, z)
			link.rotation.z = ang
			link.add_to_group(_CHAIN_GROUP)
			add_child(link)

			# Store for chain animation
			_anim_links.append(link)
			_anim_link_dists.append(d_start + actual_step * 0.5)
			_anim_link_zs.append(z)

			# Left Plate (offset sidebar, positive Z)
			var lp_in := MeshInstance3D.new()
			lp_in.mesh = straight_plate_mesh
			lp_in.material_override = mat
			lp_in.position = Vector3(-straight_center_x, 0.0, inner_z)
			link.add_child(lp_in)

			var lp_jog := MeshInstance3D.new()
			lp_jog.mesh = jog_plate_mesh
			lp_jog.material_override = mat
			lp_jog.position = Vector3(0.0, 0.0, (inner_z + outer_z) * 0.5)
			lp_jog.rotation.y = jog_ang
			link.add_child(lp_jog)

			var lp_out := MeshInstance3D.new()
			lp_out.mesh = straight_plate_mesh
			lp_out.material_override = mat
			lp_out.position = Vector3(straight_center_x, 0.0, outer_z)
			link.add_child(lp_out)

			# Right Plate (offset sidebar, negative Z)
			var rp_in := MeshInstance3D.new()
			rp_in.mesh = straight_plate_mesh
			rp_in.material_override = mat
			rp_in.position = Vector3(-straight_center_x, 0.0, -inner_z)
			link.add_child(rp_in)

			var rp_jog := MeshInstance3D.new()
			rp_jog.mesh = jog_plate_mesh
			rp_jog.material_override = mat
			rp_jog.position = Vector3(0.0, 0.0, -(inner_z + outer_z) * 0.5)
			rp_jog.rotation.y = -jog_ang
			link.add_child(rp_jog)

			var rp_out := MeshInstance3D.new()
			rp_out.mesh = straight_plate_mesh
			rp_out.material_override = mat
			rp_out.position = Vector3(straight_center_x, 0.0, -outer_z)
			link.add_child(rp_out)

			# Joint Roller (narrow end at local_x = -effective_link_len * 0.5)
			var ro := MeshInstance3D.new()
			ro.mesh = cyl_m
			ro.material_override = mat
			ro.position = Vector3(-effective_link_len * 0.5, 0.0, 0.0)
			ro.rotation.x = PI / 2.0
			link.add_child(ro)

			# Joint Pin
			var pin := MeshInstance3D.new()
			pin.mesh = pin_m
			pin.material_override = mat
			pin.position = Vector3(-effective_link_len * 0.5, 0.0, 0.0)
			pin.rotation.x = PI / 2.0
			link.add_child(pin)

	# Shared mesh for flights (square tubes)
	var scaled_flight_dia := flight_diameter * s
	var scaled_flight_h := scaled_flight_dia * 0.5
	var flight_len := s_dist + 2.0 * outer_z
	var flight_mesh_res := BoxMesh.new()
	flight_mesh_res.size = Vector3(scaled_flight_dia, scaled_flight_dia, flight_len)

	# BoxShape3D for flight collision (matching visual size)
	var flight_shape := BoxShape3D.new()
	flight_shape.size = Vector3(scaled_flight_dia, scaled_flight_dia, flight_len)

	# Store path data for flight animation
	_anim_path_pts = pts
	_anim_flight_perp = scaled_flight_h

	# Flights — placed along the closed-loop path and animated each physics frame
	var al2: Array[float] = [0.0]
	for i in range(1, pts.size()):
		al2.append(al2[al2.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total2 := al2[al2.size() - 1]
	_anim_path_al = al2
	_anim_path_total = total2

	var fd := flight_spacing * 0.5
	var fi := 0
	var s2 := 0
	while fd < total2:
		while s2 < al2.size() - 2 and al2[s2 + 1] < fd:
			s2 += 1
		var t := (fd - al2[s2]) / (al2[s2 + 1] - al2[s2]) if al2[s2 + 1] > al2[s2] else 0.0
		t = clampf(t, 0.0, 1.0)
		var pos := pts[s2].lerp(pts[s2 + 1], t)
		var d2 := (pts[s2 + 1] - pts[s2]).normalized()
		var n := Vector2(-d2.y, d2.x)
		var ang := atan2(d2.y, d2.x)

		for k in range(4):
			var zc_k := start_z + (2 * k + 0.5) * s_dist

			# AnimatableBody3D — moves each frame, imparting velocity to RigidBody contacts
			var fl := AnimatableBody3D.new()
			fl.name = "Flight_S%d_F%d" % [k, fi]
			fl.sync_to_physics = false
			fl.position = Vector3(pos.x + n.x * scaled_flight_h, pos.y + n.y * scaled_flight_h, zc_k)
			fl.rotation = Vector3(0.0, 0.0, ang)

			# Visual mesh
			var fl_mesh := MeshInstance3D.new()
			fl_mesh.mesh = flight_mesh_res
			fl_mesh.material_override = mat
			fl.add_child(fl_mesh)

			# Collision shape — physically pushes boards
			var fl_shape := CollisionShape3D.new()
			fl_shape.shape = flight_shape
			fl.add_child(fl_shape)

			fl.add_to_group(_CHAIN_GROUP)
			add_child(fl)

			# Store for animation
			_anim_flights.append(fl)
			_anim_flight_dists.append(fd)
			_anim_flight_zs.append(zc_k)

		fi += 1
		fd += flight_spacing

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
