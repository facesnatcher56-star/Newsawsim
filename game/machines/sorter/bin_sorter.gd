@tool
class_name BinSorter
extends StaticBody3D

## 50-Bay Industrial Lumber Bin Sorter with Blender Frame & Dynamic Carriage Lowering.

const CutBoardScene := preload("res://game/lumber/cut_board.tscn")

@export_range(2, 50, 1) var num_bins: int = 50
@export_range(1, 50, 1) var max_boards_per_bay: int = 10
@export var continuous_infeed_spawner: bool = false
@export var random_bay_sorting: bool = false
@export_range(0.1, 2.0, 0.05) var indexing_speed: float = 0.50
@export_range(0.6, 3.5, 0.1) var bin_width: float = 1.0
@export_range(2.5, 7.5, 0.1) var bin_depth: float = 5.5
@export_range(2.5, 6.0, 0.1) var sorter_height: float = 4.30
@export_range(0.5, 6.0, 0.1) var conveyor_speed: float = 2.5
@export_range(0.5, 6.0, 0.1) var haulout_speed: float = 1.2
@export_range(1.0, 25.0, 0.5) var gate_speed: float = 14.0
@export var auto_spawn_test_board: bool = false

# State arrays for all bays
var _bay_board_counts: Array[int] = []
var _bay_discharging: Array[bool] = []
var _discharge_timers: Array[float] = []
var _cradle_heights: Array[float] = []
var _cradle_target_heights: Array[float] = []
var _gate_angles: Array[float] = []
var _target_gate_angles: Array[float] = []
var _gate_hold_timers: Array[float] = []

# Node references from BlenderFrame
var _gate_nodes: Array[Node3D] = []
var _cradle_nodes: Array[Node3D] = []
var _cradle_bodies: Array[AnimatableBody3D] = []
var _gate_bodies: Array[AnimatableBody3D] = []
var _top_drive_shaft: Node3D = null
var _top_tail_shaft: Node3D = null
var _haulout_drive_shaft: Node3D = null
var _haulout_tail_shaft: Node3D = null
var _floor_bed: StaticBody3D = null

# Board tracking state
var _tracked_boards: Array[SorterBoardTracker.BoardTrackingData] = []

const TOP_CATCH_Y: float = 3.80
const FLOOR_DISCHARGE_Y: float = 0.05

func _ready() -> void:
	_init_state_arrays()
	_bind_blender_frame_nodes()
	_setup_physics_collision()
	_setup_standalone_camera()

func _init_state_arrays() -> void:
	_bay_board_counts.clear()
	_bay_discharging.clear()
	_discharge_timers.clear()
	_cradle_heights.clear()
	_cradle_target_heights.clear()
	_gate_angles.clear()
	_target_gate_angles.clear()
	_gate_hold_timers.clear()

	for i in range(num_bins):
		_bay_board_counts.append(0)
		_bay_discharging.append(false)
		_discharge_timers.append(0.0)
		_cradle_heights.append(TOP_CATCH_Y)
		_cradle_target_heights.append(TOP_CATCH_Y)
		_gate_angles.append(0.0)
		_target_gate_angles.append(0.0)
		_gate_hold_timers.append(0.0)

func _bind_blender_frame_nodes() -> void:
	_gate_nodes.clear()
	_cradle_nodes.clear()
	
	var frame: Node = get_node_or_null("BlenderFrame")
	if not frame:
		frame = self

	for b in range(num_bins):
		var gate := frame.find_child("Gate_%02d" % b, true, false) as Node3D
		if gate:
			_gate_nodes.append(gate)
		var carr := frame.find_child("Carriage_%02d" % b, true, false) as Node3D
		if carr:
			_cradle_nodes.append(carr)

	_top_drive_shaft = frame.find_child("TopDriveShaft", true, false) as Node3D
	_top_tail_shaft = frame.find_child("TopTailShaft", true, false) as Node3D
	_haulout_drive_shaft = frame.find_child("HaulOutDriveShaft", true, false) as Node3D
	_haulout_tail_shaft = frame.find_child("HaulOutTailShaft", true, false) as Node3D

func _setup_physics_collision() -> void:
	var res := SorterCollisionBuilder.build(self, _gate_nodes)
	_floor_bed = res.floor_bed
	_cradle_bodies = res.cradle_bodies
	_gate_bodies = res.gate_bodies
	
	var infeed: Area3D = res.infeed_zone
	if infeed and not infeed.body_entered.is_connected(_on_infeed_body_entered):
		infeed.body_entered.connect(_on_infeed_body_entered)

func _setup_standalone_camera() -> void:
	if Engine.is_editor_hint():
		return
	var test_cam: Camera3D = get_node_or_null("TestCamera")
	var test_light: DirectionalLight3D = get_node_or_null("TestLight")
	var is_standalone: bool = (get_tree().current_scene == self)
	if not is_standalone:
		if is_instance_valid(test_cam):
			test_cam.current = false
		if is_instance_valid(test_light):
			test_light.visible = false

func can_accept_board(body: Node3D) -> bool:
	return SorterBoardTracker.can_accept_board(body, num_bins, _bay_board_counts, _bay_discharging, max_boards_per_bay, _tracked_boards)

