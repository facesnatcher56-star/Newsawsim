@tool
extends Node3D

## incline_log_deck.gd
## Chain-driven incline log deck with proper sprocket/chain/race geometry.
##
## Each track runs a full roller-chain loop:
##   top run (surface, +Z / uphill)  →  top sprocket wrap
##   → return run (under frame, -Z)  →  bottom sprocket wrap  →  repeat
##
## AnimatableBody3D lugs handle log physics.
## MeshInstance3D chain links handle visuals (animated in _process).

@export var incline_angle_deg: float = 22.0
@export var incline_length:    float = 5.0
@export var incline_width:     float = 2.4
@export var chain_speed:       float = 0.55
@export var lugs_per_track:    int   = 4
@export var lug_spacing:       float = 1.5
@export var track_x_positions: Array[float] = [-0.9, -0.3, 0.3, 0.9]
@export var running:           bool  = true

# ── Geometry constants ───────────────────────────────────────────────────────
const PLATE_T       := 0.12
const LUG_W         := 0.30
const LUG_H         := 0.25
const LUG_D         := 0.15
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

# ── Runtime state ────────────────────────────────────────────────────────────
var _slope_root:    Node3D

# Lugs (physics)
var _lugs:          Array[AnimatableBody3D] = []
var _lug_shapes:    Array[CollisionShape3D] = []
var _lug_track_x:   Array[float]            = []
var _slot:          Array[float]            = []
var _slot_visible:  Array[bool]             = []

# Chain links (visuals)
var _chain_nodes:   Array[Node3D]  = []
var _chain_tx:      Array[float]   = []
var _link_slot:     Array[float]   = []
var _chain_travel:  float          = 0.0

# Sprocket nodes (for rotation animation)
var _sprocket_nodes: Array[Node3D] = []

# Derived
var _cycle_len:  float
var _surface_y:  float
var _hidden_y:   float
var _spr_cy:     float   # sprocket centre Y in slope-local space
var _loop_len:   float   # full chain loop length per track


func _ready() -> void:
	_cycle_len = float(lugs_per_track) * lug_spacing
	_surface_y =  PLATE_T * 0.5 + LUG_H * 0.5
	_hidden_y  = -(PLATE_T * 0.5 + LUG_H * 0.5 + 0.06)
	_spr_cy    = PLATE_T * 0.5 - SPROCKET_R        # sprocket centre just below surface
	_loop_len  = 2.0 * incline_length + 2.0 * PI * SPROCKET_R

	_slope_root = Node3D.new()
	_slope_root.name = "SlopeRoot"
	_slope_root.rotation_degrees.x = -incline_angle_deg
	add_child(_slope_root)

	_build_frame()
	_spawn_chain_links()
	_update_chain_links()   # set initial positions in editor too
	_spawn_lugs()


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

	_slope_root.add_child(frame)


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
		shaft.position = Vector3(0.0, _spr_cy, ez)
		frame.add_child(shaft)

		# One sprocket assembly per track
		for si in range(track_x_positions.size()):
			var tx: float = track_x_positions[si]
			var sp_root := Node3D.new()
			sp_root.name = "Sprocket_%s_%d" % [suffix, si]
			sp_root.rotation_degrees.z = 90.0
			sp_root.position = Vector3(tx, _spr_cy, ez)
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
	var n_links := int(ceil(_loop_len / CHAIN_PITCH)) + 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.20, 0.23)
	mat.metallic     = 0.93
	mat.roughness    = 0.30

	# Shared meshes for all links
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(CHAIN_PLATE_W, CHAIN_PLATE_H, CHAIN_PLATE_D)

	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius    = CHAIN_ROLLER_R
	roller_mesh.bottom_radius = CHAIN_ROLLER_R
	roller_mesh.height        = CHAIN_SPAN + CHAIN_PLATE_W * 2.0 + 0.01
	roller_mesh.radial_segments = 6

	var inner_x := CHAIN_SPAN * 0.5 + CHAIN_PLATE_W * 0.5   # centre of side plate

	for xi in range(track_x_positions.size()):
		var tx: float = track_x_positions[xi]
		for j in range(n_links):
			var slot0 := float(j) * CHAIN_PITCH

			var link := Node3D.new()
			link.name = "ChainLink_%d_%d" % [xi, j]

			# Left side plate
			var lp := MeshInstance3D.new()
			lp.mesh = plate_mesh
			lp.material_override = mat
			lp.position = Vector3(-inner_x, 0.0, 0.0)
			link.add_child(lp)

			# Right side plate
			var rp := MeshInstance3D.new()
			rp.mesh = plate_mesh
			rp.material_override = mat
			rp.position = Vector3(inner_x, 0.0, 0.0)
			link.add_child(rp)

			# Cross roller/pin (oriented along X)
			var ro := MeshInstance3D.new()
			ro.mesh = roller_mesh
			ro.material_override = mat
			ro.rotation_degrees.z = 90.0
			link.add_child(ro)

			_slope_root.add_child(link)
			_chain_nodes.append(link)
			_chain_tx.append(tx)
			_link_slot.append(slot0)


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN LOOP PATH
# ─────────────────────────────────────────────────────────────────────────────

