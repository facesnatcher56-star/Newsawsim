@tool
extends Node3D

## simple_chain_deck.gd
## Horizontal (level) chain deck — same frame, chains, sprockets, legs, and zones
## as level_chain_deck.gd, but without retractable stoppers or pivoting ramp.

@export var deck_length:       float = 5.0
@export var deck_width:        float = 3.9
@export var chain_speed:       float = 0.55
@export var chain_accel_speed: float = 2.0
@export var track_x_positions: Array[float] = [-2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
@export var running:           bool  = false
@export var reverse_direction: bool  = false
@export var floor_y:           float = -1.0
@export var external_stop:     bool  = false

@export_group("Lugs")
@export var lugs_enabled:      bool = false
@export_range(0, 64, 1) var lug_count: int = 6
@export var lug_radius:        float = 0.07
@export var lug_height:        float = 0.34
@export var lug_height_offset: float = 0.075
@export var lug_color:         Color = Color.WHITE
@export var lug_plate_size:    Vector3 = Vector3(0.22, 0.035, 0.22)
@export var lug_plate_color:   Color = Color(0.62, 0.62, 0.58)

@export_group("Zones")
@export var load_zone_position: Vector3 = Vector3(0.0, 0.35, -1.8)
@export var load_zone_size:     Vector3 = Vector3(3.9, 0.7, 0.35)
@export var top_zone_position:  Vector3 = Vector3(0.0, 0.4, 2.3)
@export var top_zone_size:      Vector3 = Vector3(3.9, 0.8, 0.5)
@export var deck_area_position: Vector3 = Vector3(0.0, 0.5, 0.0)
@export var deck_area_size:     Vector3 = Vector3(4.3, 1.2, 5.15)
@export_group("")

## Reference to the headrig carriage to check for backpressure.
@export var carriage: AnimatableBody3D
## Maximum logs the deck can carry simultaneously before it's considered full.
@export var max_logs_on_deck:  int   = 2

## Assign an Area3D in the scene for the bottom trigger (visible/movable in editor).
@export var load_zone: Area3D
## Assign an Area3D in the scene for the top trigger (visible/movable in editor).
@export var top_zone: Area3D
## Assign an Area3D in the scene for the deck tracking (visible/movable in editor).
@export var deck_area: Area3D

signal log_reached_top(l_node: RigidBody3D)

# ── Geometry constants ───────────────────────────────────────────────────────
const DECK_SURFACE_Y := 0.06
const SPROCKET_R     := 0.15
const SPROCKET_T     := 0.045
const SPROCKET_HUB_R := 0.055
const SPROCKET_HUB_T := 0.075
const SPROCKET_SEGS  := 10

# Chain link assembly
const CHAIN_SPAN     := 0.10
const CHAIN_PLATE_W  := 0.014
const CHAIN_PLATE_H  := 0.042
const CHAIN_PLATE_D  := 0.25
const CHAIN_ROLLER_R := 0.024
const CHAIN_PITCH    := 0.24

# Chain race (guide channel per track)
const RACE_WALL_T    := 0.010
const RACE_WALL_H    := 0.038

# Support Tube (HSS)
const TUBE_W         := 0.18
const TUBE_H         := 0.176

# ── Runtime state ────────────────────────────────────────────────────────────
var _start_delay_timer: float = 0.0
var _deck_root:      Node3D
var _active_log:     RigidBody3D
var _on_deck:        Dictionary = {}

# Chain links (visuals)
var _multimesh_plates: MultiMeshInstance3D
var _multimesh_rollers: MultiMeshInstance3D
var _num_links:      int            = 0
var _chain_travel:   float          = 0.0
var _current_chain_speed: float      = 0.0

# Lugs (physics)
var _lugs_nodes:     Array[AnimatableBody3D] = []
var _lugs_track_x:   Array[float]            = []
var _lugs_link_index: Array[int]              = []

# Sprocket nodes (for rotation animation)
var _sprocket_nodes: Array[Node3D] = []

# Derived
var _spr_cy:      float
var _loop_len:    float
var _editor_build_signature: String = ""

# Frame node reference (to control constant_linear_velocity)
var _frame_body:     StaticBody3D


func _ready() -> void:
	_spr_cy    = DECK_SURFACE_Y - SPROCKET_R
	_loop_len  = 2.0 * deck_length + 2.0 * PI * SPROCKET_R

	if _deck_root == null:
		_deck_root = get_node_or_null("DeckRoot")

	if _deck_root == null:
		_deck_root = Node3D.new()
		_deck_root.name = "DeckRoot"
		add_child(_deck_root)
		if Engine.is_editor_hint():
			_deck_root.owner = get_tree().edited_scene_root

	_clear_procedural_nodes()

	_build_frame()
	_spawn_chain_links()
	_update_chain_links()

	# Resolve zones
	load_zone = _deck_root.get_node_or_null("LoadZone")
	top_zone = _deck_root.get_node_or_null("TopZone")
	deck_area = _deck_root.get_node_or_null("DeckArea")
	_configure_zones()
	_editor_build_signature = _make_editor_build_signature()

	if Engine.is_editor_hint():
		_setup_editor_labels()
	else:
		_hide_editor_labels()

	if not Engine.is_editor_hint():
		if not is_instance_valid(carriage):
			var found := get_tree().get_nodes_in_group("headrig_carriage")
			if found.size() > 0:
				carriage = found[0] as AnimatableBody3D

		running = false
		if load_zone != null:
			if not load_zone.body_entered.is_connected(_on_load_zone_body_entered):
				load_zone.body_entered.connect(_on_load_zone_body_entered)
		if top_zone != null:
			if not top_zone.body_entered.is_connected(_on_top_zone_body_entered):
				top_zone.body_entered.connect(_on_top_zone_body_entered)
			if not top_zone.body_exited.is_connected(_on_top_zone_body_exited):
				top_zone.body_exited.connect(_on_top_zone_body_exited)
		if deck_area != null:
			if not deck_area.body_entered.is_connected(_on_deck_area_body_entered):
				deck_area.body_entered.connect(_on_deck_area_body_entered)
			if not deck_area.body_exited.is_connected(_on_deck_area_body_exited):
				deck_area.body_exited.connect(_on_deck_area_body_exited)


func _clear_procedural_nodes() -> void:
	_sprocket_nodes.clear()
	_num_links = 0
	_lugs_nodes.clear()
	_lugs_track_x.clear()
	_lugs_link_index.clear()
	_frame_body = null

	if _deck_root != null:
		if _deck_root.has_node("Frame"):
			var f := _deck_root.get_node("Frame")
			if Engine.is_editor_hint():
				_deck_root.remove_child(f)
			f.queue_free()

		for child in _deck_root.get_children():
			if child.name.begins_with("ChainLink_") or child.name.begins_with("Lug_") or child is MultiMeshInstance3D:
				if Engine.is_editor_hint():
					_deck_root.remove_child(child)
				child.queue_free()


# ─────────────────────────────────────────────────────────────────────────────
#  FRAME & PROCEDURAL MESHES
# ─────────────────────────────────────────────────────────────────────────────

func _configure_zones() -> void:
	load_zone = _configure_zone("LoadZone", load_zone_position, load_zone_size)
	top_zone = _configure_zone("TopZone", top_zone_position, top_zone_size)
	deck_area = _configure_zone("DeckArea", deck_area_position, deck_area_size)


func _configure_zone(zone_name: String, zone_position: Vector3, zone_size: Vector3) -> Area3D:
	if _deck_root == null:
		return null

	var zone: Area3D = _deck_root.get_node_or_null(zone_name) as Area3D
	if zone == null:
		zone = Area3D.new()
		zone.name = zone_name
		_deck_root.add_child(zone)
		if Engine.is_editor_hint():
			zone.owner = get_tree().edited_scene_root

	zone.position = zone_position

	var col: CollisionShape3D = zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		zone.add_child(col)
		if Engine.is_editor_hint():
			col.owner = get_tree().edited_scene_root

	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(zone_size.x, 0.01),
		maxf(zone_size.y, 0.01),
		maxf(zone_size.z, 0.01)
	)
	col.shape = shape
	col.position = Vector3.ZERO
	col.rotation = Vector3.ZERO
	col.scale = Vector3.ONE

	return zone


