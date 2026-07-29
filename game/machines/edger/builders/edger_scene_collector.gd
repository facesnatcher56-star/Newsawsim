@tool
extends RefCounted

## Introspects SawmillEdger's generated part tree, populating its
## station/part-tracking arrays from whatever is currently in the scene.

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func collect_generated_parts() -> void:
	if is_instance_valid(edger.infeed_system):
		edger.infeed_system.clear()
	edger._hold_down_stations.clear()
	edger._infeed_hold_down_stations.clear()
	edger._parking_ramp_stations.clear()
	edger._position_pin_stations.clear()
	edger._cushion_pin_stations.clear()
	edger._saw_blades.clear()
	edger._saw_teeth_roots.clear()

	for node in edger.find_children("*", "Node3D", true, false):
		var node_3d := node as Node3D
		if not is_instance_valid(node_3d):
			continue
		if node_3d.name.begins_with("FeedRoller"):
			if is_instance_valid(edger.infeed_system):
				edger.infeed_system.feed_rollers.append(node_3d)
		elif node_3d.name.begins_with("InfeedChainLink"):
			if is_instance_valid(edger.infeed_system):
				edger.infeed_system.chain_links.append(node_3d)
				edger.infeed_system.chain_bases.append(node_3d.position)
		elif node_3d.name.begins_with("EdgerSawBlade") and node_3d is CSGCylinder3D:
			edger._saw_blades.append(node_3d as CSGCylinder3D)
		elif node_3d.name.begins_with("EdgerSawTeeth"):
			edger._saw_teeth_roots.append(node_3d)
	_collect_infeed_hold_down_stations_from_scene()

	# Collect position pin stations if using saved assembly scenes
	var pos_assembly := edger.get_node_or_null("PositionPinAssembly") as Node3D
	if is_instance_valid(pos_assembly):
		var pins_map := {}
		var sleeves_map := {}
		for child in pos_assembly.get_children():
			if not child is Node3D:
				continue
			var name_parts := child.name.split("_")
			if name_parts.size() < 2:
				continue
			var suffix := name_parts[1]
			if child.name.begins_with("PositionPinSleeve"):
				sleeves_map[suffix] = child
			elif child.name.begins_with("PositionPin"):
				pins_map[suffix] = child

		var suffixes := pins_map.keys()
		suffixes.sort()
		for suffix in suffixes:
			var pin = pins_map[suffix] as Node3D
			var sleeve = sleeves_map.get(suffix) as Node3D
			if is_instance_valid(pin):
				var front_z: float = pin.position.z
				var retracted_y: float = pin.position.y
				var raised_y: float = retracted_y + 0.314
				var sleeve_retracted_y: float = 0.0
				var sleeve_raised_y: float = 0.0
				if is_instance_valid(sleeve):
					sleeve_retracted_y = sleeve.position.y
					sleeve_raised_y = sleeve_retracted_y + 0.314

				edger._position_pin_stations.append({
					"x": pin.position.x,
					"pin": pin,
					"sleeve": sleeve,
					"z": front_z,
					"retracted_y": retracted_y,
					"raised_y": raised_y,
					"sleeve_retracted_y": sleeve_retracted_y,
					"sleeve_raised_y": sleeve_raised_y,
					"extended": false,
				})

	# Collect cushion pin stations if using saved assembly scenes
	var cushion_assembly := edger.get_node_or_null("CushionPinAssembly") as Node3D
	if is_instance_valid(cushion_assembly):
		var station_nodes := {}
		var barrels_map := {}
		for child in cushion_assembly.get_children():
			if not child is Node3D:
				continue
			var name_parts := child.name.split("_")
			if name_parts.size() < 2:
				continue
			var suffix := name_parts[1]
			if child.name.begins_with("CushionCylinder"):
				barrels_map[suffix] = child
			elif child.name.begins_with("CushionPinAssembly"):
				station_nodes[suffix] = child

		var suffixes := station_nodes.keys()
		suffixes.sort()
		for suffix in suffixes:
			var body = station_nodes[suffix] as Node3D
			var barrel = barrels_map.get(suffix) as Node3D
			var rod = body.get_node_or_null("CushionRod") as Node3D
			var pad = body.get_node_or_null("CushionPad") as Node3D

			edger._cushion_pin_stations.append({
				"x": body.position.x,
				"body": body,
				"barrel": barrel,
				"rod": rod,
				"pad": pad,
				"base_z": body.position.z,
				"extended": false,
			})


