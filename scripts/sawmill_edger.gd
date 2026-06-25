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
@export_range(0.0, 10.0, 0.05) var infeed_chain_extension: float = 5.6:
	set(value):
		infeed_chain_extension = maxf(value, 0.0)
		_queue_rebuild()

@export var preview_board_scene: PackedScene = preload("res://scenes/cut_board.tscn"):
	set(value):
		preview_board_scene = value
		_queue_rebuild()

@export_range(0.02, 0.30, 0.01) var position_pin_radius: float = 0.045:
	set(value):
		position_pin_radius = maxf(value, 0.02)
		_queue_rebuild()

@export_range(0.05, 0.60, 0.01) var position_pin_height: float = 0.26:
	set(value):
		position_pin_height = maxf(value, 0.05)
		_queue_rebuild()

@export_range(0.20, 4.0, 0.01, "or_greater") var position_pin_spacing: float = 1.56:
	set(value):
		position_pin_spacing = maxf(value, 0.20)
		_queue_rebuild()

@export_range(0.05, 1.0, 0.01) var cushion_pin_extension: float = 0.46:
	set(value):
		cushion_pin_extension = maxf(value, 0.05)
		_queue_rebuild()

@export_range(0.20, 4.0, 0.01, "or_greater") var cushion_pin_spacing: float = 1.56:
	set(value):
		cushion_pin_spacing = maxf(value, 0.20)
		_queue_rebuild()

@export_range(2, 8, 1) var parking_ramp_stations: int = 4:
	set(value):
		parking_ramp_stations = clampi(value, 2, 8)
		_queue_rebuild()

@export_category("Generated Parts")
@export var expose_generated_parts: bool = true:
	set(value):
		expose_generated_parts = value
		if is_inside_tree():
			_adopt_generated_parts()

@export var auto_rebuild_generated_parts: bool = true

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
			if not run_editor_preview:
				_reset_preview_motion()

@export_range(0.1, 8.0, 0.1, "or_greater") var preview_feed_speed: float = 1.4

@export_category("Motion")
@export_range(0.0, 20.0, 0.1, "or_greater") var feed_roller_spin_speed: float = 1.0
@export_range(0.0, 80.0, 0.1, "or_greater") var blade_spin_speed: float = 18.0
@export_range(0.0, 20.0, 0.1, "or_greater") var hold_down_roller_spin_speed: float = 1.0
@export_range(0.0, 2.0, 0.01, "or_greater") var hold_down_raised_offset: float = 0.24
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_lower_speed: float = 0.55
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_raise_speed: float = 0.72
@export_range(0.0, 8.0, 0.01, "or_greater") var parking_ramp_speed: float = 1.8
@export_range(0.0, 8.0, 0.01, "or_greater") var position_pin_speed: float = 1.6
@export_range(0.0, 8.0, 0.01, "or_greater") var cushion_pin_speed: float = 2.2
@export_range(0.0, 4.0, 0.01, "or_greater") var centering_board_speed: float = 0.28
@export_range(0.0, 2.0, 0.01, "or_greater") var pin_retract_delay: float = 0.20
@export_range(0.0, 2.0, 0.01, "or_greater") var feed_chain_start_delay: float = 0.22
@export_range(-4.0, 0.0, 0.01) var side_load_start_z: float = -1.12

const FEED_ROLLER_RADIUS := 0.075
const FEED_ROLLER_LENGTH := 1.14
const HOLD_DOWN_ROLLER_RADIUS := 0.095
const HOLD_DOWN_ROLLER_LENGTH := 0.96
const SAMPLE_BOARD_THICKNESS := 0.04
const SAMPLE_BOARD_LENGTH := 4.8768
const SAMPLE_BOARD_WIDTH := 0.35
const SAW_X := -0.18
const INFEED_CHAIN_END_X := SAW_X - 0.18
const CHAIN_LINK_LENGTH := 0.13
const CHAIN_LINK_WIDTH := SAMPLE_BOARD_WIDTH * 0.25
const CHAIN_LINK_THICKNESS := 0.028
const CHAIN_LANE_CLEARANCE := 0.004
const CHAIN_GRIP_TOOTH_HEIGHT := 0.035
const CHAIN_GRIP_TOOTH_LENGTH := 0.055
const CHAIN_GRIP_TOOTH_WIDTH := CHAIN_LINK_WIDTH * 0.42
const HOLD_DOWN_LEAD_IN := 0.08
const PIN_BOARD_CLEARANCE := 0.05
const PIN_BOARD_X_CONTACT_MARGIN := 0.02
const PIN_READY_TOLERANCE := 0.01
const CENTERING_TOLERANCE := 0.01
const CUSHION_PAD_CONTACT_OFFSET_Z := -0.08 - 0.0225

