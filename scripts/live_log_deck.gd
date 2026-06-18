extends StaticBody3D

## live_log_deck.gd
## Horizontal live deck that queues multiple logs and advances them toward the
## tilter/carriage side.  Multi-strand chains with lugs run in +Z.
## Sprockets and drive shafts at both Z ends.

@export var deck_length: float = 2.4          # Z span of deck
@export var deck_width: float = 2.6           # X span (should cover log length)
@export var chain_speed: float = 0.30
@export var lug_spacing: float = 1.4
@export var strand_x_positions: Array[float] = [-0.75, -0.25, 0.25, 0.75]
@export var running: bool = true

var _lug_offset: float = 0.0

var _strand_lugs: Array = []

var _mat_chain: StandardMaterial3D
var _mat_lug: StandardMaterial3D
var _mat_shaft: StandardMaterial3D
var _mat_sprocket: StandardMaterial3D
var _mat_frame: StandardMaterial3D

func _ready() -> void:
	constant_linear_velocity = Vector3(0.0, 0.0, chain_speed) if running else Vector3.ZERO
	_build_materials()
	_build_frame()
	_build_shafts_and_sprockets()
	_build_chains()

func _build_materials() -> void:
	_mat_chain = StandardMaterial3D.new()
	_mat_chain.albedo_color = Color(0.22, 0.22, 0.25)
	_mat_chain.metallic = 0.9
	_mat_chain.roughness = 0.4

	_mat_lug = StandardMaterial3D.new()
	_mat_lug.albedo_color = Color(0.32, 0.28, 0.24)
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

func _build_frame() -> void:
	# Deck surface plate (thin structural base)
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(deck_width + 0.2, 0.06, deck_length + 0.1)
	var deck_surf := MeshInstance3D.new()
	deck_surf.name = "DeckSurface"
	deck_surf.mesh = deck_mesh
	deck_surf.material_override = _mat_frame
	deck_surf.position = Vector3(0.0, -0.08, 0.0)
	add_child(deck_surf)

	# Side rails
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.08, 0.18, deck_length + 0.1)
	for side in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		r.name = "SideRail_%s" % ("L" if side < 0 else "R")
		r.mesh = rail_mesh
		r.material_override = _mat_frame
		r.position = Vector3(side * (deck_width * 0.5 + 0.08), 0.0, 0.0)
		add_child(r)

	# Cross supports every 0.6 m
	var cross_mesh := BoxMesh.new()
	cross_mesh.size = Vector3(deck_width + 0.16, 0.10, 0.07)
	var num_cross := int(deck_length / 0.6) + 1
	for i in range(num_cross):
		var c := MeshInstance3D.new()
		c.name = "CrossSupport_%d" % i
		c.mesh = cross_mesh
		c.material_override = _mat_frame
		var z := -deck_length * 0.5 + i * 0.6
		c.position = Vector3(0.0, -0.04, z)
		add_child(c)

func _build_shafts_and_sprockets() -> void:
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.04
	shaft_mesh.bottom_radius = 0.04
	shaft_mesh.height = deck_width + 0.5

	var sprocket_mesh := CylinderMesh.new()
	sprocket_mesh.top_radius = 0.15
	sprocket_mesh.bottom_radius = 0.15
	sprocket_mesh.height = 0.06

	for end_idx in range(2):  # 0 = infeed (−Z), 1 = discharge (+Z)
		var z_pos := -deck_length * 0.5 if end_idx == 0 else deck_length * 0.5
		var suffix := "Infeed" if end_idx == 0 else "Discharge"

		# Drive shaft (X-axis cylinder)
		var shaft := MeshInstance3D.new()
		shaft.name = "DriveShaft_%s" % suffix
		shaft.mesh = shaft_mesh
		shaft.material_override = _mat_shaft
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, 0.10, z_pos)
		add_child(shaft)

		# Sprocket per strand
		for si in range(strand_x_positions.size()):
			var sp := MeshInstance3D.new()
			sp.name = "Sprocket_%s_%d" % [suffix, si]
			sp.mesh = sprocket_mesh
			sp.material_override = _mat_sprocket
			sp.rotation_degrees.z = 90.0
			sp.position = Vector3(strand_x_positions[si], 0.10, z_pos)
			add_child(sp)

func _build_chains() -> void:
	var num_lugs := int(ceil(deck_length / lug_spacing)) + 2

	var link_mesh := BoxMesh.new()
	link_mesh.size = Vector3(0.07, 0.04, 0.35)

	var lug_mesh := BoxMesh.new()
	lug_mesh.size = Vector3(0.10, 0.15, 0.05)  # dog bar sticking up

	_strand_lugs = []

	for si in range(strand_x_positions.size()):
		var sx := strand_x_positions[si]
		var strand_node := Node3D.new()
		strand_node.name = "DeckStrand_%d" % si
		add_child(strand_node)

		# Chain links (visual)
		var num_links := int(deck_length / 0.35) + 2
		for i in range(num_links):
			var lk := MeshInstance3D.new()
			lk.mesh = link_mesh
			lk.material_override = _mat_chain
			var z := -deck_length * 0.5 + i * 0.35
			lk.position = Vector3(sx, 0.04, z)
			strand_node.add_child(lk)

		# Lugs
		var lugs: Array[Node3D] = []
		for j in range(num_lugs):
			var lug := MeshInstance3D.new()
			lug.mesh = lug_mesh
			lug.material_override = _mat_lug
			lug.position = Vector3(sx, 0.10, -deck_length * 0.5 + j * lug_spacing)
			strand_node.add_child(lug)
			lugs.append(lug)

		_strand_lugs.append(lugs)

func _process(delta: float) -> void:
	if not running:
		return

	_lug_offset = fmod(_lug_offset + chain_speed * delta, lug_spacing)

	var half_len := deck_length * 0.5

	for si in range(_strand_lugs.size()):
		var sx := strand_x_positions[si]
		var lugs: Array = _strand_lugs[si]
		for j in range(lugs.size()):
			var z := -half_len + fmod(j * lug_spacing + _lug_offset, deck_length)
			if z > half_len:
				z -= deck_length
			lugs[j].position = Vector3(sx, 0.10, z)

func set_running(on: bool) -> void:
	running = on
	constant_linear_velocity = Vector3(0.0, 0.0, chain_speed) if on else Vector3.ZERO
