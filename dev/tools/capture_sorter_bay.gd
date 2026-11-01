extends SceneTree

## Tool: runs the bin sorter on its own, feeds it 2x8s (bay 7) and saves screenshots to
## dev/captures/: the whole machine, a board dropping through its gate, the stack on bay 7's
## forks, and a hauled-out stack on the end table. Needs a window (not --headless).
## Run: godot --path . --fixed-fps 60 --script res://dev/tools/capture_sorter_bay.gd [-- --size=2x4 --count=8]

const SORTER_SCENE := "res://game/machines/sorter/bin_sorter.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"
const OUT_DIR := "res://dev/captures"

var _world: Node3D
var _sorter: BinSorter
var _cam: Camera3D
var _size := "2x8"
var _count := 3


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			_size = arg.substr(7)
		if arg.begins_with("--count="):
			_count = int(arg.substr(8))
	var BAY: int = BinSorter.PROFILES.find(_size)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 30)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(6, 0, 0)
	floor_body.add_child(floor_mesh)
	_world.add_child(floor_body)
	_sorter = load(SORTER_SCENE).instantiate()
	_sorter.max_boards_per_bay = _count
	_world.add_child(_sorter)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 55
	_world.add_child(_cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	await _shot("overview", Vector3(-3.5, 7.5, 10.5), Vector3(6.5, 2.5, 0.0))
	var bx: float = BinSorter.bay_x(BAY)
	var dropped := false
	for n in _count + 1:
		_feed()
		for f in 900:
			await physics_frame
			if not dropped and _sorter._bays[BAY].gate_deg > 30.0:
				dropped = true
				await _shot("drop", Vector3(bx + 0.45, 4.75, 3.0), Vector3(bx + 0.6, 3.9, 0.0))
			if _sorter._bays[BAY].count >= mini(n + 1, _count) and not _sorter.feed_hold:
				break
		if n == _count - 1:
			await _settle(60)
			await _shot("bay", Vector3(bx + 0.5, 3.55, 3.3), Vector3(bx + 0.6, 3.0, 0.0))
	for f in 2400:
		await physics_frame
		if not _sorter._lift_load.is_empty() and _sorter._hauled.is_empty():
			break
	await _settle(30)
	await _shot("endtable", Vector3(13.4, 1.5, 3.6), Vector3(14.8, 0.45, 0.0))
	for b: Node in get_nodes_in_group("cut_boards"):
		var p: Vector3 = _sorter.to_local((b as Node3D).global_position)
		print("board at sorter-local (%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])
	print("CAPTURE DONE")
	quit()


func _feed() -> void:
	var board: RigidBody3D = load(BOARD_SCENE).instantiate()
	board.nominal_size = _size
	board.rotation.y = PI * 0.5
	_world.add_child(board)
	board.position = Vector3(-0.35, BinSorter.DECK_Y + board.board_thickness * 0.5 + 0.005, 0.0)


func _settle(frames: int) -> void:
	for f in frames:
		await physics_frame


func _shot(label: String, from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/sorter_" + label + ".png"))
	print("saved ", label)
