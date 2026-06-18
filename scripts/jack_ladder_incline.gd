extends StaticBody3D

## jack_ladder_incline.gd
## Multi-strand jack-ladder incline with lugs (dogs) that carry logs from the
## V-notch cradle at the base up to log-deck height.
## Visual-only chain animation. Physics surface handled by CollisionShape3D.

@export var chain_speed: float = 0.55
@export var incline_angle_deg: float = 20.0
@export var chain_length_along_slope: float = 4.4
@export var lug_spacing: float = 1.2        # distance between lug bars along slope
@export var strand_x_positions: Array[float] = [-0.75, 0.0, 0.75]
@export var running: bool = true

# Derived at runtime
var _sin_a: float = 0.0
var _cos_a: float = 0.0
var _lug_offset: float = 0.0

# Chain visual nodes per strand
var _strand_links: Array = []   # Array of Array[Node3D]
var _strand_lugs: Array = []    # Array of Array[Node3D]

# Materials (shared across all strands)
var _mat_chain: StandardMaterial3D
var _mat_lug: StandardMaterial3D
var _mat_shaft: StandardMaterial3D
var _mat_sprocket: StandardMaterial3D
var _mat_frame: StandardMaterial3D
var _mat_trough: StandardMaterial3D

func _ready() -> void:
	var ang := deg_to_rad(incline_angle_deg)
	_sin_a = sin(ang)
	_cos_a = cos(ang)

	# Set physics surface velocity (global: up the slope = -Z + Y)
	var slope_dir := Vector3(0.0, _sin_a, -_cos_a).normalized()
	constant_linear_velocity = slope_dir * chain_speed

	_build_materials()
	_build_frame()
	_build_v_notch()
	_build_shafts_and_sprockets()
	_build_chains()

func _build_materials() -> void:
	_mat_chain = StandardMaterial3D.new()
	_mat_chain.albedo_color = Color(0.22, 0.22, 0.25)
	_mat_chain.metallic = 0.9
	_mat_chain.roughness = 0.4

	_mat_lug = StandardMaterial3D.new()
	_mat_lug.albedo_color = Color(0.30, 0.28, 0.25)
	_mat_lug.metallic = 0.85
	_mat_lug.roughness = 0.5

	_mat_shaft = StandardMaterial3D.new()
	_mat_shaft.albedo_color = Color(0.35, 0.32, 0.28)
	_mat_shaft.metallic = 0.9
	_mat_shaft.roughness = 0.35

	_mat_sprocket = StandardMaterial3D.new()
	_mat_sprocket.albedo_color = Color(0.28, 0.26, 0.22)
	_mat_sprocket.metallic = 0.85
	_mat_sprocket.roughness = 0.45

	_mat_frame = StandardMaterial3D.new()
	_mat_frame.albedo_color = Color(0.20, 0.20, 0.22)
	_mat_frame.metallic = 0.8
	_mat_frame.roughness = 0.6

	_mat_trough = StandardMaterial3D.new()
	_mat_trough.albedo_color = Color(0.25, 0.23, 0.20)
	_mat_trough.metallic = 0.75
	_mat_trough.roughness = 0.55

func _build_frame() -> void:
	# Side stringers along the slope (left and right of the strand array)
	var span_x: float = (strand_x_positions.back() - strand_x_positions.front()) * 0.5 + 0.3
	var stringer_mesh := BoxMesh.new()
	stringer_mesh.size = Vector3(0.08, 0.10, chain_length_along_slope)

	for side in [-1.0, 1.0]:
		var s := MeshInstance3D.new()
		s.name = "Stringer_%s" % ("L" if side < 0 else "R")
		s.mesh = stringer_mesh
		s.material_override = _mat_frame
		# Slope centre at Y=0, Z=0 local; stringer sits at slope surface
		s.position = Vector3(side * span_x, -0.05, 0.0)
		add_child(s)

	# Cross members every 0.8 m
	var cross_mesh := BoxMesh.new()
	cross_mesh.size = Vector3(span_x * 2.0 + 0.16, 0.07, 0.07)
	var num_cross := int(chain_length_along_slope / 0.8) + 1
	for i in range(num_cross):
		var c := MeshInstance3D.new()
		c.name = "CrossMember_%d" % i
		c.mesh = cross_mesh
		c.material_override = _mat_frame
		var z := -chain_length_along_slope * 0.5 + i * 0.8
		c.position = Vector3(0.0, -0.04, z)
		add_child(c)