enum CenteringPreviewPhase {
	SIDE_LOAD,
	RAISE_PINS,
	CENTER_BOARD,
	PIN_RETRACT_DELAY,
	RETRACT_PINS,
	RETURN_PINS_HOME_Z,
	FEED_DELAY,
	FEED_BOARD,
}

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
var _sample_board: Node3D
var _feed_preview_travel := 0.0
var _feed_delay_elapsed := 0.0
var _pin_retract_delay_elapsed := 0.0
var _chain_preview_offset := 0.0
var _centering_preview_phase := CenteringPreviewPhase.SIDE_LOAD
var _active_centering_pin_indices: Array[int] = []
var _preview_board_home_global := Vector3.ZERO
var _generated_name_counts: Dictionary = {}
var _editor_group_stack: Array[Node3D] = []
var _preserved_editor_group_transforms: Dictionary = {}


func _ready() -> void:
	_rebuild()
	set_process(run_editor_preview)


func _process(delta: float) -> void:
	if not run_editor_preview:
		return
	_apply_preview_motion(delta)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and not auto_rebuild_generated_parts:
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
	if Engine.is_editor_hint() and not auto_rebuild_generated_parts and get_child_count() > 0:
		_collect_generated_parts()
		if not _feed_rollers.is_empty() or not _saw_blades.is_empty() or not _infeed_chain_links.is_empty():
			return

	_preserve_editor_group_transforms()
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
	_generated_name_counts.clear()
	_editor_group_stack.clear()

	_make_materials()
	_build_frame()
	_build_feed_deck()
	_build_hold_downs()
	_build_saw_box()
	_build_motors_and_drives()
	_build_waste_handling()
	_build_sample_board()
	_adopt_generated_parts()
	_apply_preview_motion(0.0)


func _collect_generated_parts() -> void:
	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null

	for node in find_children("*", "Node3D", true, false):
		if node.name.begins_with("FeedRoller") and node is CSGCylinder3D:
			_feed_rollers.append(node)
		elif node.name.begins_with("InfeedChainLink"):
			_infeed_chain_links.append(node)
			_infeed_chain_bases.append(node.position)
		elif node.name.begins_with("HoldDownRoller") and node is CSGCylinder3D:
			_hold_down_rollers.append(node)
		elif node.name.begins_with("EdgerSawBlade") and node is CSGCylinder3D:
			_saw_blades.append(node)
		elif node.name.begins_with("EdgerSawTeeth"):
			_saw_teeth_roots.append(node)
		elif node.name.begins_with("ReferenceCutBoard") and node is Node3D:
			_sample_board = node


func _adopt_generated_parts() -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return

	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return

	for child in get_children():
		if child.get_meta("edger_editor_group", false):
			child.owner = scene_root


func _preserve_editor_group_transforms() -> void:
	_preserved_editor_group_transforms.clear()
	for child in get_children():
		if child is Node3D and child.get_meta("edger_editor_group", false):
			_preserved_editor_group_transforms[child.name] = child.transform


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


func _push_editor_group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	group.set_meta("edger_editor_group", true)
	if _preserved_editor_group_transforms.has(group_name):
		group.transform = _preserved_editor_group_transforms[group_name]
	_current_part_parent().add_child(group)
	_adopt_new_node(group)
	_editor_group_stack.append(group)
	return group


func _pop_editor_group() -> void:
	if not _editor_group_stack.is_empty():
		_editor_group_stack.pop_back()


func _current_part_parent() -> Node:
	if _editor_group_stack.is_empty():
		return self
	return _editor_group_stack.back()


func _build_frame() -> void:
	_push_editor_group("FrameAssembly")
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
	_pop_editor_group()


