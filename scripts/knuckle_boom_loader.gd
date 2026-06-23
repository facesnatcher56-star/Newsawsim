extends Node3D

## knuckle_boom_loader.gd
## Implements an automated hydraulic knuckle boom log loader.
## Detects when the Debarker deck conveyor is empty, spawns a log in the bunk,
## and loads it onto the conveyor automatically using joint rotations and state machine.

enum State {
	IDLE,               # Waiting for log to clear deck, spawns log in bunk
	SWING_TO_BUNK,      # Swing booms over the bunk
	LOWER_TO_LOG,       # Lower grapple to pickup height
	GRAB_LOG,           # Close grapple and lock log
	LIFT_LOG,           # Lift log clear of bunk
	SWING_TO_CONVEYOR,  # Swing over to the conveyor
	LOWER_TO_CONVEYOR,  # Lower log onto the conveyor deck
	RELEASE_LOG,        # Open grapple and release log
	RETRACT_BOOM        # Raise empty boom back up
}

@export var swing_speed: float = 0.6
@export var boom_speed: float = 0.4
@export var claw_speed: float = 1.5
@export var enabled: bool = true

@export var main_boom_swing_angle: float = -0.244
@export var main_boom_pickup_angle: float = -1.117
@export var main_boom_drop_angle: float = -0.716

@export var outer_boom_swing_angle: float = -1.134
@export var outer_boom_pickup_angle: float = -1.501
@export var outer_boom_drop_angle: float = -1.030

@export var claw_open_angle: float = -0.8
@export var claw_closed_angle: float = -0.20

var current_state: State = State.IDLE
var timer: float = 0.0

# Node references
@onready var turret: Node3D = $Turret
@onready var main_boom_pivot: Node3D = $Turret/MainBoomPivot
@onready var outer_boom_pivot: Node3D = $Turret/MainBoomPivot/OuterBoomPivot
@onready var grapple_pivot: Node3D = $Turret/MainBoomPivot/OuterBoomPivot/GrapplePivot
@onready var claw_left_pivot: Node3D = $Turret/MainBoomPivot/OuterBoomPivot/GrapplePivot/ClawLeftPivot
@onready var claw_right_pivot: Node3D = $Turret/MainBoomPivot/OuterBoomPivot/GrapplePivot/ClawRightPivot
@onready var grapple_area: Area3D = $Turret/MainBoomPivot/OuterBoomPivot/GrapplePivot/GrappleArea

@onready var hydraulic_main_base: Node3D = $Turret/HydraulicMainBase
@onready var hydraulic_main_rod: Node3D = $Turret/MainBoomPivot/HydraulicMainRod
@onready var hydraulic_outer_base: Node3D = $Turret/MainBoomPivot/HydraulicOuterBase
@onready var hydraulic_outer_rod: Node3D = $Turret/MainBoomPivot/OuterBoomPivot/HydraulicOuterRod

@onready var conveyor_zone: Area3D = $ConveyorIntakeZone
@onready var bunk_zone: Area3D = $BunkZone

var clamped_log: RigidBody3D = null
var log_relative_transform: Transform3D
var grab_start_relative_transform: Transform3D
var grab_target_relative_transform: Transform3D
var grapple_swivel_yaw: float = 0.0

# Dynamic turret angles computed at ready
var bunk_turret_angle: float = PI
var conveyor_turret_angle: float = 0.0

var actual_mb_drop_angle: float = 0.0
var actual_ob_drop_angle: float = 0.0
var has_set_actual_drop_angles: bool = false

