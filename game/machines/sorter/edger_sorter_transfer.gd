@tool
extends Node3D
## Receives real edger boards lengthwise, then lifts and transfers them sideways.
## The guided carriage preserves the original board and its lumber properties.
@export var sorter_path: NodePath
@export var receiving_length: float = 6.0
@export var feed_speed: float = 1.5
@export var lift_speed: float = 1.2
var _receiver: StaticBody3D
var _zone: Area3D
var _carriage: Node3D
var _board: RigidBody3D
var _stage: int = 0
var _saved_freeze_mode: int = 0
var delivered_boards: int = 0

func _ready() -> void:
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.18, 0.36, 0.24)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.92, 0.42, 0.08)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.28, 0.3)
	steel.metallic = 0.8
	_receiver = StaticBody3D.new()
	_receiver.name = "PoweredReceivingTable"
	add_child(_receiver)
	_box(_receiver, Vector3(receiving_length, 0.12, 1.2), Vector3(0, -0.06, 0), green, true)
	for i in range(15):
		_box(_receiver, Vector3(0.12, 0.025, 1.1), Vector3(-receiving_length * 0.5 + 0.15 + i * (receiving_length - 0.3) / 14.0, 0.0125, 0), steel, false)
	for x in [-receiving_length * 0.5 + 0.2, receiving_length * 0.5 - 0.2]:
		for z in [-0.52, 0.52]:
			_box(_receiver, Vector3(0.12, 1.7, 0.12), Vector3(x, -0.95, z), green, true)
	_box(_receiver, Vector3(0.1, 0.45, 1.3), Vector3(receiving_length * 0.5, 0.15, 0), orange, true)
	_carriage = Node3D.new()
	_carriage.name = "LiftTransferCarriage"
	add_child(_carriage)
	for x in [-1.8, 0.0, 1.8]:
		_box(_carriage, Vector3(0.12, 0.08, 1.0), Vector3(x, -0.05, 0), orange, false)
		_box(self, Vector3(0.12, 4.4, 0.12), Vector3(x, 0.5, -0.75), green, false)
		_box(self, Vector3(0.1, 0.1, 3.8), Vector3(x, 2.85, 1.1), green, false)
	_zone = Area3D.new()
	_zone.name = "ReceivingBoardSensor"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(receiving_length, 0.8, 1.3)
	col.shape = shape
	col.position.y = 0.4
	_zone.add_child(col)
	add_child(_zone)

func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	parent.add_child(mesh)
	if solid:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		parent.add_child(col)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var sorter := get_node_or_null(sorter_path)
	if sorter == null:
		return
	_receiver.constant_linear_velocity = global_basis.x * (feed_speed if _stage == 0 else 0.0)
	if _stage == 3:
		_carriage.position = _carriage.position.move_toward(Vector3.ZERO, lift_speed * delta)
		if _carriage.position.length() < 0.01:
			_stage = 0
		return
	if not is_instance_valid(_board):
		_board = null
		_stage = 0
		_carriage.position = Vector3.ZERO
	if _stage == 0:
		for body in _zone.get_overlapping_bodies():
			if not body is RigidBody3D or not body.is_in_group("cut_boards") or body.is_in_group("cut_slabs") or body.freeze:
				continue
			var pos := to_local(body.global_position)
			# Wait until the trailing end has cleared the edger.
			var half_length: float = float(body.get("product_length")) * 0.5
			if pos.x - half_length < -receiving_length * 0.5 + 0.08 or absf(pos.z) > 0.45:
				continue
			if not sorter.can_accept_board(body):
				body.linear_velocity = Vector3.ZERO
				_receiver.constant_linear_velocity = Vector3.ZERO
				return
			_board = body
			_saved_freeze_mode = body.freeze_mode
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			_stage = 1
			break
		return
	var thickness: float = float(_board.get("board_thickness"))
	var destination: Vector3 = sorter.to_global(Vector3(-0.3, sorter.sorter_height + 0.14 + thickness * 0.5, 0))
	var target := destination
	if _stage == 1:
		target = Vector3(global_position.x, destination.y, global_position.z)
	_board.global_position = _board.global_position.move_toward(target, lift_speed * delta)
	_carriage.global_position = _board.global_position - Vector3(0, thickness * 0.5 + 0.025, 0)
	if _board.global_position.distance_to(target) > 0.015:
		return
	if _stage == 1:
		_stage = 2
	elif sorter.can_accept_board(_board):
		_board.freeze_mode = _saved_freeze_mode
		_board.freeze = false
		_board.sleeping = false
		sorter._on_infeed_body_entered(_board)
		delivered_boards += 1
		_board = null
		_stage = 3
