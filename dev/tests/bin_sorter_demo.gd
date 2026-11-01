extends Node3D

## Demo to watch the bin sorter in the mill: loads mill_prototype and lays a board on the
## board incline's ramp in front of every one of its lugs, so every incline lug (and so every
## sorter lug) carries a board. The camera points at the sorter. Open bin_sorter_demo.tscn and
## press F6; the camera is the mill's free-fly camera.

const LEVEL := preload("res://game/levels/mill_prototype.tscn")
const BOARD_SCENE := preload("res://game/lumber/cut_board.tscn")
## Board sizes to feed, in turn.
@export var sizes: Array[String] = ["2x8"]
## Where boards are laid, metres along the incline's chain from its pickup.
@export var lay_at: float = 1.2

## Seconds between saved screenshots (dev/captures/demo_N.png); 0 = off. With snapshots on,
## each one is taken from the next view in turn.
@export var snapshot_every: float = 0.0

## Camera views in sorter coordinates (position, look-at); keys 1-5 switch.
const VIEWS: Array = [
	[Vector3(-1.5, 6.2, 5.5), Vector3(4.5, 3.6, 0.0)],     # 1 sorter infeed and bays
	[Vector3(13.0, 3.0, 6.5), Vector3(16.5, 0.4, 0.0)],    # 2 haul-out onto the surge chains
	[Vector3(19.5, 3.2, 6.5), Vector3(22.5, 0.8, 0.0)],    # 3 surge head, pocket, unscrambler
	[Vector3(26.0, 7.5, 12.0), Vector3(27.0, 1.5, 0.0)],   # 4 whole stacker
	[Vector3(38.5, 3.2, 6.5), Vector3(33.5, 0.8, 0.0)],    # 5 outfeed and landing deck
	[Vector3(36.0, 9.0, 14.0), Vector3(44.0, 0.8, 3.0)],   # 6 forklift and the yard row
	[Vector3(18.5, 4.6, 10.5), Vector3(25.0, 1.6, 3.5)],   # 7 operator console, stair and catwalk
	[Vector3(15.0, 6.5, 9.0), Vector3(7.0, 3.6, 2.5)],     # 8 sorter catwalk, stair and cull pile
	[Vector3(72.0, 12.0, 16.0), Vector3(92.0, 2.0, -1.2)], # 9 dry kiln beyond the haul-out wall
]
var _view: int = 1

var _mill: Node3D
var _incline: Node3D
var _sorter: BinSorter
var _last: Array[float] = []
var _count: int = 0
var _lug_x: Array[float] = []
var _filled: int = 0
var _empty: int = 0
var _snap_timer: float = 3.0
var _snap_n: int = 0


func _ready() -> void:
	_mill = LEVEL.instantiate()
	add_child(_mill)
	_incline = _mill.get_node("BoardLugIncline")
	_incline.set("wait_for_board", false)
	var sorter: Node3D = _mill.get_node("BinSorter")
	_sorter = sorter as BinSorter
	var stacker := _mill.get_node_or_null("GreenStacker")
	if stacker != null:
		stacker.set("log_events", true)
		# The mill's packages are 31 layers (over 20 minutes at the mill's feed rate); 6 here
		# so a whole package, its pickup and the forklift's trip show in one run.
		# --full keeps the mill's real packages: 31 layers of 1x, 26 of 2x, one whole package per bay.
		if not "--full" in OS.get_cmdline_user_args():
			stacker.set("package_layers", 6)
			stacker.set("thick_package_layers", 6)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sizes="):
			sizes.assign(arg.trim_prefix("--sizes=").split(","))
	_bay_status = "--bays" in OS.get_cmdline_user_args()
	for n: String in ["Forklift", "StackerCrew", "SorterCrew"]:
		var node := _mill.get_node_or_null(n)
		if node != null:
			node.set("log_events", true)
	if "--log" in OS.get_cmdline_user_args():
		_sorter.log_boards = true
	if "--snapshots" in OS.get_cmdline_user_args():
		snapshot_every = 6.0
	_trace = "--crest" in OS.get_cmdline_user_args()
	var cam := _mill.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = true
		# Off the catwalk side, looking along the deck from the infeed toward the bays.
		_set_view(1)


