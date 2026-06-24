@tool
class_name SawmillEdger
extends StaticBody3D

## Industrial board edger sized for the sawmill board line.
## X is feed direction, Z is board-length/cross-machine width.

@export_category("Layout")
@export_range(2.0, 8.0, 0.1, "or_greater") var bed_length: float = 4.8:
	set(value):
		bed_length = maxf(value, 2.0)
		_queue_rebuild()

@export_range(0.8, 3.0, 0.05, "or_greater") var machine_width: float = 1.7:
	set(value):
		machine_width = maxf(value, 0.8)
		_queue_rebuild()

@export_range(0.3, 1.5, 0.05, "or_greater") var working_height: float = 0.62:
	set(value):
		working_height = maxf(value, 0.3)
		_queue_rebuild()

@export_range(0.2, 1.2, 0.01, "or_greater") var saw_spacing: float = 0.82:
	set(value):
		saw_spacing = maxf(value, 0.2)
		_queue_rebuild()

@export_category("Detail")
@export_range(2, 12, 1, "or_greater") var feed_roller_count: int = 7:
	set(value):
		feed_roller_count = maxi(value, 2)
		_queue_rebuild()

@export_range(0.2, 1.0, 0.01, "or_greater") var blade_radius: float = 0.38:
	set(value):
		blade_radius = maxf(value, 0.2)
		_queue_rebuild()

@export var show_waste_chutes: bool = true:
	set(value):
		show_waste_chutes = value
		_queue_rebuild()

@export_category("Infeed Centering")
@export_range(0.0, 4.0, 0.05) var infeed_chain_extension: float = 1.85:
	set(value):
		infeed_chain_extension = maxf(value, 0.0)
		_queue_rebuild()

@export_range(0.02, 0.30, 0.01) var position_pin_radius: float = 0.045:
	set(value):
		position_pin_radius = maxf(value, 0.02)
		_queue_rebuild()

@export_range(0.05, 0.60, 0.01) var position_pin_height: float = 0.26:
	set(value):
		position_pin_height = maxf(value, 0.05)
		_queue_rebuild()

@export_range(0.05, 1.0, 0.01) var cushion_pin_extension: float = 0.46:
	set(value):
		cushion_pin_extension = maxf(value, 0.05)
		_queue_rebuild()

@export_range(2, 8, 1) var parking_ramp_stations: int = 4:
	set(value):
		parking_ramp_stations = clampi(value, 2, 8)
		_queue_rebuild()

var _rebuild_queued := false
var _mat_frame: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_guard: StandardMaterial3D
var _mat_blade: StandardMaterial3D
var _mat_motor: StandardMaterial3D
var _mat_warning: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_hydraulic: StandardMaterial3D
var _mat_chain_grip: StandardMaterial3D
var _mat_rubber: StandardMaterial3D

@export_category("Editor Test")
@export var run_editor_preview: bool = false:
	set(value):
		run_editor_preview = value
		if is_inside_tree():
			set_process(run_editor_preview)

@export_range(0.1, 8.0, 0.1, "or_greater") var preview_feed_speed: float = 1.4

const FEED_ROLLER_RADIUS := 0.075
const FEED_ROLLER_LENGTH := 1.14
const HOLD_DOWN_ROLLER_RADIUS := 0.095
const HOLD_DOWN_ROLLER_LENGTH := 0.96
const SAMPLE_BOARD_THICKNESS := 0.045
const SAMPLE_BOARD_LENGTH := 1.35
const SAMPLE_BOARD_WIDTH := 0.32
const SAW_X := -0.18
const INFEED_CHAIN_END_X := SAW_X - 0.18
const CHAIN_LINK_LENGTH := 0.13
const CHAIN_LINK_WIDTH := SAMPLE_BOARD_WIDTH * 0.25
const CHAIN_LINK_THICKNESS := 0.028
const CHAIN_LANE_CLEARANCE := 0.004
const CHAIN_GRIP_TOOTH_HEIGHT := 0.035
const CHAIN_GRIP_TOOTH_LENGTH := 0.055
const CHAIN_GRIP_TOOTH_WIDTH := CHAIN_LINK_WIDTH * 0.42
const HOLD_DOWN_RAISED_OFFSET := 0.24
const HOLD_DOWN_LOWER_SPEED := 0.55
const HOLD_DOWN_RAISE_SPEED := 0.72
const HOLD_DOWN_LEAD_IN := 0.08

