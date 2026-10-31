extends Node3D

## Three-quarter front view of the old forklift model beside the new one (rebuilt from the
## photos of the yard's truck), same camera and scale, labelled BEFORE and AFTER, saved to
## dev/compare/forklift_before_after.png. A second pair from the rear three-quarter goes below.
## Run: godot --path . res://dev/compare/forklift_before_after.tscn

const OLD_DIR := "res://dev/compare/old_forklift/old_forklift_"
const NEW_DIR := "res://game/assets/models/forklift/forklift_"
const OUT := "res://dev/compare/forklift_before_after.png"
const PANEL := Vector2i(1200, 860)
## The old truck sits this far behind the new one so each panel sees only its own.
const OLD_OFFSET := Vector3(0.0, 0.0, -40.0)
const FL := preload("res://game/machines/forklift/forklift.gd")
## Camera (eye, target) around a truck at the origin: model frame, +X forward toward the forks.
const VIEWS: Array = [
	[Vector3(6.2, 2.6, 5.0), Vector3(-0.8, 1.4, 0.0)],
	[Vector3(-7.4, 2.8, -4.8), Vector3(-1.2, 1.3, 0.0)],
]

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

	for z: float in [0.0, OLD_OFFSET.z]:
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(30.0, 24.0)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.36, 0.35, 0.33)
		plane.material = fm
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(0.0, 0.0, z)
		add_child(floor_mesh)

	# Old truck: its own track widths, the same wheel on all four corners.
	add_child(_truck(OLD_DIR, OLD_OFFSET, 1.03, 0.93, 0.55, false))
	# New truck: as forklift.gd builds it, steer wheels scaled down, glass see-through.
	add_child(_truck(NEW_DIR, Vector3.ZERO, FL.DRIVE_Z, FL.STEER_Z, FL.STEER_R, true))

	var shots: Array = []
	for v: Array in VIEWS:
		shots.append(["BEFORE", OLD_OFFSET, v])
		shots.append(["AFTER", Vector3.ZERO, v])
	for s: Array in shots:
		var view := SubViewport.new()
		view.size = PANEL
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		add_child(view)
		var cam := Camera3D.new()
		cam.fov = 50.0
		view.add_child(cam)
		var off: Vector3 = s[1]
		var pair: Array = s[2]
		cam.position = pair[0] + off
		cam.look_at(pair[1] + off)
		cam.current = true
		var label := Label.new()
		label.text = s[0]
		label.add_theme_font_size_override("font_size", 56)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 12)
		label.position = Vector2(32, 20)
		view.add_child(label)
		_views.append(view)
	var caption := Label.new()
	caption.text = "Same camera and scale: old model (left) vs the rebuild from the yard truck's photos (right)"
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(32, PANEL.y - 48)
	_views[3].add_child(caption)
	var screen_cam := Camera3D.new()
	add_child(screen_cam)
	screen_cam.position = VIEWS[0][0]
	screen_cam.look_at(VIEWS[0][1])
	screen_cam.current = true


## A parked truck from one model set: body, inner mast and carriage at home, four wheels.
func _truck(dir: String, at: Vector3, drive_z: float, steer_z: float, steer_r: float, new_model: bool) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var body: Node3D = _gltf(dir + "body.glb")
	root.add_child(body)
	if new_model:
		FL._glass_see_through(body)
	root.add_child(_gltf(dir + "mast_inner.glb"))
	var carriage: Node3D = _gltf(dir + "carriage.glb")
	carriage.position.y = 0.05
	root.add_child(carriage)
	for x: float in [0.0, -FL.WHEELBASE]:
		var r: float = FL.TYRE_R if x == 0.0 else steer_r
		var z: float = drive_z if x == 0.0 else steer_z
		for side: float in [-1.0, 1.0]:
			var w: Node3D = _gltf(dir + "wheel.glb")
			w.basis = Basis(Vector3.UP, 0.0 if side > 0.0 else PI).scaled(Vector3.ONE * (r / FL.TYRE_R))
			w.position = Vector3(x, r, side * z)
			root.add_child(w)
	return root


## Read a .glb straight from disk, so the old models need no import.
static func _gltf(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("can't load " + path)
		return Node3D.new()
	return doc.generate_scene(state) as Node3D


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		var img := Image.create(PANEL.x * 2 + 8, PANEL.y * 2 + 8, false, _views[0].get_texture().get_image().get_format())
		img.fill(Color.BLACK)
		for i in _views.size():
			var part := _views[i].get_texture().get_image()
			img.blit_rect(part, Rect2i(Vector2i.ZERO, PANEL), Vector2i((i % 2) * (PANEL.x + 8), (i / 2) * (PANEL.y + 8)))
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[forklift_before_after] saved %s" % OUT)
		get_tree().quit()