func _build_feed_deck() -> void:
	_push_editor_group("SideFenceAssembly")
	var half_w := machine_width * 0.5
	var fence_zs: Array[float] = [-half_w + 0.22, half_w - 0.22]
	for z in fence_zs:
		_add_box("SideFence", Vector3(0, working_height + 0.18, z), Vector3(bed_length * 0.94, 0.22, 0.06), _mat_frame)
	_pop_editor_group()

	_build_infeed_chains()

	_push_editor_group("LowerFeedRollerAssembly")
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
	_pop_editor_group()


func _build_infeed_chains() -> void:
	_push_editor_group("InfeedChainAssembly")
	var chain_top := _support_top_y()
	var chain_y := chain_top - CHAIN_LINK_THICKNESS * 0.5
	var chain_start := _infeed_chain_start_x()
	var chain_end := INFEED_CHAIN_END_X
	var chain_length := chain_end - chain_start
	if chain_length <= 0.4:
		_pop_editor_group()
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
	_pop_editor_group()

	var centering_start: float = chain_start
	var centering_end: float = _centering_section_end_x()
	_build_parking_ramps(centering_start, centering_end, chain_top)
	_build_position_pins(centering_start, centering_end, chain_top)
	_build_cushion_pins(centering_start, centering_end, chain_top)


func _build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	var usable_length: float = chain_end - chain_start
	if usable_length <= 0.4:
		return

	_push_editor_group("ParkingRampAssembly")
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
	_pop_editor_group()


