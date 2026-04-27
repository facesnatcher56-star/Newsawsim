extends RigidBody3D

@export var log_interval: float = 1.0
var time_passed: float = 0.0

func _physics_process(delta: float) -> void:
	time_passed += delta
	if time_passed >= log_interval:
		time_passed = 0.0
		var current_speed = linear_velocity.length()
		print("LOG TRACER | Pos: ", global_position, " | Velocity: ", linear_velocity, " | Speed: ", current_speed)
