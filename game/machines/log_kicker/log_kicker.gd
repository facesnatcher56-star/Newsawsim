extends Node3D

## log_kicker.gd
## Debarker outfeed log trough with a flip kicker and a cushioned end stop.
##
## The model (game/assets/models/log_kicker, built by dev/blender/log_kicker) is in mill
## coordinates, like this node. Debarked logs come off the debarker's V-roll outfeed into a
## 90 deg trough; a drag chain in the bottom carries them (+X) to the end stop. The chain
## slows as a log nears the bumper and stops when it lands against it.
##
## When the incline has room the kicker fires: a cylinder rolls four paddles up through the
## far flank, they push the log up the near flank and over the rim, and it rolls down the
## skid ribs onto the incline foot. Now and then a log does not quite make it over the rim
## and rolls back into the trough; the kicker takes it again.
##
## While the incline is full the log waits against the stop and is_blocked is true (the log
## decks hold their feeders on it). While the chain is stopped, the debarker's outfeed holds
## any log about to come into the trough.

enum State { CONVEYING, AT_STOP, RAISE, ROLL, LOWER }

const LOG_RADIUS := 0.292
const LOG_HALF := 2.46
const LINE := Vector2(2.118, 0.872)          # (z, y) of a log centre in the trough
const STOP_FACE_X := 19.40
const KICK_DEG := 95.0
## Log centre path as (z, y): pushed up the near flank, over the rim, down the skids onto
## the incline foot.
const PATH_UP := Vector2(2.314, 1.066)
const PATH_RIM := Vector2(2.52, 1.152)
const PATH_OVER := Vector2(2.752, 1.037)
const PATH_FOOT := Vector2(3.25, 0.355)
## The paddles meet the log this far into their swing, and have it at the rim here.
const PADDLE_CONTACT_DEG := 22.0
const PADDLE_RIM_DEG := 72.0
## Crank pin in the kicker shaft's frame (x along the shaft from the mill origin).
const CRANK_PIN := Vector3(13.65, -0.40, -0.30)
## Trough drag chain loop (mill coordinates).
const HEAD_X := 19.30
const TAIL_X := 13.40
const CHAIN_Y := 0.39
## A log whose tail is this far into the trough's tail end is wholly in the trough.
const ENTRY_MARGIN := 0.6
## The next log is held on the outfeed with its nose this far short of the trough.
const HOLD_SHORT := 0.8
const SPROCKET_R := 0.15
const LINKS := 84
const DOG_EVERY := 4
const CHAIN_SCENE := "res://game/assets/models/log_deck/log_deck_chain.glb"

@export var trough_speed: float = 0.8
@export var creep_speed: float = 0.22
## Distance from the bumper at which the chain starts slowing a log down.
@export var slow_zone: float = 1.4
@export_group("Kicker")
@export var raise_time: float = 2.4
@export var roll_time: float = 1.4
@export var lower_time: float = 2.2
## How good the operator is, 0 = green, 1 = veteran: a veteran kicks sooner after the log
## lands and gets it over the rim more often. Not tied to the game yet.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
## Chance per kick that the log rolls back off the rim into the trough.
@export var hang_chance: float = 0.05
@export_group("Links")
## The incline deck (has_room()); the kick waits until it has room.
@export var incline_path: NodePath
## The debarker's outfeed conveyor (hold), held while the trough chain is stopped.
@export var outfeed_path: NodePath
## Prints kicks (for demos).
@export var debug_log: bool = false

## True while a log waits against the stop for the incline to make room.
var is_blocked: bool = false
var state: State = State.CONVEYING

@onready var _trough: StaticBody3D = $Trough

var _incline: Node
var _outfeed: Node
var _kicker: Node3D
var _bumper: Node3D
var _barrel: Node3D
var _rod: Node3D
var _head: Node3D
var _tail: Node3D
var _links: MultiMesh
var _dogs: MultiMesh
var _loop_len: float = 0.0
var _travel: float = 0.0
var _speed: float = 0.0
var _bumper_home: float = 0.0
var _bump: float = 0.0
var _bump_vel: float = 0.0

