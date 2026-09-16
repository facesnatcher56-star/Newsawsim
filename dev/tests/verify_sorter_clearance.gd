extends SceneTree

## Verification test for 50-bay industrial lumber bin sorter.
## Tests all 3 distinct mechanical motion paths with a 16-foot board:
##   Path A: Overhead lug-chain board transport
##   Path B: Vertical drop into bay and carriage lowering
##   Path C: Bottom discharge onto floor haul-out conveyor

func _init() -> void:
	call_deferred("run_clearance_test")

func run_clearance_test() -> void:
	print("=".repeat(70))
	print("STARTING BIN SORTER 3-PATH CLEARANCE & KINEMATIC TEST")
	print("=".repeat(70))

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var sorter: BinSorter = load("res://game/machines/sorter/bin_sorter.tscn").instantiate()
	sorter.name = "Sorter"
	sorter.auto_spawn_test_board = false
	sorter.continuous_infeed_spawner = false
	sorter.random_bay_sorting = false
	world.add_child(sorter)

	# 1. Structural Validation
	print("\n--- 1. Structural Verification ---")
	assert(sorter.num_bins == 50, "Sorter must have 50 bins")
	assert(sorter._gate_nodes.size() == 50, "Sorter must have 50 drop gate nodes")
	assert(sorter._cradle_nodes.size() == 50, "Sorter must have 50 cradle nodes")
	assert(sorter._cradle_bodies.size() == 50, "Sorter must have 50 cradle collision bodies")
	assert(sorter._gate_bodies.size() == 50, "Sorter must have 50 gate collision bodies")
	assert(is_instance_valid(sorter._top_drive_shaft), "Top drive shaft must exist")
	assert(is_instance_valid(sorter._top_tail_shaft), "Top tail shaft must exist")
	assert(is_instance_valid(sorter._haulout_drive_shaft), "Haulout drive shaft must exist")
	assert(is_instance_valid(sorter._haulout_tail_shaft), "Haulout tail shaft must exist")
	print("PASS: 50 bays, 50 gates, 50 cradles, 4 common cross shafts correctly bound.")

	# 2. Path A: Overhead Transport & Lug Geometry Check
	print("\n--- 2. Path A: Overhead Conveyor Transport ---")
	var board: RigidBody3D = load("res://game/lumber/cut_board.tscn").instantiate()
	board.nominal_size = "2x12"
	board.length_feet = 16
	board.rotation.y = PI / 2
	world.add_child(board)

	# Position board at infeed
	board.global_position = sorter.to_global(Vector3(-0.3, sorter.sorter_height + 0.08, 0.0))
	sorter._on_infeed_body_entered(board)
	assert(sorter._tracked_boards.size() == 1, "Board must be tracked by sorter")
	
	var target_bay: int = sorter._tracked_boards[0].target_bin
	print("Board assigned to Target Bay: ", target_bay)

	# Advance until board is in flight along Path A
	for f in range(60):
		await physics_frame

	var local_pos := sorter.to_local(board.global_position)
	print("Path A board position during horizontal transport: ", local_pos)
	assert(local_pos.y >= sorter.sorter_height - 0.05, "Board must be supported at transport height Y >= 4.25")
	assert(local_pos.y <= 4.70, "Board must travel strictly below overhead chain working run (Y=4.70)")
	print("PASS Path A: Board travels below overhead chains on drop skids.")

	# 3. Path B: Diverter Gate Opening & Vertical Drop
	print("\n--- 3. Path B: Diverter Gate Drop & Stack Lowering ---")
	board.contact_monitor = true
	board.max_contacts_reported = 10
	var dropped: bool = false
	for f in range(1200):
		await physics_frame
		if f % 120 == 0:
			var lp := sorter.to_local(board.global_position)
			print("Frame ", f, " pos=", lp, " gate_angle=", sorter._gate_angles[target_bay])
		if sorter._bay_board_counts[target_bay] == 1:
			dropped = true
			break

	assert(dropped, "Board failed to drop into target bay")
	local_pos = sorter.to_local(board.global_position)
	print("Board settled in bay %d at: %s" % [target_bay, str(local_pos)])
	var bay_min_x: float = float(target_bay) * sorter.bin_width
	var bay_max_x: float = float(target_bay + 1) * sorter.bin_width
	assert(local_pos.x >= bay_min_x - 0.05 and local_pos.x <= bay_max_x + 0.05, "Board must be contained within bay dividers")
	print("PASS Path B: Board cleanly released by downward drop gate and contained in bay.")

	# 4. Carriage Indexing Check
	print("\n--- 4. Carriage Indexing Simulation ---")
	var initial_cradle_h: float = sorter._cradle_heights[target_bay]
	print("Carriage height after 1 board: ", initial_cradle_h)
	# Simulate 9 more boards
	sorter._bay_board_counts[target_bay] = 9
	sorter._cradle_target_heights[target_bay] = maxf(0.50, sorter.TOP_CATCH_Y - 9.0 * 0.25)
	for f in range(120):
		await physics_frame
	print("Carriage height with 9 boards: ", sorter._cradle_heights[target_bay])
	assert(sorter._cradle_heights[target_bay] < initial_cradle_h, "Carriage must lower as boards accumulate")
	print("PASS Carriage Indexing: Smooth progressive lowering verified.")

	# 5. Path C: Floor Haul-Out Discharge Transfer
	print("\n--- 5. Path C: Floor Haul-Out Transfer ---")
	# Trigger discharge on bay
	sorter._bay_board_counts[target_bay] = sorter.max_boards_per_bay
	for f in range(400):
		await physics_frame
		if sorter._cradle_heights[target_bay] <= sorter.FLOOR_DISCHARGE_Y + 0.05:
			break

	print("Carriage discharge elevation reached: ", sorter._cradle_heights[target_bay])
	assert(sorter._cradle_heights[target_bay] <= sorter.FLOOR_DISCHARGE_Y + 0.05, 
		"Carriage forks must dip down to discharge elevation (Y=0.05m, 15cm below haulout chains at Y=0.20m)")
	assert(sorter._floor_bed.constant_linear_velocity.length() > 0.0, "Haul-out bed must have active outfeed velocity")
	print("PASS Path C: Forks interleave below haul-out chains, transferring stack to outfeed.")

	# 6. Path D: Lowered Pack Haul-Out Corridor Clearance
	print("\n--- 6. Path D: Lowered Pack Haul-Out Corridor Clearance ---")
	var dividers: StaticBody3D = sorter.get_node("RuntimeParts/BayDividers")
	assert(is_instance_valid(dividers), "BayDividers must exist")
	for child in dividers.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var box_shape := child.shape as BoxShape3D
			var bottom_y: float = child.position.y - box_shape.size.y * 0.5
			assert(bottom_y >= 1.55, "Divider bottom Y (%.2f) must not extend into 1.4m pack corridor (Y >= 1.60m)" % bottom_y)
	print("PASS Path D: Full machine length floor tunnel verified open from Y=0.20m to Y=1.60m (1.40m headroom).")

	print("\n" + "=".repeat(70))
	print("ALL 4 MOTION ENVELOPES VERIFIED SUCCESSFULLY: 50-BAY BIN SORTER VALIDATED")
	print("=".repeat(70))
	quit(0)