func _make_editor_build_signature() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		deck_length,
		floor_y,
		track_x_positions,
		lugs_enabled,
		lug_count,
		lug_radius,
		lug_height,
		lug_height_offset,
		lug_color,
		lug_plate_size,
		lug_plate_color,
		deck_width
	]


func _rebuild_deck_geometry() -> void:
	_spr_cy = DECK_SURFACE_Y - SPROCKET_R
	_loop_len = 2.0 * deck_length + 2.0 * PI * SPROCKET_R
	_clear_procedural_nodes()
	_build_frame()
	_spawn_chain_links()
	_update_chain_links()


func _build_frame() -> void:
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough    = false
	frame.physics_material_override = pm

	_frame_body = frame

	_build_support_tubes(frame)
	_build_chain_races(frame)
	_build_cross_beams(frame)
	_build_split_legs(frame)
	_build_sprockets(frame)

	_deck_root.add_child(frame)


func _build_support_tubes(frame: StaticBody3D) -> void:
	var size := Vector3(TUBE_W, TUBE_H, deck_length)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.28)
	mat.metallic     = 0.80
	mat.roughness    = 0.35

	for tx in track_x_positions:
		var mi := MeshInstance3D.new()
		mi.name = "SupportTube_%.2f" % tx
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(tx, -0.052, 0.0)
		frame.add_child(mi)

		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var col_top  := DECK_SURFACE_Y + CHAIN_PLATE_H * 0.5 + 0.015
		var col_bottom := -0.052 - TUBE_H * 0.5
		var col_h   := col_top - col_bottom
		var col_y   := col_bottom + col_h * 0.5
		bs.size = Vector3(TUBE_W, col_h, deck_length)
		col.shape = bs
		col.position = Vector3(tx, col_y, 0.0)
		frame.add_child(col)


