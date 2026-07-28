@tool
class_name SawmillEdger
extends StaticBody3D

const SawmillEdgerAssemblyBuilder := preload("res://scripts/sawmill_edger_assembly_builder.gd")
const SawmillEdgerPartFactory := preload("res://scripts/edger_builders/edger_part_factory.gd")
const SawmillEdgerSceneCollector := preload("res://scripts/edger_builders/edger_scene_collector.gd")

## Industrial board edger sized for the sawmill board line.
## X is feed direction, Z is board-length/cross-machine width.

@export_category("Machine Geometry")
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

@export_range(2, 12, 1, "or_greater") var feed_roller_count: int = 7:
	set(value):
		feed_roller_count = maxi(value, 2)
		_queue_rebuild()

@export_range(0.2, 1.0, 0.01, "or_greater") var blade_radius: float = 0.38:
	set(value):
		blade_radius = maxf(value, 0.2)
		_queue_rebuild()

@export_category("Pin Geometry")
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

@export_category("Infeed")
@export var infeed_deck: Node3D = null

@export_range(0.0, 10.0, 0.05) var infeed_chain_extension: float = 5.6:
	set(value):
		infeed_chain_extension = maxf(value, 0.0)
		_queue_rebuild()

@export_category("Editor Preview")
@export var show_waste_chutes: bool = true:
	set(value):
		show_waste_chutes = value
		_queue_rebuild()


@export_category("Build System")
@export var expose_generated_parts: bool = true:
	set(value):
		expose_generated_parts = value
		if is_inside_tree():
			_adopt_generated_parts()

@export var auto_rebuild_generated_parts: bool = true

var _rebuild_queued := false
var _mat_frame: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_guard: StandardMaterial3D
var _mat_blade: StandardMaterial3D
var _mat_motor: StandardMaterial3D
var _mat_warning: StandardMaterial3D
var _mat_infeed_hold_down: Material
var _mat_wood: StandardMaterial3D
var _mat_hydraulic: StandardMaterial3D
var _mat_chain_grip: StandardMaterial3D
var _mat_rubber: StandardMaterial3D

@export_category("Board Physics")
@export var enable_board_physics_contacts: bool = true

const FEED_ROLLER_RADIUS := 0.075
const FEED_ROLLER_LENGTH := 1.14
const HOLD_DOWN_ROLLER_RADIUS := 0.095
const HOLD_DOWN_ROLLER_LENGTH := 0.96
const INFEED_HOLD_DOWN_ROLLER_RADIUS := 0.135
const INFEED_HOLD_DOWN_ROLLER_LENGTH := HOLD_DOWN_ROLLER_LENGTH * 0.5
const SAMPLE_BOARD_THICKNESS := 0.04
const SAMPLE_BOARD_LENGTH := 4.958
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

var _hold_down_stations: Array[Dictionary] = []
var _infeed_hold_down_stations: Array[Dictionary] = []
var _parking_ramp_stations: Array[Dictionary] = []
var _position_pin_stations: Array[Dictionary] = []
var _cushion_pin_stations: Array[Dictionary] = []
var _saw_blades: Array[CSGCylinder3D] = []
var _saw_teeth_roots: Array[Node3D] = []
var _pin_retract_delay_elapsed := 0.0
var _assembly_builder: RefCounted
var _part_factory: RefCounted
var _scene_collector: RefCounted
var _centering_board: RigidBody3D = null
var _centering_completed := false

@onready var infeed_system: EdgerInfeedSystem = $InfeedSystem
@onready var hold_down_system: EdgerHoldDownSystem = $HoldDownSystem
@onready var parking_ramp_system: EdgerParkingRampSystem = $ParkingRampSystem
@onready var pin_system: EdgerPinSystem = $PinSystem


func _ready() -> void:
	_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enable_board_physics_contacts:
		return
	_apply_real_board_contacts(delta)


