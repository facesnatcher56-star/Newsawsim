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
@export var retracted_rotation_deg: float = -70.0
@export var rotation_speed: float = 120.0 # degrees per second
@export var hold_time: float = 0.45
@export var retracted_time: float = 1.25

@onready var moving_stops: Node3D = $MovingStops
@onready var trigger_area: Area3D = $TriggerArea

var _state: StopState = StopState.EXTENDED
var _timer: float = 0.0
var _current_rot: float = 0.0

func _ready() -> void:
	_current_rot = extended_rotation_deg
	if Engine.is_editor_hint():
		if moving_stops:
			moving_stops.rotation.x = deg_to_rad(_current_rot)
		return
		
	moving_stops.rotation.x = deg_to_rad(_current_rot)
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		if moving_stops and moving_stops.rotation.x != deg_to_rad(extended_rotation_deg):
			moving_stops.rotation.x = deg_to_rad(extended_rotation_deg)
		return
		
	match _state:
		StopState.HOLDING_LOG:
			_timer -= delta
			if _timer <= 0.0:
				_state = StopState.RETRACTING
		StopState.RETRACTING:
			_move_stops_toward(retracted_rotation_deg, delta)
			if is_equal_approx(_current_rot, retracted_rotation_deg):
				_state = StopState.RETRACTED
				_timer = retracted_time
		StopState.RETRACTED:
			var has_log = false
			for body in trigger_area.get_overlapping_bodies():
				if body is RigidBody3D and body.is_in_group("logs"):
					has_log = true
					break
			if not has_log:
				_state = StopState.EXTENDING
		StopState.EXTENDING:
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