func _build_chain_races(frame: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.26)
	mat.metallic     = 0.85
	mat.roughness    = 0.42

	var wall_size := Vector3(RACE_WALL_T, RACE_WALL_H, deck_length)
	var wall_y := DECK_SURFACE_Y - CHAIN_ROLLER_R + RACE_WALL_H * 0.5

	for tx in track_x_positions:
		for side in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.name = "Race_%.2f_%s" % [tx, ("L" if side < 0.0 else "R")]
			var bm := BoxMesh.new()
			bm.size = wall_size
			mi.mesh = bm
			mi.material_override = mat
			mi.position = Vector3(tx + side * 0.07, wall_y, 0.0)
			frame.add_child(mi)


func _build_cross_beams(frame: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.22, 0.23)
	mat.metallic     = 0.80
	mat.roughness    = 0.40

	var max_tx: float = track_x_positions.max()
	var beam_w: float = (max_tx + TUBE_W * 0.5 - 0.005) * 2.0
	var beam_size := Vector3(beam_w, 0.08, 0.08)
	var beam_y := -0.052

	var num_beams := int(ceil(deck_length / 1.0)) + 1
	for i in range(1, num_beams - 1):
		var cz := -deck_length * 0.5 + i * (deck_length / (num_beams - 1))
		var mi := MeshInstance3D.new()
		mi.name = "CrossBeam_%d" % i
		var bm := BoxMesh.new()
		bm.size = beam_size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0.0, beam_y, cz)
		frame.add_child(mi)


