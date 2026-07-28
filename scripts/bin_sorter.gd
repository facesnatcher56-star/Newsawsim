## bin_sorter.gd
## Industrial Green 3D Lumber Bin Sorter (Overhead Drop Sorter / Sling Sorter).
## Features:
## - Industrial Green structural steel gantry & open-bottom gravity collection hoppers.
## - Safety Yellow catwalks, handrails, and safety toe-kick plates.
## - Safety Orange hinged diverter drop gates & pneumatic cylinders.
## - Automatic optical laser scanner at infeed for length measurement.
## - Real-time physics overhead drag chain transport & pneumatic drop gate actuation.
## High-performance implementation: MeshInstance3D / MultiMeshInstance3D + Physical Lug Pushers.
@tool
extends StaticBody3D

const BinSorterFrameBuilder := preload("res://scripts/bin_sorter_builders/bin_sorter_frame_builder.gd")
const BinSorterGateBuilder := preload("res://scripts/bin_sorter_builders/bin_sorter_gate_builder.gd")
const CutBoardScene := preload("res://scenes/cut_board.tscn")

## Number of sorting bays (2 to 8).
@export_range(2, 8, 1) var num_bins: int = 4:
	set(v): num_bins = v; _rebuild()

## Width of each bin bay (meters).
@export_range(0.6, 3.5, 0.1) var bin_width: float = 0.9:
	set(v): bin_width = v; _rebuild()

## Depth of each bin pocket (Z axis, meters).
@export_range(2.5, 7.5, 0.1) var bin_depth: float = 5.5:
	set(v): bin_depth = v; _rebuild()

## Height of the overhead drag track (meters).
@export_range(2.5, 6.0, 0.1) var sorter_height: float = 4.0:
	set(v): sorter_height = v; _rebuild()

## Speed of overhead lugged drag chain (m/s).
@export_range(0.5, 6.0, 0.1) var conveyor_speed: float = 2.5:
	set(v):
		conveyor_speed = v
		constant_linear_velocity = Vector3(v, 0.0, 0.0)

## Pneumatic drop gate actuation speed (rad/s).
@export_range(1.0, 10.0, 0.5) var gate_speed: float = 6.0:
	set(v): gate_speed = v

## Automatically spawn 4.958m CutBoard test instance at infeed for physics testing.
@export var auto_spawn_test_board: bool = true

# Shared material references
var _mat_green: StandardMaterial3D
var _mat_yellow: StandardMaterial3D
var _mat_orange: StandardMaterial3D
var _mat_dark_steel: StandardMaterial3D
var _mat_chrome: StandardMaterial3D
var _mat_rubber: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_sprocket_steel: StandardMaterial3D
var _mat_cast_iron: StandardMaterial3D
var _mat_brass: StandardMaterial3D

# Internal mechanics references populated by builders
var _gate_nodes: Array[AnimatableBody3D] = []
var _piston_nodes: Array[Array] = []
var _status_led_nodes: Array[Dictionary] = []
var _target_gate_angles: Array[float] = []
var _gate_hold_timers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# MultiMesh drag chain lug system & physical pusher body
var _multimesh_lugs: MultiMeshInstance3D = null
var _lug_pusher_body: AnimatableBody3D = null
var _lug_count_per_track: int = 0
var _track_positions: Array[float] = []
var _chain_offset: float = 0.0
var _rebuild_pending: bool = false

# Dynamic board tracking state
class BoardTrackingData:
	var board: RigidBody3D
	var target_bin: int
	var infeed_time: float
	var active: bool = true
	var gate_triggered: bool = false

var _tracked_boards: Array[BoardTrackingData] = []


func _ready() -> void:
	constant_linear_velocity = Vector3(conveyor_speed, 0.0, 0.0)
	if Engine.is_editor_hint():
		_rebuild()
	else:
		_do_rebuild()
		call_deferred("_setup_standalone_camera")


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_do_rebuild()
		return
	if _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	_do_rebuild()


