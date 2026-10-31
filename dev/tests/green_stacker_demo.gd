extends Node3D

## Demo to watch the green stacker on its own: drops sorter-style packs (a single stack of
## boards, one board wide) onto the surge chain tail whenever there is room, and shows the
## line from fixed viewpoints. Keys 1-5 switch views, P pauses feeding.
## Run: godot --path . res://dev/tests/green_stacker_demo.tscn

const BOARD_SCENE := preload("res://game/lumber/cut_board.tscn")
const STACKER_SCENE := preload("res://game/machines/stacker/green_stacker.tscn")
const Stacker := preload("res://game/machines/stacker/green_stacker.gd")
const FORKLIFT_SCENE := preload("res://game/machines/forklift/forklift.tscn")
const CrewScript := preload("res://game/machines/stacker/stacker_crew.gd")

## Pack sizes to feed, in turn (each pack is one size).
@export var sizes: Array[String] = ["2x8"]
## Boards in each pack, like a sorter bay.
@export var pack_boards: int = 10
## Layers per package for the demo (the mill default is 31), so a whole package cycle shows
## in a few minutes.
@export var demo_layers: int = 6

var _stacker: Node3D
var _cam: Camera3D
var _label: Label
var _feeding: bool = true
var _pack_n: int = 0
var _fed: int = 0
var _view: int = 1
## Seconds between saved screenshots (dev/captures/stacker_N.png, each from the next view);
## 0 = off. Run with `-- --snapshots` to turn on.
var _snap_every: float = 0.0
var _snap_timer: float = 4.0
var _snap_n: int = 0
## Started with `-- --view=N`: snapshots stay on that view instead of cycling.
var _fixed_view: bool = false
## Started with `-- --views=9,10,...`: snapshots cycle through only these views.
var _views: Array[int] = []
## Started with `-- --lengths`: packs of mixed lengths (6-16 ft in turn), even-ended at the
## line-up fence end as the sorter sends them, to watch the stacker alternate its ending.
var _lengths: bool = false

const VIEWS: Array = [
	[Vector3(26.0, 7.5, 12.0), Vector3(27.0, 1.5, 0.0)],     # 1 whole line from the +Z side
	[Vector3(19.5, 3.2, 6.5), Vector3(22.5, 0.8, 0.0)],      # 2 surge head, pocket, unscrambler foot
	[Vector3(24.0, 4.6, 5.5), Vector3(26.8, 2.6, -1.0)],     # 3 unscrambler head, line-up rolls
	[Vector3(33.2, 3.3, 3.4), Vector3(29.6, 2.3, 0.3)],      # 4 forks, fence, sticks, hoist (from downstream)
	[Vector3(38.5, 3.2, 6.5), Vector3(33.5, 0.8, 0.0)],      # 5 outfeed and landing deck
	[Vector3(36.0, 9.0, 14.0), Vector3(44.0, 0.8, 3.0)],     # 6 forklift and the yard row
	[Vector3(18.5, 4.6, 10.5), Vector3(25.0, 1.6, 3.5)],     # 7 operator console, stair and catwalk
	[Vector3(28.3, 4.9, -4.6), Vector3(28.1, 2.5, 0.2)],      # 8 forming section and both ending fences, from the -Z side
	[Vector3(28.25, 8.5, 0.01), Vector3(28.25, 2.6, 0.0)],    # 9 forming section from straight above
	[Vector3(29.85, 6.5, 0.01), Vector3(29.85, 2.4, 0.0)],     # 10 package on the hoist from straight above
	[Vector3(37.6, 1.5, 5.4), Vector3(35.6, 0.75, 2.4)],      # 11 landed package, far (+Z) end face
	[Vector3(37.6, 1.5, -5.5), Vector3(35.6, 0.75, -2.5)],    # 12 landed package, near (-Z) end face
	[Vector3(25.95, 4.6, -1.2), Vector3(25.95, 2.6, -1.25)],   # 13 infeed and line-up fence from straight above
]
## Close-up of the fork cycle (used for the cycle burst snapshots).
const CYCLE_VIEW: Array = [Vector3(32.6, 4.4, 2.6), Vector3(29.8, 2.6, 0.0)]   # above and downstream of the hoist
var _burst: int = 0


