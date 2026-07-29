@tool
extends Node3D

## level_chain_deck.gd
## Horizontal (level) chain deck logic: running/friction-drive control,
## retractable stopper and ramp state, and trigger zones.
##
## Compatible with the standard kicker/transfer station API.
## All procedural construction lives in LevelDeckVisuals (level_deck_visuals.gd);
## this script animates the stopper/ramp/frame bodies the visuals expose.

@export var deck_length:       float = 5.0:
	set(v): deck_length = v; _rebuild_everything()
@export var deck_width:        float = 5.4:
	set(v): deck_width = v; _rebuild_everything()
@export var chain_speed:       float = 0.55
@export var track_x_positions: Array[float] = [-2.4, -1.8, -1.2, -0.6, 0.0, 0.6, 1.2, 1.8, 2.4]:
	set(v): track_x_positions = v; _rebuild_everything()
@export var running:           bool  = false
@export var reverse_direction: bool  = false
@export var stoppers_extended: bool  = true
@export var stopper_height:    float = 0.35:
	set(v): stopper_height = v; _rebuild_everything()
@export var stopper_speed:     float = 1.2
@export var floor_y:           float = -1.0:
	set(v): floor_y = v; _rebuild_everything()

@export_group("Pivoting Ramp")
@export var ramp_enabled:        bool  = true:
	set(v): ramp_enabled = v; _rebuild_everything()
@export var ramp_lowered:        bool  = true
@export var ramp_length:         float = 1.2:
	set(v): ramp_length = v; _rebuild_everything()
@export var ramp_angle_down_deg: float = -20.0:
	set(v): ramp_angle_down_deg = v; _rebuild_everything()
@export var ramp_angle_up_deg:   float = 50.0:
	set(v): ramp_angle_up_deg = v; _rebuild_everything()
@export var ramp_speed:          float = 90.0

## Maximum logs the deck can carry simultaneously before it's considered full.
@export var max_logs_on_deck:  int   = 2

## Assign an Area3D in the scene for the bottom trigger (visible/movable in editor).
@export var load_zone: Area3D
## Assign an Area3D in the scene for the top trigger (visible/movable in editor).
@export var top_zone: Area3D
## Assign an Area3D in the scene for the deck tracking (visible/movable in editor).
@export var deck_area: Area3D

signal log_reached_top(l_node: RigidBody3D)

# ── Runtime state ────────────────────────────────────────────────────────────
var _start_delay_timer: float = 0.0
var _deck_root:      Node3D
var _visuals:        LevelDeckVisuals
var _active_log:     RigidBody3D
var _on_deck:        Dictionary = {}

# Stoppers
var _stoppers_body:  AnimatableBody3D

# Frame node reference (to control constant_linear_velocity)
var _frame_body:     StaticBody3D

# Ramp
var _ramp_body:      AnimatableBody3D


func _ready() -> void:
	if _deck_root == null:
		_deck_root = get_node_or_null("DeckRoot")
	
	if _deck_root == null:
		_deck_root = Node3D.new()
		_deck_root.name = "DeckRoot"
		add_child(_deck_root)
		if Engine.is_editor_hint():
			_deck_root.owner = get_tree().edited_scene_root

	# Resolve or spawn visuals node
	_visuals = _deck_root.get_node_or_null("Visuals") as LevelDeckVisuals
	if _visuals == null:
		_visuals = LevelDeckVisuals.new()
		_visuals.name = "Visuals"
		_deck_root.add_child(_visuals)
		if Engine.is_editor_hint():
			_visuals.owner = get_tree().edited_scene_root

	_rebuild_everything()


func _rebuild_everything() -> void:
	if not is_node_ready() or _visuals == null:
		return

	# Configure visuals build parameters
	_visuals.deck_length = deck_length
	_visuals.track_x_positions = track_x_positions
	_visuals.stopper_height = stopper_height
	_visuals.floor_y = floor_y
	_visuals.stoppers_extended = stoppers_extended
	_visuals.ramp_enabled = ramp_enabled
	_visuals.ramp_lowered = ramp_lowered
	_visuals.ramp_length = ramp_length
	_visuals.ramp_angle_down_deg = ramp_angle_down_deg
	_visuals.ramp_angle_up_deg = ramp_angle_up_deg

	# Rebuild procedural components in visuals
	_visuals.build()

	# Retrieve body references
	_frame_body = _visuals.frame_body
	_stoppers_body = _visuals.stoppers_body
	_ramp_body = _visuals.ramp_body

	# Resolve zones
	load_zone = _deck_root.get_node_or_null("LoadZone")
	top_zone = _deck_root.get_node_or_null("TopZone")
	deck_area = _deck_root.get_node_or_null("DeckArea")

	# Setup or hide editor-only labels
	if Engine.is_editor_hint():
		_setup_editor_labels()
	else:
		_hide_editor_labels()

	if not Engine.is_editor_hint():
		# Hook up trigger zone signals
		running = false
		if load_zone != null:
			if not load_zone.body_entered.is_connected(_on_load_zone_body_entered):
				load_zone.body_entered.connect(_on_load_zone_body_entered)
		if top_zone != null:
			if not top_zone.body_entered.is_connected(_on_top_zone_body_entered):
				top_zone.body_entered.connect(_on_top_zone_body_entered)
			if not top_zone.body_exited.is_connected(_on_top_zone_body_exited):
				top_zone.body_exited.connect(_on_top_zone_body_exited)
		if deck_area != null:
			if not deck_area.body_entered.is_connected(_on_deck_area_body_entered):
				deck_area.body_entered.connect(_on_deck_area_body_entered)
			if not deck_area.body_exited.is_connected(_on_deck_area_body_exited):
				deck_area.body_exited.connect(_on_deck_area_body_exited)


