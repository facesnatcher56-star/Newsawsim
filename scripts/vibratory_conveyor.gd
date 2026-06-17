extends StaticBody3D

@export var speed: float = 1.2
@export var direction: Vector3 = Vector3(0.989, 0.148, 0) # Slanted direction (matching ~8.5 degrees incline)
@export var vibration_frequency: float = 45.0 # Hz
@export var vibration_amplitude: float = 0.012 # displacement

@onready var visuals: Node3D = $Visuals

var time: float = 0.0
var original_visuals_pos: Vector3

func _ready() -> void:
	# constant_linear_velocity is in global coordinates in Godot 4
	constant_linear_velocity = direction.normalized() * speed
	if visuals:
		original_visuals_pos = visuals.position

func _process(delta: float) -> void:
	time += delta
	if visuals:
		# Rapid diagonal/shaking motion typical of vibrating conveyors
		var offset = Vector3(
			sin(time * vibration_frequency) * vibration_amplitude,
			abs(sin(time * vibration_frequency * 1.3)) * vibration_amplitude * 0.4,
			cos(time * vibration_frequency * 0.7) * vibration_amplitude * 0.2
		)
		visuals.position = original_visuals_pos + offset
