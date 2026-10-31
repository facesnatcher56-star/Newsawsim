extends Node3D

## headrig.gd
## Band headrig line: log deck, stop-loaders, chain turner, setworks carriage, band mill,
## outfeed live rolls and sawyer's cab. The model (game/assets/models/headrig, built by
## dev/blender/headrig) is in mill coordinates, like this node.
##
## Logs come off the log kicker onto a short live chain deck that carries them down to the
## stop-loaders. When the carriage is home and empty the loaders throw the front log onto
## the headblocks against the receded knees. The dogs clamp it, the setworks run the knees
## forward to set the first cut, and the carriage gigs through the band saw, slowing in the
## cut. At the end of the pass the knees recede a touch off the saw line and the carriage
## gigs back; at home the setworks set the next cut. After CUTS_PER_FACE cuts the dogs open,
## the knees recede and the chain turner rolls the log half a turn so the sawn face sits
## against the knees, and the other face is sawn. When the log has given all its boards the
## cant is let go past the saw and kicked onto the outfeed rolls with the boards.
##
## The log does the sawing itself (log.gd cut_board): a slab or board drops to the outfeed
## when the log's tail clears the blade.

enum Car { HOME_EMPTY, LOADING, DOGGING, SETTING, GIG_FORWARD, RECEDE, GIG_BACK, UNDOG_TURN, TURNING,
	RELEASE, RETURN_EMPTY }

const LOG_R := 0.245              # sawn core radius (bark is off by now)
const LOG_HALF := 2.46
const CUT_DEPTH := 0.05
const CUTS_PER_FACE := 2
const SAW := Vector3(21.9, 0.0, 5.73)
const BAND_FRONT_X := 21.77
const WHEEL_R := 0.85
const WHEEL_Z := 4.88
const UPPER_Y := 2.95
const LOWER_Y := -0.95
const TOOTH_PITCH := 0.0445
const UPPER_GUIDE_Y := 0.80
const MODEL_Y := -1.288
const CAR_HOME_X := 16.9
const CAR_END_X := 24.75
const KNEE_REST := 6.62
const DOG_OPEN_Y := 0.92
const CAR_WHEEL_R := 0.16
## Deck (mill coordinates): surface y = DECK_Y0 - (z - DECK_Z0) * tan(3 deg).
const DECK_X := Vector2(13.9, 19.9)
const DECK_Z0 := 3.12
const DECK_Z1 := 5.35
const DECK_Y0 := 0.0698
const DECK_SLOPE := deg_to_rad(3.0)
const DECK_STRANDS: Array[float] = [14.4, 15.4, 16.4, 17.4, 18.4, 19.4]
const STOP_Z := 5.12
const LOADER_DEG := 55.0
const TURN_DEG := 31.0
const OUT_X := Vector2(22.35, 29.0)
const OUT_Z := Vector2(4.8, 5.7)
const OUT_TOP_Y := -0.15
const OUT_ROLL_R := 0.1
const CHAIN_SCENE := "res://game/assets/models/log_deck/log_deck_chain.glb"
const TOOTH_SCENE := "res://game/assets/models/headrig/headrig_tooth.glb"

@export var deck_speed: float = 0.25
@export var outfeed_speed: float = 1.4
@export_group("Carriage")
## Gig speed outside the cut, feed speed in the cut, and the gig back.
@export var gig_speed: float = 1.4
@export var feed_speed: float = 0.6
@export var return_speed: float = 2.2
@export var setworks_speed: float = 0.22
@export var dog_speed: float = 0.35
## How good the sawyer is, 0 = green, 1 = veteran: a veteran feeds faster and wastes
## less time between passes. Not tied to the game yet.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
@export var band_speed: float = 9.0
## Prints the carriage's moves (for demos).
@export var debug_log: bool = false

var car_state: Car = Car.HOME_EMPTY
## True for the edger-side decks that ask: a log on the carriage or the carriage away.
var clamped_log: RigidBody3D = null
var current_progress: float = 0.0

var _model: Node3D
var _carriage: Node3D
var _knees: Array[Node3D] = []
var _dogs: Array[Node3D] = []
var _car_wheels: Array[Node3D] = []
var _loaders: Array[Node3D] = []
var _turners: Array[Node3D] = []
var _upper_wheel: Node3D
var _lower_wheel: Node3D
var _guide: Node3D
var _out_rolls: Array[Node3D] = []
var _deck_head: Node3D
var _deck_tail: Node3D
var _guide_rest_y: float = 0.0

