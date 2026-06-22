extends SceneTree

func _init():
	var file = FileAccess.open("debug_trough_conveyor.log", FileAccess.WRITE)
	file.store_line("=== TESTING CHAIN TROUGH CONVEYOR ===")
	
	var scene = load("res://scenes/chain_trough_conveyor.tscn")
	if not scene:
		file.store_line("Failed to load res://scenes/chain_trough_conveyor.tscn")
		quit(1)
		return
		
	var inst = scene.instantiate()
	root.add_child(inst)
	
	# Wait a frame to let Godot run the _ready lifecycle method and build visuals
	await create_timer(0.016).timeout
	
	file.store_line("Conveyor instanced successfully.")
	file.store_line("Length: " + str(inst.conveyor_length))
	file.store_line("Width: " + str(inst.conveyor_width))
	
	# Verify visual nodes were built
	var visuals = inst.get_node_or_null("Visuals")
	if not visuals:
		file.store_line("Error: Visuals node not found!")
		quit(1)
		return
		
	var trough_bed = visuals.get_node_or_null("TroughBed")
	var kicker_shaft = inst.get_node_or_null("KickerShaft")
	
	if trough_bed:
		file.store_line("TroughBed geometry is generated.")
		var left_slope = trough_bed.get_node_or_null("LeftSlope")
		var left_wall = inst.get_node_or_null("LeftWall")
		if left_slope and left_wall:
			file.store_line("Original Left Slope X size: %.3f, position X: %.3f" % [left_slope.size.x, left_slope.position.x])
			file.store_line("Original Left Wall position X: %.3f" % [left_wall.position.x])
	
	# Move LeftWall closer (to X = -0.39)
	file.store_line("\n--- Moving Left Wall to X = -0.39m ---")
	var left_wall_node = inst.get_node_or_null("LeftWall")
	if left_wall_node:
		left_wall_node.position.x = -0.39
	inst._rebuild_everything()
	
	# Fetch fresh references since rebuilding recreates the Visuals hierarchy
	var new_visuals = inst.get_node_or_null("Visuals")
	var new_trough_bed = new_visuals.get_node_or_null("TroughBed") if new_visuals else null
	
	if new_trough_bed:
		var left_slope = new_trough_bed.get_node_or_null("LeftSlope")
		var left_wall = inst.get_node_or_null("LeftWall")
		var col_left_wall = inst.get_node_or_null("CollisionLeftWall")
		if left_slope and left_wall:
			file.store_line("New Left Slope X size: %.3f, position X: %.3f" % [left_slope.size.x, left_slope.position.x])
			file.store_line("New Left Wall position X: %.3f" % [left_wall.position.x])
		if col_left_wall:
			file.store_line("New Left Wall Collision position X: %.3f" % [col_left_wall.position.x])
			
	file.store_line("Simulation completed.")
	file.close()
	quit(0)
