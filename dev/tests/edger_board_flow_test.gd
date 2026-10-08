extends SceneTree

## Test: a board cut by the edger leaves the edger and travels onto the landing deck without twisting. Run: godot --headless --path . --script res://dev/tests/edger_board_flow_test.gd

func _init():
	call_deferred("run_test")

func run_test():
	print("--- RUNNING FULL MILL PROTOTYPE FLOW TEST ---")
	var scene_res = load("res://game/levels/mill_prototype.tscn")
	var mill = scene_res.instantiate()
	root.add_child(mill)
	current_scene = mill

	var edger = mill.get_node("SawmillEdger")
	var deck = mill.get_node("landing_deck_frame")
	var sorter = mill.get_node_or_null("BinSorter")

	print("Edger: ", edger != null, " Deck: ", deck != null, " Sorter: ", sorter != null)

	var boards = mill.find_children("*", "RigidBody3D", true, false).filter(func(n): return n.is_in_group("cut_boards") or "CutBoard" in n.name)
	var edger_boards = boards.filter(func(b): return absf(b.global_position.z - 18.29) < 0.5)
	var board: RigidBody3D = edger_boards[0] if not edger_boards.is_empty() else boards[0]

	var success := false
	var worst_yaw := 0.0
	for frame in range(1200):
		await physics_frame
		if frame >= 500 and frame % 60 == 0:
			var deck_local = deck.to_local(board.global_position)
			print("F%03d: pos=(%.2f, %.2f, %.2f) rot_y=%.2f vel=(%.2f, %.2f, %.2f) deck_local_z=%.2f" % [
				frame, board.global_position.x, board.global_position.y, board.global_position.z,
				board.rotation_degrees.y,
				board.linear_velocity.x, board.linear_velocity.y, board.linear_velocity.z,
				deck_local.z
			])
		# Track yaw only while the board is on the deck, before the incline takes it.
		if board.global_position.x > 49.0 and board.global_position.z < 20.5:
			worst_yaw = maxf(worst_yaw, absf(board.rotation_degrees.y))
		if board.global_position.z > 20.0 and board.global_position.x > 48.0:
			success = true

	# The board must arrive broadside. The deck once swung it about 18 degrees.
	print("worst yaw on the deck: %.1f deg" % worst_yaw)
	if success and worst_yaw < 5.0:
		print("EDGER_FLOW_TEST PASS failures=0")
		quit(0)
	else:
		push_error("EDGER_FLOW_TEST FAIL: Board failed to exit edger and transport along deck")
		quit(1)
