extends SceneTree

## Tool: sends two boards through the bin sorter on its own and saves close-up screenshots of the
## bay they land in (dev/captures/). Needs a window (not --headless).
## Run: godot --path . --script res://dev/tools/capture_sorter_bay.gd

const SORTER_SCENE := "res://game/machines/sorter/bin_sorter.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"
const OUT_DIR := "res://dev/captures"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var sorter: BinSorter = load(SORTER_SCENE).instantiate()
	sorter.random_bay_sorting = false
	world.add_child(sorter)
	for i in 4:
		await physics_frame
	var cam := Camera3D.new()
	cam.current = true
	world.add_child(cam)
	var target := -1
	for n in 2:
		var board: RigidBody3D = load(BOARD_SCENE).instantiate()
		board.nominal_size = "1x8"
		board.length_feet = 8
		board.rotation.y = PI * 0.5
		world.add_child(board)
		board.global_position = sorter.to_global(Vector3(-0.35, sorter.sorter_height + board.board_thickness * 0.5 + 0.01, 0.0))
		await physics_frame
		sorter._on_infeed_body_entered(board)
		target = SorterBoardTracker.get_board_sorting_grade(board, sorter.num_bins)
		for f in 700:
			await physics_frame
			if sorter._bay_board_counts[target] >= n + 1:
				break
		for f in 120:
			await physics_frame
	var bay_x: float = float(target) * sorter.bin_width + 0.5
	var shots := {
		"side": Vector3(bay_x, 3.4, 7.0),
		"front": Vector3(bay_x + 4.0, 4.2, 1.5),
		"top": Vector3(bay_x, 9.0, 0.1),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for label: String in shots:
		cam.global_position = sorter.to_global(shots[label])
		cam.look_at(sorter.to_global(Vector3(bay_x, 3.5, 0.0)), Vector3.UP)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/bay_" + label + ".png"))
	print("CAPTURE DONE bay ", target)
	quit()
