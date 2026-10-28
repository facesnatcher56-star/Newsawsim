class_name Forklift
extends VehicleBody3D

## Heavy lumber-yard forklift (about 13 t empty, Hyster XD class). Model: dev/blender/forklift/
## forklift_build.py. Drives itself: waits behind the green stacker's landing deck, drives the
## forks in between the lift rails under a finished package, lifts it, backs out, swings
## round and sets it down on 4x4 bunks in a yard row, then comes back.
##
## Physics: a VehicleBody3D with four raycast wheels (front drive, rear steer, as on the real
## truck), its real mass with the centre of mass toward the counterweight, and collision for
## the body, mast, carriage and forks (the carriage and fork colliders move with the lift).
## A package on the forks rides with the carriage and its weight is added to the truck: the
## mass goes up and the centre of mass moves forward, so it accelerates and brakes like the
## loaded truck. Set down, the package is a free body again.
##
## Model frame (as exported): +X forward, +Y up, +Z to the truck's right, origin on the ground
## under the middle of the drive axle. VehicleBody3D drives along +Z, so the model is turned
## -90 degrees about Y inside the body: model (x, y, z) is body (-z, y, x).

const MODELS := "res://game/assets/models/forklift/"

const WHEELBASE := 2.85
const TYRE_R := 0.55
const DRIVE_Z := 1.03
const STEER_Z := 0.93
const FORK_FACE_X := 0.70
const FORK_LEN := 1.8288
const FORK_T := 0.08
const FORK_W := 0.20
const FORK_SPREAD := 1.05
const FREE_LIFT := 1.2                     # carriage rises this far before the inner mast moves
const LIFT_MAX := 3.2
const COM_EMPTY := Vector3(-1.0, 0.9, 0.0)  # model frame: well back, toward the counterweight

# Yard layout in the stacker's frame (x along the line, z across; see the green stacker).
const LANDING_STOP_X := 36.45
const START := Vector2(42.0, 0.0)          # waits here, forks toward the deck (-X)
const ARC_C := Vector2(42.0, -4.0)         # swing-round arc centre, radius 4
const ARC_R := 4.0
## Yard row: packages set down along z, forks toward +Z. In the mill this row runs along the
## north wall inside the building (the far package end is 0.5 m off the wall) and the spots
## stop short of the east wall; the far spot is filled first so the truck never drives past
## a set-down package.
const ROW_X := 46.0
const SPOT_Z: Array[float] = [6.0, 4.2, 2.4, 0.6]
const BUNK_H := 0.10
const BUNK_X: Array[float] = [-2.1, 0.0, 2.1]

@export var stacker: NodePath
## Put the truck at its waiting spot behind the stacker's landing deck on start.
@export var start_at_home: bool = true
@export var empty_mass: float = 13000.0
@export_range(0.5, 5.0, 0.1) var travel_speed: float = 2.2
@export_range(0.1, 1.0, 0.05) var creep_speed: float = 0.4
@export_range(0.05, 1.0, 0.05) var lift_speed: float = 0.35
@export var log_events: bool = false

enum St { WAIT, IN, LIFT, OUT, SWING_BACK, TO_SPOT, LOWER, BACK_OFF, SWING_HOME, DONE }

var _stacker: Node3D
var _state: int = St.WAIT
var _lift: float = 0.5                     # fork bottom height above the ground
var _lift_target: float = 0.5
var _carry: RigidBody3D
var _pkg_bottom_on_forks: float = 0.0
var _spot: int = 0
var _path: PackedVector3Array = PackedVector3Array()
var _path_dir: int = 1
var _path_speed: float = 1.0
var _path_i: int = 0
var _path_done: bool = true
var _clock: float = 0.0
var _still_from: Vector3 = Vector3.ZERO
var _still_t: float = 0.0

