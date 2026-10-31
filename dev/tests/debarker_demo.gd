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
	[Vector3(21.5, 4.2, -3.0), Vector3(16.3, 0.4, 3.0)],    # 0 kicker, end stop and incline foot
	[Vector3(20.0, 4.2, 11.5), Vector3(19.8, 0.3, 5.4)],    # H log deck, carriage and headrig saw
	[Vector3(29.0, 5.5, -4.0), Vector3(29.0, -0.5, 7.0)],   # J headrig outfeed and the transfer on
	[Vector3(33.0, 6.5, 0.0), Vector3(39.0, -0.5, 10.0)],   # K roller bed, transfer deck and unscrambler
	[Vector3(41.0, 7.0, 9.0), Vector3(47.5, -0.5, 19.5)],   # L edger, takeaway, landing deck and sorter incline
	[Vector3(37.0, 6.5, 6.01), Vector3(37.0, 0.0, 6.0)],   # E straight down over headrig outfeed to edger
	[Vector3(39.5, 3.2, 0.2), Vector3(42.0, -0.6, 5.0)],    # R outfeed end stop, board kickers and chipper
	[Vector3(32.5, 3.4, 13.5), Vector3(36.5, -0.3, 8.4)],   # I cant transfer, turner and gang
	[Vector3(45.0, 2.8, 12.8), Vector3(40.5, -0.3, 8.6)],   # O gang outfeed lift rolls and board transfer
	[Vector3(35.5, 3.0, 15.5), Vector3(40.5, -0.4, 10.8)],  # Z unscrambler from the deck end
	[Vector3(36.2, 0.6, 11.4), Vector3(39.8, -0.2, 11.4)],  # X pocket and incline from the end
	[Vector3(37.0, 3.2, 12.6), Vector3(41.0, 1.0, 15.4)],   # C lug loader, stops and flipper
	[Vector3(35.0, 5.0, 23.5), Vector3(41.0, 0.8, 17.5)],   # V scanner deck from the infeed end
	[Vector3(38.3, 3.0, 17.6), Vector3(42.6, 1.0, 21.4)],   # A positioners, ramps and lineal infeed
	[Vector3(52.8, 3.4, 18.0), Vector3(48.3, 1.0, 21.8)],   # S edger and picker belt
]
## Close-ups for checking boards on the board line's chains (PageDown cycles, PageUp back).
const CLOSE_UPS: Array = [
	[Vector3(38.2, 0.25, 6.9), Vector3(39.1, -0.2, 7.7)],      # feed chain tails under the board kickers
	[Vector3(37.6, 0.55, 10.9), Vector3(38.7, 0.2, 11.6)],     # unscrambler lugs on the incline
	[Vector3(37.6, 1.5, 13.6), Vector3(38.5, 1.1, 14.3)],      # unscrambler top, dead plate, take-away, lug loader
	[Vector3(37.3, 1.45, 14.4), Vector3(38.4, 1.1, 15.0)],     # lug loader stops and flipper
	[Vector3(37.3, 1.45, 16.9), Vector3(38.3, 1.1, 17.5)],     # scanner chain lugs
	[Vector3(37.2, 1.5, 20.5), Vector3(38.3, 1.1, 21.2)],      # skids, positioner heads, ramps
	[Vector3(42.4, 1.5, 20.5), Vector3(43.3, 1.1, 21.6)],      # sharp chain and hold-downs at the edger
	[Vector3(44.7, 1.9, 19.9), Vector3(44.6, 1.3, 21.6)],      # saw box from the operator side
	[Vector3(47.3, 1.6, 20.4), Vector3(48.3, 1.1, 21.6)],      # picker belt and picker
	[Vector3(31.0, 0.9, 1.0), Vector3(32.7, -0.45, 3.8)],      # slab slasher and slab pan
	[Vector3(48.0, 1.4, 18.0), Vector3(49.5, 0.1, 20.2)],      # near edging slasher and chute
	[Vector3(52.0, 1.3, 9.2), Vector3(54.8, -0.8, 12.0)],      # pans into the collector and chipper
	[Vector3(51.0, 3.0, 18.0), Vector3(55.6, 0.6, 24.5)],      # belt end, landing table and transfer
	[Vector3(60.5, 3.2, 24.0), Vector3(55.6, 0.3, 29.0)],      # transfer end and lug incline foot
]
var _close_up: int = -1
var _flitches: int = 0
## Chain bed spots (bed-local z) where D drops test logs, from near the feeder back.
const DROP_Z: Array[float] = [1.2, 1.9, 2.6, 3.3, 4.0, 4.7]
var _drops: int = 0
var _phases := {}

