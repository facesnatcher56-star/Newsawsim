extends Node3D

## headrig_outfeed.gd
## Live roll case after the band headrig, with kicker arms.
##
## The model (game/assets/models/headrig_outfeed, built by dev/blender/headrig_outfeed) is in
## mill coordinates, like this node. Everything the headrig saws rides its outfeed rolls on
## down this roll case (+X):
##   - a slab reaching the kick zone is tipped off the -Z edge by the slab kickers and slides down
##     the skids onto the waste system's slab slasher (slab_target_path), which chops it for the
##     vibrating conveyors to the big chipper
##   - a cant reaching the same zone is thrown to +Z by the cant kickers to the gang resaw
##     (cant_target_path); with no gang linked it rides on and goes out like a board
##   - a board rides to the cushioned end stop and the board kickers throw it to +Z onto the
##     board transfer (board_target_path, has_room()) once there is room
## While a piece waits for its kicker or for room, the case stops.

enum Kick { IDLE, THROW, LOWER }

const CASE_X := Vector2(29.0, 43.6)
const CASE_Z := Vector2(4.8, 5.7)
const TOP_Y := -0.15
const ROLL_R := 0.1
const STOP_X := 43.45
## Slab and cant kick when the piece's centre passes this x (the middle of the kick zone).
const KICK_ZONE_X := 32.7
const KICK_DEG := 34.0
const CRANK := 0.28
## Kicker shaft pivots (z, y), arm x positions and the floor anchor of each cylinder.
const KICKERS := {
	"Slab": {"xs": [30.8, 32.0, 33.2, 34.4], "pivot": Vector2(4.60, -0.58)},
	"Cant": {"xs": [31.4, 32.6, 33.8, 35.0], "pivot": Vector2(5.90, -0.58)},
	"Board": {"xs": [39.2, 40.4, 41.6, 42.8], "pivot": Vector2(5.90, -0.58)},
}
## Slab path as (z, y offsets): lifted off the rolls, over the -Z edge, down the skids onto the
## slab slasher's chains (tops at y -0.45, so a slab's middle ends about 0.27 under where it was).
const SLAB_PATH := [Vector2(5.25, 0.0), Vector2(4.95, 0.12), Vector2(4.72, 0.02), Vector2(4.52, -0.17),
	Vector2(4.32, -0.27)]
## Board/cant path toward +Z: lifted, over the +Z edge and down the skid to the landing.
const BOARD_PATH := [Vector2(5.25, 0.0), Vector2(5.55, 0.14), Vector2(5.85, 0.06)]

@export var roll_speed: float = 1.4
@export_group("Kickers")
@export var throw_time: float = 1.1
@export var lower_time: float = 1.0
## Where boards land on the transfer, (z, y) of the board centre.
@export var board_landing: Vector2 = Vector2(6.6, -0.05)
## Where cants land at the gang resaw, (z, y) of the cant centre.
@export var cant_landing: Vector2 = Vector2(6.55, 0.03)
## How good the operator is, 0 = green, 1 = veteran: a veteran kicks a board sooner after it
## lands on the stop. Not tied to the game yet.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
@export_group("Links")
## The board transfer (has_room()); a board waits on the stop until it has room.
@export var board_target_path: NodePath
## The gang resaw infeed (has_room()); with none set, cants ride on like boards.
@export var cant_target_path: NodePath
## The waste system's slab slasher (slab_room()); a slab waits in the kick zone until it is clear.
@export var slab_target_path: NodePath
## Prints kicks (for demos).
@export var debug_log: bool = false

## True while the case is stopped with a piece waiting.
var is_holding: bool = false

@onready var _case: StaticBody3D = $Case

