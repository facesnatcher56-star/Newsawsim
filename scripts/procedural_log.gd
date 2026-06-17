extends RigidBody3D

# Procedural Log with bark removal and board cutting mechanics
# Bark visualized as a child MeshInstance3D "Bark"
# Boards are separate MeshInstance3D children under a "Boards" node.
# Both are removed when the log passes specific processing stations.

@export var bark_enabled: bool = true
@export var board_count: int = 4  # Number of cuttable boards attached to the log

var max_boards: int = 4

# Approximate world coordinates of processing stations (adjust if needed)
const DEBARKER_RING_POS: Vector3 = Vector3(0.3, 1.4, 1.25)
const BANDSaw_POS: Vector3 = Vector3(19, -0.083, 6.13)
const PROCESS_RADIUS: float = 0.5

func _ready() -> void:
	add_to_group("logs")
	if board_count <= 0:
		board_count = 4
	max_boards = board_count
	_create_bark()
	_create_boards()
	_setup_csg_cut()

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
	# Cut a board when near the bandsaw (fallback, only if not frozen)
	if not freeze and board_count > 0 and $Boards.get_child_count() > 0 and global_transform.origin.distance_to(BANDSaw_POS) < PROCESS_RADIUS:
		cut_board(BANDSaw_POS)

func _remove_bark() -> void:
	if $Bark:
		$Bark.visible = false
		bark_enabled = false
		for i in range(12):
			var offset_x = randf_range(-0.9, 0.9)
			var spawn_pos = global_position + Vector3(offset_x, 0.0, 0.0)
			_spawn_bark_piece(spawn_pos)

func _spawn_bark_piece(pos: Vector3) -> void:
	var bark_scene = load("res://scenes/bark_piece.tscn")
	if bark_scene:
		var bark = bark_scene.instantiate()
		# Prevent collision between the bark piece and any log in the scene to avoid physics glitches
		for log_body in get_tree().get_nodes_in_group("logs"):
			if log_body is RigidBody3D:
				bark.add_collision_exception_with(log_body)
		
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
		bark.linear_velocity = peel_vel + Vector3(0.0, -0.4, 0.0)
		
		bark.angular_velocity = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0)
		)

var cut_box: CSGBox3D = null

func _setup_csg_cut() -> void:
	var wood_core = get_node_or_null("WoodCore")
	if wood_core is CSGShape3D:
		cut_box = wood_core.get_node_or_null("CutBox")
		if not cut_box:
			cut_box = CSGBox3D.new()
			cut_box.name = "CutBox"
			cut_box.size = Vector3(1.0, 3.0, 1.0)
			cut_box.operation = CSGShape3D.OPERATION_SUBTRACTION
			cut_box.material = wood_core.material
			cut_box.position = Vector3(0.0, 0.0, 10.0) # Start outside
			wood_core.add_child(cut_box)

func _update_csg_cut_position() -> void:
	var wood_core = get_node_or_null("WoodCore")
	if wood_core is CSGShape3D:
		if not cut_box:
			cut_box = wood_core.get_node_or_null("CutBox")
		if cut_box:
			if board_count == max_boards:
				cut_box.position = Vector3(0.0, 0.0, 10.0)
			else:
				var cut_z = 0.245 - (max_boards - board_count) * 0.05
				cut_box.position = Vector3(0.0, 0.0, cut_z + 0.5)
				print("[PROCEDURAL LOG] Cut flat face at Z: ", cut_z)

func cut_board(saw_pos: Vector3) -> void:
	if board_count <= 0:
		return
	
	# Select prefab based on first cut vs subsequent cuts
	var prefab_path = "res://scenes/cut_board.tscn"
	if board_count == max_boards:
		prefab_path = "res://scenes/cut_slab.tscn"
		
	# Spawn physical board
	var board_scene = load(prefab_path)
	if board_scene:
		var board = board_scene.instantiate()
		get_parent().add_child(board)
		
		# Spawn at saw's global position but aligned with log
		# OutfeedConveyor belt is at Z = 5.44. Let's spawn at Z = 5.7 to land cleanly on the belt.
		board.global_position = Vector3(global_position.x, global_position.y, 5.7)
		
		# Organic tumble off
		board.linear_velocity = Vector3(0.0, -0.5, -0.8)
		board.angular_velocity = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		
		board.add_collision_exception_with(self)
		print("[PROCEDURAL LOG] Sliced board. Spawned at: ", board.global_position)
		
	board_count -= 1
	
	# Perform visual flat cut using CSG Subtraction!
	_update_csg_cut_position()

func get_current_radius() -> float:
	return 0.245
