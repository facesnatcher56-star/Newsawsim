@tool
class_name SawmillEdger
extends StaticBody3D

const SawmillEdgerAssemblyBuilder := preload("res://scripts/sawmill_edger_assembly_builder.gd")

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

@export_category("Infeed Integration")
@export var infeed_deck: Node3D = null

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

@export_range(-0.20, 0.20, 0.001) var preview_board_y_offset: float = -0.029:
	set(value):
		preview_board_y_offset = value
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
@export var use_saved_assembly_scenes: bool = false:
	set(value):
		use_saved_assembly_scenes = value
		_queue_rebuild()

@export var frame_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/frame_assembly.tscn")
@export var side_fence_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/side_fence_assembly.tscn")
@export var infeed_chain_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/infeed_chain_assembly.tscn")
@export var parking_ramp_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/parking_ramp_assembly.tscn")
@export var infeed_hold_down_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/infeed_hold_down_roller_assembly.tscn")
@export var position_pin_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/position_pin_assembly.tscn")
@export var cushion_pin_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/cushion_pin_assembly.tscn")
@export var lower_feed_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/lower_feed_roller_assembly.tscn")
@export var upper_hold_down_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/upper_hold_down_roller_assembly.tscn")
@export var saw_blade_and_guard_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/saw_blade_and_guard_assembly.tscn")
@export var motor_drive_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/motor_drive_assembly.tscn")
@export var waste_handling_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/waste_handling_assembly.tscn")
@export var reference_board_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/reference_board_assembly.tscn")

var _rebuild_queued := false
var _mat_frame: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_guard: StandardMaterial3D
var _mat_blade: StandardMaterial3D
var _mat_motor: StandardMaterial3D
var _mat_warning: StandardMaterial3D
var _mat_infeed_hold_down: Material
var _mat_wood: StandardMaterial3D
var _mat_hydraulic: StandardMaterial3D
var _mat_chain_grip: StandardMaterial3D
var _mat_rubber: StandardMaterial3D

@export_category("Motion")
@export_range(0.1, 8.0, 0.1, "or_greater") var infeed_chain_feed_speed: float = 1.4
@export_range(0.0, 20.0, 0.1, "or_greater") var feed_roller_spin_speed: float = 1.0
@export_range(0.0, 80.0, 0.1, "or_greater") var blade_spin_speed: float = 18.0
@export_range(0.0, 2.0, 0.01, "or_greater") var hold_down_raised_offset: float = 0.24
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_lower_speed: float = 0.55
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_raise_speed: float = 0.72
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_roller_spin_speed: float = 1.0
@export_range(0.0, 80.0, 0.1, "or_greater") var hold_down_roller_spin_accel: float = 18.0
@export_range(0.0, 80.0, 0.1, "or_greater") var hold_down_roller_spin_stop_rate: float = 10.0
@export_range(0.0, 8.0, 0.01, "or_greater") var parking_ramp_speed: float = 1.8
@export_range(0.0, 8.0, 0.01, "or_greater") var position_pin_speed: float = 1.6
@export_range(0.0, 8.0, 0.01, "or_greater") var cushion_pin_speed: float = 2.2
@export_range(0.0, 4.0, 0.01, "or_greater") var centering_board_speed: float = 0.28
@export_range(0.0, 2.0, 0.01, "or_greater") var pin_retract_delay: float = 0.20
@export_range(0.0, 2.0, 0.01, "or_greater") var feed_chain_start_delay: float = 0.22
@export_range(-4.0, 0.0, 0.01) var side_load_start_z: float = -1.12

@export_category("Board Physics")
@export var enable_board_physics_contacts: bool = true
@export_range(0.0, 2000.0, 1.0, "or_greater") var board_feed_force: float = 420.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var parking_ramp_lift_force: float = 520.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parking_ramp_lift_damping: float = 35.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var centering_pin_force: float = 260.0
@export_range(0.0, 200.0, 1.0, "or_greater") var centering_pin_damping: float = 28.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var hold_down_contact_force: float = 360.0

const FEED_ROLLER_RADIUS := 0.075
const FEED_ROLLER_LENGTH := 1.14
const HOLD_DOWN_ROLLER_RADIUS := 0.095
const HOLD_DOWN_ROLLER_LENGTH := 0.96
const INFEED_HOLD_DOWN_ROLLER_RADIUS := 0.135
const INFEED_HOLD_DOWN_ROLLER_LENGTH := HOLD_DOWN_ROLLER_LENGTH * 0.5
const SAMPLE_BOARD_THICKNESS := 0.04
const SAMPLE_BOARD_LENGTH := 4.958
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

var _feed_rollers: Array[Node3D] = []
var _infeed_chain_links: Array[Node3D] = []
var _infeed_chain_bases: Array[Vector3] = []
var _hold_down_rollers: Array[Node3D] = []
var _hold_down_stations: Array[Dictionary] = []
var _infeed_hold_down_rollers: Array[Node3D] = []
var _infeed_hold_down_stations: Array[Dictionary] = []
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
var _centering_preview_phase := 0
var _active_centering_pin_indices: Array[int] = []
var _preview_board_home_global := Vector3.ZERO
var _generated_name_counts: Dictionary = {}
var _editor_group_stack: Array[Node3D] = []
var _preserved_editor_group_transforms: Dictionary = {}
var _assembly_builder: RefCounted


