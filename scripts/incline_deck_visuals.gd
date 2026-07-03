@tool
class_name InclineDeckVisuals
extends Node3D

## incline_deck_visuals.gd
## Procedural construction and animation for the incline log deck:
## static frame (meshes + bed/rail collision), sprockets, chain-link
## MultiMeshes, and lug pusher meshes. No game logic — incline_log_deck.gd
## drives it via build(), advance_chain() and refresh_chain_links().

# ── Geometry constants ───────────────────────────────────────────────────────
const PLATE_T       := 0.12
const LUG_W         := 0.125
const LUG_H         := 0.27
const LUG_BASE_H    := 0.055
const LUG_BASE_D    := 0.27
const LUG_POST_W    := 0.11
const LUG_POST_D    := 0.11
const RAIL_T        := 0.06
const RAIL_H        := 0.22
const STRINGER_W    := 0.08
const STRINGER_H    := 0.18

# Sprocket
const SPROCKET_R    := 0.15    # pitch-circle radius
const SPROCKET_T    := 0.045   # outer ring thickness (axial)
const SPROCKET_HUB_R:= 0.055   # hub radius
const SPROCKET_HUB_T:= 0.075   # hub length
const SPROCKET_SEGS := 10      # polygon segments → gear silhouette

# Chain link assembly
const CHAIN_SPAN    := 0.10    # X gap between inner faces of side plates
const CHAIN_PLATE_W := 0.014   # side plate X thickness
const CHAIN_PLATE_H := 0.042   # side plate height
const CHAIN_PLATE_D := 0.195   # side plate depth (along chain, < pitch)
const CHAIN_ROLLER_R:= 0.024   # cross-pin / roller radius
const CHAIN_PITCH   := 0.24    # centre-to-centre link spacing along chain

# Chain race (guide channel per track)
const RACE_WALL_T   := 0.010
const RACE_WALL_H   := 0.038

# ── Build parameters (set by build()) ────────────────────────────────────────
var incline_length: float = 5.0
var incline_width:  float = 5.2
var track_x_positions: Array[float] = []

# ── Derived geometry (read by the deck for lug placement) ────────────────────
var surface_y: float
var hidden_y:  float
var spr_cy:    float   # sprocket centre Y in slope-local space
var loop_len:  float   # full chain loop length per track

var _multimesh_plates: MultiMeshInstance3D
var _multimesh_rollers: MultiMeshInstance3D
var _num_links:      int   = 0
var _chain_travel:   float = 0.0
var _sprocket_nodes: Array[Node3D] = []
var _lug_material:   StandardMaterial3D


## (Re)build all procedural geometry from the deck's exports.
func build(p_incline_length: float, p_incline_width: float, p_track_x_positions: Array[float]) -> void:
	incline_length = p_incline_length
	incline_width  = p_incline_width
	track_x_positions = p_track_x_positions

	surface_y = PLATE_T * 0.5
	hidden_y  = -(PLATE_T * 0.5 + LUG_H + LUG_BASE_H + 0.08)
	spr_cy    = PLATE_T * 0.5 - SPROCKET_R        # sprocket centre just below surface
	loop_len  = 2.0 * incline_length + 2.0 * PI * SPROCKET_R

	# Clear any previous build (tool script re-runs in the editor).
	_sprocket_nodes.clear()
	for child in get_children():
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()

	_build_frame()
	_spawn_chain_links()
	refresh_chain_links()


## Advance the chain by a distance in metres and spin the sprockets to match.
func advance_chain(dist: float) -> void:
	_chain_travel += dist
	var ang := dist / SPROCKET_R
	for sp in _sprocket_nodes:
		if is_instance_valid(sp):
			sp.rotate(Vector3.RIGHT, ang)


# ─────────────────────────────────────────────────────────────────────────────
#  FRAME
# ─────────────────────────────────────────────────────────────────────────────

func _build_frame() -> void:
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	var pm := PhysicsMaterial.new()
	pm.friction = 1.8
	pm.rough    = true
	frame.physics_material_override = pm

	_build_bed(frame)
	_build_side_rails(frame)
	_build_chain_races(frame)
	_build_subframe(frame)
	_build_sprockets(frame)

	add_child(frame)


func _build_bed(frame: StaticBody3D) -> void:
	var size := Vector3(incline_width, PLATE_T, incline_length)
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.40, 0.22)
	mat.metallic     = 0.65
	mat.roughness    = 0.50

	var mi  := MeshInstance3D.new()
	mi.name = "BedPlate"
	var bm  := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	frame.add_child(mi)

	var col := CollisionShape3D.new()
	var bs  := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	frame.add_child(col)


