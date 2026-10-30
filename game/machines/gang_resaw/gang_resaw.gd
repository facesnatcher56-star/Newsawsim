extends Node3D

## gang_resaw.gd
## Cant transfer, flip turner, sharp-chain infeed and twin-arbor chipping gang.
##
## The model (game/assets/models/gang_resaw, built by dev/blender/gang_resaw) is in mill
## coordinates, like this node. The headrig outfeed's cant kickers throw a two-sided cant (+Z)
## onto the transfer (has_room()); its chains carry it to the stop. When the infeed is free the
## flip turner rolls it a quarter turn over onto the sharp chain, sawn faces down, and the chain
## feeds it (+X) under the press rolls into the gang: chip heads flatten the round sides and
## the saws split it into eight 2x12s on edge, which come out onto the lift rolls. At the end
## stop, once the board transfer below has room, the rolls drop and the boards tip over flat
## onto the transfer. The headrig outfeed holds its board kickers while the lift is up
## (board_lane_clear()).

enum Xfer { EMPTY, CARRY, AT_STOP, TURN, SETTLE }
enum Feed { EMPTY, FEED, OUT, DROP }

const CANT_HALF := 2.46
const CANT_R := 0.245
const CANT_H := 0.29
## Transfer chains (+Z) and the cant at the stop.
const XFER_X: Array[float] = [30.9, 32.7, 34.5]
const XFER_Z := Vector2(5.95, 8.05)
const XFER_TOP_Y := -0.22
const STOP_CANT_Z := 7.86
const TURNER_PIVOT := Vector2(8.45, -0.5)      # (z, y)
## Sharp chain and gang line.
const LINE_Z := 8.9
const SHARP_X := Vector2(30.35, 36.25)
const SHARP_TOP_Y := -0.15
const PRESS_X: Array[float] = [34.62, 35.87]   # where each press roll bears on the cant
const PRESS_DEG := 22.0
const CHIP_X := 36.75
const SAW_X := 37.25
const BOARD_T := 0.038
const KERF := 0.005
const N_BOARDS := 8
const OUT_STOP_X := 43.61
const LIFT_DROP := 0.2
const SPROCKET_R := 0.1
const LINK_PITCH := 0.152
const CHAIN_SCENE := "res://game/assets/models/log_deck/log_deck_chain.glb"

@export var transfer_speed: float = 0.45
@export var feed_speed: float = 0.7
@export var turn_time: float = 1.8
@export var settle_time: float = 0.6
@export var drop_time: float = 0.9
## Board transfer chain top (y): the lift sets the pack down on it.
@export var transfer_top_y: float = -0.2
## How good the operator is, 0 = green, 1 = veteran: a veteran turns the next cant sooner.
## Not tied to the game yet.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
@export_group("Links")
## The board transfer under the outfeed (has_room()); the boards wait on the lift rolls.
@export var board_target_path: NodePath
## Prints each step (for demos).
@export var debug_log: bool = false

var xfer: Xfer = Xfer.EMPTY
var feed: Feed = Feed.EMPTY

var _board_target: Node
var _turner: Node3D
var _press: Array[Node3D] = []
var _press_rolls: Array[Node3D] = []
var _arbors: Array[Node3D] = []
var _chip_heads: Array[Node3D] = []
var _lift: Node3D
var _lift_rolls: Array[Node3D] = []
var _xfer_shafts: Array[Node3D] = []
var _lift_home: float = 0.0
var _lift_down: float = 1.0
var _press_amt: Array[float] = [0.0, 0.0]

var _cant: RigidBody3D = null           # on the transfer / turner
var _cant_start := Transform3D()
var _cant_goal := Transform3D()
var _feeding: RigidBody3D = null        # in the infeed and gang
var _cut_box: CSGBox3D = null
var _boards: Array[RigidBody3D] = []

