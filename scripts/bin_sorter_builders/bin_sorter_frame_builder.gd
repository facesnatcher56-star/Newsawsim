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
	_build_infeed_return_shaft()
	_build_bin_hoppers()
	_build_floor_haul_out_conveyor()
	_build_drive_motors()


func _get_track_positions() -> Array[float]:
	var bin_d: float = sorter.bin_depth
	var usable_depth: float = bin_d - 1.2
	var step_z: float = usable_depth / 4.0
	var track_positions: Array[float] = []
	for c_idx in range(5):
		track_positions.append(-usable_depth * 0.5 + c_idx * step_z)
	return track_positions


func _build_floor_haul_out_conveyor() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	var haul_out := Node3D.new()
	haul_out.name = "FloorHaulOutConveyor"
	haul_out.position = Vector3(total_length * 0.5 - 0.5, 0.20, 0.0)

	# 5 Parallel Heavy Steel Floor Conveyor Chains matching Photo 3
	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]

		# Green steel channel frame bed along floor
		var bed := CSGBox3D.new()
		bed.name = "ConveyorBedChannel_T%d" % t_idx
		bed.size = Vector3(total_length, 0.14, 0.16)
		bed.position = Vector3(0.0, 0.0, track_z)
		bed.material = sorter._mat_green
		haul_out.add_child(bed)

		# Heavy Dark Steel Floor Drag Chain Strand
		var chain_strand := CSGBox3D.new()
		chain_strand.name = "FloorChainStrand_T%d" % t_idx
		chain_strand.size = Vector3(total_length, 0.04, 0.06)
		chain_strand.position = Vector3(0.0, 0.08, track_z)
		chain_strand.material = sorter._mat_dark_steel
		haul_out.add_child(chain_strand)

	# Transverse Steel Tie Beams every 1.8m along floor
	var beam_count: int = num_bins + 1
	for b in range(beam_count):
		var bx: float = b * bin_w - (total_length * 0.5 - 0.5)
		var cross_beam := CSGBox3D.new()
		cross_beam.name = "FloorConveyorCrossBeam_%d" % b
		cross_beam.size = Vector3(0.16, 0.16, bin_d - 0.4)
		cross_beam.position = Vector3(bx, -0.02, 0.0)
		cross_beam.material = sorter._mat_green
		haul_out.add_child(cross_beam)

	# Outfeed Electric Haul-Out Drive Motor Assembly
	var motor := CSGCylinder3D.new()
	motor.name = "FloorHaulOutMotor"
	motor.radius = 0.16
	motor.height = 0.45
	motor.rotation = Vector3(0.0, 0.0, PI * 0.5)
	motor.position = Vector3(total_length * 0.5 + 0.3, 0.10, bin_d * 0.40)
	motor.material = sorter._mat_green
	haul_out.add_child(motor)

	sorter.add_child(haul_out)


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

		# Upper & Lower Horizontal Hopper Support Ledger Beams
		for side in [-1.0, 1.0]:
			var upper_ledger := CSGBox3D.new()
			upper_ledger.name = "UpperHopperLedger_B%d_Z%d" % [i, int(side)]
			upper_ledger.size = Vector3(bin_w + 0.2, 0.15, 0.15)
			upper_ledger.position = Vector3(x_pos, sorter_h * 0.80, side * (bin_d * 0.48))
			upper_ledger.material = sorter._mat_green
			sorter.add_child(upper_ledger)

			var lower_ledger := CSGBox3D.new()
			lower_ledger.name = "LowerHopperLedger_B%d_Z%d" % [i, int(side)]
			lower_ledger.size = Vector3(bin_w + 0.2, 0.15, 0.15)
			lower_ledger.position = Vector3(x_pos, sorter_h * 0.35, side * (bin_d * 0.48))
			lower_ledger.material = sorter._mat_green
			sorter.add_child(lower_ledger)

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
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	# Solid Infeed Transfer Table Deck (X = -0.5m to X = 0.1m) so boards spawn stably
	var infeed_table := CSGBox3D.new()
	infeed_table.name = "InfeedTransferTable"
	infeed_table.size = Vector3(0.60, 0.04, bin_d - 0.4)
	infeed_table.position = Vector3(-0.20, sorter_h + 0.10, 0.0)
	infeed_table.material = sorter._mat_dark_steel
	infeed_table.use_collision = true
	sorter.add_child(infeed_table)

	# 5-strand overhead steel drag chain guide channels (Open top for 100% chain visibility, terminated before sprockets)
	var channel_start_x: float = -0.35
	var channel_end_x: float = total_length - 0.65
	var channel_len: float = channel_end_x - channel_start_x

	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]

		var channel_group := Node3D.new()
		channel_group.name = "ChainChannel_T%d" % t_idx

		# Dual Side Guide Rails (Left and Right of roller chain, shallow 0.06m height leaving chain 100% visible)
		for side_z in [-0.045, 0.045]:
			var side_plate := CSGBox3D.new()
			side_plate.name = "SideGuidePlate_Z%.3f" % side_z
			side_plate.size = Vector3(channel_len, 0.06, 0.010)
			side_plate.position = Vector3((channel_start_x + channel_end_x) * 0.5, sorter_h + 0.555, track_z + side_z)
			side_plate.material = sorter._mat_dark_steel
			channel_group.add_child(side_plate)

		sorter.add_child(channel_group)

		# Static Continuous 3D Roller Chain Strands (Zero Per-Frame Physics Overhead - 60+ FPS)
		var chain_group := Node3D.new()
		chain_group.name = "ContinuousChainLoop_T%d" % t_idx

		# Top Return Strand
		var top_strand := CSGBox3D.new()
		top_strand.name = "StaticTopChainStrand"
		top_strand.size = Vector3(total_length, 0.035, 0.04)
		top_strand.position = Vector3(total_length * 0.5 - 0.5, sorter_h + 0.63, track_z)
		top_strand.material = sorter._mat_dark_steel
		chain_group.add_child(top_strand)

		# Bottom Transport Strand
		var bot_strand := CSGBox3D.new()
		bot_strand.name = "StaticBottomChainStrand"
		bot_strand.size = Vector3(total_length, 0.035, 0.04)
		bot_strand.position = Vector3(total_length * 0.5 - 0.5, sorter_h + 0.48, track_z)
		bot_strand.material = sorter._mat_dark_steel
		chain_group.add_child(bot_strand)

		# Outfeed Sprocket 180-degree Chain Wrap Arc
		var outfeed_wrap := CSGCylinder3D.new()
		outfeed_wrap.name = "OutfeedSprocketWrap"
		outfeed_wrap.radius = 0.075
		outfeed_wrap.height = 0.04
		outfeed_wrap.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		outfeed_wrap.position = Vector3(total_length - 0.5, sorter_h + 0.555, track_z)
		outfeed_wrap.material = sorter._mat_sprocket_steel
		chain_group.add_child(outfeed_wrap)

		# Infeed Sprocket 180-degree Chain Wrap Arc
		var infeed_wrap := CSGCylinder3D.new()
		infeed_wrap.name = "InfeedSprocketWrap"
		infeed_wrap.radius = 0.075
		infeed_wrap.height = 0.04
		infeed_wrap.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		infeed_wrap.position = Vector3(-0.5, sorter_h + 0.555, track_z)
		infeed_wrap.material = sorter._mat_sprocket_steel
		chain_group.add_child(infeed_wrap)

		sorter.add_child(chain_group)

	# Entry/Exit Transfer Deck Skid Bars (at infeed and outfeed transitions only)
	for sx in [-0.4, -0.2, num_bins * bin_w + 0.2, num_bins * bin_w + 0.4]:
		var skid_bar := CSGBox3D.new()
		skid_bar.name = "SlideSkidBar_X%.1f" % sx
		skid_bar.size = Vector3(0.04, 0.04, bin_d - 0.8)
		skid_bar.position = Vector3(sx, sorter_h + 0.05, 0.0)
		skid_bar.material = sorter._mat_dark_steel
		sorter.add_child(skid_bar)


