extends StaticBody3D

## A flat solid box that carries whatever rests on it, like a conveyor belt that never moves.
## Resize or move it with its CollisionShape3D child. Everything here can be changed in the
## Inspector while you play.

@export_group("Switch")
## Turns the surface on or off. When switched off it slows to a stop (see "Slow Down Rate").
@export var running: bool = true

@export_group("Speed")
## How fast the surface carries things once it is up to speed, in metres per second.
## 0.2 is a slow crawl, 1 is a brisk walk. Bigger numbers = faster.
@export_range(0.0, 5.0, 0.05, "or_greater") var carry_speed: float = 0.2
## How quickly it speeds up when it starts, in metres per second gained every second.
## Small number = gentle start. Big number = it jumps up to speed almost instantly.
@export_range(0.05, 20.0, 0.05, "or_greater") var speed_up_rate: float = 1.0
## How quickly it slows down when switched off, in metres per second lost every second.
## Small number = it coasts to a stop. Big number = it stops quickly.
@export_range(0.05, 20.0, 0.05, "or_greater") var slow_down_rate: float = 2.0

@export_group("Direction")
## Which way it carries things, in the mill's own directions (not the box's): X = east (the way the logs
## travel along the debarker), Z = across the trough, Y = leave at 0.
## (1, 0, 0) carries toward +X, (-1, 0, 0) carries backwards. You only need the direction here, the speed is set by "Carry Speed".
@export var direction: Vector3 = Vector3(1, 0, 0)

@export_group("Grip")
## How strongly it grips what is on it. 0 = like ice, things slide over it and are not carried.
## Higher = things are held and dragged along firmly.
@export_range(0.0, 5.0, 0.05, "or_greater") var grip: float = 1.0:
	set(value):
		grip = value
		_apply_grip()

## The speed it is moving at right now (it eases between 0 and Carry Speed).
var current_speed: float = 0.0

var _material := PhysicsMaterial.new()


func _ready() -> void:
	_apply_grip()


func _physics_process(delta: float) -> void:
	var target: float = carry_speed if running else 0.0
	var rate: float = speed_up_rate if target > current_speed else slow_down_rate
	current_speed = move_toward(current_speed, target, rate * delta)
	if direction.length() < 0.0001:
		constant_linear_velocity = Vector3.ZERO
	else:
		constant_linear_velocity = direction.normalized() * current_speed


func _apply_grip() -> void:
	_material.friction = grip
	_material.rough = true
	_material.bounce = 0.0
	physics_material_override = _material
