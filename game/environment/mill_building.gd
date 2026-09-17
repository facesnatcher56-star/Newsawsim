@tool
class_name MillBuilding
extends Node3D

## Procedurally builds the mill enclosure: a concrete-and-glazed perimeter wall,
## structural columns, roof trusses, a gable roof and interior work lights.
##
## Every piece is derived from [member width] and [member length], so the
## envelope can be resized to wrap whatever machinery a level contains. Pieces
## are added as children of this node *without* an owner, so they are never
## written into the scene file - they are rebuilt from the exported values each
## time the scene is loaded. Editing an exported value while the scene is open
## rebuilds the building immediately.
##
## Generated in this node's local space, centred on the origin: the ridge runs
## down local -Z, the floor of the mill sits at y = -1.29, and X spans
## -width/2 .. +width/2. Place the instance so that local (0, 0, 0) lands on the
## centre of the area to be covered.

const GENERATED_GROUP := &"sawmill_building_geometry"

## Door and conveyor openings, in this node's local space.
## wall - which wall to cut, offset - distance along that wall from the centre,
## width - how wide the gap is, top - how high the gap reaches. An opening that
## cannot fit the current wall length is skipped, so a resized building never
## ends up with a hole in mid-air.
const OPENINGS := [
	{"wall": &"south", "offset": -16.75, "width": 8.0, "top": 6.0},   # incline outfeed
	{"wall": &"west", "offset": -27.4, "width": 14.0, "top": 6.5},     # log infeed / truck door
	{"wall": &"north", "offset": 30.0, "width": 11.0, "top": 7.0},     # bin sorter haul-out
	{"wall": &"east", "offset": -14.1, "width": 3.0, "top": 3.0},      # personnel door
]

@export_group("Footprint")
## Span of the building along X, in metres.
@export_range(20.0, 200.0, 0.5) var width: float = 72.0:
	set(value):
		width = value
		_rebuild_if_ready()

## Span of the building along Z, in metres.
@export_range(20.0, 300.0, 0.5) var length: float = 106.0:
	set(value):
		length = value
		_rebuild_if_ready()

@export_group("Walls")
## Height of the foot of the walls; keep it just below the mill floor.
@export var wall_bottom: float = -1.5:
	set(value):
		wall_bottom = value
		_rebuild_if_ready()

## Height of the wall head, where the eaves sit.
@export var wall_top: float = 7.7:
	set(value):
		wall_top = value
		_rebuild_if_ready()

## Wall thickness in metres.
@export_range(0.1, 1.0, 0.05) var wall_thickness: float = 0.3:
	set(value):
		wall_thickness = value
		_rebuild_if_ready()

## Bottom of the continuous glazing band.
@export var glazing_bottom: float = 1.0:
	set(value):
		glazing_bottom = value
		_rebuild_if_ready()

## Top of the continuous glazing band.
@export var glazing_top: float = 4.6:
	set(value):
		glazing_top = value
		_rebuild_if_ready()

@export_group("Roof")
## Height of the ridge above the eaves.
@export_range(1.0, 25.0, 0.5) var roof_rise: float = 6.0:
	set(value):
		roof_rise = value
		_rebuild_if_ready()

## How far the roof projects past the walls, in metres.
@export_range(0.0, 5.0, 0.1) var roof_overhang: float = 1.0:
	set(value):
		roof_overhang = value
		_rebuild_if_ready()

## Thickness of the roof slabs.
@export_range(0.1, 1.0, 0.05) var roof_thickness: float = 0.35:
	set(value):
		roof_thickness = value
		_rebuild_if_ready()

@export_group("Structure")
## Target spacing between roof trusses, in metres.
@export_range(3.0, 30.0, 0.5) var truss_spacing: float = 12.0:
	set(value):
		truss_spacing = value
		_rebuild_if_ready()

## Pilaster columns evenly spaced down each wall, corners included.
@export_range(2, 24, 1) var wall_columns: int = 7:
	set(value):
		wall_columns = value
		_rebuild_if_ready()