var _cam: Camera3D
var _label: Label
var _time: float = 0.0


func _ready() -> void:
	var mill := MILL_SCENE.instantiate()
	# Test windows must never take the user's mouse: the mill's free-fly camera would capture it
	# on start and again on any click in the window.
	var flies := mill.find_children("*", "Camera3D", true, false).filter(
			func(c: Node) -> bool: return "auto_capture_on_start" in c)
	for fly in flies:
		fly.auto_capture_on_start = false
	add_child(mill)
	for fly in flies:
		fly.set_process_unhandled_input(false)
		fly.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Clicks on the window don't take focus from whatever the user is working in.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for deck_name in ["LogDeck", "LogDeckOpposite", "LogKicker"]:
		var deck := mill.get_node_or_null("LogFeedStation/%s" % deck_name)
		if deck and "debug_log" in deck:
			deck.debug_log = true
	for node_name in ["Headrig", "HeadrigOutfeed", "GangResaw", "UnscramblerLine", "ScannerDeck", "EdgerLine",
			"WasteSystem", "LandingTransfer"]:
		var node := mill.get_node_or_null(node_name)
		if node and "debug_log" in node:
			node.debug_log = true
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
	# Scripted runs: -- --keys=1:Delete,1:F,1:F --probe-every=20 --end=300 (game seconds).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--keys="):
			for item in arg.trim_prefix("--keys=").split(","):
				var parts := item.split(":")
				_auto_keys.append([float(parts[0]), OS.find_keycode_from_string(parts[1])])
		elif arg.begins_with("--probe-every="):
			_probe_every = float(arg.trim_prefix("--probe-every="))
		elif arg.begins_with("--end="):
			_auto_end = float(arg.trim_prefix("--end="))
		elif arg.begins_with("--shots="):
			# Comma-separated game times; each saves the view to --shot-dir as shot_<t>.png.
			for t in arg.trim_prefix("--shots=").split(","):
				_auto_shots.append(float(t))
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.trim_prefix("--shot-dir=")
		elif arg == "--probe-headrig":
			# Probe the cut products around the headrig too, not just the board line.
			_probe_min_x = 15.0
			_probe_min_z = -2.0
		elif arg == "--no-hud":
			_label.visible = false
		elif arg.begins_with("--cam="):
			# --cam=t:x,y,z:tx,ty,tz moves the camera at game time t (repeat for more moves).
			var parts := arg.trim_prefix("--cam=").split(":")
			var p := parts[1].split_floats(",")
			var q := parts[2].split_floats(",")
			_auto_cams.append([float(parts[0]), Vector3(p[0], p[1], p[2]), Vector3(q[0], q[1], q[2])])


var _auto_keys: Array = []
var _probe_every: float = 0.0
var _next_probe: float = 0.0
var _auto_end: float = 0.0
var _auto_shots: Array[float] = []
var _auto_cams: Array = []
var _probe_min_x: float = 36.0
var _probe_min_z: float = 12.5
var _shot_dir: String = "user://"


func _press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	_unhandled_input(ev)


func _run_auto() -> void:
	while not _auto_keys.is_empty() and _time >= float(_auto_keys[0][0]):
		_press(_auto_keys.pop_front()[1])
	if _probe_every > 0.0 and _time >= _next_probe:
		_next_probe = _time + _probe_every
		print("[probe] ---- t %.1f s ----" % _time)
		_press(KEY_P)
	while not _auto_cams.is_empty() and _time >= float(_auto_cams[0][0]):
		var c: Array = _auto_cams.pop_front()
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = 50.0
		_cam.position = c[1]
		_cam.look_at(c[2])
	while not _auto_shots.is_empty() and _time >= _auto_shots[0]:
		var path := _shot_dir.path_join("shot_%05.1f.png" % _auto_shots.pop_front())
		get_viewport().get_texture().get_image().save_png(path)
		print("[debarker_demo] saved %s" % path)
	if _auto_end > 0.0 and _time >= _auto_end:
		print("[debarker_demo] scripted run done at %.1f s" % _time)
		get_tree().quit()


