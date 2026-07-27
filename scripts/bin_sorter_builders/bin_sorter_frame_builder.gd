@tool
extends RefCounted

## Builds the static framework of the Lumber Bin Sorter:
## - Industrial Green structural H-beam gantry columns and cross beams.
## - Overhead catwalk with Safety Yellow handrails and access ladder.
## - Elevated drag chain guide channels & drive motor housing.
## - Funneled open-bottom gravity collection bin hoppers.

var sorter: Node


func _init(p_sorter: Node) -> void:
	sorter = p_sorter


func build_all() -> void:
	_build_support_gantry()
	_build_catwalk_and_handrails()
	_build_overhead_track_channels()
	_build_bin_hoppers()
	_build_drive_motors()


func _build_support_gantry() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0  # extra overhang for infeed/outfeed

	# Main longitudinal overhead I-beams (Industrial Green)
	var half_d: float = bin_d * 0.5
	for side in [-1.0, 1.0]:
		var beam := CSGBox3D.new()
		beam.name = "LongitudinalBeam_Z%d" % [int(side)]
		beam.size = Vector3(total_length, 0.25, 0.18)
		beam.position = Vector3(total_length * 0.5 - 0.5, sorter_h, side * half_d)
		beam.material = sorter._mat_green
		beam.use_collision = true
		sorter.add_child(beam)

	# Vertical support columns at each bay division
	for i in range(num_bins + 1):
		var x_pos: float = i * bin_w
		for side in [-1.0, 1.0]:
			var col := CSGBox3D.new()
			col.name = "SupportColumn_B%d_Z%d" % [i, int(side)]
			col.size = Vector3(0.20, sorter_h, 0.20)
			col.position = Vector3(x_pos, sorter_h * 0.5, side * half_d)
			col.material = sorter._mat_green
			col.use_collision = true
			sorter.add_child(col)

			# Base plate
			var base_plate := CSGBox3D.new()
			base_plate.name = "BasePlate"
			base_plate.size = Vector3(0.40, 0.03, 0.40)
			base_plate.position = Vector3(x_pos, 0.015, side * half_d)
			base_plate.material = sorter._mat_dark_steel
			sorter.add_child(base_plate)

		# Cross beam tying columns at top
		var cross_beam := CSGBox3D.new()
		cross_beam.name = "CrossBeam_B%d" % [i]
		cross_beam.size = Vector3(0.18, 0.22, bin_d + 0.3)
		cross_beam.position = Vector3(x_pos, sorter_h - 0.11, 0.0)
		cross_beam.material = sorter._mat_green
		cross_beam.use_collision = true
		sorter.add_child(cross_beam)

		# Diagonal gusset braces connecting columns to top beams
		for side in [-1.0, 1.0]:
			var brace := CSGBox3D.new()
			brace.name = "DiagonalBrace"
			brace.size = Vector3(0.10, 0.70, 0.10)
			brace.position = Vector3(x_pos, sorter_h - 0.50, side * (half_d - 0.35))
			brace.rotation = Vector3(side * 0.45, 0.0, 0.0)
			brace.material = sorter._mat_green
			sorter.add_child(brace)