func _ready() -> void:
	_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enable_board_physics_contacts:
		return
	_apply_real_board_contacts(delta)


func _apply_real_board_contacts(delta: float) -> void:
	var boards := _real_cut_boards()
	if boards.is_empty():
		return

	# Check if any board is in the top_zone to trigger pin engagement
	var boards_in_top_zone := _get_boards_in_top_zone()

	_update_real_parking_ramps(delta, boards)
	_update_real_position_pins(delta, boards, boards_in_top_zone)
	_update_real_cushion_pins(delta, boards, boards_in_top_zone)

	# Pause deck if board is in top zone
	_set_infeed_deck_pause(not boards_in_top_zone.is_empty())

	_spin_real_contact_parts(delta, boards)
	for body in boards:
		var local_center := to_local(body.global_position)
		# Prevent affecting boards across the map (e.g. cut_board.tscn far away)
		if absf(local_center.z) > 4.5 or absf(local_center.y - working_height) > 0.6:
			continue
		if not _board_overlaps_x_range(local_center.x, _infeed_chain_start_x() - 0.35, bed_length * 0.5 + 0.55):
			continue
		body.sleeping = false
		_apply_feed_contact(body, local_center)
		_apply_parking_ramp_edge_contacts(body, local_center)
		_apply_centering_pin_contacts(body, local_center, delta)
		_apply_hold_down_contacts(body, local_center)


func _real_cut_boards() -> Array[RigidBody3D]:
	var boards: Array[RigidBody3D] = []
	if not is_inside_tree():
		return boards
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var body := node as RigidBody3D
		if not is_instance_valid(body):
			continue
		if body == _sample_board or body.freeze:
			continue
		boards.append(body)
	return boards


func _apply_feed_contact(body: RigidBody3D, local_center: Vector3) -> void:
	if not _board_overlaps_x_range(local_center.x, _infeed_chain_start_x(), bed_length * 0.5):
		return

	# Feed boards through the chain
	if local_center.x > _centering_section_end_x() + 0.2:
		pass  # Allow feeding
	else:
		return

	var x_axis := global_transform.basis.x.normalized()
	var current_speed := body.linear_velocity.dot(x_axis)
	var speed_error := infeed_chain_feed_speed - current_speed
	var force := clampf(speed_error * body.mass * 18.0, -board_feed_force, board_feed_force)
	body.apply_central_force(x_axis * force)


func _apply_parking_ramp_edge_contacts(body: RigidBody3D, local_center: Vector3) -> void:
	var edge_lifts := _parking_ramp_edge_lifts_for_board(body, local_center)
	if edge_lifts == Vector2.ZERO:
		return

	var y_axis := global_transform.basis.y.normalized()
	var base_center_y := to_global(Vector3(0.0, _preview_board_center_y(), 0.0)).dot(y_axis)
	var bounds := _get_board_local_z_bounds_for_body(body)
	_apply_board_edge_lift(body, bounds.x - local_center.z, base_center_y + edge_lifts.x, y_axis)
	_apply_board_edge_lift(body, bounds.y - local_center.z, base_center_y + edge_lifts.y, y_axis)


func _apply_board_edge_lift(body: RigidBody3D, local_z: float, target_axis_y: float, y_axis: Vector3) -> void:
	var edge_global := body.global_transform * Vector3(0.0, 0.0, local_z)
	var edge_axis_y := edge_global.dot(y_axis)
	var height_error := target_axis_y - edge_axis_y
	if height_error <= -0.003:
		return

	var force_offset := edge_global - body.global_position
	var point_velocity := body.linear_velocity + body.angular_velocity.cross(force_offset)
	var lift_force := height_error * parking_ramp_lift_force * 22.0
	lift_force -= point_velocity.dot(y_axis) * parking_ramp_lift_damping * body.mass
	lift_force = clampf(lift_force, 0.0, parking_ramp_lift_force)
	if lift_force > 0.0:
		body.apply_force(y_axis * lift_force, force_offset)


func _apply_centering_pin_contacts(body: RigidBody3D, local_center: Vector3, delta: float) -> void:
	# Centering is now handled by position and cushion pins - this is disabled
	return


func _apply_hold_down_contacts(body: RigidBody3D, local_center: Vector3) -> void:
	var has_contact := false
	for station in _infeed_hold_down_stations:
		if _board_overlaps_x_range(local_center.x, float(station["x"]) - INFEED_HOLD_DOWN_ROLLER_RADIUS, float(station["x"]) + INFEED_HOLD_DOWN_ROLLER_RADIUS):
			has_contact = true
			break
	if not has_contact:
		for roller in _contact_rollers("HoldDownRoller"):
			if _board_overlaps_x_range(local_center.x, roller.position.x - HOLD_DOWN_ROLLER_RADIUS, roller.position.x + HOLD_DOWN_ROLLER_RADIUS):
				has_contact = true
				break
	if not has_contact:
		for roller in _contact_rollers("InfeedHoldDownRoller"):
			if _board_overlaps_x_range(local_center.x, roller.position.x - INFEED_HOLD_DOWN_ROLLER_RADIUS, roller.position.x + INFEED_HOLD_DOWN_ROLLER_RADIUS):
				has_contact = true
				break
	if not has_contact:
		return

	var y_axis := global_transform.basis.y.normalized()
	body.apply_central_force(-y_axis * hold_down_contact_force)
	_apply_feed_contact(body, local_center)


