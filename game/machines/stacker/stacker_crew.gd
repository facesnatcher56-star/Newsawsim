class_name StackerCrew
extends Node3D

## The green stacker's crew: an operator console with a stack light and two workers.
##
## - Jam eyes: the moment the stacker reports a jam (a twisted board, a board riding another,
##   a board off the line, a stalled layer) the line stops itself (lockout) and the stack
##   light goes red, so a jam never grows into a pile-up. The sorter holds its packs meanwhile.
## - Every board that has to be dealt with goes on one list, and both workers work through it
##   together, one board at a time each, nearest first: the catwalk worker (posted on the +Z
##   catwalk) and the operator (at the console). A board on the infeed is reached from the
##   catwalk and squared up, put back upstream, or set aside on the holdover rack; a board on
##   the floor is carried to the unscrambler pocket and put in. Whoever is free helps, going
##   down or up the catwalk stair if the board is on the other level.
## - A board is never pulled out from under others: whatever lies on it comes off first, and a
##   board in a worker's hands is out of everything's way until it is set down.
## - When the list is done they go back to their posts and the operator restarts the line at
##   the console. If the same jam keeps coming back (three fixes in a row), they leave the line
##   locked out and the console says to call maintenance, instead of looping.
##
## Workers walk on the catwalk at catwalk height, on the catwalk stair, and on the floor along
## aisles laid out clear of the stair, console and line. Positions are in the stacker's frame
## (stacker_build.py).

const MillWorkerScript := preload("res://game/characters/mill_worker.gd")

@export var stacker: NodePath
@export var log_events: bool = false
## How fast the crew walks, metres per second.
@export_range(0.5, 4.0, 0.1) var walk_speed: float = 2.0
## Seconds a worker takes to lift a board and set it down where it belongs.
@export_range(0.2, 3.0, 0.05) var hand_time: float = 0.5

const CONSOLE := Vector3(23.0, 0.0, 5.4)
const OPERATOR := Vector3(23.0, 0.0, 6.05)
const STACK_LIGHT := Vector3(24.0, 0.0, 5.0)
const AISLE_Z := 6.4                           # floor aisle along the +Z side, outside the console
const FAR_AISLE_Z := -6.4                      # floor aisle along the -Z side
const END_X := 38.2                            # round the outfeed's head end
const REACH_Z := 4.2                           # stand this far out to reach a board on the floor
const CATWALK := Vector3(27.5, 2.45, 3.5)      # catwalk worker's post
const CATWALK_X := Vector2(25.3, 30.7)
const POCKET_SIDE := Vector3(21.3, 0.0, 4.2)   # floor beside the pocket, clear of the stair
const STAIR_TOP := Vector3(24.95, 2.45, 3.5)   # +Z catwalk stair (runs down toward -X)
const STAIR_FOOT := Vector3(21.55, 0.0, 3.5)
const STAIR_OUT := Vector3(21.35, 0.0, 4.6)    # off the bottom step, toward the aisle
const JAM_CONFIRM := 0.5
const MAX_REPEATS := 3

enum St { RUNNING, LOCKED, FIXING, RESTARTING, HALTED }

var _stacker: Node3D
var _operator: Node3D
var _catwalker: Node3D
var _state: int = St.RUNNING
var _jam: Dictionary = {}
var _jam_t: float = 0.0
var _t: float = 0.0
var _repeats: int = 0
var _last_kind: String = ""
var _queue: Array[RigidBody3D] = []            # boards still to deal with, shared by both workers
var _hands: Array[Hand] = []


## One worker at work: the board he has taken on and how far he is with it.
class Hand:
	var worker: Node3D
	var title: String
	var up: bool                 # on the catwalk (else on the floor)
	var board: RigidBody3D
	var stage: int = 0
	var from: Transform3D
	var to: Transform3D
	var t: float = -1.0          # hands-on move under way, 0..1
	var moved: int = 0

	func _init(w: Node3D, p_title: String, p_up: bool) -> void:
		worker = w
		title = p_title
		up = p_up
