@tool
class_name SawmillEdger
extends StaticBody3D

const SawmillEdgerAssemblyBuilder := preload("res://scripts/sawmill_edger_assembly_builder.gd")
const SawmillEdgerPreviewController := preload("res://scripts/edger_preview_controller.gd")

## Industrial board edger sized for the sawmill board line.
## X is feed direction, Z is board-length/cross-machine width.

@export_category("Layout")
@export_range(2.0, 8.0, 0.1, "or_greater") var bed_length: float = 4.8:
	set(value):
		bed_length = maxf(value, 2.0)
		_queue_rebuild()

@export_range(0.8, 3.0, 0.05, "or_greater") var machine_width: float = 1.7:
	set(value):
		machine_width = maxf(value, 0.8)
		_queue_rebuild()

@export_range(0.3, 1.5, 0.05, "or_greater") var working_height: float = 0.62:
	set(value):
		working_height = maxf(value, 0.3)
		_queue_rebuild()

@export_range(0.2, 1.2, 0.01, "or_greater") var saw_spacing: float = 0.82:
	set(value):
		saw_spacing = maxf(value, 0.2)
		_queue_rebuild()

@export_category("Detail")
@export_range(2, 12, 1, "or_greater") var feed_roller_count: int = 7:
	set(value):
		feed_roller_count = maxi(value, 2)
		_queue_rebuild()

@export_range(0.2, 1.0, 0.01, "or_greater") var blade_radius: float = 0.38:
	set(value):
		blade_radius = maxf(value, 0.2)
		_queue_rebuild()

@export var show_waste_chutes: bool = true:
	set(value):
		show_waste_chutes = value
		_queue_rebuild()

@export_category("Infeed Centering")
@export_range(0.0, 10.0, 0.05) var infeed_chain_extension: float = 5.6:
	set(value):
		infeed_chain_extension = maxf(value, 0.0)
		_queue_rebuild()

@export var preview_board_scene: PackedScene = preload("res://scenes/cut_board.tscn"):
	set(value):
		preview_board_scene = value
		_queue_rebuild()

@export_range(0.02, 0.30, 0.01) var position_pin_radius: float = 0.045:
	set(value):
		position_pin_radius = maxf(value, 0.02)
		_queue_rebuild()

@export_range(0.05, 0.60, 0.01) var position_pin_height: float = 0.26:
	set(value):
		position_pin_height = maxf(value, 0.05)
		_queue_rebuild()

@export_range(0.20, 4.0, 0.01, "or_greater") var position_pin_spacing: float = 1.56:
	set(value):
		position_pin_spacing = maxf(value, 0.20)
		_queue_rebuild()

@export_range(0.05, 1.0, 0.01) var cushion_pin_extension: float = 0.46:
	set(value):
		cushion_pin_extension = maxf(value, 0.05)
		_queue_rebuild()

@export_range(0.20, 4.0, 0.01, "or_greater") var cushion_pin_spacing: float = 1.56:
	set(value):
		cushion_pin_spacing = maxf(value, 0.20)
		_queue_rebuild()

@export_range(2, 8, 1) var parking_ramp_stations: int = 4:
	set(value):
		parking_ramp_stations = clampi(value, 2, 8)
		_queue_rebuild()

@export_category("Generated Parts")
@export var expose_generated_parts: bool = true:
	set(value):
		expose_generated_parts = value
		if is_inside_tree():
			_adopt_generated_parts()

@export var auto_rebuild_generated_parts: bool = true
@export var use_saved_assembly_scenes: bool = false:
	set(value):
		use_saved_assembly_scenes = value
		_queue_rebuild()

