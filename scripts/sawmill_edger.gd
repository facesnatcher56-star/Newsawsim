@tool
class_name SawmillEdger
extends StaticBody3D

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

var _rebuild_queued := false
var _mat_frame: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_guard: StandardMaterial3D
var _mat_blade: StandardMaterial3D
var _mat_motor: StandardMaterial3D
var _mat_warning: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_hydraulic: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree():
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
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_make_materials()
	_build_frame()
	_build_feed_deck()
	_build_hold_downs()
	_build_saw_box()
	_build_motors_and_drives()
	_build_waste_handling()
	_build_sample_board()


func _make_materials() -> void:
	_mat_frame = _mat(Color(0.30, 0.32, 0.34), 0.85, 0.34)
	_mat_dark = _mat(Color(0.13, 0.14, 0.15), 0.75, 0.42)
	_mat_guard = _mat(Color(0.20, 0.46, 0.28), 0.55, 0.36)
	_mat_blade = _mat(Color(0.72, 0.72, 0.76), 1.0, 0.16)
	_mat_motor = _mat(Color(0.08, 0.23, 0.34), 0.70, 0.30)
	_mat_warning = _mat(Color(0.95, 0.55, 0.06), 0.55, 0.35)
	_mat_wood = _mat(Color(0.78, 0.64, 0.42), 0.0, 0.78)
	_mat_hydraulic = _mat(Color(0.86, 0.86, 0.88), 1.0, 0.12)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _build_frame() -> void:
	var half_l := bed_length * 0.5
	var half_w := machine_width * 0.5
	var leg_y := working_height * 0.5 - 0.34
	var leg_h := maxf(working_height + 0.28, 0.7)
	var end_xs: Array[float] = [-half_l + 0.28, half_l - 0.28]
	var side_zs: Array[float] = [-half_w + 0.12, half_w - 0.12]

	for x in end_xs:
		for z in side_zs:
			_add_box("Leg", Vector3(x, leg_y, z), Vector3(0.12, leg_h, 0.12), _mat_frame)
			_add_box("Foot", Vector3(x, -0.05, z), Vector3(0.42, 0.08, 0.28), _mat_frame)

	var rail_zs: Array[float] = [-half_w + 0.08, half_w - 0.08]
	for z in rail_zs:
		_add_box("LongFrameRail", Vector3(0, working_height - 0.18, z), Vector3(bed_length, 0.14, 0.12), _mat_frame)
		_add_box("LowerFrameRail", Vector3(0, 0.16, z), Vector3(bed_length * 0.92, 0.10, 0.10), _mat_frame)

	var cross_xs: Array[float] = [-half_l + 0.2, -0.7, 0.7, half_l - 0.2]
	for x in cross_xs:
		_add_box("CrossMember", Vector3(x, working_height - 0.2, 0), Vector3(0.12, 0.12, machine_width), _mat_frame)


func _build_feed_deck() -> void:
	_add_box("WearPlate", Vector3(0, working_height, 0), Vector3(bed_length, 0.055, 0.54), _mat_dark)

	var half_w := machine_width * 0.5
	var fence_zs: Array[float] = [-half_w + 0.22, half_w - 0.22]
	for z in fence_zs:
		_add_box("SideFence", Vector3(0, working_height + 0.18, z), Vector3(bed_length * 0.94, 0.22, 0.06), _mat_frame)

	var spacing := bed_length / float(feed_roller_count + 1)
	for i in range(feed_roller_count):
		var x := -bed_length * 0.5 + spacing * float(i + 1)
		_add_cylinder("FeedRoller", Vector3(x, working_height + 0.06, 0), 0.075, 1.14, _mat_dark, Vector3(PI * 0.5, 0, 0), 28)
		_add_cylinder("RollerShaft", Vector3(x, working_height + 0.06, 0), 0.025, machine_width + 0.18, _mat_blade, Vector3(PI * 0.5, 0, 0), 20)