func _process(delta: float) -> void:
	_time += delta
	_run_auto()
	_cam.current = true
	var lines := PackedStringArray(["t %.1f s   views: 1-9   F: %dx speed   D: log on deck" % [_time, Engine.time_scale]])
	var mill := get_child(0)
	var headrig_node := mill.get_node_or_null("Headrig")
	if headrig_node and headrig_node.has_method("status_text"):
		lines.append("Headrig: %s" % headrig_node.status_text())
	var outfeed_node := mill.get_node_or_null("HeadrigOutfeed")
	if outfeed_node and outfeed_node.has_method("status_text"):
		lines.append("Outfeed: %s" % outfeed_node.status_text())
	var gang_node := mill.get_node_or_null("GangResaw")
	if gang_node and gang_node.has_method("status_text"):
		lines.append("Gang: %s" % gang_node.status_text())
	var uns_node := mill.get_node_or_null("UnscramblerLine")
	if uns_node and uns_node.has_method("status_text"):
		lines.append("Unscrambler: %s" % uns_node.status_text())
	var deck_node := mill.get_node_or_null("ScannerDeck")
	if deck_node and deck_node.has_method("status_text"):
		lines.append("Deck: %s" % deck_node.status_text())
	var edger_node := mill.get_node_or_null("EdgerLine")
	if edger_node and edger_node.has_method("status_text"):
		lines.append("Edger: %s" % edger_node.status_text())
	var waste_node := mill.get_node_or_null("WasteSystem")
	if waste_node and waste_node.has_method("status_text"):
		lines.append("Waste: %s" % waste_node.status_text())
	var landing_node := mill.get_node_or_null("LandingTransfer")
	if landing_node and landing_node.has_method("status_text"):
		lines.append("Landing: %s" % landing_node.status_text())
	for deck_name in ["LogDeck", "LogDeckOpposite", "LogKicker"]:
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
	elif key.keycode == KEY_0:
		_set_view(10)
	elif key.keycode == KEY_H:
		_set_view(11)
	elif key.keycode == KEY_J:
		_set_view(12)
	elif key.keycode == KEY_Q:
		_set_view(13)
	elif key.keycode == KEY_W:
		_set_view(14)
	elif key.keycode == KEY_E:
		_set_view(15)
	elif key.keycode == KEY_R:
		_set_view(16)
	elif key.keycode == KEY_I:
		_set_view(17)
	elif key.keycode == KEY_O:
		_set_view(18)
	elif key.keycode == KEY_Z:
		_set_view(19)
	elif key.keycode == KEY_X:
		_set_view(20)
	elif key.keycode == KEY_C:
		_set_view(21)
	elif key.keycode == KEY_V:
		_set_view(22)
	elif key.keycode == KEY_A:
		_set_view(23)
	elif key.keycode == KEY_S:
		_set_view(24)
	elif key.keycode == KEY_PAGEDOWN or key.keycode == KEY_PAGEUP:
		_close_up = posmod(_close_up + (1 if key.keycode == KEY_PAGEDOWN else -1), CLOSE_UPS.size())
		var v: Array = CLOSE_UPS[_close_up]
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = 50.0
		_cam.position = v[0]
		_cam.look_at(v[1])
	elif key.keycode == KEY_HOME:
		# Debug: open up the edger (hide its gates, lid and operator plates) to see inside.
		var e := get_child(0).get_node_or_null("EdgerLine")
		if e:
			for n in ["SawGate", "ChipGate", "TopLid", "OperatorPlate", "Reman_OperatorPlate", "OperatorSide",
					"OperatorPlate_001", "Reman_OperatorPlate_001"]:
				for node in e.find_children(n + "*", "", true, false):
					if node is Node3D:
						node.visible = not node.visible
			print("[debarker_demo] edger opened up for a look inside")
	elif key.keycode == KEY_INSERT:
		# Short waste pieces straight onto both cross pans near the collector.
		for i in 3:
			var sp := (load("res://game/lumber/cut_slab.tscn") as PackedScene).instantiate() as RigidBody3D
			add_child(sp)
			sp.configure_length(1.2)
			sp.add_to_group("waste_piece")
			sp.global_position = Vector3(54.4, -0.6, 8.0 + 1.3 * i)
		for i in 2:
			var ep := (load("res://game/lumber/cut_board.tscn") as PackedScene).instantiate() as RigidBody3D
			add_child(ep)
			ep.configure_dimensions(1.2, 0.04, 0.05)
			ep.add_to_group("cut_slabs")
			ep.add_to_group("edgings")
			ep.add_to_group("waste_piece")
			ep.global_position = Vector3(54.4, -0.6, 15.0 + 1.3 * i)
		print("[debarker_demo] %.1f s waste pieces onto the cross pans" % _time)
	elif key.keycode == KEY_END:
		# A test slab straight onto the slab slasher's chains.
		var sl := (load("res://game/lumber/cut_slab.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(sl)
		sl.global_position = Vector3(32.7, -0.35, 4.35)
		print("[debarker_demo] %.1f s a slab onto the slab slasher" % _time)
	elif key.keycode == KEY_TAB:
		# A rough flitch straight onto the positioning skids, even-ended at the zero line; each
		# press is the next length, 6 ft to 16 ft.
		var feet: int = 6 + 2 * (_flitches % 6)
		_flitches += 1
		var length := feet * 0.3048
		var fl := (load("res://game/lumber/cut_board.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(fl)
		fl.configure_dimensions(length, 0.038, randf_range(0.22, 0.32))
		fl.nominal_size = "flitch"
		fl.set_wane(randf_range(0.015, 0.04), randf_range(0.015, 0.04))
		fl.global_position = Vector3(43.6 - length * 0.5, 1.14, 20.7)
		print("[debarker_demo] %.1f s a %d ft flitch onto the edger skids" % [_time, feet])
	elif key.keycode == KEY_DELETE:
		# One board of each length, 6 ft to 16 ft, onto the feed chains even-ended at the zero line
		# as the headrig outfeed's end stop leaves them.
		for i in 6:
			var feet := 6 + 2 * i
			var length := feet * 0.3048
			var b := (load("res://game/lumber/cut_board.tscn") as PackedScene).instantiate() as RigidBody3D
			add_child(b)
			b.configure_dimensions(length, 0.038, 0.184)
			b.global_position = Vector3(43.4 - length * 0.5, -0.1, 6.6 + 0.42 * i)
		print("[debarker_demo] %.1f s one board of each length 6-16 ft onto the feed chains" % _time)
	elif key.keycode == KEY_M:
		# Four test boards onto the lug loader, a little apart.
		for i in 4:
			var b := (load("res://game/lumber/cut_board.tscn") as PackedScene).instantiate() as RigidBody3D
			add_child(b)
			b.global_position = Vector3(41.0 + 0.04 * i, 1.16, 14.3 + 0.22 * i)
		print("[debarker_demo] %.1f s four boards onto the lug loader" % _time)
	elif key.keycode == KEY_N:
		# Three test boards onto the feed chains, a little apart.
		for i in 3:
			var b := (load("res://game/lumber/cut_board.tscn") as PackedScene).instantiate() as RigidBody3D
			b.debug_contacts = key.shift_pressed
			b.debug_interval = 2.0
			add_child(b)
			b.global_position = Vector3(41.06 + 0.05 * i, -0.1, 6.7 + 0.45 * i)
		print("[debarker_demo] %.1f s three boards onto the feed chains" % _time)
	elif key.keycode == KEY_P:
		# Probe: incline foot geometry and logs around the kicker.
		var mill := get_child(0)
		var headrig := mill.get_node_or_null("Headrig")
		if headrig and headrig.has_method("status_text"):
			print("[probe] headrig: %s" % headrig.status_text())
		for node_name in ["UnscramblerLine", "ScannerDeck", "ScannerCrew", "EdgerLine", "LandingTransfer", "BinSorter"]:
			var m := mill.get_node_or_null(node_name)
			if m and m.has_method("status_text"):
				print("[probe] %s: %s" % [node_name, m.status_text()])
		for node in get_tree().get_nodes_in_group("waste_piece"):
			var wp := node as RigidBody3D
			print("[probe] waste piece at %s v %s%s" % [wp.global_position, wp.linear_velocity, " frozen" if wp.freeze else ""])
		for node in get_tree().get_nodes_in_group("cut_boards"):
			var bd := node as RigidBody3D
			if bd.global_position.x > _probe_min_x and bd.global_position.z > _probe_min_z and bd.global_position.z < 70.0 \
					and not bd.is_in_group("waste_piece"):
				print("[probe] board %s %.1f ft at %s rot %s v %s" % [bd.name,
					(bd.product_length if "product_length" in bd else 0.0) / 0.3048, bd.global_position,
					bd.global_rotation_degrees, bd.linear_velocity])
				# What the board overlaps (slightly grown), to find what holds it.
				var cs := bd.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if cs and bd.global_position.z < 30.0:
					var q := PhysicsShapeQueryParameters3D.new()
					var grown := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
					grown.size += Vector3(0.02, 0.02, 0.02)
					q.shape = grown
					q.transform = cs.global_transform
					q.exclude = [bd.get_rid()]
					for hit in bd.get_world_3d().direct_space_state.intersect_shape(q, 8):
						var c := hit["collider"] as Node
						print("[probe]   touches %s (%s)" % [str(c.get_path()) if c else "?", hit["shape"]])
		for node in get_tree().get_nodes_in_group("logs"):
			var l := node as Node3D
			if l.global_position.x > 12.0 and l.global_position.x < 46.0:
				print("[probe] log %s at %s rot %s frozen %s" % [l.name, l.global_position, l.global_rotation_degrees,
					(l as RigidBody3D).freeze])
	elif key.keycode == KEY_G:
		# A test log straight onto the headrig's log deck.
		var log_body := (load("res://game/lumber/log.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(log_body)
		log_body.global_position = Vector3(16.9, 0.45, 4.3)
		print("[debarker_demo] %.1f s dropped a log on the headrig deck" % _time)
	elif key.keycode == KEY_U:
		# A test cant: a log sawn on two faces, dropped on the gang's cant transfer.
		var cant := (load("res://game/lumber/log.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(cant)
		cant.global_transform = Transform3D(Basis.IDENTITY, Vector3(32.7, 0.08, 6.55))
		for face in 2:
			for k in 2:
				cant.cuts_on_current_face = k + 1
				cant._update_csg_cut_position()
			cant.start_new_cut_face()
		cant.board_count = 0
		print("[debarker_demo] %.1f s dropped a cant on the outfeed" % _time)
	elif key.keycode == KEY_T or key.keycode == KEY_Y:
		# A test slab (T) or board (Y) onto the headrig outfeed roll case.
		var path := "res://game/lumber/cut_slab.tscn" if key.keycode == KEY_T else "res://game/lumber/cut_board.tscn"
		var piece := (load(path) as PackedScene).instantiate() as RigidBody3D
		add_child(piece)
		piece.global_position = Vector3(30.2, 0.05, 5.25)
		print("[debarker_demo] %.1f s dropped a %s on the outfeed" % [_time, "slab" if key.keycode == KEY_T else "board"])
	elif key.keycode == KEY_B:
		# Test speed for the headrig carriage: three times as fast through its cycle.
		var hr := get_child(0).get_node_or_null("Headrig")
		if hr:
			for prop in ["gig_speed", "feed_speed", "return_speed", "setworks_speed", "dog_speed"]:
				hr.set(prop, hr.get(prop) * 3.0)
			print("[debarker_demo] headrig at test speed")
	elif key.keycode == KEY_K:
		# A test log onto the conveyor past the debarker, short of the kicker.
		var log_body := (load("res://game/lumber/log.tscn") as PackedScene).instantiate() as RigidBody3D
		add_child(log_body)
		log_body.global_position = Vector3(14.6, 1.2, 2.118)
		print("[debarker_demo] %.1f s dropped a log on the kicker conveyor" % _time)
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
		var speed := 1.0 if Engine.time_scale >= 8.0 else Engine.time_scale * 2.0
		Engine.time_scale = speed
		Engine.physics_ticks_per_second = int(60 * speed)


func _set_view(n: int) -> void:
	var v: Array = VIEWS[n - 1]
	_cam.fov = 110.0 if n == 6 else 60.0
	# The plan view is orthographic from just under the roof.
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if n == 15 else Camera3D.PROJECTION_PERSPECTIVE
	_cam.size = 30.0
	_cam.position = v[0]
	_cam.look_at(v[1])
