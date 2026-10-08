extends SceneTree

## Tool: loads the mill, follows the first cut board and saves screenshots from set camera angles.
## Needs a window (do NOT use --headless). Images go to dev/captures/ (git-ignored).
## Run: godot --path . --script res://dev/tools/capture_views.gd -- <frame,frame,...>
## Default frames: 560,640,700,760,840,1000

const OUT_DIR := "res://dev/captures"

var _frames: Array[int] = [560, 640, 700, 760, 840, 1000]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_frames.clear()
		for token: String in args[0].split(","):
			_frames.append(int(token))
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	var boards: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("cut_boards"))
	var board: RigidBody3D = boards[0]

	var cam := Camera3D.new()
	cam.current = true
	cam.far = 200.0
	mill.add_child(cam)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var last: int = _frames.max()
	for frame in range(last + 1):
		await physics_frame
		if frame in _frames:
			var at: Vector3 = board.global_position
			# Top-down view follows the board (shows yaw); side view shows how it sits.
			await _shoot(cam, at + Vector3(0.0, 6.0, 0.01), at, "f%04d_top" % frame)
			await _shoot(cam, at + Vector3(-3.0, 2.5, -4.5), at, "f%04d_side" % frame)
			# Close-up of the board's +X end (the end furthest along the feed direction).
			var nose: Vector3 = at + board.global_basis.z * float(board.product_length) * 0.5
			await _shoot(cam, nose + Vector3(-1.5, 1.5, 1.5), nose, "f%04d_nose" % frame)
			var tail: Vector3 = at - board.global_basis.z * float(board.product_length) * 0.5
			await _shoot(cam, tail + Vector3(1.5, 1.5, 1.5), tail, "f%04d_tail" % frame)
	print("CAPTURE DONE ", _frames)
	quit()


func _shoot(cam: Camera3D, from: Vector3, look_at_point: Vector3, label: String) -> void:
	cam.global_position = from
	cam.look_at(look_at_point, Vector3.UP)
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + label + ".png"))
