class_name SorterCrew
extends Node3D

## The bin sorter's crew: a worker stationed on the sorter's catwalk and a stack light.
##
## - Jam eyes: when the sorter reports a jam the sorter and the lug incline feeding it stop at
##   once (lockout) and the stack light goes red.
## - A board lying loose on the deck: the worker walks along the catwalk, reaches over and
##   lays it on top of its bay's pile.
## - A board that landed on its edge (or badly tipped) in a bay: he reaches in and lays it flat
##   on that bay's pile.
## - A board that fell to the floor: he goes down the sorter's stair, walks the aisle, carries
##   the board to the cull pile and goes back up to his post. One down in the haul-out pit: he
##   climbs down the pit ladder and walks along the pit floor beside the stopped chains (safe:
##   the line is locked out), and carries it back up the ladder.
## - Then he restarts the line. If the same jam keeps coming back (three fixes in a row) the
##   line stays locked out and the light stays red.
##
## Positions are in the sorter's frame (sorter_build.py): catwalk at y 4.10, z 3.25..4.15,
## x -0.0..11.6; its stair runs down from x 11.6 to about x 17.1 at z 3.38..4.15.

const MillWorkerScript := preload("res://game/characters/mill_worker.gd")

@export var sorter: NodePath
@export var log_events: bool = false
## How fast the worker walks, metres per second.
@export_range(0.5, 4.0, 0.1) var walk_speed: float = 2.0
## Seconds the worker takes to lift a board and set it down where it belongs.
@export_range(0.2, 3.0, 0.05) var hand_time: float = 0.5

const CATWALK_Y := 4.10
const CATWALK_Z := 3.70
const CATWALK_X := Vector2(0.2, 11.4)
const POST := Vector3(6.0, CATWALK_Y, CATWALK_Z)
const STAIR_TOP := Vector3(11.55, CATWALK_Y, 3.77)
const STAIR_FOOT := Vector3(17.25, 0.0, 3.77)
const AISLE_Z := 5.0
const CULL := Vector3(13.6, 0.0, 5.7)          # cull pile on the floor, boards along X
const STACK_LIGHT := Vector3(12.2, 0.0, 4.7)
const JAM_CONFIRM := 0.5
## Walking lane along the pit floor: between the haul strands and the carriage end blocks.
const PIT_LANE_Z := 2.65
const MAX_REPEATS := 3

enum St { RUNNING, FIXING, RETURNING, HALTED }

var _sorter: Node3D
var _worker: Node3D
var _state: int = St.RUNNING
var _jam: Dictionary = {}
var _jam_t: float = 0.0
var _ok_t: float = 0.0
var _repeats: int = 0
var _last_kind: String = ""
var _step: int = 0
var _culled: int = 0
var _lamps: Array[MeshInstance3D] = []
var _tween_board: RigidBody3D
var _tween_from: Transform3D
var _tween_to: Transform3D
var _tween_t: float = -1.0


func _ready() -> void:
	if not sorter.is_empty():
		_sorter = get_node_or_null(sorter) as Node3D
	if _sorter == null:
		push_warning("SorterCrew: no sorter")
		return
	_build.call_deferred()


func _s(p: Vector3) -> Vector3:
	return _sorter.to_global(p)


func _l(n: Node3D) -> Vector3:
	return _sorter.to_local(n.global_position)


func _log(text: String) -> void:
	if log_events:
		print("[SorterCrew] " + text)


func _build() -> void:
	var pole_root := Node3D.new()
	pole_root.name = "SorterStackLight"
	get_parent().add_child(pole_root)
	pole_root.global_transform = Transform3D(_sorter.global_basis, _s(STACK_LIGHT))
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.57, 0.6)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 2.4
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = grey
	pm.position = Vector3(0.0, 1.2, 0.0)
	pole_root.add_child(pm)
	for i in 3:
		var lamp := CylinderMesh.new()
		lamp.top_radius = 0.07
		lamp.bottom_radius = 0.07
		lamp.height = 0.12
		var colour: Color = [Color(0.1, 0.9, 0.2), Color(1.0, 0.6, 0.05), Color(1.0, 0.08, 0.05)][i]
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.emission_enabled = true
		m.emission = colour
		var mi := MeshInstance3D.new()
		mi.mesh = lamp
		mi.material_override = m
		mi.position = Vector3(0.0, 2.45 + i * 0.13, 0.0)
		pole_root.add_child(mi)
		_lamps.append(mi)
	_worker = MillWorkerScript.new()
	_worker.set("walk_speed", walk_speed)
	_worker.name = "SorterCatwalkWorker"
	get_parent().add_child(_worker)
	_worker.global_position = _s(POST)
	_worker.call("face", _s(Vector3(POST.x, CATWALK_Y, 0.0)))
	_light(0)


