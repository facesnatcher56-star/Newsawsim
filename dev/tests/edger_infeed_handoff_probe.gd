extends SceneTree

## Follows the level's initial board from EdgerTakeAway toward the edger infeed.
## Reports physical contacts and fails if the board reaches the mill floor before
## becoming supported by the edger infeed chain.

const LEVEL := "res://game/levels/mill_prototype.tscn"


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var mill: Node3D = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await physics_frame

	var deck: Node3D = mill.get_node("EdgerTakeAway") as Node3D
	var edger: SawmillEdger = mill.get_node("SawmillEdger") as SawmillEdger
	var board: RigidBody3D = mill.get_node("InclineOutfeed/CutBoard") as RigidBody3D
	board.contact_monitor = true
	board.max_contacts_reported = 24

	var touched_edger_feed: bool = false
	var fell_to_floor: bool = false
	for frame: int in 1800:
		await physics_frame
		if not is_instance_valid(board):
			print("BOARD FREED frame=", frame)
			break
		var names := PackedStringArray()
		for collider: Node3D in board.get_colliding_bodies():
			names.append(String(collider.name))
			if String(collider.name) == "InfeedChainFeedBelt" or String(collider.name).contains("ParkingRamp"):
				touched_edger_feed = true
		var local_deck: Vector3 = deck.to_local(board.global_position)
		var local_edger: Vector3 = edger.to_local(board.global_position)
		if frame % 30 == 0 or board.global_position.y < -0.50:
			print("F%04d world=%s deck=%s edger=%s vel=%s freeze=%s contacts=%s deck_run=%s" % [
				frame, board.global_position, local_deck, local_edger, board.linear_velocity,
				board.freeze, ",".join(names), deck.get("running")])
		if board.global_position.y < -0.50 and not touched_edger_feed:
			fell_to_floor = true
			break
		if touched_edger_feed and local_edger.x > -3.0 and local_edger.y > edger.working_height - 0.20:
			print("ADVANCED ON EDGER FEED frame=", frame, " local=", local_edger)
			break

	print("EDGER_INFEED_HANDOFF_PROBE touched_feed=%s fell_to_floor=%s" % [touched_edger_feed, fell_to_floor])
	quit(1 if fell_to_floor or not touched_edger_feed else 0)