@export var frame_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/frame_assembly.tscn")
@export var side_fence_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/side_fence_assembly.tscn")
@export var infeed_chain_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/infeed_chain_assembly.tscn")
@export var parking_ramp_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/parking_ramp_assembly.tscn")
@export var infeed_hold_down_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/infeed_hold_down_roller_assembly.tscn")
@export var position_pin_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/position_pin_assembly.tscn")
@export var cushion_pin_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/cushion_pin_assembly.tscn")
@export var lower_feed_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/lower_feed_roller_assembly.tscn")
@export var upper_hold_down_roller_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/upper_hold_down_roller_assembly.tscn")
@export var saw_blade_and_guard_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/saw_blade_and_guard_assembly.tscn")
@export var motor_drive_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/motor_drive_assembly.tscn")
@export var waste_handling_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/waste_handling_assembly.tscn")
@export var reference_board_assembly_scene: PackedScene = preload("res://scenes/edger_assemblies/reference_board_assembly.tscn")

var _rebuild_queued := false
var _mat_frame: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_guard: StandardMaterial3D
var _mat_blade: StandardMaterial3D
var _mat_motor: StandardMaterial3D
var _mat_warning: StandardMaterial3D
var _mat_infeed_hold_down: StandardMaterial3D
var _mat_roller_stripe: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_hydraulic: StandardMaterial3D
var _mat_chain_grip: StandardMaterial3D
var _mat_rubber: StandardMaterial3D

@export_category("Editor Test")
@export var run_editor_preview: bool = false:
	set(value):
		run_editor_preview = value
		if is_inside_tree():
			set_process(run_editor_preview)
			if not run_editor_preview:
				_reset_preview_motion()

@export_category("Motion")
@export_range(0.1, 8.0, 0.1, "or_greater") var infeed_chain_feed_speed: float = 1.4
@export_range(0.0, 20.0, 0.1, "or_greater") var feed_roller_spin_speed: float = 1.0
@export_range(0.0, 80.0, 0.1, "or_greater") var blade_spin_speed: float = 18.0
@export_range(0.0, 2.0, 0.01, "or_greater") var hold_down_raised_offset: float = 0.24
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_lower_speed: float = 0.55
@export_range(0.0, 4.0, 0.01, "or_greater") var hold_down_raise_speed: float = 0.72
@export_range(0.0, 8.0, 0.01, "or_greater") var parking_ramp_speed: float = 1.8
@export_range(0.0, 8.0, 0.01, "or_greater") var position_pin_speed: float = 1.6
@export_range(0.0, 8.0, 0.01, "or_greater") var cushion_pin_speed: float = 2.2
@export_range(0.0, 4.0, 0.01, "or_greater") var centering_board_speed: float = 0.28
@export_range(0.0, 2.0, 0.01, "or_greater") var pin_retract_delay: float = 0.20
@export_range(0.0, 2.0, 0.01, "or_greater") var feed_chain_start_delay: float = 0.22
@export_range(-4.0, 0.0, 0.01) var side_load_start_z: float = -1.12

const FEED_ROLLER_RADIUS := 0.075
const FEED_ROLLER_LENGTH := 1.14
const HOLD_DOWN_ROLLER_RADIUS := 0.095
const HOLD_DOWN_ROLLER_LENGTH := 0.96
const INFEED_HOLD_DOWN_ROLLER_RADIUS := 0.135
const INFEED_HOLD_DOWN_ROLLER_LENGTH := HOLD_DOWN_ROLLER_LENGTH * 0.5
const SAMPLE_BOARD_THICKNESS := 0.04
const SAMPLE_BOARD_LENGTH := 4.8768
const SAMPLE_BOARD_WIDTH := 0.35
const SAW_X := -0.18
const INFEED_CHAIN_END_X := SAW_X - 0.18
const CHAIN_LINK_LENGTH := 0.13
const CHAIN_LINK_WIDTH := SAMPLE_BOARD_WIDTH * 0.25
const CHAIN_LINK_THICKNESS := 0.028
const CHAIN_LANE_CLEARANCE := 0.004
const CHAIN_GRIP_TOOTH_HEIGHT := 0.035
const CHAIN_GRIP_TOOTH_LENGTH := 0.055
const CHAIN_GRIP_TOOTH_WIDTH := CHAIN_LINK_WIDTH * 0.42
const HOLD_DOWN_LEAD_IN := 0.08
const PIN_BOARD_CLEARANCE := 0.05
const PIN_BOARD_X_CONTACT_MARGIN := 0.02
const PIN_READY_TOLERANCE := 0.01
const CENTERING_TOLERANCE := 0.01
const CUSHION_PAD_CONTACT_OFFSET_Z := -0.08 - 0.0225

