extends Node3D

## The scanner deck's crew: a worker on the floor at the deck's fence end and a stack light.
##
## When the deck's double eye sees one board lying on another ahead of the scanner, the scanner
## chains stop (scanner_deck.gd) and the light goes red; the same goes for a board tipped up and
## stuck on the take-away head or the lug loader. The worker walks along the end of the deck to
## it, shoulders the board (the top one of a double), carries it back down the aisle to the feed chains
## ahead of the unscrambler and sets it down there to go round again. Back at his post the light
## goes green; the chains run again as soon as the double is gone.
##
## Positions are in mill coordinates, like the scanner deck.

const MillWorkerScript := preload("res://game/characters/mill_worker.gd")

@export var deck: NodePath = ^"../ScannerDeck"
@export var log_events: bool = false
## How fast the worker walks, metres per second.
@export_range(0.5, 4.0, 0.1) var walk_speed: float = 1.6
## Seconds the worker takes to set a board down.
@export_range(0.2, 3.0, 0.05) var hand_time: float = 0.6

const AISLE_X := 45.35                  # floor just past the deck's fence end
const POST := Vector3(AISLE_X, 0.0, 17.2)
const STACK_LIGHT := Vector3(45.6, 0.0, 16.2)
const FEED_Z := 7.2                      # feed chains ahead of the unscrambler
const FEED_END_X := 43.4                 # boards lie on the feed chains even-ended here
const FEED_Y := 0.0
const CONFIRM := 0.5

enum St { WATCHING, GOING, CARRYING, SETTING, RETURNING }

var _deck: Node3D
var _worker: Node3D
var _state: int = St.WATCHING
var _seen_t: float = 0.0
var _board: RigidBody3D
var _lamps: Array[MeshInstance3D] = []
var _tween_from: Transform3D
var _tween_to: Transform3D
var _tween_t: float = -1.0
var _cleared: int = 0


func _ready() -> void:
	_deck = get_node_or_null(deck) as Node3D
	if _deck == null:
		push_warning("ScannerCrew: no scanner deck")
		return
	log_events = log_events or bool(_deck.get("debug_log"))
	_build.call_deferred()


func _log(text: String) -> void:
	if log_events:
		print("[ScannerCrew] " + text)


func _build() -> void:
	var pole_root := Node3D.new()
	pole_root.name = "ScannerStackLight"
	get_parent().add_child(pole_root)
	pole_root.global_position = STACK_LIGHT
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
	_worker.name = "ScannerDeckWorker"
	get_parent().add_child(_worker)
	_worker.global_position = POST
	_worker.call("face", Vector3(40.0, 0.0, POST.z))
	_light(0)


func _light(which: int) -> void:
	for i in _lamps.size():
		(_lamps[i].material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if i == which else 0.0


func _aisle(from_z: float, to_z: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(Vector3(AISLE_X, 0.0, from_z))
	pts.append(Vector3(AISLE_X, 0.0, to_z))
	return pts


func _physics_process(delta: float) -> void:
	if _deck == null or _worker == null:
		return
	_run_tween(delta)
	match _state:
		St.WATCHING:
			var top: RigidBody3D = _deck.call("find_fault")
			_seen_t = _seen_t + delta if top != null else 0.0
			if _seen_t < CONFIRM:
				return
			_board = top
			_light(2)
			_log("%s (%s at z %.2f), going over" % ["double at the scanner" if top == _deck.call("find_double") else "board stuck on the lug loader",
					top.name, top.global_position.z])
			_worker.call("walk", _aisle(_worker.global_position.z, top.global_position.z))
			_state = St.GOING
		St.GOING:
			if bool(_worker.call("is_walking")):
				return
			if not is_instance_valid(_board):
				_back()
				return
			_light(1)
			_worker.call("face", _board.global_position)
			_worker.call("shoulder", _board)
			_worker.call("walk", _aisle(_worker.global_position.z, FEED_Z))
			_state = St.CARRYING
		St.CARRYING:
			if bool(_worker.call("is_walking")):
				return
			_worker.call("drop_carry")
			if not is_instance_valid(_board):
				_back()
				return
			_worker.call("face", Vector3(40.0, 0.0, FEED_Z))
			_worker.call("set_reach", true)
			var length: float = float(_board.get("product_length"))
			var t: float = float(_board.get("board_thickness"))
			_tween_from = _board.global_transform
			_tween_to = Transform3D(Basis.IDENTITY, Vector3(FEED_END_X - length * 0.5, FEED_Y + t * 0.5 + 0.02, FEED_Z))
			_tween_t = 0.0
			_state = St.SETTING
		St.SETTING:
			if _tween_t >= 0.0:
				return
			_cleared += 1
			_log("board back on the feed chains (%d so far)" % _cleared)
			_back()
		St.RETURNING:
			if not bool(_worker.call("is_walking")):
				_worker.call("face", Vector3(40.0, 0.0, POST.z))
				_light(0)
				_state = St.WATCHING
				_seen_t = 0.0


func _back() -> void:
	_board = null
	_worker.call("set_reach", false)
	_worker.call("walk", _aisle(_worker.global_position.z, POST.z))
	_state = St.RETURNING


func _run_tween(delta: float) -> void:
	if _tween_t < 0.0:
		return
	_tween_t += delta / hand_time
	var u: float = clampf(_tween_t, 0.0, 1.0)
	if is_instance_valid(_board):
		var t: Transform3D = _tween_from.interpolate_with(_tween_to, u * u * (3.0 - 2.0 * u))
		_board.global_transform = t
		if u >= 1.0:
			MillWorkerScript.set_down(_board)
			_board.freeze = false
			_board.linear_velocity = Vector3.ZERO
			_board.angular_velocity = Vector3.ZERO
	if u >= 1.0:
		_tween_t = -1.0
		_worker.call("set_reach", false)


## One line for debug HUDs and probes.
func status_text() -> String:
	return "%s, boards cleared %d" % [St.keys()[_state], _cleared]
