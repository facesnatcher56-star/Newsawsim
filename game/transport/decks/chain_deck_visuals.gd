@tool
extends Node3D

@export var deck_length: float = 4.2
@export var link_spacing: float = 0.32
@export var chain_speed: float = 0.55

const TRACK_X: Array[float] = [-3.3, -2.7, -2.1, -1.5, -0.9, -0.3, 0.3, 0.9]
const TRACK_NAMES: Array[String] = [
	"Track0Links",
	"Track1Links",
	"Track2Links",
	"Track3Links",
	"Track4Links",
	"Track5Links",
	"Track6Links",
	"Track7Links",
]
const SPROCKET_R: float = 0.20
const SPROCKET_Y: float = 0.95

var _num_links: int = 0
var _multimesh_side_plates: MultiMeshInstance3D
var _multimesh_pins: MultiMeshInstance3D
var _multimesh_blocks: MultiMeshInstance3D
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
	_build_runner_beds()
	_build_chains()
	_build_shafts_and_sprockets.call_deferred(parent)
	_build_bolts.call_deferred(parent)

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
	_num_links = int(round(loop_length / link_spacing))
	var num_tracks := TRACK_X.size()
	
	# Clean up any existing MultiMeshInstance3D children
	for child in get_children():
		if child is MultiMeshInstance3D:
			if Engine.is_editor_hint():
				remove_child(child)
			child.queue_free()
			
	var num_even_links := 0
	var num_odd_links := 0
	for li in _num_links:
		if li % 2 == 0:
			num_even_links += 1
		else:
			num_odd_links += 1

	# 1. Side Plates MultiMesh
	_multimesh_side_plates = MultiMeshInstance3D.new()
	_multimesh_side_plates.name = "SidePlatesMultiMesh"
	var mm_plates := MultiMesh.new()
	mm_plates.transform_format = MultiMesh.TRANSFORM_3D
	mm_plates.use_custom_data = false
	mm_plates.use_colors = false
	var m_plate := BoxMesh.new()
	m_plate.size = Vector3(0.02, 0.08, 0.34)
	mm_plates.mesh = m_plate
	mm_plates.instance_count = _num_links * num_tracks * 2
	_multimesh_side_plates.multimesh = mm_plates
	_multimesh_side_plates.material_override = _mat_chain
	add_child(_multimesh_side_plates)

	# 2. Pins MultiMesh
	_multimesh_pins = MultiMeshInstance3D.new()
	_multimesh_pins.name = "PinsMultiMesh"
	var mm_pins := MultiMesh.new()
	mm_pins.transform_format = MultiMesh.TRANSFORM_3D
	mm_pins.use_custom_data = false
	mm_pins.use_colors = false
	var m_pin := BoxMesh.new()
	m_pin.size = Vector3(0.2, 0.04, 0.04)
	mm_pins.mesh = m_pin
	mm_pins.instance_count = num_even_links * num_tracks * 2
	_multimesh_pins.multimesh = mm_pins
	_multimesh_pins.material_override = _mat_chain
	add_child(_multimesh_pins)

	# 3. Blocks MultiMesh
	_multimesh_blocks = MultiMeshInstance3D.new()
	_multimesh_blocks.name = "BlocksMultiMesh"
	var mm_blocks := MultiMesh.new()
	mm_blocks.transform_format = MultiMesh.TRANSFORM_3D
	mm_blocks.use_custom_data = false
	mm_blocks.use_colors = false
	var m_block := BoxMesh.new()
	m_block.size = Vector3(0.14, 0.06, 0.18)
	mm_blocks.mesh = m_block
	mm_blocks.instance_count = num_odd_links * num_tracks * 1
	_multimesh_blocks.multimesh = mm_blocks
	_multimesh_blocks.material_override = _mat_chain
	add_child(_multimesh_blocks)

	_update_positions(0.0)

func _build_shafts_and_sprockets(visuals: Node3D) -> void:
	var half_z := deck_length * 0.5
	var min_x: float = TRACK_X.min()
	var max_x: float = TRACK_X.max()
	var shaft_center_x := (min_x + max_x) * 0.5
	var shaft_width := (max_x - min_x) + 0.2
	for end_name: String in ["Infeed", "Discharge"]:
		var z := half_z if end_name == "Infeed" else -half_z
		var shaft := CSGCylinder3D.new()
		shaft.name = "%sShaft" % end_name
		shaft.radius = 0.035
		shaft.height = shaft_width
		shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		shaft.position = Vector3(shaft_center_x, SPROCKET_Y, z)
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
		Vector3(-3.25, 0.0, -1.72), Vector3(-3.25, 0.0, 1.72),
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
	if Engine.is_editor_hint() or _num_links == 0:
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
	if not is_instance_valid(_multimesh_side_plates) or not is_instance_valid(_multimesh_pins) or not is_instance_valid(_multimesh_blocks):
		return
	var loop_length := _num_links * link_spacing
	var num_tracks := TRACK_X.size()
	
	var plate_idx := 0
	var pin_idx := 0
	var block_idx := 0
	
	for t in num_tracks:
		var track_x := TRACK_X[t]
		for i in _num_links:
			var slot0 := float(i) * link_spacing + travel_dist
			var local_t := _get_loop_transform(slot0, loop_length)
			var link_pos := Vector3(track_x, local_t.origin.y, local_t.origin.z)
			var link_xf := Transform3D(local_t.basis, link_pos)
			
			# Side plates
			for sx in [-0.1, 0.1]:
				var lp_xf := link_xf * Transform3D(Basis(), Vector3(sx, 0.04, 0.0))
				_multimesh_side_plates.multimesh.set_instance_transform(plate_idx, lp_xf)
				plate_idx += 1
				
			# Even / Odd features
			if i % 2 == 0:
				for pz in [-0.16, 0.16]:
					var pin_xf := link_xf * Transform3D(Basis(), Vector3(0.0, 0.04, pz))
					_multimesh_pins.multimesh.set_instance_transform(pin_idx, pin_xf)
					pin_idx += 1
			else:
				var block_xf := link_xf * Transform3D(Basis(), Vector3(0.0, 0.04, 0.0))
				_multimesh_blocks.multimesh.set_instance_transform(block_idx, block_xf)
				block_idx += 1

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
