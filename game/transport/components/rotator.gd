extends Node3D

@export var speed: float = 5.0
@export var axis: Vector3 = Vector3.FORWARD

func _process(delta: float) -> void:
	rotate(axis.normalized(), speed * delta)
