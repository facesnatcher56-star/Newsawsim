extends SceneTree

## Probe: lists where the grip rollers and trough sit in the debarker, then follows any log through
## the mill and prints its position, speed and what it touches around the debarker.
## Run: godot --headless --path . --script res://dev/probes/log_debarker_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var station: Node3D = mill.get_node("DebarkerStation")
	for n in ["DebarkInfeedConveyor", "GripRoller1", "GripRoller2", "GripRoller3", "GripRoller4", "DebarkerLockZone", "Stop"]:
		var node: Node3D = station.get_node(n)
		var extra := ""
		if node is CollisionObject3D:
			for c in node.find_children("*", "CollisionShape3D", false, false):
				var shape: Shape3D = (c as CollisionShape3D).shape
				extra += " [%s at %s]" % [shape.get_class(), (c as Node3D).global_position]
		print("DEBARKER ", n, " world=", node.global_position, extra)
	var seen := {}
	for frame in 5400:
		await physics_frame
		for node in get_nodes_in_group("logs"):
			var log_body := node as RigidBody3D
			if log_body == null or log_body.freeze:
				continue
			var id: int = log_body.get_instance_id()
			var near: bool = log_body.global_position.distance_to(station.global_position) < 14.0
			if near and frame % 30 == 0:
				var touching := []
				if log_body.contact_monitor:
					for c in log_body.get_colliding_bodies():
						touching.append(String(c.get_parent().name) + "/" + String(c.name))
				print("f=%d log pos=%s vel=%s contacts=%s" % [frame, log_body.global_position, log_body.linear_velocity, touching])
			seen[id] = true
	print("logs seen: ", seen.size())
	quit()