func _light(which: int) -> void:
	for i in _lamps.size():
		(_lamps[i].material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if i == which else 0.0


# Routes: along the catwalk; down the stair to the floor aisle; and back up.
func _along(x: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(_s(Vector3(clampf(x, CATWALK_X.x, CATWALK_X.y), CATWALK_Y, CATWALK_Z)))
	return pts


func _down_to(x: float, z: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(_s(Vector3(STAIR_TOP.x - 0.2, CATWALK_Y, STAIR_TOP.z)))
	pts.append(_s(STAIR_TOP))
	pts.append(_s(STAIR_FOOT))
	pts.append(_s(Vector3(STAIR_FOOT.x + 0.3, 0.0, AISLE_Z)))
	pts.append(_s(Vector3(x, 0.0, AISLE_Z)))
	pts.append(_s(Vector3(x, 0.0, z)))
	return pts


## Down the stair, along the aisle to the pit ladder, down it and along the pit floor to x.
func _down_into_pit(x: float, z: float) -> PackedVector3Array:
	var pts := _down_to(BinSorter.LADDER_X, AISLE_Z)
	pts.append(_s(Vector3(BinSorter.LADDER_X, 0.0, BinSorter.PIT_Z + 0.35)))
	pts.append(_s(Vector3(BinSorter.LADDER_X, BinSorter.PIT_FLOOR_Y, BinSorter.PIT_Z - 0.35)))
	pts.append(_s(Vector3(BinSorter.LADDER_X, BinSorter.PIT_FLOOR_Y, PIT_LANE_Z)))
	pts.append(_s(Vector3(clampf(x, BinSorter.PIT_X0 + 0.3, BinSorter.PIT_X1 - 0.3), BinSorter.PIT_FLOOR_Y, z)))
	return pts


## The first points of any route from where the worker stands: back along the pit floor and up
## the ladder if he is down in the pit, then to the aisle.
func _out_to_aisle() -> PackedVector3Array:
	var here: Vector3 = _l(_worker)
	var pts := PackedVector3Array()
	if here.y < -0.3:
		pts.append(_s(Vector3(here.x, BinSorter.PIT_FLOOR_Y, PIT_LANE_Z)))
		pts.append(_s(Vector3(BinSorter.LADDER_X, BinSorter.PIT_FLOOR_Y, PIT_LANE_Z)))
		pts.append(_s(Vector3(BinSorter.LADDER_X, BinSorter.PIT_FLOOR_Y, BinSorter.PIT_Z - 0.35)))
		pts.append(_s(Vector3(BinSorter.LADDER_X, 0.0, BinSorter.PIT_Z + 0.35)))
		here = Vector3(BinSorter.LADDER_X, 0.0, AISLE_Z)
	pts.append(_s(Vector3(here.x, 0.0, AISLE_Z)))
	return pts


static func _in_pit(p: Vector3) -> bool:
	return p.y < -0.3 and p.x > BinSorter.PIT_X0 and p.x < BinSorter.PIT_X1 and absf(p.z) < BinSorter.PIT_Z


func _up_to_post() -> PackedVector3Array:
	var pts := _out_to_aisle()
	pts.append(_s(Vector3(STAIR_FOOT.x + 0.3, 0.0, AISLE_Z)))
	pts.append(_s(STAIR_FOOT))
	pts.append(_s(STAIR_TOP))
	pts.append(_s(Vector3(STAIR_TOP.x - 0.2, CATWALK_Y, CATWALK_Z)))
	pts.append(_s(POST))
	return pts


func _physics_process(delta: float) -> void:
	if _sorter == null or _worker == null:
		return
	_run_tween(delta)
	match _state:
		St.RUNNING:
			var jam: Dictionary = _sorter.call("find_jam")
			if jam.is_empty():
				_jam_t = 0.0
				_ok_t += delta
				if _ok_t > 30.0:
					_repeats = 0
				return
			_jam_t += delta
			if _jam_t < JAM_CONFIRM:
				return
			_sorter.call("set_locked", true)
			_ok_t = 0.0
			_jam = jam
			# Each loose board is its own fault: only the same board coming back counts as a repeat.
			var kind: String = "%s:%d" % [jam["kind"], (jam["board"] as Node).get_instance_id()]
			_repeats = _repeats + 1 if kind == _last_kind else 1
			_last_kind = kind
			_light(2)
			if _repeats > MAX_REPEATS:
				_state = St.HALTED
				_log("halted: %s jam came back %d times" % [_last_kind, _repeats - 1])
				return
			_log("jam: %s board at %s, sorter stopped" % [_jam["kind"], str(_jam["at"])])
			var at: Vector3 = _jam["at"]
			if _jam["kind"] == "deck" or _jam["kind"] == "bay":
				_worker.call("walk", _along(at.x))
			elif _in_pit(at):
				_worker.call("walk", _down_into_pit(at.x, PIT_LANE_Z))
			else:
				# Stand at the board's +Z end (boards lie along Z), clear of the columns.
				_worker.call("walk", _down_to(at.x, minf(at.z + 2.7, 4.6)))
			_step = 0
			_state = St.FIXING
			_light(1)
		St.FIXING:
			if _tween_t >= 0.0 or bool(_worker.call("is_walking")):
				return
			var b: RigidBody3D = _jam["board"]
			if not is_instance_valid(b):
				_done()
				return
			if _jam["kind"] == "bay":
				# Landed badly in its bay: reach in and lay it flat on its pile.
				if _step == 0:
					_worker.call("face", b.global_position)
					_worker.call("set_reach", true)
					MillWorkerScript.lift_clear(b)
					_tween(b, _sorter.call("restack_place", b))
					_step = 1
				else:
					_done()
			elif _jam["kind"] == "deck":
				if _step == 0 and int(_sorter.call("hand_bay", b)) < 0:
					# No bay taking its size has room: down to the cull pile with it, never into
					# another size's pack.
					_worker.call("face", b.global_position)
					_worker.call("shoulder", b)
					_worker.call("walk", _down_to(CULL.x, CULL.z - 0.5))
					_jam["kind"] = "floor"
					_step = 1
				elif _step == 0:
					_worker.call("face", b.global_position)
					_worker.call("set_reach", true)
					MillWorkerScript.lift_clear(b)
					_tween(b, _sorter.call("hand_place", b))
					_step = 1
				else:
					_done()
			else:
				match _step:
					0:
						_worker.call("face", b.global_position)
						_worker.call("shoulder", b)
						var pts := _out_to_aisle()
						pts.append(_s(Vector3(CULL.x, 0.0, AISLE_Z)))
						pts.append(_s(Vector3(CULL.x, 0.0, CULL.z - 0.5)))
						_worker.call("walk", pts)
						_step = 1
					1:
						_worker.call("drop_carry")
						_worker.call("set_reach", true)
						b.add_to_group("cull")
						var t: float = float(b.get("board_thickness"))
						_tween(b, _sorter.global_transform * Transform3D(Basis(), CULL + Vector3(0.0, t * (_culled + 0.5), 0.0)))
						_culled += 1
						_step = 2
					_:
						_worker.call("walk", _up_to_post())
						_state = St.RETURNING
		St.RETURNING:
			if not bool(_worker.call("is_walking")):
				_done()


func _done() -> void:
	_worker.call("set_reach", false)
	_sorter.call("set_locked", false)
	_light(0)
	_state = St.RUNNING
	_jam_t = 0.0
	_log("%s cleared, sorter restarted" % _jam.get("kind", "jam"))


func _tween(b: RigidBody3D, to: Transform3D) -> void:
	_tween_board = b
	_tween_from = b.global_transform
	_tween_to = to
	_tween_t = 0.0


func _run_tween(delta: float) -> void:
	if _tween_t < 0.0:
		return
	_tween_t += delta / hand_time
	var u: float = clampf(_tween_t, 0.0, 1.0)
	if is_instance_valid(_tween_board):
		var t: Transform3D = _tween_from.interpolate_with(_tween_to, u * u * (3.0 - 2.0 * u))
		t.origin.y += sin(u * PI) * 0.2
		_tween_board.global_transform = t
		if u >= 1.0:
			MillWorkerScript.set_down(_tween_board)
			_tween_board.freeze = _tween_board.is_in_group("cull")   # cull pile boards stay put
			_tween_board.linear_velocity = Vector3.ZERO
	if u >= 1.0:
		_tween_t = -1.0
		_worker.call("set_reach", false)
