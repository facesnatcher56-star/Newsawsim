extends SceneTree

func _init():
	var file = FileAccess.open("debug_waste_kicker.log", FileAccess.WRITE)
	file.store_line("=== TESTING WASTE CONVEYOR KICKER ===")
	
	var scene = load("res://scenes/waste_conveyor_kicker.tscn")
	if not scene:
		file.store_line("Failed to load res://scenes/waste_conveyor_kicker.tscn")
		quit(1)
		return
		
	var inst = scene.instantiate()
	root.add_child(inst)
	
	await create_timer(0.016).timeout
	
	file.store_line("Conveyor instanced successfully.")
	
	# Verify kicker shaft and children exist
	var kicker_shaft = inst.get_node_or_null("KickerShaft")
	if kicker_shaft:
		file.store_line("KickerShaft node is present.")
		var arm_pivot = kicker_shaft.get_node_or_null("ArmPivot_0")
		if arm_pivot:
			file.store_line("ArmPivot_0 is present.")
			var upper_arm = arm_pivot.get_node_or_null("UpperArmBody_0")
			if upper_arm:
				file.store_line("UpperArmBody_0 is present.")
	else:
		file.store_line("Error: KickerShaft not found!")
		quit(1)
		return
		
	# Verify rollers exist
	var rail_left = inst.get_node_or_null("Visuals/RailLeft")
	if rail_left:
		file.store_line("RailLeft node is present.")
		for i in range(3):
			var roller = rail_left.get_node_or_null("Roller_%d" % i)
			if roller:
				file.store_line("Roller_%d is present. Position: %s, Radius: %f, Height: %f" % [
					i, str(roller.position), roller.radius, roller.height
				])
			else:
				file.store_line("Error: Roller_%d not found in RailLeft!" % i)
				file.close()
				quit(1)
				return
	else:
		file.store_line("Error: Visuals/RailLeft not found!")
		file.close()
		quit(1)
		return
		
	var kicker_zone = inst.get_node_or_null("KickerZone")
	if kicker_zone:
		file.store_line("KickerZone is present.")
	else:
		file.store_line("Error: KickerZone not found!")
		quit(1)
		return

	# Trigger a kick cycle
	file.store_line("\n--- Triggering Kick Cycle ---")
	inst.kick()
	
	for frame in range(120):
		await create_timer(0.016).timeout
		var state_names = ["IDLE", "KICKING", "HOLDING", "RETRACTING"]
		var current_state = inst.get("_state")
		var state_str = state_names[current_state] if current_state < state_names.size() else str(current_state)
		var shaft_angle = inst.get("_shaft_angle")
		
		if frame % 10 == 0 or frame == 119:
			file.store_line("Frame %d: State=%s, ShaftAngle=%.1f" % [
				frame, state_str, shaft_angle
			])
			
	file.store_line("Simulation completed.")
	file.close()
	quit(0)
