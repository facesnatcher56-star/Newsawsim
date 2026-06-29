@tool
class_name RollerBed3D
extends StaticBody3D

## Procedural roller bed for transporting rigid lumber.
## The bed is centered on its origin and extends along transport_direction.

@export_category("Layout")
@export_range(1, 100, 1, "or_greater") var roller_count: int = 10:
	set(value):
		roller_count = maxi(value, 1)
		_queue_rebuild()

## End-to-end roller width in meters.
@export_range(0.1, 20.0, 0.05, "or_greater") var roller_length: float = 2.4:
	set(value):
		roller_length = maxf(value, 0.1)
		_queue_rebuild()

## Outside roller diameter in meters.
@export_range(0.05, 2.0, 0.01, "or_greater") var roller_diameter: float = 0.18:
	set(value):
		roller_diameter = maxf(value, 0.05)
		_queue_rebuild()

## Center-to-center distance between adjacent rollers.
@export_range(0.05, 5.0, 0.01, "or_greater") var roller_spacing: float = 0.35:
	set(value):
		roller_spacing = maxf(value, 0.05)
		_queue_rebuild()

@export_category("Motion")
## Local-space direction in which lumber travels. The vertical component is ignored.
@export var transport_direction: Vector3 = Vector3.FORWARD:
	set(value):
		transport_direction = value
		_queue_rebuild()
		_update_motion()

@export_range(0.0, 20.0, 0.05, "or_greater") var speed: float = 2.0:
	set(value):
		speed = maxf(value, 0.0)
		_update_motion()

@export var enabled: bool = true:
	set(value):
		enabled = value
		_update_motion()

@export_category("Appearance")
@export var roller_color: Color = Color(0.35, 0.45, 0.38, 1.0):
	set(value):
		roller_color = value
		_queue_rebuild()

@export_range(8, 64, 1) var radial_segments: int = 24:
	set(value):
		radial_segments = clampi(value, 8, 64)
		_queue_rebuild()

@export_category("Flip Table")
@export var flip_table_present: bool = true:
	set(value):
		flip_table_present = value
		_queue_rebuild()

@export var flip_table_enabled: bool = false:
	set(value):
		if not flip_table_present:
			flip_table_enabled = false
		else:
			flip_table_enabled = value
		_update_flip_target()

@export var flip_pivot_on_right: bool = false:
	set(value):
		flip_pivot_on_right = value
		_queue_rebuild()

@export_range(0.0, 90.0, 0.5) var flip_max_angle: float = 45.0:
	set(value):
		flip_max_angle = value
		_update_flip_target()

@export var flip_hold_time: float = 1.5

@export_range(10.0, 360.0, 5.0) var flip_speed_deg: float = 90.0

@export_range(0.1, 20.0, 0.05, "or_greater") var plate_length: float = 2.4:
	set(value):
		plate_length = maxf(value, 0.1)
		_queue_rebuild()

@export_range(0.01, 0.20, 0.01) var plate_thickness: float = 0.03:
	set(value):
		plate_thickness = value
		_queue_rebuild()

@export_range(-0.5, 0.5, 0.01) var plate_y_offset: float = 0.0:
	set(value):
		plate_y_offset = value
		_queue_rebuild()

@export var plate_color: Color = Color(0.20, 0.22, 0.25, 1.0):
	set(value):
		plate_color = value
		_queue_rebuild()

@export_range(0.01, 1.0, 0.01) var plate_width: float = 0.18:
	set(value):
		plate_width = value
		_queue_rebuild()

@export_range(0.01, 0.5, 0.01) var connecting_bar_width: float = 0.08:
	set(value):
		connecting_bar_width = value
		_queue_rebuild()

@export_range(0.01, 0.2, 0.01) var connecting_bar_thickness: float = 0.03:
	set(value):
		connecting_bar_thickness = value
		_queue_rebuild()

@export_category("Stop Gate")
@export var stop_gate_present: bool = true:
	set(value):
		stop_gate_present = value
		_queue_rebuild()

@export_range(0.1, 20.0, 0.05, "or_greater") var stop_gate_length: float = 2.4:
	set(value):
		stop_gate_length = maxf(value, 0.1)
		_queue_rebuild()

@export var stop_gate_raised: bool = true:
	set(value):
		stop_gate_raised = value
		_update_stop_gate_target()

@export var auto_flip_on_stop: bool = true

@export_range(0.05, 3.0, 0.05) var board_pass_gate_delay: float = 0.45

@export_range(0.05, 1.0, 0.01) var stop_gate_height_offset: float = 0.15:
	set(value):
		stop_gate_height_offset = value
		_queue_rebuild()

@export_range(0.1, 5.0, 0.1) var stop_gate_speed: float = 1.0