var _feed_rollers: Array[CSGCylinder3D] = []
var _infeed_chain_links: Array[Node3D] = []
var _infeed_chain_bases: Array[Vector3] = []
var _hold_down_rollers: Array[CSGCylinder3D] = []
var _hold_down_stations: Array[Dictionary] = []
var _parking_ramp_stations: Array[Dictionary] = []
var _position_pin_stations: Array[Dictionary] = []
var _cushion_pin_stations: Array[Dictionary] = []
var _saw_blades: Array[CSGCylinder3D] = []
var _saw_teeth_roots: Array[Node3D] = []
var _sample_board: CSGBox3D
var _preview_travel := 0.0
var _chain_preview_offset := 0.0


func _ready() -> void:
	_rebuild()
	set_process(run_editor_preview)


func _process(delta: float) -> void:
	if not run_editor_preview:
		return
	_preview_travel = fposmod(_preview_travel + preview_feed_speed * delta, _preview_travel_length())
	_apply_preview_motion(delta)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_rebuild()
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	await get_tree().process_frame
	_rebuild_queued = false
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_hold_down_stations.clear()
	_parking_ramp_stations.clear()
	_position_pin_stations.clear()
	_cushion_pin_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null

	_make_materials()
	_build_frame()
	_build_feed_deck()
	_build_hold_downs()
	_build_saw_box()
	_build_motors_and_drives()
	_build_waste_handling()
	_build_sample_board()
	_apply_preview_motion(0.0)


func _make_materials() -> void:
	_mat_frame = _mat(Color(0.30, 0.32, 0.34), 0.85, 0.34)
	_mat_dark = _mat(Color(0.13, 0.14, 0.15), 0.75, 0.42)
	_mat_guard = _mat(Color(0.20, 0.46, 0.28), 0.55, 0.36)
	_mat_blade = _mat(Color(0.72, 0.72, 0.76), 1.0, 0.16)
	_mat_motor = _mat(Color(0.08, 0.23, 0.34), 0.70, 0.30)
	_mat_warning = _mat(Color(0.95, 0.55, 0.06), 0.55, 0.35)
	_mat_wood = _mat(Color(0.78, 0.64, 0.42), 0.0, 0.78)
	_mat_hydraulic = _mat(Color(0.86, 0.86, 0.88), 1.0, 0.12)
	_mat_chain_grip = _mat(Color(0.42, 0.44, 0.44), 0.9, 0.22)
	_mat_rubber = _mat(Color(0.03, 0.03, 0.035), 0.0, 0.55)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _build_frame() -> void:
	var half_l := bed_length * 0.5
	var half_w := machine_width * 0.5
	var leg_y := working_height * 0.5 - 0.34
	var leg_h := maxf(working_height + 0.28, 0.7)
	var end_xs: Array[float] = [-half_l + 0.28, half_l - 0.28]
	var side_zs: Array[float] = [-half_w + 0.12, half_w - 0.12]

	for x in end_xs:
		for z in side_zs:
			_add_box("Leg", Vector3(x, leg_y, z), Vector3(0.12, leg_h, 0.12), _mat_frame)
			_add_box("Foot", Vector3(x, -0.05, z), Vector3(0.42, 0.08, 0.28), _mat_frame)

	var rail_zs: Array[float] = [-half_w + 0.08, half_w - 0.08]
	for z in rail_zs:
		_add_box("LongFrameRail", Vector3(0, working_height - 0.18, z), Vector3(bed_length, 0.14, 0.12), _mat_frame)
		_add_box("LowerFrameRail", Vector3(0, 0.16, z), Vector3(bed_length * 0.92, 0.10, 0.10), _mat_frame)

	var cross_xs: Array[float] = [-half_l + 0.2, -0.7, 0.7, half_l - 0.2]
	for x in cross_xs:
		_add_box("CrossMember", Vector3(x, working_height - 0.2, 0), Vector3(0.12, 0.12, machine_width), _mat_frame)


