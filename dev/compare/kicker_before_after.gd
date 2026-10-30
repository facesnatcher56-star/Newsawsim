extends Node3D

## Close three-quarter view of the old belt kicker conveyor and its box stop beside the new
## log trough, flip kicker and cushioned end stop, same camera and scale, labelled BEFORE
## and AFTER, saved to dev/compare/kicker_before_after.png. Each has a log at the stop and
## the incline foot it kicks onto.
## Run: godot --path . res://dev/compare/kicker_before_after.tscn

const OLD_SCENE := preload("res://dev/compare/old_kicker/old_waste_conveyor_kicker.tscn")
const OLD_STOP := preload("res://game/assets/models/Stop.glb")
const NEW_SCENE := preload("res://game/machines/log_kicker/log_kicker.tscn")
const INCLINE_SCENE := preload("res://game/transport/decks/incline_log_deck.tscn")
const LOG_SCENE := preload("res://game/lumber/log.tscn")
const OUT := "res://dev/compare/kicker_before_after.png"
const PANEL := Vector2i(1600, 1200)
## The old kicker sits this far behind the new one so each panel sees only its own.
const OLD_OFFSET := Vector3(0.0, 0.0, -60.0)

var _views: Array[SubViewport] = []
var _frames: int = 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color(0.12, 0.10, 0.08)
	sky_mat.ground_horizon_color = Color(0.36, 0.31, 0.25)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.6, 0.56)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	for z in [0.0, OLD_OFFSET.z]:
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(30.0, 24.0)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.36, 0.35, 0.33)
		plane.material = fm
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(16.0, -1.288, 3.0 + z)
		add_child(floor_mesh)
		# The incline foot both kick onto, where the mill has it.
		var incline := INCLINE_SCENE.instantiate() as Node3D
		incline.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(13.47)), Vector3(16.518, 0.130, 4.093 + z))
		add_child(incline)

	# The old belt conveyor, kicker and box stop where the mill had them.
	var old := OLD_SCENE.instantiate() as Node3D
	old.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1.5, 0, 0)),
		Vector3(16.151764, 0.45677352, 2.118968) + OLD_OFFSET)
	add_child(old)
	var stop := Node3D.new()
	stop.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)),
		Vector3(19.605684, 1.2457577, 2.2462158) + OLD_OFFSET)
	add_child(stop)
	var stop_model := OLD_STOP.instantiate() as Node3D
	stop_model.position = Vector3(0.36242676, 0, -0.054519653)
	stop.add_child(stop_model)
	var fresh := NEW_SCENE.instantiate() as Node3D
	add_child(fresh)

	# A log against each stop.
	_log(Vector3(17.05, 0.849, 2.118) + OLD_OFFSET)
	_log(Vector3(16.90, 0.872, 2.118))

	for panel in [["BEFORE", OLD_OFFSET.z], ["AFTER", 0.0]]:
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		add_child(view)
		# Same three-quarter view on each: from the far side, over the end stop end,
		# looking back along the trough at the kicker and the incline foot.
		var cam := Camera3D.new()
		cam.fov = 50.0
		view.add_child(cam)
		var z: float = panel[1]
		cam.position = Vector3(21.4, 2.9, -1.5 + z)
		cam.look_at(Vector3(16.6, 0.5, 2.6 + z))
		cam.current = true
		var label := Label.new()
		label.text = panel[0]
		label.add_theme_font_size_override("font_size", 64)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 14)
		label.position = Vector2(40, 24)
		view.add_child(label)
		_views.append(view)
	var caption := Label.new()
	caption.text = "Same camera and scale on both: old belt kicker (left) vs log trough, flip kicker and end stop (right)"
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(40, PANEL.y - 54)
	_views[1].add_child(caption)
	var screen_cam := Camera3D.new()
	add_child(screen_cam)
	screen_cam.position = Vector3(21.4, 2.9, -1.5)
	screen_cam.look_at(Vector3(16.6, 0.5, 2.6))
	screen_cam.current = true


func _log(pos: Vector3) -> void:
	var log_body := LOG_SCENE.instantiate() as RigidBody3D
	log_body.freeze = true
	add_child(log_body)
	log_body.global_position = pos


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		var left := _views[0].get_texture().get_image()
		var right := _views[1].get_texture().get_image()
		var img := Image.create(PANEL.x * 2 + 8, PANEL.y, false, left.get_format())
		img.fill(Color.BLACK)
		img.blit_rect(left, Rect2i(Vector2i.ZERO, PANEL), Vector2i.ZERO)
		img.blit_rect(right, Rect2i(Vector2i.ZERO, PANEL), Vector2i(PANEL.x + 8, 0))
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[kicker_before_after] saved %s" % OUT)
