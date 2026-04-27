extends RigidBody3D

@export var speed_threshold: float = 0.1
@export var report_interval: float = 0.5
var last_report_time: float = 0.0

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 10
	print("--- LOG TRACER ACTIVE ---")
	print("Monitoring contacts for: ", name)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var current_speed = state.linear_velocity.length()
	var time = Time.get_ticks_msec() / 1000.0
	
	if time - last_report_time < report_interval:
		return
		
	var contact_count = state.get_contact_count()
	
	if contact_count > 0:
		last_report_time = time
		print("\n[LOG TRACER] Speed: %.3f | Contacts: %d | Angular: %v" % [current_speed, contact_count, state.angular_velocity])
		print("  State: Sleep=%s | Freeze=%s | Damp[L:%.2f, A:%.2f]" % [
			sleeping, freeze, linear_damp, angular_damp
		])
		var lin_locks = ""
		if axis_lock_linear_x: lin_locks += "X"
		if axis_lock_linear_y: lin_locks += "Y"
		if axis_lock_linear_z: lin_locks += "Z"
		var ang_locks = ""
		if axis_lock_angular_x: ang_locks += "X"
		if axis_lock_angular_y: ang_locks += "Y"
		if axis_lock_angular_z: ang_locks += "Z"
		
		print("  Locks: Lin=[%s] | Ang=[%s]" % [lin_locks if lin_locks != "" else "None", ang_locks if ang_locks != "" else "None"])
		
		for i in range(contact_count):
			var collider = state.get_contact_collider_object(i)
			var collider_name = "Unknown"
			if collider:
				collider_name = collider.name
				if collider is Node:
					# Get full path to be sure which object it is
					collider_name = String(collider.get_path())
			
			var local_pos = state.get_contact_local_position(i)
			var normal = state.get_contact_local_normal(i) # Normal pointing INTO the log
			var collider_pos = state.get_contact_collider_position(i)
			
			print("  #%d hit [%s] at %v" % [i, collider_name, collider_pos])
			print("     Normal: %v (Points into log)" % [normal])
			
			# Check if normal is opposing velocity
			if current_speed > 0.01:
				var dot = state.linear_velocity.normalized().dot(normal)
				if dot < -0.7: # Facing each other
					print("     !!! HIGH OPPOSING FORCE FROM THIS COLLISION !!!")

	elif current_speed < speed_threshold and state.linear_velocity.length() > 0.001:
		# If it's slow but not stopped, and no contacts? That's weird too.
		last_report_time = time
		print("[LOG TRACER] WARNING: Low speed (%.3f) but NO reported contacts." % current_speed)

func _physics_process(_delta: float) -> void:
	if sleeping:
		var time = Time.get_ticks_msec() / 1000.0
		if time - last_report_time >= report_interval:
			last_report_time = time
			print("[LOG TRACER] BODY IS SLEEPING at ", global_position)

