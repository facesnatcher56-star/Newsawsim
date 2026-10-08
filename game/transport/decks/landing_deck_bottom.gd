extends StaticBody3D

## The floor of the edger landing deck. It works like a conveyor belt that never moves:
## anything resting on it is carried along at the speed and direction set below.
## Everything here can be changed in the Inspector while you play.

@export_group("Switch")
## Turns the belt on or off. When switched off the belt slows to a stop
## (see "Slow Down Rate") instead of stopping instantly.
@export var running: bool = true

@export_group("Speed")
## How fast the belt carries a board once it is up to speed, in metres per second.
## 0.5 is a slow walking pace. Bigger numbers = faster belt.
@export_range(0.0, 5.0, 0.05, "or_greater") var carry_speed: float = 0.55
## How quickly the belt speeds up when it starts, in metres per second gained every second.
## Small number = gentle start. Big number = it jumps up to speed almost instantly.
@export_range(0.05, 20.0, 0.05, "or_greater") var speed_up_rate: float = 1.2
## How quickly the belt slows down when switched off, in metres per second lost every second.
## Small number = it coasts to a stop. Big number = it stops quickly.
@export_range(0.05, 20.0, 0.05, "or_greater") var slow_down_rate: float = 2.0

@export_group("Direction")
## Which way the belt carries the board, measured along the deck itself.
## Z (third number) = along the deck, toward the incline. (0, 0, 1) is the normal way, (0, 0, -1) runs it backwards.
## X (first number) = toward the board stop. Use a small value like 0.1 to also nudge boards gently toward the stop.
## Y (second number) = leave at 0.
## You only need the direction, not the strength: the speed is set by "Carry Speed".
@export var direction: Vector3 = Vector3(0, 0, 1)

@export_group("Grip")
## How strongly the belt grips the board. 0 = like ice, the board slides over it and is not carried.
## Low = the board can still be pushed across it. High = the board is dragged along firmly.
## Tip: you want it low enough that the edger can push a board across, but high enough to carry the board once it is all on the deck.
@export_range(0.0, 5.0, 0.05, "or_greater") var grip: float = 0.5:
	set(value):
		grip = value
		_apply_grip()

## The speed the belt is moving at right now (it eases between 0 and Carry Speed).
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
		constant_linear_velocity = global_basis * direction.normalized() * current_speed


func _apply_grip() -> void:
	_material.friction = grip
	_material.rough = true
	_material.bounce = 0.0
	physics_material_override = _material
