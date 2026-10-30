extends Node3D

## live_log_deck.gd
## Debarker infeed log deck: a 7 m live chain deck on a 3 deg slope down to a four-stroke
## step feeder (log ladder) that singulates logs onto the debarker infeed.
##
## The model (game/assets/models/log_deck, built by dev/blender/log_deck) is in this node's
## frame: logs lie along X, the chains carry them towards -Z, the infeed line is at z 2.118.
## The deck on the other side of the infeed is the same deck turned 180 deg about that line.
##
## Logs on the chains cannot roll (their rotation is locked while they are on the deck), so
## a log that lands on another one rides there, and a log that lands crooked stays crooked.
## The chains will not run with a riding log or one turned more than skew_stop_deg off
## square; they wait for the loader to fix it (it holds the chains with hold_chains while
## it works). The chains also stop as soon as a log reaches the pocket against the first
## riser, and while the moving steps are up.
##
## Each feeder stroke lifts every log on the ladder one step: the moving steps rise, the
## logs roll forward off them onto the next fixed tread, and the steps drop back. The pocket
## log is squared up on the way. The top log rolls down the infeed's dump skid into the V,
## but only once the debarker says it can take one. Now and then a log does not clear the
## riser and rolls back; the next stroke takes it again.

enum Feed { IDLE, RAISE, ROLL, LOWER, DWELL }

const LOG_RADIUS := 0.292
## Feeder geometry in this node's frame (dev/blender/log_deck/ld_build.py): riser k is at
## RISER_Z[k]; a log rests against riser k+1 with its bottom at REST_Y[k] (k 0 = the pocket
## on the chains).
const RISER_Z: Array[float] = [5.38, 4.73, 4.08, 3.43]
const REST_Y: Array[float] = [0.160, 0.4845, 0.8091, 1.1336]
const LOG_X := -0.823
## Top edge of the infeed's dump skid and the infeed log line, as (z, y).
const SKID_EDGE := Vector2(2.978, 1.472)
const SKID_FOOT := Vector2(2.558, 0.792)
const LINE := Vector2(2.118, 0.872)
const STEP_LIFT := 0.45
## The moving steps meet a resting log this far into their stroke.
const STEP_CONTACT := 0.05
## Chain loop in the bed frame (matches ld_build.py).
const HEAD_Z := 0.30
const TAIL_Z := 6.70
const SPROCKET_R := 0.25
const CHAIN_Y := -0.02
const STRANDS: Array[float] = [-1.375, -0.275, 0.275, 1.375]
const LINKS_PER_STRAND := 96
const DOG_EVERY := 4
const FLOOR_Y := -1.288
const CHAIN_SCENE := "res://game/assets/models/log_deck/log_deck_chain.glb"

## Only one deck at a time may be handing a log to the shared infeed.
static var _infeed_claim: Node = null

@export var chain_speed: float = 0.2
## Seconds the chains wait after a log lands, so the loader can finish its set-down.
@export var deck_start_delay: float = 4.0
@export var chain_grip_acceleration: float = 2.0
## The chains will not run with a log turned further than this off square, or with a log
## riding on top of another; they wait for the loader to fix it.
@export var skew_stop_deg: float = 12.0
@export var rider_stop_height: float = 0.25
@export_group("Step feeder")
@export var raise_time: float = 3.0
@export var roll_time: float = 2.4
@export var lower_time: float = 2.6
## How good the feeder operator is, 0 = green, 1 = veteran: a veteran cycles with less
## dwell and squares the pocket log up better, so fewer logs hang on a riser. Not tied to
## the game yet.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
## Chance per log per stroke that it does not clear the riser and rolls back.
@export var hang_chance: float = 0.04
@export var dump_target_path: NodePath
## Optional kicker (anything with is_blocked): hold the top log while it is blocked.
@export var downstream_kicker_path: NodePath
## Prints feeder strokes and hand-offs (for demos).
@export var debug_log: bool = false
@export_group("Layout")
## Which side the drive and catwalk go on (+1 = +X); the far side from the loader.
@export var service_side: int = 1

## Set by the knuckleboom loader while it works on the deck: the chains stand still.
var hold_chains: bool = false
var feed_state: Feed = Feed.IDLE

