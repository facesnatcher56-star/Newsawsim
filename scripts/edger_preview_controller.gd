@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func apply_preview_motion(delta: float) -> void:
	if not is_instance_valid(edger._sample_board):
		return

	match edger._centering_preview_phase:
		SawmillEdger.CenteringPreviewPhase.SIDE_LOAD:
			_update_side_load_phase(delta)
		SawmillEdger.CenteringPreviewPhase.RAISE_PINS:
			_update_pin_actuators(delta, true, false)
			if _active_pins_are_raised() and _active_cushions_are_at_target():
				edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.CENTER_BOARD
		SawmillEdger.CenteringPreviewPhase.CENTER_BOARD:
			_update_pin_actuators(delta, true, true)
			_update_center_board_phase(delta)
		SawmillEdger.CenteringPreviewPhase.PIN_RETRACT_DELAY:
			_update_pin_actuators(delta, true, false)
			edger._pin_retract_delay_elapsed += delta
			if edger._pin_retract_delay_elapsed >= edger.pin_retract_delay:
				edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.RETRACT_PINS
		SawmillEdger.CenteringPreviewPhase.RETRACT_PINS:
			_update_pin_actuators(delta, false, false)
			if _pins_are_retracted_down() and _cushions_are_home():
				edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.RETURN_PINS_HOME_Z
		SawmillEdger.CenteringPreviewPhase.RETURN_PINS_HOME_Z:
			_update_position_pins_z_home(delta)
			_update_cushion_pins_home(delta)
			if _pins_and_cushions_are_home():
				edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.LOWER_RAMPS
		SawmillEdger.CenteringPreviewPhase.LOWER_RAMPS:
			pass
		SawmillEdger.CenteringPreviewPhase.FEED_DELAY:
			edger._feed_delay_elapsed += delta
			if edger._feed_delay_elapsed >= edger.feed_chain_start_delay:
				edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.FEED_BOARD
		SawmillEdger.CenteringPreviewPhase.FEED_BOARD:
			_update_feed_board_phase(delta)

	_update_parking_ramp_preview(delta)
	_update_board_height_for_ramps(delta)
	if edger._centering_preview_phase == SawmillEdger.CenteringPreviewPhase.LOWER_RAMPS and _ramps_are_home() and _board_is_on_chain():
		edger._feed_delay_elapsed = 0.0
		edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.FEED_DELAY
	_update_infeed_hold_down_preview(delta)
	_update_hold_down_preview(delta, edger.to_local(edger._sample_board.global_position).x)


func reset_preview_motion() -> void:
	edger._feed_preview_travel = 0.0
	edger._feed_delay_elapsed = 0.0
	edger._pin_retract_delay_elapsed = 0.0
	edger._chain_preview_offset = 0.0
	edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.SIDE_LOAD
	edger._active_centering_pin_indices = _select_board_contact_position_pins()
	_update_infeed_chain_preview()

	for roller in edger._feed_rollers:
		if is_instance_valid(roller):
			roller.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for roller in edger._hold_down_rollers:
		if is_instance_valid(roller):
			roller.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for roller in edger._infeed_hold_down_rollers:
		if is_instance_valid(roller):
			roller.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for blade in edger._saw_blades:
		if is_instance_valid(blade):
			blade.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	for teeth_root in edger._saw_teeth_roots:
		if is_instance_valid(teeth_root):
			teeth_root.rotation = Vector3.ZERO

	if is_instance_valid(edger._sample_board):
		if edger._preview_board_home_global == Vector3.ZERO:
			edger._preview_board_home_global = edger._sample_board.global_position
		edger._sample_board.global_position = edger._preview_board_home_global
		edger._sample_board.rotation.x = 0.0

	_reset_centering_preview()
	_reset_infeed_hold_down_preview()
	_reset_hold_down_preview()


func _reset_centering_preview() -> void:
	for station in edger._parking_ramp_stations:
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp := node as Node3D
			if is_instance_valid(ramp):
				ramp.rotation.x = float(ramp.get_meta("retracted_angle", 0.0))

	for station in edger._position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin):
			pin.position.y = float(station["retracted_y"])
			pin.position.z = float(station["z"])
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve):
			sleeve.position.y = float(station["sleeve_retracted_y"])
			sleeve.position.z = float(station["z"])

	for station in edger._cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body):
			body.position.z = float(station["base_z"])


