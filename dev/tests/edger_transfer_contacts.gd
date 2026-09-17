extends SceneTree

## Contact-level probe for the edger -> landing deck transfer.
##
## For every frame the tracked board spends crossing the gap, prints where the
## board is, how fast it is going in X, and every contact it has: which body,
## where on the board, and how hard the impulse was. A sudden -X impulse at the
## tail with an edger part in the list means the board is being stopped by the
## machine; nothing but chain friction means it simply ran out of drive.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/edger_transfer_contacts.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 900
const START_X := 45.0
const END_X := 50.6

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await physics_frame
	await physics_frame

	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no cut board found")
		quit()
		return
	board.contact_monitor = true
	board.max_contacts_reported = 16
	var half_length: float = 2.479
	if "product_length" in board:
		half_length = float(board.get("product_length")) * 0.5
	print("tracking %s  half_length=%.3f" % [board.name, half_length])
	print("columns: x, y, vx, dvx (change in vx since last frame), then every contact as name@board_local_x*impulse_len")

	var previous_vx: float = 0.0
	var reported: int = 0
	for frame in range(FRAMES):
		await physics_frame
		var pos: Vector3 = board.global_position
		var vel: Vector3 = board.linear_velocity
		if pos.x < START_X:
			previous_vx = vel.x
			continue
		if pos.x > END_X and reported > 8:
			break
		reported += 1

		# Attribute the per-frame impulse along X to whoever delivered it: a
		# negative sum is a brake, a positive sum is a drive.
		var per_collider: Dictionary = {}
		var total_x: float = 0.0
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(board.get_rid())
		if state != null:
			for i in state.get_contact_count():
				var other: Object = state.get_contact_collider_object(i)
				var name: String = "-"
				if other is Node:
					name = String((other as Node).get_path()).replace("/root/MillPrototype/", "")
				var impulse: Vector3 = state.get_contact_impulse(i)
				if not per_collider.has(name):
					per_collider[name] = [0.0, 0]
				var entry: Array = per_collider[name]
				entry[0] = float(entry[0]) + impulse.x
				entry[1] = int(entry[1]) + 1
				total_x += impulse.x
		var ranked: Array = []
		for key in per_collider:
			ranked.append([absf(float(per_collider[key][0])), key, float(per_collider[key][0]), int(per_collider[key][1])])
		ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var parts: Array[String] = []
		for entry in ranked.slice(0, 4):
			parts.append("%s %+.1f x%d" % [entry[1], entry[2], entry[3]])
		var mass: float = maxf(board.mass, 0.001)
		print("f%04d x=%7.3f vx=%6.2f dvx=%6.2f | impulse_x sum=%+8.1f (=> %+6.1f m/s^2) | %s" % [
			frame, pos.x, vel.x, vel.x - previous_vx, total_x, total_x / (mass / 60.0),
			" ; ".join(parts)])
		previous_vx = vel.x
	quit()

func _pick_board(mill: Node) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_distance: float = 1e9
	for node in mill.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if body == null or body.freeze or not body.is_in_group("cut_boards"):
			continue
		if body.global_position.x > 44.0:
			continue
		var distance: float = absf(body.global_position.z - 18.29)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best
