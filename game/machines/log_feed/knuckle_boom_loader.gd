extends Node3D

## knuckle_boom_loader.gd
## Stationary electric knuckleboom loader (Weiler K261 / Cat 519 SM class) that feeds a
## debark log deck from a log yard pile, two to four logs a bite.
##
## The model (game/assets/models/knuckle_boom, built by dev/blender/knuckle_boom) is driven
## by its joint nodes: slew on KBL_Turret, boom and stick pitch on KBL_Boom / KBL_Stick.
## The operator is modelled in tip space: the stick tip is steered in cylindrical
## coordinates (slew angle, radius, height) with acceleration-limited motion, a two-link IK
## turns radius/height into boom and stick angles, and each joint is rate-limited like a
## hydraulic function. The grapple hangs free on its dangle link as a damped pendulum, so
## it swings when the turret starts and stops; the operator waits for it to settle before
## biting logs or setting them down. The rotator turns the logs to line up with the deck.
##
## Logs on the deck cannot roll (the deck stops lock their rotation), so a log that lands
## on top of another rides there until somebody fixes it. After every set-down the loader
## looks over the deck. For each log riding on another it holds the deck chains, brakes
## the grapple plumb, comes down beside the rider with the tongs closed and pushes it
## sideways off onto free chain. If two pushes do not clear it, or there is no room to
## push it into, it picks that log up on its own and sets it down on a clear spot.

enum Phase {
	TO_PILE, SETTLE_PILE, DESCEND_PILE, GRAB, LIFT_PILE, TO_DECK, WAIT_DECK, DESCEND_DECK, RELEASE, LIFT_DECK,
	INSPECT_DECK, FIX_TO, FIX_SETTLE, FIX_LOWER, FIX_PUSH, FIX_BACKOFF, FIX_CHECK,
	RETURN_TO_PILE, RETURN_LOWER,
}

const LOG_RADIUS := 0.292
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const TONG_OPEN := deg_to_rad(60.0)
const BOOM_LIMITS := Vector2(deg_to_rad(-8.0), deg_to_rad(65.0))
const STICK_LIMITS := Vector2(deg_to_rad(-140.0), deg_to_rad(-30.0))
## Where logs sit in the closed grapple (rotator space: X along the logs, Y up from the
## dangle pin, Z across), and how far the tongs stay open around them.
const BUNDLE_SLOTS := {
	1: [Vector3(0.0, -1.55, 0.0)],
	2: [Vector3(0.0, -1.55, 0.30), Vector3(0.0, -1.55, -0.30)],
	3: [Vector3(0.0, -1.78, 0.30), Vector3(0.0, -1.78, -0.30), Vector3(0.0, -1.27, 0.0)],
	4: [Vector3(0.0, -1.80, 0.30), Vector3(0.0, -1.80, -0.30), Vector3(0.0, -1.24, 0.30), Vector3(0.0, -1.24, -0.30)],
}
const BUNDLE_TONG := { 1: 0.06, 2: 0.18, 3: 0.30, 4: 0.33 }
## Deck-local landing spot: middle of the deck width, near the infeed end.
const DECK_DROP_LOCAL := Vector3(-1.1, 0.0, 1.15)
## Deck-local box that must be clear of logs before another bundle goes down.
const DECK_ROOM_MIN := Vector3(-3.8, -0.3, -0.1)
const DECK_ROOM_MAX := Vector3(1.6, 1.5, 2.3)
## Deck-local span the loader treats as the deck (logs along X, chains run along Z).
const DECK_SPAN_MIN := Vector3(-4.0, -0.4, -2.4)
const DECK_SPAN_MAX := Vector3(1.8, 2.0, 2.4)
## Where a log centre may sit on the chains: clear of the infeed end beam and the stops.
const CHAIN_Z_LIMITS := Vector2(-1.75, 1.75)
## Centre spacing that counts as "touching" for two logs side by side on the chains.
const LOG_PITCH := 0.62
## A log whose centre sits this far above lying on the chains is riding on another one
## (one nested in the groove between two logs sits about 0.5 m up).
const RIDER_HEIGHT := 0.25
## A log lying more than this far off square to the deck gets picked up and squared.
const SKEW_LIMIT_DEG := 12.0
## The closed tongs as a pusher paddle (rotator space): half extents and centre.
const PADDLE_HALF := Vector3(0.28, 0.5, 0.45)
const PADDLE_CENTRE := Vector3(0.0, -1.5, 0.0)

