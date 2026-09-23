extends SceneTree

## End-to-end probe for one physical board: edger outfeed -> landing deck ->
## lug incline -> bin sorter. The flow test only checks that a board leaves the
## edger; this one follows the same board all the way and reports where it is in
## whichever machine currently holds it, plus the incline's hold/drive state, so a
## stall at the new under-deck pickup is visible rather than inferred.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/full_line_probe.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 3000
const REPORT_EVERY := 50

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill

	var deck: Node3D = mill.get_node("landing_deck_frame")
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var sorter: Node = mill.get_node("BinSorter")

	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no board found")
		quit(1)
		return
	print("tracking %s  product_length=%s" % [board.name, str(board.get("product_length"))])
	print("frame | world x     z      y   | deck z  incl z  incl y | face(o)  swing(o) | tracked by sorter")

	var taken_at := -1
	for frame in range(FRAMES):
		await physics_frame
		if not is_instance_valid(board):
			print("board freed at frame %d" % frame)
			break
		for data in sorter.get("_tracked_boards"):
			if data.board == board:
				taken_at = frame
				break
		if frame % REPORT_EVERY != 0:
			continue
		var world: Vector3 = board.global_position
		var deck_local: Vector3 = deck.to_local(world)
		var incline_local: Vector3 = incline.to_local(world)
		# up = board's face normal. 0 deg means lying flat; near 90 deg means it has
		# tipped onto its edge. cross = board's long axis vs world X, i.e. how far it
		# has swung away from broadside.
		var basis: Basis = board.global_transform.basis
		var face: float = rad_to_deg(acos(clampf(absf(basis.y.normalized().dot(Vector3.UP)), 0.0, 1.0)))
		var long_axis: float = rad_to_deg(acos(clampf(absf(basis.x.normalized().dot(Vector3.RIGHT)), 0.0, 1.0)))
		print("%5d | %7.2f %6.2f %6.2f | %6.2f %7.2f %7.2f | %8.1f %8.1f | %s" % [
			frame, world.x, world.z, world.y, deck_local.z,
			incline_local.z, incline_local.y,
			face, long_axis,
			"yes" if taken_at >= 0 else "no"])
		if taken_at >= 0 and frame > taken_at + 200:
			break

	print("sorter took the board: %s" % ("yes at frame %d" % taken_at if taken_at >= 0 else "NO"))
	quit(0 if taken_at >= 0 else 1)

func _pick_board(mill: Node) -> RigidBody3D:
	var all: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool:
			return n.is_in_group("cut_boards") or "CutBoard" in String(n.name))
	var near: Array = all.filter(
		func(b: Node) -> bool: return absf((b as Node3D).global_position.z - 18.29) < 0.5)
	return (near[0] if not near.is_empty() else all[0]) as RigidBody3D
