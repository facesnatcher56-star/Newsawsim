class_name SorterCollisionBuilder
extends RefCounted

## Builds runtime collision bodies and detection triggers for the 50-bay bin sorter.

static func build(sorter: Node3D, gate_nodes: Array[Node3D]) -> Dictionary:
	var old := sorter.get_node_or_null("RuntimeParts")
	if is_instance_valid(old):
		old.free()

	var parts := Node3D.new()
	parts.name = "RuntimeParts"
	sorter.add_child(parts)

	var smooth_mat := PhysicsMaterial.new()
	smooth_mat.friction = 0.15
	smooth_mat.bounce = 0.0

	var haulout_mat := PhysicsMaterial.new()
	haulout_mat.friction = 0.50
	haulout_mat.bounce = 0.0

	var num_bays: int = int(sorter.get("num_bins"))
	var bay_w: float = float(sorter.get("bin_width"))
	var bay_d: float = float(sorter.get("bin_depth"))
	var sorter_h: float = float(sorter.get("sorter_height"))
	var conv_speed: float = float(sorter.get("conveyor_speed"))
	var total_len: float = num_bays * bay_w

	# 1. Infeed Table Approach Plate
	var infeed_bed := StaticBody3D.new()
	infeed_bed.name = "InfeedBed"
	infeed_bed.physics_material_override = smooth_mat
	infeed_bed.constant_linear_velocity = sorter.global_basis.x * conv_speed
	parts.add_child(infeed_bed)
	_add_box_col(infeed_bed, Vector3(-0.3, sorter_h - 0.02, 0.0), Vector3(0.60, 0.04, 4.4))

	# 2. Inter-bay crossbeam supports (Boundary divider ties)
	var beam_supports := StaticBody3D.new()
	beam_supports.name = "BayTopBeams"
	beam_supports.physics_material_override = smooth_mat
	parts.add_child(beam_supports)
	for i in range(num_bays + 1):
		var bx: float = i * bay_w
		_add_box_col(beam_supports, Vector3(bx, sorter_h - 0.04, 0.0), Vector3(0.08, 0.08, 4.4))

	# 3. Dynamic Hinged Diverter Drop Gate Collisions
	var gate_bodies: Array[AnimatableBody3D] = []
	for b in range(gate_nodes.size()):
		var g_body := AnimatableBody3D.new()
		g_body.name = "GateCollision_%02d" % b
		g_body.sync_to_physics = true
		g_body.physics_material_override = smooth_mat
		parts.add_child(g_body)
		g_body.position = Vector3(b * bay_w + 0.08, sorter_h, 0.0)
		# Local skid position relative to gate hinge (hinge is at X=0, Y=0)
		_add_box_col(g_body, Vector3(0.38, -0.025, 0.0), Vector3(0.76, 0.05, 4.0))
		gate_bodies.append(g_body)

	# 4. Floor Haul-Out Conveyor Bed (Deck at Y = 0.20m, clear pack corridor)
	var floor_bed := StaticBody3D.new()
	floor_bed.name = "FloorHauloutBed"
	floor_bed.physics_material_override = haulout_mat
	parts.add_child(floor_bed)
	_add_box_col(floor_bed, Vector3(total_len * 0.5, 0.15, 0.0), Vector3(total_len + 2.0, 0.10, 4.4))

	# 5. Full-Depth Bay Divider Containment Walls (Y from 1.60m to 4.30m, leaving 1.4m haul-out tunnel)
	var dividers := StaticBody3D.new()
	dividers.name = "BayDividers"
	dividers.physics_material_override = smooth_mat
	parts.add_child(dividers)
	for i in range(num_bays + 1):
		var x: float = i * bay_w
		_add_box_col(dividers, Vector3(x, 2.95, 0.0), Vector3(0.08, 2.70, 5.0))

	# 6. Movable Cradle Collision Bodies (One per bay with 4 load forks interleaved between haulout chains)
	var cradle_bodies: Array[AnimatableBody3D] = []
	for b in range(num_bays):
		var cradle_col_body := AnimatableBody3D.new()
		cradle_col_body.name = "CradleCollision_%02d" % b
		cradle_col_body.sync_to_physics = true
		cradle_col_body.physics_material_override = smooth_mat
		parts.add_child(cradle_col_body)
		var x_c: float = b * bay_w + bay_w * 0.5
		# Spine beam along Z
		_add_box_col(cradle_col_body, Vector3(-0.35, 0.0, 0.0), Vector3(0.16, 0.12, 4.8))
		# 4 cantilever support forks matching CARRIAGE_FORKS = [-1.5, -0.5, 0.5, 1.5]
		for z_fk: float in [-1.5, -0.5, 0.5, 1.5]:
			_add_box_col(cradle_col_body, Vector3(0.0, -0.03, z_fk), Vector3(bay_w * 0.76, 0.06, 0.12))
		cradle_col_body.position = Vector3(x_c, 3.80, 0.0)
		cradle_bodies.append(cradle_col_body)

	# 7. Infeed Scanner Detection Zone
	var infeed_zone := Area3D.new()
	infeed_zone.name = "InfeedScannerZone"
	parts.add_child(infeed_zone)
	var zone_col := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(1.2, 1.0, bay_d)
	zone_col.shape = zone_shape
	zone_col.position = Vector3(-0.3, sorter_h + 0.3, 0.0)
	infeed_zone.add_child(zone_col)

	return {
		"floor_bed": floor_bed,
		"cradle_bodies": cradle_bodies,
		"gate_bodies": gate_bodies,
		"infeed_zone": infeed_zone
	}

static func _add_box_col(parent: Node3D, pos: Vector3, size: Vector3) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	parent.add_child(col)
	return col
