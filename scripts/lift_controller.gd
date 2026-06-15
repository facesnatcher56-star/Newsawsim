extends Node

## lift_controller.gd
## Manages the log lifts based on log positions to ensure handoff.
## Lifts are STOPPED by default and only START when a log is ready to be lifted.

# Pickup Zone: The bottom of Incline 1 where the log meets the lift cradle
@export var pickup_z_min: float = 2.6
@export var pickup_z_max: float = 3.2

# Active Zone: The entire travel length of the lift to ensure it finishes the job
@export var travel_z_max: float = 4.5

func _physics_process(_delta: float) -> void:
	var logs = get_tree().get_nodes_in_group("logs")
	var lifts = get_tree().get_nodes_in_group("log_lifts")
	
	if lifts.size() == 0:
		return
		
	var log_is_ready_or_moving = false
	
	for log_body in logs:
		if log_body is RigidBody3D:
			var pos = log_body.global_position
			
			# Detect if a log is at the bottom (ready) or being carried (up to release point)
			if pos.z > pickup_z_min and pos.z < travel_z_max:
				# Also check height to ensure it's on the incline/lift path
				if pos.y > 0.1 and pos.y < 2.5:
					log_is_ready_or_moving = true
					if log_body.sleeping:
						print("[LIFT CONTROLLER] Waking up sleeping log: ", log_body.name)
						log_body.sleeping = false
	
	# Update all lifts: Run ONLY if a log is in the system
	for lift in lifts:
		# --- DEEP PHYSICS DIAGNOSTIC ---
		if Engine.get_frames_drawn() % 30 == 0:
			for log_body in logs:
				if log_body is RigidBody3D:
					var dist = lift.global_position.distance_to(log_body.global_position)
					if dist < 1.0:
						print("[PHYSICS DEEP TRACE] %s <-> Log Dist: %.3f" % [lift.name, dist])
						print("  Lift Global Pos: %v | Scale: %v" % [lift.global_position, lift.global_transform.basis.get_scale()])
						print("  Log Global Pos: %v | Sleep: %s" % [log_body.global_position, log_body.sleeping])
						
						# Check if their collision layers/masks actually match
						print("  Lift Layer: %d, Mask: %d | Log Layer: %d, Mask: %d" % [lift.collision_layer, lift.collision_mask, log_body.collision_layer, log_body.collision_mask])
						if (lift.collision_layer & log_body.collision_mask) == 0:
							print("  !!! ALERT: Layer/Mask mismatch! Lift Layer: %d vs Log Mask: %d" % [lift.collision_layer, log_body.collision_mask])
		# --- END DIAGNOSTIC ---
		
		if lift.is_paused != (!log_is_ready_or_moving):
			if log_is_ready_or_moving:
				print("[LIFT CONTROLLER] Log detected. Starting lifts.")
			else:
				print("[LIFT CONTROLLER] No log in system. Stopping lifts.")
		
		lift.is_paused = !log_is_ready_or_moving
