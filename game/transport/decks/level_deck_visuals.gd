@tool
class_name LevelDeckVisuals
extends Node3D

## level_deck_visuals.gd
## Procedural construction and animation for the level chain deck: frame
## (support tubes, races, cross beams, split legs, sprockets), retractable
## stoppers, pivoting ramp, and chain-link MultiMeshes. No game logic —
## level_chain_deck.gd sets the build parameters, calls build(), then drives
## the chain via advance_chain() / refresh_chain_links() and animates the
## exposed stopper/ramp/frame bodies itself.

# ── Geometry constants ───────────────────────────────────────────────────────
const DECK_SURFACE_Y := 0.06
const SPROCKET_R     := 0.15    # pitch-circle radius
const SPROCKET_T     := 0.045   # outer ring thickness (axial)
const SPROCKET_HUB_R := 0.055   # hub radius
const SPROCKET_HUB_T := 0.075   # hub length
const SPROCKET_SEGS  := 10      # polygon segments → gear silhouette

# Chain link assembly
const CHAIN_SPAN     := 0.10    # X gap between inner faces of side plates
const CHAIN_PLATE_W  := 0.014   # side plate X thickness
const CHAIN_PLATE_H  := 0.042   # side plate height
const CHAIN_PLATE_D  := 0.25    # side plate depth (along chain, slightly > pitch for overlap)
const CHAIN_ROLLER_R := 0.024   # cross-pin / roller radius
const CHAIN_PITCH    := 0.24    # centre-to-centre link spacing along chain

# Chain race (guide channel per track)
const RACE_WALL_T    := 0.010
const RACE_WALL_H    := 0.038

# Support Tube (HSS)
const TUBE_W         := 0.18
const TUBE_H         := 0.176

# ── Build parameters (set by the deck before build()) ────────────────────────
var deck_length:         float = 5.0
var track_x_positions:   Array[float] = []
var stopper_height:      float = 0.35
var floor_y:             float = -1.0
var stoppers_extended:   bool  = true
var ramp_enabled:        bool  = true
var ramp_lowered:        bool  = true
var ramp_length:         float = 1.2
var ramp_angle_down_deg: float = -20.0
var ramp_angle_up_deg:   float = 50.0

# ── Derived geometry & bodies (read by the deck) ─────────────────────────────
var spr_cy:      float   # sprocket centre Y
var loop_len:    float   # full chain loop length per track
var extended_y:  float   # stopper body Y when extended
var retracted_y: float   # stopper body Y when retracted

var frame_body:    StaticBody3D      # friction-drive surface (constant_linear_velocity)
var stoppers_body: AnimatableBody3D  # deck animates Y between extended_y/retracted_y
var ramp_body:     AnimatableBody3D  # deck animates X rotation between ramp angles

var _multimesh_plates: MultiMeshInstance3D
var _multimesh_rollers: MultiMeshInstance3D
var _num_links:      int   = 0
var _chain_travel:   float = 0.0
var _sprocket_nodes: Array[Node3D] = []


## (Re)build all procedural geometry from the current build parameters.
func build() -> void:
	spr_cy      = DECK_SURFACE_Y - SPROCKET_R
	loop_len    = 2.0 * deck_length + 2.0 * PI * SPROCKET_R
	extended_y  = DECK_SURFACE_Y + stopper_height * 0.5
	retracted_y = DECK_SURFACE_Y - stopper_height * 0.5 - 0.05

	# Clear any previous build (tool script rebuilds on export changes).
	_sprocket_nodes.clear()
	_num_links = 0
	frame_body = null
	stoppers_body = null
	ramp_body = null
	for child in get_children():
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()

	_build_frame()
	_build_stoppers()
	_build_pivot_ramp()
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
#  FRAME & PROCEDURAL MESHES
# ─────────────────────────────────────────────────────────────────────────────

func _build_frame() -> void:
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough    = false
	frame.physics_material_override = pm

	frame_body = frame

	_build_support_tubes(frame)
	_build_chain_races(frame)
	_build_cross_beams(frame)
	_build_split_legs(frame)
	_build_sprockets(frame)

	add_child(frame)


