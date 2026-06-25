# (adding a comment to force re-parse)
extends RigidBody3D

# Log with bark and board cutting mechanics
# The bark is represented by a child MeshInstance3D "Bark"
# Boards are represented by child MeshInstance3D nodes under a "Boards" container.
# Bark and boards are removed when the log passes specific processing stations.

@export var bark_enabled: bool = true
@export var board_count: int = 4  # Number of cuttable boards attached to the log
@export var debarker_node_path: NodePath = "../DebarkerStation/DebarkerRing/Model"
@export var debarker_peel_radius: float = 0.04
@export var debarker_alignment_radius: float = 0.85

var max_boards: int = 4
var cuts_on_current_face: int = 0
var current_cut_face: int = 0

const CUT_DEPTH_PER_PASS: float = 0.05

# Positions of processing stations (approximate world coordinates)
const DEBARKER_RING_POS: Vector3 = Vector3(5.165, 0.714, 2.072)
const BANDSaw_POS: Vector3 = Vector3(19, -0.083, 6.13)  # Position of the Bandsaw node
const PROCESS_RADIUS: float = 0.5  # Proximity radius to trigger processing

var bark_sections: Array[Node3D] = []
var bark_coat: CSGCylinder3D = null

func _ready() -> void:
	add_to_group("logs")
	if board_count <= 0:
		board_count = 4
	max_boards = board_count
	_create_bark()
	_create_bark_coat()
	_create_boards()
	_collect_bark_sections()
	_update_bark_coat()
	_setup_csg_cut()

# Create visual bark as a simple box mesh matching the log size
func _create_bark() -> void:
	if not bark_enabled:
		return
	if has_node("Bark"):
		return
	var bark_node = MeshInstance3D.new()
	bark_node.name = "Bark"
	# Use a simple BoxMesh sized to the log's collision shape (assumes uniform size)
	var box = BoxMesh.new()
	box.size = Vector3(0.32, 1.9, 0.35)  # Approximate size from existing BoxShape3D_o3d8n
	bark_node.mesh = box
	# Brown bark material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)
	bark_node.material_override = mat
	add_child(bark_node)

# A continuous, visual-only shell hides the seams between functional bark
# sections. The sections still control peeling and spawn the physical scraps.
func _create_bark_coat() -> void:
	if not bark_enabled:
		return
	var bark_root := get_node_or_null("Bark") as Node3D
	if bark_root == null:
		return
	bark_coat = bark_root.get_node_or_null("BarkCoat") as CSGCylinder3D
	if bark_coat:
		return

	bark_coat = CSGCylinder3D.new()
	bark_coat.name = "BarkCoat"
	bark_coat.radius = 0.291
	bark_coat.height = _get_log_core_length()
	bark_coat.sides = 48
	bark_coat.smooth_faces = true
	bark_coat.rotation.z = PI * 0.5
	bark_coat.material = _create_bark_coat_material()
	bark_root.add_child(bark_coat)

func _create_bark_coat_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;

varying vec3 bark_pos;

void vertex() {
	bark_pos = VERTEX;
}

void fragment() {
	float angle = atan(bark_pos.z, bark_pos.x);
	float long_furrow = sin(angle * 11.0 + bark_pos.y * 3.5);
	float broken_furrow = sin(angle * 19.0 - bark_pos.y * 8.0 + sin(angle * 5.0));
	float fine_grain = sin(bark_pos.y * 37.0 + angle * 7.0);
	float grain = long_furrow * 0.16 + broken_furrow * 0.10 + fine_grain * 0.035;
	vec3 dark_bark = vec3(0.105, 0.047, 0.018);
	vec3 light_bark = vec3(0.285, 0.135, 0.045);
	ALBEDO = mix(dark_bark, light_bark, clamp(0.52 + grain, 0.0, 1.0));
	ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

# Create a container with board meshes that can be cut off
func _create_boards() -> void:
	if has_node("Boards"):
		return
	var boards_root = Node3D.new()
	boards_root.name = "Boards"
	add_child(boards_root)
	for i in range(board_count):
		var board_node = MeshInstance3D.new()
		board_node.name = "Board_%d" % i
		var plane = BoxMesh.new()
		plane.size = Vector3(0.3, 0.02, 0.6)  # Thin board
		board_node.mesh = plane
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.7, 0.5)
		board_node.material_override = mat
		# Position boards along the log length
		board_node.transform.origin = Vector3(0, 0.9 - i * 0.3, 0)
		boards_root.add_child(board_node)

