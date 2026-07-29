@tool
extends RefCounted

## Builds the static framework of the Lumber Bin Sorter:
## - Industrial Green structural steel gantry columns and cross beams.
## - Overhead catwalk with Safety Yellow handrails and access ladder.
## - Elevated drag chain guide channels & drive motor housing.
## - Open-Frame Gravity Collection Bin Hoppers with Z-Beam attached Cradle, 2 Slender X-Extending Tapered L-Forks, & Floor Clearance Tunnel.
## Uses high-performance MeshInstance3D nodes (Zero CSG overhead).

var sorter: Node


func _init(p_sorter: Node) -> void:
	sorter = p_sorter


func build_all() -> void:
	_build_support_gantry()
	_build_catwalk_and_handrails()
	_build_overhead_track_channels()
	_build_infeed_return_shaft()
	_build_bin_hoppers()
	_build_floor_haul_out_conveyor()
	_build_drive_motors()
	_build_building_lights()


func _get_track_positions() -> Array[float]:
	var bin_d: float = sorter.bin_depth
	var usable_depth: float = bin_d - 1.2
	var step_z: float = usable_depth / 4.0
	var track_positions: Array[float] = []
	for c_idx in range(5):
		track_positions.append(-usable_depth * 0.5 + c_idx * step_z)
	return track_positions


