extends Node3D

## headrig_outfeed.gd
## Live roll case after the band headrig, with kicker arms, a slab conveyor and a drum chipper.
##
## The model (game/assets/models/headrig_outfeed, built by dev/blender/headrig_outfeed) is in
## mill coordinates, like this node. Everything the headrig saws rides its outfeed rolls on
## down this roll case (+X):
##   - a slab reaching the kick zone is tipped off the -Z edge by the slab kickers, slides down
##     the skids into the trough and the flight chain carries it end-first into the chipper
##   - a cant reaching the same zone is thrown to +Z by the cant kickers to the gang resaw
##     (cant_target_path); with no gang linked it rides on and goes out like a board
##   - a board rides to the cushioned end stop and the board kickers throw it to +Z onto the
##     board transfer (board_target_path, has_room()) once there is room
## While a piece waits for its kicker or for room, the case stops.
##
## The chipper's top feed roll pulls each slab in; now and then one hangs up in the throat and
## the feed roll backs it out and takes it again.

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
## Slab trough and its flight chain.
const TROUGH_X := Vector2(29.4, 44.5)
const TROUGH_Z := Vector2(3.55, 4.20)
const TROUGH_FLOOR_Y := -0.86
const SPROCKET_R := 0.12
const FLIGHT_PITCH := 0.6
## Slab path as (z, y) offsets: lifted off the rolls, over the -Z edge, down the skid, into the trough.
const SLAB_PATH := [Vector2(5.25, 0.0), Vector2(4.95, 0.12), Vector2(4.72, 0.02), Vector2(4.25, -0.38),
	Vector2(3.875, -0.62)]
## Board/cant path toward +Z: lifted, over the +Z edge and down the skid to the landing.
const BOARD_PATH := [Vector2(5.25, 0.0), Vector2(5.55, 0.14), Vector2(5.85, 0.06)]
## Chipper.
const CHIP_MOUTH_X := 44.55
const DRUM_X := 46.25
const FEED_ROLL_R := 0.2

@export var roll_speed: float = 1.4
@export var trough_speed: float = 0.9
@export var feed_speed: float = 0.8
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
## Chance per slab that it hangs up in the chipper throat and has to be backed out.
@export var jam_chance: float = 0.08
@export_group("Links")
## The board transfer (has_room()); a board waits on the stop until it has room.
@export var board_target_path: NodePath
## The gang resaw infeed (has_room()); with none set, cants ride on like boards.
@export var cant_target_path: NodePath
## Prints kicks and chipping (for demos).
@export var debug_log: bool = false

## True while the case is stopped with a piece waiting.
var is_holding: bool = false

@onready var _case: StaticBody3D = $Case
@onready var _trough: StaticBody3D = $Trough

var _board_target: Node
var _cant_target: Node
var _rolls: Array[Node3D] = []
var _kick := {}
var _head: Node3D
var _tail: Node3D
var _feed_roll: Node3D
var _flights: MultiMesh
var _loop_len: float = 0.0
var _roll_travel: float = 0.0
var _chain_travel: float = 0.0
var _feed_travel: float = 0.0
var _case_speed: float = 0.0
var _board_wait: float = 0.0
var _chipping: RigidBody3D = null
var _jam_timer: float = 0.0
var _chipped: int = 0
var _dust: CPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_board_target = get_node_or_null(board_target_path)
	_cant_target = get_node_or_null(cant_target_path)
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
	_head = find_child("HO_TroughHead", true, false) as Node3D
	_tail = find_child("HO_TroughTail", true, false) as Node3D
	_feed_roll = find_child("HO_FeedRoll", true, false) as Node3D
	_build_flights()
	_build_dust()
	_trough.constant_linear_velocity = Vector3(trough_speed, 0.0, 0.0)


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
	_run_chipper(delta)
	_animate(delta)


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


## A slab lands in the trough only when the stretch under the kick zone is clear; a cant only
## when the gang has room.
func _landing_clear(kind: String) -> bool:
	if kind == "Cant":
		return not _cant_target.has_method("has_room") or _cant_target.has_room()
	for node in get_tree().get_nodes_in_group("cut_slabs"):
		var s := node as RigidBody3D
		if s == null or s.freeze:
			continue
		var p := s.global_position
		if absf(p.z - 3.875) < 0.5 and p.y < -0.5 and absf(p.x - KICK_ZONE_X) < 4.9:
			return false
	return true


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


# --- Chipper -----------------------------------------------------------------------------------