func _do_rebuild() -> void:
	for child in get_children():
		if child.name in ["TestCamera", "TestLight", "TestEnvironment"]:
			continue
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()

	_init_materials()
	constant_linear_velocity = Vector3(conveyor_speed, 0.0, 0.0)

	# Reset mechanics lists
	_gate_nodes.clear()
	_piston_nodes.clear()
	_status_led_nodes.clear()
	_target_gate_angles.clear()
	for i in range(num_bins):
		_target_gate_angles.append(0.0)

	# Execute procedural builders
	BinSorterFrameBuilder.new(self).build_all()
	BinSorterGateBuilder.new(self).build_all()

	# Create Infeed Optical Scanner Detection Area
	_build_infeed_trigger_zone()

	# Create Overhead Drag Chain MultiMesh Lugs & Physical Lug Pushers
	_build_overhead_chain_lugs()


func _setup_standalone_camera() -> void:
	if Engine.is_editor_hint():
		return
	var test_cam: Camera3D = get_node_or_null("TestCamera")
	var test_light: DirectionalLight3D = get_node_or_null("TestLight")

	var is_standalone: bool = (get_tree().current_scene == self or get_tree().current_scene == get_parent())

	if is_instance_valid(test_cam):
		test_cam.current = is_standalone
	if is_instance_valid(test_light):
		test_light.visible = is_standalone


func _init_materials() -> void:
	_mat_green = StandardMaterial3D.new()
	_mat_green.albedo_color = Color(0.18, 0.36, 0.24)
	_mat_green.metallic = 0.70
	_mat_green.roughness = 0.35

	_mat_yellow = StandardMaterial3D.new()
	_mat_yellow.albedo_color = Color(0.90, 0.75, 0.08)
	_mat_yellow.metallic = 0.40
	_mat_yellow.roughness = 0.40

	_mat_orange = StandardMaterial3D.new()
	_mat_orange.albedo_color = Color(0.95, 0.45, 0.05)
	_mat_orange.metallic = 0.50
	_mat_orange.roughness = 0.35

	_mat_dark_steel = StandardMaterial3D.new()
	_mat_dark_steel.albedo_color = Color(0.22, 0.24, 0.26)
	_mat_dark_steel.metallic = 0.85
	_mat_dark_steel.roughness = 0.30

	_mat_chrome = StandardMaterial3D.new()
	_mat_chrome.albedo_color = Color(0.85, 0.88, 0.90)
	_mat_chrome.metallic = 0.95
	_mat_chrome.roughness = 0.10

	_mat_rubber = StandardMaterial3D.new()
	_mat_rubber.albedo_color = Color(0.12, 0.12, 0.14)
	_mat_rubber.metallic = 0.10
	_mat_rubber.roughness = 0.80

	_mat_red = StandardMaterial3D.new()
	_mat_red.albedo_color = Color(0.95, 0.10, 0.10)
	_mat_red.emission_enabled = true
	_mat_red.emission = Color(0.95, 0.10, 0.10)
	_mat_red.emission_energy_multiplier = 1.2

	_mat_sprocket_steel = StandardMaterial3D.new()
	_mat_sprocket_steel.albedo_color = Color(0.35, 0.38, 0.42)
	_mat_sprocket_steel.metallic = 0.90
	_mat_sprocket_steel.roughness = 0.25

	_mat_cast_iron = StandardMaterial3D.new()
	_mat_cast_iron.albedo_color = Color(0.15, 0.16, 0.18)
	_mat_cast_iron.metallic = 0.60
	_mat_cast_iron.roughness = 0.55

	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color(0.85, 0.68, 0.20)
	_mat_brass.metallic = 0.85
	_mat_brass.roughness = 0.30


func _build_infeed_trigger_zone() -> void:
	var trigger_area := Area3D.new()
	trigger_area.name = "InfeedScannerArea"
	trigger_area.position = Vector3(-0.3, sorter_height + 0.1, 0.0)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.8, bin_depth)

	var col := CollisionShape3D.new()
	col.name = "ScannerCol"
	col.shape = shape
	trigger_area.add_child(col)

	trigger_area.body_entered.connect(_on_infeed_body_entered)
	add_child(trigger_area)


