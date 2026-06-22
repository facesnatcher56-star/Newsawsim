extends SceneTree

func _init():
	var file = FileAccess.open("debug_stops.log", FileAccess.WRITE)
	var scene = load("res://debark.tscn")
	if not scene:
		file.store_line("Failed to load res://debark.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	root.add_child(inst)
	
	file.store_line("=== SIMULATING RETRACTABLE STOPS ===")
	
	var stops1 = inst.get_node_or_null("LogFeedStation/DebarkDeckTest/RetractableStops")
	if not stops1:
		file.store_line("Stops not found!")
		quit(1)
		return
		
	# Let's run the simulation for 300 physics frames (5 seconds at 60fps)
	for frame in range(600):
		# Force physics process to tick
		await create_timer(0.016).timeout
		
		# Log every 10 frames or on state change
		var state_names = ["EXTENDED", "HOLDING_LOG", "RETRACTING", "RETRACTED", "SETTLING", "EXTENDING"]
		var current_state = stops1.get("_state")
		var state_str = state_names[current_state] if current_state < state_names.size() else str(current_state)
		
		var dumping_logs = stops1.get("_dumping_logs") as Array
		var deck_logs = stops1.get("_deck_logs") as Array
		var timer = stops1.get("_timer")
		
		var dump_target = stops1.get("_dump_target")
		var target_speed = dump_target.speed if dump_target else -1.0
		
		file.store_line("Frame %d: State=%s, Timer=%.3f, Dumping=%d, Deck=%d, InfeedSpeed=%.2f" % [
			frame, state_str, timer, dumping_logs.size(), deck_logs.size(), target_speed
		])
		
		if dump_target:
			var infeed_area = dump_target.get_node_or_null("LogArea") as Area3D
			if infeed_area:
				var bodies = infeed_area.get_overlapping_bodies()
				file.store_line("  Infeed bodies: " + str(bodies.size()))
				for b in bodies:
					file.store_line("    " + b.name + " pos: " + str(b.global_position))
					
		# Check WasteConveyor2
		var debarker_station = dump_target.get_parent() if dump_target else null
		if debarker_station:
			var lock_zone = debarker_station.get_node_or_null("DebarkerLockZone") as Area3D
			if lock_zone:
				file.store_line("  LockZone bodies: " + str(lock_zone.get_overlapping_bodies().size()))
			var conveyor2 = debarker_station.get_node_or_null("WasteConveyor2")
			if conveyor2:
				var conveyor2_area = conveyor2.get_node_or_null("LogArea") as Area3D
				if conveyor2_area:
					file.store_line("  Conveyor2 bodies: " + str(conveyor2_area.get_overlapping_bodies().size()))
					
	file.close()
	quit(0)
