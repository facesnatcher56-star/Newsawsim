extends Node3D

## Close three-quarter view of the old chain log deck beside the new live deck and step
## feeder, same camera and scale, labelled BEFORE and AFTER, saved to
## dev/compare/log_deck_before_after.png. Both sit at the debarker infeed, with logs on.
## Run: godot --path . res://dev/compare/log_deck_before_after.tscn

const OLD_SCENE := preload("res://dev/compare/old_log_deck/old_chain_log_deck.tscn")
const NEW_SCENE := preload("res://game/transport/decks/live_log_deck.tscn")
const DEBARKER_SCENE := preload("res://game/machines/debarker/debarker_station.tscn")
const LOG_SCENE := preload("res://game/lumber/log.tscn")
const OUT := "res://dev/compare/log_deck_before_after.png"
const PANEL := Vector2i(1600, 1200)
## The old deck sits this far behind the new one so each panel sees only its own.
const OLD_OFFSET := Vector3(0.0, 0.0, -60.0)

var _views: Array[SubViewport] = []
var _frames: int = 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# A sky to reflect, so the old deck's metallic paint reads as it does in the mill.
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
		plane.size = Vector2(40.0, 30.0)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.36, 0.35, 0.33)
		plane.material = fm
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(2.0, -1.288, 6.0 + z)
		add_child(floor_mesh)
		# The debarker the deck feeds, the same in both.
		var deb := DEBARKER_SCENE.instantiate() as Node3D
		deb.position = Vector3(0.0, 0.0, z)
		add_child(deb)
		deb.set("running", false)

	# The old deck where the log feed station had it.
	var old := OLD_SCENE.instantiate() as Node3D
	old.position = Vector3(0.277256, 0.22059476, 5.068916) + OLD_OFFSET
	add_child(old)
	var fresh := NEW_SCENE.instantiate() as Node3D
	add_child(fresh)

	# Logs: the old deck's chains and stops; the new deck's chains and every feeder step.
	for z in [3.4, 4.1, 5.5]:
		_log(Vector3(-0.823, 1.387 + 0.292, z) + OLD_OFFSET)
	var bed := fresh.get_node("Bed") as Node3D
	for bz in [0.3, 2.4, 3.9]:
		_log(bed.to_global(Vector3(0.0, 0.292, bz)), bed.global_basis)
	_log(Vector3(-0.823, 1.121, 4.39))

	for panel in [["BEFORE", OLD_OFFSET.z], ["AFTER", 0.0]]:
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		add_child(view)
		# Same three-quarter view on each: from the service side, above the deck end at
		# the infeed, close enough that the deck and its hand-off fill the frame.
		var cam := Camera3D.new()
		cam.fov = 50.0
		view.add_child(cam)
		var z: float = panel[1]
		cam.position = Vector3(5.2, 3.1, 7.4 + z)
		cam.look_at(Vector3(-1.0, 0.5, 4.5 + z))
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
	caption.text = "Same camera and scale on both: old chain deck (left) vs live deck with step feeder (right)"
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(40, PANEL.y - 54)
	_views[1].add_child(caption)
	var screen_cam := Camera3D.new()
	add_child(screen_cam)
	screen_cam.position = Vector3(4.6, 3.3, 9.2)
	screen_cam.look_at(Vector3(-0.9, 0.4, 4.4))
	screen_cam.current = true


func _log(pos: Vector3, basis_: Basis = Basis.IDENTITY) -> void:
	var log_body := LOG_SCENE.instantiate() as RigidBody3D
	log_body.freeze = true
	add_child(log_body)
	log_body.global_transform = Transform3D(basis_, pos)


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
		print("[log_deck_before_after] saved %s" % OUT)
