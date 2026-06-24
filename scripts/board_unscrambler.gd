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

@export var chain_spacing: float = 0.8:
	set(v): chain_spacing = v; _rebuild()
@export var set_gap: float = 0.1:
	set(v): set_gap = v; _rebuild()
@export var flight_spacing: float = 1.4:
	set(v): flight_spacing = v; _rebuild()
@export var flight_height: float = 0.1:
	set(v): flight_height = v; _rebuild()
@export var chain_diameter: float = 0.048:
	set(v): chain_diameter = v; _rebuild()
@export var flight_diameter: float = 0.08:
	set(v): flight_diameter = v; _rebuild()
@export var chain_overhang: float = 0.35:
	set(v): chain_overhang = v; _rebuild()

const MAT_STEEL_COLOR  := Color(0.28, 0.30, 0.33)
const MAT_FLOOR_COLOR  := Color(0.22, 0.24, 0.26)
const _CHAIN_GROUP := &"_unscrambler_chains"

var _mat_plate: StandardMaterial3D
var _mat_floor: StandardMaterial3D

# ── Profile definition ───────────────────────────────────────────────────────
# Points describe the OUTER (top) edge of one side plate.
# X = horizontal (left = entry, right = exit), Y = vertical.
# A closed polygon is formed by appending the INNER (bottom) edge in reverse.
const _OUTER: Array[Vector2] = [
	Vector2(-1.50,  0.00),  # entry far left
	Vector2(-0.60,  0.00),  # before V-notch
	Vector2(-0.44, -0.28),  # notch descends
	Vector2(-0.22, -0.28),  # notch bottom flat
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
	Vector2(-0.44, -0.44),
	Vector2(-0.22, -0.44),
	Vector2(-0.04, -0.15),
	Vector2( 0.22,  0.19),
	Vector2( 0.50,  0.55),
	Vector2( 0.78,  0.81),
	Vector2( 1.00,  0.93),
	Vector2( 2.50,  0.93),
]

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame

	_mat_plate = StandardMaterial3D.new()
	_mat_plate.albedo_color = MAT_STEEL_COLOR
	_mat_plate.metallic = 0.85
	_mat_plate.roughness = 0.30

	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = MAT_FLOOR_COLOR
	_mat_floor.metallic = 0.80
	_mat_floor.roughness = 0.40

	_build_side_plate(0.0)
	_build_side_plate(machine_width)
	_build_cross_members()
	_build_working_surface()
	_build_chains_and_flights()

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
		_add_beam(bp * s, Vector3(0.06, 0.06, machine_width + plate_thickness))

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
	# Thin steel tray panels that follow the profile segments
	var segments: Array[Array] = [
		# [from_outer_index, to_outer_index]
		[0, 1],   # entry flat
		[1, 3],   # V-notch
		[3, 5],   # bottom of notch rising
		[5, 8],   # main upward curve
		[8, 9],   # exit flat
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

		var tray := CSGBox3D.new()
		tray.name = "Surface"
		tray.size = Vector3(length, 0.010, machine_width - plate_thickness * 2.2)
		tray.position = Vector3(mid.x, mid.y, machine_width * 0.5)
		tray.rotation.z = angle
		tray.material = _mat_floor
		tray.use_collision = true

		var is_v_notch: bool = (seg[0] == 1 and seg[1] == 3) or (seg[0] == 3 and seg[1] == 5)
		if is_v_notch:
			var zc_center := machine_width * 0.5
			var scale_factor: float = (chain_diameter / 0.048) * s
			var outer_z := (0.052 + 0.014) * scale_factor
			var slot_w := (outer_z * 2.0 + 0.014 * scale_factor) * 1.3
			var total_width := 4.0 * chain_spacing + 3.0 * set_gap
			var start_z := (machine_width - total_width) * 0.5
			var chain_zs: Array[float] = []
			for k in range(4):
				var zc_k := start_z + k * (chain_spacing + set_gap) + chain_spacing * 0.5
				chain_zs.append(zc_k - chain_spacing * 0.5)
				chain_zs.append(zc_k + chain_spacing * 0.5)
			for cz in chain_zs:
				var slot := CSGBox3D.new()
				slot.name = "Slot"
				slot.operation = 2 # CSGShape3D.OPERATION_SUBTRACT
				slot.size = Vector3(length + 0.1, 0.05, slot_w)
				slot.position = Vector3(0.0, 0.0, cz - zc_center)
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
		
		# Return path underneath the working surface
		Vector2( 2.50 + chain_overhang, 0.70), # sprocket bottom
		Vector2( 1.00,  0.70),  # under exit flat
		Vector2( 0.78,  0.58),  # under curve upper
		Vector2( 0.50,  0.32),  # under curve mid
		Vector2( 0.22, -0.04),  # under curve lower
		Vector2(-0.04, -0.48),  # under notch rising
		Vector2(-0.22, -0.48),  # under notch bottom
		Vector2(-0.22, -0.28),  # close the loop
	]

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
	var zc := zw * 0.5
	var total_width := 4.0 * chain_spacing + 3.0 * set_gap
	var start_z := (zw - total_width) * 0.5
	var za := start_z
	var zb := start_z + 3.0 * (chain_spacing + set_gap) + chain_spacing

	# Scale diameter, pitch and dimensions relative to Level Deck chain links
	# Level deck references: pitch = 0.2032, plate length = 0.25, plate height = 0.042,
	# plate width = 0.014, plate Z offset = 0.052, roller radius = 0.024, roller height = 0.128.
	# Scale factor based on custom chain_diameter compared to default level deck roller diameter (0.048).
	var scale_factor: float = (chain_diameter / 0.048) * s

	var link_len := 0.2032 * s
	var plate_len := 0.25 * s
	var plate_h := 0.042 * scale_factor
	var plate_w := 0.014 * scale_factor
	var inner_z := 0.052 * scale_factor
	var outer_z := inner_z + plate_w
	var roller_r := 0.024 * scale_factor

	# Calculate offset sidebar chain plate segments
	var straight_len := plate_len * 0.5 - link_len * 0.05
	var straight_center_x := (plate_len * 0.5 + link_len * 0.05) * 0.5

	var dx := link_len * 0.1
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

	# Chain rails (8 chains total, 4 sets of twin chains)
	var chain_zs: Array[float] = []
	for k in range(4):
		var zc_k := start_z + k * (chain_spacing + set_gap) + chain_spacing * 0.5
		chain_zs.append(zc_k - chain_spacing * 0.5)
		chain_zs.append(zc_k + chain_spacing * 0.5)
	for z in chain_zs:
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.001:
				continue
			var d := (b - a) / seg
			var ang := atan2(d.y, d.x)
			var cnt := maxi(1, int(seg / link_len))
			var stp := seg / float(cnt)
			for j in range(cnt):
				var p := a + d * ((j + 0.5) * stp)
				var link := Node3D.new()
				link.name = "Link"
				link.position = Vector3(p.x, p.y, z)
				link.rotation.z = ang
				link.add_to_group(_CHAIN_GROUP)
				add_child(link)

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

				# Joint Roller (narrow end at local_x = -link_len * 0.5)
				var ro := MeshInstance3D.new()
				ro.mesh = cyl_m
				ro.material_override = mat
				ro.position = Vector3(-link_len * 0.5, 0.0, 0.0)
				ro.rotation.x = PI / 2.0
				link.add_child(ro)

				# Joint Pin
				var pin := MeshInstance3D.new()
				pin.mesh = pin_m
				pin.material_override = mat
				pin.position = Vector3(-link_len * 0.5, 0.0, 0.0)
				pin.rotation.x = PI / 2.0
				link.add_child(pin)

				# If this is the last link of the segment, add a roller & pin at the end to cap it
				if j == cnt - 1:
					var ro_end := MeshInstance3D.new()
					ro_end.mesh = cyl_m
					ro_end.material_override = mat
					ro_end.position = Vector3(link_len * 0.5, 0.0, 0.0)
					ro_end.rotation.x = PI / 2.0
					link.add_child(ro_end)

					var pin_end := MeshInstance3D.new()
					pin_end.mesh = pin_m
					pin_end.material_override = mat
					pin_end.position = Vector3(link_len * 0.5, 0.0, 0.0)
					pin_end.rotation.x = PI / 2.0
					link.add_child(pin_end)

	# Shared mesh for flights (Square tubes)
	var scaled_flight_dia = flight_diameter * s
	var scaled_flight_h = flight_height * s
	var flight_len := chain_spacing + (inner_z * 2.0 + plate_w) + 0.01
	var flight_mesh_res := BoxMesh.new()
	flight_mesh_res.size = Vector3(scaled_flight_dia, scaled_flight_dia, flight_len)

	# Bracket setup for attaching flights visually to chains
	var contact_h: float = plate_h * 0.5 + scaled_flight_dia * 0.5
	var bracket_m: BoxMesh = null
	var bracket_y: float = 0.0
	if scaled_flight_h > contact_h:
		var bracket_h: float = scaled_flight_h - contact_h
		bracket_m = BoxMesh.new()
		bracket_m.size = Vector3(plate_len * 0.5, bracket_h, inner_z * 2.0)
		bracket_y = (-scaled_flight_h + plate_h * 0.5 - scaled_flight_dia * 0.5) * 0.5

	# Flights
	var al2: Array[float] = [0.0]
	for i in range(1, pts.size()):
		al2.append(al2[al2.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total2 := al2[al2.size() - 1]

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
			var zc_k := start_z + k * (chain_spacing + set_gap) + chain_spacing * 0.5
			var fl := MeshInstance3D.new()
			fl.name = "Flight_S%d_F%d" % [k, fi]
			fl.mesh = flight_mesh_res
			fl.position = Vector3(pos.x + n.x * scaled_flight_h, pos.y + n.y * scaled_flight_h, zc_k)
			fl.rotation = Vector3(0.0, 0.0, ang)
			fl.material_override = mat
			fl.add_to_group(_CHAIN_GROUP)
			add_child(fl)

			if bracket_m:
				var b1 := MeshInstance3D.new()
				b1.name = "BracketA"
				b1.mesh = bracket_m
				b1.material_override = mat
				b1.position = Vector3(0.0, bracket_y, -chain_spacing * 0.5)
				fl.add_child(b1)

				var b2 := MeshInstance3D.new()
				b2.name = "BracketB"
				b2.mesh = bracket_m
				b2.material_override = mat
				b2.position = Vector3(0.0, bracket_y, chain_spacing * 0.5)
				fl.add_child(b2)

		fi += 1
		fd += flight_spacing
