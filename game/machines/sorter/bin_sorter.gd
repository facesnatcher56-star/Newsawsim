@tool
class_name BinSorter
extends StaticBody3D

## 50-Bay Industrial Lumber Bin Sorter with Blender Frame & Dynamic Carriage Lowering.

const CutBoardScene := preload("res://game/lumber/cut_board.tscn")
const SorterChainSystemScript := preload("res://game/machines/sorter/sorter_chain_system.gd")
const SorterCradleVisualBuilderScript := preload("res://game/machines/sorter/sorter_cradle_visual_builder.gd")

# Fixed physical dimensions defined by the 50-bay Blender structural frame model
const num_bins: int = 50
const bin_width: float = 1.0
const bin_depth: float = 5.5
const sorter_height: float = 4.30

@export_group("Conveyor & Drive Speeds")
@export_range(0.5, 6.0, 0.1) var conveyor_speed: float = 2.5
@export_range(0.5, 6.0, 0.1) var haulout_speed: float = 1.2
@export_range(0.1, 2.0, 0.05) var indexing_speed: float = 0.50
@export_range(1.0, 25.0, 0.5) var gate_speed: float = 14.0

@export_group("Sorting Rules")
@export_range(1, 50, 1) var max_boards_per_bay: int = 10
@export var random_bay_sorting: bool = false

@export_group("Testing & Simulation")
@export var auto_spawn_test_board: bool = false
@export var continuous_infeed_spawner: bool = false


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
var _cradle_plates_mm: MultiMeshInstance3D = null
var _cradle_spines_mm: MultiMeshInstance3D = null
var _cradle_shafts_mm: MultiMeshInstance3D = null
var _cradle_collars_mm: MultiMeshInstance3D = null
var _top_drive_shaft: Node3D = null
var _top_tail_shaft: Node3D = null
var _haulout_drive_shaft: Node3D = null
var _haulout_tail_shaft: Node3D = null
var _floor_bed: StaticBody3D = null
var _chain_system: Node3D = null
var _chain_visual_elapsed: float = 0.0
const CHAIN_IDLE_DELAY: float = 2.0
const TOP_PARK_DELAY: float = 1.0
var _top_active: bool = false
var _haulout_active: bool = false
var _top_empty_seconds: float = 0.0
var _haulout_empty_seconds: float = 0.0

# Board tracking state
var _tracked_boards: Array[SorterBoardTracker.BoardTrackingData] = []
var _bay_boards: Array[Array] = []
var _bay_stack_heights: Array[float] = []

const TOP_CATCH_Y: float = 3.40
const FLOOR_DISCHARGE_Y: float = 0.05

func _ready() -> void:
	_init_state_arrays()
	_bind_blender_frame_nodes()
	_setup_reference_cradle_visuals()
	_setup_physics_collision()
	_setup_chain_system()
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
	_bay_boards.clear()
	_bay_stack_heights.clear()

	for i in range(num_bins):
		_bay_board_counts.append(0)
		_bay_discharging.append(false)
		_discharge_timers.append(0.0)
		_cradle_heights.append(TOP_CATCH_Y)
		_cradle_target_heights.append(TOP_CATCH_Y)
		_gate_angles.append(0.0)
		_target_gate_angles.append(0.0)
		_gate_hold_timers.append(0.0)
		_bay_boards.append([])
		_bay_stack_heights.append(0.0)

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

func _setup_reference_cradle_visuals() -> void:
	_cradle_nodes = SorterCradleVisualBuilderScript.build(
		self, _cradle_nodes, num_bins, bin_width, TOP_CATCH_Y
	)
	var root: Node3D = get_node("CradleVisuals") as Node3D
	_cradle_plates_mm = root.get_node("TaperedForkPlates") as MultiMeshInstance3D
	_cradle_spines_mm = root.get_node("RearSpines") as MultiMeshInstance3D
	_cradle_shafts_mm = root.get_node("PivotShafts") as MultiMeshInstance3D
	_cradle_collars_mm = root.get_node("PivotCollars") as MultiMeshInstance3D