func _run_chipper(delta: float) -> void:
	if _chipping == null:
		for node in get_tree().get_nodes_in_group("cut_slabs"):
			var s := node as RigidBody3D
			if s == null or s.freeze:
				continue
			var p := s.global_position
			if absf(p.z - 3.875) < 0.5 and p.y < -0.3 and p.x + _half_length(s) > CHIP_MOUTH_X + 0.15:
				_chipping = s
				s.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				s.freeze = true
				# Square it up in the throat under the feed roll.
				s.global_position = Vector3(s.global_position.x, TROUGH_FLOOR_Y + 0.07, 3.875)
				if _rng.randf() < jam_chance:
					_jam_timer = _rng.randf_range(1.5, 3.0)
				break
		return
	if not is_instance_valid(_chipping):
		_chipping = null
		return
	var v := feed_speed
	if _jam_timer > 0.0:
		# Hung up: the feed roll stalls, then backs the slab out a little before taking it again.
		_jam_timer -= delta
		v = 0.0 if _jam_timer > 0.8 else -0.4
		if _jam_timer <= 0.0 and debug_log:
			print("[%s] %.1f s slab backed out of the chipper throat" % [name, Time.get_ticks_msec() / 1000.0])
	_chipping.global_position.x += v * delta
	_feed_travel += v * delta
	if _dust:
		_dust.emitting = v > 0.0
	if _chipping.global_position.x - _half_length(_chipping) > DRUM_X - 0.3:
		_chipping.queue_free()
		_chipping = null
		if _dust:
			_dust.emitting = false
		_chipped += 1
		if debug_log:
			print("[%s] %.1f s slab chipped (%d)" % [name, Time.get_ticks_msec() / 1000.0, _chipped])


# --- Animation --------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	_roll_travel += _case_speed * delta
	for r in _rolls:
		r.rotation.z = -_roll_travel / ROLL_R
	_chain_travel += trough_speed * delta
	var a := -_chain_travel / SPROCKET_R
	if _head:
		_head.rotation.z = a
	if _tail:
		_tail.rotation.z = a
	if _feed_roll:
		_feed_roll.rotation.z = _feed_travel / FEED_ROLL_R
	_update_flights()


func _build_flights() -> void:
	var scene := load("res://game/assets/models/headrig_outfeed/headrig_outfeed_flight.glb") as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var mi: MeshInstance3D = null
	for n in src.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	if mi == null:
		src.free()
		return
	_loop_len = 2.0 * (TROUGH_X.y - TROUGH_X.x - 0.5) + TAU * SPROCKET_R
	_flights = MultiMesh.new()
	_flights.transform_format = MultiMesh.TRANSFORM_3D
	_flights.mesh = mi.mesh
	_flights.instance_count = int(_loop_len / FLIGHT_PITCH)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flights"
	mmi.multimesh = _flights
	add_child(mmi)
	src.free()
	_update_flights()


## Fine chips and dust kicked back out under the rubber curtain while a slab is in the drum.
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "ChipDust"
	_dust.position = Vector3(CHIP_MOUTH_X - 0.05, TROUGH_FLOOR_Y + 0.25, 3.875)
	_dust.emitting = false
	_dust.amount = 40
	_dust.lifetime = 0.9
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.03, 0.15, 0.3)
	_dust.direction = Vector3(-1.0, 0.4, 0.0)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 0.6
	_dust.initial_velocity_max = 1.6
	_dust.gravity = Vector3(0.0, -6.0, 0.0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.018)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.38)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	_dust.mesh = quad
	add_child(_dust)


## A flight at distance s round the loop: the top run travels +X along the trough floor;
## the paddle stands out of the loop (its local +Y).
func _update_flights() -> void:
	if _flights == null:
		return
	var x0 := TROUGH_X.x + 0.25
	var x1 := TROUGH_X.y - 0.25
	var run := x1 - x0
	var cy := TROUGH_FLOOR_Y - SPROCKET_R
	var zc := (TROUGH_Z.x + TROUGH_Z.y) * 0.5
	var pitch := _loop_len / _flights.instance_count
	for i in _flights.instance_count:
		var s := fposmod(i * pitch + _chain_travel, _loop_len)
		var pos: Vector3
		var t: Vector3
		if s < run:
			pos = Vector3(x0 + s, TROUGH_FLOOR_Y, zc)
			t = Vector3.RIGHT
		elif s < run + PI * SPROCKET_R:
			var a := (s - run) / SPROCKET_R
			pos = Vector3(x1 + SPROCKET_R * sin(a), cy + SPROCKET_R * cos(a), zc)
			t = Vector3(cos(a), -sin(a), 0.0)
		elif s < 2.0 * run + PI * SPROCKET_R:
			pos = Vector3(x1 - (s - run - PI * SPROCKET_R), cy - SPROCKET_R, zc)
			t = Vector3.LEFT
		else:
			var a := (s - 2.0 * run - PI * SPROCKET_R) / SPROCKET_R
			pos = Vector3(x0 - SPROCKET_R * sin(a), cy - SPROCKET_R * cos(a), zc)
			t = Vector3(-cos(a), sin(a), 0.0)
		var out := Vector3.BACK.cross(t)
		_flights.set_instance_transform(i, Transform3D(Basis(t, out, t.cross(out)), pos))


## One line for debug HUDs.
func status_text() -> String:
	var ks := []
	for k in _kick:
		if _kick[k]["state"] != Kick.IDLE:
			ks.append(k.to_lower())
	return "case %.1f m/s%s, kicking %s, chipped %d%s" % [_case_speed, " (holding)" if is_holding else "",
			", ".join(ks) if not ks.is_empty() else "-", _chipped, ", throat jam" if _jam_timer > 0.0 else ""]
