extends SceneTree

## Test: the bin sorter in the mill. Loads mill_prototype, lays 2x8s on the board lug incline
## and lets its lugs carry them up and over the crest onto the sorter's infeed. Checks every
## board ends up on bay 7's forks and that the incline never had to stop.
## Run: godot --headless --fixed-fps 60 --path . --script res://dev/tests/bin_sorter_mill_test.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"
const BOARDS := 6
const GAP := 6.0               # seconds between boards laid on the ramp


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node3D = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var sorter: BinSorter = mill.get_node("BinSorter")
	sorter.log_boards = OS.get_cmdline_user_args().has("--log")
	incline.set("wait_for_board", false)
	var boards: Array[RigidBody3D] = []
	var held_seen := false
	var t := 0.0
	var dt := 1.0 / 60.0
	var next := 1.0
	while t < BOARDS * GAP + 75.0:
		if boards.size() < BOARDS and t >= next:
			var board: RigidBody3D = load(BOARD_SCENE).instantiate()
			board.nominal_size = "2x8"
			mill.add_child(board)
			# On the ramp just uphill of the landing deck, broadside like the deck hands it over.
			board.global_position = incline.to_global(Vector3(0.0, 0.6 * tan(deg_to_rad(26.0)) + 0.05, 0.6))
			board.global_rotation = incline.global_rotation + Vector3(deg_to_rad(-26.0), 0.0, 0.0)
			boards.append(board)
			next += GAP
		if not bool(incline.get("running")):
			held_seen = true
		await physics_frame
		t += dt

	var problems := 0
	var bay7 := 0
	for i in boards.size():
		var b := boards[i]
		if not is_instance_valid(b):
			print("  #%d FREED (fell out of the world)" % i)
			problems += 1
			continue
		var p: Vector3 = sorter.to_local(b.global_position)
		var bx: float = BinSorter.bay_x(7)
		var where := "?"
		if p.y > 1.2 and p.y < BinSorter.DECK_Y - 0.3 and p.x > bx + 0.15 and p.x < bx + 1.0:
			where = "in bay 7"
			bay7 += 1
		else:
			problems += 1
		print("  #%d -> sorter-local (%.2f, %.2f, %.2f)  %s" % [i, p.x, p.y, p.z, where])
	if sorter._bays[7].count != bay7:
		print("  bay 7: sorter counts %d, %d boards on its forks" % [sorter._bays[7].count, bay7])
		problems += 1
	print("incline stopped at any point: ", held_seen)
	if held_seen:
		problems += 1
	print("RESULT ", "PASS" if problems == 0 else "FAIL (%d problems)" % problems)
	quit()
