extends AnimatableBody3D

## headrig_carriage.gd
## Moves the carriage back and forth along a defined axis and distance.
## Uses AnimatableBody3D to correctly carry RigidBody3D logs.

enum State {
	STOPPED,
	MOVING_FORWARD,
	WAITING_END,
	RETURNING,
	WAITING_START
}

@export var speed: float = 2.0
@export var travel_distance: float = 12.0
@export var auto_cycle: bool = true
@export var pause_at_ends: float = 2.0
@export var travel_axis: Vector3 = Vector3(0, 0, 1) # Axis in local space

var current_state: State = State.STOPPED
var timer: float = 0.0
var start_pos: Vector3
var target_pos: Vector3
var current_progress: float = 0.0 # Normalized position [0.0, 1.0]

func _ready() -> void:
	start_pos = position
	target_pos = start_pos + travel_axis.normalized() * travel_distance
	if auto_cycle:
		current_state = State.MOVING_FORWARD
	print("[HEADRIG CARRIAGE] Initialized at: ", start_pos, " traveling to: ", target_pos)

func _physics_process(delta: float) -> void:
	match current_state:
		State.STOPPED:
			pass
			
		State.MOVING_FORWARD:
			current_progress += (speed / travel_distance) * delta
			if current_progress >= 1.0:
				current_progress = 1.0
				timer = pause_at_ends
				current_state = State.WAITING_END
				print("[HEADRIG CARRIAGE] Reached end. Pausing.")
			position = start_pos.lerp(target_pos, current_progress)
			# Force physics server to register transform change to calculate carrying velocity
			global_transform = global_transform
			
		State.WAITING_END:
			timer -= delta
			if timer <= 0.0:
				current_state = State.RETURNING
				print("[HEADRIG CARRIAGE] Returning.")
				
		State.RETURNING:
			current_progress -= (speed / travel_distance) * delta
			if current_progress <= 0.0:
				current_progress = 0.0
				timer = pause_at_ends
				current_state = State.WAITING_START
				print("[HEADRIG CARRIAGE] Returned to start. Pausing.")
			position = start_pos.lerp(target_pos, current_progress)
			# Force physics server to register transform change to calculate carrying velocity
			global_transform = global_transform
			
		State.WAITING_START:
			timer -= delta
			if timer <= 0.0:
				if auto_cycle:
					current_state = State.MOVING_FORWARD
					print("[HEADRIG CARRIAGE] Starting next cycle.")
				else:
					current_state = State.STOPPED

func start_feed() -> void:
	current_state = State.MOVING_FORWARD

func start_return() -> void:
	current_state = State.RETURNING

func stop_carriage() -> void:
	current_state = State.STOPPED