var _screen: Label3D
var _lamps: Array[MeshInstance3D] = []
var _cleared: int = 0


func _ready() -> void:
	if not stacker.is_empty():
		_stacker = get_node_or_null(stacker) as Node3D
	if _stacker == null:
		push_warning("StackerCrew: no stacker")
		return
	_build.call_deferred()


func _s(p: Vector3) -> Vector3:
	return _stacker.to_global(p)


func _l(n: Node3D) -> Vector3:
	return _stacker.to_local(n.global_position)


func _log(text: String) -> void:
	if log_events:
		print("[Crew] " + text)


# ─────────────────────────────────────────────────────────────────────────────
#  CONSOLE AND WORKERS
# ─────────────────────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Node3D.new()
	root.name = "OperatorConsole"
	get_parent().add_child(root)
	root.global_transform = Transform3D(_stacker.global_basis, _s(CONSOLE))
	var grey := _mat(Color(0.55, 0.57, 0.6), 0.5)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.4)
	_mesh(root, _box(Vector3(1.4, 0.95, 0.6)), grey, Vector3(0.0, 0.475, 0.0))
	var panel := _mesh(root, _box(Vector3(1.4, 0.05, 0.45)), dark, Vector3(0.0, 1.0, 0.08))
	panel.rotation.x = deg_to_rad(25.0)
	_mesh(root, _box(Vector3(0.8, 0.5, 0.06)), dark, Vector3(-0.15, 1.35, -0.2))
	_screen = Label3D.new()
	_screen.font_size = 40
	_screen.pixel_size = 0.0015
	_screen.position = Vector3(-0.15, 1.35, -0.165)
	root.add_child(_screen)
	var stop := CylinderMesh.new()
	stop.top_radius = 0.05
	stop.bottom_radius = 0.06
	stop.height = 0.05
	_mesh(root, stop, _mat(Color(0.9, 0.05, 0.03), 0.3), Vector3(0.5, 1.07, 0.15))
	var go := CylinderMesh.new()
	go.top_radius = 0.035
	go.bottom_radius = 0.035
	go.height = 0.03
	_mesh(root, go, _mat(Color(0.05, 0.7, 0.1), 0.3), Vector3(0.32, 1.05, 0.15))
	var pole_root := Node3D.new()
	get_parent().add_child(pole_root)
	pole_root.global_transform = Transform3D(_stacker.global_basis, _s(STACK_LIGHT))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 2.4
	_mesh(pole_root, pole, grey, Vector3(0.0, 1.2, 0.0))
	for i in 3:
		var lamp := CylinderMesh.new()
		lamp.top_radius = 0.07
		lamp.bottom_radius = 0.07
		lamp.height = 0.12
		var colour: Color = [Color(0.1, 0.9, 0.2), Color(1.0, 0.6, 0.05), Color(1.0, 0.08, 0.05)][i]
		var m := _mat(colour, 0.3)
		m.emission_enabled = true
		m.emission = colour
		_lamps.append(_mesh(pole_root, lamp, m, Vector3(0.0, 2.45 + i * 0.13, 0.0)))
	_operator = MillWorkerScript.new()
	_operator.set("walk_speed", walk_speed)
	_operator.name = "StackerOperator"
	get_parent().add_child(_operator)
	_operator.global_position = _s(OPERATOR)
	_operator.call("face", _s(CONSOLE))
	_catwalker = MillWorkerScript.new()
	_catwalker.set("walk_speed", walk_speed)
	_catwalker.name = "StackerCatwalkWorker"
	get_parent().add_child(_catwalker)
	_catwalker.global_position = _s(CATWALK)
	_catwalker.call("face", _s(Vector3(CATWALK.x, CATWALK.y, 0.0)))
	_hands = [Hand.new(_operator, "operator", false), Hand.new(_catwalker, "catwalk worker", true)]
	_status(0, "STACKER\nRUNNING", Color(0.3, 1.0, 0.4))


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


