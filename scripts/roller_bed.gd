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
@export var roller_color: Color = Color(0.34, 0.36, 0.40, 1.0):
	set(value):
		roller_color = value
		_queue_rebuild()

@export_range(8, 64, 1) var radial_segments: int = 24:
	set(value):
		radial_segments = clampi(value, 8, 64)
		_queue_rebuild()

var _roller_visuals: Array[MeshInstance3D] = []
var _rebuild_queued: bool = false

func _ready() -> void:
	_rebuild()

func _physics_process(_delta: float) -> void:
	# Re-evaluate this so rotating the whole bed also rotates its transport velocity.
	_update_motion()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled or is_zero_approx(speed):
		return
	var radius: float = roller_diameter * 0.5
	var angular_step: float = -(speed / radius) * delta
	for roller: MeshInstance3D in _roller_visuals:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, angular_step)

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

	var material := StandardMaterial3D.new()
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

	_update_motion()

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