func _apply_real_board_contacts(delta: float) -> void:
	var boards := _real_cut_boards()
	hold_down_system.update_infeed(delta, boards)
	hold_down_system.update(delta, boards)
	if boards.is_empty():
		return

	var boards_in_top_zone := _get_boards_in_top_zone()

	if is_instance_valid(_centering_board) and not _centering_completed:
		if _centering_board.global_position.z >= pin_system.position_pin_target_z:
			_pin_retract_delay_elapsed += delta
			if _pin_retract_delay_elapsed >= pin_system.retraction_delay:
				_centering_completed = true
		else:
			_pin_retract_delay_elapsed = 0.0

	if _centering_completed and not boards_in_top_zone.has(_centering_board):
		_centering_board = null
		_centering_completed = false
		_pin_retract_delay_elapsed = 0.0

	if not is_instance_valid(_centering_board):
		if not boards_in_top_zone.is_empty():
			_centering_board = boards_in_top_zone[0]
			_centering_completed = false

	parking_ramp_system.update(delta)
	pin_system.update_position_pins(delta)
	pin_system.update_cushion_pins(delta)

	_set_infeed_deck_pause(is_instance_valid(_centering_board))

	infeed_system.spin(delta)
	for body in boards:
		var local_center := to_local(body.global_position)
		if absf(local_center.z) > 4.5 or absf(local_center.y - working_height) > 0.6:
			continue
		if not _board_overlaps_x_range(local_center.x, _infeed_chain_start_x() - 0.35, bed_length * 0.5 + 0.55):
			continue
		body.sleeping = false
		parking_ramp_system.apply_edge_contacts(body, local_center)
		hold_down_system.apply_contacts(body, local_center)


func _real_cut_boards() -> Array[RigidBody3D]:
	var boards: Array[RigidBody3D] = []
	if not is_inside_tree():
		return boards
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var body := node as RigidBody3D
		if not is_instance_valid(body):
			continue
		if body.freeze:
			continue
		var local_center := to_local(body.global_position)
		if absf(local_center.z) > 4.5 or absf(local_center.y - working_height) > 1.2 or absf(local_center.x) > 6.0:
			continue
		boards.append(body)
	return boards





func _get_boards_in_top_zone() -> Array[RigidBody3D]:
	var boards_in_zone: Array[RigidBody3D] = []
	var deck = infeed_deck
	if not is_instance_valid(deck) and is_inside_tree():
		deck = get_parent().get_node_or_null("EdgerTakeAway")

	if is_instance_valid(deck):
		var top_zone = null
		if deck.has_method("get"):
			top_zone = deck.get("top_zone")
		else:
			top_zone = deck.top_zone if "top_zone" in deck else null

		if is_instance_valid(top_zone):
			for body in top_zone.get_overlapping_bodies():
				if body is RigidBody3D and (body.is_in_group("cut_boards") or "board" in body.name.to_lower()):
					boards_in_zone.append(body)

	return boards_in_zone







func _real_ramps_are_home(ramps: Array[Node3D]) -> bool:
	for ramp in ramps:
		if is_instance_valid(ramp) and absf(ramp.rotation.x - float(ramp.get_meta("retracted_angle", 0.0))) > PIN_READY_TOLERANCE:
			return false
	return true


func _parking_ramp_nodes() -> Array[Node3D]:
	var ramps: Array[Node3D] = []
	if not _parking_ramp_stations.is_empty():
		for station in _parking_ramp_stations:
			var nodes: Array = station["nodes"]
			for node in nodes:
				var ramp := node as Node3D
				if is_instance_valid(ramp):
					ramps.append(ramp)
		return ramps
	for node in find_children("ParkingRampPivot*", "Node3D", true, false):
		var ramp := node as Node3D
		if is_instance_valid(ramp):
			ramps.append(ramp)
	return ramps