func _setup_physics_collision() -> void:
	var res := SorterCollisionBuilder.build(self, _gate_nodes)
	_floor_bed = res.floor_bed
	_cradle_bodies = res.cradle_bodies
	_gate_bodies = res.gate_bodies
	
	var infeed: Area3D = res.infeed_zone
	if infeed and not infeed.body_entered.is_connected(_on_infeed_body_entered):
		infeed.body_entered.connect(_on_infeed_body_entered)

func _setup_chain_system() -> void:
	_chain_system = SorterChainSystemScript.new()
	_chain_system.name = "SorterChainSystem"
	add_child(_chain_system)

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


func is_tracking_board(body: Node3D) -> bool:
	for data: SorterBoardTracker.BoardTrackingData in _tracked_boards:
		if data.board == body:
			return true
	return false

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

	var tracking: SorterBoardTracker.BoardTrackingData = SorterBoardTracker.BoardTrackingData.new()
	tracking.board = body as RigidBody3D
	tracking.target_bin = target_b
	tracking.infeed_time = Time.get_ticks_msec() / 1000.0
	# Keep the lumber fully dynamic. The synchronized overhead lugs provide the
	# horizontal force; no freezing, transform steering, or scripted velocity.
	var rigid_board: RigidBody3D = body as RigidBody3D
	rigid_board.contact_monitor = true
	rigid_board.max_contacts_reported = maxi(rigid_board.max_contacts_reported, 16)
	rigid_board.sleeping = false
	_tracked_boards.append(tracking)


func _board_has_stack_support(tracking: SorterBoardTracker.BoardTrackingData) -> bool:
	var bay: int = tracking.target_bin
	if bay < 0 or bay >= _cradle_bodies.size():
		return false
	for collider: Node3D in tracking.board.get_colliding_bodies():
		if collider == _cradle_bodies[bay]:
			return true
		for settled: Variant in _bay_boards[bay]:
			if is_instance_valid(settled) and collider == settled:
				return true
	return false


func _register_landed_board(tracking: SorterBoardTracker.BoardTrackingData) -> void:
	var bay: int = tracking.target_bin
	var board: RigidBody3D = tracking.board
	_bay_boards[bay].append(board)
	_bay_board_counts[bay] += 1
	var thickness: float = maxf(float(board.get("board_thickness")), 0.019)
	_bay_stack_heights[bay] += thickness
	# Index down by the actual lumber thickness. The already-landed rigid boards
	# ride the physical AnimatableBody3D arms down and remain stacked by contact.
	_cradle_target_heights[bay] = maxf(0.50, TOP_CATCH_Y - _bay_stack_heights[bay])


