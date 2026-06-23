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

@export var chain_spacing: float = 1.8:
	set(v): chain_spacing = v; _rebuild()
@export var flight_spacing: float = 0.35:
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
		add_child(tray)

# ── Chains & Flights ─────────────────────────────────────────────────────────

func _build_chains_and_flights() -> void:
	var s := profile_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.9
	mat.roughness = 0.25

	# Build path: V-notch to exit + overhang
	var raw: Array[Vector2] = _OUTER.duplicate()
	var last := raw[raw.size() - 1]
	var prev := raw[raw.size() - 2]
	raw.append(last + (last - prev).normalized() * chain_overhang)

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
	var za := zc - chain_spacing * 0.5
	var zb := zc + chain_spacing * 0.5

	# Scale diameter, pitch and dimensions relative to Level Deck chain links
	# Level deck references: pitch = 0.2032, plate length = 0.25, plate height = 0.042,
	# plate width = 0.014, plate Z offset = 0.052, roller radius = 0.024, roller height = 0.128.
	# Scale factor based on custom chain_diameter compared to default level deck roller diameter (0.048).
	var scale_factor: float = (chain_diameter / 0.048) * s

	var link_len := 0.2032 * scale_factor
	var plate_len := 0.25 * scale_factor
	var plate_h := 0.042 * scale_factor
	var plate_w := 0.014 * scale_factor
	var inner_z := 0.052 * scale_factor
	var roller_r := 0.024 * scale_factor
	var roller_h := 0.128 * scale_factor

	# Shared meshes for chain links
	var box_m := BoxMesh.new()
	box_m.size = Vector3(plate_len, plate_h, plate_w)

	var cyl_m := CylinderMesh.new()
	cyl_m.top_radius = roller_r
	cyl_m.bottom_radius = roller_r
	cyl_m.height = roller_h
	cyl_m.radial_segments = 8

	# Chain rails
	for z in [za, zb]:
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

				# Left Plate
				var lp := MeshInstance3D.new()
				lp.mesh = box_m
				lp.material_override = mat
				lp.position = Vector3(0.0, 0.0, -inner_z)
				link.add_child(lp)

				# Right Plate
				var rp := MeshInstance3D.new()
				rp.mesh = box_m
				rp.material_override = mat
				rp.position = Vector3(0.0, 0.0, inner_z)
				link.add_child(rp)

				# Roller
				var ro := MeshInstance3D.new()
				ro.mesh = cyl_m
				ro.material_override = mat
				ro.rotation.x = PI / 2.0
				link.add_child(ro)

	# Shared mesh for flights
	var scaled_flight_dia = flight_diameter * s
	var scaled_flight_h = flight_height * s
	var flight_mesh_res := CylinderMesh.new()
	flight_mesh_res.top_radius = scaled_flight_dia * 0.5
	flight_mesh_res.bottom_radius = scaled_flight_dia * 0.5
	flight_mesh_res.height = absf(zb - za) + (0.052 * 2.0 + 0.014) * scale_factor + 0.01
	flight_mesh_res.radial_segments = 8

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

		var fl := MeshInstance3D.new()
		fl.name = "Flight%d" % fi
		fi += 1
		fl.mesh = flight_mesh_res
		fl.position = Vector3(pos.x + n.x * scaled_flight_h, pos.y + n.y * scaled_flight_h, (za + zb) * 0.5)
		fl.rotation.x = deg_to_rad(90.0)
		fl.material_override = mat
		fl.add_to_group(_CHAIN_GROUP)
		add_child(fl)

		fd += flight_spacing
