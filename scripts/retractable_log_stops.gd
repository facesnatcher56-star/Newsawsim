@tool
extends Node3D

enum StopState {
	EXTENDED,
	HOLDING_LOG,
	RETRACTING,
	RETRACTED,
	SETTLING,
	EXTENDING,
}

@export var extended_rotation_deg: float = 0.0
@export var retracted_rotation_deg: float = -180.0
@export var rotation_speed: float = 120.0 # degrees per second
@export var hold_time: float = 0.45
@export var retracted_time: float = 1.25
@export var run_speed: float = 0.2
@export var deck_start_delay: float = 2.0
@export var chain_grip_acceleration: float = 2.0
@export_node_path("Node3D") var dump_target_path: NodePath
@export var dump_speed: float = 0.9
@export var dump_acceleration: float = 1.4
@export var settle_height_above_bottom: float = 0.4
@export var settle_vertical_speed: float = 0.18
@export var settle_time: float = 0.3
## Optional: path to the WasteConveyor3/KickerZone (or any kicker with is_blocked).
## When the kicker is blocked (incline full), we hold here rather than dumping
## another log into the debarker infeed.
@export var downstream_kicker_path: NodePath

@onready var moving_stops: Node3D = $MovingStops
@onready var stop_body: AnimatableBody3D = $MovingStops/StopBody
@onready var stop_visuals: Node3D = $MovingStops/Visuals
@onready var trigger_area: Area3D = $TriggerArea
@onready var deck_area: Area3D = $DeckArea

var _state: StopState = StopState.EXTENDED
var _timer: float = 0.0
var _current_rot: float = 0.0
var _conveyor: Node3D = null
var _dump_target: Node3D = null
var _downstream_kicker: Node = null
var _dumping_logs: Array[RigidBody3D] = []
var _deck_logs: Array[RigidBody3D] = []
var _dump_target_run_speed: float = 0.0
var _deck_start_timer: float = -1.0

func _ready() -> void:
	_current_rot = extended_rotation_deg
	_conveyor = get_parent()
	_dump_target = get_node_or_null(dump_target_path) as Node3D
	if _dump_target and "speed" in _dump_target:
		_dump_target_run_speed = _dump_target.speed
	if downstream_kicker_path:
		_downstream_kicker = get_node_or_null(downstream_kicker_path)
	
	if Engine.is_editor_hint():
		_set_stop_rotation(_current_rot)
		return
		
	_set_stop_rotation(_current_rot)
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)
	if deck_area:
		deck_area.body_entered.connect(_on_deck_area_body_entered)
		deck_area.body_exited.connect(_on_deck_area_body_exited)
		for body in deck_area.get_overlapping_bodies():
			_on_deck_area_body_entered(body)

func _on_deck_area_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		if not _deck_logs.has(body):
			_deck_logs.append(body)
		_deck_start_timer = deck_start_delay
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.axis_lock_angular_z = true
		body.angular_velocity = Vector3.ZERO

