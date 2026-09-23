extends SceneTree

## Every continuously powered chain in the mill starts at rest, wakes for
## physical lumber on its own carrying bed, and returns to idle after a delay.
const MILL := "res://game/levels/mill_prototype.tscn"
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if ok:
		print("ok: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame

func _load(parent: Node3D, local_position: Vector3, group: String) -> RigidBody3D:
	var load_body: RigidBody3D = RigidBody3D.new()
	load_body.name = "PhysicalLoadProbe"
	load_body.add_to_group(group)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.28, 0.16, 0.28)
	collision.shape = box
	load_body.add_child(collision)
	parent.get_parent().add_child(load_body)
	load_body.global_position = parent.to_global(local_position)
	return load_body

func run() -> void:
	var mill: Node3D = load(MILL).instantiate()
	root.add_child(mill)
	current_scene = mill
	for group: String in ["logs", "cut_boards"]:
		for node: Node in get_nodes_in_group(group):
			if node is RigidBody3D:
				(node as RigidBody3D).free()
	await frames(90)
	var chain_deck: StaticBody3D = mill.get_node("LogFeedStation/DebarkDeckTest")
	var trough: StaticBody3D = mill.get_node("DebarkerStation/DebarkInfeedConveyor")
	var incline: StaticBody3D = mill.get_node("InclineOutfeed/InclineChainConveyor")
	var sorter: BinSorter = mill.get_node("BinSorter")
	var landing: EdgerLandingDeck = mill.get_node("landing_deck_frame")
	var unscrambler: StaticBody3D = mill.get_node("InclineOutfeed/BoardUnscrambler")
	expect(chain_deck.constant_linear_velocity.is_zero_approx(), "empty chain-log deck is stopped")
	expect(trough.constant_linear_velocity.is_zero_approx(), "empty trough chains are stopped")
	expect(incline.constant_linear_velocity.is_zero_approx(), "empty log incline chain is stopped")
	expect(landing.actual_speed < 0.02, "empty landing chains are stopped")
	expect(unscrambler.constant_linear_velocity.is_zero_approx(), "empty board unscrambler is stopped")
	expect(not sorter._top_active and not sorter._haulout_active, "sorter overhead and floor chains are stopped")

	var deck_log: RigidBody3D = _load(chain_deck, Vector3(-1.1, 1.29, 0.0), "logs")
	var trough_log: RigidBody3D = _load(trough, Vector3(0.0, 0.16, 0.0), "logs")
	var incline_log: RigidBody3D = _load(incline, Vector3(0.0, 0.29, 0.0), "logs")
	await frames(25)
	expect(bool(chain_deck.get("_drive_active")), "log landing wakes chain-log deck (retractable stops may hold its motor)")
	expect(not trough.constant_linear_velocity.is_zero_approx(), "log landing starts trough chain and its animation")
	expect(not incline.constant_linear_velocity.is_zero_approx(), "log landing starts inclined chain")
	deck_log.free()
	trough_log.free()
	incline_log.free()
	await frames(155)
	expect(chain_deck.constant_linear_velocity.is_zero_approx(), "chain-log deck parks after its load leaves")
	expect(trough.constant_linear_velocity.is_zero_approx(), "trough parks after its load leaves")
	expect(incline.constant_linear_velocity.is_zero_approx(), "log incline parks after its load leaves")
	mill.free()
	print("CHAIN_LOAD_IDLE_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)