@export_range(0.01, 0.20, 0.01) var stop_gate_thickness: float = 0.06:
	set(value):
		stop_gate_thickness = value
		_queue_rebuild()

@export var stop_gate_color: Color = Color(0.40, 0.10, 0.10, 1.0):
	set(value):
		stop_gate_color = value
		_queue_rebuild()

@export_category("Sweep Chain")
@export var sweep_chain_present: bool = false:
	set(value):
		sweep_chain_present = value
		_queue_rebuild()

@export_range(1.0, 20.0, 0.5) var sweep_speed: float = 6.0
@export_range(0.05, 0.5, 0.01) var lug_height: float = 0.15
@export_range(0.05, 0.5, 0.01) var lug_base_length: float = 0.12

## When true the sweep triggers automatically when a log/board enters the sensor area.
@export var auto_sweep: bool = true

## Moves the sweep trigger sensor along the bed relative to the last roller.
## Negative values move the sensor toward the entry end (sweep triggers sooner/earlier).
## Positive values move it past the end (sweep triggers later).
@export_range(-10.0, 2.0, 0.05, "or_less") var sweep_trigger_offset: float = 0.0:
	set(value):
		sweep_trigger_offset = value
		_queue_rebuild()

enum FlipState { FLAT, FLIPPING, HOLDING, RETRACTING }
var _flip_state: FlipState = FlipState.FLAT
var _flip_timer: float = 0.0

var _current_flip_angle_deg: float = 0.0
var _target_flip_angle_deg: float = 0.0

var _current_stop_gate_y: float = 0.0
var _target_stop_gate_y: float = 0.0

var _flip_table_node: AnimatableBody3D = null
var _flip_table_base_transform: Transform3D = Transform3D.IDENTITY
var _stop_gate_node: AnimatableBody3D = null
var _stop_gate_base_transform: Transform3D = Transform3D.IDENTITY
var _gate_board_bodies: Dictionary = {}
var _gate_stop_bodies: Dictionary = {}
var _gate_reopen_timer: float = 0.0

var _roller_visuals: Array[MeshInstance3D] = []
var _rebuild_queued: bool = false

var _sweep_lugs: Array[AnimatableBody3D] = []
var _sweep_lug_push_areas: Array[Area3D] = []
var _sweep_sprockets: Array[MeshInstance3D] = []
var _sweep_chain_nodes: Array[Node3D] = []
var _sweep_chain_gzipped: Array[float] = []
var _sweep_chain_slots: Array[float] = []
var _sweep_travel: float = 0.0
var _sweep_active: bool = false
var _sweep_sensor: Area3D = null


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		flip_table_enabled = false

func _physics_process(delta: float) -> void:
	# Re-evaluate this so rotating the whole bed also rotates its transport velocity.
	_update_motion()

	if Engine.is_editor_hint():
		return

	# 1. Flip Table state machine
	match _flip_state:
		FlipState.FLAT:
			_target_flip_angle_deg = 0.0
			if flip_table_enabled and flip_table_present:
				_flip_state = FlipState.FLIPPING
		
		FlipState.FLIPPING:
			_target_flip_angle_deg = flip_max_angle
			if not flip_table_enabled:
				_flip_state = FlipState.RETRACTING
			elif is_equal_approx(_current_flip_angle_deg, flip_max_angle):
				_flip_state = FlipState.HOLDING
				_flip_timer = flip_hold_time
		
		FlipState.HOLDING:
			_target_flip_angle_deg = flip_max_angle
			if not flip_table_enabled:
				_flip_state = FlipState.RETRACTING
			else:
				_flip_timer -= delta
				if _flip_timer <= 0.0:
					_flip_state = FlipState.RETRACTING
					flip_table_enabled = false # reset flag
		
		FlipState.RETRACTING:
			_target_flip_angle_deg = 0.0
			if flip_table_enabled:
				_flip_state = FlipState.FLIPPING
			elif is_equal_approx(_current_flip_angle_deg, 0.0):
				_flip_state = FlipState.FLAT

	# Interpolate flip angle
	if not is_equal_approx(_current_flip_angle_deg, _target_flip_angle_deg):
		_current_flip_angle_deg = move_toward(_current_flip_angle_deg, _target_flip_angle_deg, flip_speed_deg * delta)
		_apply_plate_rotations()

	# 2. Stop Gate interpolation
	if stop_gate_present and is_instance_valid(_stop_gate_node):
		_update_auto_stop_gate(delta)
		var radius: float = roller_diameter * 0.5
		var raised_y: float = radius + stop_gate_height_offset
		var retracted_y: float = -radius - 0.05
		_target_stop_gate_y = raised_y if stop_gate_raised else retracted_y

		if not is_equal_approx(_current_stop_gate_y, _target_stop_gate_y):
			_current_stop_gate_y = move_toward(_current_stop_gate_y, _target_stop_gate_y, stop_gate_speed * delta)
			_apply_stop_gate_position()

	# 3. Sweep Chain animation (lug bodies must move in _physics_process for sync_to_physics)
	if sweep_chain_present and _sweep_active and not _sweep_lugs.is_empty():
		_sweep_travel += sweep_speed * delta
		if _sweep_travel >= _sweep_loop_length():
			_sweep_travel = 0.0
			_sweep_active = false

		_update_sweep_visuals(_sweep_travel)
		_apply_sweep_push(delta)