## Hang interior work lights from every fourth truss.
@export var work_lights: bool = true:
	set(value):
		work_lights = value
		_rebuild_if_ready()

## Let the work lights cast shadows. Off by default on purpose: this mill is a
## scene full of small moving parts, so every shadow-casting light has to redraw
## its whole shadow map every frame, and that cost multiplies with each light.
@export var work_light_shadows: bool = false:
	set(value):
		work_light_shadows = value
		_rebuild_if_ready()

## Give the building physics. Turn off when it is only a backdrop.
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		_rebuild_if_ready()

var _structure: StaticBody3D = null
var _visuals: Node3D = null
var _materials: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _shape_cache: Dictionary = {}
var _used_names: Dictionary = {}

func _ready() -> void:
	rebuild()

## Throw away the generated pieces and lay the building out again.
func rebuild() -> void:
	_clear_generated()
	if not is_inside_tree():
		return
	_materials = _make_materials()
	if collision_enabled:
		_structure = StaticBody3D.new()
		_structure.name = "Structure"
		_structure.add_to_group(GENERATED_GROUP)
		add_child(_structure)
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	_visuals.add_to_group(GENERATED_GROUP)
	add_child(_visuals)
	_build_walls()
	_build_columns()
	_build_trusses()
	_build_roof()
	_build_gables()
	if work_lights:
		_build_lights()

func _rebuild_if_ready() -> void:
	if is_inside_tree():
		rebuild()

func _clear_generated() -> void:
	_mesh_cache.clear()
	_shape_cache.clear()
	_used_names.clear()
	_structure = null
	_visuals = null
	for child in get_children():
		if child.is_in_group(GENERATED_GROUP):
			remove_child(child)
			child.queue_free()

#region Walls

func _build_walls() -> void:
	var half_w: float = width * 0.5
	var half_l: float = length * 0.5
	var bands: Array[Dictionary] = [
		{"y0": wall_bottom, "y1": glazing_bottom, "material": &"concrete", "label": "Lower", "thin": false},
		{"y0": glazing_bottom, "y1": glazing_top, "material": &"glass", "label": "Glazing", "thin": true},
		{"y0": glazing_top, "y1": wall_top, "material": &"steel", "label": "Upper", "thin": false},
	]
	# north/south walls run along X, east/west walls run along Z
	var walls: Array[Dictionary] = [
		{"id": &"north", "offset": half_l, "along_x": true, "span": half_w},
		{"id": &"south", "offset": -half_l, "along_x": true, "span": half_w},
		{"id": &"east", "offset": half_w, "along_x": false, "span": half_l},
		{"id": &"west", "offset": -half_w, "along_x": false, "span": half_l},
	]
	for wall in walls:
		var wall_id: StringName = wall["id"]
		var offset: float = wall["offset"]
		var along_x: bool = wall["along_x"]
		var span: float = wall["span"]
		var openings: Array = _openings_for(wall_id, span)
		for band in bands:
			var y0: float = band["y0"]
			var y1: float = band["y1"]
			if y1 - y0 < 0.05:
				continue
			var thickness: float = wall_thickness * (0.35 if band["thin"] else 1.0)
			var label: String = "Wall_%s_%s" % [String(wall_id).capitalize(), band["label"]]
			for segment in _band_segments(-span, span, y0, y1, openings):
				var from_x: float = segment[0]
				var to_x: float = segment[1]
				var from_y: float = segment[2]
				var to_y: float = segment[3]
				var seg_len: float = to_x - from_x
				var seg_height: float = to_y - from_y
				if seg_len < 0.05 or seg_height < 0.05:
					continue
				var mid: float = (from_x + to_x) * 0.5
				var mid_y: float = (from_y + to_y) * 0.5
				if along_x:
					_add_piece(label, Transform3D(Basis(), Vector3(mid, mid_y, offset)), Vector3(seg_len, seg_height, thickness), band["material"])
				else:
					_add_piece(label, Transform3D(Basis(), Vector3(offset, mid_y, mid)), Vector3(thickness, seg_height, seg_len), band["material"])