enum CenteringPreviewPhase {
	SIDE_LOAD,
	RAISE_PINS,
	CENTER_BOARD,
	PIN_RETRACT_DELAY,
	RETRACT_PINS,
	RETURN_PINS_HOME_Z,
	LOWER_RAMPS,
	FEED_DELAY,
	FEED_BOARD,
}

var _feed_rollers: Array[CSGCylinder3D] = []
var _infeed_chain_links: Array[Node3D] = []
var _infeed_chain_bases: Array[Vector3] = []
var _hold_down_rollers: Array[CSGCylinder3D] = []
var _hold_down_stations: Array[Dictionary] = []
var _infeed_hold_down_rollers: Array[CSGCylinder3D] = []
var _infeed_hold_down_stations: Array[Dictionary] = []
var _parking_ramp_stations: Array[Dictionary] = []
var _position_pin_stations: Array[Dictionary] = []
var _cushion_pin_stations: Array[Dictionary] = []
var _saw_blades: Array[CSGCylinder3D] = []
var _saw_teeth_roots: Array[Node3D] = []
var _sample_board: Node3D
var _feed_preview_travel := 0.0
var _feed_delay_elapsed := 0.0
var _pin_retract_delay_elapsed := 0.0
var _chain_preview_offset := 0.0
var _centering_preview_phase := CenteringPreviewPhase.SIDE_LOAD
var _active_centering_pin_indices: Array[int] = []
var _preview_board_home_global := Vector3.ZERO
var _generated_name_counts: Dictionary = {}
var _editor_group_stack: Array[Node3D] = []
var _preserved_editor_group_transforms: Dictionary = {}
var _assembly_builder: RefCounted
var _preview_controller: RefCounted


func _ready() -> void:
	_rebuild()
	set_process(run_editor_preview)


func _process(delta: float) -> void:
	if not run_editor_preview:
		return
	_apply_preview_motion(delta)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and not auto_rebuild_generated_parts:
		return
	if not Engine.is_editor_hint():
		_rebuild()
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	await get_tree().process_frame
	_rebuild_queued = false
	_rebuild()


func _rebuild() -> void:
	if Engine.is_editor_hint() and not auto_rebuild_generated_parts and get_child_count() > 0:
		_collect_generated_parts()
		if not _feed_rollers.is_empty() or not _saw_blades.is_empty() or not _infeed_chain_links.is_empty():
			return

	_preserve_editor_group_transforms()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_hold_down_stations.clear()
	_infeed_hold_down_rollers.clear()
	_infeed_hold_down_stations.clear()
	_parking_ramp_stations.clear()
	_position_pin_stations.clear()
	_cushion_pin_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null
	_generated_name_counts.clear()
	_editor_group_stack.clear()

	_make_materials()
	_assembly_builder = SawmillEdgerAssemblyBuilder.new(self)
	_preview_controller = SawmillEdgerPreviewController.new(self)
	if use_saved_assembly_scenes:
		_instantiate_saved_assembly_scenes()
		_collect_generated_parts()
	else:
		_build_frame()
		_build_feed_deck()
		_build_hold_downs()
		_build_saw_box()
		_build_motors_and_drives()
		_build_waste_handling()
		_build_sample_board()
	_adopt_generated_parts()
	_apply_preview_motion(0.0)


