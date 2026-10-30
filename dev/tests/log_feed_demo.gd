extends Node3D

## Demo to watch the log feed on its own: the two knuckleboom loaders taking bundles from
## their yard piles and setting them on the debark decks, then pushing off any log that
## landed on top of another. Keys: 1-5 views, F 2x speed, R drop a log onto a deck log,
## T turn a deck log off square, G turn pushing off (riders are picked up and set down
## clear instead).
## Run: godot --path . res://dev/tests/log_feed_demo.tscn

const STATION_SCENE := preload("res://game/machines/log_feed/log_feed_station.tscn")
const PHASE_NAMES := ["TO_PILE", "SETTLE_PILE", "DESCEND_PILE", "GRAB", "LIFT_PILE", "TO_DECK", "WAIT_DECK",
	"DESCEND_DECK", "RELEASE", "LIFT_DECK", "INSPECT_DECK", "FIX_TO", "FIX_SETTLE", "FIX_LOWER", "FIX_PUSH",
	"FIX_BACKOFF", "FIX_CHECK", "RETURN_TO_PILE", "RETURN_LOWER"]
const LOG_SCENE := preload("res://game/lumber/log.tscn")

const VIEWS: Array = [
	[Vector3(-1.0, 7.5, 19.0), Vector3(-5.5, 0.5, 6.0)],      # 1 loader A, pile and deck from the side
	[Vector3(-8.5, 3.2, 14.0), Vector3(-10.5, 0.0, 9.0)],     # 2 grapple at the pile
	[Vector3(1.5, 4.5, 11.5), Vector3(-1.0, 1.5, 6.0)],       # 3 deck infeed end
	[Vector3(4.0, 14.0, 2.5), Vector3(-5.5, 0.0, 2.2)],       # 4 both loaders from above
	[Vector3(2.5, 3.8, -6.8), Vector3(-1.0, 1.4, -2.2)],      # 5 opposite deck infeed end
]

var _cam: Camera3D
var _label: Label
var _loaders: Array[Node] = []
var _last_phase: Array[int] = []
var _time: float = 0.0


func _ready() -> void:
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
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	shape.shape = box
	shape.position = Vector3(-2.0, -1.388, 2.0)
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.40, 0.38, 0.35)
	fm.roughness = 0.95
	bm.material = fm
	floor_mesh.mesh = bm
	floor_mesh.position = shape.position
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	var station := STATION_SCENE.instantiate()
	add_child(station)
	for loader_name in ["KnuckleBoomLoader", "KnuckleBoomLoaderOpposite"]:
		_loaders.append(station.get_node(loader_name))
		_last_phase.append(-1)

	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_set_view(1)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 18)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)


func _process(delta: float) -> void:
	_time += delta
	var lines := PackedStringArray(["t %.1f s   views: 1-4   F: %dx speed" % [_time, Engine.time_scale]])
	for i in range(_loaders.size()):
		var loader := _loaders[i]
		var phase: int = loader.phase
		lines.append("%s: %s  (bundle %d)" % [loader.name, PHASE_NAMES[phase], loader._bundle.size()])
		var stops: Node = loader._deck_stops
		if stops:
			lines.append("    deck: stops %s  chains %.2f m/s  held %s" % [
				["EXTENDED", "HOLDING_LOG", "RETRACTING", "RETRACTED", "SETTLING", "EXTENDING"][stops._state],
				stops._conveyor.speed, stops.hold_chains])
		if phase != _last_phase[i]:
			var extra := ""
			var deck := loader.get_node(loader.deck_path) as Node3D
			var rider: Node3D = loader._fix_log
			if rider and is_instance_valid(rider):
				extra = "  rider deck-local %s (push %d)" % [deck.to_local(rider.global_position), loader._fix_pushes]
			if PHASE_NAMES[phase] == "FIX_PUSH":
				extra += "  line %s -> %s" % [deck.to_local(loader._line_from), deck.to_local(loader._line_to)]
			print("[log_feed_demo] %.1f s %s -> %s%s" % [_time, loader.name, PHASE_NAMES[phase], extra])
			_last_phase[i] = phase
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_set_view(key.keycode - KEY_0)
	elif key.keycode == KEY_F:
		Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 2.0
	elif key.keycode == KEY_R:
		drop_rider()
	elif key.keycode == KEY_T:
		twist_log()
	elif key.keycode == KEY_G:
		# Pushing off/on: with it off every rider gets picked up and set down clear.
		for loader in _loaders:
			loader.max_pushes = 2 if loader.max_pushes == 0 else 0
		print("[log_feed_demo] pushes per rider: %d" % _loaders[0].max_pushes)


## Turns the log nearest deck A's infeed end 30 degrees off square, as if it slewed on landing.
func twist_log() -> void:
	var deck := _loaders[0].get_node(_loaders[0].deck_path) as Node3D
	var target: RigidBody3D = null
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := deck.to_local(l.global_position)
		if p.x > -4.0 and p.x < 1.8 and absf(p.z) < 2.2 and (target == null or p.z > deck.to_local(target.global_position).z):
			target = l
	if target:
		target.global_basis = Basis(Vector3.UP, deg_to_rad(30.0)) * target.global_basis
		print("[log_feed_demo] %.1f s twisted a deck log 30 deg" % _time)


## Drops a log straight onto a log lying on deck A, the way a bundle sometimes lands.
func drop_rider() -> void:
	var deck := _loaders[0].get_node(_loaders[0].deck_path) as Node3D
	var target: RigidBody3D = null
	for node in get_tree().get_nodes_in_group("logs"):
		var l := node as RigidBody3D
		if l == null or l.freeze:
			continue
		var p := deck.to_local(l.global_position)
		if p.x > -4.0 and p.x < 1.8 and absf(p.z) < 2.2 and (target == null or p.z > deck.to_local(target.global_position).z):
			target = l
	var log_body := LOG_SCENE.instantiate() as RigidBody3D
	add_child(log_body)
	var spot := deck.to_global(Vector3(-1.1, 2.4, 1.0))
	if target:
		spot = target.global_position + Vector3.UP * 0.75
	log_body.global_transform = Transform3D(deck.global_basis, spot)
	print("[log_feed_demo] %.1f s dropped a rider at %s" % [_time, spot])


func _set_view(n: int) -> void:
	var v: Array = VIEWS[n - 1]
	_cam.position = v[0]
	_cam.look_at(v[1])
