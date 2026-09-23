extends SceneTree
var failures: int = 0
func _init(): call_deferred("check")
func expect(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int):
	for i in count: await physics_frame
func check():
	var deck = load("res://game/transport/decks/edger_landing_deck.tscn").instantiate()
	root.add_child(deck)
	var chain_tracks := 0
	for belt in deck._belts:
		if String((belt as Node).name).begins_with("ChainSurface_"):
			chain_tracks += 1
	expect(chain_tracks == 5, "Five physical chain tracks required")
	expect(deck._chains.multimesh.instance_count == 520, "All chain links must be present")
	expect(deck._shafts.size() == 2, "Both common sprocket shafts must be animatable")
	var pickup_lanes_clear: bool = deck.INCLINE_PICKUP_TRACKS.size() == 4
	for pickup_x: float in deck.INCLINE_PICKUP_TRACKS:
		var nearest: float = INF
		for deck_x: float in deck.TRACKS:
			nearest = minf(nearest, absf(pickup_x - deck_x))
		if nearest < 0.60:
			pickup_lanes_clear = false
	expect(pickup_lanes_clear, "Incline pickup lanes must straddle rather than overlap deck chains")
	var discharge_frame: StaticBody3D = deck.get_node("RuntimeParts/FrameCollisions") as StaticBody3D
	var slots_open: bool = true
	for child: Node in discharge_frame.get_children():
		if not (child is CollisionShape3D) or absf((child as CollisionShape3D).position.z - 3.35) > 0.01:
			continue
		var collision: CollisionShape3D = child as CollisionShape3D
		if not (collision.shape is BoxShape3D) or absf(collision.position.y + 0.4) > 0.01:
			continue
		var box: BoxShape3D = collision.shape as BoxShape3D
		var left: float = collision.position.x - box.size.x * 0.5
		var right: float = collision.position.x + box.size.x * 0.5
		for pickup_x: float in deck.INCLINE_PICKUP_TRACKS:
			if pickup_x > left and pickup_x < right:
				slots_open = false
	expect(slots_open, "Discharge cross member must be cut around all four incline lug slots")
	var ramps = deck.get_node("RuntimeParts/LandingRampCollisions")
	expect(ramps.get_child_count() == 5, "Entry ramp plus four inter-chain ramps required")
	for col in ramps.get_children():
		expect(col.rotation.z > 0, "Ramps must rise toward +X")
		expect(is_equal_approx(col.shape.size.z, 0.8), "Ramps must stay in landing strip")
		var high = col.transform * Vector3(col.shape.size.x/2, col.shape.size.y/2, 0)
		expect(high.y < 0 and high.y > -0.007, "Ramp lip must be just below chain top")
	var board = load("res://game/lumber/cut_board.tscn").instantiate()
	board.position = Vector3(0, 0.07, 0)
	root.add_child(board)
	var identity = board.get_instance_id()
	await frames(180)
	expect(board.position.z > 1.3, "Forward chain transport failed")
	expect(abs(board.position.y - 0.019) < 0.01, "Board must remain supported")
	deck.external_stop = true
	await frames(90)
	expect(board.linear_velocity.length() < 0.025, "External stop failed")
	var stopped_z: float = board.position.z
	deck.external_stop = false
	deck.reverse_direction = true
	await frames(120)
	expect(board.position.z < stopped_z - 0.8, "Reverse chain transport failed")
	expect(board.get_instance_id() == identity and not board.freeze, "Preserve physical board identity")
	expect(board.nominal_size == "2x8" and board.length_feet == 16, "Preserve lumber metadata")
	board.free()
	deck.running = false
	await frames(60)
	expect(is_zero_approx(deck.actual_speed), "Run toggle failed")
	# A board arrives broadside from the edger, sliding along +X across the chain
	# tracks, so the arrival corridor must present one continuous surface: any face
	# standing proud of it catches the board's leading edge and stops the board
	# dead, half on the edger. Rest a nose probe on that surface in a gap between
	# tracks and push it across, which is the failing case this guards.
	var plate: Node = deck.get_node_or_null("RuntimeParts/EntryPlate")
	expect(plate != null, "Arrival corridor needs a dead plate across the chain tracks")
	if plate != null:
		var plate_shape: CollisionShape3D = null
		for child in plate.get_children():
			if child is CollisionShape3D:
				plate_shape = child
				break
		expect(plate_shape != null, "Entry plate has no collision shape")
		var plate_box := plate_shape.shape as BoxShape3D
		var plate_top: float = plate_shape.position.y + plate_box.size.y * 0.5
		expect(absf(plate_top) < 0.0005, "Entry plate top must be flush with the chain tops, got %.4f" % plate_top)
		var track_span: float = absf(deck.TRACKS[deck.TRACKS.size() - 1] - deck.TRACKS[0]) + 0.115
		expect(plate_box.size.x >= track_span,
			"Entry plate must span the chain tracks (%.2f < %.2f)" % [plate_box.size.x, track_span])

	var nose = RigidBody3D.new()
	nose.mass = 5.0
	nose.continuous_cd = true
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.20, 0.038, 0.15)
	var col = CollisionShape3D.new()
	col.shape = shape
	nose.add_child(col)
	# Between tracks, resting on the arrival surface (bottom of the probe at 0).
	nose.position = Vector3(-0.75, 0.019, 0)
	root.add_child(nose)
	for i in 90:
		nose.apply_central_force(Vector3(100, 0, 0))
		await physics_frame
		if nose.position.x > 0.12: break
	expect(nose.position.x > 0.12, "Board nose stalled crossing the arrival surface")
	expect(nose.position.y > 0.010, "Board nose dropped into a gap between chain tracks (y=%.3f)" % nose.position.y)
	nose.free()
	# Deck rotation must rotate transport into world space.
	deck.rotation.y = PI / 2
	deck.running = true
	deck.reverse_direction = false
	var rotated_load: RigidBody3D = load("res://game/lumber/cut_board.tscn").instantiate()
	root.add_child(rotated_load)
	rotated_load.global_position = deck.to_global(Vector3(0.0, 0.12, 0.0))
	await frames(45)
	expect(deck._belts[0].constant_linear_velocity.x > 0.5, "Transport must follow deck orientation")
	rotated_load.free()
	expect(abs(deck._belts[0].constant_linear_velocity.z) < 0.001, "Rotated deck must not drive world Z")
	deck.free()
	print("LANDING_DECK_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)
