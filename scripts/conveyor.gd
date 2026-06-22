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

@export_group("Kicker Configuration")
@export var kicker_enabled: bool = true
@export var kick_swing_speed: float = 220.0 ## Degrees per second for extending
@export var retract_speed: float = 180.0    ## Degrees per second for retracting
@export var hold_at_top: float = 0.3         ## Seconds to hold at full extension
@export var shaft_rotation_retracted: float = 0.0 ## Shaft rotation when retracted
@export var shaft_rotation_extended: float = 95.0  ## Shaft rotation when fully extended

enum KickerState { IDLE, KICKING, HOLDING, RETRACTING }
var _state: KickerState = KickerState.IDLE
var _hold_timer: float = 0.0
var _shaft_angle: float = 0.0

var _kicker_shaft_node: Node3D = null
var _kicker_pivots: Array[Node3D] = []
var _kicker_upper_bodies: Array[AnimatableBody3D] = []
var _kicker_lowers: Array[Node3D] = []
var _kicker_pivots_rollers: Array[Node3D] = []

var _is_stopped_by_backpressure: bool = false
var _actual_speed: float = 5.0
var _log_area: Area3D = null

func _ready() -> void:
	_actual_speed = speed
	_update_velocity()
	_log_area = get_node_or_null("LogArea")
	
	_build_kicker_hardware()
	if _kicker_shaft_node:
		if shaft_rotation_retracted == 0.0:
			shaft_rotation_retracted = _kicker_shaft_node.rotation_degrees.z
		if shaft_rotation_extended == 95.0:
			shaft_rotation_extended = shaft_rotation_retracted + 95.0
			
	_shaft_angle = shaft_rotation_retracted
	_update_kicker_arms()

func _physics_process(delta: float) -> void:
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

	if kicker_enabled:
		_process_kicker(delta)

func is_full() -> bool:
	return is_instance_valid(exit_sensor) and exit_sensor.has_overlapping_bodies()

func _update_velocity() -> void:
	var current_speed = 0.0 if _is_stopped_by_backpressure else speed
	constant_linear_velocity = direction.normalized() * current_speed

# ── Kicker Logic ──────────────────────────────────────────────────────────────

func kick() -> void:
	if not kicker_enabled or _state != KickerState.IDLE:
		return
	_state = KickerState.KICKING

func is_kicker_idle() -> bool:
	return _state == KickerState.IDLE

func _process_kicker(delta: float) -> void:
	match _state:
		KickerState.IDLE:
			_shaft_angle = shaft_rotation_retracted
			_update_kicker_arms()

		KickerState.KICKING:
			_shaft_angle = move_toward(_shaft_angle, shaft_rotation_extended, kick_swing_speed * delta)
			_update_kicker_arms()
			if is_equal_approx(_shaft_angle, shaft_rotation_extended):
				_state = KickerState.HOLDING
				_hold_timer = hold_at_top

		KickerState.HOLDING:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_state = KickerState.RETRACTING

		KickerState.RETRACTING:
			_shaft_angle = move_toward(_shaft_angle, shaft_rotation_retracted, retract_speed * delta)
			_update_kicker_arms()
			if is_equal_approx(_shaft_angle, shaft_rotation_retracted):
				_state = KickerState.IDLE

func _update_kicker_arms() -> void:
	if is_instance_valid(_kicker_shaft_node):
		_kicker_shaft_node.rotation_degrees.z = _shaft_angle
		
		# Update each upper arm dynamically to pivot around the lower arm tip and stay tangent to its roller
		for i in range(_kicker_pivots.size()):
			var pivot = _kicker_pivots[i]
			var lower = _kicker_lowers[i] if i < _kicker_lowers.size() else null
			var upper = _kicker_upper_bodies[i] if i < _kicker_upper_bodies.size() else null
			var roller = _kicker_pivots_rollers[i] if i < _kicker_pivots_rollers.size() else null
			
			if is_instance_valid(pivot) and is_instance_valid(lower) and is_instance_valid(upper) and is_instance_valid(roller):
				var lower_arm_length = 0.66866636
				var lower_mesh = lower.get_node_or_null("Mesh")
				if lower_mesh and lower_mesh.mesh is BoxMesh:
					lower_arm_length = lower_mesh.mesh.size.y
					
				# The pin joint is at the end of the lower arm
				var pivot_pos_local = lower.transform.basis.y * lower_arm_length
				
				# Convert roller position to ArmPivot local space
				var roller_pos_local = pivot.to_local(roller.global_position)
				
				# Calculate the angle of the upper arm in local space
				var dx = roller_pos_local.x - pivot_pos_local.x
				var dy = roller_pos_local.y - pivot_pos_local.y
				var L = sqrt(dx*dx + dy*dy)
				
				var D = 0.06 # roller radius (0.02) + upper arm half-thickness (0.04)
				
				if L > D:
					var phi = atan2(dy, dx) + asin(D / L)
					upper.position = pivot_pos_local
					upper.rotation.z = phi - PI/2

func _build_kicker_hardware() -> void:
	_kicker_shaft_node = get_node_or_null("KickerShaft")
	_kicker_pivots.clear()
	_kicker_upper_bodies.clear()
	_kicker_lowers.clear()
	_kicker_pivots_rollers.clear()

	# Find rollers under Visuals/RailLeft
	var rollers: Array[Node3D] = []
	var rail_left = get_node_or_null("Visuals/RailLeft")
	if rail_left:
		for child in rail_left.get_children():
			if child is CSGCylinder3D and child.name.begins_with("Roller"):
				rollers.append(child)

	if _kicker_shaft_node:
		for child in _kicker_shaft_node.get_children():
			if child.name.begins_with("ArmPivot"):
				_kicker_pivots.append(child)
				
				# Find LowerArm under the pivot
				var lower = child.get_node_or_null("LowerArm")
				if lower:
					_kicker_lowers.append(lower)
				else:
					# Placeholder to maintain alignment
					_kicker_lowers.append(null)
				
				# Find UpperArmBody under the pivot
				var upper = child.get_node_or_null("UpperArmBody")
				if not upper:
					for gchild in child.get_children():
						if gchild.name.begins_with("UpperArmBody"):
							upper = gchild
							break
				if upper:
					_kicker_upper_bodies.append(upper)
				else:
					# Placeholder to maintain alignment
					_kicker_upper_bodies.append(null)

				# Find the closest roller by global Z coordinate
				var closest_roller: Node3D = null
				var min_dist = 999999.0
				for roller in rollers:
					var dist = abs(child.global_position.z - roller.global_position.z)
					if dist < min_dist:
						min_dist = dist
						closest_roller = roller
				_kicker_pivots_rollers.append(closest_roller)