func _reset_hold_down_preview() -> void:
	for station in edger._hold_down_stations:
		station["offset"] = edger.hold_down_raised_offset
		station["spin_velocity"] = 0.0
		var nodes: Array = station["nodes"]
		var bases: Array = station["bases"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position = bases[i] + Vector3(0.0, edger.hold_down_raised_offset, 0.0)


func _reset_infeed_hold_down_preview() -> void:
	for station in edger._infeed_hold_down_stations:
		station["spin_velocity"] = 0.0
		var raised_y := float(station["raised_y"])
		var nodes: Array = station["nodes"]
		var y_offsets: Array = station["y_offsets"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position.y = raised_y + float(y_offsets[i])
		_update_infeed_hold_down_actuator(station)


func _update_infeed_chain_preview() -> void:
	var chain_start := edger._infeed_chain_start_x()
	var chain_end := SawmillEdger.INFEED_CHAIN_END_X
	var chain_length := chain_end - chain_start
	if chain_length <= 0.0:
		return
	for i in range(edger._infeed_chain_links.size()):
		var link := edger._infeed_chain_links[i]
		if not is_instance_valid(link):
			continue
		var base := edger._infeed_chain_bases[i]
		link.position = base
		link.position.x = chain_start + fposmod((base.x - chain_start) + edger._chain_preview_offset, chain_length)


func _update_side_load_phase(delta: float) -> void:
	var target_z := _board_pin_clear_z()
	var board_position := edger._sample_board.global_position
	board_position.z = move_toward(board_position.z, target_z, edger.centering_board_speed * delta)
	edger._sample_board.global_position = board_position
	if absf(edger._sample_board.global_position.z - target_z) <= SawmillEdger.CENTERING_TOLERANCE:
		edger._active_centering_pin_indices = _select_board_contact_position_pins()
		edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.RAISE_PINS


func _update_center_board_phase(delta: float) -> void:
	var target_z := _board_center_target_z()
	var board_position := edger._sample_board.global_position
	board_position.z = move_toward(board_position.z, target_z, edger.centering_board_speed * delta)
	edger._sample_board.global_position = board_position
	if absf(edger._sample_board.global_position.z - target_z) <= SawmillEdger.CENTERING_TOLERANCE:
		edger._pin_retract_delay_elapsed = 0.0
		edger._centering_preview_phase = SawmillEdger.CenteringPreviewPhase.PIN_RETRACT_DELAY


func _update_feed_board_phase(delta: float) -> void:
	var feed_step := edger.infeed_chain_feed_speed * delta
	edger._feed_preview_travel += feed_step
	edger._chain_preview_offset = fposmod(edger._chain_preview_offset + feed_step, SawmillEdger.CHAIN_LINK_LENGTH)
	_update_infeed_chain_preview()

	var board_position := edger._sample_board.global_position
	board_position.x += feed_step
	edger._sample_board.global_position = board_position

	var roller_step := (edger.infeed_chain_feed_speed / maxf(SawmillEdger.FEED_ROLLER_RADIUS, 0.001)) * edger.feed_roller_spin_speed * delta
	for roller in edger._feed_rollers:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, -roller_step)
	for blade in edger._saw_blades:
		if is_instance_valid(blade):
			blade.rotate_object_local(Vector3.UP, -edger.blade_spin_speed * delta)
	for teeth_root in edger._saw_teeth_roots:
		if is_instance_valid(teeth_root):
			teeth_root.rotate_object_local(Vector3.FORWARD, -edger.blade_spin_speed * delta)

	if edger._feed_preview_travel >= edger._feed_preview_length():
		reset_preview_motion()


func _update_parking_ramp_preview(delta: float) -> void:
	var board_center := edger.to_local(edger._sample_board.global_position)
	var board_center_x := board_center.x
	var board_leading_x: float = board_center_x + SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x: float = board_center_x - SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var ramps_can_raise := edger._centering_preview_phase < SawmillEdger.CenteringPreviewPhase.LOWER_RAMPS
	var ramps_should_raise := ramps_can_raise and (_board_is_clear_of_parking_ramps(board_center.z) or not _ramps_are_home())
	for station in edger._parking_ramp_stations:
		var station_x := float(station["x"])
		var board_over_ramp_x := board_leading_x >= station_x and board_trailing_x <= station_x
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp: Node3D = node as Node3D
			if is_instance_valid(ramp):
				var target_angle: float = float(ramp.get_meta("parked_angle" if ramps_should_raise and board_over_ramp_x else "retracted_angle", 0.0))
				ramp.rotation.x = move_toward(ramp.rotation.x, target_angle, edger.parking_ramp_speed * delta)


func _update_board_height_for_ramps(delta: float) -> void:
	if not is_instance_valid(edger._sample_board):
		return

	var edge_lifts := _current_parking_ramp_edge_lifts()
	var target_y := _board_chain_center_global_y() + (edge_lifts.x + edge_lifts.y) * 0.5
	var target_rotation_x := -asin(clampf((edge_lifts.y - edge_lifts.x) / SawmillEdger.SAMPLE_BOARD_WIDTH, -0.85, 0.85))
	var board_position := edger._sample_board.global_position
	board_position.y = target_y
	edger._sample_board.global_position = board_position
	edger._sample_board.rotation.x = target_rotation_x


func _current_parking_ramp_edge_lifts() -> Vector2:
	var max_lift := 0.0
	var zone_min_z := INF
	var zone_max_z := -INF
	var board_center := edger.to_local(edger._sample_board.global_position)
	var board_leading_x: float = board_center.x + SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x: float = board_center.x - SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	for station in edger._parking_ramp_stations:
		var station_x := float(station["x"])
		if board_leading_x < station_x or board_trailing_x > station_x:
			continue
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp := node as Node3D
			if not is_instance_valid(ramp):
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

	var lead_in := SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.75
	var board_front_z := board_center.z - SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	var board_back_z := board_center.z + SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	var back_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, board_back_z), 0.0, 1.0))
	var front_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, board_front_z), 0.0, 1.0))
	return Vector2(max_lift * front_progress, max_lift * back_progress)


