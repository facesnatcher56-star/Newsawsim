extends SceneTree

## Probe: counts what each top-level machine in the mill contains (physics bodies, moving bodies,
## collision shapes, meshes, CSG shapes, chain-link instances, lights) so heavy machines stand out.
## Run: godot --headless --path . --script res://dev/probes/mill_inventory_probe.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	for i in 60:
		await physics_frame
	print("machine | bodies static/animatable/rigid | shapes | meshes | CSG | multimesh instances | lights | scripts running _process/_physics")
	var rows := []
	for child in mill.get_children():
		var static_n := 0
		var anim_n := 0
		var rigid_n := 0
		var shapes := 0
		var meshes := 0
		var csg := 0
		var mm := 0
		var lights := 0
		var procs := 0
		var phys := 0
		var all: Array = child.find_children("*", "", true, false)
		all.append(child)
		for n in all:
			if n is AnimatableBody3D:
				anim_n += 1
			elif n is StaticBody3D:
				static_n += 1
			elif n is RigidBody3D:
				rigid_n += 1
			if n is CollisionShape3D and not (n as CollisionShape3D).disabled:
				shapes += 1
			if n is MeshInstance3D:
				meshes += 1
			if n is CSGShape3D:
				csg += 1
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
				mm += (n as MultiMeshInstance3D).multimesh.instance_count
			if n is Light3D:
				lights += 1
			if n.get_script() != null:
				if n.is_processing():
					procs += 1
				if n.is_physics_processing():
					phys += 1
		rows.append([child.name, static_n, anim_n, rigid_n, shapes, meshes, csg, mm, lights, procs, phys])
	rows.sort_custom(func(a, b): return (a[2] * 20 + a[6] * 5 + a[7] * 0.01 + a[5] * 0.2) > (b[2] * 20 + b[6] * 5 + b[7] * 0.01 + b[5] * 0.2))
	for r in rows:
		print("%-22s | %4d / %4d / %3d | %5d | %5d | %4d | %6d | %2d | %d/%d" % [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]])
	quit()