func _build_catwalk_and_handrails() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0

	var catwalk_z: float = -bin_d * 0.5 - 0.6  # Run along back side
	var catwalk_h: float = sorter_h - 0.4
	var catwalk_w: float = 0.8

	# Catwalk floor mesh / steel grate
	var floor_grate := CSGBox3D.new()
	floor_grate.name = "CatwalkFloor"
	floor_grate.size = Vector3(total_length, 0.06, catwalk_w)
	floor_grate.position = Vector3(total_length * 0.5 - 0.5, catwalk_h, catwalk_z)
	floor_grate.material = sorter._mat_dark_steel
	floor_grate.use_collision = true
	sorter.add_child(floor_grate)

	# Safety Yellow Handrails along outer edge of catwalk
	var outer_z: float = catwalk_z - catwalk_w * 0.5 + 0.04
	var rail_height: float = 1.05

	# Top handrail
	var top_rail := CSGCylinder3D.new()
	top_rail.name = "HandrailTop"
	top_rail.radius = 0.02
	top_rail.height = total_length
	top_rail.rotation = Vector3(0.0, 0.0, PI * 0.5)
	top_rail.position = Vector3(total_length * 0.5 - 0.5, catwalk_h + rail_height, outer_z)
	top_rail.material = sorter._mat_yellow
	sorter.add_child(top_rail)

	# Mid handrail
	var mid_rail := CSGCylinder3D.new()
	mid_rail.name = "HandrailMid"
	mid_rail.radius = 0.015
	mid_rail.height = total_length
	mid_rail.rotation = Vector3(0.0, 0.0, PI * 0.5)
	mid_rail.position = Vector3(total_length * 0.5 - 0.5, catwalk_h + rail_height * 0.5, outer_z)
	mid_rail.material = sorter._mat_yellow
	sorter.add_child(mid_rail)

	# Vertical handrail posts spaced every 1.5m
	var num_posts: int = int(ceil(total_length / 1.5)) + 1
	for p in range(num_posts):
		var px: float = (total_length / max(num_posts - 1, 1)) * p - 0.5
		var post := CSGCylinder3D.new()
		post.name = "HandrailPost_%d" % p
		post.radius = 0.02
		post.height = rail_height
		post.position = Vector3(px, catwalk_h + rail_height * 0.5, outer_z)
		post.material = sorter._mat_yellow
		sorter.add_child(post)

	# Safety Toe-kick plate
	var toekick := CSGBox3D.new()
	toekick.name = "ToeKickPlate"
	toekick.size = Vector3(total_length, 0.12, 0.01)
	toekick.position = Vector3(total_length * 0.5 - 0.5, catwalk_h + 0.06, outer_z)
	toekick.material = sorter._mat_yellow
	sorter.add_child(toekick)

	# Access Ladder at start of catwalk (Infeed end)
	_build_ladder(Vector3(-0.4, 0.0, catwalk_z), catwalk_h)


func _build_ladder(base_pos: Vector3, top_h: float) -> void:
	var ladder := Node3D.new()
	ladder.name = "AccessLadder"
	ladder.position = base_pos

	var width: float = 0.45
	var rungs: int = int(floor(top_h / 0.3))

	for side in [-1.0, 1.0]:
		var rail := CSGCylinder3D.new()
		rail.radius = 0.02
		rail.height = top_h + 1.0
		rail.position = Vector3(0.0, (top_h + 1.0) * 0.5, side * width * 0.5)
		rail.material = sorter._mat_yellow
		ladder.add_child(rail)

	for r in range(1, rungs + 1):
		var rung := CSGCylinder3D.new()
		rung.radius = 0.012
		rung.height = width
		rung.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		rung.position = Vector3(0.0, r * 0.3, 0.0)
		rung.material = sorter._mat_yellow
		ladder.add_child(rung)

	sorter.add_child(ladder)


func _build_overhead_track_channels() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0

	# Dual overhead steel drag chain guide channels (running along Z = ±0.8)
	var track_spacing: float = 1.6  # distance between front and back chain tracks
	for side in [-1.0, 1.0]:
		var channel := CSGBox3D.new()
		channel.name = "ChainChannel_Z%d" % [int(side)]
		channel.size = Vector3(total_length, 0.12, 0.14)
		channel.position = Vector3(total_length * 0.5 - 0.5, sorter_h + 0.15, side * track_spacing * 0.5)
		channel.material = sorter._mat_dark_steel
		channel.use_collision = true

		# Subtractive groove inside channel for drag chain
		var groove := CSGBox3D.new()
		groove.name = "ChainGroove"
		groove.operation = CSGShape3D.OPERATION_SUBTRACTION
		groove.size = Vector3(total_length + 0.2, 0.08, 0.08)
		groove.position = Vector3(0.0, 0.03, 0.0)
		channel.add_child(groove)

		sorter.add_child(channel)