func _instantiate_saved_assembly_scenes() -> void:
	var assembly_scenes: Array[PackedScene] = [
		frame_assembly_scene,
		side_fence_assembly_scene,
		infeed_chain_assembly_scene,
		parking_ramp_assembly_scene,
		infeed_hold_down_roller_assembly_scene,
		position_pin_assembly_scene,
		cushion_pin_assembly_scene,
		lower_feed_roller_assembly_scene,
		upper_hold_down_roller_assembly_scene,
		saw_blade_and_guard_assembly_scene,
		motor_drive_assembly_scene,
		waste_handling_assembly_scene,
		reference_board_assembly_scene,
	]

	for assembly_scene in assembly_scenes:
		if assembly_scene == null:
			continue
		var instance := assembly_scene.instantiate()
		if _preserved_editor_group_transforms.has(instance.name):
			instance.transform = _preserved_editor_group_transforms[instance.name]
		add_child(instance)
		_adopt_new_node(instance)


func _collect_generated_parts() -> void:
	_feed_rollers.clear()
	_infeed_chain_links.clear()
	_infeed_chain_bases.clear()
	_hold_down_rollers.clear()
	_infeed_hold_down_rollers.clear()
	_infeed_hold_down_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()
	_sample_board = null

	for node in find_children("*", "Node3D", true, false):
		if node.name.begins_with("FeedRoller") and node is CSGCylinder3D:
			_feed_rollers.append(node)
		elif node.name.begins_with("InfeedChainLink"):
			_infeed_chain_links.append(node)
			_infeed_chain_bases.append(node.position)
		elif node.name.begins_with("HoldDownRoller") and node is CSGCylinder3D:
			_hold_down_rollers.append(node)
		elif node.name.begins_with("InfeedHoldDownRoller") and node is CSGCylinder3D:
			_infeed_hold_down_rollers.append(node)
		elif node.name.begins_with("EdgerSawBlade") and node is CSGCylinder3D:
			_saw_blades.append(node)
		elif node.name.begins_with("EdgerSawTeeth"):
			_saw_teeth_roots.append(node)
		elif node.name.begins_with("ReferenceCutBoard") and node is Node3D:
			_sample_board = node


func _adopt_generated_parts() -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return

	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return

	for child in get_children():
		if child.get_meta("edger_editor_group", false):
			child.owner = scene_root


func _preserve_editor_group_transforms() -> void:
	_preserved_editor_group_transforms.clear()
	for child in get_children():
		if child is Node3D and child.get_meta("edger_editor_group", false):
			_preserved_editor_group_transforms[child.name] = child.transform


func _make_materials() -> void:
	_mat_frame = _mat(Color(0.30, 0.32, 0.34), 0.85, 0.34)
	_mat_dark = _mat(Color(0.13, 0.14, 0.15), 0.75, 0.42)
	_mat_guard = _mat(Color(0.20, 0.46, 0.28), 0.55, 0.36)
	_mat_blade = _mat(Color(0.72, 0.72, 0.76), 1.0, 0.16)
	_mat_motor = _mat(Color(0.08, 0.23, 0.34), 0.70, 0.30)
	_mat_warning = _mat(Color(0.95, 0.55, 0.06), 0.55, 0.35)
	_mat_infeed_hold_down = _mat(Color(0.05, 0.24, 0.11), 0.55, 0.34)
	_mat_roller_stripe = _mat(Color(0.92, 0.93, 0.88), 0.25, 0.24)
	_mat_wood = _mat(Color(0.78, 0.64, 0.42), 0.0, 0.78)
	_mat_hydraulic = _mat(Color(0.86, 0.86, 0.88), 1.0, 0.12)
	_mat_chain_grip = _mat(Color(0.42, 0.44, 0.44), 0.9, 0.22)
	_mat_rubber = _mat(Color(0.03, 0.03, 0.035), 0.0, 0.55)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _push_editor_group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	group.set_meta("edger_editor_group", true)
	if _preserved_editor_group_transforms.has(group_name):
		group.transform = _preserved_editor_group_transforms[group_name]
	_current_part_parent().add_child(group)
	_adopt_new_node(group)
	_editor_group_stack.append(group)
	return group