func _process(delta: float) -> void:
	var radius: float = roller_diameter * 0.5
	if Engine.is_editor_hint():
		# In editor, immediately apply targets
		_target_flip_angle_deg = flip_max_angle if flip_table_enabled else 0.0
		_current_flip_angle_deg = _target_flip_angle_deg
		_apply_plate_rotations()
		
		if stop_gate_present:
			var raised_y: float = radius + stop_gate_height_offset
			var retracted_y: float = -radius - 0.05
			_target_stop_gate_y = raised_y if stop_gate_raised else retracted_y
			_current_stop_gate_y = _target_stop_gate_y
			_apply_stop_gate_position()
		return

	var is_flipping: bool = (_flip_state != FlipState.FLAT)
	if not enabled or is_zero_approx(speed) or is_flipping:
		return
	var angular_step: float = -(speed / radius) * delta
	for roller: MeshInstance3D in _roller_visuals:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, angular_step)


func _update_flip_target() -> void:
	_target_flip_angle_deg = flip_max_angle if (flip_table_enabled and flip_table_present) else 0.0
	if Engine.is_editor_hint():
		_current_flip_angle_deg = _target_flip_angle_deg
		_apply_plate_rotations()


func _update_stop_gate_target() -> void:
	var radius: float = roller_diameter * 0.5
	var raised_y: float = radius + stop_gate_height_offset
	var retracted_y: float = -radius - 0.05
	_target_stop_gate_y = raised_y if stop_gate_raised else retracted_y
	if Engine.is_editor_hint():
		_current_stop_gate_y = _target_stop_gate_y
		_apply_stop_gate_position()


func _apply_plate_rotations() -> void:
	var angle_rad: float = deg_to_rad(_current_flip_angle_deg)
	var actual_angle: float = angle_rad * (1.0 if flip_pivot_on_right else -1.0)
	
	if is_instance_valid(_flip_table_node):
		var rotated_basis := _flip_table_base_transform.basis.rotated(_flip_table_base_transform.basis.z.normalized(), actual_angle)
		_flip_table_node.transform = Transform3D(rotated_basis, _flip_table_base_transform.origin)


func _apply_stop_gate_position() -> void:
	if is_instance_valid(_stop_gate_node):
		var travel := _local_travel_direction()
		var roller_axis := travel.cross(Vector3.UP).normalized()
		var local_up := roller_axis.cross(travel).normalized()
		_stop_gate_node.transform.origin = _stop_gate_base_transform.origin + local_up * _current_stop_gate_y

func get_bed_length() -> float:
	if roller_count <= 1:
		return roller_diameter
	return float(roller_count - 1) * roller_spacing + roller_diameter


const SWEEP_SPROCKET_R := 0.08


func _sweep_loop_span() -> float:
	return roller_length + 0.30


func _sweep_loop_length() -> float:
	return 2.0 * _sweep_loop_span() + 2.0 * PI * SWEEP_SPROCKET_R


func _is_sweep_on_top_run(d: float) -> bool:
	return fposmod(d, _sweep_loop_length()) < _sweep_loop_span()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")