@export var enabled: bool = true
@export var deck_path: NodePath
@export var pile_path: NodePath
## How good the operator is, 0 = green, 1 = veteran. Sets their pace, how big a bite they
## take, how cleanly logs come off the grapple, how fast they trust a settling grapple
## and how neatly they fix a riding log. Not tied to the game yet; meant to come from
## operator experience later.
@export_range(0.0, 1.0) var operator_skill: float = 0.6
@export_range(1, 4) var min_bundle: int = 2
@export_range(1, 4) var max_bundle: int = 4
@export_group("Hydraulics")
## K261 swing tops out at 8 rpm (0.84 rad/s). With 2 t of turret, boom and logs swinging,
## a mill operator feathers it far below that and eases in and out of every move.
@export var slew_speed: float = 0.28
@export var slew_accel: float = 0.1
@export var tip_speed: float = 0.65
@export var tip_accel: float = 0.3
## Final approach speed when coming down onto logs or setting them down.
@export var creep_speed: float = 0.2
## Seconds the hydraulics take to ramp into a new speed (soft starts and stops).
@export var ramp_time: float = 0.45
@export var boom_rate: float = 0.2
@export var stick_rate: float = 0.28
@export var rotator_rate: float = 0.5
@export var tong_rate: float = 0.6
@export_group("Grapple")
@export var swing_damping: float = 0.8
@export var settle_angle: float = deg_to_rad(4.0)
@export var settle_timeout: float = 4.0
## Height of the stick tip above the highest obstacle while swinging.
@export var swing_clearance: float = 2.8
@export_group("Deck tidying")
## Speed of the sideways push that slides a riding log off.
@export var push_speed: float = 0.2
## Pushes tried on one log before picking it up instead.
@export var max_pushes: int = 2

var phase: Phase = Phase.TO_PILE

var _turret: Node3D
var _boom: Node3D
var _stick: Node3D
var _dangle: Node3D
var _rotator: Node3D
var _tong_a: Node3D
var _tong_b: Node3D
var _cylinders: Array = []   # [barrel, rod, axis_kind]
var _deck: Node3D
var _deck_stops: Node
var _pile: Node3D
var _pusher: AnimatableBody3D

var _l1: float
var _l2: float
var _foot: Vector3

var _slew: float = 0.0
var _slew_vel: float = 0.0
var _tip := Vector2(4.0, 2.5)      # (radius, height) in base space, the operator's aim
var _tip_vel: float = 0.0
var _boom_angle: float = 0.5
var _stick_angle: float = -1.6
var _rot_yaw: float = 0.0
var _tong: float = 0.0
var _goal_slew: float = 0.0
var _goal_tip := Vector2(4.0, 2.5)
var _goal_log_axis := Vector3.RIGHT
var _goal_tong: float = 0.0

var _bob := Vector3.ZERO
var _bob_vel := Vector3.ZERO
var _pin_prev := Vector3.ZERO
var _dangle_brake: bool = false
var _timer: float = 0.0

var _bundle: Array[RigidBody3D] = []
var _bundle_start: Array[Transform3D] = []
var _bundle_slot: Array[Transform3D] = []

## Deck-local spot the current load goes to.
var _drop_local := DECK_DROP_LOCAL
## True while carrying a single log off another one rather than a bundle from the pile.
var _replacing: bool = false
var _fix_log: RigidBody3D = null
var _fix_pushes: int = 0
## Logs the rider rests on. The stopped chains' lugs hold them, so the push slides the
## rider over them instead of shoving the whole pile-up along the deck.
var _fix_supports: Array[RigidBody3D] = []
var _line_from := Vector3.ZERO
var _line_to := Vector3.ZERO
var _line_s: float = 0.0
var _push_speed: float = 0.35

## The operator is not a robot: each cycle runs a little faster or slower and swings a
## little higher or lower, and every fix is set up a bit differently.
var _rng := RandomNumberGenerator.new()
var _pace: float = 1.0
var _clearance_jitter: float = 0.0


func _ready() -> void:
	_turret = find_child("KBL_Turret", true, false)
	_boom = find_child("KBL_Boom", true, false)
	_stick = find_child("KBL_Stick", true, false)
	_dangle = find_child("KBL_Dangle", true, false)
	_rotator = find_child("KBL_Rotator", true, false)
	_tong_a = find_child("KBL_TongA", true, false)
	_tong_b = find_child("KBL_TongB", true, false)
	_l1 = _stick.position.length()
	_l2 = _dangle.position.length()
	_foot = _boom.position
	for pair in [["LiftL", 0], ["LiftR", 0], ["Stick", 1], ["TongA", 2], ["TongB1", 2], ["TongB2", 2]]:
		_cylinders.append([find_child("KBL_%sBarrel" % pair[0], true, false),
			find_child("KBL_%sRod" % pair[0], true, false), pair[1]])
	_deck = get_node_or_null(deck_path) as Node3D
	_pile = get_node_or_null(pile_path) as Node3D
	if _deck:
		_deck_stops = _deck.get_node_or_null("RetractableStops")
	_build_pusher()
	_rng.randomize()

	# Start parked over the pile side, boom up, grapple closed and hanging still.
	if _pile:
		var p := _base_local(_pile.global_position)
		_slew = atan2(-p.z, p.x)
	_goal_slew = _slew
	_tip = Vector2(4.0, _base_height(_hover_height()))
	_goal_tip = _tip
	_solve_ik(_tip)
	_boom_angle = _ik_boom
	_stick_angle = _ik_stick
	_apply_joints()
	_pin_prev = _dangle.global_position
	_bob = _pin_prev + Vector3.DOWN * _pendulum_length()
	_apply_grapple()
	_aim_cylinders()
	if enabled:
		_start_to_pile()


func _physics_process(delta: float) -> void:
	if not enabled or _turret == null:
		return
	_run_phase(delta)
	_follow_line(delta)
	_drive(delta)
	_apply_joints()
	_swing_pendulum(delta)
	_apply_grapple()
	_carry_bundle()
	_aim_cylinders()


# --- Operator ------------------------------------------------------------------