var _model: Node3D
var _mast_inner: Node3D
var _carriage: Node3D
var _carriage_shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	mass = empty_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _m2b(COM_EMPTY)
	can_sleep = false
	_model = Node3D.new()
	_model.name = "Model"
	_model.basis = Basis(Vector3.UP, -PI * 0.5)
	add_child(_model)
	_model.add_child(_load_model("forklift_body.glb"))
	_mast_inner = _load_model("forklift_mast_inner.glb")
	_model.add_child(_mast_inner)
	_carriage = Node3D.new()
	_carriage.name = "Carriage"
	_model.add_child(_carriage)
	_carriage.add_child(_load_model("forklift_carriage.glb"))
	# Body collision: counterweight, side bodies, cab, mast (wheels are raycasts).
	_box(Vector3(-2.6, 1.13, 0.0), Vector3(2.0, 1.02, 2.4))
	_box(Vector3(-0.7, 1.02, 0.0), Vector3(2.0, 1.06, 2.4))
	_box(Vector3(-0.75, 2.26, 0.0), Vector3(1.82, 1.42, 1.68))
	_box(Vector3(0.42, 1.9, 0.0), Vector3(0.28, 3.1, 1.5))
	# Carriage plate and the two forks: moved with the lift.
	_carriage_shapes = [_box(Vector3.ZERO, Vector3(0.2, 1.08, 2.4)), _box(Vector3.ZERO, Vector3(FORK_LEN, FORK_T, FORK_W)),
		_box(Vector3.ZERO, Vector3(FORK_LEN, FORK_T, FORK_W))]
	for x: float in [0.0, -WHEELBASE]:
		for side: float in [-1.0, 1.0]:
			_wheel(x, side * (DRIVE_Z if x == 0.0 else STEER_Z), x == 0.0)
	_place_carriage()
	if Engine.is_editor_hint():
		return
	if not stacker.is_empty():
		_stacker = get_node_or_null(stacker) as Node3D
	if _stacker != null:
		if start_at_home:
			# Waiting spot behind the landing deck, forks toward the deck (stacker -X); the
			# truck drives along its own +Z.
			global_transform = _stacker.global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5),
				Vector3(START.x, 0.02, START.y))
		_make_bunks.call_deferred()


## A model scene: the imported one, or read straight from the .glb when the editor hasn't
## imported it yet.
static func _load_model(file: String) -> Node3D:
	var path: String = MODELS + file
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("Forklift: can't load " + path)
		return Node3D.new()
	return doc.generate_scene(state) as Node3D


## Model-frame vector to body frame.
static func _m2b(v: Vector3) -> Vector3:
	return Vector3(-v.z, v.y, v.x)


func _box(centre: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.basis = Basis(Vector3.UP, -PI * 0.5)
	cs.position = _m2b(centre)
	add_child(cs)
	return cs


func _wheel(x: float, z: float, drive: bool) -> void:
	var w := VehicleWheel3D.new()
	w.name = ("Drive" if drive else "Steer") + ("R" if z > 0.0 else "L")
	w.position = _m2b(Vector3(x, TYRE_R + 0.06, z))
	w.wheel_radius = TYRE_R
	w.wheel_rest_length = 0.10
	w.suspension_travel = 0.08
	w.suspension_stiffness = 160.0
	w.suspension_max_force = 400000.0
	w.damping_compression = 0.88
	w.damping_relaxation = 0.92
	w.wheel_friction_slip = 2.5
	w.wheel_roll_influence = 0.05
	w.use_as_traction = drive
	w.use_as_steering = not drive
	add_child(w)
	var m: Node3D = _load_model("forklift_wheel.glb")
	# The wheel model's axle is its Z and its outer face +Z; the wheel rolls about its own X.
	m.basis = Basis(Vector3.UP, -PI * 0.5 if z > 0.0 else PI * 0.5)
	w.add_child(m)


func _place_carriage() -> void:
	_carriage.position = Vector3(0.0, _lift, 0.0)
	_mast_inner.position = Vector3(0.0, maxf(_lift - FREE_LIFT, 0.0), 0.0)
	var fx: float = FORK_FACE_X - 0.04 + FORK_LEN * 0.5
	_carriage_shapes[0].position = _m2b(Vector3(FORK_FACE_X - 0.15, _lift + 0.66, 0.0))
	_carriage_shapes[1].position = _m2b(Vector3(fx, _lift + FORK_T * 0.5, FORK_SPREAD))
	_carriage_shapes[2].position = _m2b(Vector3(fx, _lift + FORK_T * 0.5, -FORK_SPREAD))


# ─────────────────────────────────────────────────────────────────────────────
#  YARD
# ─────────────────────────────────────────────────────────────────────────────

func _s2w(p: Vector2, y: float = 0.0) -> Vector3:
	return _stacker.to_global(Vector3(p.x, y, p.y))


## Bunks for every yard spot: three 4x4s along the fork direction, the forks fit between.
func _make_bunks() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.18)
	wood.roughness = 0.9
	for z: float in SPOT_Z:
		for bx: float in BUNK_X:
			var body := StaticBody3D.new()
			body.name = "YardBunk"
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.09, BUNK_H, 1.6)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = shape.size
			bm.material = wood
			mi.mesh = bm
			body.add_child(mi)
			get_parent().add_child(body)
			body.global_transform = Transform3D(_stacker.global_basis, _s2w(Vector2(ROW_X + bx, z), BUNK_H * 0.5))


