extends AnimatableBody3D

## headrig_carriage.gd
## Manages a high-fidelity headrig carriage with automated clamping knees and dogs.
## Automatically detects logs, clamps them using a two-stage process (pushing log
## against the knees first, then clamping down), travels, releases, and returns.

enum State {
	WAITING_FOR_LOG,
	CLAMPING_STAGE_1,  # Knee/turner arms close to push log against the backstop knees
	CLAMPING_STAGE_2,  # Dogs close down to bite into the log
	MOVING_FORWARD,
	UNCLAMPING,
	KICKING_LOG,
	RETURNING,
	WAITING_START
}

@export var speed: float = 2.0
@export var travel_distance: float = 10.0
@export var pause_at_ends: float = 2.0
@export var travel_axis: Vector3 = Vector3(0, 0, 1) # Axis in local space

# Clamp angles (in radians)
@export var open_knee_angle: float = -1.2
@export var closed_knee_angle: float = 0.2
@export var open_dog_angle: float = -0.8
@export var closed_dog_angle: float = 0.2
@export var clamp_speed: float = 4.0

# Kicking parameters
@export var kick_speed_x: float = 2.5 # sideway push (local +X, global -Z)
@export var kick_speed_y: float = 1.5 # upward pop

var current_state: State = State.WAITING_FOR_LOG
var timer: float = 0.0
var start_pos: Vector3
var target_pos: Vector3
var current_progress: float = 0.0 # Normalized position [0.0, 1.0]

# Node references
@onready var knees_assembly: Node3D = get_node_or_null("KneesAssembly")
@onready var dog_pivots = [
	get_node_or_null("KneesAssembly/DogPivot1"),
	get_node_or_null("KneesAssembly/DogPivot2"),
	get_node_or_null("KneesAssembly/DogPivot3")
]
@onready var knee_pivots = [
	get_node_or_null("KneesAssembly/KneePivot1"),
	get_node_or_null("KneesAssembly/KneePivot2"),
	get_node_or_null("KneesAssembly/KneePivot3")
]
@onready var log_detector: Area3D = get_node_or_null("KneesAssembly/LogDetector")

var clamped_log: RigidBody3D = null
var log_relative_transform: Transform3D
var clamp_timer: float = 0.0
var clamp_duration: float = 0.8 # duration for each stage

func _ready() -> void:
	start_pos = position
	target_pos = start_pos + travel_axis.normalized() * travel_distance
	
	# Set initial open positions for knees and dogs
	_set_angles(open_knee_angle, open_dog_angle)
	print("[HEADRIG CARRIAGE] Initialized at: ", start_pos, " traveling to: ", target_pos)

