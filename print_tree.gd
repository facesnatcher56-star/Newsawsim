extends SceneTree

func _init():
	var file = FileAccess.open("inspect_tree.log", FileAccess.WRITE)
	var scene = load("res://debark.tscn")
	if not scene:
		file.store_line("Failed to load res://debark.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	root.add_child(inst)
	
	# Wait for 1 frame to let positions update
	await create_timer(0.1).timeout
	
	file.store_line("=== RUNTIME SCENE TREE INSPECTION ===")
	_dump_node(inst, file, 0)
	file.close()
	quit(0)

func _dump_node(node: Node, file: FileAccess, depth: int):
	var indent = ""
	for i in depth:
		indent += "  "
	
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		line += " | pos: " + str(node.global_position) + " | rot: " + str(node.global_rotation_degrees)
	if node.get_script():
		line += " | script: " + node.get_script().get_path().get_file()
		# dump script properties
		for prop in node.get_script().get_script_property_list():
			if prop.usage & PROPERTY_USAGE_EDITOR:
				line += " | " + prop.name + "=" + str(node.get(prop.name))
				
	file.store_line(line)
	for child in node.get_children():
		_dump_node(child, file, depth + 1)