func _pop_editor_group() -> void:
	if not _editor_group_stack.is_empty():
		_editor_group_stack.pop_back()


func _current_part_parent() -> Node:
	if _editor_group_stack.is_empty():
		return self
	return _editor_group_stack.back()


func _build_frame() -> void:
	_assembly_builder.build_frame()


func _build_feed_deck() -> void:
	_assembly_builder.build_feed_deck()


func _build_infeed_chains() -> void:
	_assembly_builder.build_infeed_chains()


func _build_parking_ramps(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_parking_ramps(chain_start, chain_end, chain_top)


func _build_infeed_hold_downs(chain_start: float, chain_end: float) -> void:
	_assembly_builder.build_infeed_hold_downs(chain_start, chain_end)


func _build_position_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_position_pins(chain_start, chain_end, chain_top)


func _build_cushion_pins(chain_start: float, chain_end: float, chain_top: float) -> void:
	_assembly_builder.build_cushion_pins(chain_start, chain_end, chain_top)


func _build_hold_downs() -> void:
	_assembly_builder.build_hold_downs()


func _build_saw_box() -> void:
	_assembly_builder.build_saw_box()


func _build_motors_and_drives() -> void:
	_assembly_builder.build_motors_and_drives()


func _build_waste_handling() -> void:
	_assembly_builder.build_waste_handling()


func _build_sample_board() -> void:
	_assembly_builder.build_sample_board()

func _create_reference_board() -> Node3D:
	var board: Node3D = null
	if preview_board_scene:
		board = preview_board_scene.instantiate() as Node3D
	if board == null:
		board = _create_fallback_reference_board()
	board.name = "ReferenceCutBoard"
	board.set_script(null)
	if board is RigidBody3D:
		var rigid := board as RigidBody3D
		rigid.freeze = true
		rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid.linear_velocity = Vector3.ZERO
		rigid.angular_velocity = Vector3.ZERO
		rigid.collision_layer = 0
		rigid.collision_mask = 0
	board.set_process(false)
	board.set_physics_process(false)
	return board


func _create_fallback_reference_board() -> Node3D:
	var body := Node3D.new()
	body.name = "ReferenceCutBoardFallback"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(SAMPLE_BOARD_LENGTH, SAMPLE_BOARD_THICKNESS, SAMPLE_BOARD_WIDTH)
	box.material = _mat_wood
	mesh.mesh = box
	body.add_child(mesh)
	return body


func _board_center_y() -> float:
	return _support_top_y() + SAMPLE_BOARD_THICKNESS * 0.5 + 0.004


func _support_top_y() -> float:
	return working_height + 0.04 + FEED_ROLLER_RADIUS


func _infeed_chain_start_x() -> float:
	return -bed_length * 0.5 + 0.34 - infeed_chain_extension


func _machine_infeed_entry_x() -> float:
	return -bed_length * 0.5 + 0.34


func _centering_section_end_x() -> float:
	return _machine_infeed_entry_x() - 0.14


func _preview_board_start_x() -> float:
	return _infeed_chain_start_x() + SAMPLE_BOARD_LENGTH * 0.5


func _feed_preview_length() -> float:
	return bed_length + infeed_chain_extension + SAMPLE_BOARD_LENGTH * 0.5


func _ensure_preview_controller() -> void:
	if _preview_controller == null:
		_preview_controller = SawmillEdgerPreviewController.new(self)


func _apply_preview_motion(delta: float) -> void:
	_ensure_preview_controller()
	_preview_controller.apply_preview_motion(delta)


func _reset_preview_motion() -> void:
	_ensure_preview_controller()
	_preview_controller.reset_preview_motion()

func _add_infeed_chain_link(node_name: String, local_position: Vector3, index: int) -> Node3D:
	var link_root := Node3D.new()
	link_root.name = node_name
	link_root.position = local_position
	_current_part_parent().add_child(link_root)
	_adopt_new_node(link_root)

	var link_length := CHAIN_LINK_LENGTH * 0.72
	var side_plate_width := CHAIN_LINK_WIDTH * 0.22
	var side_plate_z := CHAIN_LINK_WIDTH * 0.5 - side_plate_width * 0.5
	_add_box_child(link_root, "OuterPlate_L", Vector3(0.0, 0.0, -side_plate_z), Vector3(link_length, CHAIN_LINK_THICKNESS, side_plate_width), _mat_dark)
	_add_box_child(link_root, "OuterPlate_R", Vector3(0.0, 0.0, side_plate_z), Vector3(link_length, CHAIN_LINK_THICKNESS, side_plate_width), _mat_dark)
	_add_box_child(link_root, "CenterPad", Vector3(0.0, CHAIN_LINK_THICKNESS * 0.18, 0.0), Vector3(link_length * 0.54, CHAIN_LINK_THICKNESS * 0.55, CHAIN_LINK_WIDTH * 0.42), _mat_chain_grip)
	_add_cylinder_child(link_root, "CrossPin", Vector3(0.0, -CHAIN_LINK_THICKNESS * 0.05, 0.0), 0.011, CHAIN_LINK_WIDTH + 0.02, _mat_hydraulic, Vector3(PI * 0.5, 0.0, 0.0), 10)

	var tooth_mesh := _create_chain_grip_tooth_mesh()
	var tooth_xs: Array[float] = [-link_length * 0.22, link_length * 0.22]
	for tooth_i in range(tooth_xs.size()):
		var tooth := MeshInstance3D.new()
		tooth.name = "GripTooth_%02d" % (tooth_i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = _mat_chain_grip
		tooth.position = Vector3(tooth_xs[tooth_i], CHAIN_LINK_THICKNESS * 0.5, 0.0)
		tooth.rotation.y = PI if (index + tooth_i) % 2 == 1 else 0.0
		link_root.add_child(tooth)
		_adopt_new_node(tooth)

	return link_root


func _add_box_child(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = local_position
	box.size = size
	box.material = material
	box.use_collision = true
	parent.add_child(box)
	_adopt_new_node(box)
	return box


func _add_cylinder_child(parent: Node3D, node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = node_name
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = true
	parent.add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _add_roller_motion_stripe(roller: Node3D, radius: float, length: float) -> void:
	var stripe := CSGBox3D.new()
	stripe.name = "RollerMotionStripe"
	stripe.position = Vector3(0.0, 0.0, radius + 0.004)
	stripe.size = Vector3(0.026, length * 0.92, 0.010)
	stripe.material = _mat_roller_stripe
	stripe.use_collision = false
	roller.add_child(stripe)
	_adopt_new_node(stripe)


func _create_chain_grip_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var half_l := CHAIN_GRIP_TOOTH_LENGTH * 0.5
	var half_w := CHAIN_GRIP_TOOTH_WIDTH * 0.5
	var front := [
		Vector3(-half_l, 0.0, half_w),
		Vector3(half_l, 0.0, half_w),
		Vector3(half_l * 0.35, CHAIN_GRIP_TOOTH_HEIGHT, half_w),
		Vector3(-half_l * 0.75, CHAIN_GRIP_TOOTH_HEIGHT * 0.28, half_w),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_w))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_saw_teeth(node_name: String, center: Vector3, radius: float) -> Node3D:
	var teeth_root := Node3D.new()
	teeth_root.name = node_name
	teeth_root.position = center
	_current_part_parent().add_child(teeth_root)
	_adopt_new_node(teeth_root)

	var tooth_mesh := _create_saw_tooth_mesh()
	var tooth_count := 48
	var tooth_root_radius := radius - 0.012
	for i in range(tooth_count):
		var angle := TAU * float(i) / float(tooth_count)
		var tooth := MeshInstance3D.new()
		tooth.name = "Tooth_%02d" % (i + 1)
		tooth.mesh = tooth_mesh
		tooth.material_override = _mat_blade
		tooth.position = Vector3(cos(angle) * tooth_root_radius, sin(angle) * tooth_root_radius, 0.0)
		tooth.rotation = Vector3(0.0, 0.0, angle)
		teeth_root.add_child(tooth)
		_adopt_new_node(tooth)
	return teeth_root


func _create_saw_tooth_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var tooth_depth := 0.055
	var tangential_root := 0.026
	var tangential_tip := 0.006
	var half_thickness := 0.018
	var front := [
		Vector3(0.0, -tangential_root, half_thickness),
		Vector3(tooth_depth * 0.70, -tangential_tip, half_thickness),
		Vector3(tooth_depth, tangential_tip, half_thickness),
		Vector3(0.0, tangential_root, half_thickness),
	]
	var back := []
	for point in front:
		back.append(Vector3(point.x, point.y, -half_thickness))

	_add_mesh_face(vertices, normals, indices, front, Vector3(0, 0, 1))
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	_add_mesh_face(vertices, normals, indices, reversed_back, Vector3(0, 0, -1))
	for i in range(front.size()):
		var next_i := (i + 1) % front.size()
		_add_mesh_quad(vertices, normals, indices, front[i], front[next_i], back[next_i], back[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh_face(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, points: Array, normal: Vector3) -> void:
	var start := vertices.size()
	for point in points:
		vertices.append(point)
		normals.append(normal)
	for i in range(1, points.size() - 1):
		indices.append_array(PackedInt32Array([start, start + i, start + i + 1]))


func _add_mesh_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var start := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _add_box(node_name: String, local_position: Vector3, size: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO, collision: bool = true) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = _friendly_part_name(node_name, local_position)
	box.position = local_position
	box.rotation = local_rotation
	box.size = size
	box.material = material
	box.use_collision = collision
	_current_part_parent().add_child(box)
	_adopt_new_node(box)
	return box


func _add_cylinder(node_name: String, local_position: Vector3, radius: float, height: float, material: Material, local_rotation: Vector3, sides: int, collision: bool = true) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = _friendly_part_name(node_name, local_position)
	cylinder.position = local_position
	cylinder.rotation = local_rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = collision
	_current_part_parent().add_child(cylinder)
	_adopt_new_node(cylinder)
	return cylinder


func _adopt_new_node(node: Node) -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return
	if not node.get_meta("edger_editor_group", false):
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root != null and node != scene_root:
		node.owner = scene_root


func _friendly_part_name(base_name: String, local_position: Vector3) -> String:
	var name := "%s_%s" % [base_name, _position_name_suffix(local_position)]
	name = name.replace("__", "_").strip_edges(false, true)
	var used_count := int(_generated_name_counts.get(name, 0)) + 1
	_generated_name_counts[name] = used_count
	if used_count > 1:
		name = "%s_%02d" % [name, used_count]
	return name


func _position_name_suffix(local_position: Vector3) -> String:
	var parts: Array[String] = []
	if local_position.x < -0.18:
		parts.append("Infeed")
	elif local_position.x > 0.18:
		parts.append("Outfeed")
	else:
		parts.append("CenterX")

	if local_position.z < -0.08:
		parts.append("Front")
	elif local_position.z > 0.08:
		parts.append("Back")
	else:
		parts.append("CenterZ")

	if local_position.y < working_height - 0.12:
		parts.append("Lower")
	elif local_position.y > working_height + 0.32:
		parts.append("Upper")
	else:
		parts.append("Mid")

	return "_".join(PackedStringArray(parts))