var _front: float = 0.0
var _t: float = 0.0
var _wait: float = 0.0
var _xfer_travel: float = 0.0
var _sharp_travel: float = 0.0
var _saw_angle: float = 0.0
var _links: Array[MultiMesh] = []
var _dogs: MultiMesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_board_target = get_node_or_null(board_target_path)
	_turner = find_child("GR_Turner", true, false) as Node3D
	for i in 2:
		_press.append(find_child("GR_Press%d" % (i + 1), true, false) as Node3D)
		_press_rolls.append(find_child("GR_PressRoll%d" % (i + 1), true, false) as Node3D)
	for n in ["GR_TopArbor", "GR_BottomArbor"]:
		_arbors.append(find_child(n, true, false) as Node3D)
	for n in ["GR_ChipHeadNear", "GR_ChipHeadFar"]:
		_chip_heads.append(find_child(n, true, false) as Node3D)
	for n in ["GR_TransferTail", "GR_TransferHead"]:
		_xfer_shafts.append(find_child(n, true, false) as Node3D)
	_lift = find_child("GR_Lift", true, false) as Node3D
	if _lift:
		_lift_home = _lift.position.y
		var i := 1
		while true:
			var r := _lift.find_child("GR_ORoll%d" % i, true, false) as Node3D
			if r == null:
				break
			_lift_rolls.append(r)
			i += 1
	_build_chains()
	_set_lift(1.0)


## The headrig outfeed throws a cant over only while the transfer is empty.
func has_room() -> bool:
	return xfer == Xfer.EMPTY and _cant == null


## False unless the lift rolls are right down below the board transfer, so no board is sent
## into them.
func board_lane_clear() -> bool:
	return _lift_down >= 1.0


func _physics_process(delta: float) -> void:
	_run_transfer(delta)
	_run_feed(delta)
	_animate(delta)


# --- Transfer and turner -------------------------------------------------------------------

func _run_transfer(delta: float) -> void:
	match xfer:
		Xfer.EMPTY:
			var c := _find_cant()
			if c != null:
				_cant = c
				_freeze(c)
				xfer = Xfer.CARRY
				_log("cant on the transfer")
		Xfer.CARRY:
			if not is_instance_valid(_cant):
				_reset_transfer()
				return
			var p := _cant.global_position
			# The chains square the cant up against the stop as they bring it in.
			var target := Vector3(p.x, XFER_TOP_Y + CANT_R, STOP_CANT_Z)
			_cant.global_position = p.move_toward(target, transfer_speed * delta)
			_xfer_travel += transfer_speed * delta
			if _cant.global_position.distance_to(target) < 0.005:
				xfer = Xfer.AT_STOP
				_wait = lerpf(2.2, 0.6, operator_skill) * _rng.randf_range(0.8, 1.3)
		Xfer.AT_STOP:
			_wait -= delta
			if _wait <= 0.0 and feed == Feed.EMPTY and is_instance_valid(_cant):
				_cant_start = _cant.global_transform
				xfer = Xfer.TURN
				_t = 0.0
				_log("turning the cant onto the sharp chain")
			elif not is_instance_valid(_cant):
				_reset_transfer()
		Xfer.TURN:
			_t += delta / turn_time
			var a := deg_to_rad(90.0) * _ease(minf(_t, 1.0))
			_set_turner(rad_to_deg(a))
			_place_cant(_about_pivot(a) * _cant_start)
			if _t >= 1.0:
				_cant_goal = _sharp_pose(_cant.global_transform)
				_cant_start = _cant.global_transform
				xfer = Xfer.SETTLE
				_t = 0.0
		Xfer.SETTLE:
			_t += delta / settle_time
			var s := _ease(minf(_t, 1.0))
			_place_cant(_cant_start.interpolate_with(_cant_goal, s))
			_set_turner(90.0 * (1.0 - s))
			if _t >= 1.0:
				_feeding = _cant
				_cant = null
				_front = _feeding.global_position.x + CANT_HALF
				feed = Feed.FEED
				_reset_transfer()


func _reset_transfer() -> void:
	xfer = Xfer.EMPTY
	_cant = null
	_set_turner(0.0)


func _find_cant() -> RigidBody3D:
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := l.global_position
		if p.x > 29.5 and p.x < 36.0 and p.z > 5.9 and p.z < 8.2 and p.y > -0.4 and p.y < 0.8:
			return l
	return null