# ── Loops & Physics ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Drive stopper movement in editor preview
		if is_instance_valid(_stoppers_body) and is_instance_valid(_visuals):
			var target_y = _visuals.extended_y if stoppers_extended else _visuals.retracted_y
			_stoppers_body.position.y = move_toward(_stoppers_body.position.y, target_y, stopper_speed * delta)
		# Drive ramp pivot in editor preview
		if is_instance_valid(_ramp_body):
			var target_rot = ramp_angle_down_deg if ramp_lowered else ramp_angle_up_deg
			_ramp_body.rotation_degrees.x = move_toward(_ramp_body.rotation_degrees.x, target_rot, ramp_speed * delta)
		return

	# Auto-control ramp based on load zone occupancy
	if load_zone != null:
		var has_any := false
		for b in load_zone.get_overlapping_bodies():
			if _is_log_or_board(b):
				has_any = true
				break
		ramp_lowered = not has_any

	if _start_delay_timer > 0.0:
		_start_delay_timer -= delta
		if _start_delay_timer <= 0.0:
			set_running(true)

	var blocked_now := is_blocked_at_top()
	if not running:
		# Restart freely when not blocked at top and deck has items
		if not _on_deck.is_empty() and not blocked_now:
			set_running(true)

		# Proactively check for logs or boards in load zone to start delay timer
		if _start_delay_timer <= 0.0 and not blocked_now:
			if load_zone != null:
				var items_in_load_zone := false
				for body in load_zone.get_overlapping_bodies():
					if _is_log_or_board(body) and body is RigidBody3D:
						items_in_load_zone = true
						_active_log = body as RigidBody3D
						break
				if items_in_load_zone:
					_start_delay_timer = 2.0
		return

	if blocked_now:
		return

	if is_instance_valid(_visuals):
		_visuals.refresh_chain_links()


func _physics_process(delta: float) -> void:
	# Animate stoppers in physics process
	if is_instance_valid(_stoppers_body) and is_instance_valid(_visuals):
		var target_y = _visuals.extended_y if stoppers_extended else _visuals.retracted_y
		_stoppers_body.position.y = move_toward(_stoppers_body.position.y, target_y, stopper_speed * delta)

	# Animate ramp pivot in physics process
	if is_instance_valid(_ramp_body):
		var target_rot = ramp_angle_down_deg if ramp_lowered else ramp_angle_up_deg
		_ramp_body.rotation_degrees.x = move_toward(_ramp_body.rotation_degrees.x, target_rot, ramp_speed * delta)

	if Engine.is_editor_hint():
		return

	var blocked_now := is_blocked_at_top()
	var dir_sign := -1.0 if reverse_direction else 1.0
	var eff_speed := chain_speed * dir_sign

	# Update physical constant_linear_velocity on the frame body for friction drive
	if is_instance_valid(_frame_body):
		var vel := Vector3(0.0, 0.0, eff_speed if (running and not blocked_now) else 0.0)
		_frame_body.constant_linear_velocity = global_transform.basis * vel

	# Update physical constant_linear_velocity on the ramp for sliding assistance
	if is_instance_valid(_ramp_body):
		if running and not blocked_now and ramp_lowered:
			var rot_rad := _ramp_body.rotation.x
			var vel_dir := Vector3(0.0, -sin(rot_rad), cos(rot_rad))
			_ramp_body.constant_linear_velocity = global_transform.basis * (vel_dir * eff_speed)
		else:
			_ramp_body.constant_linear_velocity = Vector3.ZERO

	if not running or blocked_now:
		return

	var advance := eff_speed * delta
	if is_instance_valid(_visuals):
		_visuals.advance_chain(advance)