func _build_feed_deck() -> void:
	var half_w := machine_width * 0.5
	var fence_zs: Array[float] = [-half_w + 0.22, half_w - 0.22]
	for z in fence_zs:
		_add_box("SideFence", Vector3(0, working_height + 0.18, z), Vector3(bed_length * 0.94, 0.22, 0.06), _mat_frame)

	_build_infeed_chains()

	var roller_y := working_height + 0.04
	var roller_start := SAW_X + 0.58
	var roller_end := bed_length * 0.5 - 0.34
	var roller_count := maxi(feed_roller_count, 2)
	var spacing := (roller_end - roller_start) / float(roller_count - 1)
	for i in range(roller_count):
		var x := roller_start + spacing * float(i)
		var suffix := "_%02d" % (i + 1)
		var roller := _add_cylinder("FeedRoller" + suffix, Vector3(x, roller_y, 0), FEED_ROLLER_RADIUS, FEED_ROLLER_LENGTH, _mat_dark, Vector3(PI * 0.5, 0, 0), 28)
		_feed_rollers.append(roller)
		_add_cylinder("RollerShaft" + suffix, Vector3(x, roller_y, 0), 0.025, machine_width + 0.18, _mat_blade, Vector3(PI * 0.5, 0, 0), 20)


func _build_infeed_chains() -> void:
	var chain_top := _support_top_y()
	var chain_y := chain_top - CHAIN_LINK_THICKNESS * 0.5
	var chain_start := _infeed_chain_start_x()
	var chain_end := INFEED_CHAIN_END_X
	var chain_length := chain_end - chain_start
	if chain_length <= 0.4:
		return

	var lane_pitch := CHAIN_LINK_WIDTH + CHAIN_LANE_CLEARANCE
	var chain_zs: Array[float] = [-lane_pitch, 0.0, lane_pitch]
	for lane_i in range(chain_zs.size()):
		var z := chain_zs[lane_i]
		var lane_suffix := "_%02d" % (lane_i + 1)
		_add_box("InfeedChainWearRail" + lane_suffix, Vector3((chain_start + chain_end) * 0.5, chain_top - 0.07, z), Vector3(chain_length, 0.045, CHAIN_LINK_WIDTH + 0.035), _mat_frame)
		_add_cylinder("InfeedChainIdler" + lane_suffix + "_Entry", Vector3(chain_start, chain_y, z), 0.065, CHAIN_LINK_WIDTH + 0.035, _mat_dark, Vector3(PI * 0.5, 0, 0), 18)
		_add_cylinder("InfeedChainIdler" + lane_suffix + "_SawEnd", Vector3(chain_end, chain_y, z), 0.065, CHAIN_LINK_WIDTH + 0.035, _mat_dark, Vector3(PI * 0.5, 0, 0), 18)

		var link_count := maxi(6, int(chain_length / CHAIN_LINK_LENGTH))
		for i in range(link_count):
			var t := float(i) / float(link_count)
			var x := lerpf(chain_start, chain_end, t)
			var link := _add_infeed_chain_link("InfeedChainLink" + lane_suffix + "_%02d" % (i + 1), Vector3(x, chain_y, z), i)
			_infeed_chain_links.append(link)
			_infeed_chain_bases.append(link.position)

	var centering_start: float = chain_start
	var centering_end: float = _centering_section_end_x()
	_build_parking_ramps(centering_start, centering_end, chain_top)
	_build_position_pins(centering_start, centering_end, chain_top)
	_build_cushion_pins(centering_start, centering_end, chain_top)


func _build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	var usable_length: float = chain_end - chain_start
	if usable_length <= 0.4:
		return

	var station_count: int = maxi(parking_ramp_stations, 2)
	var station_spacing: float = usable_length / float(station_count)
	var ramp_x_size: float = minf(0.46, station_spacing * 0.62)
	var ramp_y_size: float = 0.055
	var ramp_z_size: float = 0.20
	var parked_y: float = chain_top + ramp_y_size * 0.5 + 0.045
	var retracted_y: float = chain_top - 0.16
	var ramp_zs: Array[float] = [-SAMPLE_BOARD_WIDTH * 0.48, SAMPLE_BOARD_WIDTH * 0.48]

	for i in range(station_count):
		var x: float = chain_start + station_spacing * (float(i) + 0.5)
		var station_nodes: Array[Node3D] = []
		var station_bases: Array[Vector3] = []
		for side_i in range(ramp_zs.size()):
			var z: float = ramp_zs[side_i]
			var suffix: String = "_%02d_%s" % [i + 1, "Front" if z < 0.0 else "Back"]
			var ramp: CSGBox3D = _add_box("ParkingRamp" + suffix, Vector3(x, retracted_y, z), Vector3(ramp_x_size, ramp_y_size, ramp_z_size), _mat_hydraulic, Vector3(0.0, 0.0, 0.0))
			station_nodes.append(ramp)
			station_bases.append(Vector3(x, parked_y, z))
			_add_cylinder("ParkingRampCylinder" + suffix, Vector3(x, working_height - 0.09, z), 0.025, 0.24, _mat_dark, Vector3.ZERO, 12)
		_parking_ramp_stations.append({
			"x": x,
			"nodes": station_nodes,
			"bases": station_bases,
			"retracted_y": retracted_y,
			"parked_y": parked_y,
		})