## Rotation about the turner shaft by angle a (over toward +Z).
func _about_pivot(a: float) -> Transform3D:
	var piv := Vector3(0.0, TURNER_PIVOT.y, TURNER_PIVOT.x)
	return Transform3D(Basis.IDENTITY, piv) * Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -piv)


## The cant squared up on the sharp chain: its length (log local X) along X, sawn faces (log
## local Z) up and down.
func _sharp_pose(now: Transform3D) -> Transform3D:
	var along := now.basis.x.normalized()
	along = Vector3.RIGHT if along.x >= 0.0 else Vector3.LEFT
	var faces := now.basis.z.normalized()
	var up := Vector3.UP if faces.y >= 0.0 else Vector3.DOWN
	var b := Basis(along, up.cross(along), up)
	return Transform3D(b, Vector3(now.origin.x, SHARP_TOP_Y + CANT_H * 0.5, LINE_Z))


func _place_cant(t: Transform3D) -> void:
	if is_instance_valid(_cant):
		_cant.global_transform = t


# --- Feed, gang and outfeed ------------------------------------------------------------------

func _run_feed(delta: float) -> void:
	match feed:
		Feed.FEED:
			if not is_instance_valid(_feeding):
				_finish_feed()
				return
			# The lift rolls come up for the boards once nothing is heading into them on the
			# transfer; the cant waits short of the saws until they are up.
			if _lift_down > 0.0 and _lane_clear(6.2, 9.4):
				_set_lift(maxf(_lift_down - delta / drop_time, 0.0))
			if _lift_down > 0.0 and _front >= SAW_X - 0.2:
				return
			_front += feed_speed * delta
			_sharp_travel += feed_speed * delta
			_feeding.global_position.x += feed_speed * delta
			if _front >= SAW_X and _boards.is_empty():
				_start_boards()
			_update_cut()
			_move_boards(_front)
			if _front - 2.0 * CANT_HALF >= SAW_X:
				_feeding.queue_free()
				_feeding = null
				_cut_box = null
				_show_boards_whole()
				feed = Feed.OUT
				_log("cant through the gang")
		Feed.OUT:
			_front = minf(_front + feed_speed * delta, OUT_STOP_X)
			_move_boards(_front)
			if _front >= OUT_STOP_X:
				var room: bool = _board_target == null or not _board_target.has_method("has_room") \
						or _board_target.has_room()
				if room and _lane_clear(7.4, 10.4):
					feed = Feed.DROP
					_t = 0.0
					_log("lift down, boards onto the transfer")
		Feed.DROP:
			# The pack rides down on the rolls, still on edge, until the transfer chains take it;
			# from there gravity and the moving chains tip the boards over, shingled.
			_t += delta / drop_time
			_set_lift(_ease(minf(_t, 1.0)))
			var roll_top := SHARP_TOP_Y - LIFT_DROP * _lift_down
			if not _boards.is_empty() and roll_top <= transfer_top_y:
				for b in _boards:
					_release_pack_board(b)
				_boards.clear()
			for b in _boards:
				if is_instance_valid(b):
					b.global_position.y = roll_top + 0.143
			if _t >= 1.0 and _boards.is_empty():
				_finish_feed()


func _finish_feed() -> void:
	feed = Feed.EMPTY
	_feeding = null
	_cut_box = null


func _start_boards() -> void:
	var scene := load("res://game/lumber/cut_board.tscn") as PackedScene
	var pitch := BOARD_T + KERF
	var half := N_BOARDS * pitch * 0.5
	for i in N_BOARDS:
		var b := scene.instantiate() as RigidBody3D
		b.nominal_size = "2x12"
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		_feeding.get_parent().add_child(b)
		b.add_collision_exception_with(_feeding)
		var z := LINE_Z - half + pitch * (i + 0.5)
		# On edge: the board's width (local Z) stands up.
		b.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, SHARP_TOP_Y + 0.143, z))
		_boards.append(b)
	for i in _boards.size():
		for j in range(i + 1, _boards.size()):
			_boards[i].add_collision_exception_with(_boards[j])
	_log("saws in, %d boards" % N_BOARDS)