func _board_overlaps_x_range(center_x: float, min_x: float, max_x: float) -> bool:
	var board_min_x := center_x - SAMPLE_BOARD_LENGTH * 0.5
	var board_max_x := center_x + SAMPLE_BOARD_LENGTH * 0.5
	return board_max_x >= min_x and board_min_x <= max_x


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
	if _scene_collector == null:
		_scene_collector = SawmillEdgerSceneCollector.new(self)

	if Engine.is_editor_hint() and not auto_rebuild_generated_parts and get_child_count() > 0:
		_scene_collector.collect_generated_parts()
		if (is_instance_valid(infeed_system) and not infeed_system.feed_rollers.is_empty()) or not _saw_blades.is_empty():
			return

	_part_factory = SawmillEdgerPartFactory.new(self)
	_part_factory._preserve_editor_group_transforms()
	for child in get_children():
		if child.get_meta("edger_controller", false):
			continue
		if Engine.is_editor_hint():
			remove_child(child)
		child.queue_free()

	if is_instance_valid(infeed_system):
		infeed_system.clear()
	_hold_down_stations.clear()
	_infeed_hold_down_stations.clear()
	_parking_ramp_stations.clear()
	_position_pin_stations.clear()
	_cushion_pin_stations.clear()
	_saw_blades.clear()
	_saw_teeth_roots.clear()

	_make_materials()
	_assembly_builder = SawmillEdgerAssemblyBuilder.new(self, _part_factory)
	_build_frame()
	_build_feed_deck()
	_build_hold_downs()
	_build_saw_box()
	_build_motors_and_drives()
	_build_waste_handling()
	_adopt_generated_parts()


func _adopt_generated_parts() -> void:
	if not Engine.is_editor_hint() or not expose_generated_parts or not is_inside_tree():
		return

	var scene_root := get_tree().edited_scene_root
	if scene_root == null or scene_root != self:
		return

	for child in get_children():
		if child.get_meta("edger_editor_group", false):
			child.owner = scene_root


func _make_materials() -> void:
	_mat_frame = _mat(Color(0.30, 0.32, 0.34), 0.85, 0.34)
	_mat_dark = _mat(Color(0.13, 0.14, 0.15), 0.75, 0.42)
	_mat_guard = _mat(Color(0.20, 0.46, 0.28), 0.55, 0.36)
	_mat_blade = _mat(Color(0.72, 0.72, 0.76), 1.0, 0.16)
	_mat_motor = _mat(Color(0.08, 0.23, 0.34), 0.70, 0.30)
	_mat_warning = _mat(Color(0.95, 0.55, 0.06), 0.55, 0.35)
	_mat_infeed_hold_down = _worn_green_roller_mat()
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


