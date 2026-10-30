extends Node3D

## Demo to watch the debarker inside the running mill: the loaders feed the decks, the
## decks drop logs into the debarker infeed, and the debarked logs carry on downstream.
## Keys: 1-9 views (7-9 the log decks and step feeders), F cycles 1x / 2x / 4x speed,
## L drops a log straight onto the infeed, D (Shift+D) drops one on a deck's chains.
## Run: godot --path . res://dev/tests/debarker_demo.tscn

const MILL_SCENE := preload("res://game/levels/mill_prototype.tscn")

const VIEWS: Array = [
	[Vector3(5.0, 5.5, 11.0), Vector3(5.0, 0.6, 2.1)],      # 1 whole debarker line from the deck side
	[Vector3(2.0, 2.6, 5.6), Vector3(4.2, 0.8, 2.1)],       # 2 infeed and feed rolls
	[Vector3(7.6, 2.4, 5.4), Vector3(5.2, 0.8, 2.1)],       # 3 ring from the outfeed side
	[Vector3(5.2, 1.6, -2.4), Vector3(5.2, -0.6, 1.5)],     # 4 under the ring: bark belt
	[Vector3(-3.0, 9.0, 14.0), Vector3(8.0, 0.0, 2.0)],     # 5 decks to outfeed overview
	[Vector3(5.0, 6.8, 2.01), Vector3(5.0, 0.0, 2.0)],      # 6 straight down over the line (wide)
	[Vector3(4.5, 3.6, 6.8), Vector3(-0.8, 0.8, 4.3)],      # 7 step feeder, deck side
	[Vector3(6.5, 5.0, 12.5), Vector3(-0.8, 0.3, 7.0)],     # 8 whole log deck
	[Vector3(4.5, 3.6, -2.56), Vector3(-0.8, 0.8, -0.06)],  # 9 step feeder, opposite deck
]
## Chain bed spots (bed-local z) where D drops test logs, from near the feeder back.
const DROP_Z: Array[float] = [1.2, 1.9, 2.6, 3.3, 4.0, 4.7]
var _drops: int = 0
var _phases := {}

var _cam: Camera3D
var _label: Label
var _time: float = 0.0


func _ready() -> void:
	var mill := MILL_SCENE.instantiate()
	add_child(mill)
	for deck_name in ["LogDeck", "LogDeckOpposite"]:
		var deck := mill.get_node_or_null("LogFeedStation/%s" % deck_name)
		if deck and "debug_log" in deck:
			deck.debug_log = true
	# The mill has its own camera; ours takes over.
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.current = true
	_set_view(1)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 18)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)


func _process(delta: float) -> void:
	_time += delta
	_cam.current = true
	var lines := PackedStringArray(["t %.1f s   views: 1-9   F: %dx speed   D: log on deck" % [_time, Engine.time_scale]])
	var mill := get_child(0)
	for deck_name in ["LogDeck", "LogDeckOpposite"]:
		var deck := mill.get_node_or_null("LogFeedStation/%s" % deck_name)
		if deck and deck.has_method("status_text"):
			lines.append("%s: %s" % [deck_name, deck.status_text()])
	for loader_name in ["KnuckleBoomLoader", "KnuckleBoomLoaderOpposite"]:
		var loader := mill.get_node_or_null("LogFeedStation/%s" % loader_name)
		if loader and "phase" in loader:
			var phase_name: String = loader.Phase.keys()[loader.phase]
			lines.append("%s: %s  tip %.2f clear %.2f goal %.2f hover %.2f deck %.2f" % [loader_name, phase_name,
				loader._tip_height_world(), loader._lift_clear_height(),
				loader._goal_tip.y + (loader._turret.get_parent() as Node3D).global_position.y,
				loader._hover_height(), loader._deck_top()])
			if _phases.get(loader_name, "") != phase_name:
				_phases[loader_name] = phase_name
				print("[debarker_demo] %.1f s %s %s" % [_time, loader_name, phase_name])
	var deb := mill.get_node_or_null("DebarkerStation")
	if deb:
		var on_infeed := 0
		for b in deb.infeed_area.get_overlapping_bodies():
			if b.is_in_group("logs"):
				on_infeed += 1
		lines.append("debarker: infeed logs %d  held %s  feeding %s  tools r %.2f" % [on_infeed,
			deb.infeed.hold, deb._carry != null, deb._tool_r])
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_set_view(key.keycode - KEY_0)
	elif key.keycode == KEY_D:
		# A test log straight onto a deck's chains (Shift: the opposite deck).
		var deck_name := "LogDeckOpposite" if key.shift_pressed else "LogDeck"
		var bed := get_child(0).get_node_or_null("LogFeedStation/%s/Bed" % deck_name) as Node3D
		if bed:
			var log_body := (load("res://game/lumber/log.tscn") as PackedScene).instantiate() as RigidBody3D
			add_child(log_body)
			var z: float = DROP_Z[_drops % DROP_Z.size()]
			_drops += 1
			log_body.global_transform = Transform3D(bed.global_basis, bed.to_global(Vector3(0.0, 0.35, z)))
			print("[debarker_demo] %.1f s dropped a log on %s" % [_time, deck_name])
	elif key.keycode == KEY_I:
		# Lists meshes around a spot, to identify parts on screen.
		var spot := Vector3(6.8, 1.9, 1.3)
		for node in get_tree().root.find_children("*", "CSGShape3D", true, false):
			var c := node as CSGShape3D
			if not c.is_root_shape():
				continue
			var aabb := c.global_transform * c.get_aabb()
			if aabb.grow(2.0).has_point(spot):
				print("[debarker_demo] CSG near %s: %s  aabb %s" % [spot, c.get_path(), aabb])
	elif key.keycode == KEY_L:
		var log_body := (load("res://game/lumber/log.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(log_body)
		log_body.global_position = Vector3(-0.8, 1.6, 2.118)
		print("[debarker_demo] %.1f s dropped a log on the infeed" % _time)
	elif key.keycode == KEY_F:
		# 1x -> 2x -> 4x. Physics ticks scale with it so each step stays 1/60 s of game time.
		var speed := 1.0 if Engine.time_scale >= 4.0 else Engine.time_scale * 2.0
		Engine.time_scale = speed
		Engine.physics_ticks_per_second = int(60 * speed)


func _set_view(n: int) -> void:
	var v: Array = VIEWS[n - 1]
	_cam.fov = 110.0 if n == 6 else 60.0
	_cam.position = v[0]
	_cam.look_at(v[1])
