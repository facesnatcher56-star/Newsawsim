extends RigidBody3D

# Procedural Log with bark removal and board cutting mechanics
# Bark visualized as a child MeshInstance3D "Bark"
# Boards are separate MeshInstance3D children under a "Boards" node.
# Both are removed when the log passes specific processing stations.

@export var bark_enabled: bool = true
@export var board_count: int = 3  # Number of cuttable boards attached to the log

# Approximate world coordinates of processing stations (adjust if needed)
const DEBARKER_RING_POS: Vector3 = Vector3(0.3, 1.4, 1.25)
const BANDSaw_POS: Vector3 = Vector3(19, -0.083, 6.13)
const PROCESS_RADIUS: float = 0.5

func _ready() -> void:
	add_to_group("logs")
	_create_bark()
	_create_boards()

# Create visual bark as a simple box mesh matching the log size
func _create_bark() -> void:
	if not bark_enabled:
		return
	var bark = MeshInstance3D.new()
	bark.name = "Bark"
	var box = BoxMesh.new()
	# Approximate size based on existing log collision shape
	box.size = Vector3(0.32, 1.9, 0.35)
	bark.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)  # Brown bark
	bark.material_override = mat
	add_child(bark)

# Create a container with board meshes that can be cut off
func _create_boards() -> void:
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
		mat.albedo_color = Color(0.8, 0.7, 0.5)  # Light wood
		board.material_override = mat
		# Position boards along the length of the log
		board.transform.origin = Vector3(0, 0.9 - i * 0.3, 0)
		boards_root.add_child(board)

func _process(delta: float) -> void:
	# Remove bark when near the debarker ring
	if bark_enabled and $Bark.visible and global_transform.origin.distance_to(DEBARKER_RING_POS) < PROCESS_RADIUS:
		_remove_bark()
	# Cut a board when near the bandsaw
	if board_count > 0 and $Boards.get_child_count() > 0 and global_transform.origin.distance_to(BANDSaw_POS) < PROCESS_RADIUS:
		_cut_board()

func _remove_bark() -> void:
	if $Bark:
		$Bark.visible = false
		bark_enabled = false

func _cut_board() -> void:
	var boards_root = $Boards
	if boards_root.get_child_count() == 0:
		return
	# Remove the farthest board (last child)
	var board_to_remove = boards_root.get_child(boards_root.get_child_count() - 1)
	board_to_remove.visible = false
	board_count -= 1
