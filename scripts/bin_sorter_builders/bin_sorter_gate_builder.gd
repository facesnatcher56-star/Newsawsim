@tool
extends RefCounted

## Builds the mechanical drop gate assemblies, pneumatic actuators,
## safety orange diverter arms, optical sensors, and status light stacks.
## Uses high-performance MeshInstance3D nodes (Zero CSG overhead).

var sorter: Node


func _init(p_sorter: Node) -> void:
	sorter = p_sorter


func build_all() -> void:
	_build_infeed_laser_scanner()
	_build_bay_gates_and_actuators()


func _make_box(p_name: String, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.material_override = mat
	return mi


func _make_cylinder(p_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.material_override = mat
	return mi


func _build_infeed_laser_scanner() -> void:
	var sorter_h: float = sorter.sorter_height
	var bin_d: float = sorter.bin_depth

	var scanner := Node3D.new()
	scanner.name = "InfeedLaserScanner"
	scanner.position = Vector3(-0.3, sorter_h + 0.5, 0.0)

	var arch := _make_box("ScannerArchTop", Vector3(0.20, 0.15, bin_d + 0.2), Vector3.ZERO, sorter._mat_yellow)
	scanner.add_child(arch)

	for side in [-1.0, 1.0]:
		var leg := _make_box("ScannerLeg_Z%d" % int(side), Vector3(0.15, 0.60, 0.15), Vector3(0.0, -0.30, side * (bin_d * 0.5)), sorter._mat_yellow)
		scanner.add_child(leg)

	var num_lasers: int = 7
	for s in range(num_lasers):
		var sz: float = (s - (num_lasers - 1) * 0.5) * (bin_d * 0.14)
		var sensor_head := _make_cylinder("LaserOpticHead_%d" % s, 0.035, 0.12, Vector3(0.0, -0.10, sz), sorter._mat_dark_steel)

		var lens := _make_cylinder("LaserLens", 0.025, 0.02, Vector3(0.0, -0.07, 0.0), sorter._mat_red)
		sensor_head.add_child(lens)
		scanner.add_child(sensor_head)

	sorter.add_child(scanner)


func _get_track_positions() -> Array[float]:
	var bin_d: float = sorter.bin_depth
	var usable_depth: float = bin_d - 1.2
	var step_z: float = usable_depth / 4.0
	var track_positions: Array[float] = []
	for c_idx in range(5):
		track_positions.append(-usable_depth * 0.5 + c_idx * step_z)
	return track_positions


func _build_bay_gates_and_actuators() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var track_positions: Array[float] = _get_track_positions()

	sorter._gate_nodes.clear()
	sorter._piston_nodes.clear()
	sorter._status_led_nodes.clear()

	for side in [-1.0, 1.0]:
		var side_z: float = side * (bin_d * 0.5 + 0.15)
		var air_header := _make_cylinder("PneumaticAirHeader_Z%d" % int(side), 0.02, num_bins * bin_w + 1.0, Vector3((num_bins * bin_w + 1.0) * 0.5 - 0.5, sorter_h + 0.40, side_z), sorter._mat_chrome, Vector3(0.0, 0.0, PI * 0.5))
		sorter.add_child(air_header)

		for b in range(num_bins):
			var bay_x: float = b * bin_w
			var clamp_mesh := _make_box("HeaderClamp_B%d_Z%d" % [b, int(side)], Vector3(0.05, 0.05, 0.05), Vector3(bay_x + 0.35, sorter_h + 0.39, side_z), sorter._mat_cast_iron)
			sorter.add_child(clamp_mesh)

	for b in range(num_bins):
		var bay_x: float = b * bin_w
		var bay_center_x: float = (b + 0.5) * bin_w

		var bay_group := Node3D.new()
		bay_group.name = "BayMechanics_%d" % b

		var gate_pivot := AnimatableBody3D.new()
		gate_pivot.name = "DropGatePivot_%d" % b
		gate_pivot.position = Vector3((b + 1.0) * bin_w - 0.08, sorter_h + 0.10, 0.0)
		gate_pivot.sync_to_physics = true

		var arm_length: float = bin_w - 0.15
		var arm_width: float = 0.22

		# Add solid Tipple Gate CollisionShape3D directly to AnimatableBody3D gate_pivot
		var gate_col := CollisionShape3D.new()
		gate_col.name = "TippleGateCol_%d" % b
		var gate_shape := BoxShape3D.new()
		gate_shape.size = Vector3(arm_length, 0.04, bin_d - 0.3)
		gate_col.shape = gate_shape
		gate_col.position = Vector3(-arm_length * 0.5, 0.0, 0.0)
		gate_pivot.add_child(gate_col)

		var torque_shaft := _make_cylinder("TorqueShaft", 0.045, bin_d + 0.4, Vector3.ZERO, sorter._mat_orange, Vector3(PI * 0.5, 0.0, 0.0))
		gate_pivot.add_child(torque_shaft)

		for t_idx in range(track_positions.size()):
			var track_z: float = track_positions[t_idx]

			var tipple_base := _make_box("WedgeTippleArm_T%d" % t_idx, Vector3(arm_length, 0.035, arm_width), Vector3(-arm_length * 0.5, 0.0, track_z), sorter._mat_orange)

			var collar := _make_cylinder("TorqueFlangeCollar", 0.065, 0.04, Vector3(arm_length * 0.5, 0.0, 0.0), sorter._mat_cast_iron, Vector3(PI * 0.5, 0.0, 0.0))
			tipple_base.add_child(collar)

			var stripe := _make_box("HazardStripe", Vector3(arm_length, 0.04, 0.02), Vector3(0.0, 0.0, arm_width * 0.5 + 0.01), sorter._mat_yellow)
			tipple_base.add_child(stripe)

			gate_pivot.add_child(tipple_base)

			# Fixed Chamfered Deck Plate mesh
			var fixed_deck := _make_box("FixedDeckPlate_B%d_T%d" % [b, t_idx], Vector3(0.20, 0.04, arm_width + 0.04), Vector3((b + 1.0) * bin_w - 0.02, sorter_h + 0.10, track_z), sorter._mat_green)
			sorter.add_child(fixed_deck)

		# Add Fixed Deck CollisionShape3D directly to sorter (StaticBody3D)
		var fd_col := CollisionShape3D.new()
		fd_col.name = "FixedDeckCol_%d" % b
		var fd_shape := BoxShape3D.new()
		fd_shape.size = Vector3(0.20, 0.04, bin_d - 0.3)
		fd_col.shape = fd_shape
		fd_col.position = Vector3((b + 1.0) * bin_w - 0.02, sorter_h + 0.10, 0.0)
		sorter.add_child(fd_col)

		for side in [-1.0, 1.0]:
			var crank := _make_box("SideTorqueCrank_Z%d" % int(side), Vector3(0.06, 0.22, 0.06), Vector3(-0.08, 0.10, side * (bin_d * 0.5 + 0.15)), sorter._mat_cast_iron)
			gate_pivot.add_child(crank)

		bay_group.add_child(gate_pivot)
		sorter._gate_nodes.append(gate_pivot)

		var pistons_in_bay: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var side_z: float = side * (bin_d * 0.5 + 0.15)
			var cyl_mount := Node3D.new()
			cyl_mount.name = "SidePneumaticActuator_Z%d" % int(side)
			cyl_mount.position = Vector3(bay_x + 0.35, sorter_h + 0.30, side_z)

			var bracket := _make_box("ColumnMountBracket", Vector3(0.14, 0.12, 0.12), Vector3.ZERO, sorter._mat_cast_iron)
			cyl_mount.add_child(bracket)

			var cyl_body := _make_cylinder("CylinderBody", 0.06, 0.40, Vector3(-0.08, -0.15, 0.0), sorter._mat_green, Vector3(0.0, 0.0, -0.45))
			cyl_mount.add_child(cyl_body)

			for cap_y in [-0.20, 0.20]:
				var cap := _make_cylinder("Cap", 0.07, 0.035, Vector3(0.0, cap_y, 0.0), sorter._mat_orange)
				cyl_body.add_child(cap)

				var fitting := _make_cylinder("Fitting", 0.015, 0.04, Vector3(0.06, cap_y, 0.0), sorter._mat_brass, Vector3(0.0, 0.0, PI * 0.5))
				cyl_body.add_child(fitting)

			var shaft := _make_cylinder("PistonShaft", 0.028, 0.35, Vector3(0.0, -0.25, 0.0), sorter._mat_chrome)
			cyl_body.add_child(shaft)

			pistons_in_bay.append(shaft)
			bay_group.add_child(cyl_mount)

		sorter._piston_nodes.append(pistons_in_bay)

		var sensor := Node3D.new()
		sensor.name = "PhotoEyeSensor_%d" % b
		sensor.position = Vector3(bay_x + 0.2, sorter_h + 0.35, -bin_d * 0.45)

		var sensor_housing := _make_box("SensorHousing", Vector3(0.12, 0.12, 0.15), Vector3.ZERO, sorter._mat_yellow)
		var lens := _make_cylinder("PhotoEyeLens", 0.025, 0.02, Vector3(0.0, 0.0, 0.08), sorter._mat_red, Vector3(PI * 0.5, 0.0, 0.0))
		sensor_housing.add_child(lens)
		sensor.add_child(sensor_housing)

		bay_group.add_child(sensor)

		var light_stack := Node3D.new()
		light_stack.name = "StatusLightStack_%d" % b
		light_stack.position = Vector3(bay_center_x, sorter_h + 0.75, -bin_d * 0.5 - 0.1)

		var pole := _make_cylinder("LightStackPole", 0.018, 0.50, Vector3.ZERO, sorter._mat_dark_steel)
		light_stack.add_child(pole)

		var leds: Dictionary = {}
		var led_configs := [
			["GreenLED", Color(0.1, 0.9, 0.2), 0.18],
			["YellowLED", Color(0.95, 0.85, 0.1), 0.06],
			["RedLED", Color(0.95, 0.1, 0.1), -0.06],
		]
		for cfg in led_configs:
			var led_name: String = cfg[0]
			var color: Color = cfg[1]
			var py: float = cfg[2]

			var led_mesh := _make_cylinder(led_name, 0.04, 0.08, Vector3(0.0, py, 0.0), null)

			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.05
			led_mesh.material_override = mat

			var omni := OmniLight3D.new()
			omni.name = "LEDLight_" + led_name
			omni.light_color = color
			omni.light_energy = 0.0
			omni.omni_range = 2.0
			led_mesh.add_child(omni)

			light_stack.add_child(led_mesh)
			leds[led_name] = led_mesh

		bay_group.add_child(light_stack)
		sorter._status_led_nodes.append(leds)

		sorter.add_child(bay_group)