func _rebuild() -> void:
	_rebuild_queued = false
	_roller_visuals.clear()

	var old_container: Node = get_node_or_null("GeneratedRollers")
	if old_container != null:
		if Engine.is_editor_hint():
			remove_child(old_container)
		old_container.queue_free()

	# CollisionShape3D nodes must be direct children of this StaticBody3D.
	for child: Node in get_children():
		if child is CollisionShape3D and child.name.begins_with("GeneratedRoller"):
			if Engine.is_editor_hint():
				remove_child(child)
			child.queue_free()

	var container := Node3D.new()
	container.name = "GeneratedRollers"
	add_child(container)
	# Generated previews and collision shapes intentionally remain unowned so
	# instances do not serialize them into their parent scenes.

	var radius: float = roller_diameter * 0.5
	var travel: Vector3 = _local_travel_direction()
	var roller_axis: Vector3 = travel.cross(Vector3.UP).normalized()
	var local_up: Vector3 = roller_axis.cross(travel).normalized()
	var roller_basis := Basis(local_up, roller_axis, travel)

	var mesh := CylinderMesh.new()
	mesh.height = roller_length
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = radial_segments
	mesh.rings = 1

	# Generate a procedural noise texture to make rotation visually obvious
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	
	var grad := Gradient.new()
	grad.set_color(0, Color(0.70, 0.70, 0.70))
	grad.set_color(1, Color(1.0, 1.0, 1.0))
	noise_tex.color_ramp = grad

	var material := StandardMaterial3D.new()
	material.albedo_texture = noise_tex
	material.albedo_color = roller_color
	material.metallic = 0.85
	material.roughness = 0.28
	mesh.material = material

	var shape := CylinderShape3D.new()
	shape.height = roller_length
	shape.radius = radius

	var center_offset: float = float(roller_count - 1) * 0.5
	for index: int in range(roller_count):
		var offset: float = (float(index) - center_offset) * roller_spacing
		var roller_transform := Transform3D(roller_basis, travel * offset)

		var visual := MeshInstance3D.new()
		visual.name = "RollerVisual%02d" % index
		visual.mesh = mesh
		visual.transform = roller_transform
		container.add_child(visual)
		_roller_visuals.append(visual)

		var collision := CollisionShape3D.new()
		collision.name = "GeneratedRollerCollision%02d" % index
		collision.shape = shape
		collision.transform = roller_transform
		add_child(collision)

	# A continuous composite surface just below the roller crowns prevents thin
	# boards from tunneling into gaps while leaving the cylinders as top contact.
	var support_depth: float = maxf(roller_diameter, 0.10)
	var support_shape := BoxShape3D.new()
	support_shape.size = Vector3(roller_length, support_depth, get_bed_length())
	var support_basis := Basis(roller_axis, Vector3.UP, -travel)
	var support_top: float = radius - 0.01
	var support := CollisionShape3D.new()
	support.name = "GeneratedRollerSupportCollision"
	support.shape = support_shape
	support.transform = Transform3D(
		support_basis,
		Vector3.UP * (support_top - support_depth * 0.5)
	)
	add_child(support)

	_rebuild_flip_table(travel, roller_axis, local_up)
	_rebuild_stop_gate(travel, roller_axis, local_up, radius)
	_rebuild_sweep_chains(travel, roller_axis, local_up, radius)

	_update_motion()

func _rebuild_flip_table(travel: Vector3, roller_axis: Vector3, local_up: Vector3) -> void:
	var old_plates_container: Node = get_node_or_null("GeneratedPlates")
	if old_plates_container != null:
		if Engine.is_editor_hint():
			remove_child(old_plates_container)
		old_plates_container.queue_free()

	_flip_table_node = null
	_flip_table_base_transform = Transform3D.IDENTITY

	if not flip_table_present:
		return

	var plates_container := Node3D.new()
	plates_container.name = "GeneratedPlates"
	add_child(plates_container)

	if roller_count > 1:
		var center_offset: float = float(roller_count - 1) * 0.5
		var pivot_dir: float = 1.0 if flip_pivot_on_right else -1.0

		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(plate_length, plate_thickness, plate_width)
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = plate_color
		plate_mat.metallic = 0.7
		plate_mat.roughness = 0.4
		plate_mesh.material = plate_mat

		var plate_shape := BoxShape3D.new()
		plate_shape.size = Vector3(plate_length, plate_thickness, plate_width)

		var plate_basis := Basis(roller_axis, local_up, travel)
		var pivot_pos := roller_axis * (pivot_dir * (roller_length * 0.5 + connecting_bar_width)) + local_up * plate_y_offset
		var table_transform := Transform3D(plate_basis, pivot_pos)

		var table_body := AnimatableBody3D.new()
		table_body.name = "FlipTable"
		table_body.sync_to_physics = true
		table_body.transform = table_transform
		plates_container.add_child(table_body)
		
		_flip_table_node = table_body
		_flip_table_base_transform = table_transform

		var gap_z_offsets: Array[float] = []
		for index: int in range(roller_count - 1):
			var gap_offset: float = (float(index) + 0.5 - center_offset) * roller_spacing
			gap_z_offsets.append(gap_offset)

			var child_transform := Transform3D(Basis.IDENTITY, Vector3(-pivot_dir * (connecting_bar_width + plate_length * 0.5), 0.0, gap_offset))

			var visual := MeshInstance3D.new()
			visual.name = "VisualArm%02d" % index
			visual.mesh = plate_mesh
			visual.transform = child_transform
			table_body.add_child(visual)

			var collision := CollisionShape3D.new()
			collision.name = "CollisionArm%02d" % index
			collision.shape = plate_shape
			collision.transform = child_transform
			table_body.add_child(collision)

		# Add the connecting bar at the pivot end of the arms
		var bar_z_length: float = gap_z_offsets.back() - gap_z_offsets.front() + plate_width
		
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(connecting_bar_width, connecting_bar_thickness, bar_z_length)
		bar_mesh.material = plate_mat
		
		var bar_shape := BoxShape3D.new()
		bar_shape.size = bar_mesh.size

		var bar_local_pos := Vector3(-pivot_dir * connecting_bar_width * 0.5, 0.0, 0.0)
		var bar_transform := Transform3D(Basis.IDENTITY, bar_local_pos)

		var bar_visual := MeshInstance3D.new()
		bar_visual.name = "ConnectingBarVisual"
		bar_visual.mesh = bar_mesh
		bar_visual.transform = bar_transform
		table_body.add_child(bar_visual)

		var bar_collision := CollisionShape3D.new()
		bar_collision.name = "ConnectingBarCollision"
		bar_collision.shape = bar_shape
		bar_collision.transform = bar_transform
		table_body.add_child(bar_collision)