@onready var _bed: StaticBody3D = $Bed
@onready var _moving: Node3D = $Model/MovingSteps

var _head_shaft: Node3D
var _tail_shaft: Node3D
var _links: MultiMesh
var _dogs: MultiMesh
var _travel: float = 0.0
var _loop_len: float = 0.0
var _chains_running: bool = false

var _locked: Array[RigidBody3D] = []
var _known: Array[RigidBody3D] = []
var _start_timer: float = 0.0

var _dump_target: Node3D
var _station: Node
var _kicker: Node
## Logs on the ladder, by step (0 = the pocket while a stroke has it).
var _ladder: Array = [null, null, null, null]
var _moves: Array = []
var _timer: float = 0.0
var _phase_time: float = 1.0
var _lift: float = 0.0
var _claim_timer: float = -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_dump_target = get_node_or_null(dump_target_path) as Node3D
	if _dump_target:
		_station = _dump_target.get_parent()
	if downstream_kicker_path:
		_kicker = get_node_or_null(downstream_kicker_path)
	_head_shaft = find_child("LD_HeadShaft", true, false)
	_tail_shaft = find_child("LD_TailShaft", true, false)
	if service_side < 0:
		var mirror := Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3(2.0 * LOG_X, 0.0, 0.0))
		for path in ["Model/Drive", "Model/Catwalk"]:
			var n := get_node_or_null(path) as Node3D
			if n:
				n.transform = mirror * n.transform
	_build_chains()
	_update_chains()


func _exit_tree() -> void:
	if _infeed_claim == self:
		_infeed_claim = null


func _physics_process(delta: float) -> void:
	var logs := _deck_logs()
	_track_logs(logs)
	_start_timer = maxf(0.0, _start_timer - delta)
	var pocket := _pocket_log(logs)
	var misplaced := has_misplaced_log(logs)
	# While the steps are up the pocket step stands above the chains: stop short of it.
	var steps_up := feed_state != Feed.IDLE and feed_state != Feed.DWELL
	var front_clear := pocket == null and not (steps_up and _front_log_z(logs) < 0.95)
	_run_chains(not logs.is_empty() and front_clear and not misplaced and not hold_chains
		and _start_timer <= 0.0, logs, delta)
	_run_feeder(pocket, misplaced, delta)
	if _claim_timer >= 0.0:
		_claim_timer -= delta
		if _claim_timer < 0.0 and _infeed_claim == self:
			_infeed_claim = null


# --- Chains ----------------------------------------------------------------------------

## Loose logs lying on the chains (not frozen, not held by anything).
func _deck_logs() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := _bed.to_local(l.global_position)
		if absf(p.x) < 3.1 and p.z > -0.3 and p.z < 7.2 and p.y > -0.2 and p.y < 2.2:
			out.append(l)
	return out


func _track_logs(logs: Array[RigidBody3D]) -> void:
	for l in logs:
		if not _known.has(l):
			# A log just landed: give the loader time to finish setting down.
			_start_timer = deck_start_delay
		if not _locked.has(l):
			_locked.append(l)
		l.axis_lock_angular_x = true
		l.axis_lock_angular_y = true
		l.axis_lock_angular_z = true
	for i in range(_locked.size() - 1, -1, -1):
		var l := _locked[i]
		if not is_instance_valid(l):
			_locked.remove_at(i)
		elif not logs.has(l):
			if not l.freeze:
				l.axis_lock_angular_x = false
				l.axis_lock_angular_y = false
				l.axis_lock_angular_z = false
			_locked.remove_at(i)
	_known = logs.duplicate()


## The log in the pocket against the first riser, if any.
func _pocket_log(logs: Array[RigidBody3D]) -> RigidBody3D:
	for l in logs:
		var p := _bed.to_local(l.global_position)
		if p.z < 0.42 and p.y - LOG_RADIUS < 0.2:
			return l
	return null


## Bed-local z of the log nearest the feeder (INF with none).
func _front_log_z(logs: Array[RigidBody3D]) -> float:
	var z := INF
	for l in logs:
		z = minf(z, _bed.to_local(l.global_position).z)
	return z