func _make_box(p_name: String, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.material_override = mat
	return mi


func _make_cylinder(p_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.material_override = mat
	return mi


func _make_smooth_curved_fork_mesh(p_name: String, arm_len: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	mi.position = pos
	mi.material_override = mat

	var arr_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments: int = 20
	var P0 := Vector2(0.0, 0.0)
	var P1 := Vector2(arm_len * 0.20, -0.06)
	var P2 := Vector2(arm_len * 0.60, -0.10)
	var P3 := Vector2(arm_len, -0.11)

	var ring_verts: Array = []

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var inv_t: float = 1.0 - t
		var pt_2d: Vector2 = inv_t * inv_t * inv_t * P0 + 3.0 * inv_t * inv_t * t * P1 + 3.0 * inv_t * (t * t) * P2 + (t * t * t) * P3

		var d1: Vector2 = 3.0 * inv_t * inv_t * (P1 - P0) + 6.0 * inv_t * t * (P2 - P1) + 3.0 * (t * t) * (P3 - P2)
		var tang_2d: Vector2 = d1.normalized()
		var norm_2d := Vector2(-tang_2d.y, tang_2d.x)

		var w: float = 0.14
		var h: float = lerp(0.14, 0.08, t)

		var center := Vector3(pt_2d.x, pt_2d.y, 0.0)
		var norm_3d := Vector3(norm_2d.x, norm_2d.y, 0.0)
		var binorm_3d := Vector3(0.0, 0.0, 1.0)

		var r_top_r: Vector3 = center + norm_3d * (h * 0.5) + binorm_3d * (w * 0.5)
		var r_top_l: Vector3 = center + norm_3d * (h * 0.5) - binorm_3d * (w * 0.5)
		var r_bot_l: Vector3 = center - norm_3d * (h * 0.5) - binorm_3d * (w * 0.5)
		var r_bot_r: Vector3 = center - norm_3d * (h * 0.5) + binorm_3d * (w * 0.5)

		ring_verts.append([r_top_r, r_top_l, r_bot_l, r_bot_r])

	for i in range(segments):
		var ring0: Array = ring_verts[i]
		var ring1: Array = ring_verts[i + 1]

		var tr0: Vector3 = ring0[0]
		var tl0: Vector3 = ring0[1]
		var bl0: Vector3 = ring0[2]
		var br0: Vector3 = ring0[3]

		var tr1: Vector3 = ring1[0]
		var tl1: Vector3 = ring1[1]
		var bl1: Vector3 = ring1[2]
		var br1: Vector3 = ring1[3]

		# Top Face (+Y)
		st.add_vertex(tr0)
		st.add_vertex(tl0)
		st.add_vertex(tr1)
		st.add_vertex(tl0)
		st.add_vertex(tl1)
		st.add_vertex(tr1)

		# Left Face (-Z)
		st.add_vertex(tl0)
		st.add_vertex(bl0)
		st.add_vertex(tl1)
		st.add_vertex(bl0)
		st.add_vertex(bl1)
		st.add_vertex(tl1)

		# Bottom Face (-Y)
		st.add_vertex(bl0)
		st.add_vertex(br0)
		st.add_vertex(bl1)
		st.add_vertex(br0)
		st.add_vertex(br1)
		st.add_vertex(bl1)

		# Right Face (+Z)
		st.add_vertex(br0)
		st.add_vertex(tr0)
		st.add_vertex(br1)
		st.add_vertex(tr0)
		st.add_vertex(tr1)
		st.add_vertex(br1)

	# Heel Cap (-X)
	var h_tr: Vector3 = ring_verts[0][0]
	var h_tl: Vector3 = ring_verts[0][1]
	var h_bl: Vector3 = ring_verts[0][2]
	var h_br: Vector3 = ring_verts[0][3]
	st.add_vertex(h_tr)
	st.add_vertex(h_bl)
	st.add_vertex(h_tl)
	st.add_vertex(h_tr)
	st.add_vertex(h_br)
	st.add_vertex(h_bl)

	# Tip Cap (+X)
	var t_ring: Array = ring_verts[segments]
	var t_tr: Vector3 = t_ring[0]
	var t_tl: Vector3 = t_ring[1]
	var t_bl: Vector3 = t_ring[2]
	var t_br: Vector3 = t_ring[3]
	st.add_vertex(t_tr)
	st.add_vertex(t_tl)
	st.add_vertex(t_bl)
	st.add_vertex(t_tr)
	st.add_vertex(t_bl)
	st.add_vertex(t_br)

	st.generate_normals()
	st.commit(arr_mesh)
	mi.mesh = arr_mesh
	return mi


func _add_box_col(parent: Node, name: String, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	col.name = name
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	if rot != Vector3.ZERO:
		col.rotation = rot
	parent.add_child(col)
	return col


func _build_floor_haul_out_conveyor() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	var haul_out := AnimatableBody3D.new()
	haul_out.name = "FloorHaulOutConveyor"
	haul_out.position = Vector3(total_length * 0.5 - 0.5, 0.20, 0.0)
	haul_out.sync_to_physics = true

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]

		var bed := _make_box("ConveyorBedChannel_T%d" % t_idx, Vector3(total_length, 0.14, 0.16), Vector3(0.0, 0.0, track_z), sorter._mat_green)
		haul_out.add_child(bed)

		var chain_strand := _make_box("FloorChainStrand_T%d" % t_idx, Vector3(total_length, 0.04, 0.06), Vector3(0.0, 0.08, track_z), sorter._mat_dark_steel)
		haul_out.add_child(chain_strand)

	var beam_count: int = num_bins + 1
	for b in range(beam_count):
		var bx: float = b * bin_w - (total_length * 0.5 - 0.5)
		var cross_beam := _make_box("FloorConveyorCrossBeam_%d" % b, Vector3(0.16, 0.16, bin_d - 0.4), Vector3(bx, -0.02, 0.0), sorter._mat_green)
		haul_out.add_child(cross_beam)

	var motor := _make_cylinder("FloorHaulOutMotor", 0.16, 0.45, Vector3(total_length * 0.5 + 0.3, 0.10, bin_d * 0.40), sorter._mat_green, Vector3(0.0, 0.0, PI * 0.5))
	haul_out.add_child(motor)

	# High friction PhysicsMaterial override for floor haul-out conveyor so boards are carried away along +X
	var mat_floor := PhysicsMaterial.new()
	mat_floor.friction = 1.0
	mat_floor.rough = true
	mat_floor.bounce = 0.0
	haul_out.physics_material_override = mat_floor

	_add_box_col(haul_out, "FloorConveyorBedCol", Vector3(total_length, 0.16, bin_d - 0.3), Vector3(0.0, 0.01, 0.0))

	sorter.add_child(haul_out)
	sorter._floor_haulout_body = haul_out


func _build_support_gantry() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0

	var half_d: float = bin_d * 0.5
	for side in [-1.0, 1.0]:
		var beam_pos := Vector3(total_length * 0.5 - 0.5, sorter_h, side * half_d)
		var beam_size := Vector3(total_length, 0.25, 0.18)
		var beam := _make_box("LongitudinalBeam_Z%d" % [int(side)], beam_size, beam_pos, sorter._mat_green)
		sorter.add_child(beam)
		_add_box_col(sorter, "BeamCol_Z%d" % [int(side)], beam_size, beam_pos)

	for i in range(num_bins + 1):
		var x_pos: float = i * bin_w
		for side in [-1.0, 1.0]:
			var col_pos := Vector3(x_pos, sorter_h * 0.5, side * half_d)
			var col_size := Vector3(0.20, sorter_h, 0.20)
			var col := _make_box("SupportColumn_B%d_Z%d" % [i, int(side)], col_size, col_pos, sorter._mat_green)
			sorter.add_child(col)
			_add_box_col(sorter, "ColumnCol_B%d_Z%d" % [i, int(side)], col_size, col_pos)

			var base_plate := _make_box("BasePlate", Vector3(0.40, 0.03, 0.40), Vector3(x_pos, 0.015, side * half_d), sorter._mat_dark_steel)
			sorter.add_child(base_plate)

			if i < num_bins:
				var bay_num: int = i + 1
				var lbl := Label3D.new()
				lbl.name = "BayNumberLabel_B%d_Z%d" % [bay_num, int(side)]
				lbl.text = "%d" % bay_num
				lbl.position = Vector3(x_pos - 0.11, 1.0, side * half_d)
				lbl.rotation = Vector3(0.0, -PI * 0.5, 0.0)  # Facing -X (facing away from haulout chain)
				lbl.pixel_size = 0.006
				lbl.font_size = 72
				lbl.modulate = Color(1.0, 1.0, 1.0)
				lbl.outline_modulate = Color(0.0, 0.0, 0.0)
				lbl.outline_size = 8
				lbl.render_priority = 10
				sorter.add_child(lbl)

		var cb_pos := Vector3(x_pos, sorter_h - 0.11, 0.0)
		var cb_size := Vector3(0.18, 0.22, bin_d + 0.3)
		var cross_beam := _make_box("CrossBeam_B%d" % [i], cb_size, cb_pos, sorter._mat_green)
		sorter.add_child(cross_beam)
		_add_box_col(sorter, "CrossBeamCol_B%d" % [i], cb_size, cb_pos)

		for side in [-1.0, 1.0]:
			var upper_ledger := _make_box("UpperHopperLedger_B%d_Z%d" % [i, int(side)], Vector3(bin_w + 0.2, 0.15, 0.15), Vector3(x_pos, sorter_h * 0.80, side * (bin_d * 0.48)), sorter._mat_green)
			sorter.add_child(upper_ledger)

			var lower_ledger := _make_box("LowerHopperLedger_B%d_Z%d" % [i, int(side)], Vector3(bin_w + 0.2, 0.15, 0.15), Vector3(x_pos, sorter_h * 0.35, side * (bin_d * 0.48)), sorter._mat_green)
			sorter.add_child(lower_ledger)

			var brace := _make_box("DiagonalBrace", Vector3(0.10, 0.70, 0.10), Vector3(x_pos, sorter_h - 0.50, side * (half_d - 0.35)), sorter._mat_green, Vector3(side * 0.45, 0.0, 0.0))
			sorter.add_child(brace)


func _build_catwalk_and_handrails() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0

	var catwalk_z: float = -bin_d * 0.5 - 0.6
	var catwalk_h: float = sorter_h - 0.4
	var catwalk_w: float = 0.8

	var floor_pos := Vector3(total_length * 0.5 - 0.5, catwalk_h, catwalk_z)
	var floor_size := Vector3(total_length, 0.06, catwalk_w)
	var floor_grate := _make_box("CatwalkFloor", floor_size, floor_pos, sorter._mat_dark_steel)
	sorter.add_child(floor_grate)
	_add_box_col(sorter, "CatwalkFloorCol", floor_size, floor_pos)

	var outer_z: float = catwalk_z - catwalk_w * 0.5 + 0.04
	var rail_height: float = 1.05

	var top_rail := _make_cylinder("HandrailTop", 0.02, total_length, Vector3(total_length * 0.5 - 0.5, catwalk_h + rail_height, outer_z), sorter._mat_yellow, Vector3(0.0, 0.0, PI * 0.5))
	sorter.add_child(top_rail)

	var mid_rail := _make_cylinder("HandrailMid", 0.015, total_length, Vector3(total_length * 0.5 - 0.5, catwalk_h + rail_height * 0.5, outer_z), sorter._mat_yellow, Vector3(0.0, 0.0, PI * 0.5))
	sorter.add_child(mid_rail)

	var num_posts: int = int(ceil(total_length / 1.5)) + 1
	for p in range(num_posts):
		var px: float = (total_length / max(num_posts - 1, 1)) * p - 0.5
		var post := _make_cylinder("HandrailPost_%d" % p, 0.02, rail_height, Vector3(px, catwalk_h + rail_height * 0.5, outer_z), sorter._mat_yellow)
		sorter.add_child(post)

	var toekick := _make_box("ToeKickPlate", Vector3(total_length, 0.12, 0.01), Vector3(total_length * 0.5 - 0.5, catwalk_h + 0.06, outer_z), sorter._mat_yellow)
	sorter.add_child(toekick)

	_build_ladder(Vector3(-0.4, 0.0, catwalk_z), catwalk_h)


func _build_ladder(base_pos: Vector3, top_h: float) -> void:
	var ladder := Node3D.new()
	ladder.name = "AccessLadder"
	ladder.position = base_pos

	var width: float = 0.45
	var rungs: int = int(floor(top_h / 0.3))

	for side in [-1.0, 1.0]:
		var rail := _make_cylinder("LadderRail", 0.02, top_h + 1.0, Vector3(0.0, (top_h + 1.0) * 0.5, side * width * 0.5), sorter._mat_yellow)
		ladder.add_child(rail)

	for r in range(1, rungs + 1):
		var rung := _make_cylinder("LadderRung_%d" % r, 0.012, width, Vector3(0.0, r * 0.3, 0.0), sorter._mat_yellow, Vector3(PI * 0.5, 0.0, 0.0))
		ladder.add_child(rung)

	sorter.add_child(ladder)


func _build_overhead_track_channels() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	# Slotted Infeed Transfer Table with open chain slot channels for lug clearance
	var table_pos_x: float = -0.20
	var table_size_x: float = 0.60
	var table_size_y: float = 0.04
	var table_y: float = sorter_h + 0.10

	var visual_table := _make_box("InfeedTransferTable", Vector3(table_size_x, table_size_y, bin_d - 0.3), Vector3(table_pos_x, table_y, 0.0), sorter._mat_dark_steel)
	sorter.add_child(visual_table)

	var z_min: float = - (bin_d - 0.3) * 0.5
	var z_max: float = (bin_d - 0.3) * 0.5
	var slot_half_w: float = 0.08
	var current_z: float = z_min

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]
		var seg_start: float = current_z
		var seg_end: float = track_z - slot_half_w
		if seg_end > seg_start + 0.02:
			var seg_len: float = seg_end - seg_start
			var seg_z: float = (seg_start + seg_end) * 0.5
			_add_box_col(sorter, "InfeedTableSegCol_%d" % t_idx, Vector3(table_size_x, table_size_y, seg_len), Vector3(table_pos_x, table_y, seg_z))
		current_z = track_z + slot_half_w

	if z_max > current_z + 0.02:
		var seg_len: float = z_max - current_z
		var seg_z: float = (current_z + z_max) * 0.5
		_add_box_col(sorter, "InfeedTableSegCol_End", Vector3(table_size_x, table_size_y, seg_len), Vector3(table_pos_x, table_y, seg_z))

	var channel_start_x: float = -0.35
	var channel_end_x: float = total_length - 0.65
	var channel_len: float = channel_end_x - channel_start_x

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]

		var channel_group := Node3D.new()
		channel_group.name = "ChainChannel_T%d" % t_idx

		for side_z in [-0.045, 0.045]:
			var side_plate := _make_box("SideGuidePlate_Z%.3f" % side_z, Vector3(channel_len, 0.06, 0.010), Vector3((channel_start_x + channel_end_x) * 0.5, sorter_h + 0.555, track_z + side_z), sorter._mat_dark_steel)
			channel_group.add_child(side_plate)

		sorter.add_child(channel_group)

		var chain_group := Node3D.new()
		chain_group.name = "ContinuousChainLoop_T%d" % t_idx

		var top_strand := _make_box("StaticTopChainStrand", Vector3(total_length, 0.035, 0.04), Vector3(total_length * 0.5 - 0.5, sorter_h + 0.63, track_z), sorter._mat_dark_steel)
		chain_group.add_child(top_strand)

		var bot_strand := _make_box("StaticBottomChainStrand", Vector3(total_length, 0.035, 0.04), Vector3(total_length * 0.5 - 0.5, sorter_h + 0.48, track_z), sorter._mat_dark_steel)
		chain_group.add_child(bot_strand)

		var outfeed_wrap := _make_cylinder("OutfeedSprocketWrap", 0.075, 0.04, Vector3(total_length - 0.5, sorter_h + 0.555, track_z), sorter._mat_sprocket_steel, Vector3(PI * 0.5, 0.0, 0.0))
		chain_group.add_child(outfeed_wrap)

		var infeed_wrap := _make_cylinder("InfeedSprocketWrap", 0.075, 0.04, Vector3(-0.5, sorter_h + 0.555, track_z), sorter._mat_sprocket_steel, Vector3(PI * 0.5, 0.0, 0.0))
		chain_group.add_child(infeed_wrap)

		sorter.add_child(chain_group)

	for sx in [-0.4, -0.2, num_bins * bin_w + 0.2, num_bins * bin_w + 0.4]:
		var skid_bar := _make_box("SlideSkidBar_X%.1f" % sx, Vector3(0.04, 0.04, bin_d - 0.8), Vector3(sx, sorter_h + 0.05, 0.0), sorter._mat_dark_steel)
		sorter.add_child(skid_bar)


func _build_infeed_return_shaft() -> void:
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var track_positions: Array[float] = _get_track_positions()

	var return_group := Node3D.new()
	return_group.name = "InfeedReturnShaftAssembly"
	return_group.position = Vector3(-0.5, sorter_h + 0.55, 0.0)

	var shaft := _make_cylinder("ReturnShaft", 0.045, bin_d - 0.4, Vector3.ZERO, sorter._mat_dark_steel, Vector3(PI * 0.5, 0.0, 0.0))
	return_group.add_child(shaft)

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]
		_build_sprocket(return_group, Vector3(0.0, 0.0, track_z), 10)

	for side in [-1.0, 1.0]:
		_build_pillow_block(return_group, Vector3(0.0, -0.12, side * (bin_d * 0.45)))

	sorter.add_child(return_group)