func _rebuild_stop_gate(travel: Vector3, roller_axis: Vector3, local_up: Vector3, radius: float) -> void:
	var old_gate: Node = get_node_or_null("GeneratedStopGate")
	if old_gate != null:
		if Engine.is_editor_hint():
			remove_child(old_gate)
		old_gate.queue_free()

	var old_sensor: Node = get_node_or_null("StopGateSensor")
	if old_sensor != null:
		if Engine.is_editor_hint():
			remove_child(old_sensor)
		old_sensor.queue_free()

	_stop_gate_node = null

	if stop_gate_present:
		var last_roller_offset: float = float(roller_count - 1) * 0.5 * roller_spacing
		var gate_offset: float = last_roller_offset + (roller_diameter * 0.5) + (stop_gate_thickness * 0.5) + 0.02
		
		var raised_y: float = radius + stop_gate_height_offset
		var retracted_y: float = -radius - 0.05
		var gate_height: float = (raised_y - retracted_y)
		
		var gate_basis := Basis(roller_axis, local_up, travel)
		
		_current_stop_gate_y = raised_y if stop_gate_raised else retracted_y
		_target_stop_gate_y = raised_y if stop_gate_raised else retracted_y
		
		var gate_transform := Transform3D(gate_basis, travel * gate_offset + local_up * _current_stop_gate_y)
		
		var gate_body := AnimatableBody3D.new()
		gate_body.name = "GeneratedStopGate"
		gate_body.transform = gate_transform
		add_child(gate_body)
		_stop_gate_node = gate_body
		_stop_gate_base_transform = Transform3D(gate_basis, travel * gate_offset)

		var child_transform := Transform3D(Basis.IDENTITY, Vector3(0, -gate_height * 0.5, 0))

		var gate_mesh := BoxMesh.new()
		gate_mesh.size = Vector3(stop_gate_length, gate_height, stop_gate_thickness)
		var gate_mat := StandardMaterial3D.new()
		gate_mat.albedo_color = stop_gate_color
		gate_mat.metallic = 0.5
		gate_mat.roughness = 0.5
		gate_mesh.material = gate_mat

		var gate_shape := BoxShape3D.new()
		gate_shape.size = Vector3(stop_gate_length, gate_height, stop_gate_thickness)

		var visual := MeshInstance3D.new()
		visual.name = "Visual"
		visual.mesh = gate_mesh
		visual.transform = child_transform
		gate_body.add_child(visual)

		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = gate_shape
		collision.transform = child_transform
		gate_body.add_child(collision)

		# Generate sensor area for auto-flip detection
		var sensor := Area3D.new()
		sensor.name = "StopGateSensor"
		
		# Position: 10 cm in front of the stop gate, centered on the roller crown height
		var sensor_offset: float = gate_offset - (stop_gate_thickness * 0.5) - 0.10
		sensor.transform = Transform3D(gate_basis, travel * sensor_offset + local_up * radius)
		add_child(sensor)
		
		var sensor_shape := CollisionShape3D.new()
		sensor_shape.name = "Collision"
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(stop_gate_length, radius * 1.5, 0.15) # 15cm sensor depth
		sensor_shape.shape = box_shape
		sensor.add_child(sensor_shape)
		
		sensor.body_entered.connect(_on_stop_gate_sensor_body_entered)
		sensor.body_exited.connect(_on_stop_gate_sensor_body_exited)