var _board_target: Node
var _cant_target: Node
var _rolls: Array[Node3D] = []
var _kick := {}
var _slab_target: Node
var _roll_spin: float = 0.0
var _case_speed: float = 0.0
var _board_wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_board_target = get_node_or_null(board_target_path)
	_cant_target = get_node_or_null(cant_target_path)
	_slab_target = get_node_or_null(slab_target_path)
	var i := 1
	while true:
		var r := find_child("HO_Roll%d" % i, true, false) as Node3D
		if r == null:
			break
		_rolls.append(r)
		i += 1
	for k in KICKERS:
		var spec: Dictionary = KICKERS[k]
		var xs: Array = spec["xs"]
		var pivot: Vector2 = spec["pivot"]
		_kick[k] = {
			"node": find_child("HO_%sKick" % k, true, false),
			"cyl": find_child("HO_%sCyl" % k, true, false),
			"rod": find_child("HO_%sRod" % k, true, false),
			# +1 when the arms reach toward +Z, i.e. the piece goes off toward -Z.
			"side": 1.0 if pivot.x < (CASE_Z.x + CASE_Z.y) * 0.5 else -1.0,
			"pin": Vector3(xs[0] - 0.42 + 0.05 - (xs[0] + xs[xs.size() - 1]) * 0.5, -CRANK, 0.0),
			"state": Kick.IDLE, "t": 0.0, "piece": null, "path": PackedVector3Array(), "q0": Quaternion(),
			"roll": 0.0, "deg": 0.0,
		}
		_set_kicker(k, 0.0)


func _physics_process(delta: float) -> void:
	var pieces := _case_pieces()
	var hold := false
	for p in pieces:
		var kind := _kind(p)
		var x := p.global_position.x
		if kind == "Slab" or kind == "Cant":
			if x >= KICK_ZONE_X:
				if _kick[kind]["state"] == Kick.IDLE and _landing_clear(kind):
					_start_throw(kind, p)
				else:
					hold = true
		else:
			var front := x + _half_length(p)
			if front >= STOP_X - 0.06 and p.linear_velocity.length() < 0.15:
				_board_wait -= delta
				var room: bool = _board_target == null or not _board_target.has_method("has_room") \
						or _board_target.has_room()
				# The gang's outfeed lift rolls cross the board transfer; never throw into them.
				if _cant_target != null and _cant_target.has_method("board_lane_clear"):
					room = room and _cant_target.board_lane_clear()
				if _kick["Board"]["state"] == Kick.IDLE and room and _board_wait <= 0.0:
					_start_throw("Board", p)
					_board_wait = lerpf(2.0, 0.6, operator_skill) * _rng.randf_range(0.8, 1.3)
				elif not room:
					hold = true
	is_holding = hold
	_case_speed = 0.0 if hold else roll_speed
	_case.constant_linear_velocity = Vector3(_case_speed, 0.0, 0.0)
	for k in _kick:
		_run_kicker(k, delta)


# --- Pieces on the case ------------------------------------------------------------------------

