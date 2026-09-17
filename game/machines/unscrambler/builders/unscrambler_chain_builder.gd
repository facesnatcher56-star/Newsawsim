@tool
extends RefCounted

## Builds the unscrambler's chain-and-flight conveyor system: the closed-loop
## path, all chain-rail link meshes, and the flight bars. Populates the
## animation-state arrays on the main node that _physics_process animates.

var unscrambler: Node


func _init(p_unscrambler: Node) -> void:
	unscrambler = p_unscrambler


func build_chains_and_flights() -> void:
	var s: float = unscrambler.profile_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.9
	mat.roughness = 0.25

	# Build path: V-notch to exit + overhang, closed loop return underneath
	var chain_overhang: float = unscrambler.chain_overhang
	var raw: Array[Vector2] = [
		# Forward path on top of the slide
		Vector2(-0.33, -0.28),  # V apex
		Vector2(-0.04,  0.02),  # back up from notch
		Vector2( 0.22,  0.36),  # curve begins
		Vector2( 0.50,  0.72),  # curve mid
		Vector2( 0.78,  0.98),  # curve upper
		Vector2( 1.00,  1.10),  # entry to exit flat
		Vector2( 2.50,  1.10),  # exit far right
		Vector2( 2.50 + chain_overhang, 1.10), # sprocket top
	]

	# Sample return path using quadratic Bezier curve to create natural droop
	var p0 := Vector2(2.50 + chain_overhang, 0.70)
	var p1 := Vector2(1.2, -0.9)
	var p2 := Vector2(-0.33, -0.48)

	var num_bezier_pts := 15
	for i in range(num_bezier_pts):
		var t: float = float(i) / float(num_bezier_pts - 1)
		var pt: Vector2 = (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		raw.append(pt)

	# Finally close the loop
	raw.append(Vector2(-0.33, -0.28))

	# Arc-length param
	var al: Array[float] = [0.0]
	for i in range(1, raw.size()):
		al.append(al[al.size() - 1] + (raw[i] * s).distance_to(raw[i - 1] * s))
	var total: float = al[al.size() - 1]
	if total < 0.001:
		return

	var steps := 100
	var pts: Array[Vector2] = []
	var si := 0
	for step_idx in range(steps):
		var tgt: float = step_idx * total / float(steps - 1)
		while si < al.size() - 2 and al[si + 1] < tgt:
			si += 1
		var t: float = (tgt - al[si]) / (al[si + 1] - al[si]) if al[si + 1] > al[si] else 0.0
		pts.append((raw[si] * s).lerp(raw[si + 1] * s, clampf(t, 0.0, 1.0)))
	if pts.size() < 2:
		return

	var zw: float = unscrambler.machine_width
	var s_dist: float = unscrambler.chain_spacing
	var total_width: float = 10.0 * s_dist
	var start_z: float = (zw - total_width) * 0.5

	# Scale diameter, pitch and dimensions relative to Level Deck chain links
	# Level deck references: pitch = 0.2032, plate length = 0.25, plate height = 0.042,
	# plate width = 0.014, plate Z offset = 0.052, roller radius = 0.024, roller height = 0.128.
	# Scale factor based on custom chain_diameter compared to default level deck roller diameter (0.048).
	var chain_diameter: float = unscrambler.chain_diameter
	var scale_factor: float = (chain_diameter / 0.048) * s

	var link_len: float = 0.2032 * s
	var plate_len: float = 0.25 * s

	# Cumulative distance along pts
	var pts_al: Array[float] = [0.0]
	for i in range(1, pts.size()):
		pts_al.append(pts_al[pts_al.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total_path_len: float = pts_al[pts_al.size() - 1]

	var num_links: int = int(total_path_len / link_len)
	var actual_step: float = total_path_len / float(num_links)

	# Use actual_step for placing and sizing the link plates to avoid gaps
	var effective_link_len: float = actual_step
	var effective_plate_len: float = plate_len * (actual_step / link_len)

	var plate_h: float = 0.042 * scale_factor
	var plate_w: float = 0.014 * scale_factor
	var inner_z: float = 0.052 * scale_factor
	var outer_z: float = inner_z + plate_w
	var roller_r: float = 0.024 * scale_factor

	# Calculate offset sidebar chain plate segments
	var straight_len: float = effective_plate_len * 0.5 - effective_link_len * 0.05
	var straight_center_x: float = (effective_plate_len * 0.5 + effective_link_len * 0.05) * 0.5

	var dx: float = effective_link_len * 0.1
	var dz: float = outer_z - inner_z
	var jog_len: float = sqrt(dx * dx + dz * dz)
	var jog_ang: float = -atan2(dz, dx)

	# Shared meshes for chain links
	var straight_plate_mesh := BoxMesh.new()
	straight_plate_mesh.size = Vector3(straight_len, plate_h, plate_w)

	var jog_plate_mesh := BoxMesh.new()
	jog_plate_mesh.size = Vector3(jog_len, plate_h, plate_w)

	var roller_width: float = inner_z * 2.0 - plate_w
	var cyl_m := CylinderMesh.new()
	cyl_m.top_radius = roller_r
	cyl_m.bottom_radius = roller_r
	cyl_m.height = roller_width
	cyl_m.radial_segments = 8

	var pin_m := CylinderMesh.new()
	pin_m.top_radius = roller_r * 0.5
	pin_m.bottom_radius = roller_r * 0.5
	pin_m.height = outer_z * 2.0 + plate_w * 1.5
	pin_m.radial_segments = 6

	# ── Chain rails (11 chains, drawn from one MultiMesh) ────────────────────
	# Every link is identical, so the eight fabricated parts are baked into a
	# single mesh. Eleven rails of links then cost one node and one draw call,
	# instead of ~400 links each owning a node with eight MeshInstance3D
	# children — which was over three thousand draw calls for one machine.
	var link_zs: PackedFloat32Array = PackedFloat32Array()
	for i in range(11):
		link_zs.append(start_z + i * s_dist)

	var link_mesh: ArrayMesh = _build_link_mesh(
		straight_plate_mesh, jog_plate_mesh, cyl_m, pin_m,
		straight_center_x, inner_z, outer_z, jog_ang, effective_link_len)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = false
	mm.use_colors = false
	mm.mesh = link_mesh
	mm.instance_count = num_links * link_zs.size()

	var link_visuals := MultiMeshInstance3D.new()
	link_visuals.name = "ChainLinks"
	link_visuals.multimesh = mm
	link_visuals.material_override = mat
	unscrambler.add_child(link_visuals)

	# Where each link of a rail sits along the loop, and where each rail sits
	# across the machine. The deck re-places the instances from these each frame.
	var slot_dists: PackedFloat32Array = PackedFloat32Array()
	for j in range(num_links):
		slot_dists.append(float(j) * actual_step + actual_step * 0.5)

	unscrambler._anim_link_visuals = link_visuals
	unscrambler._anim_link_slots = slot_dists
	unscrambler._anim_link_zs = link_zs
	unscrambler._anim_link_perp = plate_h * 0.5

	# Shared mesh for flights (square tubes)
	var flight_diameter: float = unscrambler.flight_diameter
	var scaled_flight_dia: float = flight_diameter * s
	var scaled_flight_h: float = scaled_flight_dia * 0.5
	var flight_len: float = s_dist + 2.0 * outer_z
	var flight_mesh_res := BoxMesh.new()
	flight_mesh_res.size = Vector3(scaled_flight_dia, scaled_flight_dia, flight_len)

	# BoxShape3D for flight collision (matching visual size)
	var flight_shape := BoxShape3D.new()
	flight_shape.size = Vector3(scaled_flight_dia, scaled_flight_dia, flight_len)

	# Store path data for flight animation
	unscrambler._anim_path_pts = pts
	unscrambler._anim_flight_perp = scaled_flight_h

	# Flights — placed along the closed-loop path and animated each physics frame
	var al2: Array[float] = [0.0]
	for i in range(1, pts.size()):
		al2.append(al2[al2.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total2: float = al2[al2.size() - 1]
	unscrambler._anim_path_al = al2
	unscrambler._anim_path_total = total2

	var flight_spacing: float = unscrambler.flight_spacing
	var fd: float = flight_spacing * 0.5
	var fi := 0
	var s2 := 0
	while fd < total2:
		while s2 < al2.size() - 2 and al2[s2 + 1] < fd:
			s2 += 1
		var t: float = (fd - al2[s2]) / (al2[s2 + 1] - al2[s2]) if al2[s2 + 1] > al2[s2] else 0.0
		t = clampf(t, 0.0, 1.0)
		var pos: Vector2 = pts[s2].lerp(pts[s2 + 1], t)
		var d2: Vector2 = (pts[s2 + 1] - pts[s2]).normalized()
		var n := Vector2(-d2.y, d2.x)
		var ang: float = atan2(d2.y, d2.x)

		for k in range(5):
			var zc_k: float = start_z + (2 * k + 0.5) * s_dist

			# AnimatableBody3D — moves each frame, imparting velocity to RigidBody contacts
			var fl := AnimatableBody3D.new()
			fl.name = "Flight_S%d_F%d" % [k, fi]
			fl.sync_to_physics = false
			fl.position = Vector3(pos.x + n.x * scaled_flight_h, pos.y + n.y * scaled_flight_h, zc_k)
			fl.rotation = Vector3(0.0, 0.0, ang)

			# Visual mesh
			var fl_mesh := MeshInstance3D.new()
			fl_mesh.mesh = flight_mesh_res
			fl_mesh.material_override = mat
			fl.add_child(fl_mesh)

			# Collision shape — physically pushes boards
			var fl_shape := CollisionShape3D.new()
			fl_shape.shape = flight_shape
			fl.add_child(fl_shape)

			fl.add_to_group(unscrambler._CHAIN_GROUP)
			unscrambler.add_child(fl)

			# Store for animation
			unscrambler._anim_flights.append(fl)
			unscrambler._anim_flight_dists.append(fd)
			unscrambler._anim_flight_zs.append(zc_k)

		fi += 1
		fd += flight_spacing


## Bake one chain link's eight fabricated parts into a single mesh, so a whole
## rail of links can be drawn by a MultiMesh.
func _build_link_mesh(
	straight_plate: Mesh,
	jog_plate: Mesh,
	roller: Mesh,
	pin: Mesh,
	straight_center_x: float,
	inner_z: float,
	outer_z: float,
	jog_ang: float,
	link_len: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Offset sidebar plates — inner, jog, outer — mirrored either side of centre.
	st.append_from(straight_plate, 0, Transform3D(Basis(), Vector3(-straight_center_x, 0.0, inner_z)))
	st.append_from(jog_plate, 0, Transform3D(Basis(Vector3.UP, jog_ang), Vector3(0.0, 0.0, (inner_z + outer_z) * 0.5)))
	st.append_from(straight_plate, 0, Transform3D(Basis(), Vector3(straight_center_x, 0.0, outer_z)))
	st.append_from(straight_plate, 0, Transform3D(Basis(), Vector3(-straight_center_x, 0.0, -inner_z)))
	st.append_from(jog_plate, 0, Transform3D(Basis(Vector3.UP, -jog_ang), Vector3(0.0, 0.0, -(inner_z + outer_z) * 0.5)))
	st.append_from(straight_plate, 0, Transform3D(Basis(), Vector3(straight_center_x, 0.0, -outer_z)))
	# Joint roller and pin lie across the narrow end of the link.
	var across := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-link_len * 0.5, 0.0, 0.0))
	st.append_from(roller, 0, across)
	st.append_from(pin, 0, across)
	return st.commit()
