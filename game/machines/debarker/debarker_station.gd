extends Node3D

## debarker_station.gd
## Rotary ring debarker line (model built by dev/blender/debarker): the log decks drop logs
## onto the V-roll infeed; when a log's nose reaches the spiked infeed rolls it is gripped
## and driven through the ring at feed speed, centred on the ring axis; the top rolls ride
## up onto it, the six tool arms spring open onto the bark as it passes the rotor and the
## bark peels off down the chute onto the bark belt; once its tail clears the outfeed rolls
## it is let go onto the V-roll outfeed, which carries it on to the kicker conveyor.
##
## The deck stops ask can_accept_log() before dumping, so only one log waits on the infeed
## while another is in the machine; the infeed is held while the next log would run into
## the feed rolls early.

const LOG_RADIUS := 0.292
## Tool arm geometry (dev/blender/debarker/db_build.py).
const TOOL_PIVOT_R := 0.64
const TOOL_LEN := 0.56
const TOOL_CLOSED_R := 0.08
## Feed rolls from the ring plane, and their contact radius.
const FEED_IN_DX := -1.0
const FEED_OUT_DX := 1.05
const FEED_ROLL_R := 0.33
## Top press roll arms park raised this far above the log line, come down onto a log
## once it is under the roll, and lift clear again when its tail has passed.
const ARM_REST := deg_to_rad(15.0)

@export var running: bool = true
## Feed speed through the ring (real machines run 30-50 m/min).
@export var feed_speed: float = 0.6
@export var rotor_rpm: float = 150.0
@export var outfeed_speed: float = 0.8

@onready var infeed: StaticBody3D = $DebarkInfeedConveyor
@onready var outfeed: StaticBody3D = $DebarkOutfeedConveyor
@onready var infeed_area: Area3D = $DebarkInfeedConveyor/LogArea

var _rotor: Node3D
var _tools: Array[Node3D] = []
var _in_arm: Node3D
var _out_arm: Node3D
var _rolls_bottom: Array[Node3D] = []
var _rolls_top: Array[Node3D] = []
var _cylinders: Array = []   # [barrel, rod]
var _axis_node: Node3D

var _ring_x: float
var _line := Vector2.ZERO        # (y, z) of the ring axis
var _carry: RigidBody3D = null
var _carry_half: float = 2.46
var _carry_v: float = 0.0
var _carry_align: float = 0.0
var _carry_from: Transform3D
var _carry_basis: Basis
var _tool_r: float = TOOL_CLOSED_R
var _in_angle: float = ARM_REST
var _out_angle: float = ARM_REST
var _since_accept: float = 99.0


func _ready() -> void:
	var machine := $MachineModel as Node3D
	_rotor = machine.find_child("DB_Rotor", true, false)
	for k in range(6):
		_tools.append(machine.find_child("DB_Tool%d" % (k + 1), true, false))
	_in_arm = machine.find_child("DB_InTopArm", true, false)
	_out_arm = machine.find_child("DB_OutTopArm", true, false)
	_rolls_bottom = [machine.find_child("DB_InBottomRoll", true, false), machine.find_child("DB_OutBottomRoll", true, false)]
	_rolls_top = [machine.find_child("DB_InTopRoll", true, false), machine.find_child("DB_OutTopRoll", true, false)]
	for side in ["In", "Out"]:
		_cylinders.append([machine.find_child("DB_%sArmCylBarrel" % side, true, false),
			machine.find_child("DB_%sArmCylRod" % side, true, false)])
	_axis_node = machine
	_rotor.add_to_group("debarker_ring")
	_ring_x = _rotor.global_position.x
	_line = Vector2(_rotor.global_position.y, _rotor.global_position.z)
	outfeed.speed = outfeed_speed
	_pose(0.0)


## Asked by the deck stops before they drop a log: true when the infeed is clear and the
## last log has had time to land and move off.
func can_accept_log() -> bool:
	if not running or _since_accept < 3.0:
		return false
	for body in infeed_area.get_overlapping_bodies():
		if body.is_in_group("logs"):
			return false
	_since_accept = 0.0
	return true


func _physics_process(delta: float) -> void:
	_since_accept += delta
	if not running:
		infeed.hold = true
		_pose(delta)
		return
	if _carry == null:
		_try_capture()
	else:
		_feed(delta)
	infeed.hold = _carry != null and _next_log_at_rolls()
	_pose(delta)


func _try_capture() -> void:
	var grip_x := _ring_x + FEED_IN_DX - 0.15
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := l.global_position
		if absf(p.z - _line.y) > 0.45 or absf(p.y - _line.x) > 0.45 or p.x > _ring_x:
			continue
		var half := _half_length(l)
		if p.x + half * absf(l.global_basis.x.normalized().x) < grip_x:
			continue
		_carry = l
		_carry_half = half
		l.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		l.freeze = true
		_carry_from = l.global_transform
		var axis := l.global_basis.x.normalized()
		var target := Vector3.RIGHT if axis.x >= 0.0 else Vector3.LEFT
		_carry_basis = Basis(Quaternion(axis, target)) * l.global_basis.orthonormalized()
		_carry_align = 0.0
		_carry_v = infeed.constant_linear_velocity.x
		return