func _run_phase(delta: float) -> void:
	_timer += delta
	match phase:
		Phase.TO_PILE:
			if _bundle.is_empty():
				_start_to_pile()
			elif _arrived():
				_enter(Phase.SETTLE_PILE)
		Phase.SETTLE_PILE:
			if _settled() or _timer > _settle_wait():
				_set_tip_height(_pick_height())
				_enter(Phase.DESCEND_PILE)
		Phase.DESCEND_PILE:
			if _arrived():
				_begin_grab()
				_enter(Phase.GRAB)
		Phase.GRAB:
			if _timer >= _grab_time() and absf(_tong - _goal_tong) < 0.01:
				_set_tip_height(maxf(_hover_height(), _lift_clear_height() + 0.3))
				_enter(Phase.LIFT_PILE)
		Phase.LIFT_PILE:
			# Start the swing once the load has cleared whatever it came off.
			if _tip_height_world() > _lift_clear_height():
				_aim_at_deck(_hover_height())
				_enter(Phase.TO_DECK)
		Phase.TO_DECK:
			if _arrived():
				_enter(Phase.WAIT_DECK)
		Phase.WAIT_DECK:
			if (_replacing or _deck_has_room()) and (_settled() or _timer > _settle_wait()):
				_set_tip_height(_drop_height())
				_enter(Phase.DESCEND_DECK)
			elif not _replacing and _timer > 5.0 and _pile and (_find_rider() or _find_skewed()):
				# The deck has stopped on a log that needs fixing and this load is in the
				# way: put it back on the pile and go sort the deck out.
				var over := _pile.global_position
				_set_goal_world(over, _hover_height())
				_goal_log_axis = _pile.global_basis.x
				_enter(Phase.RETURN_TO_PILE)
		Phase.RETURN_TO_PILE:
			if _arrived():
				_set_tip_height(_pile_top() + 0.05 + _bundle_hang())
				_enter(Phase.RETURN_LOWER)
		Phase.RETURN_LOWER:
			if _arrived():
				var returned: Array[RigidBody3D] = _bundle.duplicate()
				_bundle.clear()
				_bundle_start.clear()
				_bundle_slot.clear()
				_pile.return_logs(returned)
				_goal_tong = TONG_OPEN
				_set_tip_height(_hover_height())
				_enter(Phase.LIFT_DECK)
		Phase.DESCEND_DECK:
			if _arrived():
				_release()
				_enter(Phase.RELEASE)
		Phase.RELEASE:
			# Let the tongs come right open before lifting off the logs.
			if _timer > 1.6:
				_set_tip_height(_hover_height())
				_enter(Phase.LIFT_DECK)
				if _pile and _pile.log_count() == 0:
					_pile.restock()
		Phase.LIFT_DECK:
			if _tip_height_world() > _deck_top() + _bundle_hang() + 0.4:
				_enter(Phase.INSPECT_DECK)

		# --- Deck tidying ---
		Phase.INSPECT_DECK:
			# Give the logs a moment to come to rest before judging them.
			if _timer > 1.0 and (_deck_calm() or _timer > 3.0):
				_inspect_deck()
		Phase.FIX_TO:
			if _arrived():
				_enter(Phase.FIX_SETTLE)
		Phase.FIX_SETTLE:
			if _settled() or _timer > _settle_wait():
				_dangle_brake = true
				_set_tip_height(_line_from.y)
				_enter(Phase.FIX_LOWER)
		Phase.FIX_LOWER:
			if _arrived():
				_hold_supports(true)
				_set_pusher(true)
				_line_s = 0.0
				_enter(Phase.FIX_PUSH)
		Phase.FIX_PUSH:
			if _line_s >= _line_from.distance_to(_line_to) and _arrived():
				_set_pusher(false)
				_hold_supports(false)
				# Back off a little before lifting so the tongs do not drag the log back.
				var back := _line_to + (_line_from - _line_to).normalized() * 0.25 + Vector3.UP * 1.0
				_set_goal_world(back, back.y)
				_enter(Phase.FIX_BACKOFF)
		Phase.FIX_BACKOFF:
			if _arrived():
				_dangle_brake = false
				_enter(Phase.FIX_CHECK)
		Phase.FIX_CHECK:
			if _timer > 1.2 and (_deck_calm() or _timer > 3.0):
				_inspect_deck()


func _enter(next: Phase) -> void:
	phase = next
	_timer = 0.0


func _start_to_pile() -> void:
	_replacing = false
	_pace = lerpf(0.75, 1.1, operator_skill) * _rng.randf_range(0.93, 1.05)
	_clearance_jitter = _rng.randf_range(-0.3, 0.35) * _sloppiness()
	# Never quite the same spot twice.
	_drop_local = DECK_DROP_LOCAL + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.12, 0.12))
	if _pile == null:
		return
	if _pile.log_count() == 0:
		_pile.restock()
	# A green operator takes smaller bites.
	var biggest := roundi(lerpf(min_bundle, max_bundle, 0.35 + 0.65 * operator_skill))
	var n := _rng.randi_range(min_bundle, maxi(min_bundle, biggest))
	_start_pick(_pile.take_bundle(n), _pile.global_basis.x)