func _build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	var front_z: float = -SAMPLE_BOARD_WIDTH * 0.72
	var raised_y: float = chain_top + position_pin_height * 0.5 + 0.015
	var retracted_y: float = chain_top - position_pin_height * 0.65
	for i in range(station_count):
		var x: float = lerpf(first_x, last_x, float(i) / float(station_count - 1))
		var suffix: String = "_%02d" % (i + 1)
		var pin: CSGCylinder3D = _add_cylinder("PositionPin" + suffix, Vector3(x, retracted_y, front_z), position_pin_radius, position_pin_height, _mat_warning, Vector3.ZERO, 20)
		_add_cylinder("PositionPinSleeve" + suffix, Vector3(x, chain_top - 0.08, front_z), position_pin_radius * 1.25, 0.10, _mat_dark, Vector3.ZERO, 18)
		_position_pin_stations.append({
			"x": x,
			"pin": pin,
			"raised_y": raised_y,
			"retracted_y": retracted_y,
			"z": front_z,
		})


func _build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	var back_z: float = SAMPLE_BOARD_WIDTH * 0.78
	var pin_y: float = chain_top + 0.065
	for i in range(station_count):
		var x: float = lerpf(first_x, last_x, float(i) / float(station_count - 1))
		var suffix: String = "_%02d" % (i + 1)
		var body: Node3D = Node3D.new()
		body.name = "CushionPinAssembly" + suffix
		body.position = Vector3(x, pin_y, back_z)
		add_child(body)

		var barrel: CSGCylinder3D = _add_cylinder_child(body, "CushionCylinder", Vector3(0.0, 0.0, 0.13), 0.035, 0.26, _mat_dark, Vector3(PI * 0.5, 0.0, 0.0), 16)
		var rod: CSGCylinder3D = _add_cylinder_child(body, "CushionRod", Vector3(0.0, 0.0, -0.08), 0.018, cushion_pin_extension, _mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 14)
		var pad: CSGBox3D = _add_box_child(body, "CushionPad", Vector3(0.0, 0.0, -0.08 - cushion_pin_extension * 0.5), Vector3(0.16, 0.12, 0.045), _mat_rubber)
		_cushion_pin_stations.append({
			"x": x,
			"body": body,
			"barrel": barrel,
			"rod": rod,
			"pad": pad,
			"base_z": back_z,
			"extended": false,
		})