func _set_view(v: int) -> void:
	var cam := _mill.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	_view = v
	var pair: Array = VIEWS[v - 1]
	cam.global_position = _sorter.to_global(pair[0])
	cam.look_at(_sorter.to_global(pair[1]), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_set_view(key.keycode - KEY_0)
	elif key.keycode in [KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		# Lug speed is the incline's chain speed; the sorter's lug chain is geared to it.
		var up: bool = key.keycode in [KEY_EQUAL, KEY_KP_ADD]
		var v: float = clampf(float(_incline.get("chain_speed")) + (0.05 if up else -0.05), 0.1, 1.5)
		_incline.set("chain_speed", v)
		print("lug speed: incline %.2f m/s (%.0f boards a minute)" % [v, 60.0 * v / 0.74])


func _physics_process(_delta: float) -> void:
	var slots: Array = _incline.get("_slot")
	if _last.size() != slots.size():
		_last.assign(slots)
		return
	var loop: float = float(_incline.get("_loop_len"))
	for i in slots.size():
		var before: float = _last[i]
		var now: float = float(slots[i])
		# This lug just passed the lay point (allowing for the loop wrapping round).
		var passed: bool = before < lay_at and now >= lay_at and now - before < loop * 0.5
		_last[i] = now
		if passed:
			_lay_board(now + 0.18)
	_tally_lugs()
	if _bay_status:
		_print_bays(_delta)
	if _trace:
		_trace_crest(_delta)
	if snapshot_every > 0.0:
		_snap_timer -= _delta
		if _snap_timer <= 0.0:
			_snap_timer = snapshot_every
			_snap_n += 1
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://dev/captures/demo_%d_v%d.png" % [_snap_n, _view]))
			_set_view(_view % VIEWS.size() + 1)


## Count each sorter lug as it passes bay 0: did it have a board in front of it?
func _tally_lugs() -> void:
	var gauge: float = BinSorter.bay_x(0) + 0.5
	if _lug_x.size() != _sorter._lugs.size():
		_lug_x.resize(_sorter._lugs.size())
		_lug_x.fill(INF)
	for k in _sorter._lugs.size():
		var x: float = _sorter._lugs[k].position.x + BinSorter.LUG_FACE
		var on_run: bool = _sorter._lugs[k].position.y < BinSorter.TOP_SHAFT_Y
		if on_run and _lug_x[k] < gauge and x >= gauge:
			var carrying := false
			for c: BinSorter.Carried in _sorter._carried:
				if is_instance_valid(c.board):
					var t: float = _sorter._trailing(c.board)
					if t >= x - 0.05 and t < x + 0.4:
						carrying = true
			if carrying:
				_filled += 1
			else:
				_empty += 1
			print("sorter lugs past bay 0: %d with a board, %d empty" % [_filled, _empty])
		_lug_x[k] = x if on_run else INF


## --crest: keeps the last 3 s of every board near the incline crest (sorter frame) and
## prints it, with the sorter's infeed state, when one falls off below the deck.
var _trace: bool = false
var _bay_status: bool = false
var _bay_clock: float = 0.0
var _bay_last: String = ""
var _hist: Dictionary = {}
var _trace_clock: float = 0.0
var _sample_t: float = 0.0

func _trace_crest(delta: float) -> void:
	_trace_clock += delta
	_sample_t -= delta
	var sample: bool = _sample_t <= 0.0
	if sample:
		_sample_t = 0.1
	for n: Node in get_tree().get_nodes_in_group("cut_boards"):
		var b := n as RigidBody3D
		if b == null:
			continue
		var p: Vector3 = _sorter.to_local(b.global_position)
		if p.x < -3.5 or p.x > 1.5:
			_hist.erase(b)
			continue
		var h: Array = _hist.get(b, [])
		if p.y < BinSorter.DECK_Y - 0.5 and not h.is_empty() and float(h[-1][1].y) > BinSorter.DECK_Y - 0.3:
			print("CREST FALL %s at t %.2f; queue %d hold %s gate %s infeed %s top %.2f incline %.2f" % [
				b.name, _trace_clock, _sorter._queue.size(), _sorter._hold_chain, _sorter._gate_wait,
				_sorter._infeed_on, _sorter._top_speed, float(_incline.get("actual_speed"))])
			for e: Array in h:
				print("   t %.2f pos (%.2f, %.2f, %.2f) rot (%.0f, %.0f, %.0f) vel (%.2f, %.2f, %.2f)" % [
					e[0], e[1].x, e[1].y, e[1].z, e[2].x, e[2].y, e[2].z, e[3].x, e[3].y, e[3].z])
			_hist.erase(b)
			continue
		if sample:
			var r: Vector3 = (_sorter.global_basis.inverse() * b.global_basis).get_euler() * (180.0 / PI)
			h.append([_trace_clock, p, r, _sorter.global_basis.inverse() * b.linear_velocity])
			if h.size() > 30:
				h.pop_front()
			_hist[b] = h


## A board on the ramp's carrying plane, just ahead of the lug at chain distance `s`.
func _lay_board(s: float) -> void:
	var sample: Array = _incline.call("_sample", s)
	var point: Vector2 = sample[0]
	var a: float = deg_to_rad(float(_incline.get("slope_angle_deg")))
	var board: RigidBody3D = BOARD_SCENE.instantiate()
	board.nominal_size = sizes[_count % sizes.size()]
	_count += 1
	_mill.add_child(board)
	# Chain line to the carrying plane is CARRIER_DROP; then half the board plus a little.
	var lift: float = 0.024 + float(board.get("board_thickness")) * 0.5 + 0.01
	var local := Vector3(0.0, point.y + lift * cos(a), point.x - lift * sin(a))
	board.global_position = _incline.to_global(local)
	board.global_rotation = _incline.global_rotation + Vector3(-a, 0.0, 0.0)


## With --bays, every 10 s: each bay holding boards, its phase, count of capacity and fork height.
func _print_bays(delta: float) -> void:
	_bay_clock += delta
	if _bay_clock < 10.0:
		return
	_bay_clock = 0.0
	var parts: PackedStringArray = []
	var bays: Array = _sorter.get("_bays")
	for i in bays.size():
		var bay: Variant = bays[i]
		if bay.count > 0 or bay.phase != 0:
			parts.append("bay %d %s %s %d/%d forks %.2f" % [i, bay.size, BinSorter.BayPhase.keys()[bay.phase],
					bay.count, _sorter.call("_bay_capacity", i), bay.carriage_y])
	var line: String = ", ".join(parts)
	print("[bays] t %.0f s  %s" % [Time.get_ticks_msec() / 1000.0, line if line != "" else "all empty"])
