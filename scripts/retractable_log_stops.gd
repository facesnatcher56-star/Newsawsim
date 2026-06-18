@tool
extends Node3D

enum StopState {
	EXTENDED,
	HOLDING_LOG,
	RETRACTING,
	RETRACTED,
	EXTENDING,
}

@export var extended_rotation_deg: float = 0.0
@export var retracted_rotation_deg: float = -180.0
@export var rotation_speed: float = 120.0 # degrees per second
@export var hold_time: float = 0.45
@export var retracted_time: float = 1.25
@export var run_speed: float = 0.2
@export_node_path("Node3D") var dump_target_path: NodePath
@export var dump_speed: float = 3.0
@export var dump_lift_speed: float = 1.8

@onready var moving_stops: Node3D = $MovingStops
@onready var trigger_area: Area3D = $TriggerArea
@onready var deck_area: Area3D = $DeckArea

var _state: StopState = StopState.EXTENDED
var _timer: float = 0.0
var _current_rot: float = 0.0
var _conveyor: Node3D = null
var _dump_target: Node3D = null
var _dumping_logs: Array[RigidBody3D] = []

func _ready() -> void:
	_current_rot = extended_rotation_deg
	_conveyor = get_parent()
	_dump_target = get_node_or_null(dump_target_path) as Node3D
	
	if Engine.is_editor_hint():
		if moving_stops:
			moving_stops.rotation.x = deg_to_rad(_current_rot)
		return
		
	moving_stops.rotation.x = deg_to_rad(_current_rot)
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)
	if deck_area:
		deck_area.body_entered.connect(_on_deck_area_body_entered)
		deck_area.body_exited.connect(_on_deck_area_body_exited)
		for body in deck_area.get_overlapping_bodies():
			_on_deck_area_body_entered(body)

func _on_deck_area_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.axis_lock_angular_z = true
		body.angular_velocity = Vector3.ZERO
		print("[STOPS] Log entered deck area. Locking rotation: ", body.name)

func _on_deck_area_body_exited(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false
		print("[STOPS] Log left deck area. Unlocking rotation: ", body.name)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		if moving_stops and moving_stops.rotation.x != deg_to_rad(extended_rotation_deg):
			moving_stops.rotation.x = deg_to_rad(extended_rotation_deg)
		return
		
	match _state:
		StopState.EXTENDED:
			# Conveyor runs only when a log is on the deck
			if _conveyor:
				if _is_log_on_deck():
					_conveyor.speed = run_speed
				else:
					_conveyor.speed = 0.0
					
		StopState.HOLDING_LOG:
			if _conveyor:
				_conveyor.speed = 0.0
			_timer -= delta
			if _timer <= 0.0:
				_state = StopState.RETRACTING
				
		StopState.RETRACTING:
			if _conveyor:
				_conveyor.speed = run_speed
			_dump_logs_toward_waste_conveyor(delta)
			_move_stops_toward(retracted_rotation_deg, delta)
			if is_equal_approx(_current_rot, retracted_rotation_deg):
				_state = StopState.RETRACTED
				_timer = retracted_time
				
		StopState.RETRACTED:
			if _conveyor:
				_conveyor.speed = run_speed
			_dump_logs_toward_waste_conveyor(delta)
			_timer -= delta
			# Wait until timer completes and the log has cleared the trigger area
			var has_log_in_trigger = false
			for body in trigger_area.get_overlapping_bodies():
				if body is RigidBody3D and body.is_in_group("logs"):
					has_log_in_trigger = true
					break
			if _timer <= 0.0 and not has_log_in_trigger:
				_state = StopState.EXTENDING
				
		StopState.EXTENDING:
			if _conveyor:
				_conveyor.speed = 0.0
			_prune_dumping_logs(true)
			_move_stops_toward(extended_rotation_deg, delta)
			if is_equal_approx(_current_rot, extended_rotation_deg):
				_state = StopState.EXTENDED

func _move_stops_toward(target_rot: float, delta: float) -> void:
	_current_rot = move_toward(_current_rot, target_rot, rotation_speed * delta)
	moving_stops.rotation.x = deg_to_rad(_current_rot)

func _dump_logs_toward_waste_conveyor(delta: float) -> void:
	_prune_dumping_logs(false)
	for body in _get_active_log_bodies():
		var dump_direction = _get_dump_direction(body)
		var target_velocity = dump_direction * dump_speed
		target_velocity.y = _get_dump_lift_velocity(body)
		body.sleeping = false
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false
		body.linear_velocity = target_velocity
		if _dump_target:
			var target_position = _dump_target.global_position + Vector3(0.0, 0.65, 0.0)
			body.global_position = body.global_position.move_toward(target_position, dump_speed * delta)
		body.angular_velocity = dump_direction.cross(Vector3.UP).normalized() * dump_speed

func _get_dump_direction(body: RigidBody3D) -> Vector3:
	if _dump_target:
		var direction = _dump_target.global_position - body.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			return direction.normalized()
	if _conveyor and "direction" in _conveyor:
		return (_conveyor.global_transform.basis * _conveyor.direction.normalized()).normalized()
	return -global_transform.basis.z.normalized()

func _get_dump_lift_velocity(body: RigidBody3D) -> float:
	if _dump_target:
		var target_height = _dump_target.global_position.y + 0.55
		if body.global_position.y < target_height:
			return max(dump_lift_speed, (target_height - body.global_position.y) * 4.0)
	return min(body.linear_velocity.y, dump_lift_speed)

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if _state != StopState.EXTENDED:
		return
	if body is RigidBody3D and body.is_in_group("logs"):
		if not _dumping_logs.has(body):
			_dumping_logs.append(body)
		_state = StopState.HOLDING_LOG
		_timer = hold_time

func _is_log_on_deck() -> bool:
	if deck_area == null:
		return false
	var bodies = deck_area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D and body.is_in_group("logs"):
			return true
	return false

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
		if clear_all or not is_instance_valid(body) or _has_reached_dump_target(body):
			_dumping_logs.remove_at(i)

func _has_reached_dump_target(body: RigidBody3D) -> bool:
	if _dump_target == null:
		return false
	var offset = body.global_position - _dump_target.global_position
	var target_height = _dump_target.global_position.y + 0.45
	return Vector2(offset.x, offset.z).length() < 0.35 and body.global_position.y >= target_height
