extends Node

## Debug script to trace position pin trigger issues
## Attach to the scene root and monitor the connection between EdgerTakeAway and SawmillEdger

func _ready() -> void:
	print("=== POSITION PIN DEBUG START ===")
	_check_edger_takeaway()
	_check_sawmill_edger()
	_check_cut_board()

func _physics_process(_delta: float) -> void:
	_check_active_board()

func _check_edger_takeaway() -> void:
	var edger_takeaway = get_tree().root.get_node_or_null("EdgerTakeAway")
	if not is_instance_valid(edger_takeaway):
		print("[EdgerTakeAway] NOT FOUND in scene root")
		return

	print("\n[EdgerTakeAway] Found: ", edger_takeaway.name)

	# Check for top_zone
	var top_zone = edger_takeaway.get("top_zone")
	print("[EdgerTakeAway] top_zone property: ", "EXISTS" if top_zone != null else "MISSING")

	if is_instance_valid(top_zone):
		var bodies = top_zone.get_overlapping_bodies()
		print("[EdgerTakeAway] top_zone overlapping bodies count: ", bodies.size())
		for body in bodies:
			print("  - ", body.name, " (RigidBody3D: ", body is RigidBody3D, ")")
			if body is RigidBody3D:
				print("    Groups: ", body.get_groups())

	# Check for external_stop property
	var ext_stop = edger_takeaway.get("external_stop")
	print("[EdgerTakeAway] external_stop property: ", "EXISTS" if ext_stop != null else "MISSING")

func _check_sawmill_edger() -> void:
	var sawmill = get_tree().root.get_node_or_null("SawmillEdger")
	if not is_instance_valid(sawmill):
		print("\n[SawmillEdger] NOT FOUND in scene root")
		return

	print("\n[SawmillEdger] Found: ", sawmill.name)

	# Check internal state
	if sawmill.has_meta("_real_active_board"):
		var active_board = sawmill.get_meta("_real_active_board")
		print("[SawmillEdger] _real_active_board: ", active_board)

	# Check position pin stations
	var pin_count = sawmill.get("_position_pin_stations")
	if pin_count != null:
		print("[SawmillEdger] Position pin stations count: ", (pin_count as Array).size())

func _check_cut_board() -> void:
	var boards = get_tree().get_nodes_in_group("cut_boards")
	print("\n[CutBoards] Found ", boards.size(), " boards in 'cut_boards' group")

	for board in boards:
		if board is RigidBody3D:
			var local_pos = Vector3.ZERO
			var sawmill = get_tree().root.get_node_or_null("SawmillEdger")
			if is_instance_valid(sawmill):
				local_pos = sawmill.to_local(board.global_position)

			print("  - ", board.name)
			print("    RigidBody3D: yes")
			print("    Position: ", board.global_position)
			print("    Groups: ", board.get_groups())
			print("    Frozen: ", board.freeze if board.has_property("freeze") else "N/A")

func _check_active_board() -> void:
	# This runs every frame to monitor the state
	var sawmill = get_tree().root.get_node_or_null("SawmillEdger")
	if not is_instance_valid(sawmill):
		return

	# Access private variable using reflection (careful with this)
	var script = sawmill.get_script()
	if script == null:
		return

	# Try to read internal state via object inspection
	# This is a workaround since we can't directly access private members from outside
	var state_changed = false

	# Instead, check top_zone overlapping bodies
	var edger_takeaway = get_tree().root.get_node_or_null("EdgerTakeAway")
	if is_instance_valid(edger_takeaway):
		var top_zone = edger_takeaway.get("top_zone")
		if is_instance_valid(top_zone):
			var bodies = top_zone.get_overlapping_bodies()
			if not bodies.is_empty():
				# Board is in top zone - this should trigger pins!
				var first_board = bodies[0]
				if first_board is RigidBody3D and (first_board.is_in_group("cut_boards") or "board" in first_board.name.to_lower()):
					if not Engine.is_editor_hint():
						# Board should be triggering pins here
						var local_pos = sawmill.to_local(first_board.global_position)
						print("\n[ACTIVE TRIGGER] Board at top_zone: ", first_board.name, " at X=", local_pos.x)
