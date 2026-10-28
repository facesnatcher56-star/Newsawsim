extends SceneTree

## Tool: runs the mill with boards fed onto the board incline's crest and saves screenshots of
## the bin sorter from several angles to dev/captures/mill_*.png: overview, crest hand-off onto
## the transfer, a board at the stop, a gate dropping a board, the bay pile, along the deck.
## Needs a window. Run: godot --path . --resolution 1600x900 --script res://dev/tools/capture_sorter_mill.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"
const OUT_DIR := "res://dev/captures"
const SIZES: Array[String] = ["2x8", "1x6", "2x10", "2x8", "2x4", "2x8"]

var _mill: Node3D
var _sorter: BinSorter
var _incline: Node3D
var _cam: Camera3D
var _fed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mill = load(LEVEL).instantiate()
	root.add_child(_mill)
	current_scene = _mill
	_sorter = _mill.get_node("BinSorter")
	_incline = _mill.get_node("BoardLugIncline")
	_incline.set("wait_for_board", false)
	_cam = Camera3D.new()
	_cam.fov = 55
	_mill.add_child(_cam)
	_cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	await _frames(30)
	await _shot("overview", Vector3(-4.0, 9.0, 9.0), Vector3(6.0, 3.0, 0.0))
	_feed()
	# Crest hand-off: watch the first board come off the incline onto the transfer.
	await _until(func() -> bool: return _sorter._queue.size() > 0, 1200)
	await _frames(20)
	await _shot("crest", Vector3(-1.2, 5.3, 2.6), Vector3(-0.2, 4.3, 0.0))
	# At the stop, lug coming down behind it.
	await _until(func() -> bool: return not _sorter._carried.is_empty(), 900)
	await _shot("stop", Vector3(0.3, 5.0, 2.4), Vector3(0.6, 4.35, 0.0))
	for n in SIZES.size() - 1:
		_feed_later(4.0 * (n + 1))
	# A gate dropping: side view along the board's length, then the bay pile.
	await _until(func() -> bool: return _sorter._bays.any(func(b: BinSorter.Bay) -> bool: return b.gate_deg > 25.0), 3000)
	var open_bay: int = 0
	for i in BinSorter.NB:
		if _sorter._bays[i].gate_deg > 25.0:
			open_bay = i
	var bx: float = BinSorter.bay_x(open_bay)
	await _frames(4)
	await _shot("drop_side", Vector3(bx + 0.5, 3.9, 3.4), Vector3(bx + 0.55, 3.8, 0.0))
	await _frames(10)
	await _shot("drop_side_later", Vector3(bx + 0.5, 3.9, 3.4), Vector3(bx + 0.55, 3.6, 0.0))
	await _until(func() -> bool: return _sorter._bays[7].count >= 3, 4000)
	await _frames(60)
	await _shot("bay7_pile", Vector3(BinSorter.bay_x(7) + 0.5, 3.6, 3.2), Vector3(BinSorter.bay_x(7) + 0.6, 3.1, 0.0))
	await _shot("bay7_from_end", Vector3(BinSorter.bay_x(7) + 2.6, 3.9, 0.8), Vector3(BinSorter.bay_x(7) + 0.6, 3.2, 0.0))
	await _shot("along_deck", Vector3(-1.0, 4.9, 0.6), Vector3(6.0, 4.0, 0.0))
	print("CAPTURE DONE")
	quit()


func _feed() -> void:
	var board: RigidBody3D = load(BOARD_SCENE).instantiate()
	board.nominal_size = SIZES[_fed % SIZES.size()]
	_fed += 1
	_mill.add_child(board)
	var run: float = 2.785 / tan(deg_to_rad(26.0))
	board.global_position = _incline.to_global(Vector3(0.0, 2.785 + 0.06, run + 0.9))
	board.global_rotation = _incline.global_rotation


func _feed_later(seconds: float) -> void:
	create_timer(seconds, true, true).timeout.connect(_feed)


func _until(done: Callable, max_frames: int) -> void:
	for f in max_frames:
		if done.call():
			return
		await physics_frame


func _frames(n: int) -> void:
	for f in n:
		await physics_frame


func _shot(label: String, from: Vector3, at: Vector3) -> void:
	_cam.global_position = _sorter.to_global(from)
	_cam.look_at(_sorter.to_global(at), Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/mill_" + label + ".png"))
	print("saved ", label)