func _on_stop_gate_sensor_body_entered(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if not stop_gate_present:
		return
	if not (body is RigidBody3D):
		return

	if _should_stop_for_flip(body):
		_gate_stop_bodies[body.get_instance_id()] = body
		stop_gate_raised = true
		_gate_reopen_timer = 0.0
		if auto_flip_on_stop and _flip_state == FlipState.FLAT and not flip_table_enabled and flip_table_present:
			flip_table_enabled = true
	elif _should_pass_gate(body):
		_gate_board_bodies[body.get_instance_id()] = body
		if _gate_stop_bodies.is_empty():
			stop_gate_raised = false
			_gate_reopen_timer = board_pass_gate_delay


func _on_stop_gate_sensor_body_exited(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if body == null:
		return

	_gate_board_bodies.erase(body.get_instance_id())
	_gate_stop_bodies.erase(body.get_instance_id())
	if _gate_stop_bodies.is_empty() and _gate_board_bodies.is_empty():
		_gate_reopen_timer = board_pass_gate_delay


func _update_auto_stop_gate(delta: float) -> void:
	_prune_gate_tracking()
	if not _gate_stop_bodies.is_empty():
		stop_gate_raised = true
		return
	if not _gate_board_bodies.is_empty():
		stop_gate_raised = false
		_gate_reopen_timer = board_pass_gate_delay
		return
	if _gate_reopen_timer > 0.0:
		_gate_reopen_timer -= delta
		if _gate_reopen_timer <= 0.0:
			stop_gate_raised = true


func _prune_gate_tracking() -> void:
	for id in _gate_board_bodies.keys():
		var board_body: Node = _gate_board_bodies[id]
		if not is_instance_valid(board_body):
			_gate_board_bodies.erase(id)
	for id in _gate_stop_bodies.keys():
		var stop_body: Node = _gate_stop_bodies[id]
		if not is_instance_valid(stop_body):
			_gate_stop_bodies.erase(id)


func _should_pass_gate(body: Node) -> bool:
	return body.is_in_group("cut_boards") and not body.is_in_group("cut_slabs") and not body.is_in_group("logs")


func _should_stop_for_flip(body: Node) -> bool:
	return body.is_in_group("cut_slabs") or body.is_in_group("logs")

func _local_travel_direction() -> Vector3:
	var horizontal := Vector3(transport_direction.x, 0.0, transport_direction.z)
	if horizontal.is_zero_approx():
		return Vector3.FORWARD
	return horizontal.normalized()

func _update_motion() -> void:
	if not is_inside_tree():
		return
	var local_velocity: Vector3 = _local_travel_direction() * speed if enabled else Vector3.ZERO
	constant_linear_velocity = global_transform.basis * local_velocity


func _rebuild_sweep_chains(travel: Vector3, _roller_axis: Vector3, local_up: Vector3, radius: float) -> void:
	var old_sweep: Node = get_node_or_null("GeneratedSweepSystem")
	if old_sweep != null:
		if Engine.is_editor_hint():
			remove_child(old_sweep)
		old_sweep.queue_free()

	var old_sensor: Node = get_node_or_null("SweepSensor")
	if old_sensor != null:
		if Engine.is_editor_hint():
			remove_child(old_sensor)
		old_sensor.queue_free()

	_sweep_lugs.clear()
	_sweep_lug_push_areas.clear()
	_sweep_sprockets.clear()
	_sweep_chain_nodes.clear()
	_sweep_chain_gzipped.clear()
	_sweep_chain_slots.clear()
	_sweep_sensor = null
	_sweep_active = false
	_sweep_travel = 0.0

	if not sweep_chain_present:
		return

	var sweep_container := Node3D.new()
	sweep_container.name = "GeneratedSweepSystem"
	add_child(sweep_container)

	var R := SWEEP_SPROCKET_R
	var Y_top := radius - 0.02
	var Y_center := Y_top - R

	var X_start := -roller_length * 0.5 - 0.15
	var X_end := roller_length * 0.5 + 0.15
	var L_span := X_end - X_start
	var loop_len := 2.0 * L_span + 2.0 * PI * R

	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.22, 0.24, 0.25)
	mat_metal.metallic = 0.85
	mat_metal.roughness = 0.35

	var mat_lug := StandardMaterial3D.new()
	mat_lug.albedo_color = Color(0.9, 0.75, 0.1)
	mat_lug.metallic = 0.3
	mat_lug.roughness = 0.4

	var mat_chain := StandardMaterial3D.new()
	mat_chain.albedo_color = Color(0.15, 0.15, 0.17)
	mat_chain.metallic = 0.9
	mat_chain.roughness = 0.4

	var center_offset := float(roller_count - 1) * 0.5
	var gap_z_offsets: Array[float] = []
	if roller_count > 1:
		for index in range(roller_count - 1):
			gap_z_offsets.append((float(index) + 0.5 - center_offset) * roller_spacing)
	else:
		gap_z_offsets.append(0.0)

	var sweep_statics := StaticBody3D.new()
	sweep_statics.name = "Statics"
	sweep_container.add_child(sweep_statics)

	for gz in gap_z_offsets:
		var gap_pos := travel * gz

		var sp_l := MeshInstance3D.new()
		var sp_l_mesh := CylinderMesh.new()
		sp_l_mesh.top_radius = R
		sp_l_mesh.bottom_radius = R
		sp_l_mesh.height = 0.03
		sp_l_mesh.radial_segments = 10
		sp_l.mesh = sp_l_mesh
		sp_l.material_override = mat_metal
		sp_l.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), gap_pos + Vector3(X_start, Y_center, 0.0))
		sweep_statics.add_child(sp_l)
		_sweep_sprockets.append(sp_l)

		var sp_r := MeshInstance3D.new()
		var sp_r_mesh := CylinderMesh.new()
		sp_r_mesh.top_radius = R
		sp_r_mesh.bottom_radius = R
		sp_r_mesh.height = 0.03
		sp_r_mesh.radial_segments = 10
		sp_r.mesh = sp_r_mesh
		sp_r.material_override = mat_metal
		sp_r.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), gap_pos + Vector3(X_end, Y_center, 0.0))
		sweep_statics.add_child(sp_r)
		_sweep_sprockets.append(sp_r)

		var guide := MeshInstance3D.new()
		var guide_mesh := BoxMesh.new()
		guide_mesh.size = Vector3(L_span, 0.03, 0.04)
		guide.mesh = guide_mesh
		guide.material_override = mat_metal
		guide.transform = Transform3D(Basis.IDENTITY, gap_pos + Vector3(0.0, Y_center, 0.0))
		sweep_statics.add_child(guide)

	# Triangle lug (PrismMesh with left_to_right = 1.0)
	var lug_mesh := PrismMesh.new()
	lug_mesh.size = Vector3(lug_base_length, lug_height, 0.05)
	lug_mesh.left_to_right = 1.0

	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(lug_base_length + 0.03, 0.008, 0.055)

	var lug_shape := BoxShape3D.new()
	lug_shape.size = Vector3(lug_base_length, lug_height, 0.05)

	var lug_collision_y := 0.008 + lug_height * 0.5

	for i in range(gap_z_offsets.size()):
		var lug := AnimatableBody3D.new()
		lug.name = "Lug_%d" % i
		lug.sync_to_physics = true
		sweep_container.add_child(lug)
		_sweep_lugs.append(lug)

		var plate_mi := MeshInstance3D.new()
		plate_mi.name = "MountingPlate"
		plate_mi.mesh = plate_mesh
		plate_mi.material_override = mat_lug
		plate_mi.position = Vector3(0.0, 0.004, 0.0)
		lug.add_child(plate_mi)

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = lug_mesh
		mi.material_override = mat_lug
		mi.position = Vector3(0.0, lug_collision_y, 0.0)
		lug.add_child(mi)

		var col := CollisionShape3D.new()
		col.name = "Collision"
		col.shape = lug_shape
		col.position = Vector3(0.0, lug_collision_y, 0.0)
		lug.add_child(col)

		var push_area := Area3D.new()
		push_area.name = "PushArea"
		push_area.monitoring = true
		push_area.monitorable = false
		var push_col := CollisionShape3D.new()
		push_col.shape = lug_shape
		push_col.position = col.position
		push_area.add_child(push_col)
		lug.add_child(push_area)
		_sweep_lug_push_areas.append(push_area)

	# Spawn visual chain links
	const SWEEP_PITCH := 0.12
	var n_links := int(ceil(loop_len / SWEEP_PITCH)) + 2

	var link_plate_mesh := BoxMesh.new()
	link_plate_mesh.size = Vector3(SWEEP_PITCH * 0.85, 0.024, 0.005)

	var link_roller_mesh := CylinderMesh.new()
	link_roller_mesh.top_radius = 0.015
	link_roller_mesh.bottom_radius = 0.015
	link_roller_mesh.height = 0.035
	link_roller_mesh.radial_segments = 6

	for i in range(gap_z_offsets.size()):
		var gz := gap_z_offsets[i]
		for j in range(n_links):
			var slot_pos := float(j) * SWEEP_PITCH
			
			var link := Node3D.new()
			link.name = "ChainLink_%d_%d" % [i, j]
			
			var lp := MeshInstance3D.new()
			lp.mesh = link_plate_mesh
			lp.material_override = mat_chain
			lp.position = Vector3(0.0, 0.0, -0.016)
			link.add_child(lp)

			var rp := MeshInstance3D.new()
			rp.mesh = link_plate_mesh
			rp.material_override = mat_chain
			rp.position = Vector3(0.0, 0.0, 0.016)
			link.add_child(rp)

			var ro := MeshInstance3D.new()
			ro.mesh = link_roller_mesh
			ro.material_override = mat_chain
			ro.rotation_degrees.x = 90.0
			link.add_child(ro)

			sweep_container.add_child(link)
			
			_sweep_chain_nodes.append(link)
			_sweep_chain_gzipped.append(gz)
			_sweep_chain_slots.append(slot_pos)

	var last_roller_pos := travel * (center_offset * roller_spacing + sweep_trigger_offset)
	var sensor := Area3D.new()
	sensor.name = "SweepSensor"
	sensor.transform = Transform3D(Basis.IDENTITY, last_roller_pos + local_up * (radius + 0.15))
	add_child(sensor)
	_sweep_sensor = sensor

	var sensor_shape := CollisionShape3D.new()
	sensor_shape.name = "Collision"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(roller_length, 0.5, 0.25)
	sensor_shape.shape = box_shape
	sensor.add_child(sensor_shape)

	sensor.body_entered.connect(_on_sweep_sensor_body_entered)
	
	_update_sweep_visuals(0.0)