func _feed(delta: float) -> void:
	if not is_instance_valid(_carry):
		_carry = null
		return
	# The spiked rolls bite and bring the log up to feed speed; it is pulled onto the ring
	# axis over the first half second.
	# The feed rolls stop (the ring keeps turning) while the log ahead on the outfeed is held
	# close in front, so the log coming through never shoves it on into a full trough.
	var target_v := feed_speed
	if outfeed.hold and _gap_ahead() < 0.4:
		target_v = 0.0
	_carry_v = move_toward(_carry_v, target_v, 1.2 * delta)
	_carry_align = minf(1.0, _carry_align + delta / 0.5)
	var xf := _carry.global_transform
	var pos := xf.origin + Vector3.RIGHT * _carry_v * delta
	var a := smoothstep(0.0, 1.0, _carry_align)
	pos.y = lerpf(_carry_from.origin.y, _line.x, a)
	pos.z = lerpf(_carry_from.origin.z, _line.y, a)
	_carry_from.origin.x = pos.x
	_carry.global_transform = Transform3D(_carry_from.basis.slerp(_carry_basis, a), pos)
	if pos.x - _carry_half > _ring_x + FEED_OUT_DX + 0.3:
		# Tail is through the outfeed rolls: hand the log to the outfeed conveyor.
		_carry.freeze = false
		_carry.linear_velocity = Vector3.RIGHT * _carry_v
		_carry.angular_velocity = Vector3.ZERO
		_carry = null


## Clear distance from the carried log's nose to the tail of the next log out on the outfeed.
func _gap_ahead() -> float:
	var nose := _carry.global_position.x + _carry_half
	var gap := INF
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l == _carry or l.freeze:
			continue
		var p := l.global_position
		if absf(p.z - _line.y) > 0.6 or p.x < nose:
			continue
		gap = minf(gap, p.x - _half_length(l) - nose)
	return gap


var _feed_roll_v: float = 0.0


func _process(delta: float) -> void:
	# Bottom rolls' tops and top rolls' bottoms both move +X with the log. Drawn per frame,
	# capped (RollSpin).
	var s := RollSpin.step(_feed_roll_v / FEED_ROLL_R, delta)
	for r in _rolls_bottom:
		r.rotation.z -= s
	for r in _rolls_top:
		r.rotation.z += s


func _next_log_at_rolls() -> bool:
	var stop_x := _ring_x + FEED_IN_DX - 0.5
	for body in infeed_area.get_overlapping_bodies():
		var l := body as RigidBody3D
		if l and l != _carry and l.is_in_group("logs"):
			if l.global_position.x + _half_length(l) >= stop_x:
				return true
	return false


func _half_length(l: RigidBody3D) -> float:
	if l.has_method("get_log_core_length"):
		return l.get_log_core_length() * 0.5
	return 2.46


## Rotor, tools, top rolls, feed rolls and cylinders follow the log.
func _pose(delta: float) -> void:
	var v := _carry_v if _carry else 0.0
	if running:
		_rotor.rotation.x += rotor_rpm * TAU / 60.0 * delta
	var in_x := _ring_x + FEED_IN_DX
	var out_x := _ring_x + FEED_OUT_DX
	var front := -INF
	var tail := INF
	if _carry:
		front = _carry.global_position.x + _carry_half
		tail = _carry.global_position.x - _carry_half
	# Tools spring open as the nose comes through and ride the bark until the tail passes.
	var tool_target := LOG_RADIUS if front > _ring_x - 0.05 and tail < _ring_x + 0.25 else TOOL_CLOSED_R
	_tool_r = move_toward(_tool_r, tool_target, 3.0 * delta)
	var tool_angle := acos(clampf((TOOL_PIVOT_R * TOOL_PIVOT_R + TOOL_LEN * TOOL_LEN - _tool_r * _tool_r)
		/ (2.0 * TOOL_PIVOT_R * TOOL_LEN), -1.0, 1.0))
	for t in _tools:
		t.rotation.x = tool_angle
	# Press rolls come down once the log nose is under them and lift when the tail clears.
	var in_target := 0.0 if front > in_x + 0.1 and tail < in_x - 0.05 else ARM_REST
	var out_target := 0.0 if front > out_x + 0.1 and tail < out_x - 0.05 else ARM_REST
	_in_angle = move_toward(_in_angle, in_target, 1.2 * delta)
	_out_angle = move_toward(_out_angle, out_target, 1.2 * delta)
	# The infeed arm reaches +X from its pivot, the outfeed arm -X: they lift opposite ways.
	_in_arm.rotation.z = _in_angle
	_out_arm.rotation.z = -_out_angle
	_feed_roll_v = v
	var pin_axis := -_axis_node.global_basis.z
	for c in _cylinders:
		var barrel: Node3D = c[0]
		var rod: Node3D = c[1]
		var a := barrel.global_position
		var b := rod.global_position
		barrel.look_at(b, pin_axis)
		rod.look_at(a, pin_axis)