func _build_bin_hoppers() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height

	for b in range(num_bins):
		var bay_x: float = b * bin_w
		var bay_center_x: float = (b + 0.5) * bin_w
		var hopper := Node3D.new()
		hopper.name = "GravityBinHopper_%d" % b

		# 1. Top Horizontal Divider Header Beam connecting tops of posts to overhead gantry cross-beams at Y = 3.89m
		var top_header_y: float = sorter_h - 0.11
		var top_header := _make_box("TopDividerHeaderBeam_%d" % b, Vector3(0.10, 0.14, bin_d - 0.5), Vector3(bay_x - 0.15, top_header_y, 0.0), sorter._mat_green)
		hopper.add_child(top_header)

		# 2. Extended Open Vertical Divider Grid (Series of smaller green posts from Y = 1.34m to Y = 3.89m with zero visual gap)
		var post_count: int = 5
		var clear_height: float = 1.34  # Open clearance tunnel height above floor for lumber flow
		var post_h: float = top_header_y - clear_height
		var post_y: float = clear_height + (post_h * 0.5)

		for p in range(post_count):
			var pz: float = - (bin_d * 0.42) + p * (bin_d * 0.84 / (post_count - 1))
			var divider_post := _make_box("OpenDividerPost_B%d_P%d" % [b, p], Vector3(0.08, post_h, 0.08), Vector3(bay_x - 0.15, post_y, pz), sorter._mat_green)
			hopper.add_child(divider_post)

			# Welded flange mounting brackets at top and bottom connections
			var top_flange := _make_box("WeldedFlangeTop_B%d_P%d" % [b, p], Vector3(0.14, 0.04, 0.14), Vector3(bay_x - 0.15, top_header_y - 0.07, pz), sorter._mat_dark_steel)
			hopper.add_child(top_flange)

			var bot_flange := _make_box("WeldedFlangeBot_B%d_P%d" % [b, p], Vector3(0.14, 0.04, 0.14), Vector3(bay_x - 0.15, clear_height + 0.02, pz), sorter._mat_dark_steel)
			hopper.add_child(bot_flange)

		# Solid physics collider for bay divider wall boundary at X = bay_x - 0.15m
		var mat_smooth_wall := PhysicsMaterial.new()
		mat_smooth_wall.friction = 0.0
		mat_smooth_wall.bounce = 0.0

		var wall_static := StaticBody3D.new()
		wall_static.name = "DividerWallStatic_%d" % b
		wall_static.physics_material_override = mat_smooth_wall
		_add_box_col(wall_static, "DividerWallCol", Vector3(0.06, post_h + 0.2, bin_d - 0.3), Vector3(bay_x - 0.15, post_y, 0.0))
		hopper.add_child(wall_static)

		# 3. Horizontal Bottom Tie Beam connecting all vertical posts across Z at Y = 1.34m (offset back at X = bay_x - 0.15m)
		var tie_beam := _make_box("BottomDividerTieBeam_%d" % b, Vector3(0.10, 0.12, bin_d - 0.5), Vector3(bay_x - 0.15, clear_height - 0.06, 0.0), sorter._mat_green)
		hopper.add_child(tie_beam)

		# 3. Photo Eye Optical Sensor Housing (Shooting laser beam along X at Y = sorter_h - 0.50m)
		var eye_y: float = sorter_h - 0.50
		var emitter := _make_box("PhotoEyeEmitter_B%d" % b, Vector3(0.08, 0.10, 0.08), Vector3(bay_x - 0.15, eye_y, 0.0), sorter._mat_yellow)
		var emitter_lens := _make_cylinder("LensRed", 0.025, 0.02, Vector3(0.04, 0.0, 0.0), sorter._mat_red, Vector3(0.0, 0.0, PI * 0.5))
		emitter.add_child(emitter_lens)
		hopper.add_child(emitter)

		var receiver := _make_box("PhotoEyeReceiver_B%d" % b, Vector3(0.08, 0.10, 0.08), Vector3(bay_x + bin_w - 0.05, eye_y, 0.0), sorter._mat_yellow)
		var recv_lens := _make_cylinder("LensDark", 0.025, 0.02, Vector3(-0.04, 0.0, 0.0), sorter._mat_dark_steel, Vector3(0.0, 0.0, PI * 0.5))
		receiver.add_child(recv_lens)
		hopper.add_child(receiver)

		var beam_line := _make_box("PhotoEyeBeam_B%d" % b, Vector3(bin_w + 0.10, 0.012, 0.012), Vector3(bay_x + (bin_w - 0.20) * 0.5, eye_y, 0.0), sorter._mat_red)
		hopper.add_child(beam_line)

		# 4. Option A Indexing Sling Cradle Assembly (AnimatableBody3D starting at Top Elevation Y = sorter_h - 0.70m)
		var top_cradle_y: float = sorter_h - 0.70
		var cradle_group := AnimatableBody3D.new()
		cradle_group.name = "OptionACradle_B%d" % b
		cradle_group.position = Vector3(bay_x + bin_w * 0.5, top_cradle_y, 0.0)
		cradle_group.sync_to_physics = true

		# High-friction, zero-bounce PhysicsMaterial override to prevent boards from landing and sliding forward
		var mat_cradle := PhysicsMaterial.new()
		mat_cradle.friction = 1.0
		mat_cradle.rough = true
		mat_cradle.bounce = 0.0
		cradle_group.physics_material_override = mat_cradle

		# Solid physics collider for Main Orange Support Beam
		_add_box_col(cradle_group, "MainCradleBeamCol", Vector3(0.16, 0.16, bin_d - 0.3), Vector3(-bin_w * 0.5, 0.0, 0.0))

		# Main Orange Support Beam running along Z at X = bay_x
		var main_cradle_beam_z := _make_box("OrangeCradleBeamZ", Vector3(0.16, 0.16, bin_d - 0.3), Vector3(-bin_w * 0.5, 0.0, 0.0), sorter._mat_orange)
		cradle_group.add_child(main_cradle_beam_z)

		# Outer End Guide Brackets attached to the ends of the orange Z-beam at Z = -bin_d/2 and Z = +bin_d/2
		for side in [-1.0, 1.0]:
			var side_z: float = side * (bin_d * 0.46)
			var bracket := _make_box("OuterIBeamGuideBracket_Z%d" % int(side), Vector3(0.24, 0.32, 0.20), Vector3(-bin_w * 0.5, 0.0, side_z), sorter._mat_orange)
			var shoe := _make_box("WhiteGuideShoe", Vector3(0.04, 0.28, 0.04), Vector3(0.0, 0.0, -side * 0.11), sorter._mat_chrome)
			bracket.add_child(shoe)
			cradle_group.add_child(bracket)

			# Dynamic Hoist Cable extending up to upper gantry ledger at X = bay_x
			var hoist_cable := _make_cylinder("GantryHoistCable", 0.015, sorter_h * 0.8, Vector3(bay_x, sorter_h * 0.40, side_z), sorter._mat_dark_steel)
			hopper.add_child(hoist_cable)

		# 7 Slender 100% Procedural Smooth Curved J-Cradle Forks per bin (spaced densely along Z to support even 6ft short boards)
		var arm_len: float = bin_w - 0.15
		var fork_count: int = 7
		for fk_idx in range(fork_count):
			var fk_z: float = - (bin_d * 0.42) + fk_idx * (bin_d * 0.84 / (fork_count - 1))
			var fork_mesh := _make_smooth_curved_fork_mesh("SmoothTaperedLFork_%d" % fk_idx, arm_len, Vector3(-bin_w * 0.5, 0.0, fk_z), sorter._mat_orange)
			cradle_group.add_child(fork_mesh)

			# Solid 5-segment Bezier curved physics colliders matching the visual curved fork 100%
			_add_curved_fork_colliders(cradle_group, arm_len, fk_z)

		hopper.add_child(cradle_group)
		sorter._cradle_nodes.append(cradle_group)
		sorter.add_child(hopper)