func _build_hold_downs() -> void:
	var hold_down_xs: Array[float] = [-1.2, -0.45, 0.45, 1.2]
	for x in hold_down_xs:
		_add_box("HoldDownCrosshead", Vector3(x, working_height + 0.58, 0), Vector3(0.12, 0.12, 1.20), _mat_frame)
		_add_box("HoldDownTopPressureBox", Vector3(x, working_height + 0.87, 0), Vector3(0.32, 0.22, 0.92), _mat_frame)
		_add_box("HoldDownYoke", Vector3(x, working_height + 0.33, 0), Vector3(0.16, 0.10, 1.06), _mat_warning)
		_add_cylinder("HoldDownRoller", Vector3(x, working_height + 0.42, 0), 0.095, 0.96, _mat_warning, Vector3(PI * 0.5, 0, 0), 28)
		_add_cylinder("HoldDownAxle", Vector3(x, working_height + 0.42, 0), 0.026, 1.12, _mat_hydraulic, Vector3(PI * 0.5, 0, 0), 20)

		var side_zs: Array[float] = [-0.46, 0.46]
		for z in side_zs:
			_add_box("YokeSidePlate", Vector3(x, working_height + 0.38, z), Vector3(0.16, 0.28, 0.055), _mat_warning)
			_add_cylinder("GuidePost", Vector3(x - 0.09, working_height + 0.60, z), 0.026, 0.54, _mat_hydraulic, Vector3.ZERO, 18)
			_add_cylinder("PressureCylinderBarrel", Vector3(x + 0.09, working_height + 0.75, z), 0.055, 0.28, _mat_dark, Vector3.ZERO, 24)
			_add_cylinder("PressureCylinderRod", Vector3(x + 0.09, working_height + 0.51, z), 0.023, 0.30, _mat_hydraulic, Vector3.ZERO, 18)
			_add_box("RodClevis", Vector3(x + 0.09, working_height + 0.35, z), Vector3(0.11, 0.06, 0.07), _mat_hydraulic)
			_add_box("TopClevisBracket", Vector3(x + 0.09, working_height + 0.91, z), Vector3(0.13, 0.08, 0.09), _mat_dark)


func _build_saw_box() -> void:
	_add_box("MainSawGuard", Vector3(0, working_height + 0.68, 0), Vector3(1.05, 0.95, machine_width + 0.12), _mat_guard)
	_add_box("ThroatOpening", Vector3(0, working_height + 0.22, 0), Vector3(1.15, 0.18, 0.78), _mat_dark)

	var blade_z := saw_spacing * 0.5
	var blade_zs: Array[float] = [-blade_z, blade_z]
	for z in blade_zs:
		_add_cylinder("EdgerSawBlade", Vector3(0, working_height + 0.2, z), blade_radius, 0.035, _mat_blade, Vector3(PI * 0.5, 0, 0), 64)
		_add_cylinder("BladeHub", Vector3(0, working_height + 0.2, z), 0.12, 0.07, _mat_dark, Vector3(PI * 0.5, 0, 0), 32)
		_add_box("BladeKerfGuard", Vector3(0.12, working_height + 0.26, z), Vector3(0.34, 0.06, 0.09), _mat_warning)

	_add_cylinder("SawArbor", Vector3(0, working_height + 0.2, 0), 0.045, machine_width + 0.36, _mat_blade, Vector3(PI * 0.5, 0, 0), 28)


func _build_motors_and_drives() -> void:
	var motor_z := machine_width * 0.5 + 0.34
	var motor_zs: Array[float] = [-motor_z, motor_z]
	for z in motor_zs:
		_add_box("MotorMount", Vector3(0, working_height + 0.08, z), Vector3(0.48, 0.18, 0.18), _mat_frame)
		_add_cylinder("SawMotor", Vector3(-0.22, working_height + 0.25, z), 0.22, 0.48, _mat_motor, Vector3(0, 0, PI * 0.5), 32)
		_add_cylinder("DrivePulley", Vector3(0.22, working_height + 0.25, z), 0.16, 0.08, _mat_dark, Vector3(0, 0, PI * 0.5), 28)
		_add_box("BeltGuard", Vector3(0.10, working_height + 0.42, z), Vector3(0.58, 0.10, 0.28), _mat_dark, Vector3(0, 0, 0.18))


func _build_waste_handling() -> void:
	if not show_waste_chutes:
		return

	var chute_z := machine_width * 0.5 + 0.18
	var z_signs: Array[float] = [-1.0, 1.0]
	for z_sign in z_signs:
		var z := chute_z * z_sign
		_add_box("TrimChute", Vector3(0.62, working_height - 0.08, z), Vector3(1.6, 0.06, 0.36), _mat_dark, Vector3(0, 0, -0.16 * z_sign))
		_add_box("ChipConveyorBelt", Vector3(1.15, working_height - 0.32, z + 0.18 * z_sign), Vector3(1.7, 0.08, 0.26), _mat_dark)
		_add_box("ChipConveyorRail", Vector3(1.15, working_height - 0.19, z + 0.34 * z_sign), Vector3(1.7, 0.18, 0.05), _mat_frame)


func _build_sample_board() -> void:
	_add_box("ReferenceBoard", Vector3(-1.7, working_height + 0.095, 0), Vector3(1.35, 0.045, 0.32), _mat_wood)


func _add_box(name: String, position: Vector3, size: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = name
	box.position = position
	box.rotation = rotation
	box.size = size
	box.material = material
	box.use_collision = true
	add_child(box)
	return box


func _add_cylinder(name: String, position: Vector3, radius: float, height: float, material: Material, rotation: Vector3, sides: int) -> CSGCylinder3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.name = name
	cylinder.position = position
	cylinder.rotation = rotation
	cylinder.radius = radius
	cylinder.height = height
	cylinder.sides = sides
	cylinder.material = material
	cylinder.use_collision = true
	add_child(cylinder)
	return cylinder