func _build_support_tubes(frame: StaticBody3D) -> void:
	var size := Vector3(TUBE_W, TUBE_H, deck_length)
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.28) # steel HSS
	mat.metallic     = 0.80
	mat.roughness    = 0.35

	for tx in track_x_positions:
		# Visual Tube
		var mi := MeshInstance3D.new()
		mi.name = "SupportTube_%.2f" % tx
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(tx, -0.052, 0.0)
		frame.add_child(mi)

		# Collision shape for log physics support
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		# Top of chain links is DECK_SURFACE_Y + CHAIN_PLATE_H * 0.5
		# Bottom of support tube is -0.052 - TUBE_H * 0.5
		var col_top := DECK_SURFACE_Y + CHAIN_PLATE_H * 0.5 + 0.015
		var col_bottom := -0.052 - TUBE_H * 0.5
		var col_h := col_top - col_bottom
		var col_y := col_bottom + col_h * 0.5
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
	var wall_y := DECK_SURFACE_Y - CHAIN_ROLLER_R + RACE_WALL_H * 0.5 # 0.055

	for tx in track_x_positions:
		for side in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.name = "Race_%.2f_%s" % [tx, ("L" if side < 0.0 else "R")]
			var bm := BoxMesh.new()
			bm.size = wall_size
			mi.mesh = bm
			mi.material_override = mat
			# Wall center: 0.07m from track center (provides 0.13m gap for 0.128m chain width)
			mi.position = Vector3(tx + side * 0.07, wall_y, 0.0)
			frame.add_child(mi)


func _build_cross_beams(frame: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.22, 0.23) # darker structural steel
	mat.metallic     = 0.80
	mat.roughness    = 0.40

	var max_tx: float = track_x_positions.max()
	# Width ends 5mm inside the outer face of the outermost support tubes to prevent texture popping
	var beam_w: float = (max_tx + TUBE_W * 0.5 - 0.005) * 2.0
	var beam_size := Vector3(beam_w, 0.08, 0.08)
	var beam_y := -0.052 # centered with support tubes

	var num_beams := int(ceil(deck_length / 1.0)) + 1
	# Skip the very ends to prevent clashing with shafts and sprockets
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

	# Leg columns go from Y = 0.0 down to floor_y
	var leg_h: float = abs(floor_y - 0.0)
	var leg_y: float = floor_y * 0.5
	var col_size := Vector3(0.04, leg_h, 0.06)

	for tx in track_x_positions:
		for end_z in [-deck_length * 0.5, deck_length * 0.5]:
			var suffix := "Bot" if end_z < 0.0 else "Top"
			
			# Left column
			var mi_l := MeshInstance3D.new()
			mi_l.name = "LegColumn_%.2f_%s_L" % [tx, suffix]
			var bm_l := BoxMesh.new()
			bm_l.size = col_size
			mi_l.mesh = bm_l
			mi_l.material_override = mat_leg
			mi_l.position = Vector3(tx - 0.10, leg_y, end_z)
			frame.add_child(mi_l)

			# Right column
			var mi_r := MeshInstance3D.new()
			mi_r.name = "LegColumn_%.2f_%s_R" % [tx, suffix]
			var bm_r := BoxMesh.new()
			bm_r.size = col_size
			mi_r.mesh = bm_r
			mi_r.material_override = mat_leg
			mi_r.position = Vector3(tx + 0.10, leg_y, end_z)
			frame.add_child(mi_r)

			# Bottom foot plate connecting the two columns on the floor
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

	# Drive shaft (ends 15mm inside the outermost leg column faces to prevent texture popping)
	var max_tx: float = track_x_positions.max()
	var shaft_h: float = (max_tx + 0.10 + 0.02 - 0.015) * 2.0

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius    = SPROCKET_HUB_R * 0.6
	shaft_mesh.bottom_radius = SPROCKET_HUB_R * 0.6
	shaft_mesh.height        = shaft_h

	for end_idx in range(2):
		var ez     := -deck_length * 0.5 if end_idx == 0 else deck_length * 0.5
		var suffix := "Bot" if end_idx == 0 else "Top"

		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = mat_hub
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, spr_cy, ez)
		frame.add_child(shaft)

		for si in range(track_x_positions.size()):
			var tx: float = track_x_positions[si]
			var sp_root := Node3D.new()
			sp_root.name = "Sprocket_%s_%d" % [suffix, si]
			sp_root.rotation_degrees.z = 90.0
			sp_root.position = Vector3(tx, spr_cy, ez)
			frame.add_child(sp_root)

			# Toothed ring
			var outer_mesh := CylinderMesh.new()
			outer_mesh.top_radius    = SPROCKET_R
			outer_mesh.bottom_radius = SPROCKET_R
			outer_mesh.height        = SPROCKET_T
			outer_mesh.radial_segments = SPROCKET_SEGS
			var outer := MeshInstance3D.new()
			outer.mesh = outer_mesh
			outer.material_override = mat_sp
			sp_root.add_child(outer)

			# Hub
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
#  RETRACTABLE STOPPERS
# ─────────────────────────────────────────────────────────────────────────────