func _build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	_push_editor_group("PositionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, position_pin_spacing)
	var front_z: float = -SAMPLE_BOARD_WIDTH * 0.72
	var raised_y: float = chain_top + position_pin_height * 0.5 + 0.015
	var retracted_y: float = chain_top - position_pin_height * 0.65
	var sleeve_retracted_y: float = chain_top - 0.08
	var sleeve_raised_y: float = sleeve_retracted_y + raised_y - retracted_y
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var pin: CSGCylinder3D = _add_cylinder("PositionPin" + suffix, Vector3(x, retracted_y, front_z), position_pin_radius, position_pin_height, _mat_warning, Vector3.ZERO, 20)
		var sleeve: CSGCylinder3D = _add_cylinder("PositionPinSleeve" + suffix, Vector3(x, sleeve_retracted_y, front_z), position_pin_radius * 1.25, 0.10, _mat_dark, Vector3.ZERO, 18)
		_position_pin_stations.append({
			"x": x,
			"pin": pin,
			"sleeve": sleeve,
			"raised_y": raised_y,
			"retracted_y": retracted_y,
			"sleeve_raised_y": sleeve_raised_y,
			"sleeve_retracted_y": sleeve_retracted_y,
			"z": front_z,
		})
	_pop_editor_group()


func _build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	var station_count: int = 4
	var first_x: float = chain_start + 0.42
	var last_x: float = chain_end - 0.36
	if last_x <= first_x:
		return

	_push_editor_group("CushionPinAssembly")
	var station_xs: Array[float] = _pin_station_xs(first_x, last_x, station_count, cushion_pin_spacing)
	var back_z: float = SAMPLE_BOARD_WIDTH * 0.78
	var pin_y: float = chain_top + 0.065
	for i in range(station_xs.size()):
		var x: float = station_xs[i]
		var suffix: String = "_%02d" % (i + 1)
		var body: Node3D = Node3D.new()
		body.position = Vector3(x, pin_y, back_z)
		body.name = _friendly_part_name("CushionPinAssembly" + suffix, body.position)
		_current_part_parent().add_child(body)
		_adopt_new_node(body)

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
	_pop_editor_group()


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


func _build_hold_downs() -> void:
	_push_editor_group("UpperHoldDownRollerAssembly")
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
			node.position.y += hold_down_raised_offset
		_hold_down_stations.append({
			"x": x,
			"nodes": moving_nodes,
			"bases": base_positions,
			"offset": hold_down_raised_offset,
		})
	_pop_editor_group()


func _build_saw_box() -> void:
	_push_editor_group("SawBladeAndGuardAssembly")
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
	_pop_editor_group()


func _build_motors_and_drives() -> void:
	_push_editor_group("MotorDriveAssembly")
	var motor_z := machine_width * 0.5 + 0.34
	var motor_zs: Array[float] = [-motor_z, motor_z]
	for z in motor_zs:
		_add_box("MotorMount", Vector3(SAW_X, working_height + 0.08, z), Vector3(0.48, 0.18, 0.18), _mat_frame)
		_add_cylinder("SawMotor", Vector3(SAW_X - 0.22, working_height + 0.25, z), 0.22, 0.48, _mat_motor, Vector3(0, 0, PI * 0.5), 32)
		_add_cylinder("DrivePulley", Vector3(SAW_X + 0.22, working_height + 0.25, z), 0.16, 0.08, _mat_dark, Vector3(0, 0, PI * 0.5), 28)
		_add_box("BeltGuard", Vector3(SAW_X + 0.10, working_height + 0.42, z), Vector3(0.58, 0.10, 0.28), _mat_dark, Vector3(0, 0, 0.18))
	_pop_editor_group()


func _build_waste_handling() -> void:
	if not show_waste_chutes:
		return

	_push_editor_group("WasteHandlingAssembly")
	var chute_z := machine_width * 0.5 + 0.18
	var z_signs: Array[float] = [-1.0, 1.0]
	for z_sign in z_signs:
		var z := chute_z * z_sign
		_add_box("TrimChute", Vector3(0.62, working_height - 0.08, z), Vector3(1.6, 0.06, 0.36), _mat_dark, Vector3(0, 0, -0.16 * z_sign))
		_add_box("ChipConveyorBelt", Vector3(1.15, working_height - 0.32, z + 0.18 * z_sign), Vector3(1.7, 0.08, 0.26), _mat_dark)
		_add_box("ChipConveyorRail", Vector3(1.15, working_height - 0.19, z + 0.34 * z_sign), Vector3(1.7, 0.18, 0.05), _mat_frame)
	_pop_editor_group()


func _build_sample_board() -> void:
	_push_editor_group("ReferenceBoardAssembly")
	var board := _create_reference_board()
	board.position = Vector3(_preview_board_start_x(), _board_center_y(), side_load_start_z)
	_current_part_parent().add_child(board)
	_sample_board = board
	_preview_board_home_global = board.global_position
	_pop_editor_group()


func _create_reference_board() -> Node3D:
	var board: Node3D = null
	if preview_board_scene:
		board = preview_board_scene.instantiate() as Node3D
	if board == null:
		board = _create_fallback_reference_board()
	board.name = "ReferenceCutBoard"
	board.set_script(null)
	if board is RigidBody3D:
		var rigid := board as RigidBody3D
		rigid.freeze = true
		rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid.linear_velocity = Vector3.ZERO
		rigid.angular_velocity = Vector3.ZERO
		rigid.collision_layer = 0
		rigid.collision_mask = 0
	board.set_process(false)
	board.set_physics_process(false)
	return board


func _create_fallback_reference_board() -> Node3D:
	var body := Node3D.new()
	body.name = "ReferenceCutBoardFallback"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(SAMPLE_BOARD_LENGTH, SAMPLE_BOARD_THICKNESS, SAMPLE_BOARD_WIDTH)
	box.material = _mat_wood
	mesh.mesh = box
	body.add_child(mesh)
	return body


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
	return _infeed_chain_start_x() + SAMPLE_BOARD_LENGTH * 0.5


func _feed_preview_length() -> float:
	return bed_length + infeed_chain_extension + SAMPLE_BOARD_LENGTH * 0.5


func _apply_preview_motion(delta: float) -> void:
	if not is_instance_valid(_sample_board):
		return

	match _centering_preview_phase:
		CenteringPreviewPhase.SIDE_LOAD:
			_update_side_load_phase(delta)
		CenteringPreviewPhase.RAISE_PINS:
			_update_pin_actuators(delta, true, false)
			if _active_pins_are_raised() and _active_cushions_are_at_target():
				_centering_preview_phase = CenteringPreviewPhase.CENTER_BOARD
		CenteringPreviewPhase.CENTER_BOARD:
			_update_pin_actuators(delta, true, true)
			_update_center_board_phase(delta)
		CenteringPreviewPhase.PIN_RETRACT_DELAY:
			_update_pin_actuators(delta, true, false)
			_pin_retract_delay_elapsed += delta
			if _pin_retract_delay_elapsed >= pin_retract_delay:
				_centering_preview_phase = CenteringPreviewPhase.RETRACT_PINS
		CenteringPreviewPhase.RETRACT_PINS:
			_update_pin_actuators(delta, false, false)
			if _pins_are_retracted_down() and _cushions_are_home():
				_centering_preview_phase = CenteringPreviewPhase.RETURN_PINS_HOME_Z
		CenteringPreviewPhase.RETURN_PINS_HOME_Z:
			_update_position_pins_z_home(delta)
			_update_cushion_pins_home(delta)
			if _pins_and_cushions_are_home():
				_feed_delay_elapsed = 0.0
				_centering_preview_phase = CenteringPreviewPhase.FEED_DELAY
		CenteringPreviewPhase.FEED_DELAY:
			_feed_delay_elapsed += delta
			if _feed_delay_elapsed >= feed_chain_start_delay:
				_centering_preview_phase = CenteringPreviewPhase.FEED_BOARD
		CenteringPreviewPhase.FEED_BOARD:
			_update_feed_board_phase(delta)

	_update_parking_ramp_preview(delta)
	_update_hold_down_preview(delta, to_local(_sample_board.global_position).x)


func _reset_preview_motion() -> void:
	_feed_preview_travel = 0.0
	_feed_delay_elapsed = 0.0
	_pin_retract_delay_elapsed = 0.0
	_chain_preview_offset = 0.0
	_centering_preview_phase = CenteringPreviewPhase.SIDE_LOAD
	_active_centering_pin_indices = _select_board_contact_position_pins()
	_update_infeed_chain_preview()

	for roller in _feed_rollers:
		if is_instance_valid(roller):
			roller.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for roller in _hold_down_rollers:
		if is_instance_valid(roller):
			roller.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for blade in _saw_blades:
		if is_instance_valid(blade):
			blade.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for teeth_root in _saw_teeth_roots:
		if is_instance_valid(teeth_root):
			teeth_root.rotation = Vector3.ZERO

	if is_instance_valid(_sample_board):
		if _preview_board_home_global == Vector3.ZERO:
			_preview_board_home_global = _sample_board.global_position
		_sample_board.global_position = _preview_board_home_global

	_reset_centering_preview()
	_reset_hold_down_preview()


func _reset_centering_preview() -> void:
	for station in _parking_ramp_stations:
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp := node as Node3D
			if is_instance_valid(ramp):
				ramp.position.y = float(station["retracted_y"])

	for station in _position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin):
			pin.position.y = float(station["retracted_y"])
			pin.position.z = float(station["z"])
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve):
			sleeve.position.y = float(station["sleeve_retracted_y"])
			sleeve.position.z = float(station["z"])

	for station in _cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body):
			body.position.z = float(station["base_z"])