var _deck_body: StaticBody3D
var _stop_shape: CollisionShape3D
var _outfeed: StaticBody3D
var _deck_links: MultiMesh
var _deck_dogs: MultiMesh
var _teeth: MultiMesh
var _deck_travel: float = 0.0
var _band_travel: float = 0.0
var _out_spin: float = 0.0
var _deck_locked: Array[RigidBody3D] = []

var _car_x: float = CAR_HOME_X
var _car_vel: float = 0.0
var _knee_z: float = KNEE_REST
var _knee_target: float = KNEE_REST
var _dog_y: float = DOG_OPEN_Y
var _dog_target: float = DOG_OPEN_Y
var _guide_drop: float = 0.0
var _guide_target: float = 0.0
var _loader_deg: float = 0.0
var _turner_deg: float = 0.0

var _log: RigidBody3D = null
var _roll: float = 0.0
var _end_flip: bool = false                # the log on the carriage has local X along +X
var _cuts_on_face: int = 0
var _face: int = 0
var _face_a_depth: float = 0.0
var _cut_this_pass: bool = false
var _sawing: bool = false                  # the log's front is past the saw on this pass
var _timer: float = 0.0
var _phase_time: float = 1.0
var _load_from := Vector3.ZERO
var _load_q := Quaternion.IDENTITY
var _turn_from: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_model = $Model
	_carriage = find_child("HR_Carriage", true, false) as Node3D
	for i in 3:
		_knees.append(find_child("HR_Knee%d" % (i + 1), true, false) as Node3D)
		_dogs.append(find_child("HR_Dog%d" % (i + 1), true, false) as Node3D)
	for i in 4:
		_car_wheels.append(find_child("HR_CarWheel%d" % (i + 1), true, false) as Node3D)
	for i in 3:
		_loaders.append(find_child("HR_Loader%d" % (i + 1), true, false) as Node3D)
	for i in 2:
		_turners.append(find_child("HR_Turner%d" % (i + 1), true, false) as Node3D)
	_upper_wheel = find_child("HR_UpperWheel", true, false) as Node3D
	_lower_wheel = find_child("HR_LowerWheel", true, false) as Node3D
	_guide = find_child("HR_UpperGuide", true, false) as Node3D
	if _guide:
		_guide_rest_y = _guide.position.y
	_deck_head = find_child("HR_DeckHead", true, false) as Node3D
	_deck_tail = find_child("HR_DeckTail", true, false) as Node3D
	var i := 1
	while true:
		var r := find_child("HR_OutRoll%d" % i, true, false) as Node3D
		if r == null:
			break
		_out_rolls.append(r)
		i += 1
	_build_collision()
	_build_deck_chains()
	_build_teeth()
	_apply_pose()


func _physics_process(delta: float) -> void:
	_run_deck(delta)
	_run_carriage(delta)
	_run_band(delta)
	_apply_pose()


func _process(delta: float) -> void:
	# Top of the rolls moves +X with the wood: about -Z. Drawn per frame, capped (RollSpin).
	_out_spin += RollSpin.step(-outfeed_speed / OUT_ROLL_R, delta)
	for r in _out_rolls:
		r.rotation.z = _out_spin


# --- Collision -------------------------------------------------------------------------

