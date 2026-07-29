extends Area3D

func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is RigidBody3D and body.is_in_group("logs"):
			body.angular_velocity = Vector3.ZERO