func _reset_hold_down_preview() -> void:
	for station in _hold_down_stations:
		station["offset"] = hold_down_raised_offset
		var nodes: Array = station["nodes"]
		var bases: Array = station["bases"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position = bases[i] + Vector3(0.0, hold_down_raised_offset, 0.0)


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


func _update_side_load_phase(delta: float) -> void:
	var target_z := _board_pin_clear_z()
	var board_position := _sample_board.global_position
	board_position.z = move_toward(board_position.z, target_z, centering_board_speed * delta)
	_sample_board.global_position = board_position
	if absf(_sample_board.global_position.z - target_z) <= CENTERING_TOLERANCE:
		_active_centering_pin_indices = _select_board_contact_position_pins()
		_centering_preview_phase = CenteringPreviewPhase.RAISE_PINS


func _update_center_board_phase(delta: float) -> void:
	var target_z := _board_center_target_z()
	var board_position := _sample_board.global_position
	board_position.z = move_toward(board_position.z, target_z, centering_board_speed * delta)
	_sample_board.global_position = board_position
	if absf(_sample_board.global_position.z - target_z) <= CENTERING_TOLERANCE:
		_pin_retract_delay_elapsed = 0.0
		_centering_preview_phase = CenteringPreviewPhase.PIN_RETRACT_DELAY


func _update_feed_board_phase(delta: float) -> void:
	var feed_step := preview_feed_speed * delta
	_feed_preview_travel += feed_step
	_chain_preview_offset = fposmod(_chain_preview_offset + feed_step, CHAIN_LINK_LENGTH)
	_update_infeed_chain_preview()

	var board_position := _sample_board.global_position
	board_position.x += feed_step
	_sample_board.global_position = board_position

	var roller_step := (preview_feed_speed / maxf(FEED_ROLLER_RADIUS, 0.001)) * feed_roller_spin_speed * delta
	for roller in _feed_rollers:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, -roller_step)
	for blade in _saw_blades:
		if is_instance_valid(blade):
			blade.rotate_object_local(Vector3.UP, -blade_spin_speed * delta)
	for teeth_root in _saw_teeth_roots:
		if is_instance_valid(teeth_root):
			teeth_root.rotate_object_local(Vector3.FORWARD, -blade_spin_speed * delta)

	if _feed_preview_travel >= _feed_preview_length():
		_reset_preview_motion()