func _build_collision() -> void:
	# Deck bed: one box tilted to the deck slope, built here so the tilt is unambiguous.
	_deck_body = StaticBody3D.new()
	_deck_body.name = "DeckBed"
	add_child(_deck_body)
	var mid_z := (DECK_Z0 + DECK_Z1) * 0.5
	var bed := CollisionShape3D.new()
	var bed_box := BoxShape3D.new()
	bed_box.size = Vector3(DECK_X.y - DECK_X.x, 0.2, DECK_Z1 - DECK_Z0 + 0.05)
	bed.shape = bed_box
	var basis_tilt := Basis(Vector3.RIGHT, DECK_SLOPE)   # local +Z runs down-slope
	bed.transform = Transform3D(basis_tilt, Vector3((DECK_X.x + DECK_X.y) * 0.5, _deck_y(mid_z) - 0.1 * cos(DECK_SLOPE), mid_z))
	_deck_body.add_child(bed)
	# The loaders' stop horns at the deck end.
	_stop_shape = CollisionShape3D.new()
	var stop_box := BoxShape3D.new()
	stop_box.size = Vector3(DECK_X.y - DECK_X.x, 0.45, 0.16)
	_stop_shape.shape = stop_box
	_stop_shape.position = Vector3((DECK_X.x + DECK_X.y) * 0.5, _deck_y(STOP_Z) + 0.2, STOP_Z + 0.08)
	_deck_body.add_child(_stop_shape)
	# Outfeed live rolls as one flat bed.
	_outfeed = StaticBody3D.new()
	_outfeed.name = "OutfeedRolls"
	add_child(_outfeed)
	var out_shape := CollisionShape3D.new()
	var out_box := BoxShape3D.new()
	out_box.size = Vector3(OUT_X.y - OUT_X.x, 0.1, OUT_Z.y - OUT_Z.x)
	out_shape.shape = out_box
	out_shape.position = Vector3((OUT_X.x + OUT_X.y) * 0.5, OUT_TOP_Y - 0.05, (OUT_Z.x + OUT_Z.y) * 0.5)
	_outfeed.add_child(out_shape)
	_outfeed.constant_linear_velocity = Vector3(outfeed_speed, 0.0, 0.0)


func _deck_y(z: float) -> float:
	return DECK_Y0 - (z - DECK_Z0) * tan(DECK_SLOPE)


# --- Deck ------------------------------------------------------------------------------

## Loose logs on the deck.
func _deck_logs() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze or l == _log:
			continue
		var p := l.global_position
		if p.x > DECK_X.x - 0.5 and p.x < DECK_X.y + 0.5 and p.z > DECK_Z0 - 0.1 and p.z < DECK_Z1 + 0.1 \
				and p.y < _deck_y(p.z) + 1.2:
			out.append(l)
	return out


## The log sitting against the stop horns, if any.
func _stop_log(logs: Array[RigidBody3D]) -> RigidBody3D:
	var best: RigidBody3D = null
	for l in logs:
		if l.global_position.z > STOP_Z - 0.4 and (best == null or l.global_position.z > best.global_position.z):
			best = l
	return best


## Asked by the log kicker: room on the deck for another log.
func has_room() -> bool:
	var logs := _deck_logs()
	if logs.size() >= 3:
		return false
	for l in logs:
		if l.global_position.z < DECK_Z0 + 0.85:
			return false
	return true


func _run_deck(delta: float) -> void:
	var logs := _deck_logs()
	for l in logs:
		l.axis_lock_angular_x = true
		l.axis_lock_angular_y = true
		l.axis_lock_angular_z = true
		if not _deck_locked.has(l):
			_deck_locked.append(l)
	for idx in range(_deck_locked.size() - 1, -1, -1):
		var l := _deck_locked[idx]
		if not is_instance_valid(l) or not logs.has(l):
			_deck_locked.remove_at(idx)
	var front := _stop_log(logs)
	var run := not logs.is_empty() and front == null
	var dir := Basis(Vector3.RIGHT, DECK_SLOPE) * Vector3.BACK
	_deck_body.constant_linear_velocity = dir * deck_speed if run else Vector3.ZERO
	if not run:
		return
	_deck_travel += deck_speed * delta
	var target := Vector3(0.0, 0.0, dir.z * deck_speed)
	for l in logs:
		l.sleeping = false
		var h := Vector3(l.linear_velocity.x, 0.0, l.linear_velocity.z).move_toward(target, 1.5 * delta)
		l.linear_velocity = Vector3(h.x, l.linear_velocity.y, h.z)


func _build_deck_chains() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var link := (src.find_child("LD_ChainLink", true, false) as MeshInstance3D).mesh
	var dog := (src.find_child("LD_ChainDog", true, false) as MeshInstance3D).mesh
	src.free()
	_deck_links = _make_multimesh(link, DECK_STRANDS.size() * 24, "DeckChainLinks")
	_deck_dogs = _make_multimesh(dog, DECK_STRANDS.size() * 8, "DeckChainDogs")


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