func _board_is_clear_of_parking_ramps(board_center_z: float) -> bool:
	var board_min_z := board_center_z - SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	var board_max_z := board_center_z + SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	for station in edger._parking_ramp_stations:
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp := node as Node3D
			if not is_instance_valid(ramp):
				continue
			var lift_span := float(ramp.get_meta("board_lift_span", 0.0))
			var side_sign := 1.0 if ramp.position.z >= 0.0 else -1.0
			var inner_z := ramp.position.z - side_sign * lift_span
			var ramp_min_z := minf(ramp.position.z, inner_z)
			var ramp_max_z := maxf(ramp.position.z, inner_z)
			if board_max_z >= ramp_min_z and board_min_z <= ramp_max_z:
				return false
	return true


func _board_chain_center_global_y() -> float:
	return edger.to_global(Vector3(0.0, edger._preview_board_center_y(), 0.0)).y


func _ramps_are_home() -> bool:
	for station in edger._parking_ramp_stations:
		var nodes: Array = station["nodes"]
		for node in nodes:
			var ramp := node as Node3D
			if is_instance_valid(ramp) and absf(ramp.rotation.x - float(ramp.get_meta("retracted_angle", 0.0))) > SawmillEdger.PIN_READY_TOLERANCE:
				return false
	return true


func _board_is_on_chain() -> bool:
	return (
		absf(edger._sample_board.global_position.y - _board_chain_center_global_y()) <= SawmillEdger.CENTERING_TOLERANCE
		and absf(edger._sample_board.rotation.x) <= SawmillEdger.CENTERING_TOLERANCE
	)


func _update_pin_actuators(delta: float, active: bool, push_board: bool) -> void:
	var hold_position_pin_z := not push_board and (
		edger._centering_preview_phase == SawmillEdger.CenteringPreviewPhase.PIN_RETRACT_DELAY
		or edger._centering_preview_phase == SawmillEdger.CenteringPreviewPhase.RETRACT_PINS
	)
	for i in range(edger._position_pin_stations.size()):
		var station: Dictionary = edger._position_pin_stations[i]
		var pin: Node3D = station["pin"] as Node3D
		var sleeve: Node3D = station["sleeve"] as Node3D
		if not is_instance_valid(pin) and not is_instance_valid(sleeve):
			continue
		var pin_is_active := active and edger._active_centering_pin_indices.has(i)
		var target_y: float = _position_pin_raised_y(station) if pin_is_active else float(station["retracted_y"])
		var sleeve_target_y: float = _position_pin_sleeve_raised_y(station, target_y) if pin_is_active else float(station["sleeve_retracted_y"])
		var target_z := _position_pin_target_z(i, active, push_board)
		if is_instance_valid(pin):
			pin.position.y = move_toward(pin.position.y, target_y, edger.position_pin_speed * delta)
			if not hold_position_pin_z:
				pin.position.z = move_toward(pin.position.z, target_z, edger.centering_board_speed * delta)
		if is_instance_valid(sleeve):
			sleeve.position.y = move_toward(sleeve.position.y, sleeve_target_y, edger.position_pin_speed * delta)
			if not hold_position_pin_z:
				sleeve.position.z = move_toward(sleeve.position.z, target_z, edger.centering_board_speed * delta)

	for i in range(edger._cushion_pin_stations.size()):
		var station: Dictionary = edger._cushion_pin_stations[i]
		var body: Node3D = station["body"] as Node3D
		if not is_instance_valid(body):
			continue
		var target_z := _cushion_target_z(i, active)
		body.position.z = move_toward(body.position.z, target_z, edger.cushion_pin_speed * delta)