func _build_stoppers() -> void:
	var mat_sleeve := StandardMaterial3D.new()
	mat_sleeve.albedo_color = Color(0.25, 0.27, 0.28) # same steel as HSS
	mat_sleeve.metallic     = 0.80
	mat_sleeve.roughness    = 0.35
	
	var sleeve_mesh := CylinderMesh.new()
	sleeve_mesh.top_radius    = 0.065
	sleeve_mesh.bottom_radius = 0.065
	sleeve_mesh.height        = 0.20
	sleeve_mesh.radial_segments = 12

	var sz := deck_length * 0.5 - 0.30

	if frame_body != null:
		for i in range(track_x_positions.size()):
			var tx: float = track_x_positions[i]
			var sleeve := MeshInstance3D.new()
			sleeve.name = "StopperSleeve_%d" % i
			sleeve.mesh = sleeve_mesh
			sleeve.material_override = mat_sleeve
			sleeve.position = Vector3(tx + 0.14, -0.06, sz)
			frame_body.add_child(sleeve)

	var stoppers := AnimatableBody3D.new()
	stoppers.name = "Stoppers"
	stoppers.sync_to_physics = true
	
	# Initial vertical position matches the state
	stoppers.position = Vector3(0.0, extended_y if stoppers_extended else retracted_y, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.05) # safety orange
	mat.metallic     = 0.50
	mat.roughness    = 0.40

	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius    = 0.05
	cyl_mesh.bottom_radius = 0.05
	cyl_mesh.height        = stopper_height
	cyl_mesh.radial_segments = 12

	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.05
	cyl_shape.height = stopper_height

	for i in range(track_x_positions.size()):
		var tx: float = track_x_positions[i]
		
		# Visual (offset to the side of the chain race)
		var mi := MeshInstance3D.new()
		mi.name = "StopperVisual_%d" % i
		mi.mesh = cyl_mesh
		mi.material_override = mat
		mi.position = Vector3(tx + 0.14, 0.0, sz)
		stoppers.add_child(mi)

		# Collision Shape (offset to the side of the chain race)
		var col := CollisionShape3D.new()
		col.name = "StopperCollision_%d" % i
		col.shape = cyl_shape
		col.position = Vector3(tx + 0.14, 0.0, sz)
		stoppers.add_child(col)

	stoppers_body = stoppers
	add_child(stoppers)


