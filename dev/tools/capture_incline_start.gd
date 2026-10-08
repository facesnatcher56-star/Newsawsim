extends SceneTree

## Tool: fixed camera on the incline foot. Saves a shot while the incline is paused and shots just after
## it starts, to check the chains do not jump. Needs a window (not --headless). Images go to dev/captures/.
## Run: godot --path . --script res://dev/tools/capture_incline_start.gd

const OUT_DIR := "res://dev/captures"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var incline: Node3D = mill.get_node("BoardLugIncline")
	var cam := Camera3D.new()
	cam.current = true
	cam.far = 200.0
	mill.add_child(cam)
	cam.global_position = incline.to_global(Vector3(3.2, 2.2, 0.5))
	cam.look_at(incline.to_global(Vector3(-0.5, 0.2, 0.2)), Vector3.UP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for i in 30:
		await physics_frame
	await _shot("incline_paused")
	incline._board_has_arrived = true
	for i in 3:
		await physics_frame
	await _shot("incline_started_3")
	for i in 20:
		await physics_frame
	await _shot("incline_started_23")
	print("CAPTURE DONE incline start")
	quit()


func _shot(label: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + label + ".png"))