func _build_drive_motors() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	var drive_assembly := Node3D.new()
	drive_assembly.name = "OutfeedDriveAssembly"
	drive_assembly.position = Vector3(total_length - 0.5, sorter_h + 0.55, 0.0)

	var shaft := _make_cylinder("DriveShaft", 0.05, bin_d - 0.4, Vector3.ZERO, sorter._mat_dark_steel, Vector3(PI * 0.5, 0.0, 0.0))
	drive_assembly.add_child(shaft)

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]
		_build_sprocket(drive_assembly, Vector3(0.0, 0.0, track_z), 10)

	for side in [-1.0, 1.0]:
		_build_pillow_block(drive_assembly, Vector3(0.0, -0.12, side * (bin_d * 0.45)))

	var motor := Node3D.new()
	motor.name = "DriveMotor"
	motor.position = Vector3(0.2, 0.15, bin_d * 0.5 + 0.3)

	var motor_casing := _make_cylinder("MotorCasing", 0.22, 0.60, Vector3.ZERO, sorter._mat_green, Vector3(0.0, 0.0, PI * 0.5))
	motor.add_child(motor_casing)

	for f in range(7):
		var fin := _make_cylinder("MotorFin_%d" % f, 0.24, 0.02, Vector3((f - 3) * 0.07, 0.0, 0.0), sorter._mat_dark_steel, Vector3(0.0, 0.0, PI * 0.5))
		motor.add_child(fin)

	var fan_cowl := _make_cylinder("FanShroud", 0.23, 0.12, Vector3(0.34, 0.0, 0.0), sorter._mat_yellow, Vector3(0.0, 0.0, PI * 0.5))
	motor.add_child(fan_cowl)

	var jbox := _make_box("JunctionBox", Vector3(0.18, 0.18, 0.14), Vector3(0.0, 0.22, 0.0), sorter._mat_dark_steel)
	motor.add_child(jbox)

	var gearbox := _make_box("Gearbox", Vector3(0.42, 0.42, 0.50), Vector3(-0.30, 0.0, -0.20), sorter._mat_dark_steel)
	motor.add_child(gearbox)

	var guard := _make_box("DriveChainGuard", Vector3(0.25, 0.50, 0.45), Vector3(-0.20, 0.0, -0.45), sorter._mat_yellow)
	motor.add_child(guard)

	drive_assembly.add_child(motor)
	sorter.add_child(drive_assembly)