func _on_infeed_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if not (body is RigidBody3D) or not body.is_in_group("cut_boards") or body.is_in_group("cut_slabs") or body.freeze:
		return

	for data in _tracked_boards:
		if data.board == body:
			return

	var raw_target: int = 0
	if random_bay_sorting:
		raw_target = randi() % num_bins
	else:
		raw_target = SorterBoardTracker.get_board_sorting_grade(body, num_bins)

	var target_b: int = -1
	for offset in range(num_bins):
		var candidate: int = (raw_target + offset) % num_bins
		if _bay_board_counts[candidate] < max_boards_per_bay and not _bay_discharging[candidate]:
			target_b = candidate
			break

	if target_b < 0:
		return

	var tracking := SorterBoardTracker.BoardTrackingData.new()
	tracking.board = body as RigidBody3D
	tracking.target_bin = target_b
	tracking.infeed_time = Time.get_ticks_msec() / 1000.0
	tracking.previous_freeze_mode = (body as RigidBody3D).freeze_mode
	(body as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	(body as RigidBody3D).freeze = true
	_tracked_boards.append(tracking)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# 1. Rotate conveyor and haul-out shafts
	if is_instance_valid(_top_drive_shaft):
		_top_drive_shaft.rotate_z(conveyor_speed * delta / 0.18)
	if is_instance_valid(_top_tail_shaft):
		_top_tail_shaft.rotate_z(conveyor_speed * delta / 0.18)
	if is_instance_valid(_haulout_drive_shaft):
		_haulout_drive_shaft.rotate_z(haulout_speed * delta / 0.16)
	if is_instance_valid(_haulout_tail_shaft):
		_haulout_tail_shaft.rotate_z(haulout_speed * delta / 0.16)

	# 2. Update haul-out constant linear velocity
	if is_instance_valid(_floor_bed):
		_floor_bed.constant_linear_velocity = global_basis.x * haulout_speed

	# 3. Process tracked boards moving overhead
	var i: int = _tracked_boards.size() - 1
	while i >= 0:
		var tracking := _tracked_boards[i]
		if not is_instance_valid(tracking.board) or not tracking.active:
			_tracked_boards.remove_at(i)
			i -= 1
			continue

		var local_pos := to_local(tracking.board.global_position)
		var bay_x: float = float(tracking.target_bin) * bin_width

		if not tracking.dropped_into_bay:
			if not tracking.released:
				# Advance board toward target bay along +X
				var target_pos: Vector3 = Vector3(bay_x + bin_width * 0.45, sorter_height + 0.08, 0.0)
				tracking.board.global_position = tracking.board.global_position.move_toward(to_global(target_pos), conveyor_speed * delta)
				local_pos = to_local(tracking.board.global_position)

			# Trigger drop gate as board approaches bay (negative rotation opens downward)
			if not tracking.gate_triggered and local_pos.x >= bay_x + bin_width * 0.10:
				tracking.gate_triggered = true
				_target_gate_angles[tracking.target_bin] = -1.1
				_gate_hold_timers[tracking.target_bin] = 1.5

			# Release board into bay
			if local_pos.x >= bay_x + bin_width * 0.35 and not tracking.released:
				tracking.released = true
				tracking.board.freeze_mode = tracking.previous_freeze_mode
				tracking.board.freeze = false
				tracking.board.sleeping = false
				tracking.board.linear_velocity = Vector3(0.0, -3.0, 0.0)

			# Confirm drop into cradle
			if tracking.released and local_pos.y < sorter_height - 0.25 and local_pos.x >= bay_x - 0.1 and local_pos.x < bay_x + bin_width + 0.1:
				tracking.dropped_into_bay = true
				if tracking.target_bin < _bay_board_counts.size():
					_bay_board_counts[tracking.target_bin] += 1
					var count: int = _bay_board_counts[tracking.target_bin]
					_cradle_target_heights[tracking.target_bin] = maxf(0.50, TOP_CATCH_Y - float(count) * 0.25)
				_target_gate_angles[tracking.target_bin] = 0.0
				_tracked_boards.remove_at(i)

		i -= 1

	# 4. Animate diverter drop gates
	for b in range(num_bins):
		if _gate_hold_timers[b] > 0.0:
			_gate_hold_timers[b] -= delta
			if _gate_hold_timers[b] <= 0.0:
				_target_gate_angles[b] = 0.0

		_gate_angles[b] = move_toward(_gate_angles[b], _target_gate_angles[b], gate_speed * delta)
		if b < _gate_nodes.size() and is_instance_valid(_gate_nodes[b]):
			_gate_nodes[b].rotation.z = _gate_angles[b]
		if b < _gate_bodies.size() and is_instance_valid(_gate_bodies[b]):
			_gate_bodies[b].rotation.z = _gate_angles[b]

	# 5. Animate cradle carriages & manage discharge lifecycle
	for b in range(num_bins):
		# Full bay triggers discharge cycle
		if _bay_board_counts[b] >= max_boards_per_bay and not _bay_discharging[b]:
			_bay_discharging[b] = true
			_discharge_timers[b] = 4.0
			_cradle_target_heights[b] = FLOOR_DISCHARGE_Y

		if _bay_discharging[b]:
			if _cradle_heights[b] <= FLOOR_DISCHARGE_Y + 0.05:
				_discharge_timers[b] -= delta
				if _discharge_timers[b] <= 0.0:
					# Discharge complete, reset bay to empty and raise cradle
					_bay_board_counts[b] = 0
					_bay_discharging[b] = false
					_cradle_target_heights[b] = TOP_CATCH_Y

		# Smoothly interpolate cradle elevation
		_cradle_heights[b] = move_toward(_cradle_heights[b], _cradle_target_heights[b], indexing_speed * delta)

		# Apply translation to visual Blender carriage model (origin is at 3.30m)
		if b < _cradle_nodes.size() and is_instance_valid(_cradle_nodes[b]):
			_cradle_nodes[b].position.y = _cradle_heights[b] - TOP_CATCH_Y

		# Update physical cradle collision support body
		if b < _cradle_bodies.size() and is_instance_valid(_cradle_bodies[b]):
			_cradle_bodies[b].position.y = _cradle_heights[b]
