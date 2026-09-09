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
	expect(deck._belts.size() == 5, "Five physical chain tracks required")
	expect(deck._chains.multimesh.instance_count == 525, "All chain links must be present")
	expect(deck._shafts.size() == 2, "Both common sprocket shafts must be animatable")
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
	# A short board-nose probe starts on the ramp below the next chain top.
	# Constant input force represents the edger continuing to push the board.
	var nose = RigidBody3D.new()
	nose.mass = 5.0
	nose.continuous_cd = true
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.20, 0.038, 0.15)
	var col = CollisionShape3D.new()
	col.shape = shape
	nose.add_child(col)
	nose.position = Vector3(-0.75, -0.03, 0)
	root.add_child(nose)
	for i in 90:
		nose.apply_central_force(Vector3(100, 0, 0))
		await physics_frame
		if nose.position.x > 0.12: break
	expect(nose.position.x > 0.12 and nose.position.y > 0.005, "Board nose failed to climb ramp onto chain")
	nose.free()
	# Deck rotation must rotate transport into world space.
	deck.rotation.y = PI / 2
	deck.running = true
	deck.reverse_direction = false
	await frames(45)
	expect(deck._belts[0].constant_linear_velocity.x > 0.5, "Transport must follow deck orientation")
	expect(abs(deck._belts[0].constant_linear_velocity.z) < 0.001, "Rotated deck must not drive world Z")
	deck.free()
	print("LANDING_DECK_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)