func _build_sprocket(parent: Node, pos: Vector3, teeth_count: int = 10) -> void:
	var sprocket := Node3D.new()
	sprocket.name = "SprocketGear"
	sprocket.position = pos

	var hub := _make_cylinder("SprocketHub", 0.16, 0.05, Vector3.ZERO, sorter._mat_sprocket_steel, Vector3(PI * 0.5, 0.0, 0.0))
	sprocket.add_child(hub)

	var collar := _make_cylinder("ShaftCollar", 0.08, 0.09, Vector3.ZERO, sorter._mat_dark_steel, Vector3(PI * 0.5, 0.0, 0.0))
	sprocket.add_child(collar)

	var tooth_angle_step: float = (PI * 2.0) / float(teeth_count)
	for t in range(teeth_count):
		var angle: float = t * tooth_angle_step
		var tooth := _make_box("Tooth_%d" % t, Vector3(0.04, 0.05, 0.05), Vector3(cos(angle) * 0.175, sin(angle) * 0.175, 0.0), sorter._mat_sprocket_steel, Vector3(0.0, 0.0, angle))
		sprocket.add_child(tooth)

	parent.add_child(sprocket)


func _build_pillow_block(parent: Node, pos: Vector3) -> void:
	var block := Node3D.new()
	block.name = "PillowBlockBearing"
	block.position = pos

	var base := _make_box("PillowBlockBase", Vector3(0.18, 0.04, 0.22), Vector3.ZERO, sorter._mat_cast_iron)
	block.add_child(base)

	var cap := _make_cylinder("PillowBlockCap", 0.08, 0.16, Vector3(0.0, 0.06, 0.0), sorter._mat_cast_iron, Vector3(PI * 0.5, 0.0, 0.0))
	block.add_child(cap)

	for bx in [-0.06, 0.06]:
		for bz in [-0.07, 0.07]:
			var bolt := _make_cylinder("BearingBolt", 0.012, 0.08, Vector3(bx, 0.03, bz), sorter._mat_chrome)
			block.add_child(bolt)

	parent.add_child(block)


