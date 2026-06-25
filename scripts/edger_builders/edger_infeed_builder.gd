@tool
extends RefCounted

var edger: SawmillEdger
var pin_builder: RefCounted


func _init(p_edger: SawmillEdger, p_pin_builder: RefCounted) -> void:
	edger = p_edger
	pin_builder = p_pin_builder


func build_infeed_chains() -> void:
	edger._push_editor_group("InfeedChainAssembly")
	var chain_top := edger._support_top_y()
	var chain_y := chain_top - SawmillEdger.CHAIN_LINK_THICKNESS * 0.5
	var chain_start := edger._infeed_chain_start_x()
	var chain_end := SawmillEdger.INFEED_CHAIN_END_X
	var chain_length := chain_end - chain_start
	if chain_length <= 0.4:
		edger._pop_editor_group()
		return

	var chain_zs: Array[float] = [0.0]
	for lane_i in range(chain_zs.size()):
		var z := chain_zs[lane_i]
		var lane_suffix := "_%02d" % (lane_i + 1)
		edger._add_box("InfeedChainWearRail" + lane_suffix, Vector3((chain_start + chain_end) * 0.5, chain_top - 0.07, z), Vector3(chain_length, 0.045, SawmillEdger.CHAIN_LINK_WIDTH + 0.035), edger._mat_frame)
		edger._add_cylinder("InfeedChainIdler" + lane_suffix + "_Entry", Vector3(chain_start, chain_y, z), 0.065, SawmillEdger.CHAIN_LINK_WIDTH + 0.035, edger._mat_dark, Vector3(PI * 0.5, 0, 0), 18)
		edger._add_cylinder("InfeedChainIdler" + lane_suffix + "_SawEnd", Vector3(chain_end, chain_y, z), 0.065, SawmillEdger.CHAIN_LINK_WIDTH + 0.035, edger._mat_dark, Vector3(PI * 0.5, 0, 0), 18)

		var link_count := maxi(6, int(chain_length / SawmillEdger.CHAIN_LINK_LENGTH))
		for i in range(link_count):
			var t := float(i) / float(link_count)
			var x := lerpf(chain_start, chain_end, t)
			var link := edger._add_infeed_chain_link("InfeedChainLink" + lane_suffix + "_%02d" % (i + 1), Vector3(x, chain_y, z), i)
			edger._infeed_chain_links.append(link)
			edger._infeed_chain_bases.append(link.position)
	edger._pop_editor_group()

	var centering_start: float = chain_start
	var centering_end: float = edger._centering_section_end_x()
	build_parking_ramps(centering_start, centering_end, chain_top)
	build_infeed_hold_downs(centering_start, centering_end)
	pin_builder.build_position_pins(centering_start, centering_end, chain_top)
	pin_builder.build_cushion_pins(centering_start, centering_end, chain_top)