# ─────────────────────────────────────────────────────────────────────────────
#  RUN
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _stacker == null:
		return
	_clock += delta
	_track_still(delta)
	if log_events and fposmod(_clock, 5.0) < delta:
		var p: Vector3 = _s2l(global_position)
		_log("status %s at (%.2f, %.2f) speed %.2f lift %.2f->%.2f steer %.2f mass %.0f" % [St.keys()[_state], p.x, p.z,
			_flat(linear_velocity).length(), _lift, _lift_target, steering, mass])
	_update_task()
	_follow(delta)
	_lift = move_toward(_lift, _lift_target, lift_speed * delta)
	_place_carriage()


func _update_task() -> void:
	match _state:
		St.WAIT:
			_lift_target = 0.5
			var pkg: RigidBody3D = _stacker.call("ready_package")
			if pkg != null and _spot < SPOT_Z.size() and _path_done and _stopped():
				var bottom: float = _stacker.to_local(pkg.global_position).y - float(pkg.get_meta("bottom_offset", 0.3))
				_lift_target = bottom - FORK_T - 0.02
				_pkg_bottom_on_forks = bottom
				if absf(_lift - _lift_target) < 0.01:
					_go(St.IN, [START, Vector2(LANDING_STOP_X + 0.10 + FORK_FACE_X, 0.0)], 1, creep_speed)
		St.IN:
			if _path_done and _stopped():
				_lift_target = _pkg_bottom_on_forks + 0.20
				_state = St.LIFT
				_log("forks under the package: lifting")
		St.LIFT:
			if _carry == null and _lift + FORK_T >= _pkg_bottom_on_forks - 0.002:
				_pick_up(_stacker.call("ready_package"))
			if absf(_lift - _lift_target) < 0.005:
				_go(St.OUT, [_path_end_2d(), START], -1, creep_speed)
		St.OUT:
			# Carry low once the fork tips are past the outfeed's head shaft and drive.
			if _s2l(global_position).x > LANDING_STOP_X + 0.3 + FORK_FACE_X + FORK_LEN:
				_lift_target = 0.30
			if _path_done and _stopped():
				_go(St.SWING_BACK, _arc(0.0, 90.0), -1, travel_speed * 0.6)
		St.SWING_BACK:
			if _path_done and _stopped():
				var z: float = SPOT_Z[_spot] - (FORK_FACE_X + _carry_depth() * 0.5)
				_go(St.TO_SPOT, [Vector2(ROW_X, ARC_C.y), Vector2(ROW_X, z)], 1, travel_speed * 0.6)
		St.TO_SPOT:
			if _path_done and _stopped():
				_lift_target = BUNK_H - FORK_T + 0.001 - 0.02
				_state = St.LOWER
				_log("at yard spot %d: setting the package down" % _spot)
		St.LOWER:
			if _carry != null and _lift + FORK_T <= BUNK_H + 0.002:
				_set_down()
			if _carry == null and absf(_lift - _lift_target) < 0.005:
				_go(St.BACK_OFF, [_path_end_2d(), Vector2(ROW_X, ARC_C.y)], -1, travel_speed * 0.5)
		St.BACK_OFF:
			if _path_done and _stopped():
				_spot += 1
				_go(St.SWING_HOME, _arc(90.0, 0.0), 1, travel_speed * 0.6)
		St.SWING_HOME:
			_lift_target = 0.5
			if _path_done and _stopped():
				_state = St.WAIT if _spot < SPOT_Z.size() else St.DONE
				_log("back at the deck" if _state == St.WAIT else "yard row full")


func _carry_depth() -> float:
	if _carry == null:
		return 1.32
	var cs := _carry.get_child(0) as CollisionShape3D
	return (cs.shape as BoxShape3D).size.x if cs != null else 1.32


