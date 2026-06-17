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

@onready var moving_stops: Node3D = $MovingStops
@onready var trigger_area: Area3D = $TriggerArea
@onready var deck_area: Area3D = $DeckArea

var _state: StopState = StopState.EXTENDED
var _timer: float = 0.0
var _current_rot: float = 0.0
var _conveyor: Node3D = null

func _ready() -> void:
	_current_rot = extended_rotation_deg
	_conveyor = get_parent()
	
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
				_conveyor.speed = 0.0
			_move_stops_toward(retracted_rotation_deg, delta)
			if is_equal_approx(_current_rot, retracted_rotation_deg):
				_state = StopState.RETRACTED
				_timer = retracted_time
				
		StopState.RETRACTED:
			if _conveyor:
				_conveyor.speed = 0.0
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
			_move_stops_toward(extended_rotation_deg, delta)
			if is_equal_approx(_current_rot, extended_rotation_deg):
				_state = StopState.EXTENDED

func _move_stops_toward(target_rot: float, delta: float) -> void:
	_current_rot = move_toward(_current_rot, target_rot, rotation_speed * delta)
	moving_stops.rotation.x = deg_to_rad(_current_rot)

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if _state != StopState.EXTENDED:
		return
	if body is RigidBody3D and body.is_in_group("logs"):
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
