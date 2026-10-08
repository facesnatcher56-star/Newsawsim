extends SceneTree

## Test: one board is carried by the CarrySurface boxes from the edger across the landing deck,
## up the incline and into the bin sorter's hands, without twisting on the deck.
## Run: godot --headless --path . --script res://dev/tests/carry_surface_line_test.gd

const MAX_FRAMES := 3200
const MAX_DECK_YAW := 6.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var sorter: Node = mill.get_node("BinSorter")
	var board: RigidBody3D = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))[0]
	var worst_yaw := 0.0
	var reached_crest := false
	var taken := false
	for frame in MAX_FRAMES:
		await physics_frame
		var at: Vector3 = board.global_position
		if at.x > 49.0 and at.z < 21.6:
			worst_yaw = maxf(worst_yaw, absf(board.rotation_degrees.y))
		if at.z > 28.5 and at.y > 2.8:
			reached_crest = true
		for data in sorter._tracked_boards:
			if data.board == board:
				taken = true
		if taken:
			break
	var failures := 0
	if worst_yaw >= MAX_DECK_YAW:
		push_error("FAIL: board twisted %.1f deg on the deck" % worst_yaw)
		failures += 1
	if not reached_crest:
		push_error("FAIL: board never reached the incline crest")
		failures += 1
	if not taken:
		push_error("FAIL: sorter never took the board")
		failures += 1
	print("CARRY_SURFACE_LINE_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures, " deck_yaw=%.1f" % worst_yaw)
	quit(failures)