func _build_bin_hoppers() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height

	# Build funnel hoppers forming open-bottom gravity collection bins
	for b in range(num_bins):
		var bay_center_x: float = (b + 0.5) * bin_w
		var hopper := Node3D.new()
		hopper.name = "GravityBinHopper_%d" % b

		# Angled side guide funnel plates (Industrial Green with black rubber liners)
		# Top edge at Z = ±1.9m, Y = 3.2m. Bottom edge at Z = ±0.835m, Y = 1.275m.
		# Rotation around X = side * 0.505 slopes the plates INWARD toward Z = 0.
		var wall_height: float = 2.2
		for side in [-1.0, 1.0]:
			var wall_pivot := Node3D.new()
			wall_pivot.name = "SlopedWallPivot_Z%d" % int(side)
			wall_pivot.position = Vector3(bay_center_x, sorter_h * 0.80, side * (bin_d * 0.45))
			wall_pivot.rotation = Vector3(side * 0.505, 0.0, 0.0)  # Slopes inward toward center Z=0

			var wall := CSGBox3D.new()
			wall.name = "SlopedWall"
			wall.size = Vector3(bin_w - 0.08, wall_height, 0.03)
			wall.position = Vector3(0.0, -wall_height * 0.5, 0.0)
			wall.material = sorter._mat_green
			wall.use_collision = true
			wall_pivot.add_child(wall)

			# Black rubber cushioning liner on inside surface of funnel wall
			var liner := CSGBox3D.new()
			liner.name = "RubberLiner"
			liner.size = Vector3(bin_w - 0.10, wall_height - 0.04, 0.02)
			liner.position = Vector3(0.0, -wall_height * 0.5, -side * 0.02)
			liner.material = sorter._mat_rubber
			wall_pivot.add_child(liner)

			hopper.add_child(wall_pivot)

		# End divider walls separating adjacent bin bays
		var divider := CSGBox3D.new()
		divider.name = "BinDividerPlate_%d" % b
		divider.size = Vector3(0.04, sorter_h * 0.65, bin_d - 0.2)
		divider.position = Vector3((b + 1.0) * bin_w, sorter_h * 0.40, 0.0)
		divider.material = sorter._mat_green
		divider.use_collision = true
		hopper.add_child(divider)

		# Open-Bottom Gravity Collection Sling / Bin Pocket Base
		var bin_pocket := StaticBody3D.new()
		bin_pocket.name = "OpenBinPocketFloor"
		bin_pocket.position = Vector3(bay_center_x, 0.4, 0.0)

		# Floor collider for lumber landing
		var col := CollisionShape3D.new()
		col.name = "FloorCol"
		var shape := BoxShape3D.new()
		shape.size = Vector3(bin_w - 0.12, 0.10, bin_d - 0.6)
		col.shape = shape
		bin_pocket.add_child(col)

		# Visual floor steel grate
		var floor_mesh := CSGBox3D.new()
		floor_mesh.name = "FloorMesh"
		floor_mesh.size = shape.size
		floor_mesh.material = sorter._mat_dark_steel
		bin_pocket.add_child(floor_mesh)

		# Safety Yellow open side retaining end bars
		for side in [-1.0, 1.0]:
			var bar := CSGBox3D.new()
			bar.name = "SideRetainingBar_Z%d" % int(side)
			bar.size = Vector3(bin_w - 0.12, 0.35, 0.06)
			bar.position = Vector3(0.0, 0.20, side * (bin_d * 0.5 - 0.3))
			bar.material = sorter._mat_yellow
			bin_pocket.add_child(bar)

		hopper.add_child(bin_pocket)
		sorter.add_child(hopper)


func _build_drive_motors() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0

	# Drive Motor housing at outfeed end (Industrial Green + Motor finning)
	var motor_housing := Node3D.new()
	motor_housing.name = "OverheadDriveMotor"
	motor_housing.position = Vector3(total_length - 0.3, sorter_h + 0.3, 0.0)

	var motor_body := CSGCylinder3D.new()
	motor_body.name = "MotorCylinder"
	motor_body.radius = 0.22
	motor_body.height = 0.55
	motor_body.rotation = Vector3(0.0, 0.0, PI * 0.5)
	motor_body.material = sorter._mat_green
	motor_housing.add_child(motor_body)

	var gearbox := CSGBox3D.new()
	gearbox.name = "Gearbox"
	gearbox.size = Vector3(0.40, 0.40, 0.50)
	gearbox.position = Vector3(-0.25, 0.0, 0.0)
	gearbox.material = sorter._mat_dark_steel
	motor_housing.add_child(gearbox)

	# Drive Sprocket Shaft
	var shaft := CSGCylinder3D.new()
	shaft.name = "DriveShaft"
	shaft.radius = 0.05
	shaft.height = 1.8
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shaft.position = Vector3(-0.25, 0.0, 0.0)
	shaft.material = sorter._mat_dark_steel
	motor_housing.add_child(shaft)

	sorter.add_child(motor_housing)
