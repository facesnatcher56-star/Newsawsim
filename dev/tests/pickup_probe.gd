extends SceneTree

## Fine-grained probe of the deck -> incline hand-over window.
##
## Prints the board's position, attitude and - decisively - which bodies it is
## touching while it crosses the pickup, together with the incline's hold flags.
## A lug station in that contact list while the board is tipping means the board
## is riding up on a lug; no station in the list while it tips means something
## else is throwing it.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/pickup_probe.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 1500

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill

	var deck: Node3D = mill.get_node("landing_deck_frame")
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no board")
		quit(1)
		return
	board.contact_monitor = true
	board.max_contacts_reported = 16

	print("tracking %s" % board.name)
	print("f | incl z   y | face swing | v.z    | hold over | touching")
	for frame in range(FRAMES):
		await physics_frame
		if not is_instance_valid(board):
			break
		var local: Vector3 = incline.to_local(board.global_position)
		if local.z < -1.2 or local.z > 1.6:
			continue
		var basis: Basis = board.global_transform.basis
		var face: float = rad_to_deg(acos(clampf(absf(basis.y.normalized().dot(Vector3.UP)), 0.0, 1.0)))
		var swing: float = rad_to_deg(acos(clampf(absf(basis.x.normalized().dot(Vector3.RIGHT)), 0.0, 1.0)))
		var touching: Array[String] = []
		for body in board.get_colliding_bodies():
			var label := String((body as Node).name)
			if not touching.has(label):
				touching.append(label)
		print("%4d | %7.3f %6.3f | %5.0f %5.0f | %6.3f | %5s %5s | %s" % [
			frame, local.z, local.y, face, swing,
			board.linear_velocity.dot(incline.global_basis.z),
			str(incline.get("_pickup_held")), str(incline.get("_pickup_handed_over")),
			", ".join(touching) if not touching.is_empty() else "-"])
	quit(0)

func _pick_board(mill: Node) -> RigidBody3D:
	var all: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool:
			return n.is_in_group("cut_boards") or "CutBoard" in String(n.name))
	var near: Array = all.filter(
		func(b: Node) -> bool: return absf((b as Node3D).global_position.z - 18.29) < 0.5)
	return (near[0] if not near.is_empty() else all[0]) as RigidBody3D
