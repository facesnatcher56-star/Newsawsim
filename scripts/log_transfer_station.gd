@tool
extends Node3D

## LogTransferStation
## Kicker-style log transfer at the top of the incline.
##
## Sequence:
##   1. Log rides up incline and hits the STOP BAR (AnimatableBody3D).
##   2. Chain pauses. Station waits for carriage WAITING_FOR_LOG.
##   3. KICKER ARMS (AnimatableBody3D) swing up from below the deck surface,
##      throwing the log laterally off the stop and toward the carriage.
##   4. After arms reach full swing, they retract. Incline resumes.

@export var incline_path: NodePath
@export var carriage_path: NodePath
## Assign an Area3D in the scene to use as the catch zone (so you can see and
## move it in the editor). If left empty, one is built automatically at runtime.
@export var catch_zone: Area3D
## How far the kicker arms swing (degrees). 90 = fully vertical, 120 = past vertical.
@export var kick_swing_deg: float = 115.0
## Speed of arm swing in degrees/sec.
@export var swing_speed_deg: float = 140.0
## Seconds arms hold at full swing before retracting.
@export var hold_at_top: float = 0.25
## Seconds after arms fully retract before incline resumes.
@export var resume_delay: float = 0.6
## Width spanning the incline (match your incline_width).
@export var deck_width: float = 2.4
## Number of kicker arms across the width.
@export var arm_count: int = 3
## Arm length from pivot to tip.
@export var arm_length: float = 0.55

# ── Geometry ─────────────────────────────────────────────────────────────────
const STOP_H       := 0.38
const STOP_D       := 0.08
const ARM_W        := 0.07
const ARM_D        := 0.06
const PIVOT_Y      := 0.06   # pivot height above local origin (= deck surface)

enum KickerState { IDLE, KICKING, HOLDING, RETRACTING }
var _state: KickerState = KickerState.IDLE
var _arm_angle_deg: float = 0.0   # 0 = arms flush with/below deck, positive = swung up
var _hold_timer: float = 0.0
var _resume_timer: float = 0.0
var _waiting_log: RigidBody3D = null

var _stop_bar: AnimatableBody3D = null
var _arm_pivots: Array[Node3D] = []
var _arm_bodies: Array[AnimatableBody3D] = []

var _incline: Node3D = null
var _carriage: Node  = null


func _ready() -> void:
	_build_stop_bar()
	_build_kicker_arms()

	if Engine.is_editor_hint():
		return

	# Use the exported Area3D if assigned, otherwise build one automatically.
	if catch_zone == null:
		_build_catch_zone()
		catch_zone = get_node_or_null("CatchZone")
	if catch_zone != null:
		catch_zone.body_entered.connect(_on_catch_zone_body_entered)

	if incline_path:
		_incline = get_node_or_null(incline_path)
		if _incline and _incline.has_signal("log_reached_top"):
			_incline.log_reached_top.connect(_on_log_reached_top)
	if carriage_path:
		_carriage = get_node_or_null(carriage_path)


# ─────────────────────────────────────────────────────────────────────────────
#  BUILD
# ─────────────────────────────────────────────────────────────────────────────

func _build_stop_bar() -> void:
	if has_node("StopBar"):
		return
	_stop_bar = AnimatableBody3D.new()
	_stop_bar.name = "StopBar"
	_stop_bar.sync_to_physics = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.20, 0.18)
	mat.metallic     = 0.88
	mat.roughness    = 0.38

	var size := Vector3(deck_width + 0.2, STOP_H, STOP_D)
	var mi   := MeshInstance3D.new()
	mi.name  = "StopMesh"
	var bm   := BoxMesh.new()
	bm.size  = size
	mi.mesh  = bm
	mi.material_override = mat
	_stop_bar.add_child(mi)

	var cs  := CollisionShape3D.new()
	var bs  := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_stop_bar.add_child(cs)

	# Position: face of bar sits at Z=0, bar body extends uphill (-Z)
	_stop_bar.position = Vector3(0.0, STOP_H * 0.5, STOP_D * 0.5)
	add_child(_stop_bar)