func _build_hold_downs() -> void:
	var hold_down_xs: Array[float] = [-1.75, -0.95, 0.45, 1.25]
	var board_top := _board_center_y() + SAMPLE_BOARD_THICKNESS * 0.5
	var roller_y := board_top + HOLD_DOWN_ROLLER_RADIUS - 0.008
	for i in range(hold_down_xs.size()):
		var x := hold_down_xs[i]
		var suffix := "_%02d" % (i + 1)
		_add_box("HoldDownCrosshead" + suffix, Vector3(x, roller_y + 0.34, 0), Vector3(0.12, 0.12, 1.20), _mat_frame)
		_add_box("HoldDownTopPressureBox" + suffix, Vector3(x, roller_y + 0.60, 0), Vector3(0.32, 0.22, 0.92), _mat_frame)
		var hold_down := _add_cylinder("HoldDownRoller" + suffix, Vector3(x, roller_y, 0), HOLD_DOWN_ROLLER_RADIUS, HOLD_DOWN_ROLLER_LENGTH, _mat_warning, Vector3(PI * 0.5, 0, 0), 28)
		_hold_down_rollers.append(hold_down)
		var moving_nodes: Array[Node3D] = [hold_down]
		var axle := _add_cylinder("HoldDownAxle" + suffix, Vector3(x, roller_y, 0), 0.026, 1.12, _mat_hydraulic, Vector3(PI * 0.5, 0, 0), 20)
		moving_nodes.append(axle)

		var side_zs: Array[float] = [-0.46, 0.46]
		for side_i in range(side_zs.size()):
			var z := side_zs[side_i]
			var side_suffix := suffix + ("_L" if z < 0.0 else "_R")
			moving_nodes.append(_add_box("YokeSidePlate" + side_suffix, Vector3(x, roller_y + 0.03, z), Vector3(0.16, 0.30, 0.055), _mat_warning))
			moving_nodes.append(_add_box("YokeUpperLug" + side_suffix, Vector3(x, roller_y + 0.20, z), Vector3(0.16, 0.08, 0.16), _mat_warning))
			_add_cylinder("GuidePost" + side_suffix, Vector3(x - 0.09, roller_y + 0.34, z), 0.026, 0.54, _mat_hydraulic, Vector3.ZERO, 18)
			_add_cylinder("PressureCylinderBarrel" + side_suffix, Vector3(x + 0.09, roller_y + 0.48, z), 0.055, 0.28, _mat_dark, Vector3.ZERO, 24)
			moving_nodes.append(_add_cylinder("PressureCylinderRod" + side_suffix, Vector3(x + 0.09, roller_y + 0.25, z), 0.023, 0.30, _mat_hydraulic, Vector3.ZERO, 18))
			moving_nodes.append(_add_box("RodClevis" + side_suffix, Vector3(x + 0.09, roller_y + 0.09, z), Vector3(0.11, 0.06, 0.07), _mat_hydraulic))
			_add_box("TopClevisBracket" + side_suffix, Vector3(x + 0.09, roller_y + 0.64, z), Vector3(0.13, 0.08, 0.09), _mat_dark)

		var base_positions: Array[Vector3] = []
		for node in moving_nodes:
			base_positions.append(node.position)
			node.position.y += HOLD_DOWN_RAISED_OFFSET
		_hold_down_stations.append({
			"x": x,
			"nodes": moving_nodes,
			"bases": base_positions,
			"offset": HOLD_DOWN_RAISED_OFFSET,
		})


func _build_saw_box() -> void:
	_add_box("MainSawGuard", Vector3(SAW_X, working_height + 0.86, 0), Vector3(0.76, 0.58, machine_width + 0.12), _mat_guard, Vector3.ZERO, false)
	_add_box("UpperThroatLip", Vector3(SAW_X, working_height + 0.49, 0), Vector3(0.88, 0.08, 0.92), _mat_dark, Vector3.ZERO, false)
	for z_sign in [-1.0, 1.0]:
		_add_box("ThroatSideCheek", Vector3(SAW_X, working_height + 0.22, z_sign * 0.58), Vector3(0.88, 0.18, 0.12), _mat_dark, Vector3.ZERO, false)

	var blade_zs: Array[float] = [-saw_spacing * 0.5, 0.0, saw_spacing * 0.5]
	for i in range(blade_zs.size()):
		var z := blade_zs[i]
		var suffix := "_%02d" % (i + 1)
		var blade := _add_cylinder("EdgerSawBlade" + suffix, Vector3(SAW_X, working_height + 0.2, z), blade_radius, 0.035, _mat_blade, Vector3(PI * 0.5, 0, 0), 64, false)
		_saw_blades.append(blade)
		_saw_teeth_roots.append(_add_saw_teeth("EdgerSawTeeth" + suffix, Vector3(SAW_X, working_height + 0.2, z), blade_radius))
		_add_cylinder("BladeHub" + suffix, Vector3(SAW_X, working_height + 0.2, z), 0.12, 0.07, _mat_dark, Vector3(PI * 0.5, 0, 0), 32)
		_add_box("BladeKerfGuard" + suffix, Vector3(SAW_X + 0.12, working_height + 0.39, z), Vector3(0.34, 0.06, 0.09), _mat_warning, Vector3.ZERO, false)

	_add_cylinder("SawArbor", Vector3(SAW_X, working_height + 0.2, 0), 0.045, machine_width + 0.36, _mat_blade, Vector3(PI * 0.5, 0, 0), 28)