func _build_v_notch() -> void:
	# Two angled plates meeting at a V at the bottom of the incline.
	# The trough catches the log as it rolls off WasteConveyor3.
	var span_x: float = (strand_x_positions.back() - strand_x_positions.front()) * 0.5 + 0.6
	var trough_len: float = span_x * 2.2
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(trough_len, 0.08, 0.55)

	# Bottom (infeed) end of the incline in local space
	var z_bottom := -chain_length_along_slope * 0.5 - 0.10

	for side in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.name = "VNotch_%s" % ("L" if side < 0 else "R")
		p.mesh = plate_mesh
		p.material_override = _mat_trough
		p.rotation_degrees.z = side * 35.0   # angled inward
		p.position = Vector3(0.0, -0.25, z_bottom)
		add_child(p)

func _build_shafts_and_sprockets() -> void:
	var span_x: float = (strand_x_positions.back() - strand_x_positions.front()) + 0.3
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.04
	shaft_mesh.bottom_radius = 0.04
	shaft_mesh.height = span_x + 0.4

	var sprocket_mesh := CylinderMesh.new()
	sprocket_mesh.top_radius = 0.18
	sprocket_mesh.bottom_radius = 0.18
	sprocket_mesh.height = 0.06

	for end_idx in range(2):  # 0 = bottom, 1 = top
		var z_pos := -chain_length_along_slope * 0.5 if end_idx == 0 else chain_length_along_slope * 0.5
		var suffix := "Bottom" if end_idx == 0 else "Top"

		# Drive shaft
		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = _mat_shaft
		shaft.rotation_degrees.z = 90.0   # cylinder along X
		shaft.position = Vector3(0.0, 0.12, z_pos)
		add_child(shaft)

		# One sprocket per strand
		for si in range(strand_x_positions.size()):
			var sp := MeshInstance3D.new()
			sp.name = "Sprocket_%s_%d" % [suffix, si]
			sp.mesh = sprocket_mesh
			sp.material_override = _mat_sprocket
			sp.rotation_degrees.z = 90.0
			sp.position = Vector3(strand_x_positions[si], 0.12, z_pos)
			add_child(sp)

func _build_chains() -> void:
	var num_lugs := int(ceil(chain_length_along_slope / lug_spacing)) + 2

	var link_mesh := BoxMesh.new()
	link_mesh.size = Vector3(0.07, 0.05, 0.38)

	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = 0.025
	roller_mesh.bottom_radius = 0.025
	roller_mesh.height = 0.12

	var lug_mesh := BoxMesh.new()
	lug_mesh.size = Vector3(0.12, 0.14, 0.06)  # "dog" bar sticking up from chain

	_strand_links = []
	_strand_lugs = []

	for si in range(strand_x_positions.size()):
		var sx := strand_x_positions[si]
		var strand_node := Node3D.new()
		strand_node.name = "Strand_%d" % si
		add_child(strand_node)

		var links: Array[Node3D] = []
		var lugs: Array[Node3D] = []

		# Chain links (visual, many)
		var num_links := int(chain_length_along_slope / 0.08) + 2
		for i in range(num_links):
			var lk := MeshInstance3D.new()
			lk.mesh = link_mesh
			lk.material_override = _mat_chain
			var z := -chain_length_along_slope * 0.5 + i * 0.08
			lk.position = Vector3(sx, 0.06, z)
			strand_node.add_child(lk)
			links.append(lk)

			# Roller pin every other link
			if i % 2 == 0:
				var ro := MeshInstance3D.new()
				ro.mesh = roller_mesh
				ro.material_override = _mat_chain
				ro.rotation_degrees.z = 90.0
				ro.position = Vector3(sx, 0.08, z)
				strand_node.add_child(ro)

		# Lug bars (dogs) — these are what push the log uphill
		for j in range(num_lugs):
			var lug := MeshInstance3D.new()
			lug.mesh = lug_mesh
			lug.material_override = _mat_lug
			# Starting position will be set in _process
			lug.position = Vector3(sx, 0.14, -chain_length_along_slope * 0.5 + j * lug_spacing)
			strand_node.add_child(lug)
			lugs.append(lug)

		_strand_links.append(links)
		_strand_lugs.append(lugs)

func _process(delta: float) -> void:
	if not running:
		return

	_lug_offset = fmod(_lug_offset + chain_speed * delta, lug_spacing)

	var half_len := chain_length_along_slope * 0.5

	for si in range(_strand_lugs.size()):
		var sx := strand_x_positions[si]
		var lugs: Array = _strand_lugs[si]
		for j in range(lugs.size()):
			var z := -half_len + fmod(j * lug_spacing + _lug_offset, chain_length_along_slope)
			if z > half_len:
				z -= chain_length_along_slope
			lugs[j].position = Vector3(sx, 0.14, z)

func set_running(on: bool) -> void:
	running = on
	var slope_dir := Vector3(0.0, _sin_a, -_cos_a).normalized()
	constant_linear_velocity = slope_dir * chain_speed if on else Vector3.ZERO
