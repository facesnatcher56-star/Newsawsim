@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func build_frame() -> void:
	edger._push_editor_group("FrameAssembly")
	var half_l := edger.bed_length * 0.5
	var half_w := edger.machine_width * 0.5
	var leg_y := edger.working_height * 0.5 - 0.34
	var leg_h := maxf(edger.working_height + 0.28, 0.7)
	var end_xs: Array[float] = [-half_l + 0.28, half_l - 0.28]
	var side_zs: Array[float] = [-half_w + 0.12, half_w - 0.12]

	for x in end_xs:
		for z in side_zs:
			edger._add_box("Leg", Vector3(x, leg_y, z), Vector3(0.12, leg_h, 0.12), edger._mat_frame)
			edger._add_box("Foot", Vector3(x, -0.05, z), Vector3(0.42, 0.08, 0.28), edger._mat_frame)

	var rail_zs: Array[float] = [-half_w + 0.08, half_w - 0.08]
	for z in rail_zs:
		edger._add_box("LongFrameRail", Vector3(0, edger.working_height - 0.18, z), Vector3(edger.bed_length, 0.14, 0.12), edger._mat_frame)
		edger._add_box("LowerFrameRail", Vector3(0, 0.16, z), Vector3(edger.bed_length * 0.92, 0.10, 0.10), edger._mat_frame)

	var cross_xs: Array[float] = [-half_l + 0.2, -0.7, 0.7, half_l - 0.2]
	for x in cross_xs:
		edger._add_box("CrossMember", Vector3(x, edger.working_height - 0.2, 0), Vector3(0.12, 0.12, edger.machine_width), edger._mat_frame)
	edger._pop_editor_group()


func build_side_fences() -> void:
	edger._push_editor_group("SideFenceAssembly")
	var half_w := edger.machine_width * 0.5
	var fence_zs: Array[float] = [-half_w + 0.22, half_w - 0.22]
	for z in fence_zs:
		edger._add_box("SideFence", Vector3(0, edger.working_height + 0.18, z), Vector3(edger.bed_length * 0.94, 0.22, 0.06), edger._mat_frame)
	edger._pop_editor_group()