func _build_infeed_return_shaft() -> void:
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var track_positions: Array[float] = _get_track_positions()

	var return_group := Node3D.new()
	return_group.name = "InfeedReturnShaftAssembly"
	return_group.position = Vector3(-0.5, sorter_h + 0.55, 0.0)

	# Infeed Return Shaft Cylinder
	var shaft := CSGCylinder3D.new()
	shaft.name = "ReturnShaft"
	shaft.radius = 0.045
	shaft.height = bin_d - 0.4
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shaft.material = sorter._mat_dark_steel
	return_group.add_child(shaft)

	# 5 Compact Idler Sprockets & Pillow Block Bearings
	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]
		_build_sprocket(return_group, Vector3(0.0, 0.0, track_z), 10)

	for side in [-1.0, 1.0]:
		_build_pillow_block(return_group, Vector3(0.0, -0.12, side * (bin_d * 0.45)))

	sorter.add_child(return_group)


func _build_bin_hoppers() -> void:
	var num_bins: int = sorter.num_bins
	var bin_w: float = sorter.bin_width
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height

	# Build open-bottom gravity collection bin bays (Clean open bays with zero sloped wall conflict)
	for b in range(num_bins):
		var bay_center_x: float = (b + 0.5) * bin_w
		var hopper := Node3D.new()
		hopper.name = "GravityBinHopper_%d" % b

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
		shape.size = Vector3(bin_w - 0.12, 0.10, bin_d - 0.4)
		col.shape = shape
		bin_pocket.add_child(col)

		# Orange L-Shaped Hydraulic Indexing Sling Forks (PERPENDICULAR Support along X at Z = +-1.5m)
		var fork_group := Node3D.new()
		fork_group.name = "IndexingSlingForks"

		# Dual Heavy Orange Indexing Sling Fork Arms running along X across bay width, spaced at Z = -1.5m and Z = +1.5m
		for fz in [-1.5, 1.5]:
			var fork_arm := CSGBox3D.new()
			fork_arm.name = "IndexingSlingFork_Z%.1f" % fz
			fork_arm.size = Vector3(bin_w - 0.24, 0.14, 0.18)  # Length along X across bay width!
			fork_arm.position = Vector3(0.0, 0.0, fz)
			fork_arm.material = sorter._mat_orange
			fork_group.add_child(fork_arm)

			# 15-degree Upward Safety Lip at outer ends of fork arm (X ends)
			for side_x in [-1.0, 1.0]:
				var lip := CSGBox3D.new()
				lip.name = "ForkSafetyLip_X%d" % int(side_x)
				lip.size = Vector3(0.16, 0.22, 0.18)
				lip.position = Vector3(side_x * ((bin_w - 0.24) * 0.5), 0.08, fz)
				lip.rotation = Vector3(0.0, 0.0, side_x * 0.25)
				lip.material = sorter._mat_orange
				fork_group.add_child(lip)

		bin_pocket.add_child(fork_group)

		# 4 Corner Vertical Guide Posts & Hoist Chains for Automatic Indexing Sling
		for bx in [-1.0, 1.0]:
			for bz in [-1.0, 1.0]:
				var corner_post := CSGBox3D.new()
				corner_post.name = "CornerGuidePost_X%d_Z%d" % [int(bx), int(bz)]
				corner_post.size = Vector3(0.12, 1.5, 0.12)
				corner_post.position = Vector3(bx * (bin_w * 0.45), 0.75, bz * (bin_d * 0.45))
				corner_post.material = sorter._mat_green
				bin_pocket.add_child(corner_post)

				# Hoist Chain Cable extending down to floor
				var hoist_chain := CSGCylinder3D.new()
				hoist_chain.name = "SlingHoistChain"
				hoist_chain.radius = 0.015
				hoist_chain.height = 1.1
				hoist_chain.position = Vector3(bx * (bin_w * 0.42), 0.75, bz * (bin_d * 0.42))
				hoist_chain.material = sorter._mat_dark_steel
				bin_pocket.add_child(hoist_chain)

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
	var bin_d: float = sorter.bin_depth
	var sorter_h: float = sorter.sorter_height
	var total_length: float = num_bins * bin_w + 1.0
	var track_positions: Array[float] = _get_track_positions()

	var drive_assembly := Node3D.new()
	drive_assembly.name = "OutfeedDriveAssembly"
	drive_assembly.position = Vector3(total_length - 0.5, sorter_h + 0.55, 0.0)

	# Main Drive Shaft
	var shaft := CSGCylinder3D.new()
	shaft.name = "DriveShaft"
	shaft.radius = 0.05
	shaft.height = bin_d - 0.4
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shaft.material = sorter._mat_dark_steel
	drive_assembly.add_child(shaft)

	# 5 Compact Drive Sprockets (R = 0.075m inline with channel)
	for t_idx in range(track_positions.size()):
		var track_z: float = track_positions[t_idx]
		_build_sprocket(drive_assembly, Vector3(0.0, 0.0, track_z), 10)

	# Pillow Block Bearings on Gantry Cross Beams
	for side in [-1.0, 1.0]:
		_build_pillow_block(drive_assembly, Vector3(0.0, -0.12, side * (bin_d * 0.45)))

	# Heavy Industrial Electric Motor Body (Green with Cooling Fins & Fan Cowl)
	var motor := Node3D.new()
	motor.name = "DriveMotor"
	motor.position = Vector3(0.2, 0.15, bin_d * 0.5 + 0.3)

	var motor_casing := CSGCylinder3D.new()
	motor_casing.name = "MotorCasing"
	motor_casing.radius = 0.22
	motor_casing.height = 0.60
	motor_casing.rotation = Vector3(0.0, 0.0, PI * 0.5)
	motor_casing.material = sorter._mat_green
	motor.add_child(motor_casing)

	# Cooling Fins (7 circumferential rings)
	for f in range(7):
		var fin := CSGCylinder3D.new()
		fin.radius = 0.24
		fin.height = 0.02
		fin.rotation = Vector3(0.0, 0.0, PI * 0.5)
		fin.position = Vector3((f - 3) * 0.07, 0.0, 0.0)
		fin.material = sorter._mat_dark_steel
		motor.add_child(fin)

	# Fan Shroud Cowl (Back end)
	var fan_cowl := CSGCylinder3D.new()
	fan_cowl.name = "FanShroud"
	fan_cowl.radius = 0.23
	fan_cowl.height = 0.12
	fan_cowl.rotation = Vector3(0.0, 0.0, PI * 0.5)
	fan_cowl.position = Vector3(0.34, 0.0, 0.0)
	fan_cowl.material = sorter._mat_yellow
	motor.add_child(fan_cowl)

	# Electrical Junction Box
	var jbox := CSGBox3D.new()
	jbox.name = "JunctionBox"
	jbox.size = Vector3(0.18, 0.18, 0.14)
	jbox.position = Vector3(0.0, 0.22, 0.0)
	jbox.material = sorter._mat_dark_steel
	motor.add_child(jbox)

	# Gear Reduction Housing & Output Flange
	var gearbox := CSGBox3D.new()
	gearbox.name = "Gearbox"
	gearbox.size = Vector3(0.42, 0.42, 0.50)
	gearbox.position = Vector3(-0.30, 0.0, -0.20)
	gearbox.material = sorter._mat_dark_steel
	motor.add_child(gearbox)

	# Chain Guard Enclosure Box
	var guard := CSGBox3D.new()
	guard.name = "DriveChainGuard"
	guard.size = Vector3(0.25, 0.50, 0.45)
	guard.position = Vector3(-0.20, 0.0, -0.45)
	guard.material = sorter._mat_yellow
	motor.add_child(guard)

	drive_assembly.add_child(motor)
	sorter.add_child(drive_assembly)


