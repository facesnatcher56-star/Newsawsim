extends SceneTree

## The incline parks its pickup before a board arrives; the landing deck keeps
## feeding the board to the handoff instead of stopping to phase the lugs.
const MILL := "res://game/levels/mill_prototype.tscn"
const BOARD := "res://game/lumber/cut_board.tscn"
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: " + message)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame

func run() -> void:
	var mill: Node3D = load(MILL).instantiate()
	root.add_child(mill)
	current_scene = mill
	var incline: BoardLugIncline = mill.get_node("BoardLugIncline")
	var deck: EdgerLandingDeck = mill.get_node("landing_deck_frame")
	await frames(120)
	expect(absf(incline.actual_speed) < 0.02, "empty incline is stationary")
	expect(incline._pickup_lug_positions().is_empty(), "empty pickup corridor is parked clear")
	expect(absf(deck.actual_speed) < 0.02 and not deck.external_stop, "empty landing deck is idle")
	# Isolate this pickup test from the mill's pre-placed example board.
	for node: Node in get_nodes_in_group("cut_boards"):
		if node is RigidBody3D:
			(node as RigidBody3D).free()
	await frames(2)
	var board: RigidBody3D = load(BOARD).instantiate()
	board.nominal_size = "2x12"
	board.length_feet = 16
	mill.add_child(board)
	board.global_position = incline.to_global(Vector3(0.0, 0.10, -1.15))
	var deck_stopped: bool = false
	var deck_started: bool = false
	var early_incline_drive: bool = false
	var handed_over: bool = false
	var climbed: bool = false
	for index: int in 800:
		await physics_frame
		var z: float = incline.to_local(board.global_position).z
		if deck.actual_speed > 0.4:
			deck_started = true
		if z < 0.0 and deck_started and (deck.actual_speed < 0.4 or deck.external_stop):
			deck_stopped = true
		if z < incline._pushable_trailing_z(board.board_thickness) + board.board_width * 0.5 - 0.08 and incline.actual_speed > 0.05:
			early_incline_drive = true
		if incline._pickup_handed_over:
			handed_over = true
		if z > 1.0:
			climbed = true
			break
	expect(deck_started and not deck_stopped, "deck starts on board arrival and does not pause before pickup")
	expect(not early_incline_drive, "incline waits until board reaches the correct trailing-edge position")
	expect(handed_over, "board triggers the incline handoff")
	expect(climbed, "physical board climbs after parked incline resumes")
	var sorter: BinSorter = mill.get_node("BinSorter")
	var sorter_took_board: bool = false
	for index: int in 2200:
		await physics_frame
		for data: Variant in sorter._tracked_boards:
			if data.board == board:
				sorter_took_board = true
				break
		if sorter_took_board:
			break
	expect(sorter_took_board, "first board clears the incline into the sorter")
	await frames(720)
	print("repark drive=%.2f on_run=%s board_z=%.2f holding=%s pickup=%s sorter_top=%s" % [incline.actual_speed, str(incline._board_on_run()), incline.to_local(board.global_position).z, str(incline.is_holding()), str(incline.is_pickup_held()), str(sorter._top_active)])
	expect(absf(incline.actual_speed) < 0.02 and incline._pickup_lug_positions().is_empty(),
		"incline re-parks at the clear pickup mark after the board leaves")
	expect(absf(deck.actual_speed) < 0.02 and not deck.external_stop,
		"empty landing deck returns to idle while incline re-parks")
	var next_board: RigidBody3D = load(BOARD).instantiate()
	next_board.nominal_size = "2x8"
	next_board.length_feet = 12
	mill.add_child(next_board)
	next_board.global_position = incline.to_global(Vector3(0.0, 0.10, -1.15))
	var next_climbed: bool = false
	var next_deck_stopped: bool = false
	var next_started: bool = false
	for index: int in 800:
		await physics_frame
		var next_z: float = incline.to_local(next_board.global_position).z
		if deck.actual_speed > 0.4:
			next_started = true
		if next_z < 0.0 and next_started and (deck.actual_speed < 0.4 or deck.external_stop):
			next_deck_stopped = true
		if next_z > 1.0:
			next_climbed = true
			break
	expect(next_started and not next_deck_stopped and next_climbed,
		"second board is fed without pausing and is collected from the re-parked pickup")
	mill.free()
	print("INCLINE_IDLE_PICKUP_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)
