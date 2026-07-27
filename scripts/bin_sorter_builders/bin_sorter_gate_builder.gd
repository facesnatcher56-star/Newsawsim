@tool
extends RefCounted

## Builds the mechanical drop gate assemblies, pneumatic actuators,
## safety orange diverter arms, optical sensors, and status light stacks.

var sorter: Node


func _init(p_sorter: Node) -> void:
	sorter = p_sorter


func build_all() -> void:
	_build_infeed_laser_scanner()
	_build_bay_gates_and_actuators()


func _build_infeed_laser_scanner() -> void:
	var sorter_h: float = sorter.sorter_height
	var bin_d: float = sorter.bin_depth

	var scanner := Node3D.new()
	scanner.name = "InfeedLaserScanner"
	scanner.position = Vector3(-0.3, sorter_h + 0.5, 0.0)

	# Scanner arch frame (Safety Yellow)
	var arch := CSGBox3D.new()
	arch.name = "ScannerArchTop"
	arch.size = Vector3(0.20, 0.15, bin_d + 0.2)
	arch.position = Vector3(0.0, 0.0, 0.0)
	arch.material = sorter._mat_yellow
	scanner.add_child(arch)

	for side in [-1.0, 1.0]:
		var leg := CSGBox3D.new()
		leg.name = "ScannerLeg_Z%d" % int(side)
		leg.size = Vector3(0.15, 0.60, 0.15)
		leg.position = Vector3(0.0, -0.30, side * (bin_d * 0.5))
		leg.material = sorter._mat_yellow
		scanner.add_child(leg)

	# Optical sensor optic heads (Dark steel body + Red LED lens)
	for s in range(5):
		var sz: float = (s - 2) * (bin_d * 0.2)
		var sensor_head := CSGCylinder3D.new()
		sensor_head.name = "LaserOpticHead_%d" % s
		sensor_head.radius = 0.035
		sensor_head.height = 0.12
		sensor_head.position = Vector3(0.0, -0.10, sz)
		sensor_head.material = sorter._mat_dark_steel
		scanner.add_child(sensor_head)

		# Red laser lens
		var lens := CSGCylinder3D.new()
		lens.name = "LaserLens"
		lens.radius = 0.025
		lens.height = 0.02
		lens.position = Vector3(0.0, -0.07, 0.0)
		lens.material = sorter._mat_red
		sensor_head.add_child(lens)

	sorter.add_child(scanner)


