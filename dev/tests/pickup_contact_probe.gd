extends SceneTree

## Contact-point probe of the deck -> incline hand-over.
##
## Prints every solver contact on the tracked board, in incline-local
## coordinates, while it crosses the pickup. Reading the contact heights against
## the board's own face angle shows what is actually lifting it: a lug standing
## proud of the deck under the board's underside, or a lug pushing its trailing
## face. Guessing from body names alone cannot tell those apart.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/pickup_contact_probe.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 1500

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill

	var incline: Node3D = mill.get_node("BoardLugIncline")
	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no board")
		quit(1)
		return
	board.contact_monitor = true
	board.max_contacts_reported = 16

	print("tracking %s" % board.name)
	var state: PhysicsDirectBodyState3D = null
	for frame in range(FRAMES):
		await physics_frame
		if not is_instance_valid(board):
			break
		var local: Vector3 = incline.to_local(board.global_position)
		if local.z < -1.0 or local.z > 1.2:
			continue
		state = PhysicsServer3D.body_get_direct_state(board.get_rid())
		if state == null:
			continue
		var basis: Basis = board.global_transform.basis
		var face: float = rad_to_deg(acos(clampf(absf(basis.y.normalized().dot(Vector3.UP)), 0.0, 1.0)))
		var swing: float = rad_to_deg(acos(clampf(absf(basis.x.normalized().dot(Vector3.RIGHT)), 0.0, 1.0)))
		var parts: Array[String] = []
		for index in state.get_contact_count():
			var point: Vector3 = incline.to_local(state.get_contact_local_position(index))
			var other: Object = state.get_contact_collider_object(index)
			var label: String = String((other as Node).name) if other is Node else "?"
			parts.append("%s@(x%.2f z%.2f y%.2f)" % [label, point.x, point.z, point.y])
		print("f%4d z%7.3f y%6.3f face%5.0f swing%5.0f contacts=%d\n        %s" % [
			frame, local.z, local.y, face, swing, state.get_contact_count(),
			"\n        ".join(parts)])
		if local.z > 1.15:
			break
	quit(0)

func _pick_board(mill: Node) -> RigidBody3D:
	var all: Array = mill.find_children("*", "RigidBody3D", true, false).filter(
		func(n: Node) -> bool:
			return n.is_in_group("cut_boards") or "CutBoard" in String(n.name))
	var near: Array = all.filter(
		func(b: Node) -> bool: return absf((b as Node3D).global_position.z - 18.29) < 0.5)
	return (near[0] if not near.is_empty() else all[0]) as RigidBody3D