func _build_motors_and_drives() -> void:
	var motor_z := machine_width * 0.5 + 0.34
	var motor_zs: Array[float] = [-motor_z, motor_z]
	for z in motor_zs:
		_add_box("MotorMount", Vector3(SAW_X, working_height + 0.08, z), Vector3(0.48, 0.18, 0.18), _mat_frame)
		_add_cylinder("SawMotor", Vector3(SAW_X - 0.22, working_height + 0.25, z), 0.22, 0.48, _mat_motor, Vector3(0, 0, PI * 0.5), 32)
		_add_cylinder("DrivePulley", Vector3(SAW_X + 0.22, working_height + 0.25, z), 0.16, 0.08, _mat_dark, Vector3(0, 0, PI * 0.5), 28)
		_add_box("BeltGuard", Vector3(SAW_X + 0.10, working_height + 0.42, z), Vector3(0.58, 0.10, 0.28), _mat_dark, Vector3(0, 0, 0.18))


func _build_waste_handling() -> void:
	if not show_waste_chutes:
		return

	var chute_z := machine_width * 0.5 + 0.18
	var z_signs: Array[float] = [-1.0, 1.0]
	for z_sign in z_signs:
		var z := chute_z * z_sign
		_add_box("TrimChute", Vector3(0.62, working_height - 0.08, z), Vector3(1.6, 0.06, 0.36), _mat_dark, Vector3(0, 0, -0.16 * z_sign))
		_add_box("ChipConveyorBelt", Vector3(1.15, working_height - 0.32, z + 0.18 * z_sign), Vector3(1.7, 0.08, 0.26), _mat_dark)
		_add_box("ChipConveyorRail", Vector3(1.15, working_height - 0.19, z + 0.34 * z_sign), Vector3(1.7, 0.18, 0.05), _mat_frame)


func _build_sample_board() -> void:
	_sample_board = _add_box("ReferenceBoard", Vector3(-1.7, _board_center_y(), 0), Vector3(SAMPLE_BOARD_LENGTH, SAMPLE_BOARD_THICKNESS, SAMPLE_BOARD_WIDTH), _mat_wood, Vector3.ZERO, false)


func _board_center_y() -> float:
	return _support_top_y() + SAMPLE_BOARD_THICKNESS * 0.5 + 0.004


func _support_top_y() -> float:
	return working_height + 0.04 + FEED_ROLLER_RADIUS


func _infeed_chain_start_x() -> float:
	return -bed_length * 0.5 + 0.34 - infeed_chain_extension


func _machine_infeed_entry_x() -> float:
	return -bed_length * 0.5 + 0.34


func _centering_section_end_x() -> float:
	return _machine_infeed_entry_x() - 0.14


func _preview_board_start_x() -> float:
	return _infeed_chain_start_x() - SAMPLE_BOARD_LENGTH * 0.70


func _preview_travel_length() -> float:
	return bed_length + infeed_chain_extension + SAMPLE_BOARD_LENGTH * 1.4


func _apply_preview_motion(delta: float) -> void:
	var roller_step := (preview_feed_speed / maxf(FEED_ROLLER_RADIUS, 0.001)) * delta
	_chain_preview_offset = fposmod(_chain_preview_offset + preview_feed_speed * delta, CHAIN_LINK_LENGTH)
	_update_infeed_chain_preview()
	for roller in _feed_rollers:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, -roller_step)
	for blade in _saw_blades:
		if is_instance_valid(blade):
			blade.rotate_object_local(Vector3.UP, -18.0 * delta)
	for teeth_root in _saw_teeth_roots:
		if is_instance_valid(teeth_root):
			teeth_root.rotate_object_local(Vector3.FORWARD, -18.0 * delta)

	if is_instance_valid(_sample_board):
		var start_x: float = _preview_board_start_x()
		_sample_board.position.x = start_x + _preview_travel
		_sample_board.position.y = _board_center_y()
		_update_hold_down_preview(delta, _sample_board.position.x)
		_update_centering_preview(delta, _sample_board.position.x)


func _update_infeed_chain_preview() -> void:
	var chain_start := _infeed_chain_start_x()
	var chain_end := INFEED_CHAIN_END_X
	var chain_length := chain_end - chain_start
	if chain_length <= 0.0:
		return
	for i in range(_infeed_chain_links.size()):
		var link := _infeed_chain_links[i]
		if not is_instance_valid(link):
			continue
		var base := _infeed_chain_bases[i]
		link.position = base
		link.position.x = chain_start + fposmod((base.x - chain_start) + _chain_preview_offset, chain_length)


