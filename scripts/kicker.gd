extends Area3D

@export var kick_direction: Vector3 = Vector3(1, 0, 0)
@export var kick_speed: float = 1.0
@export var kick_damping: float = 5.0
## Optional: path to the InclineLogDeck. When set, the kick is held until the
## deck has room (backpressure from a full incline).
@export var incline_path: NodePath
## When true, the KickerShaft sibling physically sweeps the log via
## AnimatableBody3D — no velocity injection. The arm does the pushing.
@export var use_physical_arm: bool = false

var original_speed: float = -1.0
var is_kicking: bool = false
## True while a log is held in the kick zone waiting for the incline to have room.
var is_blocked: bool = false
var _arm_fired: bool = false

var _incline: Node = null
var _shaft: Node3D = null

func _ready() -> void:
	if incline_path:
		_incline = get_node_or_null(incline_path)
	if use_physical_arm:
		_shaft = get_parent().get_node_or_null("KickerShaft")

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
			# Log just entered — stop conveyor and start holding.
			# Do NOT fire yet; wait until can_kick is true.
			if parent and "speed" in parent:
				if original_speed < 0:
					original_speed = parent.speed
				parent.speed = 0.0
			if not use_physical_arm and parent and parent.has_method("kick"):
				parent.kick()
			# Relax arm bodies so the log sits on the belt naturally while waiting.
			if use_physical_arm and is_instance_valid(_shaft) and _shaft.has_method("relax"):
				_shaft.relax()
			is_kicking = true
			_arm_fired = false

		var can_kick: bool = _incline == null or _incline.has_room()
		is_blocked = not can_kick

		if can_kick:
			if use_physical_arm:
				# Fire arm once when the incline has room.
				# Log moves only from physical arm contact — no velocity injection.
				if not _arm_fired and is_instance_valid(_shaft) and _shaft.has_method("kick"):
					if _shaft.has_method("prime"):
						_shaft.prime()
					_shaft.kick()
					_arm_fired = true
					_start_log_trace(rigid_bodies)
			else:
				var global_kick_dir := global_transform.basis * kick_direction.normalized()
				var target_kick_vel := global_kick_dir * kick_speed
				for log_body in rigid_bodies:
					var current_kick_vel: Vector3 = global_kick_dir * log_body.linear_velocity.dot(global_kick_dir)
					var other_vel: Vector3 = log_body.linear_velocity - current_kick_vel
					log_body.linear_velocity = current_kick_vel.lerp(target_kick_vel, kick_damping * delta) + other_vel.lerp(Vector3.ZERO, kick_damping * delta)
		# else: hold — incline not ready, conveyor already stopped
	else:
		is_blocked = false
		if is_kicking:
			if parent and "speed" in parent and original_speed >= 0:
				parent.speed = original_speed
			original_speed = -1.0
			is_kicking = false
			_arm_fired = false


func _start_log_trace(bodies: Array[RigidBody3D]) -> void:
	for log_body in bodies:
		if not is_instance_valid(log_body):
			continue
		log_body.contact_monitor = true
		log_body.max_contacts_reported = 8
		print("[KICK TRACE] Arm fired — log at %v" % log_body.global_position)
		_trace_log(log_body, 0)


func _trace_log(log_body: RigidBody3D, tick: int) -> void:
	if not is_instance_valid(log_body) or tick > 200:
		return
	await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(log_body):
		return
	var vel := log_body.linear_velocity
	var contacts := log_body.get_colliding_bodies()
	print("[KICK TRACE] t=%.2fs  pos=%v  vel=%.3f  contacts=%d" % [
		tick * 0.05, log_body.global_position, vel.length(), contacts.size()])
	for c in contacts:
		print("  >> %s" % c.get_path())
	_trace_log(log_body, tick + 1)