## Deck chain loop round a 0.12 m sprocket at each end, in the deck's sloped frame.
func _update_deck_chains() -> void:
	if _deck_links == null:
		return
	var r := 0.12
	var z0 := DECK_Z0 + 0.1
	var z1 := DECK_Z1 - 0.12
	var run := (z1 - z0) / cos(DECK_SLOPE)
	var loop := 2.0 * run + TAU * r
	var tilt := Basis(Vector3.RIGHT, DECK_SLOPE)
	var origin_y := _deck_y(z0) - 0.02
	var per := 32
	var pitch := loop / per
	var li := 0
	var di := 0
	for x in DECK_STRANDS:
		for i in per:
			var s := fposmod(i * pitch + _deck_travel, loop)
			var p: Vector3
			var t: Vector3
			if s < run:
				p = Vector3(0, 0, s)
				t = Vector3.BACK
			elif s < run + PI * r:
				var a := (s - run) / r
				p = Vector3(0, -r + r * cos(a), run + r * sin(a))
				t = Vector3(0, -sin(a), cos(a))
			elif s < 2.0 * run + PI * r:
				p = Vector3(0, -2.0 * r, run - (s - run - PI * r))
				t = Vector3.FORWARD
			else:
				var a := (s - 2.0 * run - PI * r) / r
				p = Vector3(0, -r - r * cos(a), -r * sin(a))
				t = Vector3(0, sin(a), -cos(a))
			var wt := tilt * t
			var out := Vector3.RIGHT.cross(wt)
			var xf := Transform3D(Basis(Vector3.RIGHT, out, -wt), Vector3(x, origin_y, z0) + tilt * p)
			if i % 4 == 0:
				_deck_dogs.set_instance_transform(di, xf)
				di += 1
			else:
				_deck_links.set_instance_transform(li, xf)
				li += 1
	var ang := _deck_travel / r
	if _deck_head:
		_deck_head.rotation.x = ang
	if _deck_tail:
		_deck_tail.rotation.x = ang


# --- Band ------------------------------------------------------------------------------

