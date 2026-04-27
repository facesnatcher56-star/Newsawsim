extends StaticBody3D

@export var speed: float = 2.0:
	set(v):
		speed = v
		constant_linear_velocity = direction.normalized() * speed

@export var direction: Vector3 = Vector3.FORWARD:
	set(v):
		direction = v
		constant_linear_velocity = direction.normalized() * speed

func _ready() -> void:
	constant_linear_velocity = direction.normalized() * speed