func _process(delta: float) -> void:
	if bark_enabled:
		_update_bark_peeling()
	if not freeze and board_count > 0 and global_transform.origin.distance_to(BANDSaw_POS) < PROCESS_RADIUS:
		cut_board(BANDSaw_POS)

func _remove_bark() -> void:
	if bark_enabled and $Bark:
		$Bark.visible = false
		bark_enabled = false

func _collect_bark_sections() -> void:
	bark_sections.clear()
	var bark = get_node_or_null("Bark")
	if not bark:
		return
	for child in bark.get_children():
		if child is Node3D and String(child.name).begins_with("BarkSection"):
			bark_sections.append(child)
	if bark_sections.is_empty() and bark is Node3D:
		bark_sections.append(bark)

func _update_bark_peeling() -> void:
	var debarker_pos = _get_debarker_position()
	var remaining_sections := 0
	var coat_changed := false
	for section: Node3D in bark_sections:
		if not is_instance_valid(section):
			continue
		if section.visible:
			remaining_sections += 1
			if _section_is_inside_debarker(section, debarker_pos):
				section.visible = false
				remaining_sections -= 1
				coat_changed = true
				_spawn_bark_piece(section.global_position)
	if coat_changed:
		_update_bark_coat()
	if remaining_sections <= 0 and not bark_sections.is_empty():
		bark_enabled = false

func _update_bark_coat() -> void:
	if bark_coat == null:
		return
	var first_x := INF
	var last_x := -INF
	var visible_count := 0
	for section in bark_sections:
		if is_instance_valid(section) and section.visible:
			first_x = minf(first_x, section.position.x)
			last_x = maxf(last_x, section.position.x)
			visible_count += 1
	if visible_count == 0:
		bark_coat.visible = false
		return
	bark_coat.visible = true
	var section_length := _get_bark_section_length()
	bark_coat.height = maxf(section_length, last_x - first_x + section_length)
	bark_coat.position.x = (first_x + last_x) * 0.5

func _get_log_core_length() -> float:
	var wood_core := get_node_or_null("WoodCore") as CSGCylinder3D
	if wood_core:
		return wood_core.height
	return 4.8768

func _get_bark_section_length() -> float:
	for section in bark_sections:
		if not is_instance_valid(section):
			continue
		var body := section.get_node_or_null("Body") as CSGCylinder3D
		if body:
			return body.height
	if bark_sections.size() >= 2:
		var positions: Array[float] = []
		for section in bark_sections:
			if is_instance_valid(section):
				positions.append(section.position.x)
		positions.sort()
		if positions.size() >= 2:
			return absf(positions[1] - positions[0])
	return 0.161109

func _spawn_bark_piece(pos: Vector3) -> void:
	var bark_scene = load("res://scenes/bark_piece.tscn")
	if bark_scene:
		var bark = bark_scene.instantiate()
		# Prevent collision between the bark piece and any log in the scene to avoid physics glitches
		for l_node in get_tree().get_nodes_in_group("logs"):
			if l_node is RigidBody3D:
				bark.add_collision_exception_with(l_node)
		
		# Add to the main scene tree root first so we can set global_position safely
		get_parent().add_child(bark)
		bark.global_position = pos
		
		# Give it some organic peeling velocity
		var angle = randf_range(0.0, 2.0 * PI)
		var peel_vel = Vector3(
			randf_range(-0.3, 0.3),
			cos(angle) * randf_range(0.6, 1.5),
			sin(angle) * randf_range(0.6, 1.5)
		)
		# Add a slight downward push for falling
		bark.linear_velocity = peel_vel + Vector3(0.0, -0.4, 0.0)
		
		# Add random rotation spin
		bark.angular_velocity = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0)
		)

