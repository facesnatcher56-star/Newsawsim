@tool
class_name EdgerHoldDownSystem
extends Node3D

var edger: SawmillEdger

@export_category("Hold-Down Rollers")
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_roller_spin_resistance: float = 1.5
@export_range(0.0, 2.0, 0.01, "or_greater") var hold_down_raised_offset: float = 0.24
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_lower_speed: float = 0.6
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_raise_speed: float = 0.45


func _ready() -> void:
	edger = get_parent() as SawmillEdger


func update_infeed(delta: float, boards: Array[RigidBody3D]) -> void:
	var roller_half_length := edger.INFEED_HOLD_DOWN_ROLLER_LENGTH * 0.5
	for station in edger._infeed_hold_down_stations:
		var nodes: Array = station["nodes"]
		var y_offsets: Array = station["y_offsets"]
		if nodes.is_empty() or not is_instance_valid(nodes[0] as Node3D):
			continue
		var station_x := float(station["x"])
		var raised_y := float(station["raised_y"])

		var board_under: RigidBody3D = null
		var board_top_y := -INF
		for body in boards:
			var local_center := edger.to_local(body.global_position)
			if absf(local_center.z) > 4.5 or absf(local_center.y - edger.working_height) > 0.6:
				continue
			if not edger._board_overlaps_x_range(local_center.x, station_x - edger.INFEED_HOLD_DOWN_ROLLER_RADIUS, station_x + edger.INFEED_HOLD_DOWN_ROLLER_RADIUS):
				continue
			var z_bounds := edger._get_board_local_z_bounds_for_body(body)
			if z_bounds.y < -roller_half_length or z_bounds.x > roller_half_length:
				continue
			var top_y := local_center.y + edger._get_board_thickness_for_body(body) * 0.5
			if top_y > board_top_y:
				board_top_y = top_y
				board_under = body

		var current_y := (nodes[0] as Node3D).position.y - float(y_offsets[0])
		var new_y := current_y
		var target_y := raised_y
		var is_descended := bool(station.get("descended", false))

		if not is_descended and is_instance_valid(board_under) and edger._pin_retract_delay_elapsed > 0.0:
			is_descended = true
			station["descended"] = true

		if is_descended and is_instance_valid(board_under):
			target_y = board_top_y + edger.INFEED_HOLD_DOWN_ROLLER_RADIUS
			new_y = _lower_infeed_hold_down(current_y, board_top_y)
		elif not is_instance_valid(board_under):
			is_descended = false
			station["descended"] = false
			new_y = _retract_infeed_hold_down(current_y, raised_y)

		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position.y = new_y + float(y_offsets[i])

		var resting := is_instance_valid(board_under) and absf(new_y - target_y) <= 0.02 and target_y < raised_y - 0.01
		station["down"] = resting

		var spin_vel: float = station.get("spin_velocity", 0.0)
		if resting:
			var board_speed := board_under.linear_velocity.dot(edger.global_transform.basis.x.normalized())
			spin_vel = board_speed / maxf(edger.INFEED_HOLD_DOWN_ROLLER_RADIUS, 0.001)
		else:
			spin_vel = move_toward(spin_vel, 0.0, hold_down_roller_spin_resistance * delta)
		station["spin_velocity"] = spin_vel
		if absf(spin_vel) > 0.001:
			var roller := station.get("roller") as Node3D
			if is_instance_valid(roller):
				roller.rotate_object_local(Vector3.UP, spin_vel * delta)

		var actuator: Dictionary = station.get("actuator", {})
		if not actuator.is_empty():
			_stretch_infeed_hold_down_actuator(actuator, raised_y - new_y)


