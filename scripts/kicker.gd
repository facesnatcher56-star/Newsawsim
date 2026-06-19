extends Area3D

@export var kick_direction: Vector3 = Vector3(1, 0, 0)
@export var kick_speed: float = 1.0
@export var kick_damping: float = 5.0
## Optional: path to the InclineLogDeck. When set, the kick is held until the
## deck has room (backpressure from a full incline).
@export var incline_path: NodePath

var original_speed: float = -1.0
var is_kicking: bool = false
## True while a log is held in the kick zone waiting for the incline to have room.
var is_blocked: bool = false

var _incline: Node = null

func _ready() -> void:
	if incline_path:
		_incline = get_node_or_null(incline_path)

func _physics_process(delta: float) -> void:
	var bodies = get_overlapping_bodies()
	var rigid_bodies: Array[RigidBody3D] = []
	for body in bodies:
		if body is RigidBody3D:
			rigid_bodies.append(body)

	var log_in_zone := rigid_bodies.size() > 0
	var parent = get_parent()

	if log_in_zone:
		if not is_kicking:
			if parent and "speed" in parent:
				if original_speed < 0:
					original_speed = parent.speed
				parent.speed = 0.0
			is_kicking = true

		var can_kick: bool = _incline == null or _incline.has_room()
		is_blocked = not can_kick

		if can_kick:
			var global_kick_dir := global_transform.basis * kick_direction.normalized()
			var target_kick_vel := global_kick_dir * kick_speed
			for log_body in rigid_bodies:
				var current_kick_vel: Vector3 = global_kick_dir * log_body.linear_velocity.dot(global_kick_dir)
				var other_vel: Vector3 = log_body.linear_velocity - current_kick_vel
				log_body.linear_velocity = current_kick_vel.lerp(target_kick_vel, kick_damping * delta) + other_vel.lerp(Vector3.ZERO, kick_damping * delta)
		# else: hold — conveyor is already stopped, don't push the log
	else:
		is_blocked = false
		if is_kicking:
			if parent and "speed" in parent and original_speed >= 0:
				parent.speed = original_speed
			original_speed = -1.0
			is_kicking = false

			# Activate tracer on the boom log when it leaves the WasteConveyor3 kick zone
			if get_parent().name == "WasteConveyor3":
				for body in get_tree().get_nodes_in_group("logs"):
					if body.has_meta("boom_log") and body.has_method("enable_trace"):
						body.enable_trace()
						break