func _build_split_legs(frame: StaticBody3D) -> void:
	var mat_leg := StandardMaterial3D.new()
	mat_leg.albedo_color = Color(0.20, 0.20, 0.22)
	mat_leg.metallic     = 0.78
	mat_leg.roughness    = 0.45

	var mat_foot := StandardMaterial3D.new()
	mat_foot.albedo_color = Color(0.14, 0.14, 0.15)
	mat_foot.metallic     = 0.85
	mat_foot.roughness    = 0.35

	var leg_h: float = abs(floor_y - 0.0)
	var leg_y: float = floor_y * 0.5
	var col_size := Vector3(0.04, leg_h, 0.06)

	for tx in track_x_positions:
		for end_z in [-deck_length * 0.5, deck_length * 0.5]:
			var suffix: String = "Bot" if end_z < 0.0 else "Top"

			var mi_l := MeshInstance3D.new()
			mi_l.name = "LegColumn_%.2f_%s_L" % [tx, suffix]
			var bm_l := BoxMesh.new()
			bm_l.size = col_size
			mi_l.mesh = bm_l
			mi_l.material_override = mat_leg
			mi_l.position = Vector3(tx - 0.10, leg_y, end_z)
			frame.add_child(mi_l)

			var mi_r := MeshInstance3D.new()
			mi_r.name = "LegColumn_%.2f_%s_R" % [tx, suffix]
			var bm_r := BoxMesh.new()
			bm_r.size = col_size
			mi_r.mesh = bm_r
			mi_r.material_override = mat_leg
			mi_r.position = Vector3(tx + 0.10, leg_y, end_z)
			frame.add_child(mi_r)

			var mi_foot := MeshInstance3D.new()
			mi_foot.name = "LegFoot_%.2f_%s" % [tx, suffix]
			var bm_foot := BoxMesh.new()
			bm_foot.size = Vector3(0.32, 0.02, 0.12)
			mi_foot.mesh = bm_foot
			mi_foot.material_override = mat_foot
			mi_foot.position = Vector3(tx, floor_y + 0.01, end_z)
			frame.add_child(mi_foot)


