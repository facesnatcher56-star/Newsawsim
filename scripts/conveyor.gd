extends StaticBody3D

@export var speed: float = 5.0:
	set(v):
		if speed != v:
			speed = v
			constant_linear_velocity = direction.normalized() * speed

@export var direction: Vector3 = Vector3.FORWARD:
	set(v):
		direction = v
		_update_velocity()

## If assigned, this conveyor will stop if the downstream conveyor is full or blocked.
@export var downstream_conveyor: StaticBody3D
## Area3D at the end of THIS conveyor to detect if a log is waiting to move off.
@export var exit_sensor: Area3D
## When true, logs inside LogArea have their rotation and lateral drift locked.
@export var lock_logs: bool = false

var _is_stopped_by_backpressure: bool = false
var _actual_speed: float = 5.0
var _log_area: Area3D = null

func _ready() -> void:
	_actual_speed = speed
	_update_velocity()
	_log_area = get_node_or_null("LogArea")

func _physics_process(_delta: float) -> void:
	var blocked = false
	if is_instance_valid(downstream_conveyor):
		# Check if downstream is full or stopped
		var downstream_busy = false
		if downstream_conveyor.has_method("is_full") and downstream_conveyor.is_full():
			downstream_busy = true
		elif downstream_conveyor.get("speed") == 0.0 or downstream_conveyor.get("_is_stopped_by_backpressure") == true:
			downstream_busy = true
			
		# If downstream is busy and we have a log at our exit, we must stop.
		if downstream_busy and is_instance_valid(exit_sensor) and exit_sensor.has_overlapping_bodies():
			blocked = true
	
	if blocked != _is_stopped_by_backpressure:
		_is_stopped_by_backpressure = blocked
		_update_velocity()

	if lock_logs and _log_area != null:
		var fwd := direction.normalized()
		for body in _log_area.get_overlapping_bodies():
			if body is RigidBody3D and body.is_in_group("logs"):
				body.angular_velocity = Vector3.ZERO
				var v: Vector3 = body.linear_velocity
				body.linear_velocity = fwd * v.dot(fwd) + Vector3(0.0, v.y, 0.0)

func is_full() -> bool:
	return is_instance_valid(exit_sensor) and exit_sensor.has_overlapping_bodies()

func _update_velocity() -> void:
	var current_speed = 0.0 if _is_stopped_by_backpressure else speed
	constant_linear_velocity = direction.normalized() * current_speed