func _update_centering_preview(delta: float, board_center_x: float) -> void:
	var board_leading_x: float = board_center_x + SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x: float = board_center_x - SAMPLE_BOARD_LENGTH * 0.5
	var board_on_centering_section: bool = board_leading_x > _infeed_chain_start_x() and board_trailing_x < _machine_infeed_entry_x()
	var active_pin_indices: Array[int] = []
	if board_on_centering_section:
		active_pin_indices = _select_active_position_pins(board_leading_x, board_trailing_x)
	var centering_active: bool = not active_pin_indices.is_empty()

	if is_instance_valid(_sample_board):
		if board_leading_x < _infeed_chain_start_x():
			_sample_board.position.z = -SAMPLE_BOARD_WIDTH * 0.30
		elif centering_active:
			_sample_board.position.z = move_toward(_sample_board.position.z, 0.0, 0.28 * delta)

	for station in _parking_ramp_stations:
		var target_y: float = float(station["parked_y"]) if board_on_centering_section else float(station["retracted_y"])
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp: Node3D = node as Node3D
			if is_instance_valid(ramp):
				ramp.position.y = move_toward(ramp.position.y, target_y, 1.8 * delta)

	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var pin: Node3D = station["pin"] as Node3D
		if not is_instance_valid(pin):
			continue
		var target_y: float = float(station["raised_y"]) if active_pin_indices.has(i) else float(station["retracted_y"])
		pin.position.y = move_toward(pin.position.y, target_y, 1.6 * delta)

	for station in _cushion_pin_stations:
		var body: Node3D = station["body"] as Node3D
		if not is_instance_valid(body):
			continue
		var target_offset: float = -cushion_pin_extension if centering_active else 0.0
		body.position.z = move_toward(body.position.z, float(station["base_z"]) + target_offset, 2.2 * delta)


func _select_active_position_pins(board_leading_x: float, board_trailing_x: float) -> Array[int]:
	var candidates: Array[Dictionary] = []
	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var x: float = float(station["x"])
		if x <= board_trailing_x + 0.08:
			var dist_to_trailing: float = abs(x - board_trailing_x)
			var dist_to_leading: float = abs(x - board_leading_x)
			candidates.append({
				"index": i,
				"score": minf(dist_to_trailing, dist_to_leading),
			})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)

	var selected: Array[int] = []
	for candidate in candidates:
		selected.append(int(candidate["index"]))
		if selected.size() >= 2:
			break
	return selected