func _build_overhead_chain_lugs() -> void:
	var total_length: float = num_bins * bin_width + 1.0
	var lug_spacing: float = 1.2
	_lug_count_per_track = int(ceil(total_length / lug_spacing))

	var usable_depth: float = bin_depth - 1.2
	var step_z: float = usable_depth / 4.0
	_track_positions.clear()
	for c_idx in range(5):
		_track_positions.append(-usable_depth * 0.5 + c_idx * step_z)

	var total_instances: int = _lug_count_per_track * _track_positions.size()

	# 1. Visual MultiMesh Lugs
	_multimesh_lugs = MultiMeshInstance3D.new()
	_multimesh_lugs.name = "DragLugsMultiMesh"

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false

	var lug_mesh := BoxMesh.new()
	lug_mesh.size = Vector3(0.08, 0.38, 0.08)
	mm.mesh = lug_mesh
	mm.instance_count = total_instances
	_multimesh_lugs.multimesh = mm
	_multimesh_lugs.material_override = _mat_orange
	add_child(_multimesh_lugs)

	# 2. Single AnimatableBody3D containing physical lug colliders for board pushing
	_lug_pusher_body = AnimatableBody3D.new()
	_lug_pusher_body.name = "PhysicalDragLugPushers"
	_lug_pusher_body.sync_to_physics = true
	_lug_pusher_body.constant_linear_velocity = Vector3(conveyor_speed, 0.0, 0.0)

	var shape_box := BoxShape3D.new()
	shape_box.size = Vector3(0.08, 0.38, 0.08)

	var col_idx: int = 0
	for t_idx in range(_track_positions.size()):
		var track_z: float = _track_positions[t_idx]
		for i in range(_lug_count_per_track):
			var base_x: float = i * lug_spacing - 0.5
			var col := CollisionShape3D.new()
			col.name = "LugCol_%d" % col_idx
			col.shape = shape_box
			col.position = Vector3(base_x, sorter_height + 0.28, track_z)
			_lug_pusher_body.add_child(col)
			col_idx += 1

	add_child(_lug_pusher_body)

	_update_lug_multimesh()

	if auto_spawn_test_board and not Engine.is_editor_hint():
		call_deferred("spawn_test_board")


func _update_lug_multimesh() -> void:
	if _multimesh_lugs == null or _multimesh_lugs.multimesh == null:
		return
	var total_length: float = num_bins * bin_width + 1.0
	var lug_spacing: float = 1.2
	var mm: MultiMesh = _multimesh_lugs.multimesh

	var idx: int = 0
	for t_idx in range(_track_positions.size()):
		var track_z: float = _track_positions[t_idx]
		for i in range(_lug_count_per_track):
			var raw_x: float = i * lug_spacing - 0.5 + _chain_offset
			var x_pos: float = fmod(raw_x + 0.5, total_length) - 0.5
			if x_pos < -0.5:
				x_pos += total_length
			var xform := Transform3D(Basis(), Vector3(x_pos, sorter_height + 0.28, track_z))
			mm.set_instance_transform(idx, xform)
			idx += 1

	if is_instance_valid(_lug_pusher_body):
		_lug_pusher_body.position.x = _chain_offset
		_lug_pusher_body.constant_linear_velocity = Vector3(conveyor_speed, 0.0, 0.0)


func spawn_test_board() -> RigidBody3D:
	if CutBoardScene == null:
		return null
	var board_inst: RigidBody3D = CutBoardScene.instantiate() as RigidBody3D
	board_inst.name = "TestCutBoard_4.958m"
	board_inst.position = Vector3(-0.3, sorter_height + 0.14, 0.0)
	board_inst.rotation = Vector3(0.0, PI * 0.5, 0.0)
	add_child(board_inst)
	return board_inst