func _build_sprockets(frame: StaticBody3D) -> void:
	var mat_sp := StandardMaterial3D.new()
	mat_sp.albedo_color = Color(0.30, 0.30, 0.32)
	mat_sp.metallic     = 0.90
	mat_sp.roughness    = 0.30

	var mat_hub := StandardMaterial3D.new()
	mat_hub.albedo_color = Color(0.38, 0.38, 0.40)
	mat_hub.metallic     = 0.88
	mat_hub.roughness    = 0.35

	var max_tx: float = track_x_positions.max()
	var shaft_h: float = (max_tx + 0.10 + 0.02 - 0.015) * 2.0

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius    = SPROCKET_HUB_R * 0.6
	shaft_mesh.bottom_radius = SPROCKET_HUB_R * 0.6
	shaft_mesh.height        = shaft_h

	for end_idx in range(2):
		var ez     := -deck_length * 0.5 if end_idx == 0 else deck_length * 0.5
		var suffix: String = "Bot" if end_idx == 0 else "Top"

		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = mat_hub
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, _spr_cy, ez)
		frame.add_child(shaft)

		for si in range(track_x_positions.size()):
			var tx: float = track_x_positions[si]
			var sp_root := Node3D.new()
			sp_root.name = "Sprocket_%s_%d" % [suffix, si]
			sp_root.rotation_degrees.z = 90.0
			sp_root.position = Vector3(tx, _spr_cy, ez)
			frame.add_child(sp_root)

			var outer_mesh := CylinderMesh.new()
			outer_mesh.top_radius    = SPROCKET_R
			outer_mesh.bottom_radius = SPROCKET_R
			outer_mesh.height        = SPROCKET_T
			outer_mesh.radial_segments = SPROCKET_SEGS
			var outer := MeshInstance3D.new()
			outer.mesh = outer_mesh
			outer.material_override = mat_sp
			sp_root.add_child(outer)

			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius    = SPROCKET_HUB_R
			hub_mesh.bottom_radius = SPROCKET_HUB_R
			hub_mesh.height        = SPROCKET_HUB_T
			hub_mesh.radial_segments = 8
			var hub := MeshInstance3D.new()
			hub.mesh = hub_mesh
			hub.material_override = mat_hub
			sp_root.add_child(hub)

			_sprocket_nodes.append(sp_root)


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN LINKS
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_chain_links() -> void:
	_num_links = int(ceil(_loop_len / CHAIN_PITCH)) + 2
	var num_tracks := track_x_positions.size()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.20)
	mat.metallic     = 0.93
	mat.roughness    = 0.35

	# Clean up any existing MultiMesh or Lug nodes
	for child in _deck_root.get_children():
		if child.name.begins_with("ChainLink_") or child.name.begins_with("Lug_") or child is MultiMeshInstance3D:
			if Engine.is_editor_hint():
				_deck_root.remove_child(child)
			child.queue_free()

	_lugs_nodes.clear()
	_lugs_track_x.clear()
	_lugs_link_index.clear()

	# 1. Plates MultiMesh
	_multimesh_plates = MultiMeshInstance3D.new()
	_multimesh_plates.name = "PlatesMultiMesh"
	var mm_plates := MultiMesh.new()
	mm_plates.transform_format = MultiMesh.TRANSFORM_3D
	mm_plates.use_custom_data = false
	mm_plates.use_colors = false
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(CHAIN_PLATE_W, CHAIN_PLATE_H, CHAIN_PLATE_D)
	mm_plates.mesh = plate_mesh
	mm_plates.instance_count = _num_links * num_tracks * 2
	_multimesh_plates.multimesh = mm_plates
	_multimesh_plates.material_override = mat
	_deck_root.add_child(_multimesh_plates)

	# 2. Rollers MultiMesh
	_multimesh_rollers = MultiMeshInstance3D.new()
	_multimesh_rollers.name = "RollersMultiMesh"
	var mm_rollers := MultiMesh.new()
	mm_rollers.transform_format = MultiMesh.TRANSFORM_3D
	mm_rollers.use_custom_data = false
	mm_rollers.use_colors = false
	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius    = CHAIN_ROLLER_R
	roller_mesh.bottom_radius = CHAIN_ROLLER_R
	roller_mesh.height        = CHAIN_SPAN + CHAIN_PLATE_W * 2.0 + 0.01
	roller_mesh.radial_segments = 6
	mm_rollers.mesh = roller_mesh
	mm_rollers.instance_count = _num_links * num_tracks
	_multimesh_rollers.multimesh = mm_rollers
	_multimesh_rollers.material_override = mat
	_deck_root.add_child(_multimesh_rollers)

	var lug_mat := StandardMaterial3D.new()
	lug_mat.albedo_color = lug_color
	lug_mat.metallic     = 0.0
	lug_mat.roughness    = 0.28

	var lug_plate_mat := StandardMaterial3D.new()
	lug_plate_mat.albedo_color = lug_plate_color
	lug_plate_mat.metallic     = 0.85
	lug_plate_mat.roughness    = 0.32

	var lug_plate_mesh := BoxMesh.new()
	lug_plate_mesh.size = Vector3(
		maxf(lug_plate_size.x, 0.01),
		maxf(lug_plate_size.y, 0.005),
		maxf(lug_plate_size.z, 0.01)
	)

	var lug_plate_shape := BoxShape3D.new()
	lug_plate_shape.size = lug_plate_mesh.size

	var lug_mesh := CylinderMesh.new()
	lug_mesh.top_radius = lug_radius
	lug_mesh.bottom_radius = lug_radius
	lug_mesh.height = lug_height
	lug_mesh.radial_segments = 16

	var lug_shape := CapsuleShape3D.new()
	lug_shape.radius = lug_radius
	lug_shape.height = maxf(lug_height, lug_radius * 2.0)

	for xi in range(track_x_positions.size()):
		var tx: float = track_x_positions[xi]
		for j in range(_num_links):
			if _should_link_have_lug(j, _num_links):
				var lug_body := AnimatableBody3D.new()
				lug_body.name = "Lug_%d_%d" % [xi, j]
				lug_body.sync_to_physics = true
				_add_lug_to_link(lug_body, lug_mesh, lug_shape, lug_mat, lug_plate_mesh, lug_plate_shape, lug_plate_mat)
				_deck_root.add_child(lug_body)
				
				_lugs_nodes.append(lug_body)
				_lugs_track_x.append(tx)
				_lugs_link_index.append(j)

	_update_chain_links()