func update(delta: float, boards: Array[RigidBody3D]) -> void:
	for station in edger._hold_down_stations:
		var nodes: Array = station["nodes"]
		if nodes.is_empty() or not is_instance_valid(nodes[0] as Node3D):
			continue
		var station_x := float(station["x"])
		var bases: Array[Vector3] = station["bases"]
		var offset := float(station.get("offset", 0.0))
		var raised_y := bases[0].y + offset

		var board_under: RigidBody3D = null
		var board_top_y := -INF
		for body in boards:
			var local_center := edger.to_local(body.global_position)
			if absf(local_center.z) > 4.5 or absf(local_center.y - edger.working_height) > 0.6:
				continue
			if not edger._board_overlaps_x_range(local_center.x, station_x - edger.HOLD_DOWN_ROLLER_RADIUS, station_x + edger.HOLD_DOWN_ROLLER_RADIUS):
				continue
			var top_y := local_center.y + edger._get_board_thickness_for_body(body) * 0.5
			if top_y > board_top_y:
				board_top_y = top_y
				board_under = body

		var target_y := raised_y
		if is_instance_valid(board_under):
			target_y = board_top_y + edger.HOLD_DOWN_ROLLER_RADIUS

		var current_y := (nodes[0] as Node3D).position.y
		var speed := hold_down_lower_speed if target_y < current_y else hold_down_raise_speed
		var new_y := move_toward(current_y, target_y, speed * delta)

		var y_delta := new_y - current_y
		for node in nodes:
			if is_instance_valid(node):
				node.position.y += y_delta

		var is_down := is_instance_valid(board_under) and absf(new_y - target_y) <= 0.02
		station["down"] = is_down

		var spin_vel: float = station.get("spin_velocity", 0.0)
		if is_down:
			var board_speed := board_under.linear_velocity.dot(edger.global_transform.basis.x.normalized())
			spin_vel = board_speed / maxf(edger.HOLD_DOWN_ROLLER_RADIUS, 0.001)
		else:
			spin_vel = move_toward(spin_vel, 0.0, hold_down_roller_spin_resistance * delta)
		station["spin_velocity"] = spin_vel
		if absf(spin_vel) > 0.001:
			var roller := nodes[0] as Node3D
			if is_instance_valid(roller):
				roller.rotate_object_local(Vector3.UP, spin_vel * delta)


func apply_contacts(body: RigidBody3D, local_center: Vector3) -> void:
	var has_contact := false
	for station in edger._infeed_hold_down_stations:
		if not bool(station.get("down", false)):
			continue
		if edger._board_overlaps_x_range(local_center.x, float(station["x"]) - edger.INFEED_HOLD_DOWN_ROLLER_RADIUS, float(station["x"]) + edger.INFEED_HOLD_DOWN_ROLLER_RADIUS):
			has_contact = true
			break
	if not has_contact:
		for station in edger._hold_down_stations:
			if not bool(station.get("down", false)):
				continue
			if edger._board_overlaps_x_range(local_center.x, float(station["x"]) - edger.HOLD_DOWN_ROLLER_RADIUS, float(station["x"]) + edger.HOLD_DOWN_ROLLER_RADIUS):
				has_contact = true
				break
	if has_contact:
		edger.infeed_system.apply_feed_contact(body, local_center)


func _lower_infeed_hold_down(current_y: float, board_top_y: float) -> float:
	var target_y := board_top_y + edger.INFEED_HOLD_DOWN_ROLLER_RADIUS
	return move_toward(current_y, target_y, hold_down_lower_speed * get_physics_process_delta_time())


func _retract_infeed_hold_down(current_y: float, raised_y: float) -> float:
	return move_toward(current_y, raised_y, hold_down_raise_speed * get_physics_process_delta_time())


func _stretch_infeed_hold_down_actuator(actuator: Dictionary, drop: float) -> void:
	var rod := actuator.get("rod") as CSGCylinder3D
	if is_instance_valid(rod):
		if not actuator.has("rod_base_height"):
			actuator["rod_base_height"] = rod.height
		var rod_top_y := float(actuator.get("rod_top_y", rod.position.y + rod.height * 0.5))
		rod.height = float(actuator["rod_base_height"]) + drop
		rod.position.y = rod_top_y - rod.height * 0.5
	for key: String in ["clevis", "pin_hole"]:
		var part := actuator.get(key) as Node3D
		if not is_instance_valid(part):
			continue
		var base_key := key + "_base_y"
		if not actuator.has(base_key):
			actuator[base_key] = part.position.y
		part.position.y = float(actuator[base_key]) - drop
