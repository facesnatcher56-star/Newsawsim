extends SceneTree
func _init():
	call_deferred("check")
func check():
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var sorter = load("res://game/machines/sorter/bin_sorter.tscn").instantiate()
	sorter.name = "Sorter"
	sorter.auto_spawn_test_board = false
	sorter.continuous_infeed_spawner = false
	sorter.random_bay_sorting = false
	sorter.position = Vector3(50.803027, -1.5, 22)
	sorter.rotation.y = -PI / 2
	world.add_child(sorter)
	var transfer = load("res://game/machines/sorter/edger_sorter_transfer.gd").new()
	transfer.position = Vector3(50.803027, 0.2471245, 18.297045)
	transfer.sorter_path = NodePath("../Sorter")
	world.add_child(transfer)
	var board = load("res://game/lumber/cut_board.tscn").instantiate()
	board.nominal_size = "2x12"
	board.length_feet = 16
	board.position = transfer.position + Vector3(0, 0.08, 0)
	world.add_child(board)
	sorter._bay_board_counts[19] = sorter.max_boards_per_bay
	assert(not sorter.can_accept_board(board), "Full target bay must block admission")
	sorter._bay_board_counts[19] = 0
	sorter._bay_discharging[19] = true
	assert(not sorter.can_accept_board(board), "Discharging target bay must block admission")
	sorter._bay_discharging[19] = false
	assert(sorter.can_accept_board(board), "Empty target bay must accept a board")
	for i in range(2200):
		await physics_frame
		if i % 180 == 0:
			print("STEP ", i, " delivered=", transfer.delivered_boards, " position=", sorter.to_local(board.global_position), " counts=", sorter._bay_board_counts)
		if sorter._bay_board_counts[19] == 1:
			var actual = sorter.to_local(board.global_position)
			assert(actual.x >= 19 * sorter.bin_width and actual.x < 20 * sorter.bin_width, "Board counted outside target bay")
			assert(transfer.delivered_boards == 1, "Board delivered more than once")
			assert(not board.freeze, "Board must return to physics after release")
			assert(board.nominal_size == "2x12" and board.length_feet == 16, "Product changed during transfer")
			print("PASS: receiving table, lift, last-bin physical collection, identity and metadata")
			quit()
			return
	print("FAIL collection timed out")
	quit(1)