func _physics_process(delta: float) -> void:
	# Check if clamped log is still valid
	if clamped_log != null and not is_instance_valid(clamped_log):
		print("[HEADRIG CARRIAGE] Clamped log became invalid. Resetting.")
		clamped_log = null
		current_state = State.RETURNING
	
	match current_state:
		State.WAITING_FOR_LOG:
			if knees_assembly != null:
				knees_assembly.position.x = 0.0
			_animate_knees(open_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			var log_body = _detect_log()
			if log_body != null:
				clamped_log = log_body
				clamp_timer = clamp_duration
				current_state = State.CLAMPING_STAGE_1
				print("[HEADRIG CARRIAGE] Log detected: ", clamped_log.name, ". Starting Stage 1 (pushing log back).")
				
		State.CLAMPING_STAGE_1:
			# Stage 1: Close knees to push the log against the backstops (dogs stay open)
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				clamp_timer = clamp_duration
				current_state = State.CLAMPING_STAGE_2
				print("[HEADRIG CARRIAGE] Log pushed back. Starting Stage 2 (dogging).")
				
		State.CLAMPING_STAGE_2:
			# Stage 2: Clamping dogs close down to secure the log
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(closed_dog_angle, delta)
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				# Log is now clamped, lock it programmatically and align it on Y-axis
				if clamped_log != null:
					clamped_log.freeze = true
					# Rotate log on Y axis by 90 degrees relative to carriage so it lies along travel direction
					var relative_basis = Basis(Vector3.UP, PI / 2.0)
					
					# Calculate log radius dynamically
					var log_radius = 0.18
					for child in clamped_log.get_children():
						if child is CollisionShape3D and child.shape is BoxShape3D:
							var shape_size = child.shape.size
							var global_scale = clamped_log.global_transform.basis.get_scale()
							log_radius = min(shape_size.x * global_scale.x, shape_size.z * global_scale.z) * 0.5
							print("[HEADRIG CARRIAGE] Calculated log radius: ", log_radius)
							break
					
					# Offset relative to knees_assembly (loading side local +X)
					log_relative_transform = Transform3D(relative_basis, Vector3(0.175 + log_radius, 0.15 + log_radius, 0.0))
					
					if knees_assembly != null:
						clamped_log.global_transform = knees_assembly.global_transform * log_relative_transform
					else:
						clamped_log.global_transform = global_transform * log_relative_transform
						
					clamped_log.add_collision_exception_with(self)
					print("[HEADRIG CARRIAGE] Log locked, exception added, and aligned. Starting travel.")
				current_state = State.MOVING_FORWARD
				
		State.MOVING_FORWARD:
			# Player can slide the knees back and forth once log is dogged
			var slide_dir = 0.0
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_UP):
				slide_dir -= 1.0
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_DOWN):
				slide_dir += 1.0
			if slide_dir != 0.0:
				if knees_assembly != null:
					knees_assembly.position.x = clamp(knees_assembly.position.x + slide_dir * 0.3 * delta, -0.2, 0.2)

			current_progress += (speed / travel_distance) * delta
			if current_progress >= 1.0:
				current_progress = 1.0
				current_state = State.UNCLAMPING
				clamp_timer = clamp_duration
				print("[HEADRIG CARRIAGE] Reached end of travel. Starting unclamping.")
			var parent = get_parent()
			if parent != null:
				global_position = parent.global_transform * start_pos.lerp(target_pos, current_progress)
			else:
				position = start_pos.lerp(target_pos, current_progress)
			
			# Make log follow knees_assembly perfectly
			if clamped_log != null:
				if knees_assembly != null:
					clamped_log.global_transform = knees_assembly.global_transform * log_relative_transform
				else:
					clamped_log.global_transform = global_transform * log_relative_transform
				
		State.UNCLAMPING:
			# Open both knees and dogs
			_animate_knees(open_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			clamp_timer -= delta
			
			# Keep log attached during unclamping animation
			if clamped_log != null:
				if knees_assembly != null:
					clamped_log.global_transform = knees_assembly.global_transform * log_relative_transform
				else:
					clamped_log.global_transform = global_transform * log_relative_transform
				
			if clamp_timer <= 0.0:
				current_state = State.KICKING_LOG
				
		State.KICKING_LOG:
			if clamped_log != null:
				# Unfreeze the log and kick it off
				clamped_log.freeze = false
				clamped_log.remove_collision_exception_with(self)
				
				# Calculate local +X kick direction in global space (global -Z direction)
				var kick_dir_x = global_transform.basis.x.normalized()
				var kick_vel = kick_dir_x * kick_speed_x + Vector3(0, kick_speed_y, 0)
				clamped_log.linear_velocity = kick_vel
				
				# Wake it up
				clamped_log.sleeping = false
				
				print("[HEADRIG CARRIAGE] Log kicked with velocity: ", kick_vel)
				clamped_log = null
				
			timer = pause_at_ends
			current_state = State.RETURNING
			
		State.RETURNING:
			_animate_knees(open_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			current_progress -= (speed / travel_distance) * delta
			if current_progress <= 0.0:
				current_progress = 0.0
				timer = pause_at_ends
				current_state = State.WAITING_START
				print("[HEADRIG CARRIAGE] Returned to start. Pausing.")
			var parent = get_parent()
			if parent != null:
				global_position = parent.global_transform * start_pos.lerp(target_pos, current_progress)
			else:
				position = start_pos.lerp(target_pos, current_progress)
			
		State.WAITING_START:
			timer -= delta
			if timer <= 0.0:
				current_state = State.WAITING_FOR_LOG
				print("[HEADRIG CARRIAGE] Ready for next log.")

func _set_angles(knee_rot: float, dog_rot: float) -> void:
	for knee in knee_pivots:
		if knee != null:
			knee.rotation.z = knee_rot
	for dog in dog_pivots:
		if dog != null:
			dog.rotation.z = dog_rot

func _animate_knees(target_knee: float, delta: float) -> void:
	for knee in knee_pivots:
		if knee != null:
			knee.rotation.z = rotate_toward(knee.rotation.z, target_knee, clamp_speed * delta)

func _animate_dogs(target_dog: float, delta: float) -> void:
	for dog in dog_pivots:
		if dog != null:
			dog.rotation.z = rotate_toward(dog.rotation.z, target_dog, clamp_speed * delta)

func _detect_log() -> RigidBody3D:
	if log_detector == null:
		return null
	var bodies = log_detector.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D and body.is_in_group("logs"):
			# Only clamp logs that are free (not already frozen/locked by something else)
			if not body.freeze:
				return body
	return null