func _on_deck_area_body_exited(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		_deck_logs.erase(body)
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		if stop_body and stop_body.rotation.x != deg_to_rad(extended_rotation_deg):
			_set_stop_rotation(extended_rotation_deg)
		return
		
	match _state:
		StopState.EXTENDED:
			# Hold after the log enters the deck area so the loader can finish its
			# release and retract cycle before the chains begin moving.
			if _conveyor:
				var deck_logs := _get_deck_logs()
				if deck_logs.is_empty():
					_deck_start_timer = -1.0
					_conveyor.speed = 0.0
				elif _deck_start_timer > 0.0:
					_deck_start_timer = maxf(0.0, _deck_start_timer - delta)
					_conveyor.speed = 0.0
				else:
					if not is_equal_approx(_conveyor.speed, run_speed):
						_conveyor.speed = run_speed
					_carry_logs_with_chains(deck_logs, delta)
					
		StopState.HOLDING_LOG:
			if _conveyor:
				_conveyor.speed = 0.0
			_timer -= delta
			if _timer <= 0.0 and _downstream_clear():
				_state = StopState.RETRACTING
				
		StopState.RETRACTING:
			if _conveyor:
				_conveyor.speed = 0.0
			_dump_logs_toward_waste_conveyor(delta)
			_move_stops_toward(retracted_rotation_deg, delta)
			if is_equal_approx(_current_rot, retracted_rotation_deg):
				_state = StopState.RETRACTED
				_timer = retracted_time

		StopState.RETRACTED:
			if _conveyor:
				_conveyor.speed = 0.0
			_dump_logs_toward_waste_conveyor(delta)
			_timer -= delta
			# Wait until timer completes and the log has cleared the trigger area
			var has_log_in_trigger = false
			for body in trigger_area.get_overlapping_bodies():
				if body is RigidBody3D and body.is_in_group("logs"):
					has_log_in_trigger = true
					break
			if _timer <= 0.0 and not has_log_in_trigger:
				_state = StopState.SETTLING
				_timer = settle_time

		StopState.SETTLING:
			# Release the log to gravity with the infeed stopped.  It must be
			# resting on the infeed bottom before that conveyor can pull it ringward.
			if _conveyor:
				_conveyor.speed = 0.0
			_set_dump_target_speed(0.0)
			_suppress_upward_rebound()
			if _dumped_logs_are_seated():
				_timer -= delta
				if _timer <= 0.0:
					_set_dump_target_speed(_dump_target_run_speed)
					_state = StopState.EXTENDING
			else:
				_timer = settle_time
				
		StopState.EXTENDING:
			if _conveyor:
				_conveyor.speed = 0.0
			_prune_dumping_logs(true)
			_move_stops_toward(extended_rotation_deg, delta)
			if is_equal_approx(_current_rot, extended_rotation_deg):
				_state = StopState.EXTENDED

func _move_stops_toward(target_rot: float, delta: float) -> void:
	_current_rot = move_toward(_current_rot, target_rot, rotation_speed * delta)
	_set_stop_rotation(_current_rot)

func _set_stop_rotation(p_rotation_degrees: float) -> void:
	var rotation_radians := deg_to_rad(p_rotation_degrees)
	# Move the physics body directly so PhysicsServer receives the transform;
	# rotate the separate visual branch to exactly the same angle.
	if stop_body:
		stop_body.rotation.x = rotation_radians
	if stop_visuals:
		stop_visuals.rotation.x = rotation_radians

func _carry_logs_with_chains(deck_logs: Array[RigidBody3D], delta: float) -> void:
	if _conveyor == null or not ("direction" in _conveyor):
		return
	var chain_direction = (_conveyor.global_basis * _conveyor.direction).normalized()
	var target_velocity = chain_direction * run_speed
	for body in deck_logs:
		if not is_instance_valid(body) or body.freeze:
			continue
		body.sleeping = false
		var horizontal_velocity = Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		horizontal_velocity = horizontal_velocity.move_toward(
			Vector3(target_velocity.x, 0.0, target_velocity.z),
			chain_grip_acceleration * delta
		)
		body.linear_velocity = Vector3(
			horizontal_velocity.x,
			body.linear_velocity.y,
			horizontal_velocity.z
		)

func _dump_logs_toward_waste_conveyor(delta: float) -> void:
	_prune_dumping_logs(false)
	for body in _get_active_log_bodies():
		var dump_direction = _get_dump_direction(body)
		var target_horizontal_velocity = dump_direction * dump_speed
		var horizontal_velocity = Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		horizontal_velocity = horizontal_velocity.move_toward(
			target_horizontal_velocity,
			dump_acceleration * delta
		)
		body.sleeping = false
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false
		# Never inject vertical energy. Gravity lowers the heavy log naturally,
		# and positive velocity from a stop collision is cancelled before it jumps.
		body.linear_velocity = Vector3(
			horizontal_velocity.x,
			min(body.linear_velocity.y, 0.0),
			horizontal_velocity.z
		)

func _get_dump_direction(body: RigidBody3D) -> Vector3:
	var landing_position := _get_landing_position(body)
	if landing_position != Vector3.ZERO:
		var direction = landing_position - body.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			return direction.normalized()
		return Vector3.ZERO
	if _conveyor and "direction" in _conveyor:
		return (_conveyor.global_transform.basis * _conveyor.direction.normalized()).normalized()
	return -global_transform.basis.z.normalized()

func _get_landing_position(body: RigidBody3D) -> Vector3:
	if _dump_target:
		# The infeed's local X axis is its travel axis. Center the log on that
		# axis, but preserve its local Z position along the length of the trough.
		var local_position := _dump_target.to_local(body.global_position)
		local_position.x = 0.0
		local_position.y = 0.0
		return _dump_target.to_global(local_position)
	return Vector3.ZERO

func _get_bottom_surface_height() -> float:
	if _dump_target:
		var bottom := _dump_target.get_node_or_null("Bottom") as CollisionShape3D
		if bottom and bottom.shape is BoxShape3D:
			var box := bottom.shape as BoxShape3D
			return bottom.global_position.y + box.size.y * bottom.global_basis.y.length() * 0.5
		return _dump_target.global_position.y
	return -INF

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if _state != StopState.EXTENDED:
		return
	if body is RigidBody3D and body.is_in_group("logs"):
		if not _dumping_logs.has(body):
			_dumping_logs.append(body)
			_set_dump_target_speed(0.0)
			_state = StopState.HOLDING_LOG
			_timer = hold_time

func _set_dump_target_speed(value: float) -> void:
	if _dump_target and "speed" in _dump_target:
		_dump_target.speed = value

func _suppress_upward_rebound() -> void:
	for body in _dumping_logs:
		if is_instance_valid(body) and body.linear_velocity.y > 0.0:
			body.linear_velocity.y = 0.0

func _dumped_logs_are_seated() -> bool:
	if _dump_target == null or _dumping_logs.is_empty():
		return false
	var maximum_center_height = _get_bottom_surface_height() + settle_height_above_bottom
	var valid_log_found := false
	for body in _dumping_logs:
		if not is_instance_valid(body):
			continue
		valid_log_found = true
		if body.global_position.y > maximum_center_height:
			return false
		if abs(body.linear_velocity.y) > settle_vertical_speed:
			return false
	return valid_log_found

func _is_log_on_deck() -> bool:
	return not _get_deck_logs().is_empty()

func _get_deck_logs() -> Array[RigidBody3D]:
	var logs: Array[RigidBody3D] = []
	for body in _deck_logs:
		if is_instance_valid(body):
			logs.append(body)
	return logs

func _get_active_log_bodies() -> Array[RigidBody3D]:
	var found: Array[RigidBody3D] = []
	for body in _dumping_logs:
		if is_instance_valid(body) and not found.has(body):
			found.append(body)
	for area in [trigger_area, deck_area]:
		if area == null:
			continue
		for body in area.get_overlapping_bodies():
			if body is RigidBody3D and body.is_in_group("logs") and not found.has(body):
				found.append(body)
	return found

func _prune_dumping_logs(clear_all: bool) -> void:
	for i in range(_dumping_logs.size() - 1, -1, -1):
		var body = _dumping_logs[i]
		# A log that reaches the target must remain tracked through SETTLING;
		# otherwise the infeed could restart without verifying that it landed.
		if clear_all or not is_instance_valid(body):
			_dumping_logs.remove_at(i)

func _has_reached_dump_target(body: RigidBody3D) -> bool:
	if _dump_target == null:
		return false
	var offset = body.global_position - _dump_target.global_position
	var target_height = _dump_target.global_position.y + 0.45
	return Vector2(offset.x, offset.z).length() < 0.35 and body.global_position.y >= target_height


func _downstream_clear() -> bool:
	if _downstream_kicker == null:
		return true
	# The kicker sets is_blocked when a log is waiting and the incline is full.
	return not _downstream_kicker.get("is_blocked")
