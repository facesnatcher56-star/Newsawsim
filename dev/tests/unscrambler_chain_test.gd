extends SceneTree

## Guards the unscrambler's chain rails.
##
## The chains used to be one Node3D per link with eight MeshInstance3D children
## per link: ~3,600 nodes and ~3,200 draw calls for a single 4-5 m machine, which
## was about half of the mill's draw calls. They are now one MultiMesh fed by a
## baked link mesh, so this test pins both the budget and the placement maths.

const UNSCRAMBLER := "res://game/machines/unscrambler/board_unscrambler.tscn"
const LEVEL := "res://game/levels/mill_prototype.tscn"
## Generous ceilings: they exist to catch a return to per-part nodes, not to
## forbid new detail.
const MAX_NODES := 250
const MAX_VISUALS := 150
const MILL_MAX_NODES := 8000
const MILL_MAX_VISUALS := 5200

var failures: int = 0

func _init() -> void:
	call_deferred("check")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func check() -> void:
	var unscrambler: Node = load(UNSCRAMBLER).instantiate()
	root.add_child(unscrambler)
	await process_frame
	await process_frame

	var counts: Dictionary = _count(unscrambler)
	expect(int(counts.nodes) <= MAX_NODES, "Unscrambler has %d nodes (budget %d)" % [counts.nodes, MAX_NODES])
	expect(int(counts.visuals) <= MAX_VISUALS, "Unscrambler has %d visual instances (budget %d)" % [counts.visuals, MAX_VISUALS])

	# One MultiMesh, no per-link nodes, and the link parts baked into one surface.
	var link_nodes: Array[Node] = []
	for child in unscrambler.get_children():
		if String(child.name).begins_with("ChainLinks"):
			link_nodes.append(child)
	expect(link_nodes.size() == 1, "Chain links must be a single MultiMesh, found %d nodes" % link_nodes.size())
	if link_nodes.is_empty():
		return
	var visuals: MultiMeshInstance3D = link_nodes[0]
	var mm: MultiMesh = visuals.multimesh
	expect(mm != null, "Chain link MultiMesh is missing")
	if mm == null:
		return
	expect(mm.mesh.get_surface_count() == 1, "Link parts are not baked into one surface")
	var slots: PackedFloat32Array = unscrambler.get("_anim_link_slots")
	var rails: PackedFloat32Array = unscrambler.get("_anim_link_zs")
	expect(slots.size() > 20, "Only %d link slots along the loop" % slots.size())
	expect(rails.size() >= 10, "Only %d chain rails" % rails.size())
	expect(mm.instance_count == slots.size() * rails.size(),
		"MultiMesh has %d instances for %d slots x %d rails" % [mm.instance_count, slots.size(), rails.size()])
	expect(rails[rails.size() - 1] - rails[0] > 4.0,
		"Chain rails only span %.2f m of the machine width" % (rails[rails.size() - 1] - rails[0]))

	# The pushers are the parts that touch boards: they must stay physical.
	expect(int(counts.bodies) >= 25, "Only %d unscrambler physics bodies left" % counts.bodies)
	expect(int(counts.shapes) >= 20, "Only %d unscrambler collision shapes left" % counts.shapes)

	# Placement: every slot sits somewhere different along the loop, and travel
	# moves a link by the distance the chain actually advanced.
	unscrambler.set("_anim_offset", 0.0)
	var seen: Array[Vector2] = []
	for j in range(slots.size()):
		var point: Vector2 = _origin_2d(unscrambler.call("_link_transform", j))
		var duplicate: bool = false
		for previous in seen:
			if previous.distance_to(point) < 0.001:
				duplicate = true
				break
		expect(not duplicate, "Link slot %d overlaps another link" % j)
		seen.append(point)

	var probe: int = 3
	unscrambler.set("_anim_offset", 0.0)
	var start: Vector2 = _origin_2d(unscrambler.call("_link_transform", probe))
	unscrambler.set("_anim_offset", 0.5)
	var moved: Vector2 = _origin_2d(unscrambler.call("_link_transform", probe))
	expect(absf(start.distance_to(moved) - 0.5) < 0.02,
		"Chain travel is not following the loop: link moved %.3f m for a 0.5 m advance" % start.distance_to(moved))

	# Whole-mill budget, so the next generator cannot quietly undo this.
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await process_frame
	await process_frame
	var mill_counts: Dictionary = _count(mill)
	expect(int(mill_counts.nodes) <= MILL_MAX_NODES,
		"Mill now has %d nodes (budget %d)" % [mill_counts.nodes, MILL_MAX_NODES])
	expect(int(mill_counts.visuals) <= MILL_MAX_VISUALS,
		"Mill now has %d visual instances (budget %d)" % [mill_counts.visuals, MILL_MAX_VISUALS])
	print("unscrambler: %d nodes, %d visuals | mill: %d nodes, %d visuals, %d multimesh instances" % [
		counts.nodes, counts.visuals, mill_counts.nodes, mill_counts.visuals, mill_counts.multimesh])
	print("failures: %d" % failures)
	mill.queue_free()
	await process_frame
	quit()

func _origin_2d(xform: Transform3D) -> Vector2:
	return Vector2(xform.origin.x, xform.origin.y)

func _count(node: Node) -> Dictionary:
	var out: Dictionary = {"nodes": 0, "visuals": 0, "multimesh": 0, "shapes": 0, "bodies": 0}
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		out.nodes += 1
		if current is VisualInstance3D:
			out.visuals += 1
		if current is MultiMeshInstance3D and (current as MultiMeshInstance3D).multimesh != null:
			out.multimesh += (current as MultiMeshInstance3D).multimesh.instance_count
		if current is CollisionShape3D and not (current as CollisionShape3D).disabled:
			out.shapes += 1
		if current is PhysicsBody3D:
			out.bodies += 1
		for c in current.get_children():
			stack.append(c)
	return out
