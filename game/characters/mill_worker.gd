class_name MillWorker
extends Node3D

## A mill worker: hard hat, safety glasses, hi-vis vest, gloves, jeans and work boots. Walks
## along a list of global waypoints (stairs are just waypoints that climb), swinging arms and
## legs, and can carry a board on the shoulder or reach out to set one down.
## Faces -Z. The figure is built from primitives in code.

signal arrived

@export var walk_speed: float = 1.3

var _path: PackedVector3Array = PackedVector3Array()
var _carry: RigidBody3D
var _phase: float = 0.0
var _moving: bool = false
var _reach: float = 0.0                    # 0 arms at sides, 1 arms out (handling a board)

var _hips: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _ready() -> void:
	var skin := _mat(Color(0.78, 0.58, 0.44), 0.6)
	var vest := _mat(Color(1.0, 0.42, 0.02), 0.5, Color(0.35, 0.12, 0.0))
	var stripe := _mat(Color(0.85, 0.85, 0.85), 0.2, Color(0.2, 0.2, 0.2))
	var shirt := _mat(Color(0.32, 0.34, 0.38), 0.8)
	var jeans := _mat(Color(0.12, 0.17, 0.30), 0.85)
	var boot := _mat(Color(0.22, 0.14, 0.08), 0.6)
	var hat := _mat(Color(0.95, 0.80, 0.05), 0.35)
	var glove := _mat(Color(0.75, 0.62, 0.38), 0.8)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.2)
	_hips = Node3D.new()
	_hips.position = Vector3(0.0, 0.93, 0.0)
	add_child(_hips)
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.1, 0.0, 0.0)
		_hips.add_child(leg)
		_part(leg, _capsule(0.075, 0.86), jeans, Vector3(0.0, -0.43, 0.0))
		_part(leg, _box(Vector3(0.12, 0.1, 0.28)), boot, Vector3(0.0, -0.88, -0.05))
		_legs.append(leg)
	_part(_hips, _capsule(0.17, 0.66), vest, Vector3(0.0, 0.3, 0.0))
	for y: float in [0.16, 0.38]:
		_part(_hips, _box(Vector3(0.35, 0.035, 0.35)), stripe, Vector3(0.0, y, 0.0))
	_part(_hips, _capsule(0.06, 0.16), skin, Vector3(0.0, 0.66, 0.0))
	_part(_hips, _sphere(0.11), skin, Vector3(0.0, 0.76, 0.0))
	_part(_hips, _box(Vector3(0.16, 0.035, 0.03)), dark, Vector3(0.0, 0.78, -0.1))           # safety glasses
	var hh := _part(_hips, _sphere(0.125), hat, Vector3(0.0, 0.83, 0.0))
	hh.scale = Vector3(1.0, 0.75, 1.1)
	var brim := CylinderMesh.new()
	brim.top_radius = 0.16
	brim.bottom_radius = 0.16
	brim.height = 0.015
	_part(_hips, brim, hat, Vector3(0.0, 0.81, -0.02))
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.22, 0.52, 0.0)
		_hips.add_child(arm)
		_part(arm, _capsule(0.055, 0.6), shirt, Vector3(0.0, -0.28, 0.0))
		_part(arm, _sphere(0.05), glove, Vector3(0.0, -0.6, 0.0))
		_arms.append(arm)


func _mat(c: Color, rough: float, emit: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


## Walk through these global points in turn; emits `arrived` at the last one.
func walk(points: PackedVector3Array) -> void:
	_path = points
	_moving = not _path.is_empty()
	if not _moving:
		arrived.emit()


func is_walking() -> bool:
	return _moving


## Turn to face a global point (on the level).
func face(p: Vector3) -> void:
	var d := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
	if d.length() > 0.01:
		look_at(global_position + d, Vector3.UP)


## Take a board onto the shoulder (it rides along until put down).
func shoulder(board: RigidBody3D) -> void:
	_carry = board
	lift_clear(board)


## A board in a worker's hands: held (frozen) and out of everything's way until it is set
## down, so lifting it never shoves the boards around it (a frozen board moved by hand would
## push straight through them).
static func lift_clear(board: RigidBody3D) -> void:
	if not board.has_meta("hand_layers"):
		board.set_meta("hand_layers", Vector2i(board.collision_layer, board.collision_mask))
	board.collision_layer = 0
	board.collision_mask = 0
	board.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	board.freeze = true


## Set down: the board collides again (and the caller unfreezes it unless it should stay put).
static func set_down(board: RigidBody3D) -> void:
	if board.has_meta("hand_layers"):
		var l: Vector2i = board.get_meta("hand_layers")
		board.collision_layer = l.x
		board.collision_mask = l.y
		board.remove_meta("hand_layers")


## Loose boards lying on top of this one (resting on it, at least partly over it). A worker
## takes those off first instead of pulling a board out from under them.
static func boards_on(board: RigidBody3D) -> Array[RigidBody3D]:
	var found: Array[RigidBody3D] = []
	var t: float = float(board.get("board_thickness"))
	var length: float = float(board.get("product_length"))
	var w: float = float(board.get("board_width"))
	var inv: Transform3D = board.global_transform.affine_inverse()
	var up: Vector3 = board.global_basis.y.normalized()
	for n: Node in board.get_tree().get_nodes_in_group("cut_boards"):
		var o := n as RigidBody3D
		if o == null or o == board or o.freeze or o.get("board_width") == null:
			continue
		var rise: float = (o.global_position - board.global_position).dot(up)
		if rise < t * 0.5 or rise > t * 0.5 + float(o.get("board_thickness")) * 1.5:
			continue
		var q: Vector3 = inv * o.global_position
		if absf(q.x) < length * 0.5 + 0.1 and absf(q.z) < (w + float(o.get("board_width"))) * 0.5 - 0.01:
			found.append(o)
	return found


func carrying() -> RigidBody3D:
	return _carry


func drop_carry() -> void:
	_carry = null


func set_reach(on: bool) -> void:
	_reach = 1.0 if on else 0.0


func _process(delta: float) -> void:
	if _moving:
		var target: Vector3 = _path[0]
		var to: Vector3 = target - global_position
		var step: float = walk_speed * delta
		if to.length() <= step:
			global_position = target
			_path.remove_at(0)
			if _path.is_empty():
				_moving = false
				arrived.emit()
		else:
			global_position += to.normalized() * step
			face(target)
		_phase += delta * walk_speed * 5.0
	else:
		_phase = move_toward(_phase, roundf(_phase / PI) * PI, delta * 4.0)
	var swing: float = sin(_phase) * (0.55 if _moving else 0.0)
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	var carry_up: float = -2.6 if _carry != null else 0.0
	var reach_out: float = -1.2 * _reach
	_arms[0].rotation.x = -swing * 0.7 + reach_out
	_arms[1].rotation.x = swing * 0.7 + reach_out + carry_up
	_hips.position.y = 0.93 + absf(sin(_phase)) * (0.03 if _moving else 0.0)
	if _carry != null and is_instance_valid(_carry):
		# On the right shoulder, the board's length along the way he walks.
		var b := global_basis
		var length_dir: Vector3 = -b.z
		var carry_basis := Basis(length_dir, Vector3.UP, length_dir.cross(Vector3.UP)).orthonormalized()
		_carry.global_transform = Transform3D(carry_basis, global_position + Vector3.UP * 1.62 + b.x * 0.2)
