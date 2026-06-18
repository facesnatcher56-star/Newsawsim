extends Node

## headrig_log_loader.gd
## Automates the log deck advance chains, retractable stops, and log loader/turner arms.
## Coordinates with the HeadrigCarriage to load and flip logs.

enum LoaderState {
	IDLE,
	WAITING_FOR_CARRIAGE,
	LOADING_LOG,
	RETRACTING_LOADER,
	ASSISTING_FLIP
}

@export_node_path("AnimatableBody3D") var carriage_path: NodePath
@export var advance_speed: float = 0.2
@export var rotation_speed: float = 120.0 # degrees per second

# Angles for stops (rotation around X)
@export var stops_extended_angle: float = 0.0
@export var stops_retracted_angle: float = -90.0

# Angles for turner arms (rotation around X)
@export var turner_lowered_angle: float = -90.0
@export var turner_raised_angle: float = 20.0
@export var turner_assist_angle: float = -35.0

@onready var deck_conveyor: Node3D = get_parent()
@onready var trigger_area: Area3D = get_parent().get_node("TriggerArea")
@onready var deck_area: Area3D = get_parent().get_node("DeckArea")
@onready var stop_body: AnimatableBody3D = get_parent().get_node("RetractableStops/StopBody")
@onready var turner_body: AnimatableBody3D = get_parent().get_node("LogTurner/TurnerBody")

# Carriage States (from headrig_carriage.gd)
const CARRIAGE_WAITING_FOR_LOG = 0
const CARRIAGE_UNDOGGING_FOR_FLIP = 15
const CARRIAGE_FLIPPING_LOG = 16

var _state: LoaderState = LoaderState.IDLE
var _carriage: Node3D = null
var _current_stops_rot: float = 0.0
var _current_turner_rot: float = -90.0
var _active_log: RigidBody3D = null

func _ready() -> void:
	_carriage = get_node_or_null(carriage_path) as Node3D
	_current_stops_rot = stops_extended_angle
	_current_turner_rot = turner_lowered_angle
	_set_stops_rotation(_current_stops_rot)
	_set_turner_rotation(_current_turner_rot)
	
	if trigger_area:
		trigger_area.body_entered.connect(_on_trigger_area_body_entered)
	
	print("[HEADRIG LOADER] Initialized. Linked to carriage: ", _carriage != null)

func _physics_process(delta: float) -> void:
	if _carriage == null:
		_carriage = get_node_or_null(carriage_path) as Node3D
		if _carriage == null:
			return

	var carriage_state = _carriage.get("current_state")
	
	# Check if carriage has started flipping/undogging - if so, immediately assist
	if (carriage_state == CARRIAGE_FLIPPING_LOG or carriage_state == CARRIAGE_UNDOGGING_FOR_FLIP) and _state != LoaderState.ASSISTING_FLIP:
		_state = LoaderState.ASSISTING_FLIP
		print("[HEADRIG LOADER] Carriage is flipping. Entering ASSISTING_FLIP state.")
		
	match _state:
		LoaderState.IDLE:
			# Advance deck chains if trigger area is empty
			if _has_log_in_area(trigger_area):
				_state = LoaderState.WAITING_FOR_CARRIAGE
				print("[HEADRIG LOADER] Log reached stop trigger. Stopping chains.")
			else:
				deck_conveyor.speed = advance_speed
				
			# Keep stops extended and turner lowered
			_move_stops_to(stops_extended_angle, delta)
			_move_turner_to(turner_lowered_angle, delta)

		LoaderState.WAITING_FOR_CARRIAGE:
			deck_conveyor.speed = 0.0
			_move_stops_to(stops_extended_angle, delta)
			_move_turner_to(turner_lowered_angle, delta)
			
			# Check if log is still present
			var log_in_trigger = _get_log_in_area(trigger_area)
			if log_in_trigger == null:
				_state = LoaderState.IDLE
				print("[HEADRIG LOADER] Log cleared from stops trigger. Resuming advance.")
				return
				
			# Carriage is ready if it's waiting for log and parked home
			var carriage_pos = _carriage.global_position
			var carriage_at_home = abs(carriage_pos.x - 14.1) < 0.1
			if carriage_state == CARRIAGE_WAITING_FOR_LOG and carriage_at_home:
				_active_log = log_in_trigger
				_state = LoaderState.LOADING_LOG
				print("[HEADRIG LOADER] Carriage ready. Commencing loading cycle.")

		LoaderState.LOADING_LOG:
			deck_conveyor.speed = 0.0
			
			# Retract stops and raise turner arms to push the log onto the carriage
			_move_stops_to(stops_retracted_angle, delta)
			_move_turner_to(turner_raised_angle, delta)
			
			# Wake up active log to ensure physics pushes it
			if is_instance_valid(_active_log):
				_active_log.sleeping = false
				
			# Once carriage transitions out of waiting, the log is clamped!
			if carriage_state != CARRIAGE_WAITING_FOR_LOG:
				_state = LoaderState.RETRACTING_LOADER
				_active_log = null
				print("[HEADRIG LOADER] Carriage has clamped the log. Retracting loader arms.")

		LoaderState.RETRACTING_LOADER:
			deck_conveyor.speed = 0.0
			
			# Return stops and turner arms to home positions
			_move_stops_to(stops_extended_angle, delta)
			_move_turner_to(turner_lowered_angle, delta)
			
			if is_equal_approx(_current_stops_rot, stops_extended_angle) and is_equal_approx(_current_turner_rot, turner_lowered_angle):
				_state = LoaderState.IDLE
				print("[HEADRIG LOADER] Loader fully retracted. Returning to IDLE.")

		LoaderState.ASSISTING_FLIP:
			deck_conveyor.speed = 0.0
			
			# Retract stops and raise turner arms to assist flip
			_move_stops_to(stops_retracted_angle, delta)
			_move_turner_to(turner_assist_angle, delta)
			
			# When carriage finishes flipping and starts redogging/advancing, stop assisting
			if carriage_state != CARRIAGE_FLIPPING_LOG and carriage_state != CARRIAGE_UNDOGGING_FOR_FLIP:
				_state = LoaderState.RETRACTING_LOADER
				print("[HEADRIG LOADER] Flip completed. Retracting flip assist.")

func _move_stops_to(target_rot: float, delta: float) -> void:
	_current_stops_rot = move_toward(_current_stops_rot, target_rot, rotation_speed * delta)
	_set_stops_rotation(_current_stops_rot)

func _move_turner_to(target_rot: float, delta: float) -> void:
	_current_turner_rot = move_toward(_current_turner_rot, target_rot, rotation_speed * delta)
	_set_turner_rotation(_current_turner_rot)

func _set_stops_rotation(degrees: float) -> void:
	if stop_body:
		stop_body.rotation.x = deg_to_rad(degrees)

func _set_turner_rotation(degrees: float) -> void:
	if turner_body:
		turner_body.rotation.x = deg_to_rad(degrees)

func _has_log_in_area(area: Area3D) -> bool:
	return _get_log_in_area(area) != null

func _get_log_in_area(area: Area3D) -> RigidBody3D:
	if area == null:
		return null
	for body in area.get_overlapping_bodies():
		if body is RigidBody3D and body.is_in_group("logs"):
			return body
	return null

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		print("[HEADRIG LOADER] Log entered stop trigger area: ", body.name)
