extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "smoke"
	print("[HEADLESS DIAGNOSTIC] mode=", mode)
	if mode == "debark_play":
		call_deferred("_run_debark_play")
		return
	if mode == "carriage_stop":
		call_deferred("_run_carriage_stop")
		return

	match mode:
		"smoke":
			print("[HEADLESS DIAGNOSTIC] basic SceneTree startup passed")
		"log":
			_test_resource("res://Prefabs/ProceduralLogNoBark.tscn", false)
		"log_prefab":
			_test_resource("res://Prefabs/LogPrefab.tscn", false)
		"headrig":
			_test_resource("res://scenes/headrig_rail_system.tscn", false)
		"headrig_tree":
			_test_resource("res://scenes/headrig_rail_system.tscn", true)
		"debark_load":
			_test_load("res://debark.tscn")
		"debark":
			_test_resource("res://debark.tscn", false)
		_:
			push_error("Unknown diagnostic mode: %s" % mode)

	quit()

func _run_carriage_stop() -> void:
	var packed := load("res://debark.tscn") as PackedScene
	assert(packed != null, "Could not load debark scene")
	var scene := packed.instantiate()
	root.add_child(scene)

	var log := scene.get_node("ProceduralLogNoBark") as RigidBody3D
	var carriage := scene.get_node("HeadrigRailSystemInstance/HeadrigCarriage")
	var knees := carriage.get_node("KneesAssembly") as Node3D
	var stop_body := knees.get_node("HeadblockStopBody") as AnimatableBody3D
	var platform := carriage.get_node("CollisionPlatform") as CollisionShape3D
	carriage.set_process(false)
	carriage.set_physics_process(false)
	log.continuous_cd = true
	var test_material := PhysicsMaterial.new()
	test_material.friction = 0.0
	test_material.bounce = 0.0
	log.physics_material_override = test_material

	await physics_frame
	var platform_shape := platform.shape as BoxShape3D
	var platform_top_y: float = carriage.to_local(platform.global_position).y + platform_shape.size.y * 0.5
	var start_local: Vector3 = Vector3(0.55, platform_top_y + 0.205, 0.0)
	var log_basis := Basis(Vector3.RIGHT, PI / 2.0)
	log.global_transform = carriage.global_transform * Transform3D(log_basis, start_local)
	log.linear_velocity = carriage.global_basis * Vector3(-2.0, 0.0, 0.0)
	log.angular_velocity = Vector3.ZERO
	log.sleeping = false

	print(
		"[CARRIAGE STOP] owners=", stop_body.get_shape_owners(),
		" start_local=", carriage.to_local(log.global_position)
	)
	for frame in range(90):
		await physics_frame
		if frame % 15 == 0:
			print("[CARRIAGE STOP] frame=", frame, " local=", carriage.to_local(log.global_position))

	var final_local: Vector3 = carriage.to_local(log.global_position)
	if final_local.x < 0.31:
		push_error("Log passed through the physical headblock stop")
		quit(1)
		return
	if final_local.x > 0.39:
		push_error("Log stopped before reaching the physical headblocks")
		quit(1)
		return
	print("[HEADLESS DIAGNOSTIC] carriage headblock stop test passed at local=", final_local)
	quit()

func _run_debark_play() -> void:
	var packed := load("res://debark.tscn") as PackedScene
	assert(packed != null, "Could not load debark scene")
	var scene := packed.instantiate()
	root.add_child(scene)
	print("[HEADLESS DIAGNOSTIC] debark scene entered tree")

	var log := scene.get_node("ProceduralLogNoBark") as RigidBody3D
	var incline := scene.get_node("InclineLogDeck")
	var slope := incline.get_node("SlopeRoot") as Node3D
	var carriage := scene.get_node("HeadrigRailSystemInstance/HeadrigCarriage")
	var blade := scene.get_node("Bandsaw/CSGCombiner3D/Blade") as Node3D
	assert(log.get_node_or_null("CollisionShape3D") != null, "Test log has no collision shape")
	print(
		"[HEADLESS PLAY] initial incline-local log=", slope.to_local(log.global_position),
		" slope_origin=", slope.global_position,
		" slope_basis=", slope.global_basis
	)
	print(
		"[HEADLESS PLAY] log collision node=", log.get_node_or_null("CollisionShape3D"),
		" owners=", log.get_shape_owners(),
		" layer=", log.collision_layer,
		" mask=", log.collision_mask
	)

	for frame in range(120):
		await physics_frame
		if frame == 0:
			var ray := PhysicsRayQueryParameters3D.create(
				slope.to_global(Vector3(0.0, 1.0, -0.154)),
				slope.to_global(Vector3(0.0, -1.0, -0.154))
			)
			ray.exclude = [log.get_rid()]
			var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
			print("[HEADLESS PLAY] incline ray hit=", hit)
			assert(not hit.is_empty(), "Incline bed is missing from the physics world")
		if frame == 5:
			incline.set_running(true)
		if frame % 30 == 0:
			print(
				"[HEADLESS PLAY] frame=", frame,
				" log=", log.global_position,
				" incline_local=", slope.to_local(log.global_position),
				" carriage=", carriage.global_position,
				" blade=", blade.global_position,
				" state=", carriage.current_state
			)

	assert(log.global_position.y > -0.5, "Test log fell through the incline deck")
	print("[HEADLESS DIAGNOSTIC] two-second physics run passed")
	quit()

func _test_load(path: String) -> void:
	var packed := load(path) as PackedScene
	assert(packed != null, "Could not load %s" % path)
	print("[HEADLESS DIAGNOSTIC] loaded ", path)

func _test_resource(path: String, add_to_tree: bool) -> void:
	var packed := load(path) as PackedScene
	assert(packed != null, "Could not load %s" % path)
	var state := packed.get_state()
	print("[HEADLESS DIAGNOSTIC] packed node count=", state.get_node_count())
	var instance := packed.instantiate()
	assert(instance != null, "Could not instantiate %s" % path)
	print("[HEADLESS DIAGNOSTIC] root children=", instance.get_children())
	if add_to_tree:
		root.add_child(instance)
		print("[HEADLESS DIAGNOSTIC] instantiated and added ", path)
	else:
		print("[HEADLESS DIAGNOSTIC] instantiated ", path)
	instance.free()