## Cuts a horizontal band into the segments left over once the openings are
## removed, plus a lintel spanning the head of each opening.
func _band_segments(x_start: float, x_end: float, y0: float, y1: float, openings: Array) -> Array:
	var out: Array = []
	var cuts: Array = []
	for opening in openings:
		var ox0: float = opening["x0"]
		var ox1: float = opening["x1"]
		if ox1 <= x_start or ox0 >= x_end:
			continue
		cuts.append([clampf(ox0, x_start, x_end), clampf(ox1, x_start, x_end), opening["top"]])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor: float = x_start
	for cut in cuts:
		var cx0: float = cut[0]
		var cx1: float = cut[1]
		var ctop: float = cut[2]
		if cx0 > cursor:
			out.append([cursor, cx0, y0, y1])
		var lintel_from: float = maxf(y0, ctop)
		if y1 - lintel_from > 0.05:
			out.append([cx0, cx1, lintel_from, y1])
		cursor = maxf(cursor, cx1)
	if cursor < x_end:
		out.append([cursor, x_end, y0, y1])
	return out

func _openings_for(wall_id: StringName, span: float) -> Array:
	var out: Array = []
	for opening in OPENINGS:
		if opening["wall"] != wall_id:
			continue
		var half_opening: float = float(opening["width"]) * 0.5
		var x0: float = float(opening["offset"]) - half_opening
		var x1: float = float(opening["offset"]) + half_opening
		if x0 <= -span or x1 >= span:
			continue
		out.append({"x0": x0, "x1": x1, "top": float(opening["top"])})
	return out

#endregion

#region Frame

func _build_columns() -> void:
	var count: int = maxi(wall_columns, 2)
	var height: float = wall_top - wall_bottom
	if height <= 0.1:
		return
	var mid_y: float = (wall_top + wall_bottom) * 0.5
	var size: Vector3 = Vector3(0.7, height, 0.7)
	var half_w: float = width * 0.5
	var half_l: float = length * 0.5
	for i in range(count):
		var t: float = float(i) / float(count - 1)
		var x: float = lerpf(-half_w, half_w, t)
		var z: float = lerpf(-half_l, half_l, t)
		_add_piece("Column_South", Transform3D(Basis(), Vector3(x, mid_y, -half_l)), size, &"steel")
		_add_piece("Column_North", Transform3D(Basis(), Vector3(x, mid_y, half_l)), size, &"steel")
		_add_piece("Column_West", Transform3D(Basis(), Vector3(-half_w, mid_y, z)), size, &"steel")
		_add_piece("Column_East", Transform3D(Basis(), Vector3(half_w, mid_y, z)), size, &"steel")

func _build_trusses() -> void:
	var ridge_y: float = _roof_underside(0.0)
	var girder_y: float = ridge_y - 0.45
	_add_piece("Roof_RidgeGirder", Transform3D(Basis(), Vector3(0.0, girder_y, 0.0)), Vector3(1.0, 0.7, length), &"beam")
	var column_top: float = girder_y - 0.35
	var column_height: float = column_top - wall_bottom
	var run: float = width * 0.5
	var y_wall: float = _roof_underside(run) - 0.3
	var y_ridge: float = ridge_y - 0.3
	var rise: float = y_ridge - y_wall
	var rafter_len: float = sqrt(run * run + rise * rise)
	var rafter_angle: float = atan2(rise, run)
	for z in _truss_positions():
		_add_piece("Truss_TieBeam", Transform3D(Basis(), Vector3(0.0, wall_top - 0.4, z)), Vector3(width, 0.45, 0.45), &"beam")
		for side: float in [-1.0, 1.0]:
			var center := Vector3(side * run * 0.5, (y_wall + y_ridge) * 0.5, z)
			var rafter_basis := Basis(Vector3.BACK, -side * rafter_angle)
			_add_piece("Truss_Rafter", Transform3D(rafter_basis, center), Vector3(rafter_len, 0.35, 0.35), &"beam")
		if column_height > 0.2:
			var center_y: float = (wall_bottom + column_top) * 0.5
			_add_piece("Column_Ridge", Transform3D(Basis(), Vector3(0.0, center_y, z)), Vector3(0.55, column_height, 0.55), &"steel")

