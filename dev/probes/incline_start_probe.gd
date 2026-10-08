extends SceneTree

## Probe: prints the incline chain speed and the board's position along the deck until the board
## reaches the incline start zone, to confirm the incline stays still until then.
## Run: godot --headless --path . --script res://dev/probes/incline_start_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var deck: Node3D = mill.get_node("landing_deck_frame")
	var board: RigidBody3D = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))[0]
	print("frame | board deck z | incline chain speed | started")
	for frame in 1300:
		await physics_frame
		if frame % 100 == 0 or (frame > 800 and frame % 20 == 0 and frame < 1100):
			print("%5d | %6.2f | %.2f | %s" % [frame, deck.to_local(board.global_position).z, incline.actual_speed, incline._board_has_arrived])
	quit()