func _should_link_have_lug(link_index: int, n_links: int) -> bool:
	if not lugs_enabled or lug_count <= 0:
		return false

	var top_spacing: float = deck_length / float(lug_count)
	if top_spacing <= 0.01:
		return false

	var loop_lug_count: int = maxi(1, int(round(_loop_len / top_spacing)))
	for lug_index in range(loop_lug_count):
		var target_slot: float = float(lug_index) * top_spacing
		var target_index: int = int(round(target_slot / CHAIN_PITCH)) % n_links
		if link_index == target_index:
			return true
	return false


func _add_lug_to_link(
	link: AnimatableBody3D,
	lug_mesh: Mesh,
	lug_shape: Shape3D,
	lug_mat: Material,
	lug_plate_mesh: Mesh,
	lug_plate_shape: Shape3D,
	lug_plate_mat: Material
) -> void:
	var plate_y: float = lug_height_offset + lug_plate_size.y * 0.5
	var lug_y: float = lug_height_offset + lug_plate_size.y + lug_height * 0.5

	var plate := MeshInstance3D.new()
	plate.name = "LugBasePlate"
	plate.mesh = lug_plate_mesh
	plate.material_override = lug_plate_mat
	plate.position = Vector3(0.0, plate_y, 0.0)
	link.add_child(plate)

	var mi := MeshInstance3D.new()
	mi.name = "LugMesh"
	mi.mesh = lug_mesh
	mi.material_override = lug_mat
	mi.position = Vector3(0.0, lug_y, 0.0)
	link.add_child(mi)

	var plate_col := CollisionShape3D.new()
	plate_col.name = "LugBasePlateCollision"
	plate_col.shape = lug_plate_shape.duplicate()
	plate_col.position = Vector3(0.0, plate_y, 0.0)
	link.add_child(plate_col)

	var col := CollisionShape3D.new()
	col.name = "LugCollision"
	col.shape = lug_shape.duplicate()
	col.position = Vector3(0.0, lug_y, 0.0)
	link.add_child(col)


func _get_loop_xform(d: float) -> Transform3D:
	d = fposmod(d, _loop_len)

	var R     := SPROCKET_R
	var piR   := PI * R
	var L     := deck_length
	var half  := L * 0.5
	var cy    := _spr_cy
	var top_y := DECK_SURFACE_Y
	var bot_y := cy - R

	var y: float
	var z: float
	var rot_x: float

	if d < L:
		z     = -half + d
		y     = top_y
		rot_x = 0.0
	elif d < L + piR:
		var theta := (d - L) / R
		z     = half  + R * sin(theta)
		y     = cy    + R * cos(theta)
		rot_x = theta - TAU
	elif d < 2.0 * L + piR:
		var d_ret := d - (L + piR)
		z     = half - d_ret
		y     = bot_y
		rot_x = -PI
	else:
		var theta := (d - (2.0 * L + piR)) / R
		z     = -half - R * sin(theta)
		y     = cy    - R * cos(theta)
		rot_x = theta - PI

	return Transform3D(Basis(Vector3.RIGHT, rot_x), Vector3(0.0, y, z))


