extends SceneTree

## Tool: rebuilds res://game/machines/sorter/bin_sorter.tscn from BinSorter's layout constants:
## the frame model plus the saved static collision (deck rails, rolls, haul chains, end stops,
## infeed zone). Rerun after re-exporting the sorter from Blender or changing a constant.
## Run: godot --headless --path . --script res://dev/tools/build_bin_sorter_scene.gd

const SCENE_PATH := "res://game/machines/sorter/bin_sorter.tscn"
## The level instances the sorter by this uid; a freshly packed scene would get a new one.
const SCENE_UID := "uid://c63j5eq6tw5ta"


func _init() -> void:
	var root := Node3D.new()
	root.name = "BinSorter"
	root.set_script(load("res://game/machines/sorter/bin_sorter.gd"))
	var model: Node3D = BinSorter.FrameScene.instantiate()
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	BinSorter.build_static_colliders(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE_PATH)
	if err == OK:
		var text := FileAccess.get_file_as_string(SCENE_PATH)
		var header_end := text.find("]")
		var header := text.substr(0, header_end)
		if not header.contains("uid="):
			text = header + " uid=\"%s\"" % SCENE_UID + text.substr(header_end)
			var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
			file.store_string(text)
			file.close()
	print("BUILD ", SCENE_PATH, " -> ", error_string(err))
	root.free()
	quit()