func _truss_positions() -> PackedFloat32Array:
	var count: int = maxi(int(roundf(length / maxf(truss_spacing, 1.0))) + 1, 2)
	var out: PackedFloat32Array = PackedFloat32Array()
	for i in range(count):
		out.append(lerpf(-length * 0.5, length * 0.5, float(i) / float(count - 1)))
	return out

## Height of the underside of the roof directly above local X.
func _roof_underside(x: float) -> float:
	var half_span: float = width * 0.5 + roof_overhang
	var slope: float = roof_rise / half_span
	return wall_top + (half_span - absf(x)) * slope - roof_thickness * 0.5

#endregion

#region Roof

func _build_roof() -> void:
	var half_span: float = width * 0.5 + roof_overhang
	var slope_len: float = sqrt(half_span * half_span + roof_rise * roof_rise)
	var angle: float = atan2(roof_rise, half_span)
	var mid_y: float = wall_top + roof_rise * 0.5
	var depth: float = length + roof_overhang * 2.0
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * half_span * 0.5, mid_y, 0.0)
		var roof_basis := Basis(Vector3.BACK, -side * angle)
		_add_piece("Roof_Slope", Transform3D(roof_basis, center), Vector3(slope_len, roof_thickness, depth), &"roof")
		var eave := Vector3(side * (half_span - 0.25), wall_top - 0.35, 0.0)
		_add_piece("Roof_Eave", Transform3D(Basis(), eave), Vector3(0.5, 0.8, depth), &"steel")
	var ridge_cap := Vector3(0.0, wall_top + roof_rise + 0.1, 0.0)
	_add_piece("Roof_RidgeCap", Transform3D(Basis(), ridge_cap), Vector3(1.5, 0.5, depth), &"roof")

func _build_gables() -> void:
	var half_w: float = width * 0.5
	# The prism's sloped edge is matched to the underside of the roof, so the
	# gable closes against the roof without leaving a sliver of daylight.
	var base_y: float = _roof_underside(half_w)
	var gable_height: float = _roof_underside(0.0) - base_y
	if gable_height <= 0.1:
		return
	var half_t: float = wall_thickness * 0.5
	var prism := PrismMesh.new()
	prism.size = Vector3(width, gable_height, wall_thickness)
	prism.left_to_right = 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-half_w, -gable_height * 0.5, -half_t),
		Vector3(half_w, -gable_height * 0.5, -half_t),
		Vector3(0.0, gable_height * 0.5, -half_t),
		Vector3(-half_w, -gable_height * 0.5, half_t),
		Vector3(half_w, -gable_height * 0.5, half_t),
		Vector3(0.0, gable_height * 0.5, half_t),
	])
	for side: float in [-1.0, 1.0]:
		var center := Vector3(0.0, base_y + gable_height * 0.5, side * length * 0.5)
		_add_mesh_piece("Gable_End", prism, Transform3D(Basis(), center), &"steel", shape)