func _update_chain_links() -> void:
	if not is_instance_valid(_multimesh_plates) or not is_instance_valid(_multimesh_rollers):
		return
	var num_tracks := track_x_positions.size()
	var inner_x := CHAIN_SPAN * 0.5 + CHAIN_PLATE_W * 0.5
	
	var plate_idx := 0
	var roller_idx := 0
	
	for xi in num_tracks:
		var tx := track_x_positions[xi]
		for j in _num_links:
			var slot := fposmod(float(j) * CHAIN_PITCH + _chain_travel, _loop_len)
			var xf   := _get_loop_xform(slot)
			var link_pos := Vector3(tx, xf.origin.y, xf.origin.z)
			var link_xf := Transform3D(xf.basis, link_pos)
			
			# Left Plate
			var lp_xf := link_xf * Transform3D(Basis(), Vector3(-inner_x, 0.0, 0.0))
			_multimesh_plates.multimesh.set_instance_transform(plate_idx, lp_xf)
			plate_idx += 1
			
			# Right Plate
			var rp_xf := link_xf * Transform3D(Basis(), Vector3(inner_x, 0.0, 0.0))
			_multimesh_plates.multimesh.set_instance_transform(plate_idx, rp_xf)
			plate_idx += 1
			
			# Joint Roller
			var ro_xf := link_xf * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3.ZERO)
			_multimesh_rollers.multimesh.set_instance_transform(roller_idx, ro_xf)
			roller_idx += 1

	# Now update separate physical lug bodies
	for i in range(_lugs_nodes.size()):
		var lug_body := _lugs_nodes[i]
		if is_instance_valid(lug_body):
			var tx := _lugs_track_x[i]
			var j := _lugs_link_index[i]
			var slot := fposmod(float(j) * CHAIN_PITCH + _chain_travel, _loop_len)
			var xf   := _get_loop_xform(slot)
			var local_xform: Transform3D = Transform3D(xf.basis, Vector3(tx, xf.origin.y, xf.origin.z))
			lug_body.global_transform = _deck_root.global_transform * local_xform
			
			# Set constant velocity to push objects like CutBoard
			var local_velocity := Vector3(0.0, 0.0, _current_chain_speed)
			var global_velocity := _deck_root.global_transform.basis * local_velocity
			lug_body.constant_linear_velocity = global_velocity


# ─────────────────────────────────────────────────────────────────────────────
#  LOOPS & PHYSICS
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_configure_zones()
		var build_signature := _make_editor_build_signature()
		if build_signature != _editor_build_signature:
			_editor_build_signature = build_signature
			_rebuild_deck_geometry()
			_setup_editor_labels()
		return

	if _start_delay_timer > 0.0:
		_start_delay_timer -= delta
		if _start_delay_timer <= 0.0:
			set_running(true)

	var blocked_now := is_blocked_at_top()
	if not running:
		if not _on_deck.is_empty() and not blocked_now:
			set_running(true)

		if _start_delay_timer <= 0.0 and not blocked_now:
			if load_zone != null:
				var items_in_load_zone := false
				for body in load_zone.get_overlapping_bodies():
					if _is_log_or_board(body) and body is RigidBody3D:
						items_in_load_zone = true
						_active_log = body as RigidBody3D
						break
				if items_in_load_zone:
					_start_delay_timer = 2.0
		return

	if blocked_now:
		_update_chain_links()
		return

	_update_chain_links()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var blocked_now := is_blocked_at_top()
	var dir_sign: float = -1.0 if reverse_direction else 1.0
	var target_speed: float = chain_speed * dir_sign if (running and not blocked_now) else 0.0
	_current_chain_speed = move_toward(_current_chain_speed, target_speed, max(chain_accel_speed, 0.0) * delta)

	if is_instance_valid(_frame_body):
		var vel := Vector3(0.0, 0.0, _current_chain_speed)
		_frame_body.constant_linear_velocity = Vector3.ZERO if lugs_enabled else global_transform.basis * vel

	if abs(_current_chain_speed) <= 0.0001:
		return

	var advance := _current_chain_speed * delta
	_chain_travel += advance

	var ang_vel := advance / SPROCKET_R
	for sp in _sprocket_nodes:
		if is_instance_valid(sp):
			sp.rotate(Vector3.RIGHT, ang_vel)


# ─────────────────────────────────────────────────────────────────────────────
#  API & TRIGGER LOGIC
# ─────────────────────────────────────────────────────────────────────────────

func _get_carriage() -> AnimatableBody3D:
	if not is_instance_valid(carriage):
		if not Engine.is_editor_hint():
			var found := get_tree().get_nodes_in_group("headrig_carriage")
			if found.size() > 0:
				carriage = found[0] as AnimatableBody3D
	return carriage