## Boards ride with their front ends at x; while still coming out of the saws only the part
## past the saw line shows.
func _move_boards(x: float) -> void:
	for b in _boards:
		if not is_instance_valid(b):
			continue
		var length: float = b.product_length
		b.global_position.x = x - length * 0.5
		var mi := b.get_node_or_null("MeshInstance3D") as Node3D
		if mi:
			var shown := clampf((x - SAW_X) / length, 0.01, 1.0)
			mi.scale.x = shown
			mi.position.x = length * 0.5 * (1.0 - shown)


func _show_boards_whole() -> void:
	for b in _boards:
		var mi := b.get_node_or_null("MeshInstance3D") as Node3D
		if mi:
			mi.scale.x = 1.0
			mi.position.x = 0.0


## Hide the part of the cant that has gone through the chip heads.
func _update_cut() -> void:
	if not is_instance_valid(_feeding):
		return
	var core := _feeding.get_node_or_null("WoodCore") as CSGShape3D
	if core == null:
		return
	if _cut_box == null:
		_cut_box = CSGBox3D.new()
		_cut_box.name = "GangCut"
		_cut_box.operation = CSGShape3D.OPERATION_SUBTRACTION
		core.add_child(_cut_box)
	_cut_box.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(CHIP_X + 3.0, SHARP_TOP_Y + CANT_H * 0.5, LINE_Z))
	_cut_box.size = Vector3(6.0, 1.2, 1.2)


func _lane_clear(z0: float, z1: float) -> bool:
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var b := node as RigidBody3D
		if b == null or b.freeze or _boards.has(b):
			continue
		var p := b.global_position
		if p.x > 37.5 and p.x < 44.0 and p.z > z0 and p.z < z1 and p.y < 0.5:
			return false
	return true


## Hand one board of the pack to physics on the transfer chains: the pack touches again (the
## boards were kept apart while kinematic) and each gets a slight lean so they go over the
## same way, the way a gang pack folds over when the lift drops away.
func _release_pack_board(b: RigidBody3D) -> void:
	if not is_instance_valid(b):
		return
	for other in _boards:
		if other != b and is_instance_valid(other):
			b.remove_collision_exception_with(other)
	_release(b)
	b.angular_velocity = Vector3(_rng.randf_range(0.6, 1.4), 0.0, 0.0)


func _freeze(b: RigidBody3D) -> void:
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO


func _release(b: RigidBody3D) -> void:
	if not is_instance_valid(b):
		return
	b.freeze = false
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.sleeping = false


# --- Animation --------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	_saw_angle += delta * 40.0
	for a in _arbors:
		if a:
			a.rotation.z = -_saw_angle
	for h in _chip_heads:
		if h:
			h.rotation.y = _saw_angle * 0.8
	for s in _xfer_shafts:
		if s:
			s.rotation.x = _xfer_travel / SPROCKET_R
	# Press rolls come down on the cant while it is under them.
	for i in _press.size():
		var on := false
		if is_instance_valid(_feeding):
			var tail := _front - 2.0 * CANT_HALF
			on = PRESS_X[i] < _front + 0.1 and PRESS_X[i] > tail - 0.1
		_press_amt[i] = move_toward(_press_amt[i], 1.0 if on else 0.0, delta * 2.5)
		if _press[i]:
			_press[i].rotation.z = -deg_to_rad(PRESS_DEG) * _ease(_press_amt[i])
		if _press_rolls[i] and on:
			_press_rolls[i].rotation.z -= feed_speed * delta / 0.11
	var out_speed := feed_speed if feed == Feed.FEED or feed == Feed.OUT and _front < OUT_STOP_X else 0.0
	for r in _lift_rolls:
		r.rotation.z -= out_speed * delta / 0.075
	_update_chains()


func _set_turner(deg: float) -> void:
	if _turner:
		_turner.rotation.x = deg_to_rad(deg)