var _log: RigidBody3D = null
var _start := Vector3.ZERO
var _q0 := Quaternion.IDENTITY
var _square := Quaternion.IDENTITY
var _path: PackedVector3Array = PackedVector3Array()
var _path_len: float = 0.0
var _hang: bool = false
var _timer: float = 0.0
var _phase_time: float = 1.0
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_incline = get_node_or_null(incline_path)
	_outfeed = get_node_or_null(outfeed_path)
	_kicker = find_child("LK_Kicker", true, false) as Node3D
	_bumper = find_child("LK_Bumper", true, false) as Node3D
	_barrel = find_child("LK_CylBarrel", true, false) as Node3D
	_rod = find_child("LK_CylRod", true, false) as Node3D
	_head = find_child("LK_HeadShaft", true, false) as Node3D
	_tail = find_child("LK_TailShaft", true, false) as Node3D
	if _bumper:
		_bumper_home = _bumper.position.x
	_build_chain()
	_set_kick(0.0)


func _physics_process(delta: float) -> void:
	var logs := _trough_logs()
	var lead := _lead_log(logs)
	_timer += delta
	var p := clampf(_timer / _phase_time, 0.0, 1.0)
	match state:
		State.CONVEYING:
			is_blocked = false
			_speed = trough_speed
			if lead != null:
				var gap := STOP_FACE_X - (lead.global_position.x + LOG_HALF)
				_speed = lerpf(creep_speed, trough_speed, clampf(gap / slow_zone, 0.0, 1.0))
				if gap < 0.04:
					_speed = 0.0
					_bump_vel = -0.35   # the bumper takes the hit
					_wait = lerpf(2.5, 0.8, operator_skill) * _rng.randf_range(0.8, 1.3)
					state = State.AT_STOP
		State.AT_STOP:
			_speed = 0.0
			_wait -= delta
			if lead == null:
				state = State.CONVEYING
			else:
				var room: bool = _incline == null or not _incline.has_method("has_room") or _incline.has_room()
				is_blocked = not room
				if room and _wait <= 0.0 and lead.linear_velocity.length() < 0.06:
					_start_kick(lead)
		State.RAISE:
			_speed = 0.0
			var deg := PADDLE_RIM_DEG * _ease(p)
			_set_kick(deg)
			var s_up := _raise_s(deg)
			_move_log(s_up, _turned(s_up, _ease(p)))
			if p >= 1.0:
				_enter(State.ROLL, roll_time)
		State.ROLL:
			_speed = 0.0
			_set_kick(lerpf(PADDLE_RIM_DEG, KICK_DEG, _ease(p)))
			var s0 := _rim_s()
			# Over the rim the log speeds up down the skids; a hung log comes back.
			var s := s0 + (_path_len - s0) * p * p if not _hang else s0 + 0.25 * sin(PI * p)
			_move_log(s, _turned(s, 1.0))
			if p >= 1.0:
				_finish_roll()
				_enter(State.LOWER, lower_time)
		State.LOWER:
			_speed = 0.0
			var deg := KICK_DEG * (1.0 - _ease(p))
			_set_kick(deg)
			if _hang and is_instance_valid(_log):
				var s_back := _raise_s(minf(deg, PADDLE_RIM_DEG))
				_move_log(s_back, _turned(s_back, 1.0))
			if p >= 1.0:
				if _hang and is_instance_valid(_log):
					_release(_log)
					_wait = 1.5
					state = State.AT_STOP
				else:
					state = State.CONVEYING
				_log = null
	_run_trough(delta)
	_animate_bumper(delta)
	_hold_outfeed(logs)


# --- Trough ----------------------------------------------------------------------------

func _trough_logs() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := l.global_position
		if p.x > 13.0 and p.x < 19.6 and absf(p.z - LINE.x) < 0.6 and p.y > 0.5 and p.y < 1.6:
			out.append(l)
	return out


func _lead_log(logs: Array[RigidBody3D]) -> RigidBody3D:
	var lead: RigidBody3D = null
	for l in logs:
		if lead == null or l.global_position.x > lead.global_position.x:
			lead = l
	return lead


