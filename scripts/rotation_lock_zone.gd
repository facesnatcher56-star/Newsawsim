extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.axis_lock_angular_z = true

func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false
