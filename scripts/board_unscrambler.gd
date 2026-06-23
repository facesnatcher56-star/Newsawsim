@tool
extends StaticBody3D

@export var chain_spacing: float = 1.8
@export var flight_spacing: float = 0.35
@export var flight_height: float = 0.08
@export var chain_diameter: float = 0.03
@export var flight_diameter: float = 0.05
@export var chain_overhang: float = 0.35

const _CHAIN_GROUP := &"_unscrambler_chains"

const _OUTER: Array[Vector2] = [
	Vector2(-0.44, -0.28),
	Vector2(-0.22, -0.28),
	Vector2(-0.04,  0.02),
	Vector2( 0.22,  0.36),
	Vector2( 0.50,  0.72),
	Vector2( 0.780, 0.980),
	Vector2( 0.839, 1.026),
	Vector2( 0.904, 1.059),
	Vector2( 0.977, 1.080),
	Vector2( 1.052, 1.087),
	Vector2( 2.50,  1.087),
]

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# Remove old chain/flight nodes
	for c in get_children():
		if c.is_in_group(_CHAIN_GROUP) or c.name.begins_with("Link") or c.name.begins_with("Flight") or c.name.begins_with("@CSGCylinder3D@"):
			c.free()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.9
	mat.roughness = 0.25

	# Build path: V-notch to exit + overhang
	var raw: Array[Vector2] = _OUTER.duplicate()
	var last := raw[raw.size() - 1]
	var prev := raw[raw.size() - 2]
	raw.append(last + (last - prev).normalized() * chain_overhang)

	# Arc-length param
	var al: Array[float] = [0.0]
	for i in range(1, raw.size()):
		al.append(al[al.size() - 1] + raw[i].distance_to(raw[i - 1]))
	var total := al[al.size() - 1]
	if total < 0.001:
		return

	var steps := 100
	var pts: Array[Vector2] = []
	var si := 0
	for s in range(steps):
		var tgt := s * total / float(steps - 1)
		while si < al.size() - 2 and al[si + 1] < tgt:
			si += 1
		var t := (tgt - al[si]) / (al[si + 1] - al[si]) if al[si + 1] > al[si] else 0.0
		pts.append(raw[si].lerp(raw[si + 1], clampf(t, 0.0, 1.0)))
	if pts.size() < 2:
		return

	var zw: float = 4.2
	var zc := zw * 0.5
	var za := zc - chain_spacing * 0.5
	var zb := zc + chain_spacing * 0.5

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	# Shared meshes for chain links
	var link_len := chain_diameter * 3.0
	var plate_len := link_len * 0.95
	var plate_h := chain_diameter * 0.8
	var plate_w := chain_diameter * 0.15
	var inner_z := chain_diameter * 0.35

	var box_m := BoxMesh.new()
	box_m.size = Vector3(plate_len, plate_h, plate_w)

	var cyl_m := CylinderMesh.new()
	cyl_m.top_radius = chain_diameter * 0.35
	cyl_m.bottom_radius = chain_diameter * 0.35
	cyl_m.height = inner_z * 2.0 + plate_w
	cyl_m.radial_segments = 8

	# Chain rails
	for z in [za, zb]:
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.001:
				continue
			var d := (b - a) / seg
			var ang := atan2(d.y, d.x)
			var cnt := maxi(1, int(seg / link_len))
			var stp := seg / float(cnt)
			for j in range(cnt):
				var p := a + d * ((j + 0.5) * stp)
				var link := Node3D.new()
				link.name = "Link"
				link.position = Vector3(p.x, p.y, z)
				link.rotation.z = ang
				link.add_to_group(_CHAIN_GROUP)
				add_child(link)
				if root:
					link.owner = root

				# Left Plate
				var lp := MeshInstance3D.new()
				lp.mesh = box_m
				lp.material_override = mat
				lp.position = Vector3(0.0, 0.0, -inner_z)
				link.add_child(lp)

				# Right Plate
				var rp := MeshInstance3D.new()
				rp.mesh = box_m
				rp.material_override = mat
				rp.position = Vector3(0.0, 0.0, inner_z)
				link.add_child(rp)

				# Roller
				var ro := MeshInstance3D.new()
				ro.mesh = cyl_m
				ro.material_override = mat
				ro.rotation.x = PI / 2.0
				link.add_child(ro)

				if root:
					lp.owner = root
					rp.owner = root
					ro.owner = root

	# Shared mesh for flights
	var flight_mesh_res := CylinderMesh.new()
	flight_mesh_res.top_radius = flight_diameter * 0.5
	flight_mesh_res.bottom_radius = flight_diameter * 0.5
	flight_mesh_res.height = absf(zb - za) + chain_diameter * 2.0
	flight_mesh_res.radial_segments = 8

	# Flights
	var al2: Array[float] = [0.0]
	for i in range(1, pts.size()):
		al2.append(al2[al2.size() - 1] + pts[i].distance_to(pts[i - 1]))
	var total2 := al2[al2.size() - 1]

	var fd := flight_spacing * 0.5
	var fi := 0
	var s2 := 0
	while fd < total2:
		while s2 < al2.size() - 2 and al2[s2 + 1] < fd:
			s2 += 1
		var t := (fd - al2[s2]) / (al2[s2 + 1] - al2[s2]) if al2[s2 + 1] > al2[s2] else 0.0
		t = clampf(t, 0.0, 1.0)
		var pos := pts[s2].lerp(pts[s2 + 1], t)
		var d2 := (pts[s2 + 1] - pts[s2]).normalized()
		var n := Vector2(-d2.y, d2.x)

		var fl := MeshInstance3D.new()
		fl.name = "Flight%d" % fi
		fi += 1
		fl.mesh = flight_mesh_res
		fl.position = Vector3(pos.x + n.x * flight_height, pos.y + n.y * flight_height, (za + zb) * 0.5)
		fl.rotation.x = deg_to_rad(90.0)
		fl.material_override = mat
		fl.add_to_group(_CHAIN_GROUP)
		add_child(fl)
		if root:
			fl.owner = root

		fd += flight_spacing