func _update_parking_ramp_preview(delta: float) -> void:
	var board_center_x := to_local(_sample_board.global_position).x
	var board_leading_x: float = board_center_x + SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x: float = board_center_x - SAMPLE_BOARD_LENGTH * 0.5
	var board_on_centering_section: bool = board_leading_x > _infeed_chain_start_x() and board_trailing_x < _machine_infeed_entry_x()
	for station in _parking_ramp_stations:
		var target_y: float = float(station["parked_y"]) if board_on_centering_section else float(station["retracted_y"])
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp: Node3D = node as Node3D
			if is_instance_valid(ramp):
				ramp.position.y = move_toward(ramp.position.y, target_y, parking_ramp_speed * delta)


func _update_pin_actuators(delta: float, active: bool, push_board: bool) -> void:
	var hold_position_pin_z := not push_board and (
		_centering_preview_phase == CenteringPreviewPhase.PIN_RETRACT_DELAY
		or _centering_preview_phase == CenteringPreviewPhase.RETRACT_PINS
	)
	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var pin: Node3D = station["pin"] as Node3D
		var sleeve: Node3D = station["sleeve"] as Node3D
		if not is_instance_valid(pin) and not is_instance_valid(sleeve):
			continue
		var target_y: float = float(station["raised_y"]) if active and _active_centering_pin_indices.has(i) else float(station["retracted_y"])
		var sleeve_target_y: float = float(station["sleeve_raised_y"]) if active and _active_centering_pin_indices.has(i) else float(station["sleeve_retracted_y"])
		var target_z := _position_pin_target_z(i, active, push_board)
		if is_instance_valid(pin):
			pin.position.y = move_toward(pin.position.y, target_y, position_pin_speed * delta)
			if not hold_position_pin_z:
				pin.position.z = move_toward(pin.position.z, target_z, centering_board_speed * delta)
		if is_instance_valid(sleeve):
			sleeve.position.y = move_toward(sleeve.position.y, sleeve_target_y, position_pin_speed * delta)
			if not hold_position_pin_z:
				sleeve.position.z = move_toward(sleeve.position.z, target_z, centering_board_speed * delta)

	for i in range(_cushion_pin_stations.size()):
		var station: Dictionary = _cushion_pin_stations[i]
		var body: Node3D = station["body"] as Node3D
		if not is_instance_valid(body):
			continue
		var target_z := _cushion_target_z(i, active)
		body.position.z = move_toward(body.position.z, target_z, cushion_pin_speed * delta)


func _update_position_pins_z_home(delta: float) -> void:
	for station in _position_pin_stations:
		var base_z := float(station["z"])
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin):
			pin.position.y = float(station["retracted_y"])
			pin.position.z = move_toward(pin.position.z, base_z, centering_board_speed * delta)
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve):
			sleeve.position.y = float(station["sleeve_retracted_y"])
			sleeve.position.z = move_toward(sleeve.position.z, base_z, centering_board_speed * delta)


func _update_cushion_pins_home(delta: float) -> void:
	for station in _cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body):
			body.position.z = move_toward(body.position.z, float(station["base_z"]), cushion_pin_speed * delta)


func _board_pin_clear_z() -> float:
	var pin_z := 0.0
	var found_pin := false
	for index in _select_board_contact_position_pins():
		if index < 0 or index >= _position_pin_stations.size():
			continue
		var pin := _position_pin_stations[index]["pin"] as Node3D
		if is_instance_valid(pin):
			pin_z = pin.global_position.z if not found_pin else maxf(pin_z, pin.global_position.z)
			found_pin = true
	if not found_pin:
		return _preview_board_home_global.z
	return maxf(_preview_board_home_global.z, pin_z + SAMPLE_BOARD_WIDTH * 0.5 + PIN_BOARD_CLEARANCE)


func _board_center_target_z() -> float:
	return global_transform.origin.z


