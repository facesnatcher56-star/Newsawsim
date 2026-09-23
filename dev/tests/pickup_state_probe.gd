extends SceneTree

## State probe for the pickup interlock: prints the incline's hold flags, the
## actual_speed of both machines and where the lugs are, so a stall can be traced
## to the flag that caused it rather than guessed at.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/pickup_state_probe.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 1400
const REPORT_EVERY := 20

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill

	var deck: Node = mill.get_node("landing_deck_frame")
	var incline: Node = mill.get_node("BoardLugIncline")
	var board: RigidBody3D = _pick_board(mill)
	print("tracking %s" % board.name)
	print("f | incl z  | hold deckheld handed | chain spd deck spd | lugs in corridor | board v.z")
	for frame in range(FRAMES):
		await physics_frame
		if not is_instance_valid(board):
			break
		if frame % REPORT_EVERY != 0:
			continue
		var z: float = (incline as Node3D).to_local(board.global_position).z
		var lugs: Array = incline.call("_pickup_lug_positions")
		var lug_text: Array[String] = []
		for item in lugs:
			lug_text.append("%.2f" % float(item))
		print("%5d | %7.3f | %5s %8s %6s | %9.3f %8.3f | %-24s | %6.3f" % [
			frame, z, str(incline.get("_pickup_held")), str(incline.get("_deck_held")),
			str(incline.get("_pickup_handed_over")),
			float(incline.get("actual_speed")), float(deck.get("actual_speed")),
			",".join(lug_text) if not lug_text.is_empty() else "-",
			board.linear_velocity.dot((incline as Node3D).global_basis.z)])
	quit(0)

func _pick_board(mill: Node) -> RigidBody3D:
	var all: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool:
			return n.is_in_group("cut_boards") or "CutBoard" in String(n.name))
	var near: Array = all.filter(
		func(b: Node) -> bool: return absf((b as Node3D).global_position.z - 18.29) < 0.5)
	return (near[0] if not near.is_empty() else all[0]) as RigidBody3D