func _worn_green_roller_mat() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.035, 0.20, 0.085, 1.0);
uniform vec4 worn_color : source_color = vec4(0.38, 0.43, 0.34, 1.0);
uniform vec4 dark_scuff_color : source_color = vec4(0.015, 0.045, 0.025, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float long_wear = smoothstep(0.72, 0.92, hash(floor(vec2(uv.x * 18.0, uv.y * 5.0))));
	float fine_scuffs = smoothstep(0.52, 0.86, hash(floor(vec2(uv.x * 55.0, uv.y * 16.0))));
	float rubbed_bands = pow(abs(sin((uv.y * 8.0 + uv.x * 2.0) * 3.14159)), 12.0) * 0.35;
	float wear = clamp(long_wear * 0.45 + fine_scuffs * 0.18 + rubbed_bands, 0.0, 0.72);
	vec3 paint = mix(base_color.rgb, worn_color.rgb, wear);
	float dark_scuffs = smoothstep(0.88, 0.98, hash(floor(vec2(uv.x * 32.0 + 9.0, uv.y * 11.0))));
	ALBEDO = mix(paint, dark_scuff_color.rgb, dark_scuffs * 0.22);
	METALLIC = 0.45;
	ROUGHNESS = 0.48 + wear * 0.26;
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	return material





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



func _board_center_y() -> float:
	return _support_top_y() + SAMPLE_BOARD_THICKNESS * 0.5 + 0.004



func _support_top_y() -> float:
	return working_height + 0.04 + FEED_ROLLER_RADIUS


func _machine_infeed_entry_x() -> float:
	return -bed_length * 0.5 + 0.34


func _centering_section_end_x() -> float:
	return _machine_infeed_entry_x() - 0.14


func _infeed_chain_start_x() -> float:
	return -bed_length * 0.5 + 0.34 - infeed_chain_extension








# ── Runtime Centering Cycle State Machine ───────────────────────────────────



func _set_infeed_deck_pause(paused: bool) -> void:
	var deck = infeed_deck
	if not is_instance_valid(deck) and is_inside_tree():
		deck = get_parent().get_node_or_null("EdgerTakeAway")
	if is_instance_valid(deck) and (deck.name == "EdgerTakeAway" or deck.has_method("set_running") or "external_stop" in deck):
		if deck.get("external_stop") != paused:
			deck.set("external_stop", paused)






func _get_board_local_z_bounds_for_body(board: RigidBody3D) -> Vector2:
	if not is_instance_valid(board):
		return Vector2(-SAMPLE_BOARD_WIDTH * 0.5, SAMPLE_BOARD_WIDTH * 0.5)

	var col_shape := board.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape != null and col_shape.shape != null:
		var parent_node := col_shape.get_parent() as Node3D
		if col_shape.shape is BoxShape3D:
			var box := col_shape.shape as BoxShape3D
			var sz := box.size
			var corners := [
				Vector3(-sz.x * 0.5, -sz.y * 0.5, -sz.z * 0.5),
				Vector3(sz.x * 0.5, -sz.y * 0.5, -sz.z * 0.5),
				Vector3(-sz.x * 0.5, sz.y * 0.5, -sz.z * 0.5),
				Vector3(sz.x * 0.5, sz.y * 0.5, -sz.z * 0.5),
				Vector3(-sz.x * 0.5, -sz.y * 0.5, sz.z * 0.5),
				Vector3(sz.x * 0.5, -sz.y * 0.5, sz.z * 0.5),
				Vector3(-sz.x * 0.5, sz.y * 0.5, sz.z * 0.5),
				Vector3(sz.x * 0.5, sz.y * 0.5, sz.z * 0.5),
			]
			var min_z := INF
			var max_z := -INF
			for pt in corners:
				var global_pt := parent_node.to_global(pt)
				var local_pt := to_local(global_pt)
				min_z = minf(min_z, local_pt.z)
				max_z = maxf(max_z, local_pt.z)
			return Vector2(min_z, max_z)
		elif col_shape.shape is ConvexPolygonShape3D:
			var convex := col_shape.shape as ConvexPolygonShape3D
			var min_z := INF
			var max_z := -INF
			for pt in convex.points:
				var global_pt := parent_node.to_global(pt)
				var local_pt := to_local(global_pt)
				min_z = minf(min_z, local_pt.z)
				max_z = maxf(max_z, local_pt.z)
			if min_z < max_z:
				return Vector2(min_z, max_z)

	var local_center := to_local(board.global_position)
	return Vector2(local_center.z - SAMPLE_BOARD_WIDTH * 0.5, local_center.z + SAMPLE_BOARD_WIDTH * 0.5)





func _get_board_thickness_for_body(board: RigidBody3D) -> float:
	if not is_instance_valid(board):
		return SAMPLE_BOARD_THICKNESS
	var col_shape := board.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape != null and col_shape.shape != null:
		if col_shape.shape is BoxShape3D:
			return (col_shape.shape as BoxShape3D).size.y
		elif col_shape.shape is ConvexPolygonShape3D:
			var convex := col_shape.shape as ConvexPolygonShape3D
			var min_y := INF
			var max_y := -INF
			for p in convex.points:
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
			if min_y < max_y:
				return max_y - min_y
	return SAMPLE_BOARD_THICKNESS
