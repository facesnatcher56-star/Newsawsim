extends Node3D

## Side profile of the old debarker station over the new ring debarker line, same scale,
## labelled BEFORE and AFTER, saved to dev/compare/debarker_before_after.png.
## Run: godot --path . res://dev/compare/debarker_before_after.tscn

const OLD_SCENE := preload("res://dev/compare/old_debarker/old_debarker_station.tscn")
const NEW_SCENE := preload("res://game/machines/debarker/debarker_station.tscn")
const LOG_SCENE := preload("res://game/lumber/log.tscn")
const OUT := "res://dev/compare/debarker_before_after.png"
const PANEL := Vector2i(1600, 1200)
## The old station sits this far behind the new one so each panel sees only its own.
const OLD_OFFSET := Vector3(0.0, 0.0, -60.0)

var _views: Array[SubViewport] = []
var _frames: int = 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.72)
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
		floor_mesh.position = Vector3(6.0, -1.288, z)
		add_child(floor_mesh)

	var old := OLD_SCENE.instantiate() as Node3D
	old.position = OLD_OFFSET
	add_child(old)
	# Where the mill had placed the old station's parts.
	(old.get_node("DebarkInfeedConveyor") as Node3D).position.x = -1.4334319
	var outfeed := old.get_node("WasteConveyor2") as Node3D
	outfeed.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1.5, 0, 0)), Vector3(10.217128, 0.45578635, 2.118159))
	(old.get_node("Stop") as Node3D).position.x = 19.605684
	var fresh := NEW_SCENE.instantiate() as Node3D
	add_child(fresh)
	fresh.set("running", false)

	# A mill log in each, sitting in the infeed, for scale.
	for z in [0.0, OLD_OFFSET.z]:
		var log_body := LOG_SCENE.instantiate() as RigidBody3D
		log_body.freeze = true
		add_child(log_body)
		log_body.position = Vector3(1.2, 0.95 if z == 0.0 else 0.75, 2.118 + z)

	for panel in [["BEFORE", OLD_OFFSET.z], ["AFTER", 0.0]]:
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		add_child(view)
		# Same three-quarter view on each machine: from the operator side, slightly above
		# and ahead of the ring, close enough that the ring fills the frame.
		var cam := Camera3D.new()
		cam.fov = 48.0
		view.add_child(cam)
		var z: float = panel[1]
		cam.position = Vector3(8.6, 2.9, 2.118 + z + 5.4)
		cam.look_at(Vector3(4.6, 0.7, 2.118 + z))
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
	caption.text = "Same camera and scale on both: old station (left) vs new ring debarker (right)"
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(40, PANEL.y - 54)
	_views[1].add_child(caption)
	var screen_cam := Camera3D.new()
	add_child(screen_cam)
	screen_cam.position = Vector3(6.4, 3.6, 24.1)
	screen_cam.look_at(Vector3(6.4, 0.9, 2.118))
	screen_cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		var top := _views[0].get_texture().get_image()
		var bottom := _views[1].get_texture().get_image()
		var img := Image.create(PANEL.x * 2 + 8, PANEL.y, false, top.get_format())
		img.fill(Color.BLACK)
		img.blit_rect(top, Rect2i(Vector2i.ZERO, PANEL), Vector2i.ZERO)
		img.blit_rect(bottom, Rect2i(Vector2i.ZERO, PANEL), Vector2i(PANEL.x + 8, 0))
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[debarker_before_after] saved %s" % OUT)
