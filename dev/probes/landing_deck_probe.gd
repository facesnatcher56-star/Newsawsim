extends SceneTree

## Probe: follows the first board from the edger onto the landing deck bottom and prints where it
## slides to, whether it reaches the board stop, and how it is then carried.
## Optional: pass a grip value to try it, e.g. -- 0.2
## Run: godot --headless --path . --script res://dev/probes/landing_deck_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var deck: Node3D = mill.get_node("landing_deck_frame")
	var board: RigidBody3D = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))[0]
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		deck.get_node("LandingDeckBottom").set("grip", float(args[0]))
	print("frame | deck x    z  | yaw  | vel x   z | belt speed")
	for frame in 1100:
		await physics_frame
		if frame < 600 or frame % 20 != 0:
			continue
		var p: Vector3 = deck.to_local(board.global_position)
		print("%5d | %6.2f %5.2f | %5.1f | %5.2f %5.2f | %.2f" % [frame, p.x, p.z,
			board.rotation_degrees.y, board.linear_velocity.x, board.linear_velocity.z,
			float(deck.get_node("LandingDeckBottom").get("current_speed"))])
	quit()
