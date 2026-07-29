@tool
extends RefCounted

## Builds the chain trough conveyor's V-trough bed (visual CSG geometry) and
## keeps the matching collision shapes in sync with the same slope math.

var conveyor: Node


func _init(p_conveyor: Node) -> void:
	conveyor = p_conveyor


func build_trough_bed() -> void:
	var visuals_root: Node3D = conveyor._visuals_root
	var conveyor_width: float = conveyor.conveyor_width
	var conveyor_length: float = conveyor.conveyor_length
	var bed_plate_t: float = conveyor.BED_PLATE_T

	var bed_comb := CSGCombiner3D.new()
	bed_comb.name = "TroughBed"
	bed_comb.use_collision = false # Collision is handled by parent CollisionShape3D
	visuals_root.add_child(bed_comb)

	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.24, 0.26, 0.28)
	mat_metal.metallic = 0.8
	mat_metal.roughness = 0.45

	# Read wall positions from scene if they exist, otherwise fallback to default conveyor_width
	var left_wall_x: float = -conveyor_width * 0.5
	var right_wall_x: float = conveyor_width * 0.5

	var left_wall_node: Node3D = conveyor.get_node_or_null("LeftWall")
	var right_wall_node: Node3D = conveyor.get_node_or_null("RightWall")

	if left_wall_node:
		left_wall_x = left_wall_node.position.x
	if right_wall_node:
		right_wall_x = right_wall_node.position.x

	# Update effective width
	var eff_width: float = right_wall_x - left_wall_x

	# Flat bottom width is centered around the outer chains
	var track_x_positions: Array = conveyor.track_x_positions
	var max_x: float = 0.0
	for tx in track_x_positions:
		max_x = maxf(max_x, absf(tx))
	var bottom_width: float = max_x * 2.0 + 0.10 # 5cm margin on each side of outer chains
	bottom_width = clampf(bottom_width, 0.20, eff_width - 0.05)

	# Bottom flat channel
	var bottom_plate := CSGBox3D.new()
	bottom_plate.name = "BottomPlate"
	bottom_plate.size = Vector3(bottom_width, bed_plate_t, conveyor_length)
	bottom_plate.position = Vector3((left_wall_x + right_wall_x) * 0.5, -0.02, 0.0)
	bottom_plate.material = mat_metal
	bed_comb.add_child(bottom_plate)

	# Slopes
	var theta: float = deg_to_rad(25.0)
	var left_dx: float = absf(left_wall_x) - bottom_width * 0.5
	var right_dx: float = right_wall_x - bottom_width * 0.5

	# Left slope
	if left_dx > 0.01:
		var w_slope: float = left_dx / cos(theta)
		var dy: float = left_dx * tan(theta)
		var left_slope := CSGBox3D.new()
		left_slope.name = "LeftSlope"
		left_slope.size = Vector3(w_slope, bed_plate_t, conveyor_length)
		left_slope.position = Vector3(left_wall_x + left_dx * 0.5, -0.02 + dy * 0.5 + 0.015, 0.0)
		left_slope.rotation_degrees = Vector3(0.0, 0.0, -25.0)
		left_slope.material = mat_metal
		bed_comb.add_child(left_slope)

	# Right slope
	if right_dx > 0.01:
		var w_slope: float = right_dx / cos(theta)
		var dy: float = right_dx * tan(theta)
		var right_slope := CSGBox3D.new()
		right_slope.name = "RightSlope"
		right_slope.size = Vector3(w_slope, bed_plate_t, conveyor_length)
		right_slope.position = Vector3(right_wall_x - right_dx * 0.5, -0.02 + dy * 0.5 + 0.015, 0.0)
		right_slope.rotation_degrees = Vector3(0.0, 0.0, 25.0)
		right_slope.material = mat_metal
		bed_comb.add_child(right_slope)


func rebuild_collision() -> void:
	var bed_plate_t: float = conveyor.BED_PLATE_T
	var conveyor_width: float = conveyor.conveyor_width
	var conveyor_length: float = conveyor.conveyor_length
	var track_x_positions: Array = conveyor.track_x_positions

	var col_bottom := conveyor.get_node_or_null("CollisionBottom") as CollisionShape3D
	var col_left := conveyor.get_node_or_null("CollisionLeft") as CollisionShape3D
	var col_right := conveyor.get_node_or_null("CollisionRight") as CollisionShape3D
	var log_area := conveyor.get_node_or_null("LogArea") as Area3D
	var log_area_col := log_area.get_node_or_null("CollisionShape3D") as CollisionShape3D if log_area else null

	var left_wall_node: Node3D = conveyor.get_node_or_null("LeftWall")
	var right_wall_node: Node3D = conveyor.get_node_or_null("RightWall")
	var left_wall_x: float = left_wall_node.position.x if left_wall_node else -conveyor_width * 0.5
	var right_wall_x: float = right_wall_node.position.x if right_wall_node else conveyor_width * 0.5
	var eff_width: float = right_wall_x - left_wall_x

	# Flat bottom width is centered around the outer chains
	var max_x: float = 0.0
	for tx in track_x_positions:
		max_x = maxf(max_x, absf(tx))
	var bottom_width: float = max_x * 2.0 + 0.10
	bottom_width = clampf(bottom_width, 0.20, eff_width - 0.05)

	if col_bottom:
		var shape := BoxShape3D.new()
		shape.size = Vector3(bottom_width, bed_plate_t, conveyor_length)
		col_bottom.shape = shape
		col_bottom.position = Vector3((left_wall_x + right_wall_x) * 0.5, -0.02, 0.0)

	var theta: float = deg_to_rad(25.0)
	var left_dx: float = absf(left_wall_x) - bottom_width * 0.5
	var right_dx: float = right_wall_x - bottom_width * 0.5

	if col_left:
		if left_dx > 0.01:
			var w_slope: float = left_dx / cos(theta)
			var dy: float = left_dx * tan(theta)
			var shape := BoxShape3D.new()
			shape.size = Vector3(w_slope, bed_plate_t, conveyor_length)
			col_left.shape = shape
			col_left.position = Vector3(left_wall_x + left_dx * 0.5, -0.02 + dy * 0.5 + 0.015, 0.0)
			col_left.rotation_degrees = Vector3(0.0, 0.0, -25.0)
		else:
			col_left.shape = null

	if col_right:
		if right_dx > 0.01:
			var w_slope: float = right_dx / cos(theta)
			var dy: float = right_dx * tan(theta)
			var shape := BoxShape3D.new()
			shape.size = Vector3(w_slope, bed_plate_t, conveyor_length)
			col_right.shape = shape
			col_right.position = Vector3(right_wall_x - right_dx * 0.5, -0.02 + dy * 0.5 + 0.015, 0.0)
			col_right.rotation_degrees = Vector3(0.0, 0.0, 25.0)
		else:
			col_right.shape = null

	if log_area_col:
		var shape := BoxShape3D.new()
		shape.size = Vector3(eff_width - 0.05, 0.8, conveyor_length + 0.05)
		log_area_col.shape = shape
		log_area.position = Vector3((left_wall_x + right_wall_x) * 0.5, 0.3, 0.0)