func _get_loop_xform(d: float) -> Transform3D:
	d = fposmod(d, _loop_len)

	var R    := SPROCKET_R
	var piR  := PI * R
	var L    := incline_length
	var half := L * 0.5
	var cy   := _spr_cy          # sprocket centre Y
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


func _update_chain_links() -> void:
	for i in range(_chain_nodes.size()):
		var slot := fposmod(_link_slot[i] + _chain_travel, _loop_len)
		var xf   := _get_loop_xform(slot)
		var node := _chain_nodes[i]
		node.position = Vector3(_chain_tx[i], xf.origin.y, xf.origin.z)
		node.basis    = xf.basis


# ─────────────────────────────────────────────────────────────────────────────
#  LUGS  (AnimatableBody3D — physics interaction)
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_lugs() -> void:
	var lug_mesh  := BoxMesh.new()
	lug_mesh.size = Vector3(LUG_W, LUG_H, LUG_D)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.30, 0.26)
	mat.metallic     = 0.88
	mat.roughness    = 0.42

	var lug_shape := BoxShape3D.new()
	lug_shape.size = Vector3(LUG_W, LUG_H, LUG_D)

	for xi in range(track_x_positions.size()):
		var tx: float = track_x_positions[xi]
		for j in range(lugs_per_track):
			var slot0 := float(j) * lug_spacing

			var lug      := AnimatableBody3D.new()
			lug.name     = "Lug_%d_%d" % [xi, j]
			lug.sync_to_physics = true

			var mi := MeshInstance3D.new()
			mi.mesh = lug_mesh
			mi.material_override = mat
			lug.add_child(mi)

			var cs    := CollisionShape3D.new()
			cs.shape  = lug_shape
			cs.disabled = slot0 >= incline_length
			lug.add_child(cs)

			_set_lug_position(lug, tx, slot0)
			_slope_root.add_child(lug)

			_lugs.append(lug)
			_lug_shapes.append(cs)
			_lug_track_x.append(tx)
			_slot.append(slot0)
			_slot_visible.append(slot0 < incline_length)


func _set_lug_position(lug: AnimatableBody3D, tx: float, slot: float) -> void:
	var half := incline_length * 0.5
	if slot < incline_length:
		lug.position = Vector3(tx, _surface_y, -half + slot)
	else:
		var t: float = (slot - incline_length) / maxf(_cycle_len - incline_length, 0.001)
		lug.position = Vector3(tx, _hidden_y, lerp(half, -half, t))


# ─────────────────────────────────────────────────────────────────────────────
#  LOOPS
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not running:
		return

	_chain_travel += chain_speed * delta
	_update_chain_links()

	# Spin sprockets: angular velocity matches chain surface speed
	var ang_vel := chain_speed / SPROCKET_R
	for sp in _sprocket_nodes:
		if is_instance_valid(sp):
			sp.rotate(Vector3.RIGHT, ang_vel * delta)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not running:
		return

	for i in range(_lugs.size()):
		_slot[i] = fmod(_slot[i] + chain_speed * delta, _cycle_len)

		var on_surface := _slot[i] < incline_length
		if on_surface != _slot_visible[i]:
			_lug_shapes[i].disabled = not on_surface
			_slot_visible[i] = on_surface

		_set_lug_position(_lugs[i], _lug_track_x[i], _slot[i])


func set_running(on: bool) -> void:
	running = on
