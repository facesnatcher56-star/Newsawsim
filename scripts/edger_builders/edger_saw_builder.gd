@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func build_saw_box() -> void:
	edger._push_editor_group("SawBladeAndGuardAssembly")
	edger._add_box("MainSawGuard", Vector3(SawmillEdger.SAW_X, edger.working_height + 0.86, 0), Vector3(0.76, 0.58, edger.machine_width + 0.12), edger._mat_guard, Vector3.ZERO, false)
	edger._add_box("UpperThroatLip", Vector3(SawmillEdger.SAW_X, edger.working_height + 0.49, 0), Vector3(0.88, 0.08, 0.92), edger._mat_dark, Vector3.ZERO, false)
	for z_sign in [-1.0, 1.0]:
		edger._add_box("ThroatSideCheek", Vector3(SawmillEdger.SAW_X, edger.working_height + 0.22, z_sign * 0.58), Vector3(0.88, 0.18, 0.12), edger._mat_dark, Vector3.ZERO, false)

	var blade_zs: Array[float] = [-edger.saw_spacing * 0.5, 0.0, edger.saw_spacing * 0.5]
	for i in range(blade_zs.size()):
		var z := blade_zs[i]
		var suffix := "_%02d" % (i + 1)
		var blade := edger._add_cylinder("EdgerSawBlade" + suffix, Vector3(SawmillEdger.SAW_X, edger.working_height + 0.2, z), edger.blade_radius, 0.035, edger._mat_blade, Vector3(PI * 0.5, 0, 0), 64, false)
		edger._saw_blades.append(blade)
		edger._saw_teeth_roots.append(edger._add_saw_teeth("EdgerSawTeeth" + suffix, Vector3(SawmillEdger.SAW_X, edger.working_height + 0.2, z), edger.blade_radius))
		edger._add_cylinder("BladeHub" + suffix, Vector3(SawmillEdger.SAW_X, edger.working_height + 0.2, z), 0.12, 0.07, edger._mat_dark, Vector3(PI * 0.5, 0, 0), 32, false)
		edger._add_box("BladeKerfGuard" + suffix, Vector3(SawmillEdger.SAW_X + 0.12, edger.working_height + 0.39, z), Vector3(0.34, 0.06, 0.09), edger._mat_warning, Vector3.ZERO, false)

	edger._add_cylinder("SawArbor", Vector3(SawmillEdger.SAW_X, edger.working_height + 0.2, 0), 0.045, edger.machine_width + 0.36, edger._mat_blade, Vector3(PI * 0.5, 0, 0), 28, false)
	edger._pop_editor_group()

func build_motors_and_drives() -> void:
	edger._push_editor_group("MotorDriveAssembly")
	var motor_z := edger.machine_width * 0.5 + 0.34
	var motor_zs: Array[float] = [-motor_z, motor_z]
	for z in motor_zs:
		edger._add_box("MotorMount", Vector3(SawmillEdger.SAW_X, edger.working_height + 0.08, z), Vector3(0.48, 0.18, 0.18), edger._mat_frame)
		edger._add_cylinder("SawMotor", Vector3(SawmillEdger.SAW_X - 0.22, edger.working_height + 0.25, z), 0.22, 0.48, edger._mat_motor, Vector3(0, 0, PI * 0.5), 32)
		edger._add_cylinder("DrivePulley", Vector3(SawmillEdger.SAW_X + 0.22, edger.working_height + 0.25, z), 0.16, 0.08, edger._mat_dark, Vector3(0, 0, PI * 0.5), 28)
		edger._add_box("BeltGuard", Vector3(SawmillEdger.SAW_X + 0.10, edger.working_height + 0.42, z), Vector3(0.58, 0.10, 0.28), edger._mat_dark, Vector3(0, 0, 0.18))
	edger._pop_editor_group()
