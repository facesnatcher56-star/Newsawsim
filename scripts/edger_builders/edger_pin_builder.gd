@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	edger._push_editor_group("PositionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, edger.position_pin_spacing)
	var front_z: float = -SawmillEdger.SAMPLE_BOARD_WIDTH * 0.72
	var raised_y: float = chain_top + edger.position_pin_height * 0.5 + 0.015
	var retracted_y: float = chain_top - edger.position_pin_height * 0.65
	var sleeve_retracted_y: float = chain_top - 0.08
	var sleeve_raised_y: float = sleeve_retracted_y + raised_y - retracted_y
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var pin: CSGCylinder3D = edger._add_cylinder("PositionPin" + suffix, Vector3(x, retracted_y, front_z), edger.position_pin_radius, edger.position_pin_height, edger._mat_warning, Vector3.ZERO, 20)
		var sleeve: CSGCylinder3D = edger._add_cylinder("PositionPinSleeve" + suffix, Vector3(x, sleeve_retracted_y, front_z), edger.position_pin_radius * 1.25, 0.10, edger._mat_dark, Vector3.ZERO, 18)
		edger._position_pin_stations.append({
			"x": x,
			"pin": pin,
			"sleeve": sleeve,
			"raised_y": raised_y,
			"retracted_y": retracted_y,
			"sleeve_raised_y": sleeve_raised_y,
			"sleeve_retracted_y": sleeve_retracted_y,
			"z": front_z,
		})
	edger._pop_editor_group()

func build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	edger._push_editor_group("CushionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, edger.cushion_pin_spacing)
	var back_z: float = SawmillEdger.SAMPLE_BOARD_WIDTH * 0.78
	var pin_y: float = chain_top + 0.065
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var body: Node3D = Node3D.new()
		body.position = Vector3(x, pin_y, back_z)
		body.name = edger._friendly_part_name("CushionPinAssembly" + suffix, body.position)
		edger._current_part_parent().add_child(body)
		edger._adopt_new_node(body)

		var barrel: CSGCylinder3D = edger._add_cylinder_child(body, "CushionCylinder", Vector3(0.0, 0.0, 0.13), 0.035, 0.26, edger._mat_dark, Vector3(PI * 0.5, 0.0, 0.0), 16)
		var rod: CSGCylinder3D = edger._add_cylinder_child(body, "CushionRod", Vector3(0.0, 0.0, -0.08), 0.018, edger.cushion_pin_extension, edger._mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 14)
		var pad: CSGBox3D = edger._add_box_child(body, "CushionPad", Vector3(0.0, 0.0, -0.08 - edger.cushion_pin_extension * 0.5), Vector3(0.16, 0.12, 0.045), edger._mat_rubber)
		edger._cushion_pin_stations.append({
			"x": x,
			"body": body,
			"barrel": barrel,
			"rod": rod,
			"pad": pad,
			"base_z": back_z,
			"extended": false,
		})
	edger._pop_editor_group()

func _pin_station_xs(first_x: float, last_x: float, station_count: int, station_spacing: float) -> Array[float]:
	var positions: Array[float] = []
	if station_count <= 0:
		return positions
	if station_count == 1:
		positions.append((first_x + last_x) * 0.5)
		return positions

	var center_x: float = (first_x + last_x) * 0.5
	var effective_spacing: float = maxf(station_spacing, 0.20)
	var span: float = effective_spacing * float(station_count - 1)
	var start_x: float = center_x - span * 0.5
	for i in range(station_count):
		positions.append(start_x + effective_spacing * float(i))
	return positions
