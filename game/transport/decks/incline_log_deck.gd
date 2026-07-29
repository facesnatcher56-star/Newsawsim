@tool
extends Node3D

## incline_log_deck.gd
## Chain-driven incline log deck: lug physics, trigger zones, and start/stop
## control with headrig backpressure.
##
## AnimatableBody3D lugs handle log physics. All procedural meshes and the
## chain-link animation live in InclineDeckVisuals (incline_deck_visuals.gd).

@export var incline_angle_deg: float = 22.0
@export var incline_length:    float = 5.0
@export var incline_width:     float = 5.2
@export var chain_speed:       float = 0.55
@export var lugs_per_track:    int   = 4
@export var lug_spacing:       float = 1.5
@export var track_x_positions: Array[float] = [-2.4, -1.8, -1.2, -0.6, 0.0, 0.6, 1.2, 1.8, 2.4]
@export var running:           bool  = false
## Reference to the headrig carriage to check for backpressure.
@export var carriage: AnimatableBody3D
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
var _start_delay_timer: float = 0.0   # counts down before chain starts
var _slope_root:    Node3D
var _visuals:       InclineDeckVisuals
var _active_log:    RigidBody3D       # log that triggered the current chain run
var _on_deck:       Dictionary = {}   # instance_id → RigidBody3D, all logs currently on incline
var _was_blocked_at_top: bool = false # detects top-zone cleared transition

# Lugs (physics)
var _lugs:          Array[AnimatableBody3D] = []
var _lug_shapes:    Array[CollisionShape3D] = []
var _lug_track_x:   Array[float]            = []
var _slot:          Array[float]            = []
var _slot_visible:  Array[bool]             = []

# Derived
var _cycle_len:  float




func _ready() -> void:
	_cycle_len = float(lugs_per_track) * lug_spacing

	if _slope_root == null:
		_slope_root = get_node_or_null("SlopeRoot")
	
	if _slope_root == null:
		_slope_root = Node3D.new()
		_slope_root.name = "SlopeRoot"
		add_child(_slope_root)
		if Engine.is_editor_hint():
			_slope_root.owner = get_tree().edited_scene_root
			
	_slope_root.rotation_degrees.x = -incline_angle_deg

	# Visuals child (re)builds all procedural geometry from the exports.
	_visuals = _slope_root.get_node_or_null("Visuals") as InclineDeckVisuals
	if _visuals == null:
		_visuals = InclineDeckVisuals.new()
		_visuals.name = "Visuals"
		_slope_root.add_child(_visuals)
	_visuals.build(incline_length, incline_width, track_x_positions)

	_spawn_lugs()

	# Resolve zones from SlopeRoot when not wired via export.
	if load_zone == null:
		load_zone = _slope_root.get_node_or_null("LoadZone")
	if top_zone == null:
		top_zone = _slope_root.get_node_or_null("TopZone")
	if deck_area == null:
		deck_area = _slope_root.get_node_or_null("DeckArea")

	if not Engine.is_editor_hint():
		# Resolve carriage by group lookup if not wired via export.
		if not is_instance_valid(carriage):
			var found := get_tree().get_nodes_in_group("headrig_carriage")
			if found.size() > 0:
				carriage = found[0] as AnimatableBody3D
		# Force off at runtime regardless of exported value — LoadZone starts it.
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


# ─────────────────────────────────────────────────────────────────────────────
#  LUGS  (AnimatableBody3D — physics interaction)
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_lugs() -> void:
	var lug_shape := BoxShape3D.new()
	lug_shape.size = Vector3(InclineDeckVisuals.LUG_POST_W, InclineDeckVisuals.LUG_H, InclineDeckVisuals.LUG_POST_D)

	for xi in range(track_x_positions.size()):
		var tx: float = track_x_positions[xi]
		for j in range(lugs_per_track):
			var slot0 := float(j) * lug_spacing

			var lug      := AnimatableBody3D.new()
			lug.name     = "Lug_%d_%d" % [xi, j]
			lug.sync_to_physics = true

			_visuals.build_lug_visuals(lug)

			var cs    := CollisionShape3D.new()
			cs.shape  = lug_shape
			cs.position = Vector3(0.0, InclineDeckVisuals.LUG_BASE_H + InclineDeckVisuals.LUG_H * 0.5, 0.055)
			cs.disabled = slot0 >= incline_length
			lug.add_child(cs)

			_set_lug_position(lug, tx, slot0)
			_slope_root.add_child(lug)

			_lugs.append(lug)
			_lug_shapes.append(cs)
			_lug_track_x.append(tx)
			_slot.append(slot0)
			_slot_visible.append(slot0 < incline_length)


func _set_lug_position(lug: AnimatableBody3D, tx: float, slot: float) -> void:
	var half := incline_length * 0.5
	if slot < incline_length:
		lug.position = Vector3(tx, _visuals.surface_y, -half + slot)
	else:
		var t: float = (slot - incline_length) / maxf(_cycle_len - incline_length, 0.001)
		lug.position = Vector3(tx, _visuals.hidden_y, lerp(half, -half, t))