func _update_real_parking_ramps(delta: float, _boards: Array[RigidBody3D]) -> void:
	var ramps := _parking_ramp_nodes()
	if ramps.is_empty():
		return
	# Ramps stay retracted - position and cushion pins handle board positioning
	var should_raise := false
	for ramp in ramps:
		var target_angle := float(ramp.get_meta("retracted_angle", 0.0))
		ramp.rotation.x = move_toward(ramp.rotation.x, target_angle, parking_ramp_speed * delta)


func _select_position_pins_for_board(board: RigidBody3D) -> Array[int]:
	var selected_indices: Array[int] = []
	var candidates: Array[Dictionary] = []

	var local_center := to_local(board.global_position)
	var board_min_x := local_center.x - SAMPLE_BOARD_LENGTH * 0.5
	var board_max_x := local_center.x + SAMPLE_BOARD_LENGTH * 0.5

	# Find all position pins that overlap with the board's X range
	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var pin_x := float(station["x"])
		# Check if this pin's X position falls within board's X range
		if pin_x >= board_min_x and pin_x <= board_max_x:
			candidates.append({"index": i, "x": pin_x})

	if candidates.size() < 2:
		return selected_indices

	# Sort by X position to find the two furthest apart
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["x"]) < float(b["x"])
	)

	# Select the first and last (furthest apart in X)
	selected_indices.append(int(candidates[0]["index"]))
	selected_indices.append(int(candidates[-1]["index"]))

	return selected_indices


func _get_boards_in_top_zone() -> Array[RigidBody3D]:
	var boards_in_zone: Array[RigidBody3D] = []
	var deck = infeed_deck
	if not is_instance_valid(deck) and is_inside_tree():
		deck = get_parent().get_node_or_null("EdgerTakeAway")

	if is_instance_valid(deck):
		var top_zone = null
		if deck.has_method("get"):
			top_zone = deck.get("top_zone")
		else:
			top_zone = deck.top_zone if "top_zone" in deck else null

		if is_instance_valid(top_zone):
			for body in top_zone.get_overlapping_bodies():
				if body is RigidBody3D and (body.is_in_group("cut_boards") or "board" in body.name.to_lower()):
					boards_in_zone.append(body)

	return boards_in_zone


func _board_has_pins_engaged(board: RigidBody3D) -> bool:
	var local_center := to_local(board.global_position)
	# Check if any position pins are engaged with this board
	for station in _position_pin_stations:
		var pin_x := float(station["x"])
		var board_min_x := local_center.x - SAMPLE_BOARD_LENGTH * 0.5
		var board_max_x := local_center.x + SAMPLE_BOARD_LENGTH * 0.5
		if pin_x >= board_min_x and pin_x <= board_max_x:
			return true
	# Check if any cushion pins are engaged with this board
	for station in _cushion_pin_stations:
		var pin_x := float(station["x"])
		var board_min_x := local_center.x - SAMPLE_BOARD_LENGTH * 0.5
		var board_max_x := local_center.x + SAMPLE_BOARD_LENGTH * 0.5
		if pin_x >= board_min_x and pin_x <= board_max_x:
			return true
	return false


func _update_real_position_pins(delta: float, boards: Array[RigidBody3D], boards_in_top_zone: Array[RigidBody3D]) -> void:
	# If there's a board in the top_zone, select which pins should be active
	var active_pin_indices: Array[int] = []
	if not boards_in_top_zone.is_empty():
		active_pin_indices = _select_position_pins_for_board(boards_in_top_zone[0])

	for i in range(_position_pin_stations.size()):
		var station: Dictionary = _position_pin_stations[i]
		var pin: Node3D = station["pin"] as Node3D
		var sleeve: Node3D = station["sleeve"] as Node3D
		if not is_instance_valid(pin) and not is_instance_valid(sleeve):
			continue

		var target_y: float = float(station["retracted_y"])
		var sleeve_target_y: float = float(station["sleeve_retracted_y"])
		var target_z: float = float(station["z"])

		# Only engage this pin if it's selected for the active board
		if active_pin_indices.has(i):
			target_y = 0.35
			sleeve_target_y = 0.35
			# Push pin in +Z direction to extend toward board center
			target_z = float(station["z"]) + 0.5

		if is_instance_valid(pin):
			pin.position.y = move_toward(pin.position.y, target_y, position_pin_speed * delta)
			pin.position.z = move_toward(pin.position.z, target_z, centering_board_speed * delta)
		if is_instance_valid(sleeve):
			sleeve.position.y = move_toward(sleeve.position.y, sleeve_target_y, position_pin_speed * delta)
			sleeve.position.z = move_toward(sleeve.position.z, target_z, centering_board_speed * delta)


