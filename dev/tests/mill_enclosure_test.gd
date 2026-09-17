extends SceneTree

## Guards the mill enclosure: every machine in the level has to stand on the
## floor slab, clear the walls, and sit under the roof with room to spare.

const LEVEL := "res://game/levels/mill_prototype.tscn"
const IGNORED_ROOTS: Array[String] = ["Ground", "MillBuilding", "SkyClouds", "Camera3D", "DirectionalLight3D"]
## How far a machine must stay clear of the innermost face of a wall pilaster.
const MIN_WALL_CLEARANCE := 0.5
## How much headroom a machine must have under the roof.
const MIN_ROOF_CLEARANCE := 0.5

var failures: int = 0

func _init() -> void:
	call_deferred("check")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func check() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var building: Node3D = level.get_node_or_null("MillBuilding")
	expect(building != null, "Level has no MillBuilding node")
	if building == null:
		return
	var visuals: Node = building.get_node_or_null("Visuals")
	var structure: Node = building.get_node_or_null("Structure")
	expect(visuals != null and visuals.get_child_count() > 40, "Mill building generated too little geometry")
	expect(structure != null and structure.get_child_count() > 40, "Mill building generated too little collision")

	# Shadow-casting lights are the known frame-time killer in this mill: the
	# scene is always moving, so every one of them redraws a shadow map per frame.
	var light_count: int = 0
	var shadow_lights: int = 0
	for node in building.find_children("*", "Light3D", true, false):
		light_count += 1
		if (node as Light3D).shadow_enabled:
			shadow_lights += 1
	expect(shadow_lights <= 4, "Enclosure adds %d shadow-casting lights" % shadow_lights)
	expect(light_count <= 16, "Enclosure adds %d work lights" % light_count)

	var floor_box: AABB = _floor_box(level)
	var floor_rect := Rect2(floor_box.position.x, floor_box.position.z, floor_box.size.x, floor_box.size.z)
	var wall_bottom: float = float(building.get("wall_bottom"))
	var origin: Vector3 = building.global_position
	var half_w: float = float(building.get("width")) * 0.5
	var half_l: float = float(building.get("length")) * 0.5
	var pilaster_half: float = 0.35
	expect(wall_bottom < floor_box.end.y - 0.05, "Wall foot must sit below the floor surface")

	var machine_count: int = 0
	var envelope := AABB()
	for child in level.get_children():
		if not (child is Node3D) or IGNORED_ROOTS.has(String(child.name)):
			continue
		var box: AABB = _world_aabb(child)
		if box.size == Vector3.ZERO:
			continue
		machine_count += 1
		var machine: String = String(child.name)
		if machine_count == 1:
			envelope = box
		else:
			envelope = envelope.merge(box)
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		expect(floor_rect.encloses(footprint), "%s overhangs the floor slab" % machine)
		expect(box.position.x - origin.x > -half_w + pilaster_half + MIN_WALL_CLEARANCE, "%s is buried in the -X wall" % machine)
		expect(box.end.x - origin.x < half_w - pilaster_half - MIN_WALL_CLEARANCE, "%s is buried in the +X wall" % machine)
		expect(box.position.z - origin.z > -half_l + pilaster_half + MIN_WALL_CLEARANCE, "%s is buried in the -Z wall" % machine)
		expect(box.end.z - origin.z < half_l - pilaster_half - MIN_WALL_CLEARANCE, "%s is buried in the +Z wall" % machine)
		var far_x: float = maxf(absf(box.position.x - origin.x), absf(box.end.x - origin.x))
		var roof_y: float = float(building.call("_roof_underside", far_x))
		expect(roof_y - box.end.y > MIN_ROOF_CLEARANCE, "%s has only %.2fm of headroom under the roof" % [machine, roof_y - box.end.y])

	expect(machine_count >= 10, "Expected the full mill, only found %d machines" % machine_count)
	print("machines: %d, envelope %s .. %s" % [machine_count, envelope.position.snapped(Vector3(0.01, 0.01, 0.01)), envelope.end.snapped(Vector3(0.01, 0.01, 0.01))])
	print("floor slab: %s .. %s" % [floor_box.position.snapped(Vector3(0.01, 0.01, 0.01)), floor_box.end.snapped(Vector3(0.01, 0.01, 0.01))])
	print("building footprint: x %.2f .. %.2f, z %.2f .. %.2f, walls %.2f .. %.2f" % [origin.x - half_w, origin.x + half_w, origin.z - half_l, origin.z + half_l, wall_bottom, float(building.get("wall_top"))])
	print("failures: %d" % failures)
	level.queue_free()
	await process_frame
	quit()

func _floor_box(level: Node) -> AABB:
	var shape_node: Node3D = level.get_node("Ground/CollisionShape3D")
	var shape: BoxShape3D = shape_node.shape as BoxShape3D
	var size: Vector3 = shape.size
	var center: Vector3 = shape_node.global_position
	return AABB(center - size * 0.5, size)

func _world_aabb(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	var start: Transform3D = (node as Node3D).transform if node is Node3D else Transform3D.IDENTITY
	_collect(node, start, boxes)
	if boxes.is_empty():
		return AABB()
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	return box

func _collect(node: Node, xform: Transform3D, out: Array[AABB]) -> void:
	var local: AABB = _node_aabb(node)
	if local.size != Vector3.ZERO:
		out.append(xform * local)
	for child in node.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		_collect(child, child_xform, out)

func _node_aabb(node: Node) -> AABB:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).get_aabb()
	if node is CSGShape3D:
		return (node as CSGShape3D).get_aabb()
	if node is CollisionShape3D:
		return _shape_aabb((node as CollisionShape3D).shape)
	return AABB()

func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		return AABB(Vector3(-radius, -radius, -radius), Vector3(radius, radius, radius) * 2.0)
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.is_empty():
			return AABB()
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		return box
	return AABB()