# ─────────────────────────────────────────────────────────────────────────────
#  LOOPS
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _start_delay_timer > 0.0:
		_start_delay_timer -= _delta
		if _start_delay_timer <= 0.0:
			set_running(true)

	var blocked_now := is_blocked_at_top()
	if not running:
		# Jog one alignment step when top zone clears AND headrig is free —
		# headrig being free means it finished its cycle and released the log,
		# not just moved it temporarily out of the zone mid-cut.
		if _was_blocked_at_top and not blocked_now and _is_headrig_free():
			set_running(true, true)
		# Also restart freely when headrig is free and deck has logs.
		elif not _on_deck.is_empty() and not blocked_now and _is_headrig_free():
			set_running(true)

		# Proactively check for logs in load zone to start delay timer
		if _start_delay_timer <= 0.0 and not blocked_now:
			if load_zone != null:
				var logs_in_load_zone := false
				for body in load_zone.get_overlapping_bodies():
					if body.is_in_group("logs") and body is RigidBody3D:
						logs_in_load_zone = true
						_active_log = body as RigidBody3D
						break
				if logs_in_load_zone:
					_start_delay_timer = 2.0
		_was_blocked_at_top = blocked_now
		return

	_was_blocked_at_top = blocked_now

	if is_blocked_at_top():
		return

	_visuals.refresh_chain_links()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not running:
		return

	if is_blocked_at_top():
		return

	var advance := chain_speed * delta

	# Check if we should stop at the next alignment.
	# We want to stop at the next alignment if:
	# 1. The headrig carriage is busy (not free).
	# 2. OR the deck is empty (no logs left to carry).
	var should_stop_at_align := not _is_headrig_free() or _on_deck.is_empty()

	if should_stop_at_align and _slot.size() > 0:
		var rem := fmod(_slot[0], lug_spacing)
		var dist_to_align := lug_spacing - rem
		if advance >= dist_to_align:
			advance = dist_to_align
			set_running(false)

	_visuals.advance_chain(advance)

	for i in range(_lugs.size()):
		_slot[i] = fmod(_slot[i] + advance, _cycle_len)

		var on_surface := _slot[i] < incline_length
		if on_surface != _slot_visible[i]:
			_lug_shapes[i].disabled = not on_surface
			_slot_visible[i] = on_surface

		_set_lug_position(_lugs[i], _lug_track_x[i], _slot[i])


func _get_carriage() -> AnimatableBody3D:
	if not is_instance_valid(carriage):
		if not Engine.is_editor_hint():
			var found := get_tree().get_nodes_in_group("headrig_carriage")
			if found.size() > 0:
				carriage = found[0] as AnimatableBody3D
	return carriage


func _is_headrig_free() -> bool:
	var carriage_ref = _get_carriage()
	if not is_instance_valid(carriage_ref):
		return true
	if not ("clamped_log" in carriage_ref) or not ("current_progress" in carriage_ref):
		return true
	return (carriage_ref.clamped_log == null) and ((carriage_ref.current_progress as float) < 0.01)


func set_running(on: bool, force: bool = false) -> void:
	if on and not force and _on_deck.is_empty():
		var has_log_in_load_zone := false
		if load_zone != null:
			for body in load_zone.get_overlapping_bodies():
				if body.is_in_group("logs") and body is RigidBody3D:
					has_log_in_load_zone = true
					break
		if not has_log_in_load_zone:
			return   # nothing on the deck or in load zone — don't spin the chain
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


func _unlock_log(l_node: RigidBody3D) -> void:
	l_node.freeze = false
	l_node.axis_lock_angular_y = false
	l_node.axis_lock_angular_z = false
	l_node.axis_lock_linear_x = false


## Returns true when the deck can physically accept another log from the kicker.
## Only checks physical space — does not care if the headrig is busy.
func has_room() -> bool:
	if is_blocked_at_top():
		return false
	return _on_deck.size() < max_logs_on_deck


## Returns true if a log is physically sitting in the top zone.
func is_blocked_at_top() -> bool:
	if top_zone == null:
		return false
	for body in top_zone.get_overlapping_bodies():
		if body.is_in_group("logs"):
			return true
	return false


# ─────────────────────────────────────────────────────────────────────────────
#  TRIGGER ZONES
# ─────────────────────────────────────────────────────────────────────────────

func _on_deck_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("logs") and body is RigidBody3D:
		var l_node := body as RigidBody3D
		_on_deck[l_node.get_instance_id()] = l_node
		if running:
			l_node.freeze = false
			l_node.axis_lock_angular_y = true
			l_node.axis_lock_angular_z = true
			l_node.axis_lock_linear_x = true


func _on_deck_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("logs"):
		_on_deck.erase(body.get_instance_id())


func _on_load_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("logs") and not running and _start_delay_timer <= 0.0:
		_active_log = body as RigidBody3D
		_start_delay_timer = 2.0


func _on_top_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("logs"):
		var l_node := body as RigidBody3D
		_unlock_log(l_node)
		if _active_log == l_node:
			_active_log = null
		log_reached_top.emit(l_node)


func _on_top_zone_body_exited(body: Node3D) -> void:
	# Log was kicked sideways off the incline — remove from deck tracking.
	if body.is_in_group("logs"):
		_on_deck.erase(body.get_instance_id())
