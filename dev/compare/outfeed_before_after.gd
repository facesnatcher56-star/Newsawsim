extends Node3D

## Three-quarter view of the old flip-plate roller bed, sweep roller and dead-end resaw decks
## beside the new roll case with slab, cant and board kickers, slab conveyor, drum chipper and
## the cant transfer and twin-arbor gang, same camera and scale, labelled BEFORE and AFTER, saved to dev/compare/outfeed_before_after.png.
## Run: godot --path . res://dev/compare/outfeed_before_after.tscn

const OLD_SCENE := preload("res://dev/compare/old_outfeed/old_outfeed.tscn")
const NEW_SCENE := preload("res://game/machines/headrig_outfeed/headrig_outfeed.tscn")
const GANG_SCENE := preload("res://game/machines/gang_resaw/gang_resaw.tscn")
const OUT := "res://dev/compare/outfeed_before_after.png"
const PANEL := Vector2i(1600, 1200)
## The old line sits this far behind the new one so each panel sees only its own.
const OLD_OFFSET := Vector3(0.0, 0.0, -60.0)
const EYE := Vector3(31.0, 5.0, 15.5)
const TARGET := Vector3(38.5, -0.6, 5.8)

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
		plane.size = Vector2(36.0, 30.0)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.36, 0.35, 0.33)
		plane.material = fm
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(38.0, -1.288, 3.0 + z)
		add_child(floor_mesh)

	var old := OLD_SCENE.instantiate() as Node3D
	old.position = OLD_OFFSET
	add_child(old)
	add_child(NEW_SCENE.instantiate())
	add_child(GANG_SCENE.instantiate())

	for panel in [["BEFORE", OLD_OFFSET.z], ["AFTER", 0.0]]:
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		add_child(view)
		# Same three-quarter view on each: from the board side, downstream of the headrig,
		# taking in the whole case, the slab side and the chipper.
		var cam := Camera3D.new()
		cam.fov = 55.0
		view.add_child(cam)
		var z: float = panel[1]
		cam.position = EYE + Vector3(0.0, 0.0, z)
		cam.look_at(TARGET + Vector3(0.0, 0.0, z))
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
	caption.text = "Same camera and scale: old roller bed and dead-end resaw decks vs kicker roll case, slab chipper and cant gang"
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(40, PANEL.y - 54)
	_views[1].add_child(caption)
	var screen_cam := Camera3D.new()
	add_child(screen_cam)
	screen_cam.position = EYE
	screen_cam.look_at(TARGET)
	screen_cam.current = true


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
		print("[outfeed_before_after] saved %s" % OUT)