## Head over the given logs with the tongs open, ready to settle and bite.
func _start_pick(logs: Array[RigidBody3D], log_axis: Vector3) -> void:
	_bundle = logs
	_bundle_start.clear()
	_bundle_slot.clear()
	if _bundle.is_empty():
		return
	var centre := Vector3.ZERO
	for l in _bundle:
		centre += l.global_position
	centre /= _bundle.size()
	_set_goal_world(centre, maxf(_hover_height(), _tip_height_world()))
	_goal_log_axis = log_axis
	_goal_tong = TONG_OPEN
	_enter(Phase.TO_PILE)


func _aim_at_deck(height: float) -> void:
	var drop := _deck.to_global(_drop_local)
	_set_goal_world(drop, height)
	_goal_log_axis = _deck.global_basis.x


func _begin_grab() -> void:
	var rot_inv := _rotator.global_transform.affine_inverse()
	# Lowest slots first, each taking the nearest remaining log, so no log crosses over.
	var slots: Array = BUNDLE_SLOTS[_bundle.size()].duplicate()
	slots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var remaining := _bundle.duplicate()
	_bundle = []
	for slot: Vector3 in slots:
		var best: RigidBody3D = null
		var best_d := INF
		for l: RigidBody3D in remaining:
			var p := rot_inv * l.global_position
			var d := Vector2(p.y - slot.y, p.z - slot.z).length()
			if d < best_d:
				best_d = d
				best = l
		remaining.erase(best)
		_bundle.append(best)
		best.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		best.freeze = true
		var start := rot_inv * best.global_transform
		# Turn the log's long axis onto the grapple's, keeping its roll.
		var axis := start.basis.x.normalized()
		var target_axis := Vector3.RIGHT if axis.x >= 0.0 else Vector3.LEFT
		var align := Basis(Quaternion(axis, target_axis))
		_bundle_start.append(start)
		_bundle_slot.append(Transform3D(align * start.basis.orthonormalized(), slot))
	_goal_tong = BUNDLE_TONG[_bundle.size()]


func _release() -> void:
	# As the tongs swing open they ease the upper logs outward. How far varies, so most
	# top logs settle onto the chains but now and then one stays riding.
	var low_y := INF
	for t in _bundle_slot:
		low_y = minf(low_y, t.origin.y)
	var across := _deck.global_basis.z.normalized() if _deck else Vector3.FORWARD
	for i in range(_bundle.size()):
		var l := _bundle[i]
		if not is_instance_valid(l):
			continue
		l.freeze = false
		l.angular_velocity = Vector3.ZERO
		l.linear_velocity = Vector3.ZERO
		if i < _bundle_slot.size() and _bundle_slot[i].origin.y > low_y + 0.2 and _deck:
			var side := _release_side(l)
			if side != 0.0:
				# A practised hand opens the tongs so the top logs roll clear more often.
				var nudge := lerpf(0.1, 0.3, operator_skill)
				l.linear_velocity = across * side * _rng.randf_range(nudge, nudge + 0.35)
	_bundle.clear()
	_bundle_start.clear()
	_bundle_slot.clear()
	_goal_tong = TONG_OPEN


## Which way (+1/-1 along deck Z, 0 for neither) an upper log can fall clear of the
## bundle: a side with free chain, picked at random when both are free.
func _release_side(l: RigidBody3D) -> float:
	var z := _deck.to_local(l.global_position).z
	var sides: Array[float] = []
	for s in [1.0, -1.0]:
		if _chain_spot_free_ignoring(z + s * 2.0 * LOG_PITCH * 0.75, _bundle):
			sides.append(s)
	if sides.is_empty():
		return 0.0
	return sides[_rng.randi_range(0, sides.size() - 1)]


func _carry_bundle() -> void:
	if _bundle.is_empty() or phase == Phase.TO_PILE or phase == Phase.SETTLE_PILE or phase == Phase.DESCEND_PILE:
		return
	var t := 1.0
	if phase == Phase.GRAB:
		t = smoothstep(0.0, 1.0, clampf(_timer / _grab_time(), 0.0, 1.0))
	var rot_xf := _rotator.global_transform
	for i in range(_bundle.size()):
		var l := _bundle[i]
		if is_instance_valid(l):
			l.global_transform = rot_xf * _bundle_start[i].interpolate_with(_bundle_slot[i], t)


func _grab_time() -> float:
	return (TONG_OPEN - BUNDLE_TONG.get(_bundle.size(), 0.2)) / tong_rate


# --- Deck tidying -----------------------------------------------------------------

## Looks the deck over; starts a push or a re-place for the first riding log, or goes
## back to the pile when every log lies on the chains.
func _inspect_deck() -> void:
	var rider := _find_rider()
	if rider == null:
		_fix_log = null
		_fix_pushes = 0
		var skewed := _find_skewed()
		if skewed:
			_regrapple_square(skewed)
			return
		_hold_deck(false)
		_start_to_pile()
		return
	_hold_deck(true)
	if rider != _fix_log:
		_fix_log = rider
		_fix_pushes = 0
	var target_z := NAN
	# Most of the time the operator shoves it off; sometimes they just pick it up.
	if _fix_pushes < max_pushes and (_fix_pushes > 0 or _rng.randf() > 0.2):
		target_z = _push_target_z(rider)
	if not is_nan(target_z):
		_fix_pushes += 1
		_plan_push(rider, target_z)
		return
	# Pushing has not worked or has nowhere to go: lift the log off and set it down clear.
	var spot := _free_chain_z(rider)
	if is_nan(spot):
		# Deck is full: let the chains run so the stops can meter logs off, then look again.
		_hold_deck(false)
		_set_tip_height(_hover_height())
		_enter(Phase.FIX_CHECK)
		_timer = -2.0
		return
	var rider_local := _deck.to_local(rider.global_position)
	_drop_local = Vector3(rider_local.x, 0.0, spot)
	_replacing = true
	_fix_log = null
	_fix_pushes = 0
	var one: Array[RigidBody3D] = [rider]
	_start_pick(one, _deck.global_basis.x)