func _build_teeth() -> void:
	var scene := load(TOOTH_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var mi := src.find_child("HR_Tooth", true, false) as MeshInstance3D
	var mesh: Mesh = mi.mesh if mi else null
	src.free()
	if mesh == null:
		return
	var loop := 2.0 * (UPPER_Y - LOWER_Y) + TAU * WHEEL_R
	_teeth = _make_multimesh(mesh, int(loop / TOOTH_PITCH), "BandTeeth")


func _run_band(delta: float) -> void:
	_band_travel += band_speed * delta
	if _upper_wheel:
		_upper_wheel.rotation.x = _band_travel / WHEEL_R
	if _lower_wheel:
		_lower_wheel.rotation.x = _band_travel / WHEEL_R
	if _teeth == null:
		return
	var run := UPPER_Y - LOWER_Y
	var loop := 2.0 * run + TAU * WHEEL_R
	var n := _teeth.instance_count
	var pitch := loop / n
	for i in n:
		var s := fposmod(i * pitch + _band_travel, loop)
		var y: float
		var z: float
		var t: Vector3
		if s < run:
			y = UPPER_Y - s
			z = SAW.z
			t = Vector3.DOWN
		elif s < run + PI * WHEEL_R:
			var a := (s - run) / WHEEL_R
			y = LOWER_Y - WHEEL_R * sin(a)
			z = WHEEL_Z + WHEEL_R * cos(a)
			t = Vector3(0, -cos(a), -sin(a))
		elif s < 2.0 * run + PI * WHEEL_R:
			y = LOWER_Y + (s - run - PI * WHEEL_R)
			z = WHEEL_Z - WHEEL_R
			t = Vector3.UP
		else:
			var a := (s - 2.0 * run - PI * WHEEL_R) / WHEEL_R
			y = UPPER_Y + WHEEL_R * sin(a)
			z = WHEEL_Z - WHEEL_R * cos(a)
			t = Vector3(0, cos(a), sin(a))
		var bx := Vector3.RIGHT
		var by := t.cross(bx)
		_teeth.set_instance_transform(i, Transform3D(Basis(bx, by, t), Vector3(BAND_FRONT_X, y, z)))


# --- Carriage --------------------------------------------------------------------------

func _run_carriage(delta: float) -> void:
	_timer += delta
	var p := clampf(_timer / _phase_time, 0.0, 1.0)
	if _log != null and not is_instance_valid(_log):
		_log = null
		clamped_log = null
		_enter(Car.RETURN_EMPTY, 1.0)
	match car_state:
		Car.HOME_EMPTY:
			_drive_to(CAR_HOME_X, return_speed, delta)
			_knee_target = KNEE_REST
			_dog_target = DOG_OPEN_Y
			_guide_target = 0.0
			if _timer > _pause() and absf(_car_x - CAR_HOME_X) < 0.01 and absf(_knee_z - KNEE_REST) < 0.005:
				var front := _stop_log(_deck_logs())
				if front != null and front.linear_velocity.length() < 0.1:
					_start_load(front)
		Car.LOADING:
			# Loaders swing up and over, the log rolls off them onto the headblocks.
			_loader_deg = LOADER_DEG * sin(PI * p)
			_move_loading_log(p)
			if p >= 1.0:
				_loader_deg = 0.0
				_stop_shape.disabled = false
				_cuts_on_face = 0
				_face = 0
				_face_a_depth = 0.0
				_roll = 0.0
				_dog_target = _dog_closed_y()
				_enter(Car.DOGGING, 1.0)
		Car.DOGGING:
			if absf(_dog_y - _dog_target) < 0.003 and _timer > 0.3:
				_knee_target = _cut_knee_z()
				_guide_target = UPPER_GUIDE_Y - (2.0 * LOG_R + 0.06)
				_enter(Car.SETTING, 1.0)
		Car.SETTING:
			# The sawyer waits for the outfeed rolls past the saw to clear before taking the cut.
			if absf(_knee_z - _knee_target) < 0.002 and _timer > 0.4 and _outfeed_clear(SAW.x, SAW.x + 2.0 * LOG_HALF):
				_cut_this_pass = false
				_sawing = false
				if debug_log:
					print("[%s] cut %d on face %s" % [name, _cuts_on_face + 1, "AB"[_face]])
				_enter(Car.GIG_FORWARD, 1.0)
		Car.GIG_FORWARD:
			var speed := gig_speed * lerpf(0.8, 1.15, operator_skill)
			if _in_cut():
				speed = feed_speed * lerpf(0.8, 1.15, operator_skill)
			_drive_to(CAR_END_X, speed, delta)
			if not _cut_this_pass and _log and _log.has_method("begin_cut"):
				# The cut opens from the front end back to the saw line as the log runs through.
				var sawn := _car_x + LOG_HALF - SAW.x
				if sawn > 0.0:
					if not _sawing:
						_sawing = true
						_log.begin_cut(Vector3.RIGHT)
					_log.update_cut(sawn)
			if not _cut_this_pass and _tail_x() > SAW.x + 0.08:
				_sawing = false
				_cut()
			if absf(_car_x - CAR_END_X) < 0.01:
				if _log != null and _log.board_count <= 0:
					_enter(Car.RELEASE, 1.0)
				else:
					# Recede a touch off the saw line for the gig back.
					_knee_target = _knee_z + 0.02
					_enter(Car.RECEDE, 0.4)
		Car.RECEDE:
			if p >= 1.0:
				_enter(Car.GIG_BACK, 1.0)
		Car.GIG_BACK:
			_drive_to(CAR_HOME_X, return_speed, delta)
			if absf(_car_x - CAR_HOME_X) < 0.01:
				if _cuts_on_face >= CUTS_PER_FACE and _face == 0:
					_dog_target = DOG_OPEN_Y
					_knee_target = KNEE_REST
					_guide_target = 0.0
					_enter(Car.UNDOG_TURN, 1.0)
				else:
					_knee_target = _cut_knee_z()
					_enter(Car.SETTING, 1.0)
		Car.UNDOG_TURN:
			if absf(_dog_y - _dog_target) < 0.003 and absf(_knee_z - _knee_target) < 0.002:
				_turn_from = _roll
				_enter(Car.TURNING, 3.0)
		Car.TURNING:
			# The turner swings up under the log and rolls it half a turn against the knees.
			_turner_deg = TURN_DEG * sin(PI * minf(p * 1.15, 1.0))
			_roll = _turn_from + PI * _ease(clampf((p - 0.1) / 0.8, 0.0, 1.0))
			if p >= 1.0:
				_turner_deg = 0.0
				_roll = _turn_from + PI
				_face_a_depth = _cuts_on_face * CUT_DEPTH
				_face = 1
				_cuts_on_face = 0
				if _log and _log.has_method("start_new_cut_face"):
					_log.start_new_cut_face()
				_dog_target = _dog_closed_y()
				_enter(Car.DOGGING, 1.0)
		Car.RELEASE:
			# The knees run up to just short of the saw line, setting the cant out past it over the
			# outfeed rolls; then the dogs open and it settles onto them.
			_knee_target = SAW.z + 0.03
			if absf(_knee_z - _knee_target) > 0.004 or not _outfeed_clear(_car_x - LOG_HALF - 0.3, _car_x + LOG_HALF + 0.3):
				pass
			elif absf(_dog_y - DOG_OPEN_Y) > 0.003:
				_dog_target = DOG_OPEN_Y
			elif _timer > 0.4:
				_kick_cant()
				_enter(Car.RETURN_EMPTY, 1.0)
		Car.RETURN_EMPTY:
			_guide_target = 0.0
			_knee_target = KNEE_REST
			_drive_to(CAR_HOME_X, return_speed, delta)
			if absf(_car_x - CAR_HOME_X) < 0.01:
				_enter(Car.HOME_EMPTY, 1.0)
	# Setworks, dogs and guide move at their own pace.
	_knee_z = move_toward(_knee_z, _knee_target, setworks_speed * delta)
	_dog_y = move_toward(_dog_y, _dog_target, dog_speed * delta)
	_guide_drop = move_toward(_guide_drop, _guide_target, 0.3 * delta)
	current_progress = clampf((_car_x - CAR_HOME_X) / (CAR_END_X - CAR_HOME_X), 0.0, 1.0)
	_place_log()


func _enter(s: Car, duration: float) -> void:
	car_state = s
	_timer = 0.0
	_phase_time = maxf(duration, 0.01)


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _pause() -> float:
	return lerpf(2.0, 0.6, operator_skill)


## Heavy carriage: accelerate and brake at a fixed rate toward the target.
func _drive_to(target: float, speed: float, delta: float) -> void:
	var dist := target - _car_x
	var brake := sqrt(2.0 * 1.6 * absf(dist))
	var want := signf(dist) * minf(speed, brake)
	_car_vel = move_toward(_car_vel, want, 1.6 * delta)
	if absf(dist) < 0.004 and absf(_car_vel) < 0.05:
		_car_vel = 0.0
		_car_x = target
		return
	_car_x += _car_vel * delta
	for w in _car_wheels:
		if w:
			w.rotation.z -= _car_vel * delta / CAR_WHEEL_R


## Dog slide height with its teeth just into the log's top (the teeth sit 0.11 below it).
func _dog_closed_y() -> float:
	return 2.0 * LOG_R + 0.10


## Knee face z that puts the next cut on the current face on the saw line.
func _cut_knee_z() -> float:
	var k := _cuts_on_face + 1
	var centre_z := SAW.z + LOG_R - k * CUT_DEPTH
	var seat := LOG_R if _face == 0 else LOG_R - _face_a_depth
	return centre_z + seat


func _seat_extent() -> float:
	return LOG_R if _face == 0 else LOG_R - _face_a_depth


func _log_basis() -> Basis:
	# Log long axis (local X) along the carriage, local +Z (face A) toward the saw.
	# A log is the same either end first: one that came onto the deck the other way round keeps
	# its ends (local X along +X world), turned half over so face A still faces the saw.
	if _end_flip:
		return Basis(Vector3.RIGHT, _roll + PI)
	return Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, _roll)