func _build_kicker_arms() -> void:
	if has_node("KickerPivots"):
		return

	var pivot_root := Node3D.new()
	pivot_root.name = "KickerPivots"
	add_child(pivot_root)

	var mat_arm := StandardMaterial3D.new()
	mat_arm.albedo_color = Color(0.28, 0.26, 0.22)
	mat_arm.metallic     = 0.85
	mat_arm.roughness    = 0.42

	var mat_pad := StandardMaterial3D.new()
	mat_pad.albedo_color = Color(0.12, 0.10, 0.09)
	mat_pad.metallic     = 0.30
	mat_pad.roughness    = 0.85

	# Spacing arms evenly across deck width
	for i in range(arm_count):
		var t: float = 0.5 if arm_count == 1 else float(i) / float(arm_count - 1)
		var ax: float = lerp(-deck_width * 0.5 + 0.15, deck_width * 0.5 - 0.15, t)

		# Pivot node — rotation happens here
		var pivot := Node3D.new()
		pivot.name = "ArmPivot_%d" % i
		pivot.position = Vector3(ax, PIVOT_Y, -0.05)
		pivot_root.add_child(pivot)
		_arm_pivots.append(pivot)

		# AnimatableBody3D arm — child of pivot so it orbits the pivot
		var arm := AnimatableBody3D.new()
		arm.name = "Arm_%d" % i
		arm.sync_to_physics = true

		# Arm mesh: extends upward from pivot when angle=0 arm is pointing uphill-ish
		# (starts angled slightly below deck so it's hidden, swings CCW to kick)
		var arm_mi := MeshInstance3D.new()
		arm_mi.name = "ArmMesh"
		var arm_bm  := BoxMesh.new()
		arm_bm.size = Vector3(ARM_W, arm_length, ARM_D)
		arm_mi.mesh = arm_bm
		arm_mi.material_override = mat_arm
		arm_mi.position = Vector3(0.0, arm_length * 0.5, 0.0)
		arm.add_child(arm_mi)

		# Rubber tip pad at the end that contacts the log
		var pad_mi := MeshInstance3D.new()
		pad_mi.name = "Pad"
		var pad_bm  := BoxMesh.new()
		pad_bm.size = Vector3(ARM_W + 0.04, 0.06, ARM_D + 0.04)
		pad_mi.mesh = pad_bm
		pad_mi.material_override = mat_pad
		pad_mi.position = Vector3(0.0, arm_length - 0.02, 0.0)
		arm.add_child(pad_mi)

		# Collision shape
		var cs  := CollisionShape3D.new()
		var bs  := BoxShape3D.new()
		bs.size = Vector3(ARM_W, arm_length, ARM_D)
		cs.shape    = bs
		cs.position = Vector3(0.0, arm_length * 0.5, 0.0)
		arm.add_child(cs)

		pivot.add_child(arm)
		_arm_bodies.append(arm)

	# Start arms angled back under the deck surface (negative = arms point downhill/under)
	_set_arm_angle(-15.0)


func _build_catch_zone() -> void:
	if has_node("CatchZone"):
		return
	var zone  := Area3D.new()
	zone.name = "CatchZone"
	var cs    := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Tight zone — only the last 0.5 m right against the stop bar.
	shape.size = Vector3(deck_width, 0.8, 0.5)
	cs.shape    = shape
	cs.position = Vector3(0.0, 0.3, -0.25)
	zone.add_child(cs)
	add_child(zone)


# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _set_arm_angle(deg: float) -> void:
	_arm_angle_deg = deg
	for pivot in _arm_pivots:
		pivot.rotation_degrees.x = deg


# ─────────────────────────────────────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────────────────────────────────────

func _on_log_reached_top(log: RigidBody3D) -> void:
	if _state != KickerState.IDLE or _waiting_log != null:
		return
	_waiting_log = log
	print("[TRANSFER] Log at top — waiting for carriage.")


func _on_catch_zone_body_entered(body: Node3D) -> void:
	if not body.is_in_group("logs") or _waiting_log != null:
		return
	_waiting_log = body as RigidBody3D
	if _incline != null:
		_incline.set_running(false)
	print("[TRANSFER] Log caught at stop bar.")


# ─────────────────────────────────────────────────────────────────────────────
#  LOOP
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match _state:
		KickerState.IDLE:
			if _waiting_log == null or not is_instance_valid(_waiting_log):
				_waiting_log = null
				return
			# Wait until carriage is ready (WAITING_FOR_LOG == 0)
			if _carriage != null and "current_state" in _carriage and _carriage.current_state == 0:
				_state = KickerState.KICKING
				print("[TRANSFER] Carriage ready — kicking log.")

		KickerState.KICKING:
			_arm_angle_deg = move_toward(_arm_angle_deg, kick_swing_deg, swing_speed_deg * delta)
			_set_arm_angle(_arm_angle_deg)
			if _arm_angle_deg >= kick_swing_deg:
				_state      = KickerState.HOLDING
				_hold_timer = hold_at_top
				_waiting_log = null   # arms have thrown it — physics takes over
				print("[TRANSFER] Arms at full swing.")

		KickerState.HOLDING:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_state = KickerState.RETRACTING
				print("[TRANSFER] Arms retracting.")

		KickerState.RETRACTING:
			_arm_angle_deg = move_toward(_arm_angle_deg, -15.0, swing_speed_deg * delta)
			_set_arm_angle(_arm_angle_deg)
			if _arm_angle_deg <= -15.0:
				_state        = KickerState.IDLE
				_resume_timer = resume_delay
				print("[TRANSFER] Arms reset. Resuming incline in %.1fs." % resume_delay)

	# Resume incline after arms have cleared
	if _resume_timer > 0.0:
		_resume_timer -= delta
		if _resume_timer <= 0.0 and _incline != null:
			_incline.set_running(true)
			print("[TRANSFER] Incline resumed.")
