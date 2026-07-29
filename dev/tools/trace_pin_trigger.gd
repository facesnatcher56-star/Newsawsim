extends Node
## Trace the exact disconnect in position pin triggering

var sawmill_edger: Node3D
var edger_takeaway: Node3D

func _ready() -> void:
	sawmill_edger = get_tree().root.get_node_or_null("SawmillEdger")
	edger_takeaway = get_tree().root.get_node_or_null("EdgerTakeAway")

	print("\n╔════ PIN TRIGGER ANALYSIS ════╗")
	print("║ Checking position pin detection chain...")
	_analyze_structure()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_check_board_detection()

func _analyze_structure() -> void:
	print("\n1. STRUCTURE CHECK:")
	print("   SawmillEdger: ", "✓ Found" if is_instance_valid(sawmill_edger) else "✗ MISSING")
	print("   EdgerTakeAway: ", "✓ Found" if is_instance_valid(edger_takeaway) else "✗ MISSING")

	if not is_instance_valid(edger_takeaway):
		print("\n   Looking for EdgerTakeAway in tree...")
		var all_nodes = get_tree().get_nodes_in_group("node")
		var found = false
		for node in get_tree().root.find_children("*", "Node3D"):
			if node.name == "EdgerTakeAway":
				print("   Found EdgerTakeAway at: ", node.get_path())
				found = true
				break
		if not found:
			print("   EdgerTakeAway not found anywhere in scene!")
		return

	print("\n2. DECK REFERENCE CHECK:")
	var deck = edger_takeaway
	print("   Deck name: ", deck.name)
	print("   Deck class: ", deck.get_class())

	# Check if deck has top_zone property
	var has_top_zone_prop = "top_zone" in deck
	print("   Has 'top_zone' property: ", "✓ Yes" if has_top_zone_prop else "✗ No")

	if not has_top_zone_prop:
		print("   Available properties:")
		for prop in deck.get_property_list():
			if "zone" in prop.name.to_lower():
				print("     - ", prop.name)

	# Try to get top_zone
	var top_zone = null
	if deck.has_method("get"):
		top_zone = deck.get("top_zone")
	elif has_top_zone_prop:
		top_zone = deck.top_zone

	print("   top_zone value: ", "✓ Valid Area3D" if is_instance_valid(top_zone) else "✗ Null or invalid")

	if is_instance_valid(top_zone):
		print("\n3. TOP_ZONE CONTENT CHECK:")
		print("   Zone name: ", top_zone.name)
		print("   Zone path: ", top_zone.get_path())

		# Get collision shape (the actual trigger)
		var col_shape = top_zone.get_node_or_null("CollisionShape3D")
		print("   CollisionShape3D: ", "✓ Found" if is_instance_valid(col_shape) else "✗ Missing")

func _check_board_detection() -> void:
	if not is_instance_valid(sawmill_edger) or not is_instance_valid(edger_takeaway):
		return

	var deck = edger_takeaway
	var top_zone = null

	if deck.has_method("get"):
		top_zone = deck.get("top_zone")
	else:
		top_zone = deck.top_zone if "top_zone" in deck else null

	if not is_instance_valid(top_zone):
		return

	var overlapping_bodies = top_zone.get_overlapping_bodies()

	if not overlapping_bodies.is_empty():
		print("\n╔════ BOARD DETECTED IN TOP_ZONE ════╗")
		for body in overlapping_bodies:
			print("  Body: ", body.name)
			print("    - Type: ", body.get_class())
			print("    - Is RigidBody3D: ", body is RigidBody3D)
			if body is RigidBody3D:
				print("    - Groups: ", body.get_groups())
				print("    - In 'cut_boards': ", body.is_in_group("cut_boards"))
				print("    - 'board' in name: ", "board" in body.name.to_lower())
				print("    - Would trigger pins: ", (body.is_in_group("cut_boards") or "board" in body.name.to_lower()))

				# Check position pin stations
				var pin_stations = sawmill_edger.get("_position_pin_stations")
				if pin_stations != null:
					var pin_count = (pin_stations as Array).size()
					print("    - Available position pin stations: ", pin_count)
					if pin_count == 0:
						print("      ⚠ WARNING: No position pin stations!")