func _update_real_cushion_pins(delta: float, boards: Array[RigidBody3D], boards_in_top_zone: Array[RigidBody3D]) -> void:
	for i in range(_cushion_pin_stations.size()):
		var station: Dictionary = _cushion_pin_stations[i]
		var body: Node3D = station["body"] as Node3D
		if not is_instance_valid(body):
			continue

		var pin_x := float(station["x"])
		var nearby_board: RigidBody3D = null
		var board_z_bounds: Vector2 = Vector2.ZERO

		# Find a board from the top_zone that overlaps this pin's X position
		for board in boards_in_top_zone:
			var local_center := to_local(board.global_position)
			var board_min_x := local_center.x - SAMPLE_BOARD_LENGTH * 0.5
			var board_max_x := local_center.x + SAMPLE_BOARD_LENGTH * 0.5
			# Check if pin's X falls within board's X range
			if pin_x >= board_min_x and pin_x <= board_max_x:
				nearby_board = board
				board_z_bounds = _get_board_local_z_bounds_for_body(board)
				break

		var base_z := float(station["base_z"])
		var target_z := base_z

		# If a board is nearby, extend the pin to contact it
		if is_instance_valid(nearby_board):
			var fully_extended_z := base_z - cushion_pin_extension
			var pad_contact_offset := CUSHION_PAD_CONTACT_OFFSET_Z - cushion_pin_extension * 0.5
			var pad := body.get_node_or_null("CushionPad") as Node3D
			if is_instance_valid(pad):
				pad_contact_offset = pad.position.z - 0.0225
			var contact_z := board_z_bounds.y - pad_contact_offset
			target_z = clampf(contact_z, fully_extended_z, base_z)

		body.position.z = move_toward(body.position.z, target_z, cushion_pin_speed * delta)


func _spin_real_contact_parts(delta: float, boards: Array[RigidBody3D]) -> void:
	var board_in_machine := false
	for body in boards:
		var local_center := to_local(body.global_position)
		if _board_overlaps_x_range(local_center.x, _infeed_chain_start_x(), bed_length * 0.5):
			board_in_machine = true
			break
	if not board_in_machine:
		return
	var feed_step := (infeed_chain_feed_speed / maxf(FEED_ROLLER_RADIUS, 0.001)) * feed_roller_spin_speed * delta
	for roller in _feed_rollers:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, -feed_step)
	var hold_down_step := (infeed_chain_feed_speed / maxf(HOLD_DOWN_ROLLER_RADIUS, 0.001)) * hold_down_roller_spin_speed * delta
	for roller in _contact_rollers("HoldDownRoller"):
		roller.rotate_object_local(Vector3.UP, hold_down_step)
	var infeed_hold_down_step := (infeed_chain_feed_speed / maxf(INFEED_HOLD_DOWN_ROLLER_RADIUS, 0.001)) * hold_down_roller_spin_speed * delta
	for roller in _contact_rollers("InfeedHoldDownRoller"):
		roller.rotate_object_local(Vector3.UP, infeed_hold_down_step)


func _parking_ramp_edge_lifts_for_board(body: RigidBody3D, local_center: Vector3) -> Vector2:
	var max_lift := 0.0
	var zone_min_z := INF
	var zone_max_z := -INF
	var board_leading_x := local_center.x + SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := local_center.x - SAMPLE_BOARD_LENGTH * 0.5
	for ramp in _parking_ramp_nodes():
		if board_leading_x < ramp.position.x or board_trailing_x > ramp.position.x:
			continue
		var lift_span := float(ramp.get_meta("board_lift_span", 0.0))
		if lift_span <= 0.0:
			continue
		var side_sign := 1.0 if ramp.position.z >= 0.0 else -1.0
		var inner_z := ramp.position.z - side_sign * lift_span
		zone_min_z = minf(zone_min_z, minf(ramp.position.z, inner_z))
		zone_max_z = maxf(zone_max_z, maxf(ramp.position.z, inner_z))
		max_lift = maxf(max_lift, sin(absf(ramp.rotation.x)) * lift_span)
	if max_lift <= 0.0 or zone_min_z >= zone_max_z:
		return Vector2.ZERO

	var thickness := _get_board_thickness_for_body(body)
	var lead_in := thickness * 0.75
	var bounds := _get_board_local_z_bounds_for_body(body)
	var board_front_z := bounds.x
	var board_back_z := bounds.y
	var front_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, board_front_z), 0.0, 1.0))
	var back_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, board_back_z), 0.0, 1.0))
	return Vector2(max_lift * front_progress, max_lift * back_progress)