func _update_sweep_visuals(p_travel: float) -> void:
	var R := SWEEP_SPROCKET_R
	var X_start := -roller_length * 0.5 - 0.15
	var X_end := roller_length * 0.5 + 0.15
	var L_span := X_end - X_start
	var loop_len := 2.0 * L_span + 2.0 * PI * R

	var center_offset := float(roller_count - 1) * 0.5
	for i in range(_sweep_lugs.size()):
		var lug := _sweep_lugs[i]
		if is_instance_valid(lug):
			var gz := (float(i) + 0.5 - center_offset) * roller_spacing if roller_count > 1 else 0.0
			lug.transform = _get_sweep_loop_xform(p_travel, gz)

	for i in range(_sweep_chain_nodes.size()):
		var node = _sweep_chain_nodes[i]
		if is_instance_valid(node):
			var slot := fposmod(_sweep_chain_slots[i] + p_travel, loop_len)
			node.transform = _get_sweep_loop_xform(slot, _sweep_chain_gzipped[i])

	var ang_rad := -p_travel / R
	for sp in _sweep_sprockets:
		if is_instance_valid(sp):
			sp.rotation.y = ang_rad


func _get_sweep_loop_xform(d: float, gz: float) -> Transform3D:
	var R := SWEEP_SPROCKET_R
	var Y_top := (roller_diameter * 0.5) - 0.02
	var Y_center := Y_top - R
	var Y_bot := Y_center - R

	var X_start := -roller_length * 0.5 - 0.15
	var X_end := roller_length * 0.5 + 0.15
	var L_span := X_end - X_start

	var loop_len := 2.0 * L_span + 2.0 * PI * R
	d = fposmod(d, loop_len)

	var x: float
	var y: float
	var rot_z: float

	if d < L_span:
		x = X_start + d
		y = Y_top
		rot_z = 0.0
	elif d < L_span + PI * R:
		var theta := (d - L_span) / R
		x = X_end + R * sin(theta)
		y = Y_center + R * cos(theta)
		rot_z = theta
	elif d < 2.0 * L_span + PI * R:
		var d_ret := d - (L_span + PI * R)
		x = X_end - d_ret
		y = Y_bot
		rot_z = PI
	else:
		var theta := (d - (2.0 * L_span + PI * R)) / R
		x = X_start - R * sin(theta)
		y = Y_center - R * cos(theta)
		rot_z = PI + theta

	return Transform3D(Basis(Vector3.FORWARD, rot_z), Vector3(x, y, gz))