func _update_position_pins_z_home(delta: float) -> void:
	for station in edger._position_pin_stations:
		var base_z := float(station["z"])
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin):
			pin.position.y = float(station["retracted_y"])
			pin.position.z = move_toward(pin.position.z, base_z, edger.centering_board_speed * delta)
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve):
			sleeve.position.y = float(station["sleeve_retracted_y"])
			sleeve.position.z = move_toward(sleeve.position.z, base_z, edger.centering_board_speed * delta)


func _update_cushion_pins_home(delta: float) -> void:
	for station in edger._cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body):
			body.position.z = move_toward(body.position.z, float(station["base_z"]), edger.cushion_pin_speed * delta)


func _board_pin_clear_z() -> float:
	var pin_z := 0.0
	var found_pin := false
	for index in _select_board_contact_position_pins():
		if index < 0 or index >= edger._position_pin_stations.size():
			continue
		var pin := edger._position_pin_stations[index]["pin"] as Node3D
		if is_instance_valid(pin):
			pin_z = pin.global_position.z if not found_pin else maxf(pin_z, pin.global_position.z)
			found_pin = true
	if not found_pin:
		return edger._preview_board_home_global.z
	return maxf(edger._preview_board_home_global.z, pin_z + SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5 + SawmillEdger.PIN_BOARD_CLEARANCE)


func _board_center_target_z() -> float:
	return edger.global_transform.origin.z


func _position_pin_target_z(index: int, active: bool, push_board: bool) -> float:
	var station: Dictionary = edger._position_pin_stations[index]
	var base_z := float(station["z"])
	if not active or not push_board or not edger._active_centering_pin_indices.has(index):
		return base_z
	if not is_instance_valid(edger._sample_board):
		return base_z

	var board_minus_edge_global_z := edger._sample_board.global_position.z - SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	var pin_node := station["pin"] as Node3D
	var parent_node: Node3D = null
	if is_instance_valid(pin_node):
		parent_node = pin_node.get_parent() as Node3D
	var board_minus_edge_local_z := board_minus_edge_global_z
	if is_instance_valid(parent_node):
		board_minus_edge_local_z = parent_node.to_local(Vector3(edger._sample_board.global_position.x, edger._sample_board.global_position.y, board_minus_edge_global_z)).z
	return maxf(base_z, board_minus_edge_local_z - edger.position_pin_radius)


func _position_pin_raised_y(station: Dictionary) -> float:
	var board_top_y := edger._preview_board_center_y() + SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.5
	if is_instance_valid(edger._sample_board):
		board_top_y = edger.to_local(edger._sample_board.global_position).y + SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.5
	var pin_center_for_board_top := board_top_y - edger.position_pin_height * 0.5 + 0.012
	return clampf(pin_center_for_board_top, float(station["retracted_y"]), float(station["raised_y"]))


func _position_pin_sleeve_raised_y(station: Dictionary, pin_target_y: float) -> float:
	return float(station["sleeve_retracted_y"]) + maxf(pin_target_y - float(station["retracted_y"]), 0.0)


func _cushion_target_z(index: int, active: bool) -> float:
	var station: Dictionary = edger._cushion_pin_stations[index]
	var base_z := float(station["base_z"])
	if not active or not edger._active_centering_pin_indices.has(index):
		return base_z

	var fully_extended_z := base_z - edger.cushion_pin_extension
	var body := station["body"] as Node3D
	if not is_instance_valid(body) or not is_instance_valid(edger._sample_board):
		return fully_extended_z

	var board_plus_edge_global_z := edger._sample_board.global_position.z + SawmillEdger.SAMPLE_BOARD_WIDTH * 0.5
	var parent_node := body.get_parent() as Node3D
	var board_plus_edge_local_z := board_plus_edge_global_z
	if is_instance_valid(parent_node):
		board_plus_edge_local_z = parent_node.to_local(Vector3(edger._sample_board.global_position.x, edger._sample_board.global_position.y, board_plus_edge_global_z)).z

	var pad_contact_offset := SawmillEdger.CUSHION_PAD_CONTACT_OFFSET_Z - edger.cushion_pin_extension * 0.5
	var contact_z := board_plus_edge_local_z - pad_contact_offset
	return clampf(contact_z, fully_extended_z, base_z)