func _board_is_clear_of_real_parking_ramps(board_center_z: float) -> bool:
	var board_min_z := board_center_z - SAMPLE_BOARD_WIDTH * 0.5
	var board_max_z := board_center_z + SAMPLE_BOARD_WIDTH * 0.5
	for ramp in _parking_ramp_nodes():
		var lift_span := float(ramp.get_meta("board_lift_span", 0.0))
		var side_sign := 1.0 if ramp.position.z >= 0.0 else -1.0
		var inner_z := ramp.position.z - side_sign * lift_span
		var ramp_min_z := minf(ramp.position.z, inner_z)
		var ramp_max_z := maxf(ramp.position.z, inner_z)
		if board_max_z >= ramp_min_z and board_min_z <= ramp_max_z:
			return false
	return true


func _real_ramps_are_home(ramps: Array[Node3D]) -> bool:
	for ramp in ramps:
		if is_instance_valid(ramp) and absf(ramp.rotation.x - float(ramp.get_meta("retracted_angle", 0.0))) > PIN_READY_TOLERANCE:
			return false
	return true


func _parking_ramp_nodes() -> Array[Node3D]:
	var ramps: Array[Node3D] = []
	if not _parking_ramp_stations.is_empty():
		for station in _parking_ramp_stations:
			var nodes: Array = station["nodes"]
			for node in nodes:
				var ramp := node as Node3D
				if is_instance_valid(ramp):
					ramps.append(ramp)
		return ramps
	for node in find_children("ParkingRampPivot*", "Node3D", true, false):
		var ramp := node as Node3D
		if is_instance_valid(ramp):
			ramps.append(ramp)
	return ramps


func _contact_rollers(prefix: String) -> Array[Node3D]:
	var rollers: Array[Node3D] = []
	var source: Array[Node3D] = []
	if prefix == "InfeedHoldDownRoller":
		source = _infeed_hold_down_rollers
	else:
		source = _hold_down_rollers
	for roller in source:
		if is_instance_valid(roller):
			rollers.append(roller)
	if not rollers.is_empty():
		return rollers
	for node in find_children(prefix + "*", "Node3D", true, false):
		var roller := node as Node3D
		if is_instance_valid(roller):
			rollers.append(roller)
	return rollers


func _board_overlaps_x_range(center_x: float, min_x: float, max_x: float) -> bool:
	var board_min_x := center_x - SAMPLE_BOARD_LENGTH * 0.5
	var board_max_x := center_x + SAMPLE_BOARD_LENGTH * 0.5
	return board_max_x >= min_x and board_min_x <= max_x


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
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()

	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_hold_down_stations.clear()
	_infeed_hold_down_rollers.clear()
	_infeed_hold_down_stations.clear()
	_parking_ramp_stations.clear()
	_position_pin_stations.clear()
	_cushion_pin_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null
	_generated_name_counts.clear()
	_editor_group_stack.clear()

	_make_materials()
	_assembly_builder = SawmillEdgerAssemblyBuilder.new(self)
	if use_saved_assembly_scenes:
		_instantiate_saved_assembly_scenes()
		_collect_generated_parts()
	else:
		_build_frame()
		_build_feed_deck()
		_build_hold_downs()
		_build_saw_box()
		_build_motors_and_drives()
		_build_waste_handling()
	_adopt_generated_parts()


func _instantiate_saved_assembly_scenes() -> void:
	var assembly_scenes: Array[PackedScene] = [
		frame_assembly_scene,
		side_fence_assembly_scene,
		infeed_chain_assembly_scene,
		parking_ramp_assembly_scene,
		infeed_hold_down_roller_assembly_scene,
		position_pin_assembly_scene,
		cushion_pin_assembly_scene,
		lower_feed_roller_assembly_scene,
		upper_hold_down_roller_assembly_scene,
		saw_blade_and_guard_assembly_scene,
		motor_drive_assembly_scene,
		waste_handling_assembly_scene,
	]
	if _should_include_reference_board():
		assembly_scenes.append(reference_board_assembly_scene)

	for assembly_scene in assembly_scenes:
		if assembly_scene == null:
			continue
		var instance := assembly_scene.instantiate()
		if _preserved_editor_group_transforms.has(instance.name):
			instance.transform = _preserved_editor_group_transforms[instance.name]
		add_child(instance)
		_adopt_new_node(instance)


func _should_include_reference_board() -> bool:
	return Engine.is_editor_hint()


