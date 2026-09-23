extends SceneTree

## Diagnostic probe for a board that stalls on the landing deck instead of being
## carried across it. Mirrors edger_board_flow_test.gd but prints the drive state
## of both machines each report interval, so the cause is a measured value rather
## than a guess:
##   deck.actual_speed / external_stop / _is_board_entering / _belts_slippery
##   incline._holding / actual_speed
## plus which bodies the board is actually touching.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/deck_drive_diagnosis.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 1200
const REPORT_EVERY := 30

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill

	var deck: Node = mill.get_node("landing_deck_frame")
	var incline: Node = mill.get_node("BoardLugIncline")
	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no board found")
		quit(1)
		return
	board.contact_monitor = true
	board.max_contacts_reported = 12

	var half_len: float = float(board.get("product_length")) * 0.5
	print("board=%s  product_length=%s  half_len=%.3f" % [
		board.name, str(board.get("product_length")), half_len])
	print("deck-local x needed to clear the edger: %.3f (tail_x must reach -2.90)" % (-2.90 + half_len))
	print("frame | deck_x  deck_z | board_v       | deck.actual ext entering slippery | incline.hold inc.spd | touching")
	for frame in range(FRAMES):
		await physics_frame
		if frame % REPORT_EVERY != 0:
			continue
		var local: Vector3 = (deck as Node3D).to_local(board.global_position)
		var vel: Vector3 = board.linear_velocity
		var touching: Array[String] = []
		for body in board.get_colliding_bodies():
			var path := String((body as Node).get_path()).replace("/root/MillPrototype/", "")
			if not touching.has(path):
				touching.append(path)
		print("%5d | %7.3f %7.3f | %5.2f %5.2f %5.2f | %7.3f %5s %8s %8s | %8s %7.3f | %s" % [
			frame, local.x, local.z, vel.x, vel.y, vel.z,
			float(deck.get("actual_speed")), str(deck.get("external_stop")),
			str(deck.call("_is_board_entering")), str(deck.get("_belts_slippery")),
			str(incline.call("is_holding")), float(incline.get("actual_speed")),
			", ".join(touching) if not touching.is_empty() else "-"])
		if frame > 400 and local.z > 2.0:
			print("   >>> board is being carried across the deck")
			break
	quit(0)

## Same selection rule as edger_board_flow_test.gd so both probes watch the
## identical board.
func _pick_board(mill: Node) -> RigidBody3D:
	var all: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool:
			return n.is_in_group("cut_boards") or "CutBoard" in String(n.name))
	var near: Array = all.filter(
		func(b: Node) -> bool: return absf((b as Node3D).global_position.z - 18.29) < 0.5)
	return (near[0] if not near.is_empty() else all[0]) as RigidBody3D
