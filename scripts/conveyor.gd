extends StaticBody3D

@export var speed: float = 2.0
@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	constant_linear_velocity = direction.normalized() * speed