# ── API & Trigger Logic ──────────────────────────────────────────────────────

func set_running(on: bool, _force: bool = false) -> void:
	running = on
	if on:
		for l_node: RigidBody3D in _on_deck.values():
			if is_instance_valid(l_node):
				l_node.freeze = false
				l_node.axis_lock_angular_y = true
				l_node.axis_lock_angular_z = true
				l_node.axis_lock_linear_x = true
	else:
		for l_node: RigidBody3D in _on_deck.values():
			if is_instance_valid(l_node):
				l_node.freeze = true

	var dir_sign := -1.0 if reverse_direction else 1.0
	var eff_speed := chain_speed * dir_sign

	# Update velocity immediately
	if is_instance_valid(_frame_body):
		var blocked_now := is_blocked_at_top()
		var vel := Vector3(0.0, 0.0, eff_speed if (running and not blocked_now) else 0.0)
		_frame_body.constant_linear_velocity = global_transform.basis * vel

	if is_instance_valid(_ramp_body):
		var blocked_now := is_blocked_at_top()
		if running and not blocked_now and ramp_lowered:
			var rot_rad := _ramp_body.rotation.x
			var vel_dir := Vector3(0.0, -sin(rot_rad), cos(rot_rad))
			_ramp_body.constant_linear_velocity = global_transform.basis * (vel_dir * eff_speed)
		else:
			_ramp_body.constant_linear_velocity = Vector3.ZERO


func _unlock_log(l_node: RigidBody3D) -> void:
	l_node.freeze = false
	l_node.axis_lock_angular_y = false
	l_node.axis_lock_angular_z = false
	l_node.axis_lock_linear_x = false


func has_room() -> bool:
	return true


func is_blocked_at_top() -> bool:
	if not stoppers_extended:
		return false
	if top_zone == null:
		return false
	for body in top_zone.get_overlapping_bodies():
		if _is_log_or_board(body):
			return true
	return false


func _on_deck_area_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body) and body is RigidBody3D:
		var l_node := body as RigidBody3D
		var local_pos := to_local(l_node.global_position)
		if absf(local_pos.x) > 3.5 or absf(local_pos.z) > 3.5 or absf(local_pos.y) > 2.0:
			return
		_on_deck[l_node.get_instance_id()] = l_node
		if running:
			l_node.freeze = false
			l_node.axis_lock_angular_y = true
			l_node.axis_lock_angular_z = true
			l_node.axis_lock_linear_x = true


func _on_deck_area_body_exited(body: Node3D) -> void:
	if _is_log_or_board(body):
		var l_node := body as RigidBody3D
		if is_instance_valid(l_node):
			_unlock_log(l_node)
		_on_deck.erase(body.get_instance_id())


func _on_load_zone_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body):
		ramp_lowered = false
		if not running and _start_delay_timer <= 0.0:
			_active_log = body as RigidBody3D
			_start_delay_timer = 2.0


func _on_top_zone_body_entered(body: Node3D) -> void:
	if _is_log_or_board(body):
		var l_node := body as RigidBody3D
		_unlock_log(l_node)
		if _active_log == l_node:
			_active_log = null
		log_reached_top.emit(l_node)


func _on_top_zone_body_exited(body: Node3D) -> void:
	if _is_log_or_board(body):
		var l_node := body as RigidBody3D
		if is_instance_valid(l_node):
			_unlock_log(l_node)
		_on_deck.erase(body.get_instance_id())


func _is_log_or_board(body: Node) -> bool:
	if not is_instance_valid(body):
		return false
	return body.is_in_group("logs") or body.is_in_group("cut_boards")


func _setup_editor_labels() -> void:
	var zones = {
		"LoadZone": "Load Zone",
		"TopZone": "Top Zone",
		"DeckArea": "Deck Area"
	}
	if _deck_root == null:
		return
	for zone_name in zones:
		var zone = _deck_root.get_node_or_null(zone_name)
		if zone != null:
			var label = zone.get_node_or_null("EditorLabel") as Label3D
			if label == null:
				label = Label3D.new()
				label.name = "EditorLabel"
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.double_sided = false
				label.font_size = 48
				label.outline_size = 10
				label.position = Vector3(0, 0.5, 0)
				label.modulate = Color(0.0, 0.7, 1.0) # cyan/blue
				zone.add_child(label)
			label.text = zones[zone_name]


func _hide_editor_labels() -> void:
	if _deck_root == null:
		return
	for zone_name in ["LoadZone", "TopZone", "DeckArea"]:
		var zone = _deck_root.get_node_or_null(zone_name)
		if zone != null:
			var label = zone.get_node_or_null("EditorLabel")
			if label != null:
				label.hide()