func build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	var usable_length: float = chain_end - chain_start
	if usable_length <= 0.4:
		return

	edger._push_editor_group("ParkingRampAssembly")
	var station_count: int = maxi(edger.parking_ramp_stations, 2)
	var station_spacing: float = usable_length / float(station_count)
	var ramp_x_size: float = minf(0.46, station_spacing * 0.62)
	var ramp_y_size: float = 0.024
	var ramp_z_size: float = 0.20
	var retracted_y: float = chain_top - ramp_y_size * 0.5 - 0.012
	var ramp_zs: Array[float] = [-SawmillEdger.SAMPLE_BOARD_WIDTH * 0.48, SawmillEdger.SAMPLE_BOARD_WIDTH * 0.48]

	for i in range(station_count):
		var x: float = chain_start + station_spacing * (float(i) + 0.5)
		var station_nodes: Array[Node3D] = []
		for side_i in range(ramp_zs.size()):
			var z: float = ramp_zs[side_i]
			var suffix: String = "_%02d_%s" % [i + 1, "Front" if z < 0.0 else "Back"]
			var side_sign := -1.0 if z < 0.0 else 1.0
			var pivot_z := z + side_sign * ramp_z_size * 0.5
			var plate_local_z := -side_sign * ramp_z_size * 0.5
			var parked_angle := -0.24 if z < 0.0 else 0.24
			var ramp_root := Node3D.new()
			ramp_root.name = edger._friendly_part_name("ParkingRampPivot" + suffix, Vector3(x, retracted_y, z))
			ramp_root.position = Vector3(x, retracted_y, pivot_z)
			ramp_root.set_meta("retracted_angle", 0.0)
			ramp_root.set_meta("parked_angle", parked_angle)
			ramp_root.set_meta("board_lift_span", ramp_z_size)
			edger._current_part_parent().add_child(ramp_root)
			edger._adopt_new_node(ramp_root)
			edger._add_box_child(ramp_root, "ParkingRampPlate", Vector3(0.0, 0.0, plate_local_z), Vector3(ramp_x_size, ramp_y_size, ramp_z_size), edger._mat_hydraulic)
			station_nodes.append(ramp_root)

			var shaft_height := 0.09
			var shaft_y := retracted_y - ramp_y_size * 0.5 - 0.018 - shaft_height * 0.5
			edger._add_cylinder("ParkingRampShaft" + suffix, Vector3(x, shaft_y, pivot_z), 0.018, shaft_height, edger._mat_dark, Vector3.ZERO, 12)
		edger._parking_ramp_stations.append({
			"x": x,
			"nodes": station_nodes,
		})
	edger._pop_editor_group()

func build_infeed_hold_downs(chain_start: float, chain_end: float) -> void:
	var usable_length: float = chain_end - chain_start
	if usable_length <= 0.4:
		return

	var ramp_count: int = maxi(edger.parking_ramp_stations, 2)
	var roller_count: int = maxi(ramp_count - 1, 0)
	if roller_count <= 0:
		return

	edger._push_editor_group("InfeedHoldDownRollerAssembly")
	var ramp_spacing: float = usable_length / float(ramp_count)
	var board_top := edger._board_center_y() + SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.5
	var contact_y := board_top + SawmillEdger.INFEED_HOLD_DOWN_ROLLER_RADIUS - 0.006
	var raised_y := contact_y + edger.hold_down_raised_offset
	var hardware_z_limit := SawmillEdger.INFEED_HOLD_DOWN_ROLLER_LENGTH * 0.5
	var yoke_z := hardware_z_limit - 0.025
	var guide_height := 0.46
	var guide_y := contact_y + 0.37
	for i in range(roller_count):
		var x := chain_start + ramp_spacing * float(i + 1)
		var suffix := "_%02d" % (i + 1)
		edger._add_box("InfeedHoldDownCrosshead" + suffix, Vector3(x, contact_y + 0.42, 0.0), Vector3(0.12, 0.10, SawmillEdger.INFEED_HOLD_DOWN_ROLLER_LENGTH), edger._mat_frame)
		edger._add_box("InfeedHoldDownTopBox" + suffix, Vector3(x, contact_y + 0.66, 0.0), Vector3(0.28, 0.18, SawmillEdger.INFEED_HOLD_DOWN_ROLLER_LENGTH), edger._mat_frame)
		var roller := edger._add_cylinder("InfeedHoldDownRoller" + suffix, Vector3(x, raised_y, 0.0), SawmillEdger.INFEED_HOLD_DOWN_ROLLER_RADIUS, SawmillEdger.INFEED_HOLD_DOWN_ROLLER_LENGTH, edger._mat_infeed_hold_down, Vector3(PI * 0.5, 0.0, 0.0), 30)
		var axle := edger._add_cylinder("InfeedHoldDownAxle" + suffix, Vector3(x, raised_y, 0.0), 0.024, SawmillEdger.INFEED_HOLD_DOWN_ROLLER_LENGTH, edger._mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 18)
		var moving_nodes: Array[Node3D] = [roller, axle]
		var guide_xs: Array[float] = [-0.08, 0.08]
		var guide_zs: Array[float] = [-yoke_z, yoke_z]
		for guide_x in guide_xs:
			for guide_z in guide_zs:
				var guide_suffix := "%s_%s%s" % [suffix, "L" if guide_x < 0.0 else "R", "F" if guide_z < 0.0 else "B"]
				edger._add_cylinder("InfeedHoldDownGuide" + guide_suffix, Vector3(x + guide_x, guide_y, guide_z), 0.018, guide_height, edger._mat_hydraulic, Vector3.ZERO, 14)
		for z in guide_zs:
			var side_suffix := suffix + ("_F" if z < 0.0 else "_B")
			moving_nodes.append(edger._add_box("InfeedHoldDownYoke" + side_suffix, Vector3(x, raised_y + 0.04, z), Vector3(0.15, 0.24, 0.04), edger._mat_infeed_hold_down))
			moving_nodes.append(add_infeed_hold_down_pillow_block("InfeedHoldDownBearing" + side_suffix, Vector3(x, raised_y + 0.035, z)))
		var y_offsets: Array[float] = []
		for node in moving_nodes:
			y_offsets.append(node.position.y - raised_y)
		edger._infeed_hold_down_rollers.append(roller)
		edger._infeed_hold_down_stations.append({
			"x": x,
			"nodes": moving_nodes,
			"y_offsets": y_offsets,
			"raised_y": raised_y,
			"offset": edger.hold_down_raised_offset,
		})
	edger._pop_editor_group()

