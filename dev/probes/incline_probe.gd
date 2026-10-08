extends SceneTree

## Probe: follows the first board from the landing deck up the incline and prints where it is
## (incline-local z = along the ramp, y = height) so you can see whether the lugs carry it up.
## Run: godot --headless --path . --script res://dev/probes/incline_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var board: RigidBody3D = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))[0]
	var lugs: Array = incline.find_children("LugStation_*", "AnimatableBody3D", true, false)
	print("lug stations: %d, shapes per station: %d" % [lugs.size(), (lugs[0] as Node).get_child_count()])
	print("frame | incline z    y   | yaw  | vel z")
	for frame in 2600:
		await physics_frame
		if frame < 900 or frame % 100 != 0:
			continue
		var p: Vector3 = incline.to_local(board.global_position)
		print("%5d | %6.2f %5.2f | %5.1f | %5.2f" % [frame, p.z, p.y, board.rotation_degrees.y, board.linear_velocity.z])
	quit()
