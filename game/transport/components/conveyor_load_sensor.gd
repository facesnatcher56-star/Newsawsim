class_name ConveyorLoadSensor
extends RefCounted

## Shared contact-proximity check for powered beds without an existing Area3D.
## Bounds are in the machine's local coordinates and cover the carrying surface,
## not the surrounding mill or the chain's unloaded return. Only physical lumber
## counts; settled boards in neighboring bins and scenery cannot start a drive.
static func has_load(machine: Node3D, low: Vector3, high: Vector3,
		boards: bool = true, logs: bool = true) -> bool:
	if not machine.is_inside_tree():
		return false
	if boards:
		for node: Node in machine.get_tree().get_nodes_in_group("cut_boards"):
			if _within(machine, node, low, high):
				return true
	if logs:
		for node: Node in machine.get_tree().get_nodes_in_group("logs"):
			if _within(machine, node, low, high):
				return true
	return false


static func _within(machine: Node3D, node: Node, low: Vector3, high: Vector3) -> bool:
	var body: RigidBody3D = node as RigidBody3D
	if not is_instance_valid(body) or body.freeze:
		return false
	var at: Vector3 = machine.to_local(body.global_position)
	var extent: Vector3 = Vector3.ZERO
	# A long board can rest on its leading end while its centre is still well
	# outside the bed. Sense its real collision footprint, not just its origin.
	var shape_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var half: Vector3 = (shape_node.shape as BoxShape3D).size * 0.5
		var axes: Basis = machine.global_transform.affine_inverse().basis * body.global_basis
		extent = Vector3(
			absf(axes.x.x) * half.x + absf(axes.y.x) * half.y + absf(axes.z.x) * half.z,
			absf(axes.x.y) * half.x + absf(axes.y.y) * half.y + absf(axes.z.y) * half.z,
			absf(axes.x.z) * half.x + absf(axes.y.z) * half.y + absf(axes.z.z) * half.z)
	return at.x + extent.x >= low.x and at.x - extent.x <= high.x \
		and at.y + extent.y >= low.y and at.y - extent.y <= high.y \
		and at.z + extent.z >= low.z and at.z - extent.z <= high.z