func _section_is_inside_debarker(section: Node3D, debarker_pos: Vector3) -> bool:
	var section_pos = section.global_position
	var cross_axis_distance = Vector2(section_pos.y - debarker_pos.y, section_pos.z - debarker_pos.z).length()
	if cross_axis_distance > debarker_alignment_radius:
		return false
	return abs(section_pos.x - debarker_pos.x) <= debarker_peel_radius

func _get_debarker_position() -> Vector3:
	var debarker = get_node_or_null(debarker_node_path)
	if debarker is Node3D:
		return debarker.global_position
	return DEBARKER_RING_POS

var cut_box_face_a: CSGBox3D = null
var cut_box_face_b: CSGBox3D = null

func _setup_csg_cut() -> void:
	var wood_core = get_node_or_null("WoodCore")
	if wood_core is CSGShape3D:
		cut_box_face_a = _get_or_create_cut_box(wood_core, "CutBoxFaceA")
		cut_box_face_b = _get_or_create_cut_box(wood_core, "CutBoxFaceB")

func _get_or_create_cut_box(wood_core: CSGShape3D, box_name: String) -> CSGBox3D:
	var box := wood_core.get_node_or_null(box_name) as CSGBox3D
	if box == null:
		box = CSGBox3D.new()
		box.name = box_name
		box.size = Vector3(1.0, 3.0, 1.0)
		box.operation = CSGShape3D.OPERATION_SUBTRACTION
		box.material = wood_core.material
		box.position = Vector3(0.0, 0.0, 10.0)
		wood_core.add_child(box)
	return box

func _update_csg_cut_position() -> void:
	var wood_core = get_node_or_null("WoodCore")
	if wood_core is CSGShape3D:
		if cut_box_face_a == null or cut_box_face_b == null:
			_setup_csg_cut()
		var cut_depth := cuts_on_current_face * CUT_DEPTH_PER_PASS
		if current_cut_face == 0 and cut_box_face_a:
			var cut_z := 0.245 - cut_depth
			cut_box_face_a.position = Vector3(0.0, 0.0, cut_z + 0.5)
			pass
		elif current_cut_face == 1 and cut_box_face_b:
			var cut_z := -0.245 + cut_depth
			cut_box_face_b.position = Vector3(0.0, 0.0, cut_z - 0.5)
			pass

func cut_board(_saw_pos: Vector3) -> void:
	if board_count <= 0:
		return
	
	# The first cut on every face removes the curved roundback/slab.
	var is_roundback: bool = cuts_on_current_face == 0
	var prefab_path = "res://scenes/cut_board.tscn"
	if is_roundback:
		prefab_path = "res://scenes/cut_slab.tscn"
		
	# Spawn physical board
	var board_scene = load(prefab_path)
	if board_scene:
		var board_node = board_scene.instantiate()
		get_parent().add_child(board_node)
		
		# Spawn just past the saw and above the headrig outfeed so both faces
		# drop onto the same conveyor after the log is flipped.
		board_node.global_position = Vector3(_saw_pos.x, global_position.y + 0.08, 5.7)
		
		board_node.linear_velocity = Vector3(0.0, -0.25, -0.55)
		if is_roundback:
			board_node.angular_velocity = Vector3(
				randf_range(-1.2, 1.2),
				randf_range(-0.15, 0.15),
				randf_range(-0.15, 0.15)
			)
		else:
			board_node.angular_velocity = Vector3(
				randf_range(-0.5, 0.5),
				0.0,
				randf_range(-0.5, 0.5)
			)
		
		board_node.add_collision_exception_with(self)
		pass
		
	board_count -= 1
	cuts_on_current_face += 1
	
	# Perform visual flat cut using CSG Subtraction!
	_update_csg_cut_position()

func start_new_cut_face() -> void:
	cuts_on_current_face = 0
	current_cut_face = mini(current_cut_face + 1, 1)

func get_current_radius() -> float:
	return 0.245

func get_cut_depth_per_pass() -> float:
	return CUT_DEPTH_PER_PASS
