extends AnimatableBody3D

## headrig_carriage.gd
## Manages a high-fidelity headrig carriage with automated clamping knees and dogs.
## Automatically detects logs, clamps them using a two-stage process (pushing log
## against the knees first, then clamping down), travels, releases, and returns.

enum State {
	WAITING_FOR_LOG,
	CLAMPING_STAGE_1,  # Knee/turner arms close to push log against the backstop knees
	CLAMPING_STAGE_2,  # Dogs close down to bite into the log
	MOVING_FORWARD,    # Travels forward, slows down as it cuts, slices off a board
	RETRACTING_LOG,    # Retracts knees and dogged log to -0.25 at end of travel
	RETURNING,         # Returns home with log retracted
	UNDOGGING_FOR_FLIP,# Opens dogs at home so the log can be turned
	FLIPPING_LOG,      # Rolls the log 180 degrees to put the sawn face against the blocks
	REDOGGING_AFTER_FLIP,# Closes dogs again after turning
	ADVANCING_LOG,     # Advances knees forward to expose next board thickness
	UNCLAMPING,        # Opens knees and dogs to release leftover slab
	KICKING_LOG,       # Kicks leftover slab off carriage
	WAITING_START      # Wait pause at home
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
@export var cuts_before_flip: int = 2
@export var flip_duration: float = 1.2

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
var has_cut_this_pass: bool = false
var cuts_on_current_face: int = 0
var has_flipped_log: bool = false
var log_roll_angle: float = 0.0
var flip_timer: float = 0.0
var flip_start_roll: float = 0.0
var flip_target_roll: float = 0.0

func _ready() -> void:
	start_pos = position
	target_pos = start_pos + travel_axis.normalized() * travel_distance
	