func _build_side_rails(frame: StaticBody3D) -> void:
	var mat       := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.25)
	mat.metallic     = 0.82
	mat.roughness    = 0.44
	var rail_size := Vector3(RAIL_T, RAIL_H, incline_length)
	var rail_y    := PLATE_T * 0.5 + RAIL_H * 0.5

	for side: float in [-1.0, 1.0]:
		var rx := side * (incline_width * 0.5 + RAIL_T * 0.5)
		var mi  := MeshInstance3D.new()
		mi.name = "SideRail_%s" % ("L" if side < 0.0 else "R")
		var bm  := BoxMesh.new()
		bm.size = rail_size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(rx, rail_y, 0.0)
		frame.add_child(mi)

		var col  := CollisionShape3D.new()
		var bs   := BoxShape3D.new()
		bs.size  = rail_size
		col.shape    = bs
		col.position = Vector3(rx, rail_y, 0.0)
		frame.add_child(col)


func _build_chain_races(frame: StaticBody3D) -> void:
	# Per-track U-channel guides that constrain the chain laterally.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.26)
	mat.metallic     = 0.85
	mat.roughness    = 0.42

	var wall_y    := PLATE_T * 0.5 + RACE_WALL_H * 0.5
	var wall_size := Vector3(RACE_WALL_T, RACE_WALL_H, incline_length)
	var half_span := CHAIN_SPAN * 0.5 + CHAIN_PLATE_W + RACE_WALL_T * 0.5

	for tx: float in track_x_positions:
		for side: float in [-1.0, 1.0]:
			var mi  := MeshInstance3D.new()
			mi.name = "Race_%s_%s" % [tx, ("L" if side < 0.0 else "R")]
			var bm  := BoxMesh.new()
			bm.size = wall_size
			mi.mesh = bm
			mi.material_override = mat
			mi.position = Vector3(tx + side * half_span, wall_y, 0.0)
			frame.add_child(mi)


func _build_subframe(frame: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.20, 0.22)
	mat.metallic     = 0.78
	mat.roughness    = 0.55
	var sy := -(PLATE_T * 0.5 + STRINGER_H * 0.5)

	for side: float in [-1.0, 1.0]:
		var sx  := side * (incline_width * 0.5 - STRINGER_W * 0.5 - 0.04)
		var mi  := MeshInstance3D.new()
		mi.name = "Stringer_%s" % ("L" if side < 0.0 else "R")
		var bm  := BoxMesh.new()
		bm.size = Vector3(STRINGER_W, STRINGER_H, incline_length)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(sx, sy, 0.0)
		frame.add_child(mi)

	var count := int(ceil(incline_length / 0.9)) + 1
	for i in range(count):
		var cz := -incline_length * 0.5 + i * 0.9
		if cz > incline_length * 0.5 + 0.01:
			break
		var mi  := MeshInstance3D.new()
		mi.name = "Cross_%d" % i
		var bm  := BoxMesh.new()
		bm.size = Vector3(incline_width + 0.08, STRINGER_H * 0.55, 0.055)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0.0, sy + STRINGER_H * 0.22, cz)
		frame.add_child(mi)


func _build_sprockets(frame: StaticBody3D) -> void:
	var mat_sp := StandardMaterial3D.new()
	mat_sp.albedo_color = Color(0.28, 0.26, 0.24)
	mat_sp.metallic     = 0.90
	mat_sp.roughness    = 0.38

	var mat_hub := StandardMaterial3D.new()
	mat_hub.albedo_color = Color(0.35, 0.32, 0.28)
	mat_hub.metallic     = 0.88
	mat_hub.roughness    = 0.42

	# Drive shaft (one per end, spans full width)
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius    = SPROCKET_HUB_R * 0.6
	shaft_mesh.bottom_radius = SPROCKET_HUB_R * 0.6
	shaft_mesh.height        = incline_width + 0.30

	for end_idx in range(2):
		var ez     := -incline_length * 0.5 if end_idx == 0 else incline_length * 0.5
		var suffix := "Bot" if end_idx == 0 else "Top"

		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = mat_hub
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, spr_cy, ez)
		frame.add_child(shaft)

		# One sprocket assembly per track
		for si in range(track_x_positions.size()):
			var tx: float = track_x_positions[si]
			var sp_root := Node3D.new()
			sp_root.name = "Sprocket_%s_%d" % [suffix, si]
			sp_root.rotation_degrees.z = 90.0
			sp_root.position = Vector3(tx, spr_cy, ez)
			frame.add_child(sp_root)

			# Outer toothed ring (polygon silhouette)
			var outer_mesh := CylinderMesh.new()
			outer_mesh.top_radius    = SPROCKET_R
			outer_mesh.bottom_radius = SPROCKET_R
			outer_mesh.height        = SPROCKET_T
			outer_mesh.radial_segments = SPROCKET_SEGS
			var outer := MeshInstance3D.new()
			outer.mesh = outer_mesh
			outer.material_override = mat_sp
			sp_root.add_child(outer)

			# Inner hub boss
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
	_num_links = int(ceil(loop_len / CHAIN_PITCH)) + 2
	var num_tracks := track_x_positions.size()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.20, 0.23)
	mat.metallic     = 0.93
	mat.roughness    = 0.30

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
	add_child(_multimesh_plates)

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
	add_child(_multimesh_rollers)


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN LOOP PATH
# ─────────────────────────────────────────────────────────────────────────────