func _build_lights() -> void:
	var trusses: PackedFloat32Array = _truss_positions()
	if trusses.is_empty():
		return
	var rows: int = 4
	var housing_y: float = wall_top - 0.72
	# Hang the lamps off interior trusses only, so they clear the gable walls.
	var first_truss: int = 1 if trusses.size() > 2 else 0
	var last_truss: int = trusses.size() - 2 if trusses.size() > 2 else trusses.size() - 1
	for row in range(rows):
		var t: float = 0.0 if rows == 1 else float(row) / float(rows - 1)
		var index: int = clampi(int(roundf(lerpf(float(first_truss), float(last_truss), t))), 0, trusses.size() - 1)
		var z: float = trusses[index]
		for col in range(3):
			var x: float = lerpf(-width / 3.0, width / 3.0, float(col) * 0.5)
			_add_piece("Light_Housing", Transform3D(Basis(), Vector3(x, housing_y, z)), Vector3(0.5, 0.16, 0.5), &"steel")
			_add_piece("Light_Bulb", Transform3D(Basis(), Vector3(x, housing_y - 0.09, z)), Vector3(0.36, 0.04, 0.36), &"lamp")
			var spot := SpotLight3D.new()
			spot.name = _unique("Light_Spot")
			spot.light_color = Color(1.0, 0.97, 0.88)
			spot.light_energy = 6.0
			spot.shadow_enabled = work_light_shadows
			# Kept short and narrow so the unshadowed lamps cannot spill their
			# pools of light through the walls onto the ground outside.
			spot.spot_range = 14.0
			spot.spot_angle = 45.0
			spot.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(x, housing_y - 0.14, z))
			spot.add_to_group(GENERATED_GROUP)
			add_child(spot)

#endregion

#region Pieces

func _add_piece(base_name: String, xform: Transform3D, size: Vector3, material_key: StringName) -> void:
	if _visuals != null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = _unique(base_name)
		mesh_instance.mesh = _box_mesh(size)
		mesh_instance.material_override = _materials[material_key]
		mesh_instance.transform = xform
		mesh_instance.add_to_group(GENERATED_GROUP)
		_visuals.add_child(mesh_instance)
	if _structure != null:
		var collision := CollisionShape3D.new()
		collision.name = _unique(base_name + "_Shape")
		collision.shape = _box_shape(size)
		collision.transform = xform
		collision.add_to_group(GENERATED_GROUP)
		_structure.add_child(collision)

func _add_mesh_piece(base_name: String, mesh: Mesh, xform: Transform3D, material_key: StringName, shape: Shape3D) -> void:
	if _visuals != null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = _unique(base_name)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _materials[material_key]
		mesh_instance.transform = xform
		mesh_instance.add_to_group(GENERATED_GROUP)
		_visuals.add_child(mesh_instance)
	if _structure != null and shape != null:
		var collision := CollisionShape3D.new()
		collision.name = _unique(base_name + "_Shape")
		collision.shape = shape
		collision.transform = xform
		collision.add_to_group(GENERATED_GROUP)
		_structure.add_child(collision)

func _box_mesh(size: Vector3) -> BoxMesh:
	var key: Vector3 = size.snapped(Vector3(0.001, 0.001, 0.001))
	if not _mesh_cache.has(key):
		var mesh := BoxMesh.new()
		mesh.size = key
		_mesh_cache[key] = mesh
	return _mesh_cache[key]

func _box_shape(size: Vector3) -> BoxShape3D:
	var key: Vector3 = size.snapped(Vector3(0.001, 0.001, 0.001))
	if not _shape_cache.has(key):
		var shape := BoxShape3D.new()
		shape.size = key
		_shape_cache[key] = shape
	return _shape_cache[key]

func _unique(base_name: String) -> String:
	var candidate: String = base_name
	var index: int = 2
	while _used_names.has(candidate):
		candidate = "%s_%d" % [base_name, index]
		index += 1
	_used_names[candidate] = true
	return candidate

#endregion

#region Materials

func _make_materials() -> Dictionary:
	var out: Dictionary = {}
	out[&"concrete"] = _standard(Color(0.42, 0.43, 0.45), 0.0, 0.9)
	out[&"steel"] = _standard(Color(0.30, 0.32, 0.36), 0.8, 0.4)
	out[&"roof"] = _standard(Color(0.24, 0.26, 0.29), 0.7, 0.45)
	out[&"beam"] = _standard(Color(0.72, 0.36, 0.09), 0.6, 0.4)
	out[&"glass"] = _glass()
	out[&"lamp"] = _lamp()
	return out

func _standard(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _glass() -> StandardMaterial3D:
	var material: StandardMaterial3D = _standard(Color(0.66, 0.76, 0.86, 0.18), 0.85, 0.08)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _lamp() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.97, 0.85)
	return material

#endregion