	# Set initial open positions for knees and dogs
	_set_angles(open_knee_angle, open_dog_angle)
	if knees_assembly != null:
		knees_assembly.position.x = -0.25
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
				knees_assembly.position.x = -0.25
			_animate_knees(open_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			var log_body = _detect_log()
			if log_body != null:
				clamped_log = log_body
				clamp_timer = clamp_duration
				current_state = State.CLAMPING_STAGE_1
				has_cut_this_pass = false
				print("[HEADRIG CARRIAGE] Log detected: ", clamped_log.name, ". Starting Stage 1 (pushing knees to log).")
				
		State.CLAMPING_STAGE_1:
			# Stage 1: Close knees to push the log against the backstops, slide knees forward to target cut position
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			var target_x = _get_knees_target_x()
			if knees_assembly != null:
				knees_assembly.position.x = move_toward(knees_assembly.position.x, target_x, 1.0 * delta)
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				clamp_timer = clamp_duration
				current_state = State.CLAMPING_STAGE_2
				print("[HEADRIG CARRIAGE] Log pushed. Starting Stage 2 (dogging).")
				
		State.CLAMPING_STAGE_2:
			# Stage 2: Clamping dogs close down to secure the log
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(closed_dog_angle, delta)
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				# Log is now clamped, lock it programmatically and align it
				if clamped_log != null:
					clamped_log.freeze = true
					var log_radius = clamped_log.get_current_radius()
					log_roll_angle = 0.0
					cuts_on_current_face = 0
					has_flipped_log = false
					log_relative_transform = Transform3D(_get_log_relative_basis(), Vector3(0.175 + log_radius, 0.15 + log_radius, 0.0))
					
					_update_clamped_log_transform()
					clamped_log.add_collision_exception_with(self)
					print("[HEADRIG CARRIAGE] Log locked and aligned. Starting travel.")
				has_cut_this_pass = false
				current_state = State.MOVING_FORWARD
				
		State.MOVING_FORWARD:
			# Automated speed control: slow down to 35% of normal speed as we pass the bandsaw (global X 17.5 to 20.5)
			var current_speed = speed
			if global_position.x > 17.5 and global_position.x < 20.5:
				current_speed = 0.35 * speed
			
			current_progress += (current_speed / travel_distance) * delta
			if current_progress >= 1.0:
				current_progress = 1.0
				if clamped_log != null and clamped_log.board_count > 0:
					current_state = State.RETRACTING_LOG
					print("[HEADRIG CARRIAGE] Pass complete. Retracting knees/log for safe return.")
				else:
					current_state = State.UNCLAMPING
					clamp_timer = clamp_duration
					print("[HEADRIG CARRIAGE] Reached end of travel (no boards left). Unclamping.")
			
			# Carriage travel position
			var parent = get_parent()
			if parent != null:
				global_position = parent.global_transform * start_pos.lerp(target_pos, current_progress)
			else:
				position = start_pos.lerp(target_pos, current_progress)
			
			# Trigger cut board when log tail end clears the bandsaw blade (global X > 20.15)
			if global_position.x > 20.15 and not has_cut_this_pass:
				if clamped_log != null and clamped_log.has_method("cut_board"):
					clamped_log.cut_board(Vector3(19, -0.083, 6.13))
					cuts_on_current_face += 1
				has_cut_this_pass = true
			
			# Update clamped log relative transform (keeps it flush with knees as it shrinks)
			_update_clamped_log_transform()
				
		State.RETRACTING_LOG:
			# Retract knees to -0.25 so the log clears the saw blade on the return trip
			if knees_assembly != null:
				knees_assembly.position.x = move_toward(knees_assembly.position.x, -0.25, 1.0 * delta)
			
			# Update clamped log transform to follow retraction
			_update_clamped_log_transform()
			
			if knees_assembly == null or abs(knees_assembly.position.x + 0.25) < 0.001:
				current_state = State.RETURNING
				print("[HEADRIG CARRIAGE] Knees retracted. Returning home.")
				
		State.RETURNING:
			current_progress -= (speed / travel_distance) * delta
			if current_progress <= 0.0:
				current_progress = 0.0
				if clamped_log != null and clamped_log.board_count > 0:
					if _should_flip_log_at_home():
						clamp_timer = clamp_duration
						current_state = State.UNDOGGING_FOR_FLIP
						print("[HEADRIG CARRIAGE] Returned home after ", cuts_on_current_face, " cuts. Undogging for 180-degree turn.")
					else:
						current_state = State.ADVANCING_LOG
						print("[HEADRIG CARRIAGE] Returned home. Advancing log.")
				else:
					timer = pause_at_ends
					current_state = State.WAITING_START
					print("[HEADRIG CARRIAGE] Returned home (finished). Pausing.")
			
			var parent = get_parent()
			if parent != null:
				global_position = parent.global_transform * start_pos.lerp(target_pos, current_progress)
			else:
				position = start_pos.lerp(target_pos, current_progress)
			
			# Keep log attached during return
			_update_clamped_log_transform()

		State.UNDOGGING_FOR_FLIP:
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			_update_clamped_log_transform()
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				flip_timer = 0.0
				flip_start_roll = log_roll_angle
				flip_target_roll = log_roll_angle + PI
				current_state = State.FLIPPING_LOG
				print("[HEADRIG CARRIAGE] Dogs open. Turning log 180 degrees.")

		State.FLIPPING_LOG:
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			flip_timer = min(flip_timer + delta, flip_duration)
			var t: float = flip_timer / max(flip_duration, 0.001)
			t = t * t * (3.0 - 2.0 * t)
			log_roll_angle = lerp(flip_start_roll, flip_target_roll, t)
			_update_clamped_log_transform()
			if flip_timer >= flip_duration:
				log_roll_angle = flip_target_roll
				has_flipped_log = true
				cuts_on_current_face = 0
				if clamped_log != null and clamped_log.has_method("start_new_cut_face"):
					clamped_log.start_new_cut_face()
				clamp_timer = clamp_duration
				current_state = State.REDOGGING_AFTER_FLIP
				print("[HEADRIG CARRIAGE] Log turned. Redogging on the fresh face.")

		State.REDOGGING_AFTER_FLIP:
			_animate_knees(closed_knee_angle, delta)
			_animate_dogs(closed_dog_angle, delta)
			_update_clamped_log_transform()
			clamp_timer -= delta
			if clamp_timer <= 0.0:
				has_cut_this_pass = false
				current_state = State.ADVANCING_LOG
				print("[HEADRIG CARRIAGE] Log redogged. Advancing for next face cut.")
						
		State.ADVANCING_LOG:
			# Advance knees forward to expose next board thickness
			var target_x = _get_knees_target_x()
			if knees_assembly != null:
				knees_assembly.position.x = move_toward(knees_assembly.position.x, target_x, 1.0 * delta)
				
			# Keep log attached as it is advanced
			_update_clamped_log_transform()
					
			if knees_assembly == null or abs(knees_assembly.position.x - target_x) < 0.001:
				has_cut_this_pass = false
				current_state = State.MOVING_FORWARD
				print("[HEADRIG CARRIAGE] Log advanced to ", target_x, ". Starting pass.")
				
		State.UNCLAMPING:
			# Open both knees and dogs
			_animate_knees(open_knee_angle, delta)
			_animate_dogs(open_dog_angle, delta)
			clamp_timer -= delta
			
			# Keep log attached during unclamping animation
			_update_clamped_log_transform()
				
			if clamp_timer <= 0.0:
				current_state = State.KICKING_LOG
				
		State.KICKING_LOG:
			if clamped_log != null:
				# Unfreeze the remaining slab and kick it off
				clamped_log.freeze = false
				clamped_log.remove_collision_exception_with(self)
				
				# Calculate local +X kick direction in global space (global -Z direction)
				var kick_dir_x = global_transform.basis.x.normalized()
				var kick_vel = kick_dir_x * kick_speed_x + Vector3(0, kick_speed_y, 0)
				clamped_log.linear_velocity = kick_vel
				clamped_log.sleeping = false
				
				print("[HEADRIG CARRIAGE] Slab kicked with velocity: ", kick_vel)
				clamped_log = null
				
			timer = pause_at_ends
			current_state = State.RETURNING
			
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
			# Only clamp logs that are free
			if not body.freeze:
				return body
	return null

func _get_knees_target_x() -> float:
	if clamped_log == null or not is_instance_valid(clamped_log):
		return -0.25
	var cut_index = cuts_on_current_face + 1 # Next cut on the current face (1-indexed)
	var cut_z = 0.245 - cut_index * 0.05
	
	# The saw blade is located at carriage local X = 0.4215 (global Z = 6.13).
	# The log center is at: X_log_center = knees_assembly.position.x + 0.175 + log_radius.
	# The cut plane (log local Z = cut_z) aligns with carriage local X_cut = X_log_center + cut_z.
	# We want X_cut = 0.4215, which means:
	# knees_assembly.position.x + 0.175 + log_radius + cut_z = 0.4215
	# Solve for target knees_assembly.position.x:
	var log_radius = clamped_log.get_current_radius() if clamped_log.has_method("get_current_radius") else 0.245
	return 0.4215 - 0.175 - log_radius - cut_z

func _should_flip_log_at_home() -> bool:
	if clamped_log == null or not is_instance_valid(clamped_log):
		return false
	if has_flipped_log:
		return false
	if cuts_before_flip <= 0:
		return false
	if cuts_on_current_face < cuts_before_flip:
		return false
	if not ("board_count" in clamped_log) or clamped_log.board_count <= 0:
		return false
	return true

func _get_log_relative_basis() -> Basis:
	var log_scale_z = clamped_log.scale.z if clamped_log != null and is_instance_valid(clamped_log) else 1.0
	var base_basis := Basis(Vector3.UP, PI / 2.0)
	var roll_basis := Basis(Vector3.RIGHT, log_roll_angle)
	return (base_basis * roll_basis).scaled(Vector3(1.0, 1.0, log_scale_z))

func _update_clamped_log_transform() -> void:
	if clamped_log == null or not is_instance_valid(clamped_log):
		return
	
	var log_radius = clamped_log.get_current_radius()
	log_relative_transform.origin.x = 0.175 + log_radius
	log_relative_transform.origin.y = 0.15 + log_radius
	
	log_relative_transform.basis = _get_log_relative_basis()
	
	if knees_assembly != null:
		clamped_log.global_transform = knees_assembly.global_transform * log_relative_transform
	else:
		clamped_log.global_transform = global_transform * log_relative_transform
