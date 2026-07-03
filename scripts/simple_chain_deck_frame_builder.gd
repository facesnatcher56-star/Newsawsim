@tool
extends RefCounted

const DECK_SURFACE_Y := 0.06
const SPROCKET_R := 0.15
const SPROCKET_T := 0.045
const SPROCKET_HUB_R := 0.055
const SPROCKET_HUB_T := 0.075
const SPROCKET_SEGS := 10
const CHAIN_PLATE_H := 0.042
const CHAIN_ROLLER_R := 0.024
const RACE_WALL_T := 0.010
const RACE_WALL_H := 0.038
const TUBE_W := 0.18
const TUBE_H := 0.176

var _deck_length: float = 0.0
var _floor_y: float = 0.0
var _spr_cy: float = 0.0
var _track_x_positions: Array[float] = []
var _sprocket_nodes: Array[Node3D] = []


func build_frame(
	deck_length: float,
	floor_y: float,
	sprocket_center_y: float,
	track_x_positions: Array[float]
) -> Dictionary:
	_deck_length = deck_length
	_floor_y = floor_y
	_spr_cy = sprocket_center_y
	_track_x_positions.clear()
	_track_x_positions.assign(track_x_positions)
	_sprocket_nodes.clear()

	var frame := StaticBody3D.new()
	frame.name = "Frame"
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = false
	frame.physics_material_override = pm

	_build_support_tubes(frame)
	_build_chain_races(frame)
	_build_cross_beams(frame)
	_build_split_legs(frame)
	_build_sprockets(frame)

	return {
		"frame": frame,
		"sprockets": _sprocket_nodes.duplicate()
	}


func _build_support_tubes(frame: StaticBody3D) -> void:
	var size := Vector3(TUBE_W, TUBE_H, _deck_length)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.28)
	mat.metallic = 0.80
	mat.roughness = 0.35

	for tx in _track_x_positions:
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
		var col_top: float = DECK_SURFACE_Y + CHAIN_PLATE_H * 0.5 + 0.015
		var col_bottom: float = -0.052 - TUBE_H * 0.5
		var col_h: float = col_top - col_bottom
		var col_y: float = col_bottom + col_h * 0.5
		bs.size = Vector3(TUBE_W, col_h, _deck_length)
		col.shape = bs
		col.position = Vector3(tx, col_y, 0.0)
		frame.add_child(col)


func _build_chain_races(frame: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.26)
	mat.metallic = 0.85
	mat.roughness = 0.42

	var wall_size := Vector3(RACE_WALL_T, RACE_WALL_H, _deck_length)
	var wall_y: float = DECK_SURFACE_Y - CHAIN_ROLLER_R + RACE_WALL_H * 0.5

	for tx in _track_x_positions:
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
	mat.metallic = 0.80
	mat.roughness = 0.40

	var max_tx: float = _track_x_positions.max()
	var beam_w: float = (max_tx + TUBE_W * 0.5 - 0.005) * 2.0
	var beam_size := Vector3(beam_w, 0.08, 0.08)
	var beam_y := -0.052

	var num_beams := int(ceil(_deck_length / 1.0)) + 1
	for i in range(1, num_beams - 1):
		var cz: float = -_deck_length * 0.5 + i * (_deck_length / (num_beams - 1))
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
	mat_leg.metallic = 0.78
	mat_leg.roughness = 0.45

	var mat_foot := StandardMaterial3D.new()
	mat_foot.albedo_color = Color(0.14, 0.14, 0.15)
	mat_foot.metallic = 0.85
	mat_foot.roughness = 0.35

	var leg_h: float = abs(_floor_y - 0.0)
	var leg_y: float = _floor_y * 0.5
	var col_size := Vector3(0.04, leg_h, 0.06)

	for tx in _track_x_positions:
		for end_z in [-_deck_length * 0.5, _deck_length * 0.5]:
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
			mi_foot.position = Vector3(tx, _floor_y + 0.01, end_z)
			frame.add_child(mi_foot)


func _build_sprockets(frame: StaticBody3D) -> void:
	var mat_sp := StandardMaterial3D.new()
	mat_sp.albedo_color = Color(0.30, 0.30, 0.32)
	mat_sp.metallic = 0.90
	mat_sp.roughness = 0.30

	var mat_hub := StandardMaterial3D.new()
	mat_hub.albedo_color = Color(0.38, 0.38, 0.40)
	mat_hub.metallic = 0.88
	mat_hub.roughness = 0.35

	var max_tx: float = _track_x_positions.max()
	var shaft_h: float = (max_tx + 0.10 + 0.02 - 0.015) * 2.0

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = SPROCKET_HUB_R * 0.6
	shaft_mesh.bottom_radius = SPROCKET_HUB_R * 0.6
	shaft_mesh.height = shaft_h

	for end_idx in range(2):
		var ez: float = -_deck_length * 0.5 if end_idx == 0 else _deck_length * 0.5
		var suffix: String = "Bot" if end_idx == 0 else "Top"

		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = mat_hub
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, _spr_cy, ez)
		frame.add_child(shaft)

		for si in range(_track_x_positions.size()):
			var tx: float = _track_x_positions[si]
			var sp_root := Node3D.new()
			sp_root.name = "Sprocket_%s_%d" % [suffix, si]
			sp_root.rotation_degrees.z = 90.0
			sp_root.position = Vector3(tx, _spr_cy, ez)
			frame.add_child(sp_root)

			var outer_mesh := CylinderMesh.new()
			outer_mesh.top_radius = SPROCKET_R
			outer_mesh.bottom_radius = SPROCKET_R
			outer_mesh.height = SPROCKET_T
			outer_mesh.radial_segments = SPROCKET_SEGS
			var outer := MeshInstance3D.new()
			outer.mesh = outer_mesh
			outer.material_override = mat_sp
			sp_root.add_child(outer)

			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = SPROCKET_HUB_R
			hub_mesh.bottom_radius = SPROCKET_HUB_R
			hub_mesh.height = SPROCKET_HUB_T
			hub_mesh.radial_segments = 8
			var hub := MeshInstance3D.new()
			hub.mesh = hub_mesh
			hub.material_override = mat_hub
			sp_root.add_child(hub)

			_sprocket_nodes.append(sp_root)
