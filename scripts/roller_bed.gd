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

enum FlipState { FLAT, FLIPPING, HOLDING, RETRACTING }
var _flip_state: FlipState = FlipState.FLAT
var _flip_timer: float = 0.0

var _current_flip_angle_deg: float = 0.0
var _target_flip_angle_deg: float = 0.0

var _current_stop_gate_y: float = 0.0
var _target_stop_gate_y: float = 0.0

var _flipper_plates: Array[AnimatableBody3D] = []
var _stop_gate_node: AnimatableBody3D = null

var _plate_base_transforms: Array[Transform3D] = []
var _stop_gate_base_transform: Transform3D = Transform3D.IDENTITY

var _roller_visuals: Array[MeshInstance3D] = []
var _rebuild_queued: bool = false


func _ready() -> void:
	_rebuild()

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
		var radius: float = roller_diameter * 0.5
		var raised_y: float = radius + stop_gate_height_offset
		var retracted_y: float = -radius - 0.05
		_target_stop_gate_y = raised_y if stop_gate_raised else retracted_y

		if not is_equal_approx(_current_stop_gate_y, _target_stop_gate_y):
			_current_stop_gate_y = move_toward(_current_stop_gate_y, _target_stop_gate_y, stop_gate_speed * delta)
			_apply_stop_gate_position()


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
	
	for i in range(_flipper_plates.size()):
		var plate := _flipper_plates[i]
		if is_instance_valid(plate):
			var base_transform := _plate_base_transforms[i]
			var rotated_basis := base_transform.basis.rotated(base_transform.basis.z.normalized(), actual_angle)
			plate.transform = Transform3D(rotated_basis, base_transform.origin)


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
		remove_child(old_container)
		old_container.queue_free()

	# CollisionShape3D nodes must be direct children of this StaticBody3D.
	for child: Node in get_children():
		if child is CollisionShape3D and child.name.begins_with("GeneratedRoller"):
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

	_update_motion()

func _rebuild_flip_table(travel: Vector3, roller_axis: Vector3, local_up: Vector3) -> void:
	var old_plates_container: Node = get_node_or_null("GeneratedPlates")
	if old_plates_container != null:
		remove_child(old_plates_container)
		old_plates_container.queue_free()

	_flipper_plates.clear()
	_plate_base_transforms.clear()

	if not flip_table_present:
		return

	var plates_container := Node3D.new()
	plates_container.name = "GeneratedPlates"
	add_child(plates_container)

	if roller_count > 1:
		var center_offset: float = float(roller_count - 1) * 0.5
		var pivot_dir: float = 1.0 if flip_pivot_on_right else -1.0
		var plate_width: float = maxf((roller_spacing - roller_diameter) - 0.04, 0.02)

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

		for index: int in range(roller_count - 1):
			var gap_offset: float = (float(index) + 0.5 - center_offset) * roller_spacing
			var plate_transform := Transform3D(plate_basis, travel * gap_offset + roller_axis * (pivot_dir * plate_length * 0.5) + local_up * plate_y_offset)
			
			var plate_body := AnimatableBody3D.new()
			plate_body.name = "FlipperPlate%02d" % index
			plate_body.transform = plate_transform
			plates_container.add_child(plate_body)
			_flipper_plates.append(plate_body)
			_plate_base_transforms.append(plate_transform)

			var child_transform := Transform3D(Basis.IDENTITY, Vector3(-pivot_dir * plate_length * 0.5, 0, 0))

			var visual := MeshInstance3D.new()
			visual.name = "Visual"
			visual.mesh = plate_mesh
			visual.transform = child_transform
			plate_body.add_child(visual)

			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			collision.shape = plate_shape
			collision.transform = child_transform
			plate_body.add_child(collision)


func _rebuild_stop_gate(travel: Vector3, roller_axis: Vector3, local_up: Vector3, radius: float) -> void:
	var old_gate: Node = get_node_or_null("GeneratedStopGate")
	if old_gate != null:
		remove_child(old_gate)
		old_gate.queue_free()

	var old_sensor: Node = get_node_or_null("StopGateSensor")
	if old_sensor != null:
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


func _on_stop_gate_sensor_body_entered(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if not auto_flip_on_stop:
		return
	if not stop_gate_raised or not stop_gate_present:
		return
	
	if body is RigidBody3D:
		if _flip_state == FlipState.FLAT and not flip_table_enabled and flip_table_present:
			flip_table_enabled = true

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
