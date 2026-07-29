@tool
class_name EdgerParkingRampSystem
extends Node3D

var edger: SawmillEdger

@export_category("Parking Ramps")
@export_range(0.0, 8.0, 0.01, "or_greater") var parking_ramp_speed: float = 1.8
@export_range(0.0, 2000.0, 1.0, "or_greater") var parking_ramp_lift_force: float = 520.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parking_ramp_lift_damping: float = 35.0


func _ready() -> void:
	edger = get_parent() as SawmillEdger


func update(delta: float) -> void:
	var ramps := edger._parking_ramp_nodes()
	if ramps.is_empty():
		return
	var should_raise := is_instance_valid(edger._centering_board)
	for ramp in ramps:
		var target_angle: float
		if should_raise:
			target_angle = float(ramp.get_meta("parked_angle", 0.0))
		else:
			target_angle = float(ramp.get_meta("retracted_angle", 0.0))
		ramp.rotation.x = move_toward(ramp.rotation.x, target_angle, parking_ramp_speed * delta)


func apply_edge_contacts(body: RigidBody3D, local_center: Vector3) -> void:
	var edge_lifts := _edge_lifts_for_board(body, local_center)
	if edge_lifts == Vector2.ZERO:
		return

	var y_axis := edger.global_transform.basis.y.normalized()
	var base_center_y := edger.to_global(Vector3(0.0, edger._board_center_y(), 0.0)).dot(y_axis)
	var bounds := edger._get_board_local_z_bounds_for_body(body)
	_apply_board_edge_lift(body, bounds.x - local_center.z, base_center_y + edge_lifts.x, y_axis)
	_apply_board_edge_lift(body, bounds.y - local_center.z, base_center_y + edge_lifts.y, y_axis)


func ramps_are_home() -> bool:
	return edger._real_ramps_are_home(edger._parking_ramp_nodes())


func _edge_lifts_for_board(body: RigidBody3D, local_center: Vector3) -> Vector2:
	var max_lift := 0.0
	var zone_min_z := INF
	var zone_max_z := -INF
	var board_leading_x := local_center.x + edger.SAMPLE_BOARD_LENGTH * 0.5
	var board_trailing_x := local_center.x - edger.SAMPLE_BOARD_LENGTH * 0.5
	for ramp in edger._parking_ramp_nodes():
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

	var thickness := edger._get_board_thickness_for_body(body)
	var lead_in := thickness * 0.75
	var bounds := edger._get_board_local_z_bounds_for_body(body)
	var front_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, bounds.x), 0.0, 1.0))
	var back_progress := smoothstep(0.0, 1.0, clampf(inverse_lerp(zone_min_z - lead_in, zone_max_z, bounds.y), 0.0, 1.0))
	return Vector2(max_lift * front_progress, max_lift * back_progress)


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
