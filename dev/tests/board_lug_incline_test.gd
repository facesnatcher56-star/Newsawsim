extends SceneTree

## Verification for the board lug incline that lifts edger boards from the
## landing chain deck's discharge to the bin sorter's infeed table.
##
## Part 1 checks the machine on its own: carrying plane geometry, one pusher per
## chain lane, stations held out of the way on the return, a flush carrying
## surface, and a board that cannot run back down the ramp past a lug.
##
## Part 2 puts it in the mill and drives a real board up it, asserting the foot
## is flush with the deck's chain tops, the crest is flush with the sorter's
## infeed rails, and the sorter's scanner zone takes the board over at the crest.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/board_lug_incline_test.gd

const STANDALONE := "res://game/transport/decks/board_lug_incline.tscn"
const BOARD := "res://game/lumber/cut_board.tscn"
const MILL := "res://game/levels/mill_prototype.tscn"
const SORTER_RAIL_Z := 29.488    # world Z where the sorter's infeed rails begin

var failures: int = 0


func _init() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	if ok:
		print("   ok   ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func frames(count: int) -> void:
	for _i in count:
		await physics_frame


func run() -> void:
	await check_machine()
	await check_line_handoff()
	await check_sorter_interlock()
	print("BOARD_LUG_INCLINE_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)


# ─────────────────────────────────────────────────────────────────────────────
#  3. Backpressure: a full sorter stops the chain and backs the deck up
# ─────────────────────────────────────────────────────────────────────────────

func check_sorter_interlock() -> void:
	print("--- backpressure interlock ---")
	var mill: Node = load(MILL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await frames(6)

	var incline: BoardLugIncline = mill.get_node_or_null("BoardLugIncline")
	var sorter: BinSorter = mill.get_node_or_null("BinSorter")
	var deck: Node3D = mill.get_node_or_null("landing_deck_frame")
	if incline == null or sorter == null or deck == null:
		expect(false, "mill nodes for the interlock check")
		return

	# A full sorter cannot accept anything, so a board waiting on the crest must
	# park there on its lug and hold the landing deck with it.
	for bay in sorter.num_bins:
		sorter._bay_board_counts[bay] = sorter.max_boards_per_bay

	var board: RigidBody3D = load(BOARD).instantiate()
	board.nominal_size = "2x8"
	board.length_feet = 12
	mill.add_child(board)
	var park_z: float = incline._p2.x - 0.55
	board.global_position = incline.to_global(Vector3(0.0, incline._plane_y(park_z) + 0.10, park_z))
	await frames(120)

	expect(incline.is_holding(), "incline holds while the sorter cannot accept a board")
	expect(incline.actual_speed < 0.05, "chain stops while holding (%.3f m/s)" % incline.actual_speed)
	expect(bool(deck.get("external_stop")), "landing deck is backed up by the hold")

	# Room appears only when every bay has finished dumping, because a bay that is
	# discharging accepts nothing. Wait for the sorter to clear itself rather than
	# editing its state: the incline's release has to follow the real predicate.
	var freed := false
	for _frame in 1800:
		await physics_frame
		if sorter.can_accept_board(board):
			freed = true
			break
	expect(freed, "sorter finished discharging and can accept boards again")
	await frames(30)
	expect(not incline.is_holding(), "hold releases when the sorter has room")
	expect(not bool(deck.get("external_stop")), "landing deck is released with the incline")

	var taken := false
	for _frame in 900:
		await physics_frame
		if not is_instance_valid(board):
			break
		for data in sorter._tracked_boards:
			if data.board == board:
				taken = true
				break
		if taken:
			break
	expect(taken, "sorter takes the parked board once it has room")
	mill.free()


# ─────────────────────────────────────────────────────────────────────────────
#  1. The machine on its own
# ─────────────────────────────────────────────────────────────────────────────

func check_machine() -> void:
	print("--- lug incline geometry and pockets ---")
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var incline: BoardLugIncline = load(STANDALONE).instantiate()
	world.add_child(incline)
	await frames(4)

	var rise: float = incline.rise
	var run: float = incline._run
	expect(run > 0.0 and incline._slope_len > run, "ramp resolves a run shorter than its slope")
	expect(near(incline._p0.y, 0.0, 1e-6) and near(incline._p2.y, rise, 1e-6),
		"carrying plane climbs the exported rise (%.3f m)" % rise)
	expect(near(incline._p2.x, run + incline.level_length, 1e-6),
		"crest ends at ramp run plus crest length")
	expect(incline.track_x_positions.size() == 4, "four incline chains interleave between the five landing-deck chains")
	expect(incline._pickup_point.x < -0.7 and incline._pickup_point.y < -0.3,
		"incline lower tangent starts beneath the landing deck")

	# ── Lugs: one station per pocket, a pusher on every lane, and the stations
	# travelling the return run held out of the way with no collision.
	var stations: int = incline._stations.size()
	expect(stations >= 8, "lug stations are spaced along the loop (%d)" % stations)
	var carrying := 0
	var returning := 0
	var shapes_ok := true
	for i in stations:
		if incline._station_shapes[i].size() != incline.track_x_positions.size():
			shapes_ok = false
		for shape in incline._station_shapes[i]:
			if (shape as CollisionShape3D).disabled == incline._slot_visible[i]:
				shapes_ok = false
		if incline._slot_visible[i]:
			carrying += 1
		else:
			returning += 1
	expect(shapes_ok, "every station carries a pusher on all incline lanes and only pushes while on the run")
	expect(returning > 0, "returning stations are held below the bed (%d)" % returning)
	expect(carrying >= 5, "the carrying run holds several pockets at once (%d)" % carrying)
	var pitch: float = incline._loop_len / float(stations)
	expect(pitch > 0.5, "pocket pitch keeps boards apart (%.2f m)" % pitch)

	# ── Roller chain: every lane is one closed loop and the unloaded return hangs
	# below its end-to-end chord instead of being stretched tight under the bed.
	expect(incline._num_links >= 50, "full loop has enough roller links (%d per lane)" % incline._num_links)
	expect(near(incline._link_spacing * float(incline._num_links), incline._loop_len, 0.001),
		"roller links close the complete loop without a seam or overlap")
	expect(incline._plates_mm.multimesh.instance_count == incline._num_links * incline.track_x_positions.size() * 2,
		"both side plates cover every link on all incline loops")
	expect(incline._rollers_mm.multimesh.instance_count == incline._num_links * incline.track_x_positions.size(),
		"every link joint has a roller on all incline loops")
	var plate_mesh: BoxMesh = incline._plates_mm.multimesh.mesh as BoxMesh
	var links_connected := plate_mesh != null
	for j in incline._num_links:
		var slot: float = float(j) * incline._link_spacing + incline._travel
		var pin_a: Vector2 = incline._sample(slot)[0]
		var pin_b: Vector2 = incline._sample(slot + incline._link_spacing)[0]
		var chord: Vector2 = pin_b - pin_a
		var plate_xf: Transform3D = incline._chain_plate_transform(slot, incline.track_x_positions[0], j, -1.0)
		var plate_mid := Vector2(plate_xf.origin.z, plate_xf.origin.y)
		var plate_axis := Vector3(0.0, chord.y, chord.x).normalized()
		if plate_mid.distance_to((pin_a + pin_b) * 0.5) > 0.002:
			links_connected = false
		if absf(plate_xf.basis.z.normalized().dot(plate_axis)) < 0.999:
			links_connected = false
		if plate_mesh != null and plate_mesh.size.z + 0.001 < chord.length():
			links_connected = false
	expect(links_connected, "every side plate bridges one roller pin to the next with overlap")
	var return_mid: Vector2 = incline._sample(incline._return_start_s + incline._return_len * 0.5)[0]
	var chord_mid: Vector2 = incline._ret_top.lerp(incline._ret_foot, 0.5)
	expect(return_mid.y < chord_mid.y - incline.return_sag * 0.70,
		"unloaded return has natural sag (%.2f m below chord)" % (chord_mid.y - return_mid.y))
	var return_lugs_follow_chain := true
	for i in stations:
		if incline._slot[i] >= incline._run_len:
			var chain_point: Vector2 = incline._sample(incline._slot[i])[0]
			var lug_point := Vector2(incline._stations[i].position.z, incline._stations[i].position.y)
			if lug_point.distance_to(chain_point) > 0.002:
				return_lugs_follow_chain = false
	expect(return_lugs_follow_chain, "returning lugs remain attached to the sagging roller chain")

	# ── Empty chain is parked at its pickup mark. Manual reverse still works.
	await frames(30)
	expect(absf(incline.actual_speed) < 0.02 and incline._pickup_lug_positions().is_empty(),
		"empty incline parks with pickup corridor clear")
	incline.reverse_direction = true
	await frames(60)
	expect(incline.actual_speed < -0.1, "reverse control runs the full loop downhill")
	incline.running = false
	await frames(30)
	expect(absf(incline.actual_speed) < 0.02, "drive decelerates to a stop from either direction")

	# ── Carrying surface: strip tops must sit exactly on the carrying plane, or
	# a board crossing the machine would meet a lip where the ramp kinks.
	for i in stations:
		incline._set_station_shapes(i, false)
	await frames(2)
	var space: PhysicsDirectSpaceState3D = incline.get_world_3d().direct_space_state
	var flush := true
	for z: float in [0.4, 2.0, 4.8, 6.2, 7.4]:
		var plane: float = incline._plane_y(z)
		# Probe solid strips, not the open channels around the interleaved lanes.
		for lx: float in [-0.30, 0.30]:
			var from := incline.to_global(Vector3(lx, plane + 0.35, z))
			var to := incline.to_global(Vector3(lx, plane - 0.12, z))
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				flush = false
				print("   --   no carrying surface at local z=%.2f x=%.2f" % [z, lx])
				continue
			var surface: float = incline.to_local(hit["position"] as Vector3).y
			if not near(surface, plane, 0.006):
				flush = false
				print("   --   surface at local z=%.2f x=%.2f is %.4f, plane is %.4f" % [z, lx, surface, plane])
	expect(flush, "carrying surface is flush along the whole ramp and crest")

	# ── Pockets hold boards: stopped chains, a board dropped mid-ramp must be
	# caught by the lug below it instead of running down to the foot.
	incline.external_stop = true
	for i in stations:
		incline._set_station_shapes(i, true)
	await frames(4)

	var board: RigidBody3D = load(BOARD).instantiate()
	board.nominal_size = "2x8"
	board.length_feet = 16
	world.add_child(board)
	var drop_z: float = run * 0.75
	board.global_position = incline.to_global(Vector3(0.0, incline._plane_y(drop_z) + 0.12, drop_z))
	await frames(180)

	var settled := incline.to_local(board.global_position)
	var lug_z := -1.0
	for i in stations:
		if incline._slot[i] < incline._run_len:
			var point: Vector2 = incline._sample(incline._slot[i])[0]
			if point.x < drop_z and point.x > lug_z:
				lug_z = point.x
	expect(lug_z > 0.0, "a lug sits below the dropped board")
	expect(settled.z > lug_z + 0.10,
		"board is held by the lug below it (settled z=%.2f, lug z=%.2f)" % [settled.z, lug_z])
	expect(board.linear_velocity.length() < 0.15, "board comes to rest against the lug")
	expect(not board.freeze and board.nominal_size == "2x8", "board stays a physical 2x8")

	board.free()
	world.free()


# ─────────────────────────────────────────────────────────────────────────────
#  2. In the mill, climbing and handing off to the sorter
# ─────────────────────────────────────────────────────────────────────────────

func check_line_handoff() -> void:
	print("--- mill line: deck -> incline -> sorter ---")
	var mill: Node = load(MILL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await frames(6)

	var incline: BoardLugIncline = mill.get_node_or_null("BoardLugIncline")
	var sorter: BinSorter = mill.get_node_or_null("BinSorter")
	var deck: Node3D = mill.get_node_or_null("landing_deck_frame")
	expect(incline != null, "mill contains the board lug incline")
	expect(sorter != null, "mill contains the bin sorter")
	expect(deck != null, "mill contains the landing deck")
	if incline == null or sorter == null or deck == null:
		return
	expect(incline._upstream == deck, "incline found the landing deck for its upstream interlock")

	# The incline chains occupy the gaps between deck chains. This leaves enough
	# lateral clearance for both roller-chain loops and their lugs at the overlap.
	var lanes_interleaved: bool = true
	for incline_x: float in incline.track_x_positions:
		var nearest_deck_chain: float = INF
		for deck_x: float in deck.TRACKS:
			nearest_deck_chain = minf(nearest_deck_chain, absf(incline_x - deck_x))
		if nearest_deck_chain < 0.60 or not deck.INCLINE_PICKUP_TRACKS.has(incline_x):
			lanes_interleaved = false
	expect(lanes_interleaved, "incline chains straddle the deck chains without sharing a lane")
	expect(deck.PICKUP_SLOT_WIDTH > incline.LUG_POST_W + 0.08,
		"deck pickup slots clear the incline lug posts")
	expect(deck.PICKUP_SLOT_LENGTH >= incline.pickup_overlap,
		"deck pickup corridors cover the full recessed incline overlap")

	# Deck-end crossing remains flush while the incline's true foot now starts
	# below the last 0.8 m of deck so its lugs emerge through those slots.
	# A board
	# must not meet a step, and must not cross a dead gap where the drive stops.
	var deck_chain_end := deck.to_global(Vector3(0.0, 0.0, 3.35))
	expect(near(incline.global_position.y, deck_chain_end.y, 0.002),
		"deck-end crossing is level with the deck chain tops (%.4f vs %.4f)" % [incline.global_position.y, deck_chain_end.y])
	expect(near(incline.global_position.z, deck_chain_end.z, 0.002),
		"incline ramp crosses the carrying plane where the deck chain run ends")
	var pickup_world: Vector3 = incline.to_global(Vector3(
		0.0, incline._pickup_point.y, incline._pickup_point.x))
	expect(pickup_world.z < deck_chain_end.z - 0.7 and pickup_world.y < deck_chain_end.y - 0.3,
		"incline foot is recessed beneath the deck before the discharge end")

	# Crest flush with the sorter's infeed rails and reaching them, so the board
	# is handed over at the height the scanner zone expects with no gap.
	var rail_top: float = sorter.global_position.y + sorter.sorter_height
	var crest_end := incline.to_global(Vector3(0.0, incline.rise, incline._p2.x))
	expect(near(crest_end.y, rail_top, 0.006),
		"crest carrying plane is flush with the sorter's infeed rails (%.4f vs %.4f)" % [crest_end.y, rail_top])
	expect(crest_end.z >= SORTER_RAIL_Z,
		"crest overlaps the start of the sorter's infeed rails (z=%.3f)" % crest_end.z)
	expect(crest_end.z <= SORTER_RAIL_Z + 0.08,
		"crest stops at the sorter's rail fixings instead of running into them (z=%.3f)" % crest_end.z)

	# ── A real board waits on the last section of the landing deck. An incline
	# lug must rise from below through a pickup slot, collect it there, and carry
	# the same physical board all the way to the sorter.
	var board: RigidBody3D = load(BOARD).instantiate()
	board.nominal_size = "2x12"
	board.length_feet = 16
	mill.add_child(board)
	board.contact_monitor = true
	board.max_contacts_reported = 16
	var start_z: float = -0.30
	board.global_position = incline.to_global(Vector3(0.0, 0.12, start_z))
	var identity := board.get_instance_id()

	var taken_over := false
	var peak_rise := 0.0
	var held_while_waiting := false
	var touched_incline_lug := false
	for _frame in 3000:
		await physics_frame
		if not is_instance_valid(board):
			break
		peak_rise = maxf(peak_rise, incline.to_local(board.global_position).y)
		for collider: Node3D in board.get_colliding_bodies():
			if String(collider.name).begins_with("LugStation_"):
				touched_incline_lug = true
		if incline.is_holding():
			held_while_waiting = true
		for data in sorter._tracked_boards:
			if data.board == board:
				taken_over = true
				break
		if taken_over:
			break

	expect(peak_rise > incline.rise - 0.35,
		"board was carried up the ramp (peak local rise %.2f of %.2f)" % [peak_rise, incline.rise])
	expect(touched_incline_lug, "moving incline lugs physically contacted and pushed the board")
	var flatness: float = absf(board.global_basis.y.normalized().dot(Vector3.UP))
	expect(flatness > 0.90, "hold-down skids keep the board flat through the crest (%.3f)" % flatness)
	expect(taken_over, "the sorter's scanner zone took the board over at the crest")
	expect(not held_while_waiting, "incline never held while the sorter had room")
	expect(not board.freeze, "board remains a dynamic rigid body after sorter hand-off")
	if is_instance_valid(board):
		expect(board.get_instance_id() == identity, "board keeps its identity through the hand-off")
		expect(board.nominal_size == "2x12" and board.length_feet == 16,
			"board keeps its lumber metadata through the hand-off")

	# Hand-off completed: the sorter routes the board along its overhead chains and
	# drops it into the bay its grade selects.
	var target_bay: int = SorterBoardTracker.get_board_sorting_grade(board, sorter.num_bins)
	var delivered := false
	for _frame in 5000:
		await physics_frame
		if not is_instance_valid(board):
			break
		if sorter._bay_board_counts[target_bay] >= 1:
			delivered = true
			break
	expect(delivered, "board was routed and dropped into bay %d" % target_bay)
	if is_instance_valid(board):
		var bay_local := sorter.to_local(board.global_position)
		expect(bay_local.x >= target_bay * sorter.bin_width and bay_local.x < (target_bay + 1) * sorter.bin_width,
			"board came to rest inside bay %d (local=%s count=%d)" % [target_bay, bay_local, sorter._bay_board_counts[target_bay]])
		expect(not board.freeze, "board is back in physics after release")
		expect(board.nominal_size == "2x12" and board.length_feet == 16, "product survived the whole line")
	# Each phase gets its own mill: two of them share one physics space, and the
	# machines sit at the same world position, so a leftover mill would interfere.
	mill.free()