func _build_pivot_ramp() -> void:
	if not ramp_enabled:
		return
	var ramp := AnimatableBody3D.new()
	ramp.name = "PivotingRamp"
	ramp.sync_to_physics = true
	
	# Low friction physics material for smooth sliding
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15
	pm.rough    = false
	ramp.physics_material_override = pm
	
	# Position at the infeed drive shaft axis (opposite end to stops)
	# Shaft Y is spr_cy = -0.09. Shaft Z is -deck_length * 0.5.
	ramp.position = Vector3(0.0, spr_cy, -deck_length * 0.5)
	
	# Initial rotation
	var target_rot = ramp_angle_down_deg if ramp_lowered else ramp_angle_up_deg
	ramp.rotation_degrees.x = target_rot

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.28) # steel HSS
	mat.metallic     = 0.80
	mat.roughness    = 0.35

	# Tubes run in between each chain:
	# Since chains are at tx = [-0.9, -0.3, 0.3, 0.9], the gaps are at x = [-0.6, 0.0, 0.6]
	var gap_x_positions: Array[float] = []
	for i in range(track_x_positions.size() - 1):
		gap_x_positions.append((track_x_positions[i] + track_x_positions[i + 1]) * 0.5)

	# We offset the ramp geometry vertically so that the top surface of the ramp
	# aligns flush with the deck surface (Y = 0.06) when horizontal.
	# Pivot shaft is at Y = -0.09, tube radius is 0.04.
	# To make top surface at Y = 0.06: Y_local = 0.06 - (-0.09) - 0.04 = 0.11
	const RAMP_Y_OFFSET := 0.11

	# Straight tubes: radius = 0.04m, height = ramp_length
	var straight_mesh := CylinderMesh.new()
	straight_mesh.top_radius = 0.04
	straight_mesh.bottom_radius = 0.04
	straight_mesh.height = ramp_length
	straight_mesh.radial_segments = 12

	var straight_shape := CylinderShape3D.new()
	straight_shape.radius = 0.04
	straight_shape.height = ramp_length

	for i in range(gap_x_positions.size()):
		var gx: float = gap_x_positions[i]
		
		# Visual straight tube (extends along local -Z axis)
		var mi := MeshInstance3D.new()
		mi.name = "StraightTube_%d" % i
		mi.mesh = straight_mesh
		mi.material_override = mat
		# Oriented along Z axis: CylinderMesh is vertical along Y by default, so rotate 90 deg around X.
		# To extend from Z=0 to Z=-ramp_length, place center at local Z = -ramp_length * 0.5.
		mi.position = Vector3(gx, RAMP_Y_OFFSET, -ramp_length * 0.5)
		mi.rotation_degrees = Vector3(90, 0, 0)
		ramp.add_child(mi)

		# Collision Shape
		var col := CollisionShape3D.new()
		col.name = "StraightCollision_%d" % i
		col.shape = straight_shape
		col.position = Vector3(gx, RAMP_Y_OFFSET, -ramp_length * 0.5)
		col.rotation_degrees = Vector3(90, 0, 0)
		ramp.add_child(col)

	# Cross tube at the end (Z = -ramp_length).
	# Runs X flush with the outermost edges of the first and last straight tubes.
	# Outermost straight tubes are at -0.6 and 0.6. Outer edges are at -0.64 and 0.64.
	# So total length along X is exactly 1.28m.
	var min_gx: float = gap_x_positions.min()
	var max_gx: float = gap_x_positions.max()
	var cross_w: float = max_gx - min_gx + 0.08 # 1.28m
	
	var cross_mesh := CylinderMesh.new()
	cross_mesh.top_radius = 0.04
	cross_mesh.bottom_radius = 0.04
	cross_mesh.height = cross_w
	cross_mesh.radial_segments = 12

	var cross_shape := CylinderShape3D.new()
	cross_shape.radius = 0.04
	cross_shape.height = cross_w

	# Visual cross tube (oriented along X axis, so rotate 90 deg around Z)
	var mi_cross := MeshInstance3D.new()
	mi_cross.name = "CrossTube"
	mi_cross.mesh = cross_mesh
	mi_cross.material_override = mat
	mi_cross.position = Vector3(0.0, RAMP_Y_OFFSET, -ramp_length)
	mi_cross.rotation_degrees = Vector3(0, 0, 90)
	ramp.add_child(mi_cross)

	# Collision Shape for cross tube
	var col_cross := CollisionShape3D.new()
	col_cross.name = "CrossCollision"
	col_cross.shape = cross_shape
	col_cross.position = Vector3(0.0, RAMP_Y_OFFSET, -ramp_length)
	col_cross.rotation_degrees = Vector3(0, 0, 90)
	ramp.add_child(col_cross)

	ramp_body = ramp
	add_child(ramp)


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN LINKS
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_chain_links() -> void:
	_num_links = int(ceil(loop_len / CHAIN_PITCH)) + 2
	var num_tracks := track_x_positions.size()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.20) # dark oily steel
	mat.metallic     = 0.93
	mat.roughness    = 0.35

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
	_multimesh_plates.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_multimesh_rollers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_rollers)


func _get_loop_xform(d: float) -> Transform3D:
	d = fposmod(d, loop_len)

	var R     := SPROCKET_R
	var piR   := PI * R
	var L     := deck_length
	var half  := L * 0.5
	var cy    := spr_cy
	var top_y := DECK_SURFACE_Y
	var bot_y := cy - R

	var y: float
	var z: float
	var rot_x: float

	if d < L:
		# Top run: +Z direction
		z     = -half + d
		y     = top_y
		rot_x = 0.0
	elif d < L + piR:
		# Top sprocket wrap
		var theta := (d - L) / R
		z     = half  + R * sin(theta)
		y     = cy    + R * cos(theta)
		rot_x = theta - TAU
	elif d < 2.0 * L + piR:
		# Return run: -Z direction
		var d_ret := d - (L + piR)
		z     = half - d_ret
		y     = bot_y
		rot_x = -PI
	else:
		# Bottom sprocket wrap
		var theta := (d - (2.0 * L + piR)) / R
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