func _add_curved_fork_colliders(cradle_group: AnimatableBody3D, arm_len: float, fk_z: float) -> void:
	var P0 := Vector2(0.0, 0.0)
	var P1 := Vector2(arm_len * 0.20, -0.06)
	var P2 := Vector2(arm_len * 0.60, -0.10)
	var P3 := Vector2(arm_len, -0.11)

	var num_segs: int = 2
	for s in range(num_segs):
		var t0: float = float(s) / float(num_segs)
		var t1: float = float(s + 1) / float(num_segs)
		var t_mid: float = (t0 + t1) * 0.5

		var inv0: float = 1.0 - t0
		var pt0 := inv0 * inv0 * inv0 * P0 + 3.0 * inv0 * inv0 * t0 * P1 + 3.0 * inv0 * (t0 * t0) * P2 + (t0 * t0 * t0) * P3

		var inv1: float = 1.0 - t1
		var pt1 := inv1 * inv1 * inv1 * P0 + 3.0 * inv1 * inv1 * t1 * P1 + 3.0 * inv1 * (t1 * t1) * P2 + (t1 * t1 * t1) * P3

		var seg_center: Vector2 = (pt0 + pt1) * 0.5
		var seg_dir: Vector2 = pt1 - pt0
		var seg_len: float = seg_dir.length()
		var angle: float = atan2(seg_dir.y, seg_dir.x)
		var h: float = lerp(0.14, 0.08, t_mid)

		var col_pos := Vector3(-sorter.bin_width * 0.5 + seg_center.x, seg_center.y, fk_z)
		var col_rot := Vector3(0.0, 0.0, angle)

		var col := CollisionShape3D.new()
		col.name = "CurvedForkSegCol_%d" % s
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len + 0.01, h, 0.14)
		col.shape = box
		col.position = col_pos
		col.rotation = col_rot
		cradle_group.add_child(col)