func _ready() -> void:
	
	# Dynamically calculate turret rotation angles to face the bunk and conveyor zones
	var rel_bunk = bunk_zone.global_position - global_position
	bunk_turret_angle = atan2(-rel_bunk.z, rel_bunk.x)
	
	var rel_conveyor = conveyor_zone.global_position - global_position
	conveyor_turret_angle = atan2(-rel_conveyor.z, rel_conveyor.x)
	
	
	# Start with boom retracted and grapple open
	_set_joints(bunk_turret_angle, main_boom_swing_angle, outer_boom_swing_angle, claw_open_angle)

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var target_turret_y: float = bunk_turret_angle
	var target_mb_z: float = main_boom_swing_angle
	var target_ob_z: float = outer_boom_swing_angle
	var target_claw: float = claw_open_angle
	
	# Keep track of clamped log transform if holding one
	if clamped_log != null:
		if is_instance_valid(clamped_log):
			clamped_log.global_transform = grapple_area.global_transform * log_relative_transform
		else:
			clamped_log = null
			current_state = State.RETRACT_BOOM
			
	# Swivel grapple to align log straight across conveyor during transport
	match current_state:
		State.LIFT_LOG, State.SWING_TO_CONVEYOR, State.LOWER_TO_CONVEYOR, State.RELEASE_LOG:
			grapple_swivel_yaw = rotate_toward(grapple_swivel_yaw, 0.0, 1.5 * delta)
		State.GRAB_LOG:
			if clamped_log != null and is_instance_valid(clamped_log):
				# Lock to the log's actual orientation while grabbing
				grapple_swivel_yaw = clamped_log.global_rotation.y
		_:
			# Default alignment for bunk
			grapple_swivel_yaw = rotate_toward(grapple_swivel_yaw, 0.0, 1.5 * delta)
			

	match current_state:
		State.IDLE:
			target_turret_y = bunk_turret_angle
			target_mb_z = main_boom_swing_angle
			target_ob_z = outer_boom_swing_angle
			target_claw = claw_open_angle
			has_set_actual_drop_angles = false
			
			# Check if conveyor intake is empty and not blocked
			var intake_ready := not _is_log_in_area(conveyor_zone)
			if intake_ready:
				var intake_node = conveyor_zone.get_parent()
				if intake_node and intake_node.has_method("is_full") and intake_node.is_full():
					intake_ready = false
				elif intake_node and intake_node.get("speed") == 0.0:
					intake_ready = false

			if intake_ready:
				# Check if log bunk is empty
				if not _is_log_in_area(bunk_zone) and not _has_active_log():
					_spawn_new_log()
				else:
					# Log is in bunk, conveyor is empty -> Start load cycle!
					if _is_log_in_area(bunk_zone):
						current_state = State.SWING_TO_BUNK
					
		State.SWING_TO_BUNK:
			target_turret_y = bunk_turret_angle
			target_mb_z = main_boom_swing_angle
			target_ob_z = outer_boom_swing_angle
			target_claw = claw_open_angle
			
			if _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				current_state = State.LOWER_TO_LOG
				
		State.LOWER_TO_LOG:
			target_turret_y = bunk_turret_angle
			target_mb_z = main_boom_pickup_angle
			target_ob_z = outer_boom_pickup_angle
			target_claw = claw_open_angle
			
			if _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				current_state = State.GRAB_LOG
				timer = 0.6
				_start_grab_log()
				
		State.GRAB_LOG:
			target_turret_y = bunk_turret_angle
			target_mb_z = main_boom_pickup_angle
			target_ob_z = outer_boom_pickup_angle
			target_claw = claw_closed_angle
			
			timer -= delta
			if clamped_log != null:
				var t = 1.0 - (timer / 0.6)
				t = clamp(t, 0.0, 1.0)
				log_relative_transform = grab_start_relative_transform.interpolate_with(grab_target_relative_transform, t)
				
			if timer <= 0.0:
				if clamped_log != null:
					log_relative_transform = grab_target_relative_transform
					current_state = State.LIFT_LOG
				else:
					current_state = State.RETRACT_BOOM
				
		State.LIFT_LOG:
			target_turret_y = bunk_turret_angle
			target_mb_z = main_boom_swing_angle
			target_ob_z = outer_boom_swing_angle
			target_claw = claw_closed_angle
			
			if _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				current_state = State.SWING_TO_CONVEYOR
				
		State.SWING_TO_CONVEYOR:
			target_turret_y = conveyor_turret_angle
			target_mb_z = main_boom_swing_angle
			target_ob_z = outer_boom_swing_angle
			target_claw = claw_closed_angle
			
			if _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				current_state = State.LOWER_TO_CONVEYOR
				
		State.LOWER_TO_CONVEYOR:
			target_turret_y = conveyor_turret_angle
			target_mb_z = main_boom_drop_angle
			target_ob_z = outer_boom_drop_angle
			target_claw = claw_closed_angle
			
			var reached_conveyor = false
			if clamped_log != null and is_instance_valid(clamped_log):
				var deck = null
				var bodies = conveyor_zone.get_overlapping_bodies()
				for body in bodies:
					if body.name.contains("Deck") or body.name.contains("Conveyor") or body is StaticBody3D:
						deck = body
						break
				if deck == null:
					# Fallback: search parents
					var parent = get_parent()
					if parent:
						deck = parent.find_child("OppositeChainDeckTest", true, false)
						if deck == null:
							deck = parent.find_child("ChainLogDeck", true, false)
				if deck != null:
					var log_radius = 0.27
					var col_shape = clamped_log.get_node_or_null("CollisionShape3D")
					if col_shape and col_shape.shape is CapsuleShape3D:
						log_radius = col_shape.shape.radius
					
					var landing_y = deck.global_position.y + 1.15 + log_radius
					if clamped_log.global_position.y <= landing_y:
						reached_conveyor = true
						actual_mb_drop_angle = main_boom_pivot.rotation.z
						actual_ob_drop_angle = outer_boom_pivot.rotation.z
						has_set_actual_drop_angles = true
			
			if reached_conveyor or _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				if not has_set_actual_drop_angles:
					actual_mb_drop_angle = main_boom_pivot.rotation.z
					actual_ob_drop_angle = outer_boom_pivot.rotation.z
					has_set_actual_drop_angles = true
				current_state = State.RELEASE_LOG
				timer = 0.6
				
		State.RELEASE_LOG:
			target_turret_y = conveyor_turret_angle
			target_mb_z = actual_mb_drop_angle if has_set_actual_drop_angles else main_boom_drop_angle
			target_ob_z = actual_ob_drop_angle if has_set_actual_drop_angles else outer_boom_drop_angle
			target_claw = claw_open_angle
			
			timer -= delta
			if timer <= 0.0:
				_release_log()
				current_state = State.RETRACT_BOOM
				
		State.RETRACT_BOOM:
			target_turret_y = conveyor_turret_angle
			target_mb_z = main_boom_swing_angle
			target_ob_z = outer_boom_swing_angle
			target_claw = claw_open_angle
			
			if _joints_reached(target_turret_y, target_mb_z, target_ob_z, target_claw):
				current_state = State.IDLE
				
	_animate_joints(target_turret_y, target_mb_z, target_ob_z, target_claw, delta)
	
	if grapple_pivot != null:
		grapple_pivot.global_rotation = Vector3(0.0, grapple_swivel_yaw, 0.0)
		
	_update_hydraulics()

