@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func build_hold_downs() -> void:
	edger._push_editor_group("UpperHoldDownRollerAssembly")
	var hold_down_xs: Array[float] = [-1.75, -0.95, 0.45, 1.25]
	var board_top := edger._board_center_y() + SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.5
	var roller_y := board_top + SawmillEdger.HOLD_DOWN_ROLLER_RADIUS - 0.008
	for i in range(hold_down_xs.size()):
		var x := hold_down_xs[i]
		var suffix := "_%02d" % (i + 1)
		edger._add_box("HoldDownCrosshead" + suffix, Vector3(x, roller_y + 0.34, 0), Vector3(0.12, 0.12, 1.20), edger._mat_frame)
		edger._add_box("HoldDownTopPressureBox" + suffix, Vector3(x, roller_y + 0.60, 0), Vector3(0.32, 0.22, 0.92), edger._mat_frame)
		var hold_down := edger._add_cylinder("HoldDownRoller" + suffix, Vector3(x, roller_y, 0), SawmillEdger.HOLD_DOWN_ROLLER_RADIUS, SawmillEdger.HOLD_DOWN_ROLLER_LENGTH, edger._mat_warning, Vector3(PI * 0.5, 0, 0), 28)
		edger._add_roller_motion_stripe(hold_down, SawmillEdger.HOLD_DOWN_ROLLER_RADIUS, SawmillEdger.HOLD_DOWN_ROLLER_LENGTH)
		edger._hold_down_rollers.append(hold_down)
		var moving_nodes: Array[Node3D] = [hold_down]
		var axle := edger._add_cylinder("HoldDownAxle" + suffix, Vector3(x, roller_y, 0), 0.026, 1.12, edger._mat_hydraulic, Vector3(PI * 0.5, 0, 0), 20)
		moving_nodes.append(axle)

		var side_zs: Array[float] = [-0.46, 0.46]
		for side_i in range(side_zs.size()):
			var z := side_zs[side_i]
			var side_suffix := suffix + ("_L" if z < 0.0 else "_R")
			moving_nodes.append(edger._add_box("YokeSidePlate" + side_suffix, Vector3(x, roller_y + 0.03, z), Vector3(0.16, 0.30, 0.055), edger._mat_warning))
			moving_nodes.append(edger._add_box("YokeUpperLug" + side_suffix, Vector3(x, roller_y + 0.20, z), Vector3(0.16, 0.08, 0.16), edger._mat_warning))
			edger._add_cylinder("GuidePost" + side_suffix, Vector3(x - 0.09, roller_y + 0.34, z), 0.026, 0.54, edger._mat_hydraulic, Vector3.ZERO, 18)
			edger._add_cylinder("PressureCylinderBarrel" + side_suffix, Vector3(x + 0.09, roller_y + 0.48, z), 0.055, 0.28, edger._mat_dark, Vector3.ZERO, 24)
			moving_nodes.append(edger._add_cylinder("PressureCylinderRod" + side_suffix, Vector3(x + 0.09, roller_y + 0.25, z), 0.023, 0.30, edger._mat_hydraulic, Vector3.ZERO, 18))
			moving_nodes.append(edger._add_box("RodClevis" + side_suffix, Vector3(x + 0.09, roller_y + 0.09, z), Vector3(0.11, 0.06, 0.07), edger._mat_hydraulic))
			edger._add_box("TopClevisBracket" + side_suffix, Vector3(x + 0.09, roller_y + 0.64, z), Vector3(0.13, 0.08, 0.09), edger._mat_dark)

		var base_positions: Array[Vector3] = []
		for node in moving_nodes:
			base_positions.append(node.position)
			node.position.y += edger.hold_down_raised_offset
		edger._hold_down_stations.append({
			"x": x,
			"nodes": moving_nodes,
			"bases": base_positions,
			"offset": edger.hold_down_raised_offset,
		})
	edger._pop_editor_group()

func build_waste_handling() -> void:
	if not edger.show_waste_chutes:
		return

	edger._push_editor_group("WasteHandlingAssembly")
	var chute_z := edger.machine_width * 0.5 + 0.18
	var z_signs: Array[float] = [-1.0, 1.0]
	for z_sign in z_signs:
		var z := chute_z * z_sign
		edger._add_box("TrimChute", Vector3(0.62, edger.working_height - 0.08, z), Vector3(1.6, 0.06, 0.36), edger._mat_dark, Vector3(0, 0, -0.16 * z_sign))
		edger._add_box("ChipConveyorBelt", Vector3(1.15, edger.working_height - 0.32, z + 0.18 * z_sign), Vector3(1.7, 0.08, 0.26), edger._mat_dark)
		edger._add_box("ChipConveyorRail", Vector3(1.15, edger.working_height - 0.19, z + 0.34 * z_sign), Vector3(1.7, 0.18, 0.05), edger._mat_frame)
	edger._pop_editor_group()


func build_lower_feed_rollers() -> void:
	edger._push_editor_group("LowerFeedRollerAssembly")
	var roller_y := edger.working_height + 0.04
	var roller_start := SawmillEdger.SAW_X + 0.58
	var roller_end := edger.bed_length * 0.5 - 0.34
	var roller_count := maxi(edger.feed_roller_count, 2)
	var spacing := (roller_end - roller_start) / float(roller_count - 1)
	for i in range(roller_count):
		var x := roller_start + spacing * float(i)
		var suffix := "_%02d" % (i + 1)
		var roller := edger._add_cylinder("FeedRoller" + suffix, Vector3(x, roller_y, 0), SawmillEdger.FEED_ROLLER_RADIUS, SawmillEdger.FEED_ROLLER_LENGTH, edger._mat_dark, Vector3(PI * 0.5, 0, 0), 28)
		edger._add_roller_motion_stripe(roller, SawmillEdger.FEED_ROLLER_RADIUS, SawmillEdger.FEED_ROLLER_LENGTH)
		edger._feed_rollers.append(roller)
		edger._add_cylinder("RollerShaft" + suffix, Vector3(x, roller_y, 0), 0.025, edger.machine_width + 0.18, edger._mat_blade, Vector3(PI * 0.5, 0, 0), 20)
	edger._pop_editor_group()