func _plan_push(rider: RigidBody3D, target_z: float) -> void:
	var p := _deck.to_local(rider.global_position)
	var on_chains := _deck_local_on_chains(rider)
	_fix_supports.clear()
	for l in _deck_logs():
		var q := _deck_local_on_chains(l)
		if l != rider and q.y < RIDER_HEIGHT and absf(q.z - on_chains.z) < LOG_PITCH:
			_fix_supports.append(l)
	var s := signf(target_z - p.z)
	var reach := LOG_RADIUS + PADDLE_HALF.z
	# Every push is set up a little differently: where along the log the grapple bites,
	# how far back it starts, how low it rides, how hard and how far it shoves, and the
	# grapple turned a few degrees off square.
	var slop := _sloppiness()
	var along := clampf(p.x + _rng.randf_range(-0.9, 0.9) * slop, DECK_SPAN_MIN.x + 0.6, DECK_SPAN_MAX.x - 0.6)
	var start_local := Vector3(along, p.y, p.z - s * (reach + _rng.randf_range(0.05, 0.25)))
	# A green operator sometimes stops short and has to have another go.
	var end_local := Vector3(along, p.y, target_z - s * (reach - _rng.randf_range(-0.12 * slop, 0.14)))
	# Paddle bottom a little under the rider's centre, clear of the log it rides on.
	var paddle_bottom := rider.global_position.y - _rng.randf_range(0.03, 0.12)
	var pin_y := paddle_bottom - (PADDLE_CENTRE.y - PADDLE_HALF.y)
	_line_from = _deck.to_global(start_local)
	_line_from.y = pin_y
	_line_to = _deck.to_global(end_local)
	_line_to.y = pin_y
	_push_speed = push_speed * _rng.randf_range(0.8, 1.15)
	_goal_log_axis = _deck.global_basis.x.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-7.0, 7.0) * slop))
	_goal_tong = 0.0
	_set_goal_world(_line_from, pin_y + _rng.randf_range(0.6, 1.2))
	_enter(Phase.FIX_TO)


## A deck log, at rest, riding on top of another one and within reach. Nearest the
## infeed end first, since that is where the next bundle has to go.
func _find_rider() -> RigidBody3D:
	if _deck == null:
		return null
	var best: RigidBody3D = null
	var best_z := -INF
	for l in _deck_logs():
		var p := _deck_local_on_chains(l)
		if p.y > RIDER_HEIGHT and l.linear_velocity.length() < 0.3 and _can_reach(l.global_position) and p.z > best_z:
			best = l
			best_z = p.z
	return best


## Nothing on the deck is still rolling, sliding or dropping (chain travel aside).
func _deck_calm() -> bool:
	for l in _deck_logs():
		var v := l.linear_velocity
		if absf(v.y) > 0.05 or Vector2(v.x, v.z).length() > 0.3 or l.angular_velocity.length() > 0.2:
			return false
	return true


## A log lying on the chains turned well off square to the deck, at rest and in reach.
## It would jam the stops or go into the debarker crooked.
func _find_skewed() -> RigidBody3D:
	var deck_axis := _deck.global_basis.x.normalized()
	for l in _deck_logs():
		var p := _deck_local_on_chains(l)
		if p.y > RIDER_HEIGHT or l.linear_velocity.length() > 0.2 or not _can_reach(l.global_position):
			continue
		var axis := l.global_basis.x.normalized()
		var off := rad_to_deg(acos(clampf(absf(Vector2(axis.x, axis.z).normalized().dot(
			Vector2(deck_axis.x, deck_axis.z).normalized())), 0.0, 1.0)))
		if off > SKEW_LIMIT_DEG:
			return l
	return null


## Pick a turned log up, square it in the tongs and set it back down where it was (or
## on the nearest free chain if that spot has since filled).
func _regrapple_square(l: RigidBody3D) -> void:
	var p := _deck_local_on_chains(l)
	var spot := p.z if _chain_spot_free(clampf(p.z, CHAIN_Z_LIMITS.x, CHAIN_Z_LIMITS.y), l) else _free_chain_z(l)
	if is_nan(spot):
		_hold_deck(false)
		_start_to_pile()
		return
	_hold_deck(true)
	_drop_local = Vector3(clampf(p.x, DECK_SPAN_MIN.x + 0.8, DECK_SPAN_MAX.x - 0.8), 0.0,
		clampf(spot, CHAIN_Z_LIMITS.x, CHAIN_Z_LIMITS.y))
	_replacing = true
	var one: Array[RigidBody3D] = [l]
	# Come in with the rotator turned to the log as it lies; the tongs square it up.
	_start_pick(one, l.global_basis.x)