func _update_hold_down_preview(delta: float, board_center_x: float) -> void:
	var board_leading_x := board_center_x + SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := board_center_x - SAMPLE_BOARD_LENGTH * 0.5
	for station in _hold_down_stations:
		var station_x := float(station["x"])
		var should_be_down := board_leading_x >= station_x - HOLD_DOWN_LEAD_IN and board_trailing_x <= station_x
		var target_offset := 0.0 if should_be_down else HOLD_DOWN_RAISED_OFFSET
		var current_offset := float(station["offset"])
		var speed := HOLD_DOWN_LOWER_SPEED if should_be_down else HOLD_DOWN_RAISE_SPEED
		current_offset = move_toward(current_offset, target_offset, speed * delta)
		station["offset"] = current_offset

		var nodes: Array = station["nodes"]
		var bases: Array = station["bases"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position = bases[i] + Vector3(0.0, current_offset, 0.0)
				if node.name.begins_with("HoldDownRoller"):
					node.rotate_object_local(Vector3.UP, (preview_feed_speed / maxf(HOLD_DOWN_ROLLER_RADIUS, 0.001)) * delta)


func _add_infeed_chain_link(node_name: String, local_position: Vector3, index: int) -> Node3D:
	var link_root := Node3D.new()
	link_root.name = node_name
	link_root.position = local_position
	add_child(link_root)

	var link_length := CHAIN_LINK_LENGTH * 0.72
	var side_plate_width := CHAIN_LINK_WIDTH * 0.22
	var side_plate_z := CHAIN_LINK_WIDTH * 0.5 - side_plate_width * 0.5
	_add_box_child(link_root, "OuterPlate_L", Vector3(0.0, 0.0, -side_plate_z), Vector3(link_length, CHAIN_LINK_THICKNESS, side_plate_width), _mat_dark)
	_add_box_child(link_root, "OuterPlate_R", Vector3(0.0, 0.0, side_plate_z), Vector3(link_length, CHAIN_LINK_THICKNESS, side_plate_width), _mat_dark)
	_add_box_child(link_root, "CenterPad", Vector3(0.0, CHAIN_LINK_THICKNESS * 0.18, 0.0), Vector3(link_length * 0.54, CHAIN_LINK_THICKNESS * 0.55, CHAIN_LINK_WIDTH * 0.42), _mat_chain_grip)
	_add_cylinder_child(link_root, "CrossPin", Vector3(0.0, -CHAIN_LINK_THICKNESS * 0.05, 0.0), 0.011, CHAIN_LINK_WIDTH + 0.02, _mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 10)

	var tooth_mesh := _create_chain_grip_tooth_mesh()
	var tooth_xs: Array[float] = [-link_length * 0.22, link_length * 0.22]
	for tooth_i in range(tooth_xs.size()):
		var tooth := MeshInstance3D.new()
		tooth.name = "GripTooth_%02d" % (tooth_i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = _mat_chain_grip
		tooth.position = Vector3(tooth_xs[tooth_i], CHAIN_LINK_THICKNESS * 0.5, 0.0)
		tooth.rotation.y = PI if (index + tooth_i) % 2 == 1 else 0.0
		link_root.add_child(tooth)

	return link_root


func _add_box_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = local_position
	box.size = size
	box.material = material
	box.use_collision = true
	parent.add_child(box)
	return box


func _add_cylinder_child(parent: Node3D, node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = node_name
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = true
	parent.add_child(cylinder)
	return cylinder


func _create_chain_grip_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var half_l := CHAIN_GRIP_TOOTH_LENGTH * 0.5
	var half_w := CHAIN_GRIP_TOOTH_WIDTH * 0.5
	var front := [
		Vector3(-half_l, 0.0, half_w),
		Vector3(half_l, 0.0, half_w),
		Vector3(half_l * 0.35, CHAIN_GRIP_TOOTH_HEIGHT, half_w),
		Vector3(-half_l * 0.75, CHAIN_GRIP_TOOTH_HEIGHT * 0.28, half_w),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_w))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_saw_teeth(node_name: String, center: Vector3, radius: float) -> Node3D:
	var teeth_root := Node3D.new()
	teeth_root.name = node_name
	teeth_root.position = center
	add_child(teeth_root)

	var tooth_mesh := _create_saw_tooth_mesh()
	var tooth_count := 48
	var tooth_root_radius := radius - 0.012
	for i in range(tooth_count):
		var angle := TAU * float(i) / float(tooth_count)
		var tooth := MeshInstance3D.new()
		tooth.name = "Tooth_%02d" % (i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = _mat_blade
		tooth.position = Vector3(cos(angle) * tooth_root_radius, sin(angle) * tooth_root_radius, 0.0)
		tooth.rotation = Vector3(0.0, 0.0, angle)
		teeth_root.add_child(tooth)
	return teeth_root


func _create_saw_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var tooth_depth := 0.055
	var tangential_root := 0.026
	var tangential_tip := 0.006
	var half_thickness := 0.018
	var front := [
		Vector3(0.0, -tangential_root, half_thickness),
		Vector3(tooth_depth * 0.70, -tangential_tip, half_thickness),
		Vector3(tooth_depth, tangential_tip, half_thickness),
		Vector3(0.0, tangential_root, half_thickness),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_thickness))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh_face(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, points: Array, normal: Vector3) -> void:
	var start := vertices.size()
	for point in points:
		vertices.append(point)
		normals.append(normal)
	for i in range(1, points.size() - 1):
		indices.append_array(PackedInt32Array([start, start + i, start + i + 1]))


func _add_mesh_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var start := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _add_box(node_name: String, local_position: Vector3, size: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO, collision: bool = true) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = local_position
	box.rotation = local_rotation
	box.size = size
	box.material = material
	box.use_collision = collision
	add_child(box)
	return box


func _add_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = node_name
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	add_child(cylinder)
	return cylinder