func _get_loop_xform(d: float) -> Transform3D:
	d = fposmod(d, loop_len)

	var R    := SPROCKET_R
	var piR  := PI * R
	var L    := incline_length
	var half := L * 0.5
	var cy   := spr_cy           # sprocket centre Y
	var top_y := cy + R          # chain top-run Y  (≈ bed surface)
	var bot_y := cy - R          # chain return-run Y (below frame)

	var y: float
	var z: float
	var rot_x: float

	if d < L:
		# Top run: +Z (uphill)
		z     = -half + d
		y     = top_y
		rot_x = 0.0
	elif d < L + piR:
		# Top sprocket wrap
		var theta: float = (d - L) / R
		z     = half  + R * sin(theta)
		y     = cy    + R * cos(theta)
		rot_x = theta - TAU
	elif d < 2.0 * L + piR:
		# Return run: -Z (back under frame)
		var d_ret: float = d - (L + piR)
		z     = half - d_ret
		y     = bot_y
		rot_x = -PI
	else:
		# Bottom sprocket wrap
		var theta: float = (d - (2.0 * L + piR)) / R
		z     = -half - R * sin(theta)
		y     = cy    - R * cos(theta)
		rot_x = theta - PI

	return Transform3D(Basis(Vector3.RIGHT, rot_x), Vector3(0.0, y, z))


## Re-place every chain-link instance along the loop at the current travel.
func refresh_chain_links() -> void:
	if not is_instance_valid(_multimesh_plates) or not is_instance_valid(_multimesh_rollers):
		return
	var num_tracks := track_x_positions.size()
	var inner_x := CHAIN_SPAN * 0.5 + CHAIN_PLATE_W * 0.5

	var plate_idx := 0
	var roller_idx := 0

	for xi in num_tracks:
		var tx := track_x_positions[xi]
		for j in _num_links:
			var slot := fposmod(float(j) * CHAIN_PITCH + _chain_travel, loop_len)
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


# ─────────────────────────────────────────────────────────────────────────────
#  LUG VISUALS
# ─────────────────────────────────────────────────────────────────────────────

## Attach the fabricated pusher meshes to a lug body. Visuals only —
## the deck owns the lug's collision shape.
func build_lug_visuals(lug: Node3D) -> void:
	if _lug_material == null:
		_lug_material = StandardMaterial3D.new()
		_lug_material.albedo_color = Color(0.105, 0.10, 0.09)
		_lug_material.metallic     = 0.82
		_lug_material.roughness    = 0.58

	var visuals := Node3D.new()
	visuals.name = "FabricatedPusher"
	lug.add_child(visuals)

	# Wide chain shoe and heel plate anchor the pusher to the moving chain.
	_add_lug_box(visuals, "ChainShoe", Vector3(LUG_W, LUG_BASE_H, LUG_BASE_D),
		Vector3(0.0, LUG_BASE_H * 0.5, -0.045), Vector3.ZERO)
	_add_lug_box(visuals, "HeelPlate", Vector3(LUG_W * 0.90, 0.07, 0.09),
		Vector3(0.0, 0.065, -0.125), Vector3.ZERO)

	# Broad upright face contacts the log. It sits toward uphill travel (+Z).
	_add_lug_box(visuals, "PusherPost", Vector3(LUG_POST_W, LUG_H, LUG_POST_D),
		Vector3(0.0, LUG_BASE_H + LUG_H * 0.5, 0.055), Vector3.ZERO)
	# Two trailing braces give the lug the triangular, fabricated profile.
	var brace_angle := deg_to_rad(32.0)
	for brace_x in [-0.035, 0.035]:
		_add_lug_box(visuals, "RearBrace", Vector3(0.025, 0.225, 0.055),
			Vector3(brace_x, 0.145, -0.04), Vector3(brace_angle, 0.0, 0.0))


func _add_lug_box(
	parent: Node3D,
	part_name: String,
	size: Vector3,
	part_position: Vector3,
	part_rotation: Vector3
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = _lug_material
	part.position = part_position
	part.rotation = part_rotation
	parent.add_child(part)