func _on_infeed_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if not (body is RigidBody3D):
		return

	for data in _tracked_boards:
		if data.board == body:
			return

	var board_length: float = 4.958
	var aabb_size := Vector3.ZERO

	for child in body.get_children():
		if child is CollisionShape3D and is_instance_valid(child.shape):
			if child.shape is BoxShape3D:
				aabb_size = child.shape.size

	var max_dim: float = maxf(aabb_size.x, aabb_size.z)
	if max_dim > 0.1:
		board_length = max_dim

	var target_b: int = 0
	if board_length < 3.0:
		target_b = 0
	elif board_length < 4.0:
		target_b = min(1, num_bins - 1)
	elif board_length < 4.8:
		target_b = min(2, num_bins - 1)
	else:
		target_b = min(3, num_bins - 1)

	var tracking := BoardTrackingData.new()
	tracking.board = body as RigidBody3D
	tracking.target_bin = target_b
	tracking.infeed_time = Time.get_ticks_msec() / 1000.0
	_tracked_boards.append(tracking)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Advance MultiMesh & physical lug pushers forward along +X
	var total_length: float = num_bins * bin_width + 1.0
	_chain_offset = fmod(_chain_offset + conveyor_speed * delta, total_length)
	_update_lug_multimesh()

	# Process active tracked boards
	var i: int = _tracked_boards.size() - 1
	while i >= 0:
		var tracking := _tracked_boards[i]
		if not is_instance_valid(tracking.board) or not tracking.active:
			_tracked_boards.remove_at(i)
			i -= 1
			continue

		var local_pos: Vector3 = to_local(tracking.board.global_position)
		var target_x: float = (tracking.target_bin + 0.3) * bin_width

		# Propel board along sorter deck level
		if local_pos.y >= sorter_height - 0.6:
			tracking.board.linear_velocity.x = conveyor_speed

		# Trigger gate when board approaches target bin bay (Tipples rotate UPWARDS to -0.65 rad)
		if not tracking.gate_triggered and local_pos.x >= target_x - 0.9 and local_pos.x <= target_x + 0.6:
			_target_gate_angles[tracking.target_bin] = -0.65
			_gate_hold_timers[tracking.target_bin] = 2.0
			_set_bay_status_led(tracking.target_bin, "Yellow")
			tracking.gate_triggered = true

		# Board drops down into bin hopper below deck level
		if local_pos.y < sorter_height - 0.8:
			tracking.active = false
		i -= 1

	# Actuate pneumatic drop gates and piston rods (Upward angle = -0.65 rad)
	for b in range(num_bins):
		if b >= _gate_nodes.size():
			continue

		var gate: AnimatableBody3D = _gate_nodes[b]
		var target_angle: float = _target_gate_angles[b]
		var cur_angle: float = gate.rotation.z

		if not is_equal_approx(cur_angle, target_angle):
			gate.rotation.z = move_toward(cur_angle, target_angle, gate_speed * delta)

			if b < _piston_nodes.size():
				var extension: float = (abs(gate.rotation.z) / 0.65) * 0.15
				for piston in _piston_nodes[b]:
					if is_instance_valid(piston):
						piston.position.y = -0.25 - extension

		if _target_gate_angles[b] != 0.0 and is_equal_approx(gate.rotation.z, -0.65):
			_gate_hold_timers[b] -= delta
			if _gate_hold_timers[b] <= 0.0:
				_target_gate_angles[b] = 0.0
				_set_bay_status_led(b, "Green")


func _set_bay_status_led(bay_index: int, state: String) -> void:
	if bay_index < 0 or bay_index >= _status_led_nodes.size():
		return

	var leds: Dictionary = _status_led_nodes[bay_index]
	for led_name in leds.keys():
		var mesh: MeshInstance3D = leds[led_name]
		if not is_instance_valid(mesh) or not (mesh.material_override is StandardMaterial3D):
			continue
		var mat: StandardMaterial3D = mesh.material_override

		if (state == "Yellow" and led_name == "YellowLED") or (state == "Green" and led_name == "GreenLED") or (state == "Red" and led_name == "RedLED"):
			mat.emission_energy_multiplier = 2.5
		else:
			mat.emission_energy_multiplier = 0.3