func _collect_generated_parts() -> void:
	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_hold_down_stations.clear()
	_infeed_hold_down_rollers.clear()
	_infeed_hold_down_stations.clear()
	_parking_ramp_stations.clear()
	_position_pin_stations.clear()
	_cushion_pin_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null

	for node in find_children("*", "Node3D", true, false):
		var node_3d := node as Node3D
		if not is_instance_valid(node_3d):
			continue
		if node_3d.name.begins_with("FeedRoller"):
			_feed_rollers.append(node_3d)
		elif node_3d.name.begins_with("InfeedChainLink"):
			_infeed_chain_links.append(node_3d)
			_infeed_chain_bases.append(node_3d.position)
		elif node_3d.name.begins_with("HoldDownRoller"):
			_hold_down_rollers.append(node_3d)
		elif node_3d.name.begins_with("InfeedHoldDownRoller"):
			_infeed_hold_down_rollers.append(node_3d)
		elif node_3d.name.begins_with("EdgerSawBlade") and node_3d is CSGCylinder3D:
			_saw_blades.append(node_3d as CSGCylinder3D)
		elif node_3d.name.begins_with("EdgerSawTeeth"):
			_saw_teeth_roots.append(node_3d)
		elif node_3d.name.begins_with("ReferenceCutBoard"):
			_sample_board = node_3d
	_collect_infeed_hold_down_stations_from_scene()

	# Collect position pin stations if using saved assembly scenes
	var pos_assembly := get_node_or_null("PositionPinAssembly") as Node3D
	if is_instance_valid(pos_assembly):
		var pins_map := {}
		var sleeves_map := {}
		for child in pos_assembly.get_children():
			if not child is Node3D:
				continue
			var name_parts := child.name.split("_")
			if name_parts.size() < 2:
				continue
			var suffix := name_parts[1]
			if child.name.begins_with("PositionPinSleeve"):
				sleeves_map[suffix] = child
			elif child.name.begins_with("PositionPin"):
				pins_map[suffix] = child
		
		var suffixes := pins_map.keys()
		suffixes.sort()
		for suffix in suffixes:
			var pin = pins_map[suffix] as Node3D
			var sleeve = sleeves_map.get(suffix) as Node3D
			if is_instance_valid(pin):
				var front_z: float = pin.position.z
				var retracted_y: float = pin.position.y
				var raised_y: float = retracted_y + 0.314
				var sleeve_retracted_y: float = 0.0
				var sleeve_raised_y: float = 0.0
				if is_instance_valid(sleeve):
					sleeve_retracted_y = sleeve.position.y
					sleeve_raised_y = sleeve_retracted_y + 0.314
				
				_position_pin_stations.append({
					"x": pin.position.x,
					"pin": pin,
					"sleeve": sleeve,
					"z": front_z,
					"retracted_y": retracted_y,
					"raised_y": raised_y,
					"sleeve_retracted_y": sleeve_retracted_y,
					"sleeve_raised_y": sleeve_raised_y,
					"extended": false,
				})

	# Collect cushion pin stations if using saved assembly scenes
	var cushion_assembly := get_node_or_null("CushionPinAssembly") as Node3D
	if is_instance_valid(cushion_assembly):
		var station_nodes := {}
		var barrels_map := {}
		for child in cushion_assembly.get_children():
			if not child is Node3D:
				continue
			var name_parts := child.name.split("_")
			if name_parts.size() < 2:
				continue
			var suffix := name_parts[1]
			if child.name.begins_with("CushionCylinder"):
				barrels_map[suffix] = child
			elif child.name.begins_with("CushionPinAssembly"):
				station_nodes[suffix] = child
				
		var suffixes := station_nodes.keys()
		suffixes.sort()
		for suffix in suffixes:
			var body = station_nodes[suffix] as Node3D
			var barrel = barrels_map.get(suffix) as Node3D
			var rod = body.get_node_or_null("CushionRod") as Node3D
			var pad = body.get_node_or_null("CushionPad") as Node3D
			
			_cushion_pin_stations.append({
				"x": body.position.x,
				"body": body,
				"barrel": barrel,
				"rod": rod,
				"pad": pad,
				"base_z": body.position.z,
				"extended": false,
			})


func _collect_infeed_hold_down_stations_from_scene() -> void:
	var station_parts := {}
	for node in find_children("*", "Node3D", true, false):
		var station_id := _hold_down_station_id(String(node.name))
		if station_id.is_empty():
			continue
		if not station_parts.has(station_id):
			station_parts[station_id] = {
				"bearings": [],
			}
		var parts: Dictionary = station_parts[station_id]
		if node.name.begins_with("InfeedHoldDownCrosshead"):
			parts["crosshead"] = node
		elif node.name.begins_with("InfeedHoldDownRoller"):
			parts["roller"] = node
		elif node.name.begins_with("InfeedHoldDownAxle"):
			parts["axle"] = node
		elif node.name.begins_with("InfeedHoldDownBearing"):
			parts["bearings"].append(node)
		elif node.name.begins_with("PneumaticCylinder"):
			parts["actuator_root"] = node

	var station_ids := station_parts.keys()
	station_ids.sort()
	for station_id in station_ids:
		var parts: Dictionary = station_parts[station_id]
		var crosshead := parts.get("crosshead") as Node3D
		var roller := parts.get("roller") as Node3D
		if not is_instance_valid(crosshead) or not is_instance_valid(roller):
			continue

		var moving_nodes: Array[Node3D] = [crosshead, roller]
		var axle := parts.get("axle") as Node3D
		if is_instance_valid(axle):
			moving_nodes.append(axle)
		var bearings: Array = parts["bearings"]
		for bearing in bearings:
			var bearing_node := bearing as Node3D
			if is_instance_valid(bearing_node):
				moving_nodes.append(bearing_node)

		var raised_y := roller.position.y
		var y_offsets: Array[float] = []
		for moving_node in moving_nodes:
			y_offsets.append(moving_node.position.y - raised_y)

		var station := {
			"x": roller.position.x,
			"nodes": moving_nodes,
			"y_offsets": y_offsets,
			"raised_y": raised_y,
			"offset": hold_down_raised_offset,
		}
		var actuator_root := parts.get("actuator_root") as Node3D
		if is_instance_valid(actuator_root):
			var rod := actuator_root.get_node_or_null("PistonRod") as CSGCylinder3D
			var rod_top_y := -0.087
			if is_instance_valid(rod):
				rod_top_y = rod.position.y + rod.height * 0.5
			station["actuator"] = {
				"root": actuator_root,
				"attach_node": crosshead,
				"rod": rod,
				"clevis": actuator_root.get_node_or_null("RodClevis"),
				"pin_hole": actuator_root.get_node_or_null("ClevisPinHole"),
				"rod_top_y": rod_top_y,
			}
		_infeed_hold_down_stations.append(station)


