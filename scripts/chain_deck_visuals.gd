@tool
extends Node3D

@export var deck_length: float = 4.2
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

const TRACK_X: Array[float] = [-0.9, -0.3, 0.3, 0.9]
const TRACK_NAMES: Array[String] = ["LeftOuterLinks", "LeftInnerLinks", "RightInnerLinks", "RightOuterLinks"]
const SPROCKET_R: float = 0.20
const SPROCKET_Y: float = 0.95

var _chains: Dictionary = {}
var _rotating_parts: Array[Node3D] = []
var _travel_distance: float = 0.0
var _conveyor: Node = null
var _mat_chain: StandardMaterial3D
var _mat_hardware: StandardMaterial3D
var _mat_bolts: StandardMaterial3D

func _ready() -> void:
	_mat_chain = StandardMaterial3D.new()
	_mat_chain.albedo_color = Color(0.3, 0.32, 0.35)
	_mat_chain.metallic = 0.95
	_mat_chain.roughness = 0.35
	_mat_hardware = StandardMaterial3D.new()
	_mat_hardware.albedo_color = Color(0.34, 0.36, 0.38)
	_mat_hardware.metallic = 0.85
	_mat_hardware.roughness = 0.35
	_mat_bolts = StandardMaterial3D.new()
	_mat_bolts.albedo_color = Color(0.12, 0.12, 0.13)
	_mat_bolts.metallic = 0.95
	_mat_bolts.roughness = 0.3
	var parent := get_parent()
	if parent:
		_conveyor = parent.get_parent()
	if not Engine.is_editor_hint():
		_build_all.call_deferred()
		_collect_and_sort_chains.call_deferred()
	else:
		_collect_and_sort_chains()

func _build_all() -> void:
	_build_runner_beds()
	_build_chains()
	var visuals := get_parent()
	if visuals:
		_build_shafts_and_sprockets(visuals)
		_build_bolts(visuals)

func _build_runner_beds() -> void:
	var m := BoxMesh.new()
	m.size = Vector3(0.28, 0.05, deck_length)
	for i in TRACK_X.size():
		var mi := MeshInstance3D.new()
		mi.name = "RunnerBed%d" % i
		mi.mesh = m
		mi.material_override = _mat_chain
		mi.position = Vector3(TRACK_X[i], 1.075, 0.0)
		add_child(mi)

func _build_chains() -> void:
	var loop_length := 2.0 * deck_length + 2.0 * PI * SPROCKET_R
	var num_links := int(round(loop_length / link_spacing))
	for i in TRACK_X.size():
		var container := Node3D.new()
		container.name = TRACK_NAMES[i]
		add_child(container)
		for li in num_links:
			_build_link(container, li, TRACK_X[i])

func _build_link(container: Node3D, idx: int, track_x: float) -> void:
	var link := Node3D.new()
	link.name = "ChainLink%02d" % idx
	link.position.x = track_x
	container.add_child(link)
	for sx: float in [-0.1, 0.1]:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.02, 0.08, 0.34)
		mi.mesh = m
		mi.material_override = _mat_chain
		mi.position = Vector3(sx, 0.04, 0.0)
		link.add_child(mi)
	if idx % 2 == 0:
		for pz: float in [-0.16, 0.16]:
			var mi := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(0.2, 0.04, 0.04)
			mi.mesh = m
			mi.material_override = _mat_chain
			mi.position = Vector3(0.0, 0.04, pz)
			link.add_child(mi)
	else:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.14, 0.06, 0.18)
		mi.mesh = m
		mi.material_override = _mat_chain
		mi.position = Vector3(0.0, 0.04, 0.0)
		link.add_child(mi)

func _build_shafts_and_sprockets(visuals: Node3D) -> void:
	var half_z := deck_length * 0.5
	for end_name: String in ["Infeed", "Discharge"]:
		var z := half_z if end_name == "Infeed" else -half_z
		var shaft := CSGCylinder3D.new()
		shaft.name = "%sShaft" % end_name
		shaft.radius = 0.035
		shaft.height = 2.0
		shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		shaft.position = Vector3(0.0, SPROCKET_Y, z)
		shaft.material = _mat_hardware
		visuals.add_child(shaft)
		_rotating_parts.append(shaft)
		for i in TRACK_X.size():
			var spr := CSGCylinder3D.new()
			spr.name = "%sSprocket%d" % [end_name, i]
			spr.radius = SPROCKET_R
			spr.height = 0.045
			spr.sides = 10
			spr.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			spr.position = Vector3(TRACK_X[i], SPROCKET_Y, z)
			spr.material = _mat_hardware
			visuals.add_child(spr)
			_rotating_parts.append(spr)
			var hub := CSGCylinder3D.new()
			hub.name = "%sHub%d" % [end_name, i]
			hub.radius = 0.055
			hub.height = 0.075
			hub.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			hub.position = Vector3(TRACK_X[i], SPROCKET_Y, z)
			hub.material = _mat_hardware
			visuals.add_child(hub)

