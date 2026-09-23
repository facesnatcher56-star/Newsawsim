extends SceneTree

## Regression for real rigid-board handling through the overhead sorter and into
## the orange cradle. The overhead lugs must move an unfrozen board by contact;
## two dropped boards must be caught and form a non-overlapping physical stack.

const SORTER_SCENE := "res://game/machines/sorter/bin_sorter.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"

var failures: int = 0


func _init() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	if ok:
		print("   ok   ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func frames(count: int) -> void:
	for _frame: int in count:
		await physics_frame


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var sorter: BinSorter = load(SORTER_SCENE).instantiate()
	sorter.conveyor_speed = 2.5
	sorter.random_bay_sorting = false
	world.add_child(sorter)
	await frames(4)

	var physical_lugs: Array[Node] = sorter.find_children("SorterLugStation_*", "AnimatableBody3D", true, false)
	expect(not physical_lugs.is_empty(), "sorter has physical moving lug stations")
	var lug_shapes_ok: bool = not physical_lugs.is_empty()
	for station: Node in physical_lugs:
		var shapes: Array[Node] = station.find_children("*", "CollisionShape3D", false, false)
		if shapes.size() != SorterChainSystem.TOP_STRANDS.size():
			lug_shapes_ok = false
			break
	expect(lug_shapes_ok, "every sorter lug station pushes at all four chain lanes")

	var first: RigidBody3D = await _send_board(sorter)
	var target_bay: int = SorterBoardTracker.get_board_sorting_grade(first, sorter.num_bins)
	var first_touched_lug: bool = false
	var first_froze: bool = false
	var first_start_x: float = sorter.to_local(first.global_position).x
	for _frame: int in 1200:
		await physics_frame
		if not is_instance_valid(first):
			break
		first_froze = first_froze or first.freeze
		for collider: Node3D in first.get_colliding_bodies():
			if String(collider.name).begins_with("SorterLugStation_"):
				first_touched_lug = true
		if sorter._bay_board_counts[target_bay] >= 1:
			break
	var first_end_x: float = sorter.to_local(first.global_position).x
	expect(not first_froze, "sorter never freezes or teleports the first board")
	expect(first_touched_lug, "a physical sorter lug contacted the first board")
	expect(first_end_x > first_start_x + 2.0, "lug contact moved the first board along the sorter")
	expect(sorter._bay_board_counts[target_bay] == 1, "first board landed in its target bay")
	await frames(90)
	expect(_touches_cradle_or_board(first, sorter._cradle_bodies[target_bay], []),
		"first board rests on the orange cradle arms")

	# Let the gate close before admitting the next board into the same grade bay.
	for _frame: int in 240:
		await physics_frame
		if sorter._gate_angles[target_bay] < 0.02:
			break

	var second: RigidBody3D = await _send_board(sorter)
	var second_touched_lug: bool = false
	var second_froze: bool = false
	for _frame: int in 1200:
		await physics_frame
		if not is_instance_valid(second):
			break
		second_froze = second_froze or second.freeze
		for collider: Node3D in second.get_colliding_bodies():
			if String(collider.name).begins_with("SorterLugStation_"):
				second_touched_lug = true
		if sorter._bay_board_counts[target_bay] >= 2:
			break
	expect(not second_froze, "sorter never freezes or teleports the second board")
	expect(second_touched_lug, "a physical sorter lug contacted the second board")
	expect(sorter._bay_board_counts[target_bay] == 2, "second board landed in the same target bay")
	await frames(120)

	var lower: RigidBody3D = first if first.global_position.y < second.global_position.y else second
	var upper: RigidBody3D = second if lower == first else first
	var min_separation: float = (first.board_thickness + second.board_thickness) * 0.5 - 0.004
	expect(upper.global_position.y - lower.global_position.y >= min_separation,
		"boards stack without clipping through each other (separation %.4f m)" % (upper.global_position.y - lower.global_position.y))
	expect(_touches_cradle_or_board(upper, sorter._cradle_bodies[target_bay], [lower]),
		"upper board is physically supported by the board below")
	expect(_touches_cradle_or_board(lower, sorter._cradle_bodies[target_bay], []),
		"lower board remains physically supported by the orange arms")

	print("SORTER_PHYSICAL_BOARD_FLOW_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)


func _send_board(sorter: BinSorter) -> RigidBody3D:
	var board: RigidBody3D = load(BOARD_SCENE).instantiate()
	# One-inch lumber is the hardest case for tunnelling through moving lugs,
	# orange arms, or another board, so use it for both stack layers.
	board.nominal_size = "1x8"
	board.length_feet = 8
	board.rotation.y = PI * 0.5
	board.contact_monitor = true
	board.max_contacts_reported = 16
	sorter.get_parent().add_child(board)
	board.global_position = sorter.to_global(Vector3(-0.35, sorter.sorter_height + board.board_thickness * 0.5 + 0.01, 0.0))
	await physics_frame
	sorter._on_infeed_body_entered(board)
	return board


func _touches_cradle_or_board(board: RigidBody3D, cradle: AnimatableBody3D, boards: Array) -> bool:
	for collider: Node3D in board.get_colliding_bodies():
		if collider == cradle or boards.has(collider):
			return true
	return false