func _build_bay_gates_and_actuators() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var track_spacing: float = 1.6

	sorter._gate_nodes.clear()
	sorter._piston_nodes.clear()
	sorter._status_led_nodes.clear()

	for b in range(num_bins):
		var bay_x: float = b * bin_w
		var bay_center_x: float = (b + 0.5) * bin_w

		var bay_group := Node3D.new()
		bay_group.name = "BayMechanics_%d" % b

		# 1. Dual Safety Orange Hinged Drop Gate Arms (Front & Back)
		# Mounted under the drag chain channels at Z = ±0.8m.
		# Closed: lies flat bridging the bay gap. Open: tilts down to drop board into bin.
		var gate_pivot := AnimatableBody3D.new()
		gate_pivot.name = "DropGatePivot_%d" % b
		gate_pivot.position = Vector3(bay_x + 0.1, sorter_h + 0.12, 0.0)
		gate_pivot.sync_to_physics = true

		var arm_length: float = bin_w - 0.25
		var arm_width: float = 0.22  # Narrow gate arm under each chain track

		for side in [-1.0, 1.0]:
			var gate_arm := CSGBox3D.new()
			gate_arm.name = "GateArm_Z%d" % int(side)
			gate_arm.size = Vector3(arm_length, 0.04, arm_width)
			gate_arm.position = Vector3(arm_length * 0.5, 0.0, side * track_spacing * 0.5)
			gate_arm.material = sorter._mat_orange
			gate_arm.use_collision = true
			gate_pivot.add_child(gate_arm)

			# Safety Hazard Yellow Striping on outer edge of gate arm
			var stripe := CSGBox3D.new()
			stripe.name = "HazardStripe"
			stripe.size = Vector3(arm_length, 0.045, 0.03)
			stripe.position = Vector3(arm_length * 0.5, 0.0, side * (track_spacing * 0.5 + arm_width * 0.5 + 0.015))
			stripe.material = sorter._mat_yellow
			gate_pivot.add_child(stripe)

		bay_group.add_child(gate_pivot)
		sorter._gate_nodes.append(gate_pivot)

		# 2. Dual Pneumatic Cylinder Actuators (Front and Back)
		# Mounted vertically above the drop gate arms on top of the cross beam
		var pistons_in_bay: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var cyl_mount := Node3D.new()
			cyl_mount.name = "PneumaticCylinder_Z%d" % int(side)
			cyl_mount.position = Vector3(bay_center_x, sorter_h + 0.55, side * track_spacing * 0.5)

			# Cylinder Body (Industrial Green)
			var cyl_body := CSGCylinder3D.new()
			cyl_body.name = "CylinderBody"
			cyl_body.radius = 0.055
			cyl_body.height = 0.38
			cyl_body.rotation = Vector3(0.0, 0.0, -0.30)  # Angled down toward gate arm
			cyl_body.material = sorter._mat_green
			cyl_mount.add_child(cyl_body)

			# Safety Orange End Caps
			for cap_y in [-0.19, 0.19]:
				var cap := CSGCylinder3D.new()
				cap.radius = 0.065
				cap.height = 0.035
				cap.position = Vector3(0.0, cap_y, 0.0)
				cap.material = sorter._mat_orange
				cyl_body.add_child(cap)

			# Chrome Piston Shaft (extending down from cylinder to gate arm)
			var shaft := CSGCylinder3D.new()
			shaft.name = "PistonShaft"
			shaft.radius = 0.025
			shaft.height = 0.35
			shaft.position = Vector3(0.0, -0.25, 0.0)
			shaft.material = sorter._mat_chrome
			cyl_body.add_child(shaft)

			pistons_in_bay.append(shaft)
			bay_group.add_child(cyl_mount)

		sorter._piston_nodes.append(pistons_in_bay)

		# 3. Optical Photo-Eye Sensor in bay (Detecting board passage)
		var sensor := Node3D.new()
		sensor.name = "PhotoEyeSensor_%d" % b
		sensor.position = Vector3(bay_x + 0.2, sorter_h + 0.35, -track_spacing * 0.5 - 0.15)

		var sensor_housing := CSGBox3D.new()
		sensor_housing.name = "SensorHousing"
		sensor_housing.size = Vector3(0.12, 0.12, 0.15)
		sensor_housing.material = sorter._mat_yellow
		sensor.add_child(sensor_housing)

		var lens := CSGCylinder3D.new()
		lens.radius = 0.025
		lens.height = 0.02
		lens.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		lens.position = Vector3(0.0, 0.0, 0.08)
		lens.material = sorter._mat_red
		sensor_housing.add_child(lens)

		bay_group.add_child(sensor)

		# 4. Status Indicator Light Stack (Green = Ready, Yellow = Sorting, Red = Bin Full)
		var light_stack := Node3D.new()
		light_stack.name = "StatusLightStack_%d" % b
		light_stack.position = Vector3(bay_center_x, sorter_h + 0.75, -bin_d * 0.5 - 0.1)

		var pole := CSGCylinder3D.new()
		pole.radius = 0.018
		pole.height = 0.50
		pole.material = sorter._mat_dark_steel
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

			var led_mesh := CSGCylinder3D.new()
			led_mesh.name = led_name
			led_mesh.radius = 0.04
			led_mesh.height = 0.08
			led_mesh.position = Vector3(0.0, py, 0.0)

			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color * 0.4
			mat.emission_energy_multiplier = 0.5
			led_mesh.material = mat

			light_stack.add_child(led_mesh)
			leds[led_name] = led_mesh

		bay_group.add_child(light_stack)
		sorter._status_led_nodes.append(leds)

		sorter.add_child(bay_group)