## Where to push a rider: just past the log(s) it rests on, on whichever side has free
## chain, preferring the shorter push. NAN when neither side is free.
func _push_target_z(rider: RigidBody3D) -> float:
	var p := _deck_local_on_chains(rider)
	var low := INF
	var high := -INF
	for l in _deck_logs():
		if l == rider:
			continue
		var q := _deck_local_on_chains(l)
		if q.y < RIDER_HEIGHT and absf(q.z - p.z) < LOG_PITCH and absf(q.x - p.x) < 4.0:
			low = minf(low, q.z)
			high = maxf(high, q.z)
	if low == INF:
		return NAN
	var options := [high + LOG_PITCH, low - LOG_PITCH]
	options.sort_custom(func(a: float, b: float) -> bool: return absf(a - p.z) < absf(b - p.z))
	# Usually the shorter push, but not always.
	if _rng.randf() < 0.3:
		options.reverse()
	for z: float in options:
		if _chain_spot_free(z, rider) and _can_reach(_deck.to_global(Vector3(p.x, 0.0, z))):
			return z
	return NAN


## Nearest free spot on the chains for a log picked off the pile-up; NAN if none.
func _free_chain_z(rider: RigidBody3D) -> float:
	var p := _deck_local_on_chains(rider)
	var best := NAN
	var z := CHAIN_Z_LIMITS.y
	while z >= CHAIN_Z_LIMITS.x:
		if _chain_spot_free(z, rider) and _can_reach(_deck.to_global(Vector3(p.x, 0.0, z))):
			if is_nan(best) or absf(z - p.z) < absf(best - p.z):
				best = z
		z -= 0.05
	return best


func _chain_spot_free(z: float, ignore: RigidBody3D) -> bool:
	var skip: Array[RigidBody3D] = [ignore]
	return _chain_spot_free_ignoring(z, skip)


func _chain_spot_free_ignoring(z: float, ignore: Array[RigidBody3D]) -> bool:
	if z < CHAIN_Z_LIMITS.x or z > CHAIN_Z_LIMITS.y:
		return false
	for l in _deck_logs():
		if ignore.has(l):
			continue
		if absf(_deck_local_on_chains(l).z - z) < LOG_PITCH - 0.02:
			return false
	return true


## Loose logs on this deck (not frozen, not in the grapple).
func _deck_logs() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if _deck == null:
		return out
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze or _bundle.has(l):
			continue
		var p := _deck.to_local(l.global_position)
		if p.x > DECK_SPAN_MIN.x and p.x < DECK_SPAN_MAX.x and p.z > DECK_SPAN_MIN.z and p.z < DECK_SPAN_MAX.z:
			var h := _deck_local_on_chains(l).y
			if h > DECK_SPAN_MIN.y and h < DECK_SPAN_MAX.y:
				out.append(l)
	return out


## Deck-local position with y measured as the log centre's height above lying on the chains.
func _deck_local_on_chains(l: Node3D) -> Vector3:
	var p := _deck.to_local(l.global_position)
	var deck_origin := _deck.global_position
	p.y -= _deck.to_local(Vector3(deck_origin.x, _deck_top(), deck_origin.z)).y + LOG_RADIUS
	return p


func _can_reach(world: Vector3) -> bool:
	var p := _base_local(world)
	var r := Vector2(p.x, p.z).length()
	return r > 2.2 and r < _foot.x + _l1 + _l2 - 0.5


func _hold_supports(on: bool) -> void:
	for l in _fix_supports:
		if not is_instance_valid(l):
			continue
		if on:
			l.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			l.freeze = true
		else:
			l.freeze = false
			l.linear_velocity = Vector3.ZERO
	if not on:
		_fix_supports.clear()


func _hold_deck(on: bool) -> void:
	if _deck_stops and "hold_chains" in _deck_stops:
		_deck_stops.hold_chains = on


## Straight-line tip moves for the push: the aim point walks the line at push speed.
func _follow_line(delta: float) -> void:
	if phase != Phase.FIX_PUSH:
		return
	var length := _line_from.distance_to(_line_to)
	_line_s = minf(_line_s + _push_speed * delta, length)
	var p := _line_from.lerp(_line_to, _line_s / maxf(length, 0.001))
	_set_goal_world(p, p.y)


func _build_pusher() -> void:
	# The closed tongs as a solid paddle. It only collides while pushing, so the open
	# grapple never knocks logs about on its way in.
	_pusher = AnimatableBody3D.new()
	_pusher.name = "GrapplePusher"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PADDLE_HALF * 2.0
	shape.shape = box
	shape.position = PADDLE_CENTRE
	_pusher.add_child(shape)
	_rotator.add_child(_pusher)
	# An AnimatableBody3D only syncs when its own transform changes, not when a parent
	# moves, so it is top-level and placed on the rotator every physics frame.
	_pusher.top_level = true
	_pusher.global_transform = _rotator.global_transform
	_set_pusher(false)


func _set_pusher(on: bool) -> void:
	_pusher.collision_layer = 1 if on else 0
	_pusher.collision_mask = 1 if on else 0


# --- Targets and checks -----------------------------------------------------------