func _hold_down_station_id(node_name: String) -> String:
	if not (
		node_name.begins_with("InfeedHoldDownCrosshead")
		or node_name.begins_with("InfeedHoldDownRoller")
		or node_name.begins_with("InfeedHoldDownAxle")
		or node_name.begins_with("InfeedHoldDownBearing")
		or node_name.begins_with("PneumaticCylinder")
	):
		return ""
	var name_parts := node_name.split("_")
	if name_parts.size() < 2:
		return ""
	return name_parts[1]


func _adopt_generated_parts() -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return

	var scene_root := get_tree().edited_scene_root
	if scene_root == null or scene_root != self:
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
	_mat_infeed_hold_down = _worn_green_roller_mat()
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


func _worn_green_roller_mat() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.035, 0.20, 0.085, 1.0);
uniform vec4 worn_color : source_color = vec4(0.38, 0.43, 0.34, 1.0);
uniform vec4 dark_scuff_color : source_color = vec4(0.015, 0.045, 0.025, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float long_wear = smoothstep(0.72, 0.92, hash(floor(vec2(uv.x * 18.0, uv.y * 5.0))));
	float fine_scuffs = smoothstep(0.52, 0.86, hash(floor(vec2(uv.x * 55.0, uv.y * 16.0))));
	float rubbed_bands = pow(abs(sin((uv.y * 8.0 + uv.x * 2.0) * 3.14159)), 12.0) * 0.35;
	float wear = clamp(long_wear * 0.45 + fine_scuffs * 0.18 + rubbed_bands, 0.0, 0.72);
	vec3 paint = mix(base_color.rgb, worn_color.rgb, wear);
	float dark_scuffs = smoothstep(0.88, 0.98, hash(floor(vec2(uv.x * 32.0 + 9.0, uv.y * 11.0))));
	ALBEDO = mix(paint, dark_scuff_color.rgb, dark_scuffs * 0.22);
	METALLIC = 0.45;
	ROUGHNESS = 0.48 + wear * 0.26;
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
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
	_assembly_builder.build_frame()


func _build_feed_deck() -> void:
	_assembly_builder.build_feed_deck()


func _build_infeed_chains() -> void:
	_assembly_builder.build_infeed_chains()


func _build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_parking_ramps(chain_start, chain_end, chain_top)


func _build_infeed_hold_downs(chain_start: float, chain_end: float) -> void:
	_assembly_builder.build_infeed_hold_downs(chain_start, chain_end)


func _build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_position_pins(chain_start, chain_end, chain_top)


func _build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_cushion_pins(chain_start, chain_end, chain_top)


func _build_hold_downs() -> void:
	_assembly_builder.build_hold_downs()


func _build_saw_box() -> void:
	_assembly_builder.build_saw_box()


func _build_motors_and_drives() -> void:
	_assembly_builder.build_motors_and_drives()


func _build_waste_handling() -> void:
	_assembly_builder.build_waste_handling()


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


func _preview_board_center_y() -> float:
	return _board_center_y() + preview_board_y_offset


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


func _add_cylinder_child(parent: Node3D, node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = node_name
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	parent.add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _add_physics_box(node_name: String, local_position: Vector3, size: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = _friendly_part_name(node_name, local_position)
	body.position = local_position
	body.rotation = local_rotation
	body.sync_to_physics = true
	_current_part_parent().add_child(body)
	_adopt_new_node(body)
	_add_box_contact_child(body, "Visual", Vector3.ZERO, size, material)
	return body


func _add_physics_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = _friendly_part_name(node_name, local_position)
	body.position = local_position
	body.rotation = local_rotation
	body.sync_to_physics = true
	_current_part_parent().add_child(body)
	_adopt_new_node(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	_adopt_new_node(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	_adopt_new_node(collision)
	return body


func _add_box_contact_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	_adopt_new_node(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = node_name + "Collision"
	collision.position = local_position
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	_adopt_new_node(collision)
	return mesh_instance


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
	if scene_root == null or scene_root != self:
		return
	if node != scene_root:
		node.owner = scene_root


func _friendly_part_name(base_name: String, local_position: Vector3) -> String:
	var node_name_str := "%s_%s" % [base_name, _position_name_suffix(local_position)]
	node_name_str = node_name_str.replace("__", "_").strip_edges(false, true)
	var used_count := int(_generated_name_counts.get(node_name_str, 0)) + 1
	_generated_name_counts[node_name_str] = used_count
	if used_count > 1:
		node_name_str = "%s_%02d" % [node_name_str, used_count]
	return node_name_str


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


# ── Runtime Centering Cycle State Machine ───────────────────────────────────



func _set_infeed_deck_pause(paused: bool) -> void:
	var deck = infeed_deck
	if not is_instance_valid(deck) and is_inside_tree():
		deck = get_parent().get_node_or_null("EdgerTakeAway")
	if is_instance_valid(deck) and (deck.name == "EdgerTakeAway" or deck.has_method("set_running") or "external_stop" in deck):
		if deck.get("external_stop") != paused:
			deck.set("external_stop", paused)


func _position_pin_raised_y_for_board(station: Dictionary, board: RigidBody3D) -> float:
	var thickness := _get_board_thickness_for_body(board)
	var board_top_y := to_local(board.global_position).y + thickness * 0.5
	var pin_center_for_board_top := board_top_y - position_pin_height * 0.5 + 0.012
	return clampf(pin_center_for_board_top, float(station["retracted_y"]), float(station["raised_y"]))




func _board_chain_center_global_y() -> float:
	return to_global(Vector3(0.0, _preview_board_center_y(), 0.0)).y


func _get_board_local_z_bounds_for_body(board: RigidBody3D) -> Vector2:
	if not is_instance_valid(board):
		return Vector2(-SAMPLE_BOARD_WIDTH * 0.5, SAMPLE_BOARD_WIDTH * 0.5)

	var col_shape := board.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape != null and col_shape.shape != null:
		var parent_node := col_shape.get_parent() as Node3D
		if col_shape.shape is BoxShape3D:
			var box := col_shape.shape as BoxShape3D
			var sz := box.size
			var corners := [
				Vector3(-sz.x * 0.5, -sz.y * 0.5, -sz.z * 0.5),
				Vector3(sz.x * 0.5, -sz.y * 0.5, -sz.z * 0.5),
				Vector3(-sz.x * 0.5, sz.y * 0.5, -sz.z * 0.5),
				Vector3(sz.x * 0.5, sz.y * 0.5, -sz.z * 0.5),
				Vector3(-sz.x * 0.5, -sz.y * 0.5, sz.z * 0.5),
				Vector3(sz.x * 0.5, -sz.y * 0.5, sz.z * 0.5),
				Vector3(-sz.x * 0.5, sz.y * 0.5, sz.z * 0.5),
				Vector3(sz.x * 0.5, sz.y * 0.5, sz.z * 0.5),
			]
			var min_z := INF
			var max_z := -INF
			for pt in corners:
				var global_pt := parent_node.to_global(pt)
				var local_pt := to_local(global_pt)
				min_z = minf(min_z, local_pt.z)
				max_z = maxf(max_z, local_pt.z)
			return Vector2(min_z, max_z)
		elif col_shape.shape is ConvexPolygonShape3D:
			var convex := col_shape.shape as ConvexPolygonShape3D
			var min_z := INF
			var max_z := -INF
			for pt in convex.points:
				var global_pt := parent_node.to_global(pt)
				var local_pt := to_local(global_pt)
				min_z = minf(min_z, local_pt.z)
				max_z = maxf(max_z, local_pt.z)
			if min_z < max_z:
				return Vector2(min_z, max_z)

	var local_center := to_local(board.global_position)
	return Vector2(local_center.z - SAMPLE_BOARD_WIDTH * 0.5, local_center.z + SAMPLE_BOARD_WIDTH * 0.5)


func _get_board_width_for_body(board: RigidBody3D) -> float:
	var bounds := _get_board_local_z_bounds_for_body(board)
	return bounds.y - bounds.x


func _get_board_local_z_center_for_body(board: RigidBody3D) -> float:
	var bounds := _get_board_local_z_bounds_for_body(board)
	return (bounds.x + bounds.y) * 0.5


func _get_board_global_z_bounds_for_body(board: RigidBody3D) -> Vector2:
	var local_bounds := _get_board_local_z_bounds_for_body(board)
	var global_min_z := to_global(Vector3(0.0, 0.0, local_bounds.x)).z
	var global_max_z := to_global(Vector3(0.0, 0.0, local_bounds.y)).z
	return Vector2(global_min_z, global_max_z)


func _get_board_thickness_for_body(board: RigidBody3D) -> float:
	if not is_instance_valid(board):
		return SAMPLE_BOARD_THICKNESS
	var col_shape := board.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape != null and col_shape.shape != null:
		if col_shape.shape is BoxShape3D:
			return (col_shape.shape as BoxShape3D).size.y
		elif col_shape.shape is ConvexPolygonShape3D:
			var convex := col_shape.shape as ConvexPolygonShape3D
			var min_y := INF
			var max_y := -INF
			for p in convex.points:
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
			if min_y < max_y:
				return max_y - min_y
	return SAMPLE_BOARD_THICKNESS