func _collect_infeed_hold_down_stations_from_scene() -> void:
	var station_parts := {}
	for node in edger.find_children("*", "Node3D", true, false):
		var station_id := _hold_down_station_id(String(node.name))
		if station_id.is_empty():
			continue
		if not station_parts.has(station_id):
			station_parts[station_id] = {
				"bearings": [],
			}
		var parts: Dictionary = station_parts[station_id]
		if node.name.begins_with("InfeedHoldDownCrosshead"):
			parts["crosshead"] = node
		elif node.name.begins_with("InfeedHoldDownRoller"):
			parts["roller"] = node
		elif node.name.begins_with("InfeedHoldDownAxle"):
			parts["axle"] = node
		elif node.name.begins_with("InfeedHoldDownBearing"):
			parts["bearings"].append(node)
		elif node.name.begins_with("PneumaticCylinder"):
			parts["actuator_root"] = node

	var station_ids := station_parts.keys()
	station_ids.sort()
	for station_id in station_ids:
		var parts: Dictionary = station_parts[station_id]
		var crosshead := parts.get("crosshead") as Node3D
		var roller := parts.get("roller") as Node3D
		if not is_instance_valid(crosshead) or not is_instance_valid(roller):
			continue

		var moving_nodes: Array[Node3D] = [crosshead, roller]
		var axle := parts.get("axle") as Node3D
		if is_instance_valid(axle):
			moving_nodes.append(axle)
		var bearings: Array = parts["bearings"]
		for bearing in bearings:
			var bearing_node := bearing as Node3D
			if is_instance_valid(bearing_node):
				moving_nodes.append(bearing_node)

		var raised_y := roller.position.y
		var y_offsets: Array[float] = []
		for moving_node in moving_nodes:
			y_offsets.append(moving_node.position.y - raised_y)

		var station := {
			"x": roller.position.x,
			"roller": roller,
			"nodes": moving_nodes,
			"y_offsets": y_offsets,
			"raised_y": raised_y,
			"offset": edger.hold_down_system.hold_down_raised_offset if is_instance_valid(edger.hold_down_system) else 0.24,
		}
		var actuator_root := parts.get("actuator_root") as Node3D
		if is_instance_valid(actuator_root):
			var rod := actuator_root.get_node_or_null("PistonRod") as CSGCylinder3D
			var rod_top_y := -0.087
			if is_instance_valid(rod):
				rod_top_y = rod.position.y + rod.height * 0.5
			station["actuator"] = {
				"root": actuator_root,
				"attach_node": crosshead,
				"rod": rod,
				"clevis": actuator_root.get_node_or_null("RodClevis"),
				"pin_hole": actuator_root.get_node_or_null("ClevisPinHole"),
				"rod_top_y": rod_top_y,
			}
		edger._infeed_hold_down_stations.append(station)


func _hold_down_station_id(node_name: String) -> String:
	if not (
		node_name.begins_with("InfeedHoldDownCrosshead")
		or node_name.begins_with("InfeedHoldDownRoller")
		or node_name.begins_with("InfeedHoldDownAxle")
		or node_name.begins_with("InfeedHoldDownBearing")
		or node_name.begins_with("PneumaticCylinder")
	):
		return ""
	var name_parts := node_name.split("_")
	if name_parts.size() < 2:
		return ""
	return name_parts[1]