func _set_goal_world(world: Vector3, height_world: float) -> void:
	var p := _base_local(world)
	_goal_slew = _slew + wrapf(atan2(-p.z, p.x) - _slew, -PI, PI)
	_goal_tip = Vector2(Vector2(p.x, p.z).length(), _base_height(height_world))


func _set_tip_height(height_world: float) -> void:
	_goal_tip.y = _base_height(height_world)


## The base stands upright, so a world height maps to base space by an offset.
func _base_height(height_world: float) -> float:
	return height_world - (_turret.get_parent() as Node3D).global_position.y


func _arrived() -> bool:
	return absf(_goal_slew - _slew) < 0.005 and absf(_slew_vel) < 0.02 \
		and _tip.distance_to(_goal_tip) < 0.02 \
		and absf(_boom_angle - _ik_boom) < 0.01 and absf(_stick_angle - _ik_stick) < 0.01 \
		and absf(_rot_yaw - _goal_rot_yaw()) < 0.03


## 1.3 for a green operator down to 0.5 for a veteran: scales how loosely they line up.
func _sloppiness() -> float:
	return lerpf(1.3, 0.5, operator_skill)


func _settled() -> bool:
	# A veteran works with a little swing still in the grapple; a beginner waits it out.
	var tolerance := settle_angle * lerpf(0.7, 1.4, operator_skill)
	var hang := (_dangle.global_position - _bob).normalized()
	return hang.angle_to(Vector3.UP) < tolerance and (_bob_vel - _pin_velocity).length() < 0.15


func _settle_wait() -> float:
	return settle_timeout * lerpf(1.3, 0.7, operator_skill)


func _hover_height() -> float:
	return maxf(_pile_top(), _deck_top()) + swing_clearance + _clearance_jitter


func _pick_height() -> float:
	var top := -INF
	for l in _bundle:
		if is_instance_valid(l):
			top = maxf(top, l.global_position.y)
	var slot_top := -INF
	for s in BUNDLE_SLOTS[_bundle.size()]:
		slot_top = maxf(slot_top, s.y)
	return top - slot_top


## Stick tip height at which the load hangs clear of the pile or deck it came off.
func _lift_clear_height() -> float:
	var under := _deck_top() + 2.0 * LOG_RADIUS if _replacing else _pile_top()
	return under + _bundle_hang() + 0.5


func _drop_height() -> float:
	# Set the load down with its bottom a few centimetres off the chains.
	return _deck_top() + 0.05 + _bundle_hang()


## Distance from the stick tip pin down to the bottom of the carried logs.
func _bundle_hang() -> float:
	if _bundle.is_empty():
		return 2.1
	var low := 0.0
	for s in BUNDLE_SLOTS[_bundle.size()]:
		low = minf(low, s.y)
	return -low + LOG_RADIUS


func _pile_top() -> float:
	return _pile.top_height() if _pile else global_position.y


func _deck_top() -> float:
	if _deck == null:
		return global_position.y
	for child in _deck.get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			return _deck.to_global(cs.position + Vector3(0.0, (cs.shape as BoxShape3D).size.y * 0.5, 0.0)).y
	return _deck.global_position.y + 1.15


func _deck_has_room() -> bool:
	if _deck == null:
		return true
	var deck_origin := _deck.global_position
	var top_local := _deck.to_local(Vector3(deck_origin.x, _deck_top(), deck_origin.z)).y
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or _bundle.has(l):
			continue
		var p := _deck.to_local(l.global_position) - Vector3(0.0, top_local, 0.0)
		if p.x > DECK_ROOM_MIN.x and p.x < DECK_ROOM_MAX.x and p.y > DECK_ROOM_MIN.y and p.y < DECK_ROOM_MAX.y \
				and p.z > DECK_ROOM_MIN.z and p.z < DECK_ROOM_MAX.z:
			return false
	return true


func _tip_height_world() -> float:
	return _dangle.global_position.y


func _base_local(world: Vector3) -> Vector3:
	return (_turret.get_parent() as Node3D).to_local(world)


# --- Hydraulics ---------------------------------------------------------------------

var _ik_boom: float = 0.0
var _ik_stick: float = 0.0
var _pin_velocity := Vector3.ZERO


func _drive(delta: float) -> void:
	# Slew: speed profile toward the goal angle, braking early (the 0.7 leaves room for
	# the ramp lag) and easing into each speed change rather than snapping to it.
	var err := _goal_slew - _slew
	var want := signf(err) * minf(slew_speed * _pace, sqrt(2.0 * slew_accel * 0.7 * absf(err)))
	_slew_vel += clampf((want - _slew_vel) / ramp_time, -slew_accel, slew_accel) * delta
	_slew += _slew_vel * delta
	if absf(err) < 0.002 and absf(_slew_vel) < 0.01:
		_slew = _goal_slew
		_slew_vel = 0.0

	# Tip radius/height: straight-line moves with the same profile, creeping on the last
	# approach to logs.
	var to_goal := _goal_tip - _tip
	var dist := to_goal.length()
	var top_speed := tip_speed * _pace
	if _creeping():
		# Full speed most of the way down, easing to a creep for the last half metre.
		top_speed = minf(top_speed, creep_speed + 0.9 * dist)
	var want_v := minf(top_speed, sqrt(2.0 * tip_accel * 0.7 * dist))
	_tip_vel += clampf((want_v - _tip_vel) / ramp_time, -tip_accel, tip_accel) * delta
	_tip_vel = maxf(_tip_vel, 0.0)
	if dist > 0.0005:
		_tip += to_goal / dist * minf(_tip_vel * delta, dist)
	else:
		_tip_vel = 0.0

	_solve_ik(_tip)
	_boom_angle = move_toward(_boom_angle, _ik_boom, boom_rate * delta)
	_stick_angle = move_toward(_stick_angle, _ik_stick, stick_rate * delta)
	_rot_yaw = move_toward(_rot_yaw, _goal_rot_yaw(), rotator_rate * delta)
	_tong = move_toward(_tong, _goal_tong, tong_rate * delta)


