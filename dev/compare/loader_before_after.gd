extends Node3D

## Renders the old box-model knuckleboom loader next to the new Blender one at the same
## scale, labelled BEFORE and AFTER, and saves dev/compare/loader_before_after.png.
## Run: godot --path . res://dev/compare/loader_before_after.tscn

const OLD_SCENE := preload("res://dev/compare/old_knuckle_boom_loader.tscn")
const NEW_SCENE := preload("res://game/machines/log_feed/knuckle_boom_loader.tscn")
const LOG_SCENE := preload("res://game/lumber/log.tscn")
const OUT := "res://dev/compare/loader_before_after.png"
const SIZE := Vector2i(1920, 1080)

var _view: SubViewport
var _frames: int = 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 40.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.40, 0.38, 0.35)
	fm.roughness = 0.95
	plane.material = fm
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	# Old loader: its own scene sets the pose in _ready; keep it from spawning logs.
	var old := OLD_SCENE.instantiate()
	old.set("enabled", false)
	old.position = Vector3(-4.5, 0.0, 0.0)
	add_child(old)
	var smoke := old.find_child("ExhaustSmoke", true, false) as CPUParticles3D
	if smoke:
		smoke.emitting = false
	# New loader parked with the boom up, as it waits between cycles.
	var new := NEW_SCENE.instantiate()
	new.position = Vector3(4.0, 0.0, 0.0)
	add_child(new)

	# A 16 ft mill log in front of each for scale.
	for x in [-4.5, 4.0]:
		var log_body := LOG_SCENE.instantiate() as RigidBody3D
		log_body.freeze = true
		add_child(log_body)
		log_body.position = Vector3(x + 1.0, 0.3, 3.0)

	for item in [["BEFORE", Vector3(-4.5, 6.6, 0.0)], ["AFTER", Vector3(5.5, 7.8, 0.0)]]:
		var label := Label3D.new()
		label.text = item[0]
		label.font_size = 160
		label.outline_size = 24
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = item[1]
		add_child(label)

	_view = SubViewport.new()
	_view.size = SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = Viewport.MSAA_4X
	add_child(_view)
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.position = Vector3(1.0, 4.2, 15.5)
	_view.add_child(cam)
	cam.look_at(Vector3(1.0, 3.2, 0.0))
	cam.current = true
	var screen_cam := Camera3D.new()
	screen_cam.fov = 45.0
	screen_cam.position = cam.position
	add_child(screen_cam)
	screen_cam.look_at(Vector3(1.0, 3.2, 0.0))
	screen_cam.current = true

	var caption := Label.new()
	caption.text = "Knuckleboom log loader - old box model (left) vs new Weiler K261-class model (right), same scale"
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(40, 30)
	_view.add_child(caption)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		var img := _view.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[loader_before_after] saved %s" % OUT)