func _build_bolts(visuals: Node3D) -> void:
	var container := Node3D.new()
	container.name = "Bolts"
	visuals.add_child(container)
	var bm := CylinderMesh.new()
	bm.top_radius = 0.035
	bm.bottom_radius = 0.035
	bm.height = 0.04
	bm.radial_segments = 8
	var foot_positions: Array[Vector3] = [
		Vector3(-1.25, 0.0, -1.72), Vector3(-1.25, 0.0, 1.72),
		Vector3( 1.25, 0.0, -1.72), Vector3( 1.25, 0.0, 1.72),
	]
	var bi := 0
	for foot in foot_positions:
		for dx: float in [-0.12, 0.12]:
			for dz: float in [-0.12, 0.12]:
				var mi := MeshInstance3D.new()
				mi.name = "Bolt%02d" % bi
				mi.mesh = bm
				mi.material_override = _mat_bolts
				mi.position = Vector3(foot.x + dx, -0.9333, foot.z + dz)
				container.add_child(mi)
				bi += 1



func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _chains.is_empty():
		return
	var speed := chain_speed
	var dir_z := -1.0
	if _conveyor and "speed" in _conveyor and "direction" in _conveyor:
		speed = _conveyor.speed
		dir_z = _conveyor.direction.z
	var scroll_speed := speed * dir_z
	if is_zero_approx(scroll_speed):
		return
	_travel_distance += scroll_speed * delta
	_update_positions(_travel_distance)
	var rot_step := (scroll_speed / SPROCKET_R) * delta
	for part in _rotating_parts:
		if is_instance_valid(part):
			part.rotate_object_local(Vector3.UP, rot_step)

func _update_positions(travel_dist: float) -> void:
	for group_name in _chains:
		var links: Array = _chains[group_name]
		var num_links := links.size()
		if num_links == 0:
			continue
		var loop_length := num_links * link_spacing
		for idx in range(num_links):
			var link: Node3D = links[idx]
			if not is_instance_valid(link):
				continue
			var local_t := _get_loop_transform(idx * link_spacing + travel_dist, loop_length)
			link.transform.basis = local_t.basis
			link.position.y = local_t.origin.y
			link.position.z = local_t.origin.z

func _get_loop_transform(d: float, loop_length: float) -> Transform3D:
	d = fposmod(d, loop_length)
	var pi_R := PI * SPROCKET_R
	var L := (loop_length - 2.0 * pi_R) * 0.5
	var half_z := deck_length * 0.5
	var y := 1.15
	var z := 0.0
	var rot_x := 0.0
	if d < L:
		z = -half_z + d
		y = 1.15
	elif d < L + pi_R:
		var theta := (d - L) / SPROCKET_R
		z = half_z + SPROCKET_R * sin(theta)
		y = SPROCKET_Y + SPROCKET_R * cos(theta)
		rot_x = theta - 2.0 * PI
	elif d < 2.0 * L + pi_R:
		z = half_z - (d - (L + pi_R))
		y = SPROCKET_Y - SPROCKET_R
		rot_x = -PI
	else:
		var theta := (d - (2.0 * L + pi_R)) / SPROCKET_R
		z = -half_z - SPROCKET_R * sin(theta)
		y = SPROCKET_Y - SPROCKET_R * cos(theta)
		rot_x = theta - PI
	return Transform3D(Basis(Vector3.RIGHT, rot_x), Vector3(0.0, y, z))

func _collect_and_sort_chains() -> void:
	_chains.clear()
	for container in get_children():
		if not container is Node3D:
			continue
		var links: Array[Node3D] = []
		for child in container.get_children():
			if child is Node3D and child.name.begins_with("ChainLink"):
				links.append(child as Node3D)
		if not links.is_empty():
			links.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name < b.name)
			_chains[container.name] = links