## Moves where the grapple is coming down onto logs, or the deck, at close quarters.
func _creeping() -> bool:
	return phase in [Phase.DESCEND_PILE, Phase.DESCEND_DECK, Phase.FIX_LOWER, Phase.FIX_BACKOFF, Phase.RETURN_LOWER]


func _solve_ik(tip: Vector2) -> void:
	var r := tip.x - _foot.x
	var h := tip.y - (_turret.position.y + _foot.y)
	var d := clampf(Vector2(r, h).length(), absf(_l1 - _l2) + 0.05, _l1 + _l2 - 0.05)
	var cos_b := clampf((d * d - _l1 * _l1 - _l2 * _l2) / (2.0 * _l1 * _l2), -1.0, 1.0)
	var b := -acos(cos_b)
	var a := atan2(h, r) - atan2(_l2 * sin(b), _l1 + _l2 * cos(b))
	if a < BOOM_LIMITS.x or a > BOOM_LIMITS.y:
		# Boom on its stop: point the stick from the knuckle straight at the target.
		a = clampf(a, BOOM_LIMITS.x, BOOM_LIMITS.y)
		var knuckle := Vector2(cos(a), sin(a)) * _l1
		var to_target := Vector2(r, h) - knuckle
		b = wrapf(atan2(to_target.y, to_target.x) - a, -PI, PI)
	_ik_boom = a
	_ik_stick = clampf(b, STICK_LIMITS.x, STICK_LIMITS.y)


func _goal_rot_yaw() -> float:
	if _dangle == null:
		return 0.0
	var local := _dangle.global_basis.inverse() * _goal_log_axis
	var yaw := atan2(-local.z, local.x)
	# Logs are symmetric end for end: take whichever way round is closer.
	var alt := yaw + PI
	var a := _rot_yaw + wrapf(yaw - _rot_yaw, -PI, PI)
	var b := _rot_yaw + wrapf(alt - _rot_yaw, -PI, PI)
	return a if absf(a - _rot_yaw) <= absf(b - _rot_yaw) else b


func _apply_joints() -> void:
	_turret.rotation.y = _slew
	_boom.rotation.z = _boom_angle
	_stick.rotation.z = _stick_angle


func _pendulum_length() -> float:
	return 0.85 if _bundle.is_empty() or phase == Phase.DESCEND_PILE else 1.55


func _swing_pendulum(delta: float) -> void:
	var pin := _dangle.global_position
	_pin_velocity = (pin - _pin_prev) / maxf(delta, 0.0001)
	_pin_prev = pin
	var length := _pendulum_length()
	if _dangle_brake:
		# Dangle brake on: the grapple is held plumb under the stick tip.
		_bob = pin + Vector3.DOWN * length
		_bob_vel = _pin_velocity
		return
	var rel_vel := _bob_vel - _pin_velocity
	rel_vel *= exp(-swing_damping * delta)
	_bob_vel = _pin_velocity + rel_vel + GRAVITY * delta
	var old := _bob
	_bob += _bob_vel * delta
	var hang := _bob - pin
	if hang.length() < 0.001:
		hang = Vector3.DOWN
	# Keep the swing inside what the dangle link stops allow.
	var dir := hang.normalized()
	if dir.angle_to(Vector3.DOWN) > deg_to_rad(55.0):
		var axis := Vector3.DOWN.cross(dir).normalized()
		dir = Vector3.DOWN.rotated(axis, deg_to_rad(55.0))
	_bob = pin + dir * length
	_bob_vel = (_bob - old) / maxf(delta, 0.0001)


func _apply_grapple() -> void:
	var up := (_dangle.global_position - _bob).normalized()
	var heading := _turret.global_basis.x
	var x := (heading - up * heading.dot(up)).normalized()
	var z := x.cross(up)
	_dangle.global_basis = Basis(x, up, z)
	_rotator.rotation.y = _rot_yaw
	_tong_a.rotation.x = _tong
	_tong_b.rotation.x = -_tong
	if _pusher:
		_pusher.global_transform = _rotator.global_transform


func _aim_cylinders() -> void:
	for c in _cylinders:
		var barrel: Node3D = c[0]
		var rod: Node3D = c[1]
		if barrel == null or rod == null:
			continue
		var pin_axis: Vector3
		match c[2]:
			0:
				pin_axis = -_turret.global_basis.z
			1:
				pin_axis = -_boom.global_basis.z
			_:
				pin_axis = _rotator.global_basis.x
		var a := barrel.global_position
		var b := rod.global_position
		barrel.look_at(b, pin_axis)
		rod.look_at(a, pin_axis)