func _run_trough(delta: float) -> void:
	_trough.constant_linear_velocity = Vector3(_speed, 0.0, 0.0)
	if _speed <= 0.0:
		return
	_travel += _speed * delta
	_update_chain()


## The trough takes one log at a time (the kicker paddles sweep its whole length): hold the
## debarker's outfeed, with the next log's nose short of the trough, while a log is wholly in
## the trough or being kicked. It goes again once the trough is empty.
func _hold_outfeed(logs: Array[RigidBody3D]) -> void:
	if _outfeed == null or not ("hold" in _outfeed):
		return
	var occupied := state != State.CONVEYING
	for l in logs:
		if l.global_position.x - LOG_HALF > TAIL_X - ENTRY_MARGIN:
			occupied = true
	var hold := false
	if occupied:
		for node in get_tree().get_nodes_in_group("logs"):
			var l := node as RigidBody3D
			if l == null or l.freeze or l == _log:
				continue
			var p := l.global_position
			if absf(p.z - LINE.x) < 0.6 and p.x > 6.0 and p.x - LOG_HALF < TAIL_X - ENTRY_MARGIN \
					and p.x + LOG_HALF > TAIL_X - HOLD_SHORT:
				hold = true
				break
	_outfeed.hold = hold


func _animate_bumper(delta: float) -> void:
	# Spring-damper on the bumper: it gives a few centimetres when a log lands, then
	# eases back.
	var accel := -60.0 * _bump - 9.0 * _bump_vel
	_bump_vel += accel * delta
	_bump = clampf(_bump + _bump_vel * delta, -0.06, 0.0)
	if _bumper:
		_bumper.position.x = _bumper_home - _bump


# --- Kicker ----------------------------------------------------------------------------

func _start_kick(l: RigidBody3D) -> void:
	_log = l
	l.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	l.freeze = true
	_start = l.global_position
	_q0 = l.global_basis.get_rotation_quaternion()
	var axis := Basis(_q0).x.normalized()
	var square_axis := Vector3.RIGHT if axis.x >= 0.0 else Vector3.LEFT
	_square = (Quaternion(axis, square_axis) * _q0).normalized()
	var x := _start.x
	_path = PackedVector3Array([
		Vector3(x, _start.y, _start.z), Vector3(x, PATH_UP.y, PATH_UP.x), Vector3(x, PATH_RIM.y, PATH_RIM.x),
		Vector3(x, PATH_OVER.y, PATH_OVER.x), Vector3(x, PATH_FOOT.y, PATH_FOOT.x)])
	_path_len = 0.0
	for i in range(1, _path.size()):
		_path_len += _path[i - 1].distance_to(_path[i])
	_hang = _rng.randf() < hang_chance * lerpf(1.6, 0.5, operator_skill)
	is_blocked = false
	if debug_log:
		print("[%s] %.1f s kick%s" % [name, Time.get_ticks_msec() / 1000.0, " (will roll back)" if _hang else ""])
	_enter(State.RAISE, raise_time)


func _enter(s: State, duration: float) -> void:
	state = s
	_timer = 0.0
	_phase_time = maxf(duration, 0.01)


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


## Path distance the paddles have pushed the log by at a given paddle angle.
func _raise_s(deg: float) -> float:
	var t := clampf((deg - PADDLE_CONTACT_DEG) / (PADDLE_RIM_DEG - PADDLE_CONTACT_DEG), 0.0, 1.0)
	return _rim_s() * t


## The log's orientation after rolling s along the path, squared up by the given amount.
func _turned(s: float, squared: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, s / LOG_RADIUS) * _q0.slerp(_square, squared)


## Path distance from the trough to the top of the rim.
func _rim_s() -> float:
	if _path.size() < 3:
		return 0.0
	return _path[0].distance_to(_path[1]) + _path[1].distance_to(_path[2])


