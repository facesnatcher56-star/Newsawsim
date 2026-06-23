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

const MAT_STEEL_COLOR  := Color(0.28, 0.30, 0.33)
const MAT_FLOOR_COLOR  := Color(0.22, 0.24, 0.26)

var _mat_plate: StandardMaterial3D
var _mat_floor: StandardMaterial3D

# ── Profile definition ───────────────────────────────────────────────────────
# Points describe the OUTER (top) edge of one side plate.
# X = horizontal (left = entry, right = exit), Y = vertical.
# A closed polygon is formed by appending the INNER (bottom) edge in reverse.
const _OUTER: Array[Vector2] = [
	Vector2(-1.50,  0.00),  # [0]  entry far left
	Vector2(-0.60,  0.00),  # [1]  before V-notch
	Vector2(-0.44, -0.28),  # [2]  notch descends
	Vector2(-0.22, -0.28),  # [3]  notch bottom flat
	Vector2(-0.04,  0.02),  # [4]  back up from notch
	Vector2( 0.22,  0.36),  # [5]  curve begins
	Vector2( 0.50,  0.72),  # [6]  curve mid
	# [7-11] circular arc (R=0.40) — tangent-continuous from the 43° sweep
	# to a perfectly horizontal exit.  Center = (1.052, 0.687).
	Vector2( 0.780, 0.980), # [7]  arc entry  (matches prev sweep angle)
	Vector2( 0.839, 1.026), # [8]  arc 1/4
	Vector2( 0.904, 1.059), # [9]  arc 2/4
	Vector2( 0.977, 1.080), # [10] arc 3/4
	Vector2( 1.052, 1.087), # [11] arc exit / flat starts here
	Vector2( 2.50,  1.087), # [12] exit far right
]
const _INNER_OFFSETS: Array[Vector2] = [
	Vector2(-1.50, -0.16),
	Vector2(-0.60, -0.16),
	Vector2(-0.44, -0.44),
	Vector2(-0.22, -0.44),
	Vector2(-0.04, -0.15),
	Vector2( 0.22,  0.19),
	Vector2( 0.50,  0.55),
	Vector2( 0.780, 0.812),
	Vector2( 0.839, 0.856),
	Vector2( 0.904, 0.889),
	Vector2( 0.977, 0.910),
	Vector2( 1.052, 0.917),
	Vector2( 2.50,  0.917),
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
	if Engine.is_editor_hint():
		csg.owner = get_tree().edited_scene_root


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
		# +plate_thickness so beams extend into the side plates — no gap
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
	if Engine.is_editor_hint():
		box.owner = get_tree().edited_scene_root


# ── Working surface (steel tray along the profile) ───────────────────────────

func _build_working_surface() -> void:
	var s := profile_scale
	# Thin steel tray panels that follow the profile segments
	var segments: Array[Array] = [
		# [from_outer_index, to_outer_index]
		[0, 1],    # entry flat
		[1, 3],    # V-notch
		[3, 5],    # bottom of notch rising
		[5, 7],    # lower sweep
		[7, 11],   # arc transition (rounded curve)
		[11, 12],  # exit flat
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
		# +plate_thickness so trays extend into the side plates — no gap
		tray.size = Vector3(length, 0.010, machine_width + plate_thickness)
		tray.position = Vector3(mid.x, mid.y, machine_width * 0.5)
		tray.rotation.z = angle
		tray.material = _mat_floor
		tray.use_collision = true
		add_child(tray)
		if Engine.is_editor_hint():
			tray.owner = get_tree().edited_scene_root