## True while a log on the deck lies turned off square or rides on another log.
func has_misplaced_log(logs: Array[RigidBody3D]) -> bool:
	var flat := Vector2(global_basis.x.x, global_basis.x.z).normalized()
	for l in logs:
		if _bed.to_local(l.global_position).y - LOG_RADIUS > rider_stop_height:
			return true
		var axis := l.global_basis.x
		if absf(Vector2(axis.x, axis.z).normalized().dot(flat)) < cos(deg_to_rad(skew_stop_deg)):
			return true
	return false


func _run_chains(run: bool, logs: Array[RigidBody3D], delta: float) -> void:
	_chains_running = run
	var dir := -_bed.global_basis.z.normalized()
	_bed.constant_linear_velocity = dir * chain_speed if run else Vector3.ZERO
	if not run:
		return
	_travel += chain_speed * delta
	_update_chains()
	var target := Vector3(dir.x, 0.0, dir.z) * chain_speed
	for l in logs:
		l.sleeping = false
		var h := Vector3(l.linear_velocity.x, 0.0, l.linear_velocity.z)
		h = h.move_toward(target, chain_grip_acceleration * delta)
		l.linear_velocity = Vector3(h.x, l.linear_velocity.y, h.z)


func _build_chains() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var link := src.find_child("LD_ChainLink", true, false) as MeshInstance3D
	var dog := src.find_child("LD_ChainDog", true, false) as MeshInstance3D
	_loop_len = 2.0 * (TAIL_Z - HEAD_Z) + TAU * SPROCKET_R
	@warning_ignore("integer_division")
	var per := LINKS_PER_STRAND / DOG_EVERY
	_links = _make_multimesh(link.mesh, STRANDS.size() * (LINKS_PER_STRAND - per), "ChainLinks")
	_dogs = _make_multimesh(dog.mesh, STRANDS.size() * per, "ChainDogs")
	src.free()