func _active_pins_are_raised() -> bool:
	for index in edger._active_centering_pin_indices:
		if index < 0 or index >= edger._position_pin_stations.size():
			continue
		var station: Dictionary = edger._position_pin_stations[index]
		var pin := station["pin"] as Node3D
		var pin_target_y := _position_pin_raised_y(station)
		if is_instance_valid(pin) and absf(pin.position.y - pin_target_y) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - _position_pin_sleeve_raised_y(station, pin_target_y)) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
	return not edger._active_centering_pin_indices.is_empty()


func _active_cushions_are_at_target() -> bool:
	for index in edger._active_centering_pin_indices:
		if index < 0 or index >= edger._cushion_pin_stations.size():
			continue
		var station: Dictionary = edger._cushion_pin_stations[index]
		var body := station["body"] as Node3D
		if is_instance_valid(body) and absf(body.position.z - _cushion_target_z(index, true)) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
	return not edger._active_centering_pin_indices.is_empty()


func _pins_are_retracted_down() -> bool:
	for station in edger._position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin) and absf(pin.position.y - float(station["retracted_y"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - float(station["sleeve_retracted_y"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
	return true


func _cushions_are_home() -> bool:
	for station in edger._cushion_pin_stations:
		var body := station["body"] as Node3D
		if is_instance_valid(body) and absf(body.position.z - float(station["base_z"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
	return true


func _pins_and_cushions_are_home() -> bool:
	for station in edger._position_pin_stations:
		var pin := station["pin"] as Node3D
		if is_instance_valid(pin) and absf(pin.position.y - float(station["retracted_y"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
		if is_instance_valid(pin) and absf(pin.position.z - float(station["z"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
		var sleeve := station["sleeve"] as Node3D
		if is_instance_valid(sleeve) and absf(sleeve.position.y - float(station["sleeve_retracted_y"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
		if is_instance_valid(sleeve) and absf(sleeve.position.z - float(station["z"])) > SawmillEdger.PIN_READY_TOLERANCE:
			return false
	return _cushions_are_home()


func _select_board_contact_position_pins() -> Array[int]:
	var candidates: Array[Dictionary] = []
	var board_center_x := _board_center_x_for_pin_selection()
	var board_start_x := board_center_x - SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var board_end_x := board_center_x + SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var contact_min_x := board_start_x - edger.position_pin_radius - SawmillEdger.PIN_BOARD_X_CONTACT_MARGIN
	var contact_max_x := board_end_x + edger.position_pin_radius + SawmillEdger.PIN_BOARD_X_CONTACT_MARGIN

	for i in range(edger._position_pin_stations.size()):
		var station: Dictionary = edger._position_pin_stations[i]
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
	if is_instance_valid(edger._sample_board):
		return edger.to_local(edger._sample_board.global_position).x
	return edger.to_local(edger._preview_board_home_global).x


func _update_infeed_hold_down_preview(delta: float) -> void:
	if not is_instance_valid(edger._sample_board):
		return

	var board_center := edger.to_local(edger._sample_board.global_position)
	var board_leading_x := board_center.x + SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := board_center.x - SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var can_hold_down := edger._centering_preview_phase >= SawmillEdger.CenteringPreviewPhase.PIN_RETRACT_DELAY

	for station in edger._infeed_hold_down_stations:
		var station_x := float(station["x"])
		var board_under_roller := board_leading_x >= station_x - SawmillEdger.HOLD_DOWN_LEAD_IN and board_trailing_x <= station_x
		var target_y := float(station["raised_y"])
		if can_hold_down and board_under_roller:
			target_y = _infeed_hold_down_contact_y()

		var target_spin_velocity := 0.0
		if can_hold_down and board_under_roller and edger._centering_preview_phase == SawmillEdger.CenteringPreviewPhase.FEED_BOARD:
			target_spin_velocity = edger.infeed_chain_feed_speed / maxf(SawmillEdger.INFEED_HOLD_DOWN_ROLLER_RADIUS, 0.001) * edger.hold_down_roller_spin_speed
		var current_spin_velocity := float(station.get("spin_velocity", 0.0))
		current_spin_velocity = _move_hold_down_spin_velocity(current_spin_velocity, target_spin_velocity, delta)
		station["spin_velocity"] = current_spin_velocity

		var nodes: Array = station["nodes"]
		var y_offsets: Array = station["y_offsets"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if not is_instance_valid(node):
				continue
			node.position.y = move_toward(node.position.y, target_y + float(y_offsets[i]), edger.hold_down_lower_speed * delta if target_y < node.position.y else edger.hold_down_raise_speed * delta)
			if node.name.begins_with("InfeedHoldDownRoller") and not is_zero_approx(current_spin_velocity):
				node.rotate_object_local(Vector3.UP, current_spin_velocity * delta)
		_update_infeed_hold_down_actuator(station)


func _infeed_hold_down_contact_y() -> float:
	var board_center := edger.to_local(edger._sample_board.global_position)
	var board_top := board_center.y + SawmillEdger.SAMPLE_BOARD_THICKNESS * 0.5
	return board_top + SawmillEdger.INFEED_HOLD_DOWN_ROLLER_RADIUS - 0.006


func _update_infeed_hold_down_actuator(station: Dictionary) -> void:
	if not station.has("actuator"):
		return

	var actuator: Dictionary = station["actuator"]
	var root := actuator.get("root") as Node3D
	var attach_node := actuator.get("attach_node") as Node3D
	var rod := actuator.get("rod") as CSGCylinder3D
	var clevis := actuator.get("clevis") as Node3D
	var pin_hole := actuator.get("pin_hole") as Node3D
	if not is_instance_valid(root) or not is_instance_valid(attach_node):
		return

	var rod_top_y := float(actuator.get("rod_top_y", -0.087))
	var rod_bottom_y := root.to_local(attach_node.global_position).y
	var rod_height := maxf(rod_top_y - rod_bottom_y, 0.001)
	if is_instance_valid(rod):
		rod.height = rod_height
		rod.position.y = rod_top_y - rod_height * 0.5
	if is_instance_valid(clevis):
		clevis.position.y = rod_bottom_y
	if is_instance_valid(pin_hole):
		pin_hole.position.y = rod_bottom_y


func _update_hold_down_preview(delta: float, board_center_x: float) -> void:
	var board_leading_x := board_center_x + SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := board_center_x - SawmillEdger.SAMPLE_BOARD_LENGTH * 0.5
	for station in edger._hold_down_stations:
		var station_x := float(station["x"])
		var should_be_down := board_leading_x >= station_x - SawmillEdger.HOLD_DOWN_LEAD_IN and board_trailing_x <= station_x
		var target_offset := 0.0 if should_be_down else edger.hold_down_raised_offset
		var current_offset := float(station["offset"])
		var speed := edger.hold_down_lower_speed if should_be_down else edger.hold_down_raise_speed
		current_offset = move_toward(current_offset, target_offset, speed * delta)
		station["offset"] = current_offset
		var target_spin_velocity := 0.0
		if should_be_down and edger._centering_preview_phase == SawmillEdger.CenteringPreviewPhase.FEED_BOARD:
			target_spin_velocity = edger.infeed_chain_feed_speed / maxf(SawmillEdger.HOLD_DOWN_ROLLER_RADIUS, 0.001) * edger.hold_down_roller_spin_speed
		var current_spin_velocity := float(station.get("spin_velocity", 0.0))
		current_spin_velocity = _move_hold_down_spin_velocity(current_spin_velocity, target_spin_velocity, delta)
		station["spin_velocity"] = current_spin_velocity

		var nodes: Array = station["nodes"]
		var bases: Array = station["bases"]
		for i in range(nodes.size()):
			var node := nodes[i] as Node3D
			if is_instance_valid(node):
				node.position = bases[i] + Vector3(0.0, current_offset, 0.0)
				if node.name.begins_with("HoldDownRoller") and not is_zero_approx(current_spin_velocity):
					node.rotate_object_local(Vector3.UP, current_spin_velocity * delta)


func _move_hold_down_spin_velocity(current: float, target: float, delta: float) -> float:
	var rate := edger.hold_down_roller_spin_accel
	if is_zero_approx(target):
		rate = edger.hold_down_roller_spin_stop_rate
	return move_toward(current, target, rate * delta)
