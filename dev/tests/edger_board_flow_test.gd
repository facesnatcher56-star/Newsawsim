extends SceneTree

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
		if board.global_position.z > 20.0 and board.global_position.x > 48.0:
			success = true

	if success:
		print("EDGER_FLOW_TEST PASS failures=0")
		quit(0)
	else:
		push_error("EDGER_FLOW_TEST FAIL: Board failed to exit edger and transport along deck")
		quit(1)