func _is_headrig_free() -> bool:
	var carriage_ref = _get_carriage()
	if not is_instance_valid(carriage_ref):
		return true
	if not ("clamped_log" in carriage_ref) or not ("current_progress" in carriage_ref):
		return true
	return (carriage_ref.clamped_log == null) and ((carriage_ref.current_progress as float) < 0.01)


func set_running(on: bool, _force: bool = false) -> void:
	running = on
	if on:
		for l_node: RigidBody3D in _on_deck.values():
			if is_instance_valid(l_node):
				l_node.freeze = false
				l_node.axis_lock_angular_y = true
				l_node.axis_lock_angular_z = true
				l_node.axis_lock_linear_x = true
	else:
		for l_node: RigidBody3D in _on_deck.values():
			if is_instance_valid(l_node):
				l_node.freeze = true

	if is_instance_valid(_frame_body):
		var blocked_now := is_blocked_at_top()
		var vel: Vector3 = Vector3(0.0, 0.0, _current_chain_speed if (running and not blocked_now) else 0.0)
		_frame_body.constant_linear_velocity = Vector3.ZERO if lugs_enabled else global_transform.basis * vel


func _unlock_log(l_node: RigidBody3D) -> void:
	l_node.freeze = false
	l_node.axis_lock_angular_y = false
	l_node.axis_lock_angular_z = false
	l_node.axis_lock_linear_x = false


func has_room() -> bool:
	return true


func is_blocked_at_top() -> bool:
	if not external_stop:
		return false
	if top_zone == null:
		return false
	for body in top_zone.get_overlapping_bodies():
		if _is_log_or_board(body):
			return true
	return false


func _on_deck_area_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body) and body is RigidBody3D:
		var l_node: RigidBody3D = body as RigidBody3D
		_on_deck[l_node.get_instance_id()] = l_node
		if running:
			l_node.freeze = false
			l_node.axis_lock_angular_y = true
			l_node.axis_lock_angular_z = true
			l_node.axis_lock_linear_x = true


func _on_deck_area_body_exited(body: Node3D) -> void:
	if _is_log_or_board(body):
		_on_deck.erase(body.get_instance_id())


func _on_load_zone_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body):
		if not running and _start_delay_timer <= 0.0:
			_active_log = body as RigidBody3D
			_start_delay_timer = 2.0


func _on_top_zone_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body):
		var l_node: RigidBody3D = body as RigidBody3D
		_unlock_log(l_node)
		if _active_log == l_node:
			_active_log = null
		log_reached_top.emit(l_node)


func _on_top_zone_body_exited(body: Node3D) -> void:
	if _is_log_or_board(body):
		_on_deck.erase(body.get_instance_id())


func _is_log_or_board(body: Node) -> bool:
	if not is_instance_valid(body):
		return false
	return body.is_in_group("logs") or body.is_in_group("cut_boards")


func _setup_editor_labels() -> void:
	var zones = {
		"LoadZone": "Load Zone",
		"TopZone": "Top Zone",
		"DeckArea": "Deck Area"
	}
	if _deck_root == null:
		return
	for zone_name in zones:
		var zone = _deck_root.get_node_or_null(zone_name)
		if zone != null:
			var label = zone.get_node_or_null("EditorLabel") as Label3D
			if label == null:
				label = Label3D.new()
				label.name = "EditorLabel"
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.double_sided = false
				label.font_size = 48
				label.outline_size = 10
				label.position = Vector3(0, 0.5, 0)
				label.modulate = Color(0.0, 0.7, 1.0)
				zone.add_child(label)
			label.text = zones[zone_name]


func _hide_editor_labels() -> void:
	if _deck_root == null:
		return
	for zone_name in ["LoadZone", "TopZone", "DeckArea"]:
		var zone = _deck_root.get_node_or_null(zone_name)
		if zone != null:
			var label = zone.get_node_or_null("EditorLabel")
			if label != null:
				label.hide()
