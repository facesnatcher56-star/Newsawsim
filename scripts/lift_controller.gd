extends Node

## lift_controller.gd
## Manages the log lifts based on log positions to ensure handoff.
## Lifts are STOPPED by default and only START when a log is ready to be lifted.

# Pickup Zone: The bottom of Incline 1 where the log meets the lift cradle
@export var pickup_z_min: float = 2.6
@export var pickup_z_max: float = 3.2

# Active Zone: The entire travel length of the lift to ensure it finishes the job
@export var travel_z_max: float = 4.5

@export var start_delay: float = 2.0

var delay_timer: float = 0.0
var delay_completed: bool = false

func _physics_process(delta: float) -> void:
	var logs = get_tree().get_nodes_in_group("logs")
	var lifts = get_tree().get_nodes_in_group("log_lifts")
	
	if lifts.size() == 0:
		return
		
	var log_in_pickup_zone = false
	var log_in_travel_zone = false
	
	for log_body in logs:
		if log_body is RigidBody3D:
			var pos = log_body.global_position
			
			# Check if log is in pickup zone (at the bottom)
			if pos.z > pickup_z_min and pos.z < pickup_z_max:
				if pos.y > 0.1 and pos.y < 2.5:
					log_in_pickup_zone = true
					if log_body.sleeping:
						log_body.sleeping = false
			
			# Check if log is in travel zone (climbing)
			elif pos.z >= pickup_z_max and pos.z < travel_z_max:
				if pos.y > 0.1 and pos.y < 2.5:
					log_in_travel_zone = true
					if log_body.sleeping:
						log_body.sleeping = false

	var log_is_present = log_in_pickup_zone or log_in_travel_zone
	var run_lifts = false

	if log_is_present:
		if log_in_pickup_zone and not log_in_travel_zone:
			# Log is at the bottom, and nothing is currently climbing
			if not delay_completed:
				if delay_timer <= 0.0:
					delay_timer = start_delay
				
				delay_timer -= delta
				if delay_timer <= 0.0:
					delay_completed = true
					run_lifts = true
				else:
					run_lifts = false
			else:
				run_lifts = true
		else:
			# Log is climbing or we have logs in both zones
			run_lifts = true
	else:
		# No logs in system, reset delay state
		if delay_completed or delay_timer > 0.0:
		delay_timer = 0.0
		delay_completed = false
		run_lifts = false
	
	# Update all lifts: Run ONLY if run_lifts is true
	for lift in lifts:
		# --- DEEP PHYSICS DIAGNOSTIC ---
		if Engine.get_frames_drawn() % 30 == 0:
			for log_body in logs:
				if log_body is RigidBody3D:
					var dist = lift.global_position.distance_to(log_body.global_position)
					if dist < 1.0:
						
						# Check if their collision layers/masks actually match
						if (lift.collision_layer & log_body.collision_mask) == 0:
		# --- END DIAGNOSTIC ---
		
		if lift.is_paused != (!run_lifts):
			if run_lifts:
			else:
		
		lift.is_paused = !run_lifts