func _ready() -> void:
	# Test windows never take the mouse or focus from the user.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 30.0)
	shape.shape = box
	shape.position = Vector3(25.0, -0.1, 0.0)
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.42, 0.44)
	fm.roughness = 0.95
	bm.material = fm
	floor_mesh.mesh = bm
	floor_mesh.position = shape.position
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	_stacker = STACKER_SCENE.instantiate() as Node3D
	_stacker.set("package_layers", demo_layers)
	_stacker.set("auto_take_after", 0.0)       # the forklift takes them
	_stacker.set("log_events", true)
	add_child(_stacker)

	var fl := FORKLIFT_SCENE.instantiate()
	fl.set("stacker", NodePath("../GreenStacker"))
	fl.set("log_events", true)
	add_child(fl)
	# At its waiting spot behind the landing deck, forks toward the deck (-X): the truck drives
	# along its own +Z.
	fl.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(43.0, 0.02, 0.0))

	var crew := CrewScript.new()
	crew.name = "StackerCrew"
	crew.set("stacker", NodePath("../GreenStacker"))
	crew.set("log_events", true)
	add_child(crew)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	_set_view(1)
	if "--mixed" in OS.get_cmdline_user_args():
		sizes = ["2x8", "2x6"]      # packs that aren't whole layers, changing size: short layers for the crew
	if "--snapshots" in OS.get_cmdline_user_args():
		_snap_every = 5.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--layers="):
			_stacker.set("package_layers", maxi(arg.trim_prefix("--layers=").to_int(), 1))
		if arg.begins_with("--views="):
			for v: String in arg.trim_prefix("--views=").split(","):
				_views.append(clampi(v.to_int(), 1, VIEWS.size()))
			_set_view(_views[0])
		if arg.begins_with("--snap-every="):
			_snap_every = arg.trim_prefix("--snap-every=").to_float()
		if arg == "--lengths":
			_lengths = true
			pack_boards = 7
		if arg.begins_with("--view="):
			_set_view(clampi(arg.trim_prefix("--view=").to_int(), 1, VIEWS.size()))
			_fixed_view = true

	var ui := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	ui.add_child(_label)
	add_child(ui)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_set_view(key.keycode - KEY_0)
	elif key.keycode == KEY_P:
		_feeding = not _feeding


func _set_view(v: int) -> void:
	_view = v
	var pair: Array = VIEWS[v - 1]
	_cam.position = pair[0]
	_cam.look_at(pair[1], Vector3.UP)


func _physics_process(delta: float) -> void:
	if _feeding and _tail_clear():
		_feed_pack()
	if _snap_every > 0.0:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = _snap_every
			_snap_n += 1
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev/captures"))
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://dev/captures/stacker_%d_v%d.png" % [_snap_n, _view]))
			if not _views.is_empty():
				_set_view(_views[(_views.find(_view) + 1) % _views.size()])
			elif not _fixed_view:
				_set_view(_view % VIEWS.size() + 1)
		# Burst of close-ups through the second fork cycle.
		var phase: int = int(_stacker.get("_phase"))
		var layers: int = int(_stacker.get("_pkg_layers"))
		if not _fixed_view and layers == 1 and phase != 0 and _burst < 40 and fmod(_snap_timer, 0.4) < delta:
			_burst += 1
			var keep: Transform3D = _cam.global_transform
			_cam.position = CYCLE_VIEW[0]
			_cam.look_at(CYCLE_VIEW[1], Vector3.UP)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://dev/captures/cycle_%02d_p%d.png" % [_burst, phase]))
			_cam.global_transform = keep
	_label.text = "Green stacker demo   view %d (keys 1-7)   feeding %s (P)\npacks fed %d, boards %d   layer %d/%d of %s   packages out %d" % [
		_view, "on" if _feeding else "off", _pack_n, _fed, int(_stacker.get("_pkg_layers")), int(_stacker.get("package_layers")),
		_pkg_size(), int(_stacker.call("packages_done"))]


func _pkg_size() -> String:
	var s: String = str(_stacker.get("_pkg_size"))
	return s if s != "" else "-"


## Room at the surge tail for another pack, and no more than a few packs waiting ahead of
## the stacker (the sorter only sends a pack as a bay fills).
func _tail_clear() -> bool:
	var waiting: int = 0
	for b: RigidBody3D in _stacker.get("_boards"):
		if is_instance_valid(b):
			var p: Vector3 = _stacker.to_local(b.global_position)
			# A board on the surge chains near the tail (one that fell to the floor doesn't count).
			if p.y > Stacker.SURGE_TOP - 0.05 and p.y < 1.5 and p.x < Stacker.SURGE_TAIL + 1.0 and absf(p.z) < 2.6:
				return false
			if p.x < Stacker.UNS_HEAD.x and p.y > 0.15:
				waiting += 1
	return waiting < 4 * pack_boards


func _feed_pack() -> void:
	var size: String = sizes[_pack_n % sizes.size()]
	_pack_n += 1
	var spec: Dictionary = BOARD_SCENE.instantiate().get_script().LUMBER_SPECS.get(size, {"thickness": 0.038, "width": 0.184})
	var t: float = float(spec["thickness"])
	for i in pack_boards:
		var board := BOARD_SCENE.instantiate() as RigidBody3D
		board.set("nominal_size", size)
		board.name = "Board_%d" % _fed
		var z: float = randf_range(-0.04, 0.04)
		if _lengths:
			var feet: int = 6 + 2 * (_fed % 6)
			board.call("configure_dimensions", feet * 0.3048, t, float(spec["width"]))
			z = Stacker.LINEUP_FENCE_Z + 0.04 + feet * 0.3048 * 0.5
		_fed += 1
		add_child(board)
		var p := Vector3(Stacker.SURGE_TAIL + 0.4, Stacker.SURGE_TOP + t * (float(i) + 0.5) + 0.002 * i, z)
		board.global_transform = _stacker.global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), p)
		# Already moving with the surge chains, as a pack coming off the haul-out would be.
		board.linear_velocity = _stacker.global_basis.x * float(_stacker.get("surge_speed"))
		_stacker.call("receive", board)
