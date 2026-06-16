extends RigidBody3D

# Log with bark and board cutting mechanics
# The bark is represented by a child MeshInstance3D "Bark"
# Boards are represented by child MeshInstance3D nodes under a "Boards" container.
# Bark and boards are removed when the log passes specific processing stations.

@export var bark_enabled: bool = true
@export var board_count: int = 3  # Number of cuttable boards attached to the log
@export var debarker_node_path: NodePath = "../DebarkerRing/Model"
@export var debarker_peel_radius: float = 0.04
@export var debarker_alignment_radius: float = 0.85

# Positions of processing stations (approximate world coordinates)
const DEBARKER_RING_POS: Vector3 = Vector3(0.3, 1.4, 1.25)
const BANDSaw_POS: Vector3 = Vector3(19, -0.083, 6.13)  # Position of the Bandsaw node
const PROCESS_RADIUS: float = 0.5  # Proximity radius to trigger processing

var bark_sections: Array[Node3D] = []

func _ready() -> void:
	add_to_group("logs")
	_create_bark()
	_create_boards()
	_collect_bark_sections()

# Create visual bark as a simple box mesh matching the log size
func _create_bark() -> void:
	if not bark_enabled:
		return
	if has_node("Bark"):
		return
	var bark = MeshInstance3D.new()
	bark.name = "Bark"
	# Use a simple BoxMesh sized to the log's collision shape (assumes uniform size)
	var box = BoxMesh.new()
	box.size = Vector3(0.32, 1.9, 0.35)  # Approximate size from existing BoxShape3D_o3d8n
	bark.mesh = box
	# Brown bark material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)
	bark.material_override = mat
	add_child(bark)

# Create a container with board meshes that can be cut off
func _create_boards() -> void:
	if has_node("Boards"):
		return
	var boards_root = Node3D.new()
	boards_root.name = "Boards"
	add_child(boards_root)
	for i in range(board_count):
		var board = MeshInstance3D.new()
		board.name = "Board_%d" % i
		var plane = BoxMesh.new()
		plane.size = Vector3(0.3, 0.02, 0.6)  # Thin board
		board.mesh = plane
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.7, 0.5)
		board.material_override = mat
		# Position boards along the log length
		board.transform.origin = Vector3(0, 0.9 - i * 0.3, 0)
		boards_root.add_child(board)

func _process(delta: float) -> void:
	# Automatic bark removal when near the debarker ring
	if bark_enabled:
		_update_bark_peeling()
	# Automatic board cutting when near the bandsaw
	if board_count > 0 and global_transform.origin.distance_to(BANDSaw_POS) < PROCESS_RADIUS:
		_cut_board()

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
	for section in bark_sections:
		if not is_instance_valid(section):
			continue
		if section.visible:
			remaining_sections += 1
			if _section_is_inside_debarker(section, debarker_pos):
				section.visible = false
				remaining_sections -= 1
	if remaining_sections <= 0 and not bark_sections.is_empty():
		bark_enabled = false

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

func _cut_board() -> void:
	if board_count <= 0:
		return
	var boards_root = $Boards
	if boards_root.get_child_count() == 0:
		return
	# Remove the farthest board (last child)
	var board_to_remove = boards_root.get_child(boards_root.get_child_count() - 1)
	board_to_remove.visible = false
	board_count -= 1