## Points on the swing arc between the start (phi 0) and the yard row (phi 90).
func _arc(from_deg: float, to_deg: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for k in 25:
		var phi: float = deg_to_rad(lerpf(from_deg, to_deg, float(k) / 24.0))
		pts.append(ARC_C + ARC_R * Vector2(sin(phi), cos(phi)))
	return pts


func _go(state: int, pts: Array, dir: int, speed: float) -> void:
	_state = state
	_path = PackedVector3Array()
	# Densify so the nearest-point search moves smoothly.
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n: int = maxi(1, int(ceil(a.distance_to(b) / 0.1)))
		for k in n:
			_path.append(_s2w(a.lerp(b, float(k) / n)))
	_path.append(_s2w(pts[-1]))
	_path_dir = dir
	_path_speed = speed
	_path_i = 0
	_path_done = false
	_log("%s: %d points, %s" % [St.keys()[state], _path.size(), "forward" if dir > 0 else "reverse"])


func _path_end_2d() -> Vector2:
	var p: Vector3 = _s2l(global_position)
	return Vector2(p.x, p.z)


func _s2l(w: Vector3) -> Vector3:
	return _stacker.to_local(w)


## Not driving anywhere: moved under 2 cm in the last half second. (The raycast wheels leave
## a small reported velocity on a truck standing still, so velocity alone can't tell.)
func _stopped() -> bool:
	return _still_t > 0.5


func _track_still(delta: float) -> void:
	if _flat(global_position - _still_from).length() > 0.02:
		_still_from = global_position
		_still_t = 0.0
	else:
		_still_t += delta


## Pure pursuit on the drive (front) axle. The rear wheels steer, so the wheel angle is the
## opposite of a front-steer car's going forward, and the same going backward.
func _follow(delta: float) -> void:
	var fwd: Vector3 = global_basis.z
	var v_along: float = linear_velocity.dot(fwd)
	if _path_done or _path.is_empty():
		engine_force = 0.0
		brake = mass / 25.0
		steering = move_toward(steering, 0.0, delta)
		return
	var pos: Vector3 = global_position
	var best: float = INF
	for i in range(_path_i, mini(_path_i + 40, _path.size())):
		var d: float = _flat(_path[i] - pos).length()
		if d < best:
			best = d
			_path_i = i
	var remaining: float = 0.0
	for i in range(_path_i, _path.size() - 1):
		remaining += _path[i].distance_to(_path[i + 1])
	var end: Vector3 = _path[-1]
	var travel: Vector3 = fwd * _path_dir
	var last_dir: Vector3 = _flat(_path[-1] - _path[maxi(_path.size() - 2, 0)]).normalized()
	var past_end: bool = _flat(pos - end).dot(last_dir) > -0.02
	if _path_i >= _path.size() - 2 and (past_end or _flat(pos - end).length() < 0.03):
		_path_done = true
		engine_force = 0.0
		brake = mass / 25.0
		return
	var look: float = clampf(1.5 + 0.8 * absf(v_along), 1.5, 3.5)
	var target: Vector3 = end + last_dir * look
	var acc: float = 0.0
	for i in range(_path_i, _path.size() - 1):
		acc += _path[i].distance_to(_path[i + 1])
		if acc >= look:
			target = _path[i + 1]
			break
	var to_t: Vector3 = _flat(target - pos).normalized()
	var t_dir: Vector3 = _flat(travel).normalized()
	var alpha: float = atan2(t_dir.cross(to_t).y, t_dir.dot(to_t))
	var curvature: float = 2.0 * sin(alpha) / look
	var wheel: float = atan(curvature * WHEELBASE) * (-1.0 if _path_dir > 0 else 1.0)
	steering = move_toward(steering, clampf(wheel, -0.75, 0.75), 1.5 * delta)
	# Speed: the path's speed, easing down to stop at the end.
	var v_target: float = minf(_path_speed, sqrt(2.0 * 0.5 * maxf(remaining, 0.0)) + 0.05)
	var v_dir: float = v_along * _path_dir
	var err: float = v_target - v_dir
	engine_force = _path_dir * clampf(err * mass * 1.2, -mass * 0.8, mass * 2.0)
	brake = mass / 40.0 if err < -0.25 else 0.0


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ─────────────────────────────────────────────────────────────────────────────
#  LOAD
# ─────────────────────────────────────────────────────────────────────────────

func _pick_up(pkg: RigidBody3D) -> void:
	if pkg == null:
		return
	_carry = pkg
	pkg.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	pkg.freeze = true
	add_collision_exception_with(pkg)
	pkg.reparent(_carriage, true)
	_set_load(pkg.mass, _carriage.transform * pkg.position)
	_log("picked up %s, %.0f kg: truck now %.0f kg" % [pkg.name, pkg.mass, mass])


func _set_down() -> void:
	var pkg := _carry
	_carry = null
	pkg.reparent(get_parent(), true)
	pkg.freeze = false
	pkg.linear_velocity = Vector3.ZERO
	_set_load(0.0, Vector3.ZERO)
	_log("set %s down on the bunks" % pkg.name)
	# Keep ignoring it until the forks are out from under it.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(pkg):
			remove_collision_exception_with(pkg))


## Load on the forks: total mass and centre of mass (model frame).
func _set_load(load_mass: float, load_pos: Vector3) -> void:
	var total: float = empty_mass + load_mass
	var com: Vector3 = (COM_EMPTY * empty_mass + load_pos * load_mass) / total
	mass = total
	center_of_mass = _m2b(com)


func _log(text: String) -> void:
	if log_events:
		print("[Forklift %.2f] %s" % [_clock, text])