func _place_log() -> void:
	if _log == null or car_state == Car.LOADING:
		return
	var lift := 0.0
	var seat := _seat_extent()
	if car_state == Car.TURNING:
		var p := clampf(_timer / _phase_time, 0.0, 1.0)
		lift = 0.05 * sin(PI * p)
		# Rolling over, the sawn face comes round to sit flat against the knees.
		seat = lerpf(LOG_R, LOG_R - _cuts_on_face * CUT_DEPTH, _ease(clampf((p - 0.1) / 0.8, 0.0, 1.0)))
	_log.global_transform = Transform3D(_log_basis(), Vector3(_car_x, LOG_R + lift, _knee_z - seat))


func _tail_x() -> float:
	return _car_x - LOG_HALF


func _in_cut() -> bool:
	return _car_x + LOG_HALF > SAW.x - 0.15 and _tail_x() < SAW.x + 0.1


func _cut() -> void:
	_cut_this_pass = true
	if _log and _log.has_method("cut_board"):
		_log.cut_board(Vector3(SAW.x, 0.0, SAW.z), Vector3.RIGHT)
		_cuts_on_face += 1


func _start_load(l: RigidBody3D) -> void:
	_log = l
	clamped_log = l
	l.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	l.freeze = true
	l.axis_lock_angular_x = false
	l.axis_lock_angular_y = false
	l.axis_lock_angular_z = false
	_deck_locked.erase(l)
	_load_from = l.global_position
	_load_q = l.global_basis.get_rotation_quaternion()
	_end_flip = l.global_basis.x.x > 0.0
	_stop_shape.disabled = true
	if debug_log:
		print("[%s] loading a log" % name)
	_enter(Car.LOADING, 2.6)


