@tool
extends RefCounted

## Builds the unscrambler's static structure: steel side plates, cross
## members, and the working-surface tray (with chain grooves/slots cut in).

var unscrambler: Node


func _init(p_unscrambler: Node) -> void:
	unscrambler = p_unscrambler


func build_side_plates() -> void:
	_build_side_plate(0.0)
	_build_side_plate(unscrambler.machine_width)


func _build_side_plate(z_pos: float) -> void:
	var poly := PackedVector2Array()
	var s: float = unscrambler.profile_scale
	for pt in unscrambler._OUTER:
		poly.append(pt * s)
	for i in range(unscrambler._INNER_OFFSETS.size() - 1, -1, -1):
		poly.append(unscrambler._INNER_OFFSETS[i] * s)

	var plate_thickness: float = unscrambler.plate_thickness
	var csg := CSGPolygon3D.new()
	csg.name = "SidePlate_Z%d" % int(z_pos * 100)
	csg.polygon = poly
	csg.mode = CSGPolygon3D.MODE_DEPTH
	csg.depth = plate_thickness
	csg.position = Vector3(0.0, 0.0, z_pos - plate_thickness * 0.5)
	csg.material = unscrambler._mat_plate
	csg.use_collision = true
	unscrambler.add_child(csg)


func build_cross_members() -> void:
	var s: float = unscrambler.profile_scale
	var machine_width: float = unscrambler.machine_width
	var plate_thickness: float = unscrambler.plate_thickness
	# Positions along the profile where cross beams sit (X, Y midpoints of outer edge)
	var beam_positions: Array[Vector2] = [
		Vector2(-1.20, -0.08),   # entry zone bottom
		Vector2(-0.33, -0.36),   # inside the V-notch
		Vector2( 0.36,  0.54),   # mid curve
		Vector2( 0.91,  1.03),   # upper curve / arc zone
		Vector2( 1.78,  1.083),  # exit flat mid
	]
	for bp in beam_positions:
		var pos: Vector2 = bp * s
		pos.y -= 0.08 * s
		_add_beam(pos, Vector3(0.06, 0.06, machine_width + plate_thickness))


func _add_beam(profile_pos: Vector2, size: Vector3) -> void:
	var box := CSGBox3D.new()
	box.name = "Beam"
	box.size = size
	box.position = Vector3(
		profile_pos.x,
		profile_pos.y,
		unscrambler.machine_width * 0.5
	)
	box.material = unscrambler._mat_plate
	box.use_collision = true
	unscrambler.add_child(box)


func build_working_surface() -> void:
	var s: float = unscrambler.profile_scale
	var machine_width: float = unscrambler.machine_width
	var plate_thickness: float = unscrambler.plate_thickness
	var chain_diameter: float = unscrambler.chain_diameter
	var chain_spacing: float = unscrambler.chain_spacing
	# Thin steel tray panels that follow the profile segments segment-by-segment
	var segments: Array[Array] = [
		# [from_outer_index, to_outer_index]  — profile now has 9 points (0-8)
		[0, 1],   # entry flat
		[1, 2],   # V left slope  (down to apex)
		[2, 3],   # V right slope (up from apex)
		[3, 4],   # lower curve
		[4, 5],   # curve mid
		[5, 6],   # curve upper
		[6, 7],   # near-flat approach
		[7, 8],   # exit flat
	]
	for seg in segments:
		var a: Vector2 = unscrambler._OUTER[seg[0]] * s
		var b: Vector2 = unscrambler._OUTER[seg[1]] * s
		var mid := (a + b) * 0.5
		var diff := b - a
		var length := diff.length()
		if length < 0.01:
			continue
		var angle := atan2(diff.y, diff.x)

		# Make plates thicker (0.06m) so we can cut out grooves for the chains
		var surface_thickness: float = 0.06 * s
		var offset_dist: float = (surface_thickness - 0.010) * 0.5
		var n_dir := Vector2(-sin(angle), cos(angle))

		var tray := CSGBox3D.new()
		tray.name = "Surface"
		tray.size = Vector3(length, surface_thickness, machine_width - plate_thickness * 2.2)
		tray.position = Vector3(
			mid.x - n_dir.x * offset_dist,
			mid.y - n_dir.y * offset_dist,
			machine_width * 0.5
		)
		tray.rotation.z = angle
		tray.material = unscrambler._mat_floor
		tray.use_collision = true

		var is_v_notch: bool = (seg[0] == 1 and seg[1] == 2)
		var is_groove_needed: bool = (seg[0] >= 1)

		if is_groove_needed:
			var zc_center: float = machine_width * 0.5
			var scale_factor: float = (chain_diameter / 0.048) * s
			var outer_z: float = (0.052 + 0.014) * scale_factor
			var slot_w: float = (outer_z * 2.0 + 0.014 * scale_factor) * 1.15
			var plate_h: float = 0.042 * scale_factor

			# Generate 11 evenly spaced chains
			var s_dist: float = chain_spacing
			var total_width: float = 10.0 * s_dist
			var start_z: float = (machine_width - total_width) * 0.5
			var chain_zs: Array[float] = []
			for i in range(11):
				chain_zs.append(start_z + i * s_dist)

			if is_v_notch:
				# Cut 5 small slots at the bottom end of the downhill slope for the flights and chains
				var slot_len: float = 0.15 * s
				for k in range(5):
					var zc_k: float = start_z + (2 * k + 0.5) * s_dist
					var slot := CSGBox3D.new()
					slot.name = "Slot"
					slot.operation = CSGShape3D.OPERATION_SUBTRACTION
					var slot_w_flight: float = s_dist + 2.0 * outer_z + 0.02
					slot.size = Vector3(slot_len, surface_thickness + 0.05, slot_w_flight)
					# Position at the very bottom end of the downhill slope segment (local X end)
					slot.position = Vector3(length * 0.5 - slot_len * 0.5, 0.0, zc_k - zc_center)
					tray.add_child(slot)
			else:
				# Groove only recedes the chain (depth = plate_h * 1.1)
				for cz in chain_zs:
					var slot := CSGBox3D.new()
					slot.name = "Groove"
					slot.operation = CSGShape3D.OPERATION_SUBTRACTION
					var groove_depth: float = plate_h * 1.1
					slot.size = Vector3(length + 0.1, groove_depth, slot_w)
					slot.position = Vector3(0.0, surface_thickness * 0.5 - groove_depth * 0.5, cz - zc_center)
					tray.add_child(slot)

		unscrambler.add_child(tray)