func _build_building_lights() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height

	var lights_group := Node3D.new()
	lights_group.name = "IndustrialHighBayLights"

	var mat_fixture := StandardMaterial3D.new()
	mat_fixture.albedo_color = Color(0.15, 0.16, 0.18)
	mat_fixture.metallic = 0.80
	mat_fixture.roughness = 0.30

	var mat_bulb := StandardMaterial3D.new()
	mat_bulb.albedo_color = Color(0.98, 0.95, 0.85)
	mat_bulb.emission_enabled = true
	mat_bulb.emission = Color(0.98, 0.95, 0.85)
	mat_bulb.emission_energy_multiplier = 4.0

	var step_b: int = 3
	for b in range(0, num_bins, step_b):
		var lx: float = (b + 0.5) * bin_w
		var ly: float = sorter_h + 0.75

		for side in [-0.25, 0.25]:
			var lz: float = side * bin_d
			var fixture := Node3D.new()
			fixture.name = "HighBayFixture_B%d_S%.1f" % [b, side]
			fixture.position = Vector3(lx, ly, lz)

			var housing := _make_cylinder("ReflectorBell", 0.18, 0.16, Vector3.ZERO, mat_fixture)
			fixture.add_child(housing)

			var bulb := _make_cylinder("BulbLens", 0.12, 0.04, Vector3(0.0, -0.07, 0.0), mat_bulb)
			fixture.add_child(bulb)

			var spot := SpotLight3D.new()
			spot.name = "HighBaySpotLight"
			spot.position = Vector3(0.0, -0.09, 0.0)
			spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			spot.spot_range = 7.5
			spot.spot_angle = 55.0
			spot.light_color = Color(0.98, 0.94, 0.86)
			spot.light_energy = 1.4
			spot.light_specular = 0.2
			fixture.add_child(spot)

			lights_group.add_child(fixture)

	sorter.add_child(lights_group)
