extends Node3D

enum StopState {
	EXTENDED,
	HOLDING_LOG,
	RETRACTING,
	RETRACTED,
	EXTENDING,
}

@export var extended_y: float = 1.28
@export var retracted_y: float = 0.72
@export var move_speed: float = 1.8
@export var hold_time: float = 0.45
@export var retracted_time: float = 1.25

@onready var moving_stops: Node3D = $MovingStops
@onready var trigger_area: Area3D = $TriggerArea

var _state: StopState = StopState.EXTENDED
var _timer: float = 0.0

func _ready() -> void:
	moving_stops.position.y = extended_y
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)

func _physics_process(delta: float) -> void:
	match _state:
		StopState.HOLDING_LOG:
			_timer -= delta
			if _timer <= 0.0:
				_state = StopState.RETRACTING
		StopState.RETRACTING:
			_move_stops_toward(retracted_y, delta)
			if is_equal_approx(moving_stops.position.y, retracted_y):
				_state = StopState.RETRACTED
				_timer = retracted_time
		StopState.RETRACTED:
			_timer -= delta
			if _timer <= 0.0:
				_state = StopState.EXTENDING
		StopState.EXTENDING:
			_move_stops_toward(extended_y, delta)
			if is_equal_approx(moving_stops.position.y, extended_y):
				_state = StopState.EXTENDED

func _move_stops_toward(target_y: float, delta: float) -> void:
	var current := moving_stops.position.y
	moving_stops.position.y = move_toward(current, target_y, move_speed * delta)

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if _state != StopState.EXTENDED:
		return
	if body is RigidBody3D and body.is_in_group("logs"):
		_state = StopState.HOLDING_LOG
		_timer = hold_time