func _position_pin_target_z(index: int, active: bool, push_board: bool) -> float:
	var station: Dictionary = _position_pin_stations[index]
	var base_z := float(station["z"])
	if not active or not push_board or not _active_centering_pin_indices.has(index):
		return base_z
	if not is_instance_valid(_sample_board):
		return base_z

	var board_minus_edge_global_z := _sample_board.global_position.z - SAMPLE_BOARD_WIDTH * 0.5
	var pin_node := station["pin"] as Node3D
	var parent_node: Node3D = null
	if is_instance_valid(pin_node):
		parent_node = pin_node.get_parent() as Node3D
	var board_minus_edge_local_z := board_minus_edge_global_z
	if is_instance_valid(parent_node):
		board_minus_edge_local_z = parent_node.to_local(Vector3(_sample_board.global_position.x, _sample_board.global_position.y, board_minus_edge_global_z)).z
	return maxf(base_z, board_minus_edge_local_z - position_pin_radius)


func _cushion_target_z(index: int, active: bool) -> float:
	var station: Dictionary = _cushion_pin_stations[index]
	var base_z := float(station["base_z"])
	if not active or not _active_centering_pin_indices.has(index):
		return base_z

	var fully_extended_z := base_z - cushion_pin_extension
	var body := station["body"] as Node3D
	if not is_instance_valid(body) or not is_instance_valid(_sample_board):
		return fully_extended_z

	var board_plus_edge_global_z := _sample_board.global_position.z + SAMPLE_BOARD_WIDTH * 0.5
	var parent_node := body.get_parent() as Node3D
	var board_plus_edge_local_z := board_plus_edge_global_z
	if is_instance_valid(parent_node):
		board_plus_edge_local_z = parent_node.to_local(Vector3(_sample_board.global_position.x, _sample_board.global_position.y, board_plus_edge_global_z)).z

	var pad_contact_offset := CUSHION_PAD_CONTACT_OFFSET_Z - cushion_pin_extension * 0.5
	var contact_z := board_plus_edge_local_z - pad_contact_offset
	return clampf(contact_z, fully_extended_z, base_z)


func _active_pins_are_raised() -> bool:
	for index in _active_centering_pin_indices:
		if index < 0 or index >= _position_pin_stations.size():
			continue
		var station: Dictionary = _position_pin_stations[index]
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin) and absf(pin.position.y - float(station["raised_y"])) > PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - float(station["sleeve_raised_y"])) > PIN_READY_TOLERANCE:
			return false
	return not _active_centering_pin_indices.is_empty()


func _active_cushions_are_at_target() -> bool:
	for index in _active_centering_pin_indices:
		if index < 0 or index >= _cushion_pin_stations.size():
			continue
		var station: Dictionary = _cushion_pin_stations[index]
		var body := station["body"] as Node3D
		if is_instance_valid(body) and absf(body.position.z - _cushion_target_z(index, true)) > PIN_READY_TOLERANCE:
			return false
	return not _active_centering_pin_indices.is_empty()


func _pins_are_retracted_down() -> bool:
	for station in _position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin) and absf(pin.position.y - float(station["retracted_y"])) > PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - float(station["sleeve_retracted_y"])) > PIN_READY_TOLERANCE:
			return false
	return true


func _cushions_are_home() -> bool:
	for station in _cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body) and absf(body.position.z - float(station["base_z"])) > PIN_READY_TOLERANCE:
			return false
	return true


func _pins_and_cushions_are_home() -> bool:
	for station in _position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin) and absf(pin.position.y - float(station["retracted_y"])) > PIN_READY_TOLERANCE:
			return false
		if is_instance_valid(pin) and absf(pin.position.z - float(station["z"])) > PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - float(station["sleeve_retracted_y"])) > PIN_READY_TOLERANCE:
			return false
		if is_instance_valid(sleeve) and absf(sleeve.position.z - float(station["z"])) > PIN_READY_TOLERANCE:
			return false
	return _cushions_are_home()