func _move_log(s: float, q: Quaternion) -> void:
	if not is_instance_valid(_log):
		return
	var pos := _path[0]
	var left := s
	for i in range(1, _path.size()):
		var seg := _path[i - 1].distance_to(_path[i])
		if left <= seg or i == _path.size() - 1:
			pos = _path[i - 1].lerp(_path[i], clampf(left / maxf(seg, 0.001), 0.0, 1.0))
			break
		left -= seg
	_log.global_transform = Transform3D(Basis(q), pos)


func _finish_roll() -> void:
	if _hang or not is_instance_valid(_log):
		return
	_release(_log)
	if debug_log:
		print("[%s] %.1f s log onto the incline at %s" % [name, Time.get_ticks_msec() / 1000.0, _log.global_position])


func _release(l: RigidBody3D) -> void:
	l.freeze = false
	l.linear_velocity = Vector3.ZERO
	l.angular_velocity = Vector3.ZERO
	l.axis_lock_angular_x = false
	l.axis_lock_angular_y = false
	l.axis_lock_angular_z = false
	l.sleeping = false


func _set_kick(deg: float) -> void:
	if _kicker == null:
		return
	_kicker.rotation.x = deg_to_rad(deg)
	if _barrel and _rod:
		var pin := _kicker.global_transform * CRANK_PIN
		_rod.global_position = pin
		_barrel.look_at(pin, Vector3.RIGHT)
		_rod.look_at(_barrel.global_position, Vector3.RIGHT)


# --- Chain -----------------------------------------------------------------------------

func _build_chain() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var link := src.find_child("LD_ChainLink", true, false) as MeshInstance3D
	var dog := src.find_child("LD_ChainDog", true, false) as MeshInstance3D
	_loop_len = 2.0 * (HEAD_X - TAIL_X) + TAU * SPROCKET_R
	@warning_ignore("integer_division")
	var dogs := LINKS / DOG_EVERY
	_links = _make_multimesh(link.mesh, LINKS - dogs, "ChainLinks")
	_dogs = _make_multimesh(dog.mesh, dogs, "ChainDogs")
	src.free()
	_update_chain()


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


func _update_chain() -> void:
	var angle := -_travel / SPROCKET_R
	if _head:
		_head.rotation.z = angle
	if _tail:
		_tail.rotation.z = angle
	if _links == null:
		return
	var pitch := _loop_len / LINKS
	var li := 0
	var di := 0
	for i in LINKS:
		var t := _chain_frame(fposmod(i * pitch + _travel, _loop_len))
		if i % DOG_EVERY == 0:
			_dogs.set_instance_transform(di, t)
			di += 1
		else:
			_links.set_instance_transform(li, t)
			li += 1


## A link at distance s round the loop: the top run travels +X to the end stop; the link's
## +Y faces out of the loop.
func _chain_frame(s: float) -> Transform3D:
	var run := HEAD_X - TAIL_X
	var shaft_y := CHAIN_Y - SPROCKET_R
	var pos: Vector3
	var t: Vector3
	if s < run:
		pos = Vector3(TAIL_X + s, CHAIN_Y, LINE.x)
		t = Vector3.RIGHT
	elif s < run + PI * SPROCKET_R:
		var a := (s - run) / SPROCKET_R
		pos = Vector3(HEAD_X + SPROCKET_R * sin(a), shaft_y + SPROCKET_R * cos(a), LINE.x)
		t = Vector3(cos(a), -sin(a), 0.0)
	elif s < 2.0 * run + PI * SPROCKET_R:
		pos = Vector3(HEAD_X - (s - run - PI * SPROCKET_R), shaft_y - SPROCKET_R, LINE.x)
		t = Vector3.LEFT
	else:
		var a := (s - 2.0 * run - PI * SPROCKET_R) / SPROCKET_R
		pos = Vector3(TAIL_X - SPROCKET_R * sin(a), shaft_y - SPROCKET_R * cos(a), LINE.x)
		t = Vector3(-cos(a), sin(a), 0.0)
	var across := Vector3.BACK
	var out := across.cross(t)
	return Transform3D(Basis(across, out, -t), pos)


## One line for debug HUDs.
func status_text() -> String:
	return "%s, chain %.2f m/s%s" % [State.keys()[state], _speed, ", incline full" if is_blocked else ""]
