extends SceneTree

## Probe: follows the first board while the edger take-away deck carries it, printing where it is,
## plus how many lug bodies and shapes the deck built.
## Run: godot --headless --path . --script res://dev/probes/takeaway_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var deck = mill.get_node("EdgerTakeAway")
	var board: RigidBody3D = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))[0]
	print("lug bodies: %d, shapes on lug 0: %d" % [deck._lugs_nodes.size(), deck._lugs_nodes[0].find_children("*", "CollisionShape3D", true, false).size()])
	print("frame | board z (world) | x | chain speed")
	for frame in 700:
		await physics_frame
		if frame % 50 == 0:
			print("%5d | %6.2f | %6.2f | %.2f" % [frame, board.global_position.z, board.global_position.x, deck._current_chain_speed])
	quit()