func _select_board_contact_position_pins() -> Array[int]:
	var candidates: Array[Dictionary] = []
	var board_center_x := _board_center_x_for_pin_selection()
	var board_start_x := board_center_x - SAMPLE_BOARD_LENGTH * 0.5
	var board_end_x := board_center_x + SAMPLE_BOARD_LENGTH * 0.5
	var contact_min_x := board_start_x - position_pin_radius - PIN_BOARD_X_CONTACT_MARGIN
	var contact_max_x := board_end_x + position_pin_radius + PIN_BOARD_X_CONTACT_MARGIN

	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var station_x := float(station["x"])
		if station_x < contact_min_x or station_x > contact_max_x:
			continue
		candidates.append({
			"index": i,
			"x": station_x,
			"start_distance": absf(station_x - board_start_x),
			"end_distance": absf(station_x - board_end_x),
		})

	var selected: Array[int] = []
	if candidates.is_empty():
		return selected

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["start_distance"]) < float(b["start_distance"])
	)
	selected.append(int(candidates[0]["index"]))

	if candidates.size() > 1:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["end_distance"]) < float(b["end_distance"])
		)
		for candidate in candidates:
			var index := int(candidate["index"])
			if not selected.has(index):
				selected.append(index)
				break
	return selected


func _board_center_x_for_pin_selection() -> float:
	if is_instance_valid(_sample_board):
		return to_local(_sample_board.global_position).x
	return to_local(_preview_board_home_global).x


func _update_hold_down_preview(delta: float, board_center_x: float) -> void:
	var board_leading_x := board_center_x + SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := board_center_x - SAMPLE_BOARD_LENGTH * 0.5
	for station in _hold_down_stations:
		var station_x := float(station["x"])
		var should_be_down := board_leading_x >= station_x - HOLD_DOWN_LEAD_IN and board_trailing_x <= station_x
		var target_offset := 0.0 if should_be_down else hold_down_raised_offset
		var current_offset := float(station["offset"])
		var speed := hold_down_lower_speed if should_be_down else hold_down_raise_speed
		current_offset = move_toward(current_offset, target_offset, speed * delta)
		station["offset"] = current_offset

		var nodes: Array = station["nodes"]
		var bases: Array = station["bases"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position = bases[i] + Vector3(0.0, current_offset, 0.0)
				if node.name.begins_with("HoldDownRoller"):
					node.rotate_object_local(Vector3.UP, (preview_feed_speed / maxf(HOLD_DOWN_ROLLER_RADIUS, 0.001)) * hold_down_roller_spin_speed * delta)


func _add_infeed_chain_link(node_name: String, local_position: Vector3, index: int) -> Node3D:
	var link_root := Node3D.new()
	link_root.name = node_name
	link_root.position = local_position
	_current_part_parent().add_child(link_root)
	_adopt_new_node(link_root)

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
		_adopt_new_node(tooth)

	return link_root


func _add_box_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = local_position
	box.size = size
	box.material = material
	box.use_collision = true
	parent.add_child(box)
	_adopt_new_node(box)
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
	_adopt_new_node(cylinder)
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
	_current_part_parent().add_child(teeth_root)
	_adopt_new_node(teeth_root)

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
		_adopt_new_node(tooth)
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
	box.name = _friendly_part_name(node_name, local_position)
	box.position = local_position
	box.rotation = local_rotation
	box.size = size
	box.material = material
	box.use_collision = collision
	_current_part_parent().add_child(box)
	_adopt_new_node(box)
	return box


func _add_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = _friendly_part_name(node_name, local_position)
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	_current_part_parent().add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _adopt_new_node(node: Node) -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return
	if not node.get_meta("edger_editor_group", false):
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root != null and node != scene_root:
		node.owner = scene_root


func _friendly_part_name(base_name: String, local_position: Vector3) -> String:
	var name := "%s_%s" % [base_name, _position_name_suffix(local_position)]
	name = name.replace("__", "_").strip_edges(false, true)
	var used_count := int(_generated_name_counts.get(name, 0)) + 1
	_generated_name_counts[name] = used_count
	if used_count > 1:
		name = "%s_%02d" % [name, used_count]
	return name


func _position_name_suffix(local_position: Vector3) -> String:
	var parts: Array[String] = []
	if local_position.x < -0.18:
		parts.append("Infeed")
	elif local_position.x > 0.18:
		parts.append("Outfeed")
	else:
		parts.append("CenterX")

	if local_position.z < -0.08:
		parts.append("Front")
	elif local_position.z > 0.08:
		parts.append("Back")
	else:
		parts.append("CenterZ")

	if local_position.y < working_height - 0.12:
		parts.append("Lower")
	elif local_position.y > working_height + 0.32:
		parts.append("Upper")
	else:
		parts.append("Mid")

	return "_".join(PackedStringArray(parts))