func _build_sprocket(parent: Node, pos: Vector3, teeth_count: int = 10) -> void:
	var sprocket := Node3D.new()
	sprocket.name = "SprocketGear"
	sprocket.position = pos

	# Center hub (R = 0.075m matching 0.12m channel depth)
	var hub := CSGCylinder3D.new()
	hub.radius = 0.16
	hub.height = 0.05
	hub.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	hub.material = sorter._mat_sprocket_steel
	sprocket.add_child(hub)

	# Inner shaft collar
	var collar := CSGCylinder3D.new()
	collar.radius = 0.08
	collar.height = 0.09
	collar.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	collar.material = sorter._mat_dark_steel
	sprocket.add_child(collar)

	# Gear teeth
	var tooth_angle_step: float = (PI * 2.0) / float(teeth_count)
	for t in range(teeth_count):
		var angle: float = t * tooth_angle_step
		var tooth := CSGBox3D.new()
		tooth.size = Vector3(0.04, 0.05, 0.05)
		tooth.position = Vector3(cos(angle) * 0.175, sin(angle) * 0.175, 0.0)
		tooth.rotation = Vector3(0.0, 0.0, angle)
		tooth.material = sorter._mat_sprocket_steel
		sprocket.add_child(tooth)

	parent.add_child(sprocket)


func _build_pillow_block(parent: Node, pos: Vector3) -> void:
	var block := Node3D.new()
	block.name = "PillowBlockBearing"
	block.position = pos

	# Cast Iron Base
	var base := CSGBox3D.new()
	base.size = Vector3(0.18, 0.04, 0.22)
	base.material = sorter._mat_cast_iron
	block.add_child(base)

	# Bearing housing cap
	var cap := CSGCylinder3D.new()
	cap.radius = 0.08
	cap.height = 0.16
	cap.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cap.position = Vector3(0.0, 0.06, 0.0)
	cap.material = sorter._mat_cast_iron
	block.add_child(cap)

	# Chrome mounting bolts
	for bx in [-0.06, 0.06]:
		for bz in [-0.07, 0.07]:
			var bolt := CSGCylinder3D.new()
			bolt.radius = 0.012
			bolt.height = 0.08
			bolt.position = Vector3(bx, 0.03, bz)
			bolt.material = sorter._mat_chrome
			block.add_child(bolt)

	parent.add_child(block)
