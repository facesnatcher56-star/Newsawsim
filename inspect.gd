extends SceneTree

func _init():
	var file = FileAccess.open("inspect.log", FileAccess.WRITE)
	var scene = load("res://debark.tscn")
	if not scene:
		file.store_line("Failed to load res://debark.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	var rail_system = inst.get_node_or_null("HeadrigRailSystemInstance")
	var carriage = inst.get_node_or_null("HeadrigRailSystemInstance/HeadrigCarriage")
	var incline = inst.get_node_or_null("InclinePart1")
	
	if not rail_system:
		file.store_line("Rail system not found")
	elif not carriage:
		file.store_line("Carriage not found")
	else:
		var carriage_global_transform = rail_system.transform * carriage.transform
		file.store_line("Carriage Global Position: " + str(carriage_global_transform.origin))
		file.store_line("Carriage Global Basis: ")
		file.store_line("  X: " + str(carriage_global_transform.basis.x))
		file.store_line("  Y: " + str(carriage_global_transform.basis.y))
		file.store_line("  Z: " + str(carriage_global_transform.basis.z))
		
		var knees = carriage.get_node_or_null("KneesAssembly")
		if not knees:
			file.store_line("KneesAssembly not found")
		else:
			file.store_line("Carriage KneesAssembly elements (world space):")
			for child in knees.get_children():
				if child is Node3D:
					var child_global_pos = carriage_global_transform * child.position
					file.store_line("  " + child.name + " -> local: " + str(child.position) + " | world: " + str(child_global_pos))
					
	if not incline:
		file.store_line("Incline not found")
	else:
		file.store_line("Incline Global Position: " + str(incline.transform.origin))
		file.store_line("Incline Global Basis: ")
		file.store_line("  X: " + str(incline.transform.basis.x))
		file.store_line("  Y: " + str(incline.transform.basis.y))
		file.store_line("  Z: " + str(incline.transform.basis.z))
		
	file.close()
	quit(0)
