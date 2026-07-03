@tool
extends RefCounted

var edger: SawmillEdger
var factory: RefCounted


func _init(p_edger: SawmillEdger, p_factory: RefCounted) -> void:
	edger = p_edger
	factory = p_factory


func build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	factory._push_editor_group("PositionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, edger.position_pin_spacing)
	var front_z: float = -SawmillEdger.SAMPLE_BOARD_WIDTH * 0.72
	var raised_y: float = chain_top + edger.position_pin_height * 0.5 + 0.015
	var retracted_y: float = chain_top - edger.position_pin_height * 0.65
	var sleeve_retracted_y: float = chain_top - 0.08
	var sleeve_raised_y: float = sleeve_retracted_y + raised_y - retracted_y
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var pin: AnimatableBody3D = factory._add_physics_cylinder("PositionPin" + suffix, Vector3(x, retracted_y, front_z), edger.position_pin_radius, edger.position_pin_height, edger._mat_warning, Vector3.ZERO, 20)
		var sleeve: AnimatableBody3D = factory._add_physics_cylinder("PositionPinSleeve" + suffix, Vector3(x, sleeve_retracted_y, front_z), edger.position_pin_radius * 1.25, 0.10, edger._mat_dark, Vector3.ZERO, 18)
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
	factory._pop_editor_group()

func build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	factory._push_editor_group("CushionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, edger.cushion_pin_spacing)
	var back_z: float = SawmillEdger.SAMPLE_BOARD_WIDTH * 0.78
	var pin_y: float = chain_top + 0.065
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var body := AnimatableBody3D.new()
		body.position = Vector3(x, pin_y, back_z)
		body.name = factory._friendly_part_name("CushionPinAssembly" + suffix, body.position)
		body.sync_to_physics = true
		factory._current_part_parent().add_child(body)
		factory._adopt_new_node(body)

		var barrel: CSGCylinder3D = factory._add_cylinder_child(factory._current_part_parent(), "CushionCylinder" + suffix, Vector3(x, pin_y, back_z + 0.13), 0.035, 0.26, edger._mat_dark, Vector3(PI * 0.5, 0.0, 0.0), 16, false)
		var rod: CSGCylinder3D = factory._add_cylinder_child(body, "CushionRod", Vector3(0.0, 0.0, 0.11553), 0.018, 0.26031, edger._mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 14, false)
		var pad: MeshInstance3D = factory._add_box_contact_child(body, "CushionPad", Vector3(0.0, 0.0, -0.035), Vector3(0.16, 0.12, 0.045), edger._mat_rubber)
		edger._cushion_pin_stations.append({
			"x": x,
			"body": body,
			"barrel": barrel,
			"rod": rod,
			"pad": pad,
			"base_z": back_z,
			"extended": false,
		})
	factory._pop_editor_group()

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