## Stack light: 0 green (running), 1 amber (being cleared), 2 red (jam / halted).
func _status(light: int, text: String, colour: Color) -> void:
	for i in _lamps.size():
		(_lamps[i].material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if i == light else 0.0
	if _screen != null:
		_screen.text = text
		_screen.modulate = colour


# ─────────────────────────────────────────────────────────────────────────────
#  ROUTES (each worker on his own surface)
# ─────────────────────────────────────────────────────────────────────────────

## Catwalk worker: along the catwalk's centre line to x (he stays at catwalk height).
func _catwalk_route(x: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(_s(Vector3(clampf(x, CATWALK_X.x, CATWALK_X.y), CATWALK.y, CATWALK.z)))
	return pts


## On the floor from `here`: out to the aisle, along it, round the outfeed end if the target is
## on the far side, and in to stand beside the target.
func _floor_route(x: float, z: float, here: Vector3 = Vector3.INF) -> PackedVector3Array:
	if here == Vector3.INF:
		here = _l(_operator)
	var near_side: bool = here.z > 0.0
	var pts := PackedVector3Array()
	var aisle: float = AISLE_Z if near_side else FAR_AISLE_Z
	pts.append(_s(Vector3(here.x, 0.0, aisle)))
	if (z > 0.0) != near_side:
		pts.append(_s(Vector3(END_X, 0.0, aisle)))
		aisle = FAR_AISLE_Z if near_side else AISLE_Z
		pts.append(_s(Vector3(END_X, 0.0, aisle)))
	pts.append(_s(Vector3(x, 0.0, aisle)))
	pts.append(_s(Vector3(x, 0.0, z)))
	return pts


func _home_route() -> PackedVector3Array:
	return _floor_route(OPERATOR.x, OPERATOR.z)


## From the floor up the catwalk stair and along the catwalk to x.
func _up_route(h: Hand, x: float) -> PackedVector3Array:
	var pts := _floor_route(STAIR_OUT.x, STAIR_OUT.z, _l(h.worker))
	pts.append(_s(STAIR_FOOT))
	pts.append(_s(STAIR_TOP))
	pts.append_array(_catwalk_route(x))
	h.up = true
	return pts


## From the catwalk down its stair, then on the floor to (x, z).
func _down_route(h: Hand, x: float, z: float) -> PackedVector3Array:
	var pts := _catwalk_route(STAIR_TOP.x + 0.3)
	pts.append(_s(STAIR_TOP))
	pts.append(_s(STAIR_FOOT))
	pts.append(_s(STAIR_OUT))
	pts.append_array(_floor_route(x, z, STAIR_OUT))
	h.up = false
	return pts


# ─────────────────────────────────────────────────────────────────────────────
#  JOB
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _stacker == null or _operator == null:
		return
	_t += delta
	for h: Hand in _hands:
		_run_hand_move(h, delta)
	match _state:
		St.RUNNING:
			var jam: Dictionary = _stacker.call("find_jam")
			if jam.is_empty():
				_jam_t = 0.0
				if _t > 30.0:
					_repeats = 0            # a good stretch: the next jam starts a fresh count
				return
			_jam_t += delta
			if _jam_t < JAM_CONFIRM:
				return
			# Jam eyes trip: the line stops itself at once.
			_stacker.call("set_locked", true)
			_t = 0.0
			_jam = jam
			# Setting aside or filling a short layer, or putting back an extra board, is routine, not a repeat.
			var routine: bool = jam["kind"] in ["short", "extra", "fill"]
			_repeats = 0 if routine else (_repeats + 1 if jam["kind"] == _last_kind else 1)
			_last_kind = jam["kind"]
			if _repeats > MAX_REPEATS:
				_state = St.HALTED
				_status(2, "LOCKED OUT\nrepeated %s jam\ncall maintenance" % _last_kind, Color(1.0, 0.25, 0.2))
				_log("halted: %s jam came back %d times" % [_last_kind, _repeats - 1])
				return
			_status(2, "JAM\n%s board" % _jam["kind"], Color(1.0, 0.25, 0.2))
			_log("jam: %s at %s, line stopped" % [_jam["kind"], str(_jam["at"])])
			_dispatch()
		St.FIXING:
			var busy: bool = false
			for h: Hand in _hands:
				if h.t < 0.0 and not bool(h.worker.call("is_walking")):
					_work(h)
				if h.board != null or h.t >= 0.0 or bool(h.worker.call("is_walking")):
					busy = true
			if not busy and _queue.is_empty():
				_finish()
		St.RESTARTING:
			if not bool(_operator.call("is_walking")) and _t > 0.0:
				_operator.call("face", _s(CONSOLE))
				_operator.call("set_reach", true)
				if _t > 0.4:
					_operator.call("set_reach", false)
					_stacker.call("set_locked", false)
					_cleared += 1
					_status(0, "STACKER\nRUNNING", Color(0.3, 1.0, 0.4))
					_log("line restarted (%d jams cleared)" % _cleared)
					_state = St.RUNNING
					_jam_t = 0.0
					_t = 0.0
			else:
				_t = 0.0


func _dispatch() -> void:
	_queue.clear()
	_status(1, "LOCKED OUT\nclearing %s" % _jam["kind"], Color(1.0, 0.7, 0.1))
	if _jam["kind"] in ["dropped", "rider", "twisted"]:
		_queue.append(_jam["board"])            # just that board (and whatever lies on it)
	elif _jam.has("boards"):
		_queue.assign(_jam["boards"])       # a layer that can't go: extras back, or a short layer aside
	else:
		_queue = _stacker.call("straighten_infeed")
	for h: Hand in _hands:
		h.moved = 0
	_state = St.FIXING


## How far a worker has to go to get to a board: straight-line distance, plus the stair if
## the board is on the other level, plus the way round the outfeed end if a floor board can't
## be reached from his side, plus a bit if he still has a board of his own to finish.
func _cost(h: Hand, b: RigidBody3D) -> float:
	var at: Vector3 = _l(h.worker)
	var p: Vector3 = _l(b)
	var d: float = Vector2(at.x - p.x, at.z - p.z).length()
	var on_floor: bool = p.y < 1.0
	if on_floor == h.up:
		d += 8.0
	if on_floor and not h.up and not _reachable_from(b, signf(at.z)):
		d += 2.0 * absf(END_X - p.x) + 12.0
	if h.board != null or h.t >= 0.0:
		d += 4.0
	return d


## Can a worker standing on this side (+1 / -1 in Z) get at the board? Yes if its near end
## comes this side of the machine's centre line: he reaches in and pulls it out by that end.
func _reachable_from(b: RigidBody3D, side: float) -> bool:
	var p: Vector3 = _l(b)
	var axis: Vector3 = _stacker.global_basis.inverse() * b.global_basis.x
	var half: float = absf(axis.normalized().z) * float(b.get("product_length")) * 0.5 + float(b.get("board_width")) * 0.5
	return side * p.z + half > 0.5


## Where a worker on the floor stands to pick up a board: on his own side when he can reach
## it from there, else on the far side.
func _reach_z(h: Hand, b: RigidBody3D) -> float:
	var side: float = signf(_l(h.worker).z) if not h.up else 1.0
	if side == 0.0:
		side = 1.0
	return side * REACH_Z if _reachable_from(b, side) else -side * REACH_Z


## The next board for this worker: the nearest one on the list that no other worker could get
## to sooner (so nobody waits on a worker walking over from further away), or if something
## lies on it, the board on top. Nothing if every board left is someone else's to take.
func _claim(h: Hand) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d: float = INF
	for b: RigidBody3D in _queue:
		if not is_instance_valid(b):
			continue
		var d: float = _cost(h, b)
		var mine: bool = true
		for o: Hand in _hands:
			if o != h and _cost(o, b) < d:
				mine = false
		if mine and d < best_d:
			best_d = d
			best = b
	for i in range(_queue.size() - 1, -1, -1):
		if not is_instance_valid(_queue[i]):
			_queue.remove_at(i)
	if best == null:
		return null
	for i in 4:
		var tops: Array[RigidBody3D] = MillWorkerScript.boards_on(best)
		if tops.is_empty():
			break
		best = tops[0]
	for o: Hand in _hands:
		if o != h and o.board == best:
			return null              # the other worker has it (or is lifting what lies on it)
	_queue.erase(best)
	return best


func _work(h: Hand) -> void:
	if h.board == null or not is_instance_valid(h.board):
		h.board = _claim(h)
		h.stage = 0
		if h.board == null:
			return
	var b: RigidBody3D = h.board
	var p: Vector3 = _l(b)
	if h.stage == 0 and p.y < 1.0:
		# On the floor: walk to it (down the stair if on the catwalk), shoulder it, carry it to
		# the pocket side and put it in.
		var z: float = _reach_z(h, b)
		h.worker.call("walk", _down_route(h, p.x, z) if h.up else _floor_route(p.x, z, _l(h.worker)))
		h.stage = 1
		return
	match h.stage:
		1:
			h.worker.call("face", b.global_position)
			h.worker.call("shoulder", b)
			h.worker.call("walk", _floor_route(POCKET_SIDE.x, POCKET_SIDE.z, _l(h.worker)))
			h.stage = 2
		2:
			h.worker.call("drop_carry")
			h.worker.call("set_reach", true)
			_hand_move(h, b, _stacker.call("put_back_spot", b))
		_:
			# On the line: from the catwalk, opposite the board, reach over.
			var stand: float = clampf(p.x, CATWALK_X.x, CATWALK_X.y)
			if not h.up:
				h.worker.call("walk", _up_route(h, stand))
				return
			if absf(_l(h.worker).x - stand) > 0.6:
				h.worker.call("walk", _catwalk_route(stand))
				return
			h.worker.call("face", b.global_position)
			h.worker.call("set_reach", true)
			MillWorkerScript.lift_clear(b)
			_hand_move(h, b, _stacker.call("fix_spot", b) if _jam.has("boards") else _square_in_place(b))


func _finish() -> void:
	var by: PackedStringArray = []
	for h: Hand in _hands:
		h.worker.call("set_reach", false)
		if h.moved > 0:
			by.append("%s %d" % [h.title, h.moved])
	# Back to their posts; the operator restarts the line once he's at the console.
	_operator.call("walk", _down_route(_hands[0], OPERATOR.x, OPERATOR.z) if _hands[0].up else _home_route())
	_catwalker.call("walk", _catwalk_route(CATWALK.x) if _hands[1].up else _up_route(_hands[1], CATWALK.x))
	_state = St.RESTARTING
	_t = 0.0
	_log("%s cleared (%s)" % [_jam["kind"], ", ".join(by) if not by.is_empty() else "nothing to move"])


func _square_in_place(b: RigidBody3D) -> Transform3D:
	var p: Vector3 = _l(b)
	var t: float = float(b.get("board_thickness"))
	var length: float = float(b.get("product_length"))
	if p.y > 2.6 + t * 0.5 + 0.025 or p.x < 25.6:
		return _stacker.call("put_back_spot", b)
	return _stacker.global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(p.x, 2.6 + t * 0.5 + 0.003, -2.48 + length * 0.5))


func _hand_move(h: Hand, b: RigidBody3D, to: Transform3D) -> void:
	MillWorkerScript.lift_clear(b)
	h.from = b.global_transform
	h.to = to
	h.t = 0.0


## Hands-on move: lift, carry across, set down; the board is free again afterwards.
func _run_hand_move(h: Hand, delta: float) -> void:
	if h.t < 0.0:
		return
	h.t += delta / hand_time
	var u: float = clampf(h.t, 0.0, 1.0)
	var b: RigidBody3D = h.board
	if is_instance_valid(b):
		var t: Transform3D = h.from.interpolate_with(h.to, u * u * (3.0 - 2.0 * u))
		t.origin.y += sin(u * PI) * 0.2
		b.global_transform = t
		if u >= 1.0:
			MillWorkerScript.set_down(b)
			b.freeze = false
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
	if u >= 1.0:
		h.t = -1.0
		h.board = null
		h.moved += 1
		h.worker.call("set_reach", false)