func _set_joints(tur_y: float, mb_z: float, ob_z: float, claw: float) -> void:
	if turret != null:
		turret.rotation.y = tur_y
	if main_boom_pivot != null:
		main_boom_pivot.rotation.z = mb_z
	if outer_boom_pivot != null:
		outer_boom_pivot.rotation.z = ob_z
	if claw_left_pivot != null:
		claw_left_pivot.rotation.x = claw
	if claw_right_pivot != null:
		claw_right_pivot.rotation.x = -claw
		
	if grapple_pivot != null:
		grapple_pivot.global_rotation = Vector3(0.0, grapple_swivel_yaw, 0.0)
		
	_update_hydraulics()

func _animate_joints(tur_y: float, mb_z: float, ob_z: float, claw: float, delta: float) -> void:
	if turret != null:
		turret.rotation.y = rotate_toward(turret.rotation.y, turret.rotation.y + angle_difference(turret.rotation.y, tur_y), swing_speed * delta)
	if main_boom_pivot != null:
		main_boom_pivot.rotation.z = move_toward(main_boom_pivot.rotation.z, mb_z, boom_speed * delta)
	if outer_boom_pivot != null:
		outer_boom_pivot.rotation.z = move_toward(outer_boom_pivot.rotation.z, ob_z, boom_speed * delta)
	if claw_left_pivot != null:
		claw_left_pivot.rotation.x = move_toward(claw_left_pivot.rotation.x, claw, claw_speed * delta)
	if claw_right_pivot != null:
		claw_right_pivot.rotation.x = move_toward(claw_right_pivot.rotation.x, -claw, claw_speed * delta)

