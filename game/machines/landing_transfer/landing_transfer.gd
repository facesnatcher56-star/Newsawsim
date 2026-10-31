extends Node3D

## landing_transfer.gd
## Landing table and chain transfer from the picker belt end to the sorter's lug incline.
##
## The model (game/assets/models/board_line/board_landing_*, built by dev/blender/board_line/lt_build)
## is in mill coordinates, like this node. A board runs off the picker belt onto live lift rolls
## that drive it on to the cushioned end stop. Once it has stopped and the start of the transfer
## is clear, the rolls drop below the chains and the board settles on five chain strands that
## carry it sideways (+Z), level, then down an 11 deg run to a level end where the lug incline's
## lugs come up through the strands and take it. The rolls come back up for the next board.

const ChainLoop := preload("res://game/transport/chains/chain_loop.gd")

const BOARD_X := 55.6
const STOP_X := 58.04
## Five strands interleaved with the incline's lanes, plus two either side of the centre so a
## 6 ft board, centred, lies on three.
const STRAND_X: Array[float] = [52.85, 54.225, 55.26, 55.6, 55.94, 56.975, 58.35]
const LANE_Z := 21.6
const PATH := [Vector2(21.25, 1.060), Vector2(22.10, 1.060), Vector2(26.82, 0.127), Vector2(27.82, 0.127)]
const SPROCKET_R := 0.0762
const ROLL_TOP := 1.080
const ROLL_DROP := 0.08
const ROLL_R := 0.06
const LINK_PITCH := 0.06627
const LINK_SCENE := "res://game/assets/models/board_line/board_line_roller_link.glb"

@export var roll_speed: float = 1.5
@export var chain_speed: float = 0.5
@export var drop_time: float = 0.5
@export var debug_log: bool = false

var _lift_body: AnimatableBody3D
var _lift: Node3D
var _lift_home: float = 0.0
var _rolls: Array[Node3D] = []
var _down: float = 0.0
var _want_down: bool = false
var _runs: Array[StaticBody3D] = []
var _dirs: Array[Vector3] = []
var _loop
var _travel: float = 0.0
var _roll_travel: float = 0.0
var _chain := {}
var _shafts: Array[Node3D] = []
var _landed: int = 0
var _braked: bool = false


