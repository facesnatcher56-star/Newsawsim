extends Area3D

@export var kick_direction: Vector3 = Vector3(1, 0, 0) # Local direction to push (X is sideways)
@export var kick_speed: float = 1.0
@export var kick_damping: float = 5.0 # How aggressively to reach target velocity

var original_speed: float = -1.0
var is_kicking: bool = false

func _physics_process(delta: float) -> void:
	var bodies = get_overlapping_bodies()
	
	var rigid_bodies = []
	for body in bodies:
		if body is RigidBody3D:
			rigid_bodies.append(body)
			
	var log_in_zone = rigid_bodies.size() > 0
	var parent = get_parent()
	
	if log_in_zone:
		if not is_kicking:
			print("[Kicker] Log entered zone. Stopping conveyor.")
			if parent and "speed" in parent:
				if original_speed < 0:
					original_speed = parent.speed
					print("[Kicker] Saved original speed: ", original_speed)
				parent.speed = 0.0
			is_kicking = true
		
		var global_kick_dir = global_transform.basis * kick_direction.normalized()
		var target_kick_vel = global_kick_dir * kick_speed
		
		if Engine.get_frames_drawn() % 30 == 0:
			print("[Kicker] Global Kick Dir: ", global_kick_dir, " Target Vel: ", target_kick_vel)
		
		for log_body in rigid_bodies:
			# Project current velocity onto kick direction
			var current_kick_vel = global_kick_dir * log_body.linear_velocity.dot(global_kick_dir)
			var other_vel = log_body.linear_velocity - current_kick_vel
			
			var new_kick_vel = current_kick_vel.lerp(target_kick_vel, kick_damping * delta)
			var new_other_vel = other_vel.lerp(Vector3.ZERO, kick_damping * delta)
			
			log_body.linear_velocity = new_kick_vel + new_other_vel
			
			if Engine.get_frames_drawn() % 30 == 0:
				print("[Kicker] Log Vel: ", log_body.linear_velocity, " Speed: ", log_body.linear_velocity.length())
	else:
		if is_kicking:
			print("[Kicker] Zone cleared. Resuming conveyor.")
			if parent and "speed" in parent and original_speed >= 0:
				parent.speed = original_speed
				print("[Kicker] Restored speed: ", original_speed)
			original_speed = -1.0
			is_kicking = false
