extends Area3D

@export var kick_direction: Vector3 = Vector3(0, 0, 1) # Pushes sideways (Z)
@export var kick_speed: float = 1.0

func _physics_process(delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is RigidBody3D:
			# Apply a lateral force to push the log through the gap
			# We use lerp to move toward the target velocity smoothly
			var target_z = kick_direction.normalized().z * kick_speed
			body.linear_velocity.z = lerp(body.linear_velocity.z, target_z, 5.0 * delta)