const TOP_SPROCKET_R: float = 0.3236068
const HAULOUT_SPROCKET_R: float = 0.100

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# The overhead and floor chains have independent load sensors. Park both
	# empty chains at startup; a board entering the sorter wakes the overhead
	# lugs immediately, while the haul-out waits for lumber on its own floor.
	var top_loaded: bool = not _tracked_boards.is_empty() or ConveyorLoadSensor.has_load(self,
		Vector3(-0.70, sorter_height - 0.40, -3.0),
		Vector3(num_bins * bin_width + 0.5, sorter_height + 0.65, 3.0), true, false)
	var haul_loaded: bool = ConveyorLoadSensor.has_load(self,
		Vector3(-0.5, -0.20, -2.3),
		Vector3(num_bins * bin_width + 0.5, 0.95, 2.3), true, false)
	if top_loaded:
		_top_empty_seconds = 0.0
	elif _top_active:
		_top_empty_seconds += delta
	# Index the empty overhead lugs to a repeatable inlet gap rather than
	# stopping at an arbitrary phase with a post standing under the next board.
	var top_phase: float = fposmod(_chain_system.current_top_dist, SorterChainSystem.TOP_PITCH * 5.0) if is_instance_valid(_chain_system) else 0.0
	var top_gap_clear: bool = top_phase < 0.045
	_top_active = top_loaded or (_top_active and (_top_empty_seconds < TOP_PARK_DELAY or not top_gap_clear))
	if haul_loaded:
		_haulout_empty_seconds = 0.0
	elif _haulout_active:
		_haulout_empty_seconds += delta
	_haulout_active = haul_loaded or (_haulout_active and _haulout_empty_seconds < CHAIN_IDLE_DELAY)
	var top_drive: float = conveyor_speed if _top_active else 0.0
	var haul_drive: float = haulout_speed if _haulout_active else 0.0
	# 1. Rotate shafts in sync with the actual chain travel (omega = v / R).
	var omega_top: float = top_drive / TOP_SPROCKET_R
	var omega_haul: float = haul_drive / HAULOUT_SPROCKET_R
	if is_instance_valid(_top_drive_shaft):
		_top_drive_shaft.rotate_z(omega_top * delta)
	if is_instance_valid(_top_tail_shaft):
		_top_tail_shaft.rotate_z(omega_top * delta)
	if is_instance_valid(_haulout_drive_shaft):
		_haulout_drive_shaft.rotate_z(omega_haul * delta)
	if is_instance_valid(_haulout_tail_shaft):
		_haulout_tail_shaft.rotate_z(omega_haul * delta)

	# 1b. Advance collision-driving lugs every physics tick. The 7,700 visual
	# chain transforms remain capped at 30 Hz, but the AnimatableBody3D lugs move
	# smoothly at physics rate so thin boards cannot tunnel through them.
	if is_instance_valid(_chain_system):
		_chain_system.advance_physics(top_drive * delta, haul_drive * delta)
		_chain_visual_elapsed += delta
		if (top_drive > 0.0 or haul_drive > 0.0) and _chain_visual_elapsed >= (1.0 / 30.0):
			_chain_system.refresh_visuals()
			_chain_visual_elapsed = fmod(_chain_visual_elapsed, 1.0 / 30.0)

	# 2. Update haul-out constant linear velocity
	if is_instance_valid(_floor_bed):
		_floor_bed.constant_linear_velocity = global_basis.x * haul_drive

	# 3. Track fully dynamic boards while physical overhead lugs push them. This
	# code only chooses/opens the target gate and records a landing after contact;
	# it never steers a transform or injects a velocity into a board.
	var i: int = _tracked_boards.size() - 1
	while i >= 0:
		var tracking: SorterBoardTracker.BoardTrackingData = _tracked_boards[i]
		if not is_instance_valid(tracking.board) or not tracking.active:
			_tracked_boards.remove_at(i)
			i -= 1
			continue

		var local_pos: Vector3 = to_local(tracking.board.global_position)
		var bay_x: float = float(tracking.target_bin) * bin_width
		if not tracking.gate_triggered and local_pos.x >= bay_x - bin_width * 0.10:
			tracking.gate_triggered = true
			_target_gate_angles[tracking.target_bin] = 0.85
			_gate_hold_timers[tracking.target_bin] = 3.0

		# Falling below the slide plane happens naturally after the physical gate
		# rotates away. Do not count the board until it actually touches the orange
		# cradle or a previously settled board in this bay.
		if tracking.gate_triggered and local_pos.y < sorter_height - 0.10:
			tracking.released = true
		if tracking.released and _board_has_stack_support(tracking):
			tracking.dropped_into_bay = true
			_register_landed_board(tracking)
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
					_bay_boards[b].clear()
					_bay_stack_heights[b] = 0.0
					_bay_discharging[b] = false
					_cradle_target_heights[b] = TOP_CATCH_Y

		# Smoothly interpolate cradle elevation
		_cradle_heights[b] = move_toward(_cradle_heights[b], _cradle_target_heights[b], indexing_speed * delta)

		# The replacement cradle marker lives in sorter-local space at its true
		# height; its four batched MultiMeshes follow the marker transform.
		if b < _cradle_nodes.size() and is_instance_valid(_cradle_nodes[b]):
			_cradle_nodes[b].position.y = _cradle_heights[b]
			SorterCradleVisualBuilderScript.update_bay(
				_cradle_plates_mm, _cradle_spines_mm, _cradle_shafts_mm,
				_cradle_collars_mm, b, _cradle_nodes[b].transform)

		# Update physical cradle collision support body
		if b < _cradle_bodies.size() and is_instance_valid(_cradle_bodies[b]):
			_cradle_bodies[b].position.y = _cradle_heights[b]