func _joints_reached(tur_y: float, mb_z: float, ob_z: float, claw: float) -> bool:
	var t_ok = abs(angle_difference(turret.rotation.y, tur_y)) < 0.02 if turret != null else true
	var mb_ok = abs(angle_difference(main_boom_pivot.rotation.z, mb_z)) < 0.02 if main_boom_pivot != null else true
	var ob_ok = abs(angle_difference(outer_boom_pivot.rotation.z, ob_z)) < 0.02 if outer_boom_pivot != null else true
	var claw_ok = abs(angle_difference(claw_left_pivot.rotation.x, claw)) < 0.02 if claw_left_pivot != null else true
	return t_ok and mb_ok and ob_ok and claw_ok

func _is_log_in_area(area: Area3D) -> bool:
	if area == null:
		return false
	var bodies = area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D and body.is_in_group("logs"):
			return true
			
	# Distance fallback (1.2m range)
	var logs = get_tree().get_nodes_in_group("logs")
	for l in logs:
		if l is RigidBody3D:
			var dist = area.global_position.distance_to(l.global_position)
			if dist < 1.2:
				return true
	return false

func _has_active_log() -> bool:
	if is_instance_valid(clamped_log):
		return true
	if _is_log_in_area(bunk_zone):
		return true
	if _is_log_in_area(conveyor_zone):
		return true
	return false

func _spawn_new_log() -> void:
	if _has_active_log():
		return
	var log_scene = load("res://Prefabs/LogPrefab.tscn")
	if log_scene:
		var log_instance = log_scene.instantiate()
		log_instance.freeze = true # Spawn frozen to guarantee stability and prevent rolling
		get_parent().add_child(log_instance)
		log_instance.global_position = bunk_zone.global_position
		log_instance.global_rotation = Vector3(0.0, 0.0, 0.0)
		log_instance.set_meta("boom_log", true)

func _start_grab_log() -> void:
	if grapple_area == null:
		return
	
	# Try Area3D first
	var target_log = null
	var bodies = grapple_area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D and body.is_in_group("logs"):
			target_log = body
			break
			
	# Fallback to proximity search if Area3D missed
	if target_log == null:
		var logs = get_tree().get_nodes_in_group("logs")
		var min_dist = 0.6
		for l in logs:
			if l is RigidBody3D:
				var dist = grapple_area.global_position.distance_to(l.global_position)
				if dist < min_dist:
					min_dist = dist
					target_log = l
					
	if target_log != null:
		clamped_log = target_log
		clamped_log.freeze = true
		
		# Record starting relative transform
		grab_start_relative_transform = grapple_area.global_transform.affine_inverse() * clamped_log.global_transform
		grab_target_relative_transform = grab_start_relative_transform
		
		log_relative_transform = grab_start_relative_transform
	else:
		clamped_log = null

func _release_log() -> void:
	if clamped_log != null:
		if is_instance_valid(clamped_log):
			clamped_log.freeze = false
			clamped_log.linear_velocity = Vector3.ZERO
		clamped_log = null

func _update_hydraulics() -> void:
	if turret == null:
		return
		
	var up_vector = turret.global_transform.basis.z
	
	if hydraulic_main_base != null and hydraulic_main_rod != null:
		hydraulic_main_base.look_at(hydraulic_main_rod.global_position, up_vector)
		hydraulic_main_rod.look_at(hydraulic_main_base.global_position, up_vector)
		
	if hydraulic_outer_base != null and hydraulic_outer_rod != null:
		hydraulic_outer_base.look_at(hydraulic_outer_rod.global_position, up_vector)
		hydraulic_outer_rod.look_at(hydraulic_outer_base.global_position, up_vector)
