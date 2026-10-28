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

## Seconds between saved screenshots (dev/captures/demo_N.png); 0 = off.
@export var snapshot_every: float = 0.0

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
	if "--snapshots" in OS.get_cmdline_user_args():
		snapshot_every = 6.0
	var cam := _mill.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = true
		# Off the catwalk side, looking along the deck from the infeed toward the bays.
		cam.global_position = sorter.to_global(Vector3(-1.5, 6.2, 5.5))
		cam.look_at(sorter.to_global(Vector3(4.5, 3.6, 0.0)), Vector3.UP)


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
	if snapshot_every > 0.0:
		_snap_timer -= _delta
		if _snap_timer <= 0.0:
			_snap_timer = snapshot_every
			_snap_n += 1
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://dev/captures/demo_%d.png" % _snap_n))


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