func _ready() -> void:
	_lift = find_child("LT_Lift", true, false) as Node3D
	if _lift:
		_lift_home = _lift.position.y
		var i := 1
		while true:
			var r := _lift.find_child("LT_Roll%d" % i, true, false) as Node3D
			if r == null:
				break
			_rolls.append(r)
			i += 1
	for n in ["LT_Tail", "LT_Head"]:
		_shafts.append(find_child(n, true, false) as Node3D)
	# Live rolls: one moving body that drops with the lift frame.
	_lift_body = AnimatableBody3D.new()
	_lift_body.name = "LiftRolls"
	_lift_body.sync_to_physics = false
	add_child(_lift_body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(STOP_X - 52.75, 0.04, 0.6)
	cs.shape = box
	_lift_body.add_child(cs)
	# Chain runs: a moving surface per segment of the path, each a few mm below the last.
	for i in PATH.size() - 1:
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var d := (b - a).normalized()
		var t := Vector3(0.0, d.y, d.x)
		var up := Vector3(0.0, t.z, -t.y)
		var run := StaticBody3D.new()
		run.name = "TransferRun%d" % i
		add_child(run)
		var rcs := CollisionShape3D.new()
		var rbox := BoxShape3D.new()
		rbox.size = Vector3(STRAND_X[-1] - STRAND_X[0] + 0.1, 0.06, a.distance_to(b))
		rcs.shape = rbox
		rcs.transform = Transform3D(Basis(Vector3.RIGHT, up, t),
				Vector3(BOARD_X, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5) - up * (0.03 + 0.003 * i))
		run.add_child(rcs)
		_runs.append(run)
		_dirs.append(t)
	# End stop.
	var stop := StaticBody3D.new()
	stop.name = "EndStop"
	add_child(stop)
	var scs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(0.06, 0.3, 0.66)
	scs.shape = sbox
	scs.position = Vector3(STOP_X + 0.03, ROLL_TOP + 0.14, LANE_Z)
	stop.add_child(scs)
	_place_lift()
	_loop = ChainLoop.from_path(PackedVector2Array(PATH), SPROCKET_R)
	_build_chain()


func _physics_process(delta: float) -> void:
	# A photo eye at the table centre stops the rolls as a board's middle reaches it, so every
	# length lands centred on the sorter line (the end stop only catches a 16 ft board that
	# overruns). Then, with the board still and the transfer start clear, the rolls drop.
	var at_stop := false
	var on_table := false
	var centred := false
	for b in _boards_in(52.6, 59.0, LANE_Z - 0.45, LANE_Z + 0.45, 1.0, 1.3):
		on_table = true
		if b.global_position.x >= BOARD_X - 0.03 or b.global_position.x + _half_len(b) > STOP_X - 0.05:
			centred = true
			if absf(b.linear_velocity.x) < 0.1:
				at_stop = true
	_braked = centred
	var start_clear := _boards_in(52.6, 59.0, LANE_Z + 0.45, 22.4, 0.9, 1.3).is_empty()
	if not _want_down and at_stop and start_clear:
		_want_down = true
		_landed += 1
		if debug_log:
			print("[%s] %.1f s rolls down, board %d onto the transfer" % [name, Time.get_ticks_msec() / 1000.0, _landed])
	elif _want_down and not on_table and _down >= 1.0:
		_want_down = false
	_down = move_toward(_down, 1.0 if _want_down else 0.0, delta / drop_time)
	_place_lift()
	var rv := roll_speed if _down < 0.5 and not _braked else 0.0
	_lift_body.constant_linear_velocity = Vector3(rv, 0.0, 0.0)
	_roll_travel += rv * delta
	for r in _rolls:
		r.rotation.z = -_roll_travel / ROLL_R
	for i in _runs.size():
		_runs[i].constant_linear_velocity = _dirs[i] * chain_speed
	_travel += chain_speed * delta
	for s in _shafts:
		if s:
			s.rotation.x = _travel / SPROCKET_R
	if _chain.has("mm"):
		var k: int = _loop.phase_index(_travel, _chain["per"], 8)
		if k != _chain["shown"]:
			_chain["shown"] = k
			(_chain["mm"] as MultiMesh).buffer = _chain["baked"][k]


func _place_lift() -> void:
	var drop := ROLL_DROP * _ease(_down)
	_lift_body.global_transform = Transform3D(Basis.IDENTITY,
			Vector3((52.75 + STOP_X) * 0.5, ROLL_TOP - 0.02 - drop, LANE_Z))
	if _lift:
		_lift.position.y = _lift_home - drop


func _boards_in(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.is_in_group("cut_slabs"):
			continue
		var p := b.global_position
		if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1 and p.y > y0 and p.y < y1:
			out.append(b)
	return out


func _half_len(b: Node) -> float:
	return float(b.get("product_length")) * 0.5 if b.get("product_length") != null else 2.44


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _build_chain() -> void:
	var scene := load(LINK_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var mesh := (src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	src.free()
	var per := int(_loop.length / LINK_PITCH)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = per * STRAND_X.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TransferChains"
	mmi.multimesh = mm
	add_child(mmi)
	_chain = {"mm": mm, "per": per, "shown": -1, "baked": _loop.bake(per, STRAND_X, _frame, 8)}


## A link at a loop sample, at world x: (across, out of the loop, -travel); the loop runs +Z.
func _frame(smp: Array, x: float) -> Transform3D:
	var p: Vector2 = smp[0]
	var t2: Vector2 = smp[1]
	var t := Vector3(0.0, t2.y, t2.x)
	var across := Vector3.LEFT
	return Transform3D(Basis(across, across.cross(t), -t), Vector3(x, p.y, p.x))


## One line for debug HUDs.
func status_text() -> String:
	return "rolls %s, boards landed %d" % ["down" if _down >= 1.0 else ("up" if _down <= 0.0 else "moving"), _landed]
