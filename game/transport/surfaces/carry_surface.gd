@tool
class_name CarrySurface
extends StaticBody3D

## A box that carries whatever rests on it, like a conveyor belt that never moves.
## Resize and place it with its CollisionShape3D child (drag the gizmo handles).
## Its colour and the arrow show where it carries things while you edit.

## Turn the surface on or off. An off surface is just a plain solid box.
@export var enabled: bool = true
## Carry speed in metres per second.
@export_range(0.0, 10.0, 0.05, "or_greater") var speed: float = 0.5
## Direction of travel in this node's own axes (it turns with the node).
## (0, 0, 1) carries along the box's local +Z. Small sideways values give a
## gentle drift, e.g. (0.15, 0, 1) also nudges things along +X.
@export var direction: Vector3 = Vector3(0, 0, 1):
	set(value):
		direction = value
		_update_arrow()
## Surface friction. High values stop boards sliding back down a slope.
@export_range(0.0, 5.0, 0.05, "or_greater") var grip: float = 1.5:
	set(value):
		grip = value
		_apply_grip()
## Set by another machine to hold this surface (e.g. a full sorter).
@export var external_stop: bool = false
@export_group("Editor look")
@export var show_arrow: bool = true:
	set(value):
		show_arrow = value
		_update_arrow()
@export var colour: Color = Color(0.2, 0.8, 0.3, 0.35):
	set(value):
		colour = value
		_update_arrow()

var _arrow: MeshInstance3D


func _ready() -> void:
	_apply_grip()
	_update_arrow()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var carrying: bool = enabled and not external_stop and direction.length() > 0.0001
	constant_linear_velocity = global_basis * direction.normalized() * speed if carrying else Vector3.ZERO


func _apply_grip() -> void:
	var material := PhysicsMaterial.new()
	material.friction = grip
	material.rough = true
	physics_material_override = material


## Editor-only arrow showing the carry direction on the top of the box.
func _update_arrow() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		if is_instance_valid(_arrow):
			_arrow.queue_free()
		return
	if not is_instance_valid(_arrow):
		_arrow = get_node_or_null("EditorArrow") as MeshInstance3D
	if not show_arrow or direction.length() < 0.0001:
		if is_instance_valid(_arrow):
			_arrow.visible = false
		return
	if not is_instance_valid(_arrow):
		_arrow = MeshInstance3D.new()
		_arrow.name = "EditorArrow"
		_arrow.mesh = PrismMesh.new()
		add_child(_arrow)
	_arrow.visible = true
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow.material_override = material
	var top: float = 0.0
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			top = (child as CollisionShape3D).position.y + ((child as CollisionShape3D).shape as BoxShape3D).size.y * 0.5
			break
	var dir: Vector3 = direction.normalized()
	# A flat prism lying on the top face, pointing along `direction`.
	(_arrow.mesh as PrismMesh).size = Vector3(0.5, 0.6, 0.02)
	_arrow.position = Vector3(0, top + 0.02, 0)
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# The prism's tip (+Y) is turned to point along `dir`.
	_arrow.basis = Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5)
