@tool
class_name EdgerPinSystem
extends Node3D

var edger: SawmillEdger

@export_category("Position Pins")
@export_range(0.0, 8.0, 0.01, "or_greater") var position_pin_speed: float = 1.6
@export_range(0.0, 10.0, 0.1) var position_pin_raise_height: float = 5.0
@export_range(0.0, 10.0, 0.1, "or_greater") var position_pin_z_travel: float = 5.0
@export_range(0.0, 10.0, 0.01, "or_greater") var position_pin_z_travel_speed: float = 0.95
@export var position_pin_target_z: float = 18.27
@export_range(0.0, 10.0, 0.1) var retraction_delay: float = 0.5

@export_category("Cushion Pins")
@export_range(0.0, 8.0, 0.01, "or_greater") var cushion_pin_speed: float = 2.2
@export_range(0.05, 1.0, 0.01) var cushion_pin_extension: float = 0.46


func _ready() -> void:
	edger = get_parent() as SawmillEdger


func update_position_pins(delta: float) -> void:
	var active_board: RigidBody3D = null
	var active_pin_indices: Array[int] = []

	if is_instance_valid(edger._centering_board) and not edger._centering_completed:
		active_board = edger._centering_board
		active_pin_indices = _select_position_pins_for_board(active_board)

	for i in range(edger._position_pin_stations.size()):
		var station: Dictionary = edger._position_pin_stations[i]
		var pin: Node3D = station["pin"] as Node3D
		var sleeve: Node3D = station["sleeve"] as Node3D

		if not is_instance_valid(pin) and not is_instance_valid(sleeve):
			continue

		var retracted_y: float = float(station["retracted_y"])
		var raised_y: float = retracted_y + position_pin_raise_height
		var home_z: float = float(station["z"])
		var push_z: float = home_z + position_pin_z_travel

		var target_y: float = retracted_y
		var target_z: float = home_z

		if active_pin_indices.has(i) and is_instance_valid(active_board):
			if active_board.global_position.z < position_pin_target_z:
				target_y = raised_y
				if absf(pin.position.y - raised_y) < 0.01:
					target_z = push_z
				else:
					target_z = home_z
			elif edger._pin_retract_delay_elapsed < retraction_delay:
				target_y = raised_y
				target_z = pin.position.z
			else:
				if absf(pin.position.y - retracted_y) > 0.01:
					target_y = retracted_y
					target_z = pin.position.z
				else:
					target_y = retracted_y
					target_z = home_z

		if is_instance_valid(pin):
			pin.position.y = move_toward(pin.position.y, target_y, position_pin_speed * delta)
			pin.position.z = move_toward(pin.position.z, target_z, position_pin_z_travel_speed * delta)
		if is_instance_valid(sleeve):
			sleeve.position.y = move_toward(sleeve.position.y, target_y, position_pin_speed * delta)
			sleeve.position.z = move_toward(sleeve.position.z, target_z, position_pin_z_travel_speed * delta)


func update_cushion_pins(delta: float) -> void:
	for i in range(edger._cushion_pin_stations.size()):
		var station: Dictionary = edger._cushion_pin_stations[i]
		var body: Node3D = station["body"] as Node3D
		if not is_instance_valid(body):
			continue

		var pin_x := float(station["x"])
		var nearby_board: RigidBody3D = null
		var board_z_bounds: Vector2 = Vector2.ZERO

		if is_instance_valid(edger._centering_board) and not edger._centering_completed:
			var local_center := edger.to_local(edger._centering_board.global_position)
			var board_min_x := local_center.x - edger.SAMPLE_BOARD_LENGTH * 0.5
			var board_max_x := local_center.x + edger.SAMPLE_BOARD_LENGTH * 0.5
			if pin_x >= board_min_x and pin_x <= board_max_x:
				nearby_board = edger._centering_board
				board_z_bounds = edger._get_board_local_z_bounds_for_body(edger._centering_board)

		var base_z := float(station["base_z"])
		var target_z := base_z

		if is_instance_valid(nearby_board):
			var fully_extended_z := base_z - cushion_pin_extension
			var pad_contact_offset := edger.CUSHION_PAD_CONTACT_OFFSET_Z - cushion_pin_extension * 0.5
			var pad := body.get_node_or_null("CushionPad") as Node3D
			if is_instance_valid(pad):
				pad_contact_offset = pad.position.z - 0.0225
			var contact_z := board_z_bounds.y - pad_contact_offset
			target_z = clampf(contact_z, fully_extended_z, base_z)

		body.position.z = move_toward(body.position.z, target_z, cushion_pin_speed * delta)


func _select_position_pins_for_board(board: RigidBody3D) -> Array[int]:
	var selected_indices: Array[int] = []
	var candidates: Array[Dictionary] = []

	var local_center := edger.to_local(board.global_position)
	var board_min_x := local_center.x - edger.SAMPLE_BOARD_LENGTH * 0.5
	var board_max_x := local_center.x + edger.SAMPLE_BOARD_LENGTH * 0.5

	for i in range(edger._position_pin_stations.size()):
		var station: Dictionary = edger._position_pin_stations[i]
		var pin_x := float(station["x"])
		if pin_x >= board_min_x and pin_x <= board_max_x:
			candidates.append({"index": i, "x": pin_x})

	if candidates.size() < 2:
		return selected_indices

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["x"]) < float(b["x"])
	)
	selected_indices.append(int(candidates[0]["index"]))
	selected_indices.append(int(candidates[-1]["index"]))
	return selected_indices