func _move_loading_log(p: float) -> void:
	if _log == null:
		return
	var seat := Vector3(_car_x, LOG_R, KNEE_REST - LOG_R)
	var over := Vector3(lerpf(_load_from.x, seat.x, 0.5), 0.62, 5.62)
	var a := _load_from.lerp(over, _ease(clampf(p / 0.55, 0.0, 1.0)))
	var b := over.lerp(seat, _ease(clampf((p - 0.45) / 0.55, 0.0, 1.0)))
	var pos := a if p < 0.5 else b
	var target := _log_basis().get_rotation_quaternion()
	# It rolls the way it travels (toward the knees, -Z: about -X), about as far as it goes
	# (~0.6 m on a 0.245 m radius), and ends exactly in the seated pose: the roll about X is
	# picked from the turn it actually needs, plus or minus whole turns, nearest that.
	var rel := (target * _load_q.inverse()).normalized()
	var turn := rel.get_angle() * signf(rel.get_axis().x)
	var natural := -2.4
	for k in [-1.0, 1.0]:
		if absf(turn + k * TAU - natural) < absf(turn - natural):
			turn += k * TAU
	var e := _ease(p)
	var rest := (target * (Quaternion(Vector3.RIGHT, turn) * _load_q).inverse()).normalized()
	var q := Quaternion.IDENTITY.slerp(rest, e) * Quaternion(Vector3.RIGHT, turn * e) * _load_q
	_log.global_transform = Transform3D(Basis(q.normalized()), pos)


## The outfeed rolls this carriage drops wood onto (its zone_clear says when there's room).
@export var outfeed_path: NodePath = ^"../HeadrigOutfeed"


func _outfeed_clear(x0: float, x1: float) -> bool:
	var outfeed := get_node_or_null(outfeed_path)
	return outfeed == null or not outfeed.has_method("zone_clear") or outfeed.zone_clear(x0, x1)


func _kick_cant() -> void:
	if _log == null:
		return
	var l := _log
	_log = null
	clamped_log = null
	l.freeze = false
	# The knees push the cant level off the carriage onto the outfeed rolls past the saw line;
	# no throw (it used to fly and could land anywhere).
	l.linear_velocity = Vector3(0.0, 0.0, -0.2)
	l.angular_velocity = Vector3.ZERO
	l.sleeping = false
	if debug_log:
		print("[%s] cant off the carriage" % name)


func _apply_pose() -> void:
	if _carriage:
		_carriage.position.x = _car_x
	for k in _knees:
		if k:
			k.position.z = _knee_z
	for d in _dogs:
		if d:
			d.position.y = _dog_y
	for l in _loaders:
		if l:
			l.rotation.x = deg_to_rad(_loader_deg)
	for t in _turners:
		if t:
			t.rotation.x = deg_to_rad(_turner_deg)
	if _guide:
		_guide.position.y = _guide_rest_y - _guide_drop
	_update_deck_chains()


## One line for debug HUDs.
func status_text() -> String:
	return "%s, carriage %.1f m, deck %d logs" % [Car.keys()[car_state], _car_x - CAR_HOME_X, _deck_logs().size()]
