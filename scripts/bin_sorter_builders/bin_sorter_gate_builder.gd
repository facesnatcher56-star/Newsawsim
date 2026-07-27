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

	# Optical sensor optic heads (7 laser heads across the expanded Z depth)
	var num_lasers: int = 7
	for s in range(num_lasers):
		var sz: float = (s - (num_lasers - 1) * 0.5) * (bin_d * 0.14)
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

	# Continuous Chrome Pneumatic Air Supply Header Pipes along Outer Gantry Sides
	for side in [-1.0, 1.0]:
		var side_z: float = side * (bin_d * 0.5 + 0.15)
		var air_header := CSGCylinder3D.new()
		air_header.name = "PneumaticAirHeader_Z%d" % int(side)
		air_header.radius = 0.02
		air_header.height = num_bins * bin_w + 1.0
		air_header.rotation = Vector3(0.0, 0.0, PI * 0.5)
		air_header.position = Vector3((num_bins * bin_w + 1.0) * 0.5 - 0.5, sorter_h + 0.40, side_z)
		air_header.material = sorter._mat_chrome
		sorter.add_child(air_header)

		for b in range(num_bins):
			var bay_x: float = b * bin_w
			var clamp_mesh := CSGBox3D.new()
			clamp_mesh.name = "HeaderClamp_B%d_Z%d" % [b, int(side)]
			clamp_mesh.size = Vector3(0.05, 0.05, 0.05)
			clamp_mesh.position = Vector3(bay_x + 0.35, sorter_h + 0.39, side_z)
			clamp_mesh.material = sorter._mat_cast_iron
			sorter.add_child(clamp_mesh)

	for b in range(num_bins):
		var bay_x: float = b * bin_w
		var bay_center_x: float = (b + 0.5) * bin_w

		var bay_group := Node3D.new()
		bay_group.name = "BayMechanics_%d" % b

		# 1. Photo-Matched Wedge-Tapered Orange Tipples & Flush Fixed Deck Plates (Photo 2 Match)
		var gate_pivot := AnimatableBody3D.new()
		gate_pivot.name = "DropGatePivot_%d" % b
		gate_pivot.position = Vector3((b + 1.0) * bin_w - 0.15, sorter_h + 0.10, 0.0)
		gate_pivot.sync_to_physics = true

		# Round Torque Shaft with Flange Mounting Collars (Photo 2 Match)
		var torque_shaft := CSGCylinder3D.new()
		torque_shaft.name = "TorqueShaft"
		torque_shaft.radius = 0.045
		torque_shaft.height = bin_d + 0.4
		torque_shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		torque_shaft.material = sorter._mat_orange
		gate_pivot.add_child(torque_shaft)

		var arm_length: float = bin_w - 0.25
		var arm_width: float = 0.22

		for t_idx in range(track_positions.size()):
			var track_z: float = track_positions[t_idx]

			# Wedge-Tapered Orange Tipple Arm (Lies 100% flat and flush at 0 deg closed matching Photo 2)
			var tipple_base := CSGBox3D.new()
			tipple_base.name = "WedgeTippleArm_T%d" % t_idx
			tipple_base.size = Vector3(arm_length, 0.035, arm_width)
			tipple_base.position = Vector3(-arm_length * 0.5, 0.0, track_z)
			tipple_base.material = sorter._mat_orange
			tipple_base.use_collision = true

			# Flange Mounting Collar to round torque shaft (Photo 2 Match)
			var collar := CSGCylinder3D.new()
			collar.name = "TorqueFlangeCollar"
			collar.radius = 0.065
			collar.height = 0.04
			collar.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			collar.position = Vector3(arm_length * 0.5, 0.0, 0.0)
			collar.material = sorter._mat_cast_iron
			tipple_base.add_child(collar)

			# Safety Hazard Yellow Striping on outer edge
			var stripe := CSGBox3D.new()
			stripe.name = "HazardStripe"
			stripe.size = Vector3(arm_length, 0.04, 0.02)
			stripe.position = Vector3(0.0, 0.0, arm_width * 0.5 + 0.01)
			stripe.material = sorter._mat_yellow
			tipple_base.add_child(stripe)

			gate_pivot.add_child(tipple_base)

			# Fixed Chamfered Blue Deck Plate at bay bridge division (Photo 2 Match)
			var fixed_deck := CSGBox3D.new()
			fixed_deck.name = "FixedDeckPlate_B%d_T%d" % [b, t_idx]
			fixed_deck.size = Vector3(0.20, 0.04, arm_width + 0.04)
			fixed_deck.position = Vector3((b + 1.0) * bin_w - 0.02, sorter_h + 0.10, track_z)
			fixed_deck.material = sorter._mat_green
			fixed_deck.use_collision = true
			sorter.add_child(fixed_deck)

		# Side Torque Crank Arms attached to ends of pivot shaft outside lumber path
		for side in [-1.0, 1.0]:
			var crank := CSGBox3D.new()
			crank.name = "SideTorqueCrank_Z%d" % int(side)
			crank.size = Vector3(0.06, 0.22, 0.06)
			crank.position = Vector3(-0.08, 0.10, side * (bin_d * 0.5 + 0.15))
			crank.material = sorter._mat_cast_iron
			gate_pivot.add_child(crank)

		bay_group.add_child(gate_pivot)
		sorter._gate_nodes.append(gate_pivot)

		# 2. Dual Side-Mounted Pneumatic Cylinder Actuators (On gantry columns, leaving chain races 100% clear)
		var pistons_in_bay: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var side_z: float = side * (bin_d * 0.5 + 0.15)
			var cyl_mount := Node3D.new()
			cyl_mount.name = "SidePneumaticActuator_Z%d" % int(side)
			cyl_mount.position = Vector3(bay_x + 0.35, sorter_h + 0.30, side_z)

			# Column Mounting Bracket (Cast Iron)
			var bracket := CSGBox3D.new()
			bracket.name = "ColumnMountBracket"
			bracket.size = Vector3(0.14, 0.12, 0.12)
			bracket.position = Vector3(0.0, 0.0, 0.0)
			bracket.material = sorter._mat_cast_iron
			cyl_mount.add_child(bracket)

			# Cylinder Body (Industrial Green, angled down toward torque crank)
			var cyl_body := CSGCylinder3D.new()
			cyl_body.name = "CylinderBody"
			cyl_body.radius = 0.06
			cyl_body.height = 0.40
			cyl_body.rotation = Vector3(0.0, 0.0, -0.45)
			cyl_body.position = Vector3(-0.08, -0.15, 0.0)
			cyl_body.material = sorter._mat_green
			cyl_mount.add_child(cyl_body)

			# End Caps & Brass Fittings
			for cap_y in [-0.20, 0.20]:
				var cap := CSGCylinder3D.new()
				cap.radius = 0.07
				cap.height = 0.035
				cap.position = Vector3(0.0, cap_y, 0.0)
				cap.material = sorter._mat_orange
				cyl_body.add_child(cap)

				var fitting := CSGCylinder3D.new()
				fitting.radius = 0.015
				fitting.height = 0.04
				fitting.position = Vector3(0.06, cap_y, 0.0)
				fitting.rotation = Vector3(0.0, 0.0, PI * 0.5)
				fitting.material = sorter._mat_brass
				cyl_body.add_child(fitting)

			# Chrome Piston Shaft connected to Torque Crank Arm
			var shaft := CSGCylinder3D.new()
			shaft.name = "PistonShaft"
			shaft.radius = 0.028
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
		sensor.position = Vector3(bay_x + 0.2, sorter_h + 0.35, -bin_d * 0.45)

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