func _case_pieces() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for group in ["cut_boards", "logs"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as RigidBody3D
			if b == null or b.freeze or out.has(b):
				continue
			var p := b.global_position
			if p.x > CASE_X.x and p.x < CASE_X.y and absf(p.z - 5.25) < 0.7 and p.y > TOP_Y - 0.1 and p.y < 0.7:
				out.append(b)
	return out


## True if no piece lies on the rolls anywhere between x0 and x1: the headrig asks before it
## saws (products drop under the saw) or sets a cant out, so wood never lands on wood.
func zone_clear(x0: float, x1: float) -> bool:
	for p in _case_pieces():
		var half := _half_length(p)
		if p.global_position.x + half > x0 and p.global_position.x - half < x1:
			return false
	return true


func _kind(b: Node) -> String:
	if b.is_in_group("cut_slabs"):
		return "Slab"
	if b.is_in_group("logs"):
		return "Cant" if _cant_target != null else "Board"
	return "Board"


func _half_length(b: Node) -> float:
	if "product_length" in b:
		return b.product_length * 0.5
	return 2.46


## A slab is kicked only when the slasher has room for it; a cant only when the gang has room.
func _landing_clear(kind: String) -> bool:
	if kind == "Cant":
		return not _cant_target.has_method("has_room") or _cant_target.has_room()
	return _slab_target == null or not _slab_target.has_method("slab_room") or _slab_target.slab_room()


# --- Kickers -----------------------------------------------------------------------------------

func _start_throw(k: String, p: RigidBody3D) -> void:
	var kk: Dictionary = _kick[k]
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.freeze = true
	var start := p.global_position
	var path := PackedVector3Array()
	if k == "Slab":
		for v: Vector2 in SLAB_PATH:
			path.append(Vector3(start.x, start.y + v.y, v.x if v != SLAB_PATH[0] else start.z))
	else:
		var landing := cant_landing if k == "Cant" else board_landing
		for v: Vector2 in BOARD_PATH:
			path.append(Vector3(start.x, start.y + v.y, v.x if v != BOARD_PATH[0] else start.z))
		path.append(Vector3(start.x, landing.y, landing.x))
	kk["piece"] = p
	kk["path"] = path
	kk["q0"] = p.global_basis.get_rotation_quaternion()
	# Tipped toward the side it goes off: slabs roll to -Z, the rest to +Z.
	kk["roll"] = deg_to_rad(28.0) * (1.0 if k == "Slab" else -1.0)
	kk["state"] = Kick.THROW
	kk["t"] = 0.0
	if debug_log:
		print("[%s] %.1f s %s kick at x %.2f" % [name, Time.get_ticks_msec() / 1000.0, k, start.x])


func _run_kicker(k: String, delta: float) -> void:
	var kk: Dictionary = _kick[k]
	match kk["state"]:
		Kick.THROW:
			kk["t"] += delta / throw_time
			var t := minf(kk["t"], 1.0)
			# The arms swing up through the first half; the piece follows them over the edge and
			# drops the rest of the way.
			_set_kicker(k, KICK_DEG * _ease(minf(t * 1.6, 1.0)))
			_move_piece(kk, t * t * (2.0 - t))
			if t >= 1.0:
				_release(kk["piece"])
				kk["piece"] = null
				kk["state"] = Kick.LOWER
				kk["t"] = 0.0
		Kick.LOWER:
			kk["t"] += delta / lower_time
			_set_kicker(k, KICK_DEG * (1.0 - _ease(minf(kk["t"], 1.0))))
			if kk["t"] >= 1.0:
				kk["state"] = Kick.IDLE


func _move_piece(kk: Dictionary, s: float) -> void:
	var p := kk["piece"] as RigidBody3D
	if not is_instance_valid(p):
		return
	var path: PackedVector3Array = kk["path"]
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var left := s * total
	var pos := path[path.size() - 1]
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if left <= seg:
			pos = path[i - 1].lerp(path[i], left / maxf(seg, 0.001))
			break
		left -= seg
	# Tip up while on the arms, settle flat again where it lands.
	var tip: float = kk["roll"] * sin(PI * clampf(s * 1.3, 0.0, 1.0))
	var q := Quaternion(Vector3.RIGHT, tip) * (kk["q0"] as Quaternion)
	p.global_transform = Transform3D(Basis(q), pos)


func _release(p: RigidBody3D) -> void:
	if not is_instance_valid(p):
		return
	p.freeze = false
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	p.sleeping = false


func _set_kicker(k: String, deg: float) -> void:
	var kk: Dictionary = _kick[k]
	kk["deg"] = deg
	var node := kk["node"] as Node3D
	if node == null:
		return
	node.rotation.x = -kk["side"] * deg_to_rad(deg)
	var pin := node.global_transform * (kk["pin"] as Vector3)
	for part in ["cyl", "rod"]:
		var n := kk[part] as Node3D
		if n == null:
			continue
		var d := pin - n.global_position
		var b := Basis.looking_at(d.normalized(), Vector3.RIGHT)
		if part == "rod":
			b = b * Basis.from_scale(Vector3(1.0, 1.0, d.length()))
		n.global_basis = b


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)



# --- Animation --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Top of the rolls moves +X with the wood: about -Z. Drawn per frame, capped (RollSpin).
	_roll_spin += RollSpin.step(-_case_speed / ROLL_R, delta)
	for r in _rolls:
		r.rotation.z = _roll_spin


## One line for debug HUDs.
func status_text() -> String:
	var ks := []
	for k in _kick:
		if _kick[k]["state"] != Kick.IDLE:
			ks.append(k.to_lower())
	return "case %.1f m/s%s, kicking %s" % [_case_speed, " (holding)" if is_holding else "",
			", ".join(ks) if not ks.is_empty() else "-"]