func _apply_sweep_push(delta: float) -> void:
	if not _sweep_active or not _is_sweep_on_top_run(_sweep_travel):
		return

	var travel := _local_travel_direction()
	var roller_axis := travel.cross(Vector3.UP).normalized()
	var push_dir := (global_transform.basis * roller_axis).normalized()
	var target_vel := push_dir * sweep_speed
	var accel := sweep_speed * 4.0

	for area in _sweep_lug_push_areas:
		if not is_instance_valid(area):
			continue
		for body in area.get_overlapping_bodies():
			if not (body is RigidBody3D):
				continue
			if not (body.is_in_group("logs") or body.is_in_group("cut_boards")):
				continue
			if body.freeze:
				continue
			body.sleeping = false
			var horizontal_velocity := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
			var target_horizontal := Vector3(target_vel.x, 0.0, target_vel.z)
			horizontal_velocity = horizontal_velocity.move_toward(target_horizontal, accel * delta)
			body.linear_velocity = Vector3(
				horizontal_velocity.x,
				body.linear_velocity.y,
				horizontal_velocity.z
			)


func _on_sweep_sensor_body_entered(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if not sweep_chain_present or not auto_sweep:
		return
	if _sweep_active:
		return

	if body is RigidBody3D and (body.is_in_group("logs") or body.is_in_group("cut_boards")):
		_sweep_active = true
		_sweep_travel = 0.0


func trigger_sweep() -> void:
	if not sweep_chain_present or _sweep_active:
		return
	_sweep_active = true
	_sweep_travel = 0.0