func add_infeed_hold_down_pillow_block(node_name: String, local_position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = edger._friendly_part_name(node_name, local_position)
	root.position = local_position
	edger._current_part_parent().add_child(root)
	edger._adopt_new_node(root)

	edger._add_box_child(root, "BearingMountBase", Vector3(0.0, 0.060, 0.0), Vector3(0.21, 0.040, 0.115), edger._mat_frame)
	edger._add_box_child(root, "BearingLeftFoot", Vector3(-0.060, 0.026, 0.0), Vector3(0.054, 0.045, 0.105), edger._mat_frame)
	edger._add_box_child(root, "BearingRightFoot", Vector3(0.060, 0.026, 0.0), Vector3(0.054, 0.045, 0.105), edger._mat_frame)

	var housing := CSGCombiner3D.new()
	housing.name = "HalfRoundHousing"
	root.add_child(housing)
	edger._adopt_new_node(housing)

	var cap := CSGCylinder3D.new()
	cap.name = "HalfMoonCap"
	cap.position = Vector3(0.0, -0.014, 0.0)
	cap.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cap.radius = 0.078
	cap.height = 0.074
	cap.sides = 32
	cap.material = edger._mat_frame
	housing.add_child(cap)
	edger._adopt_new_node(cap)

	var flat_cut := CSGBox3D.new()
	flat_cut.name = "FlatTopCut"
	flat_cut.position = Vector3(0.0, 0.038, 0.0)
	flat_cut.size = Vector3(0.19, 0.090, 0.090)
	flat_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	housing.add_child(flat_cut)
	edger._adopt_new_node(flat_cut)

	var bore_cut := CSGCylinder3D.new()
	bore_cut.name = "ShaftBoreCut"
	bore_cut.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	bore_cut.radius = 0.034
	bore_cut.height = 0.090
	bore_cut.sides = 24
	bore_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	housing.add_child(bore_cut)
	edger._adopt_new_node(bore_cut)

	edger._add_cylinder_child(root, "BearingInnerRace", Vector3(0.0, 0.0, 0.0), 0.031, 0.080, edger._mat_dark, Vector3(PI * 0.5, 0.0, 0.0), 24)
	edger._add_cylinder_child(root, "BearingShaftStub", Vector3(0.0, 0.0, 0.0), 0.021, 0.092, edger._mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 16)

	var bolt_y := 0.084
	for bolt_x in [-0.058, 0.058]:
		edger._add_cylinder_child(root, "BoltHole", Vector3(bolt_x, bolt_y, 0.0), 0.019, 0.006, edger._mat_dark, Vector3.ZERO, 16)
		edger._add_cylinder_child(root, "BoltHead", Vector3(bolt_x, bolt_y + 0.006, 0.0), 0.014, 0.008, edger._mat_hydraulic, Vector3.ZERO, 12)
	return root