func _make_multimesh(mesh: Mesh, count: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	_bed.add_child(mmi)
	return mm


func _update_chains() -> void:
	var shaft_angle := -_travel / SPROCKET_R
	if _head_shaft:
		_head_shaft.rotation.x = shaft_angle
	if _tail_shaft:
		_tail_shaft.rotation.x = shaft_angle
	if _links == null:
		return
	var pitch := _loop_len / LINKS_PER_STRAND
	var li := 0
	var di := 0
	for x in STRANDS:
		for i in LINKS_PER_STRAND:
			var t := _chain_frame(x, fposmod(i * pitch + _travel, _loop_len))
			if i % DOG_EVERY == 0:
				_dogs.set_instance_transform(di, t)
				di += 1
			else:
				_links.set_instance_transform(li, t)
				li += 1


## Bed-frame transform of a link at distance s round the loop. The top run travels towards
## the feeder (-Z); the link's +Y faces out of the loop.
func _chain_frame(x: float, s: float) -> Transform3D:
	var run := TAIL_Z - HEAD_Z
	var shaft_y := CHAIN_Y - SPROCKET_R
	var pos: Vector3
	var t: Vector3
	if s < run:
		pos = Vector3(x, CHAIN_Y, TAIL_Z - s)
		t = Vector3(0.0, 0.0, -1.0)
	elif s < run + PI * SPROCKET_R:
		var a := (s - run) / SPROCKET_R
		pos = Vector3(x, shaft_y + SPROCKET_R * cos(a), HEAD_Z - SPROCKET_R * sin(a))
		t = Vector3(0.0, -sin(a), -cos(a))
	elif s < 2.0 * run + PI * SPROCKET_R:
		pos = Vector3(x, shaft_y - SPROCKET_R, HEAD_Z + s - run - PI * SPROCKET_R)
		t = Vector3(0.0, 0.0, 1.0)
	else:
		var a := (s - 2.0 * run - PI * SPROCKET_R) / SPROCKET_R
		pos = Vector3(x, shaft_y - SPROCKET_R * cos(a), TAIL_Z + SPROCKET_R * sin(a))
		t = Vector3(0.0, sin(a), cos(a))
	var out := Vector3.RIGHT.cross(t)
	return Transform3D(Basis(Vector3.RIGHT, out, -t), pos)


# --- Step feeder -----------------------------------------------------------------------

func _run_feeder(pocket: RigidBody3D, misplaced: bool, delta: float) -> void:
	_timer += delta
	var p := clampf(_timer / _phase_time, 0.0, 1.0)
	match feed_state:
		Feed.IDLE:
			_try_stroke(pocket, misplaced)
		Feed.RAISE:
			_set_lift(STEP_LIFT * _ease(p))
			for m in _moves:
				_place(m, m.start + Vector3(0.0, _log_lift(), 0.0), m.q0.slerp(m.square, _ease(p)))
			if p >= 1.0:
				_enter(Feed.ROLL, roll_time)
		Feed.ROLL:
			for m in _moves:
				_roll(m, _ease(p))
			if p >= 1.0:
				_finish_roll()
				_enter(Feed.LOWER, lower_time)
		Feed.LOWER:
			_set_lift(STEP_LIFT * (1.0 - _ease(p)))
			for m in _moves:
				if not m.moved:
					_place(m, m.start + Vector3(0.0, _log_lift(), 0.0), m.square)
			if p >= 1.0:
				_finish_stroke()
				var dwell := lerpf(2.4, 0.8, operator_skill) * _rng.randf_range(0.8, 1.4)
				_enter(Feed.DWELL, dwell)
		Feed.DWELL:
			if p >= 1.0:
				feed_state = Feed.IDLE


func _enter(state: Feed, duration: float) -> void:
	feed_state = state
	_timer = 0.0
	_phase_time = maxf(duration, 0.01)


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _set_lift(value: float) -> void:
	_lift = value
	if _moving:
		_moving.position.y = value


func _log_lift() -> float:
	return maxf(0.0, _lift - STEP_CONTACT)


func _try_stroke(pocket: RigidBody3D, misplaced: bool) -> void:
	var take_pocket := pocket != null and not misplaced and not hold_chains and _start_timer <= 0.0 \
		and pocket.linear_velocity.length() < 0.08
	var deliver: bool = _ladder[3] != null
	if not deliver and not take_pocket and _ladder[1] == null and _ladder[2] == null:
		return
	if deliver and not _downstream_ready():
		return
	var logs: Array = [pocket if take_pocket else null, _ladder[1], _ladder[2], _ladder[3]]
	var hang := lerpf(1.6, 0.5, operator_skill) * hang_chance
	var moving := [false, false, false, false]
	for k in range(3, -1, -1):
		if logs[k] == null or _rng.randf() < hang:
			continue
		moving[k] = k == 3 or logs[k + 1] == null or moving[k + 1]
	_moves.clear()
	for k in 4:
		var l := logs[k] as RigidBody3D
		if l == null:
			continue
		if k == 0:
			_lock(l, true)
		_moves.append(_make_move(l, k, moving[k]))
	if deliver and not moving[3]:
		_release_claim(0.5)
	if debug_log:
		print("[%s] %.1f s stroke: logs %s moving %s" % [name, Time.get_ticks_msec() / 1000.0,
			logs.map(func(l): return l != null), moving])
	_enter(Feed.RAISE, raise_time)


func _downstream_ready() -> bool:
	if _infeed_claim != null and _infeed_claim != self and is_instance_valid(_infeed_claim):
		return false
	if _kicker != null and _kicker.get("is_blocked"):
		return false
	if _station != null and _station.has_method("can_accept_log") and not _station.can_accept_log():
		return false
	_infeed_claim = self
	_claim_timer = -1.0
	return true


func _release_claim(after: float) -> void:
	_claim_timer = after


func _lock(l: RigidBody3D, frozen: bool) -> void:
	if frozen:
		l.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		l.freeze = true
		_locked.erase(l)
	else:
		l.freeze = false
		l.linear_velocity = Vector3.ZERO
		l.angular_velocity = Vector3.ZERO
		l.sleeping = false


func _make_move(l: RigidBody3D, step: int, moves: bool) -> Dictionary:
	var start := to_local(l.global_position)
	var q0 := (global_basis.inverse() * l.global_basis).get_rotation_quaternion()
	var axis := Basis(q0).x.normalized()
	var square_axis := Vector3.RIGHT if axis.x >= 0.0 else Vector3.LEFT
	var square := (Quaternion(axis, square_axis) * q0).normalized()
	var lifted := start + Vector3(0.0, STEP_LIFT - STEP_CONTACT, 0.0)
	var path := PackedVector3Array([lifted])
	if step < 3:
		var nxt := _rest(step + 1, start.x)
		path.append(nxt if moves else lifted.lerp(nxt, _rng.randf_range(0.3, 0.5)))
	else:
		var x := start.x
		var top := Vector3(x, SKID_EDGE.y + LOG_RADIUS, SKID_EDGE.x)
		var foot := Vector3(x, SKID_FOOT.y + LOG_RADIUS * 0.6, SKID_FOOT.x - 0.1)
		var line := Vector3(x, LINE.y, LINE.x)
		path.append_array(PackedVector3Array([top, foot, line]) if moves \
			else PackedVector3Array([lifted.lerp(top, _rng.randf_range(0.4, 0.6))]))
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return {
		"log": l, "step": step, "moved": moves, "start": start, "q0": q0, "square": square,
		"path": path, "length": length,
	}


## Where a log rests on step k (k 1..3) of the ladder, at log centre x.
func _rest(k: int, x: float) -> Vector3:
	return Vector3(x, REST_Y[k] + LOG_RADIUS + 0.02, RISER_Z[k] + LOG_RADIUS + 0.01)


func _roll(m: Dictionary, p: float) -> void:
	var path: PackedVector3Array = m.path
	# A log that hangs on the riser gets part way over and rolls back.
	var s: float = m.length * (p if m.moved else sin(PI * p))
	var pos := path[0]
	var left := s
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if left <= seg or i == path.size() - 1:
			pos = path[i - 1].lerp(path[i], clampf(left / maxf(seg, 0.001), 0.0, 1.0))
			break
		left -= seg
	var spin := Quaternion(Vector3.RIGHT, -s / LOG_RADIUS)
	_place(m, pos, spin * m.square)
	m["spin"] = spin


func _place(m: Dictionary, pos: Vector3, q: Quaternion) -> void:
	var l := m.log as RigidBody3D
	if not is_instance_valid(l):
		return
	l.global_transform = Transform3D(global_basis * Basis(q), to_global(pos))


func _finish_roll() -> void:
	for m in _moves:
		var l := m.log as RigidBody3D
		if not is_instance_valid(l):
			continue
		if m.moved and m.step == 3:
			# Into the infeed V: hand it to the debarker's conveyor.
			l.global_transform = Transform3D(global_basis * Basis(m.spin * m.square),
				to_global(m.path[m.path.size() - 1]))
			_lock(l, false)
			l.axis_lock_angular_x = false
			l.axis_lock_angular_y = false
			l.axis_lock_angular_z = false
			_release_claim(1.0)
			if debug_log:
				print("[%s] %.1f s log into the infeed at %s" % [name, Time.get_ticks_msec() / 1000.0,
					l.global_position])
		elif not m.moved:
			m["square"] = m.get("spin", Quaternion.IDENTITY) * m.square


func _finish_stroke() -> void:
	var ladder: Array = [null, null, null, null]
	for m in _moves:
		var l := m.log as RigidBody3D
		if not is_instance_valid(l):
			continue
		var step: int = m.step
		if m.moved:
			if step < 3:
				ladder[step + 1] = l
				_place(m, _rest(step + 1, m.start.x), m.get("spin", Quaternion.IDENTITY) * m.square)
		elif step == 0:
			# Back down on the chains in the pocket.
			_place(m, m.start, m.square)
			_lock(l, false)
		else:
			ladder[step] = l
			_place(m, m.start, m.square)
	_ladder = ladder
	_moves.clear()


## One line for debug HUDs.
func status_text() -> String:
	var n := 0
	for l in _ladder:
		if l != null:
			n += 1
	var why := ""
	if hold_chains:
		why = " (loader)"
	elif has_misplaced_log(_deck_logs()):
		why = " (log needs fixing)"
	return "%s, chains %s%s, %d on ladder" % [Feed.keys()[feed_state], "on" if _chains_running else "off", why, n]