## 0 = rolls up (boards ride on them), 1 = down below the board transfer.
func _set_lift(down: float) -> void:
	_lift_down = down
	if _lift:
		_lift.position.y = _lift_home - LIFT_DROP * down


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _log(msg: String) -> void:
	if debug_log:
		print("[%s] %.1f s %s" % [name, Time.get_ticks_msec() / 1000.0, msg])


# --- Chains -----------------------------------------------------------------------------------

func _build_chains() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var link := src.find_child("LD_ChainLink", true, false) as MeshInstance3D
	var dog := src.find_child("LD_ChainDog", true, false) as MeshInstance3D
	for x in XFER_X:
		_links.append(_make_multimesh(link.mesh, _loop_links(XFER_Z.y - XFER_Z.x), "TransferChain"))
	var n := _loop_links(SHARP_X.y - SHARP_X.x)
	@warning_ignore("integer_division")
	var dogs := n / 3
	_links.append(_make_multimesh(link.mesh, n - dogs, "SharpChain"))
	_dogs = _make_multimesh(dog.mesh, dogs, "SharpChainDogs")
	src.free()
	_update_chains()


func _loop_links(run: float) -> int:
	return int((2.0 * run + TAU * SPROCKET_R) / LINK_PITCH)


func _make_multimesh(mesh: Mesh, count: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _update_chains() -> void:
	if _links.is_empty():
		return
	var run := XFER_Z.y - XFER_Z.x
	for k in XFER_X.size():
		var strand := _links[k]
		var xloop := 2.0 * run + TAU * SPROCKET_R
		for i in strand.instance_count:
			var s := fposmod(i * xloop / strand.instance_count + _xfer_travel, xloop)
			strand.set_instance_transform(i, _loop_frame(s, Vector3(XFER_X[k], XFER_TOP_Y - 0.02, XFER_Z.x),
					Vector3.BACK, run))
	run = SHARP_X.y - SHARP_X.x
	var loop := 2.0 * run + TAU * SPROCKET_R
	var mm := _links[XFER_X.size()]
	var total := mm.instance_count + _dogs.instance_count
	var li := 0
	var di := 0
	for i in total:
		var t := _loop_frame(fposmod(i * loop / total + _sharp_travel, loop),
				Vector3(SHARP_X.x, SHARP_TOP_Y - 0.02, LINE_Z), Vector3.RIGHT, run)
		if i % 3 == 0 and di < _dogs.instance_count:
			_dogs.set_instance_transform(di, t)
			di += 1
		elif li < mm.instance_count:
			mm.set_instance_transform(li, t)
			li += 1


## A link at distance s round a chain loop whose top run starts at `start` and runs `run`
## along `dir`; the link's +Y faces out of the loop.
func _loop_frame(s: float, start: Vector3, dir: Vector3, run: float) -> Transform3D:
	var c := start.y - SPROCKET_R
	var pos: Vector3
	var t: Vector3
	if s < run:
		pos = start + dir * s
		t = dir
	elif s < run + PI * SPROCKET_R:
		var a := (s - run) / SPROCKET_R
		pos = start + dir * (run + SPROCKET_R * sin(a))
		pos.y = c + SPROCKET_R * cos(a)
		t = dir * cos(a) + Vector3.DOWN * sin(a)
	elif s < 2.0 * run + PI * SPROCKET_R:
		pos = start + dir * (run - (s - run - PI * SPROCKET_R))
		pos.y = c - SPROCKET_R
		t = -dir
	else:
		var a := (s - 2.0 * run - PI * SPROCKET_R) / SPROCKET_R
		pos = start + dir * (-SPROCKET_R * sin(a))
		pos.y = c - SPROCKET_R * cos(a)
		t = -dir * cos(a) + Vector3.UP * sin(a)
	var across := dir.cross(Vector3.UP)
	var out := across.cross(t)
	return Transform3D(Basis(across, out, -t), pos)


## One line for debug HUDs.
func status_text() -> String:
	return "transfer %s, feed %s, lift %s" % [Xfer.keys()[xfer], Feed.keys()[feed],
			"down" if _lift_down >= 1.0 else ("up" if _lift_down <= 0.0 else "moving")]
