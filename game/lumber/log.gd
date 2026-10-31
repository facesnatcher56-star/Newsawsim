extends RigidBody3D

const LogBark = preload("res://game/lumber/log_bark.gd")

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
## How much the log bows along its length (m at mid-length); -1 until first sawn. Most logs are
## straight enough; a crooked one gives short side boards: a cut near the outside only runs
## through wood for part of the length, and the sawyer saves what length he can.
var sweep: float = -1.0

const CUT_DEPTH_PER_PASS: float = 0.05
const LOG_CORE_LENGTH: float = 4.922
const LOG_PRODUCT_LENGTH: float = 4.877
const CUT_BOX_LENGTH_CLEARANCE: float = 0.24
const CUT_PRODUCT_FORWARD_SPEED: float = 0.35
const CUT_PRODUCT_DROP_SPEED: float = -0.22
const CUT_PRODUCT_BELT_KICK_SPEED: float = -1.35

# Positions of processing stations (approximate world coordinates)
const DEBARKER_RING_POS: Vector3 = Vector3(5.165, 0.714, 2.072)
const BANDSaw_POS: Vector3 = Vector3(19, -0.083, 6.13)  # Position of the Bandsaw node
const PROCESS_RADIUS: float = 0.5  # Proximity radius to trigger processing

var bark_controller = null

func _ready() -> void:
	add_to_group("logs")
	if board_count <= 0:
		board_count = 4
	max_boards = board_count
	bark_controller = LogBark.new()
	bark_controller.setup(
		self,
		bark_enabled,
		debarker_node_path,
		debarker_peel_radius,
		debarker_alignment_radius,
		DEBARKER_RING_POS
	)
	bark_enabled = bark_controller.is_enabled()
	_create_boards()
	_setup_csg_cut()
	_randomize_wood()


## Every log its own wood: tint, ring spacing and grain pattern (wood.gdshader).
var wood_tint := Vector3.ONE
var wood_seed: float = 0.0
var wood_rings: float = 160.0


func _randomize_wood() -> void:
	var warm := randf_range(-0.08, 0.08)
	var shade := randf_range(0.82, 1.08)
	wood_tint = Vector3(shade * (1.0 + warm), shade, shade * (1.0 - warm * 1.5))
	wood_seed = randf_range(0.0, 100.0)
	wood_rings = randf_range(110.0, 230.0)
	var wood_core := get_node_or_null("WoodCore") as GeometryInstance3D
	if wood_core:
		apply_wood(wood_core)


func apply_wood(g: GeometryInstance3D) -> void:
	g.set_instance_shader_parameter("tint", wood_tint)
	g.set_instance_shader_parameter("seed", wood_seed)
	g.set_instance_shader_parameter("ring_scale", wood_rings)

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

func _process(_delta: float) -> void:
	if bark_controller:
		bark_controller.update()
		bark_enabled = bark_controller.is_enabled()
	if not freeze and board_count > 0 and global_transform.origin.distance_to(BANDSaw_POS) < PROCESS_RADIUS:
		cut_board(BANDSaw_POS)

func _remove_bark() -> void:
	if bark_controller:
		bark_controller.remove_bark()
		bark_enabled = bark_controller.is_enabled()

func _get_log_core_length() -> float:
	var wood_core := get_node_or_null("WoodCore") as CSGCylinder3D
	if wood_core:
		return wood_core.height
	return LOG_CORE_LENGTH

func get_log_core_length() -> float:
	return _get_log_core_length()

func get_log_product_length() -> float:
	return LOG_PRODUCT_LENGTH

var cut_box_face_a: CSGBox3D = null
var cut_box_face_b: CSGBox3D = null

func _setup_csg_cut() -> void:
	var wood_core = get_node_or_null("WoodCore")
	if wood_core is CSGShape3D:
		# The end-grain discs join the core first, so the cuts take them off with the rest.
		var at := 0
		for end_name in ["WoodEndLeft", "WoodEndRight"]:
			var end_disc := get_node_or_null(end_name) as CSGShape3D
			if end_disc:
				var local: Transform3D = wood_core.transform.affine_inverse() * end_disc.transform
				remove_child(end_disc)
				wood_core.add_child(end_disc)
				wood_core.move_child(end_disc, at)
				end_disc.transform = local
				at += 1
		cut_box_face_a = _get_or_create_cut_box(wood_core, "CutBoxFaceA")
		cut_box_face_b = _get_or_create_cut_box(wood_core, "CutBoxFaceB")

func _get_or_create_cut_box(wood_core: CSGShape3D, box_name: String) -> CSGBox3D:
	var box := wood_core.get_node_or_null(box_name) as CSGBox3D
	if box == null:
		box = CSGBox3D.new()
		box.name = box_name
		box.operation = CSGShape3D.OPERATION_SUBTRACTION
		box.material = wood_core.material
		box.position = Vector3(0.0, 0.0, 10.0)
		wood_core.add_child(box)
	box.size = Vector3(1.0, _get_log_core_length() + CUT_BOX_LENGTH_CLEARANCE, 1.0)
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

# --- Progressive cut ------------------------------------------------------------------------
# While the log runs through the saw the cut opens from its front end back to the saw line: a
# subtraction box in WoodCore takes the sawn length off the log, and the piece being cut (the
# log's own cylinder between this cut's plane and the last one) grows out from the saw, leaning
# off the blade. cut_board() then swaps it for the real slab or board where it is.

const KERF: float = 0.004
var _peel: CSGCombiner3D = null
var _peel_cyl: CSGCylinder3D = null
var _progress_box: CSGBox3D = null
var _peel_travel := Vector3.RIGHT
var _peel_len: float = 0.0


func _face_sign() -> float:
	return 1.0 if current_cut_face == 0 else -1.0


## Distances from the log axis of this cut's plane (inner) and the last one (outer).
func _cut_planes() -> Vector2:
	var r := get_current_radius()
	return Vector2(r - (cuts_on_current_face + 1) * CUT_DEPTH_PER_PASS, r - cuts_on_current_face * CUT_DEPTH_PER_PASS)


func begin_cut(travel_direction: Vector3) -> void:
	_end_peel()
	var wood_core := get_node_or_null("WoodCore") as CSGCylinder3D
	if wood_core == null or board_count <= 0:
		return
	_peel_travel = travel_direction.normalized()
	var s := _face_sign()
	var planes := _cut_planes()
	var long := _get_log_core_length() + 1.0
	_progress_box = CSGBox3D.new()
	_progress_box.name = "CutProgress"
	_progress_box.operation = CSGShape3D.OPERATION_SUBTRACTION
	_progress_box.material = wood_core.material
	wood_core.add_child(_progress_box)
	_peel = CSGCombiner3D.new()
	_peel.name = "CutPeel"
	add_child(_peel)
	_peel_cyl = CSGCylinder3D.new()
	_peel_cyl.radius = wood_core.radius
	_peel_cyl.sides = wood_core.sides
	_peel_cyl.material = wood_core.material
	_peel.add_child(_peel_cyl)
	apply_wood(_peel)
	# Keep only the slice between the two planes.
	var inner := CSGBox3D.new()
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.material = wood_core.material
	inner.size = Vector3(1.0, long, 1.0)
	inner.position = Vector3(0.0, 0.0, s * (planes.x - 0.5))
	_peel.add_child(inner)
	if cuts_on_current_face > 0:
		var outer := CSGBox3D.new()
		outer.operation = CSGShape3D.OPERATION_SUBTRACTION
		outer.material = wood_core.material
		outer.size = Vector3(1.0, long, 1.0)
		outer.position = Vector3(0.0, 0.0, s * (planes.y + 0.5))
		_peel.add_child(outer)
	update_cut(0.0)


## progress: how far along the log (m, from its front end) the saw has cut.
func update_cut(progress: float) -> void:
	var wood_core := get_node_or_null("WoodCore") as CSGCylinder3D
	if wood_core == null or _peel == null:
		return
	var h := _get_log_core_length()
	_peel_len = clampf(progress, 0.0, h)
	var s := _face_sign()
	var planes := _cut_planes()
	# Wood-core local +Y or -Y is the log's front end (the end leading into the saw).
	var ydir := signf(wood_core.global_basis.y.dot(_peel_travel))
	var mid := ydir * (h - _peel_len) * 0.5
	_progress_box.visible = _peel_len > 0.01
	_progress_box.size = Vector3(1.0, _peel_len + 0.12, 1.0)
	_progress_box.position = Vector3(0.0, mid + ydir * 0.06, s * (planes.x + 0.5))
	_peel.visible = _peel_len > 0.01
	_peel_cyl.height = maxf(_peel_len, 0.01)
	_peel_cyl.position = Vector3(0.0, mid, 0.0)
	# Off the saw line by the kerf, the cut end leaning away from the blade (a slab more).
	var lean := minf((0.05 if cuts_on_current_face == 0 else 0.012) * _peel_len / h, 0.05)
	var pivot := Vector3(0.0, ydir * (h * 0.5 - _peel_len), 0.0)
	var tilt := asin(clampf(s * ydir * lean / maxf(_peel_len, 0.05), -0.2, 0.2))
	var bend := Transform3D(Basis(Vector3.RIGHT, tilt), Vector3.ZERO)
	_peel.transform = wood_core.transform * Transform3D(Basis.IDENTITY, pivot + Vector3(0.0, 0.0, s * KERF)) \
			* bend * Transform3D(Basis.IDENTITY, -pivot)


## Where the cut piece is: centre, along-the-log axis (the travel direction) and its outward
## face normal, in world space.
func _peel_frame() -> Array:
	var planes := _cut_planes()
	var s := _face_sign()
	var centre := _peel.global_transform * Vector3(0.0, _peel_cyl.position.y, s * (planes.x + planes.y) * 0.5)
	var along := _peel_travel
	var normal := (_peel.global_basis.z * s).normalized()
	return [centre, along, normal]


func _end_peel() -> void:
	if _peel:
		_peel.queue_free()
	if _progress_box:
		_progress_box.queue_free()
	_peel = null
	_peel_cyl = null
	_progress_box = null


func cut_board(_saw_pos: Vector3, travel_direction: Vector3 = Vector3.RIGHT) -> void:
	if board_count <= 0:
		_end_peel()
		return
	var peel_frame: Array = _peel_frame() if _peel != null else []

	# The first cut on every face removes the curved roundback/slab.
	var is_roundback: bool = cuts_on_current_face == 0
	var prefab_path = "res://game/lumber/cut_board.tscn"
	if is_roundback:
		prefab_path = "res://game/lumber/cut_slab.tscn"
		
	# Spawn physical board
	var board_scene = load(prefab_path)
	if board_scene:
		var board_node = board_scene.instantiate()
		get_parent().add_child(board_node)
		if board_node.has_method("configure_length"):
			board_node.configure_length(LOG_PRODUCT_LENGTH)
		
		# Spawn with the board center where the cut product is when its tail clears the blade.
		var product_center := _saw_pos + travel_direction.normalized() * (LOG_PRODUCT_LENGTH * 0.5)
		board_node.global_position = Vector3(product_center.x, global_position.y + 0.08, 5.7)
		
		board_node.linear_velocity = (
			travel_direction.normalized() * CUT_PRODUCT_FORWARD_SPEED
			+ Vector3(0.0, CUT_PRODUCT_DROP_SPEED, CUT_PRODUCT_BELT_KICK_SPEED)
		)
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
		# Side boards off the headrig are rough flitches: wider than the board they will make,
		# with bark on their edges, for the scanner and edger to make the most of.
		if not is_roundback and board_node.has_method("set_wane"):
			# Width and wane from where the cut is: the board's inner face is a chord at this cut's
			# plane, its outer face the narrower chord at the last one, and the difference is the
			# rounded, barky edge left on each side (the log is never quite centred: one side more).
			var planes := _cut_planes()
			var r := get_current_radius()
			var inner_w := 2.0 * sqrt(maxf(r * r - planes.x * planes.x, 0.0))
			var outer_w := 2.0 * sqrt(maxf(r * r - planes.y * planes.y, 0.0))
			var width := minf(inner_w * randf_range(0.94, 1.0), 0.33)
			var wane := maxf((inner_w - outer_w) * 0.5, 0.012)
			var skew := randf_range(-0.35, 0.35)
			var length := _board_length()
			board_node.configure_dimensions(length, randf_range(0.038, 0.043), width)
			board_node.nominal_size = "flitch"
			board_node.set_wane(wane * (1.0 + skew), wane * (1.0 - skew))
			# A short board comes from whichever stretch of the crooked log the cut stays in wood.
			if length < LOG_PRODUCT_LENGTH - 0.01:
				var slack := (LOG_PRODUCT_LENGTH - length) * 0.5
				board_node.global_position.x += randf_range(-slack, slack)
		if not peel_frame.is_empty():
			_take_over_peel(board_node, peel_frame, is_roundback)

	board_count -= 1
	_end_peel()
	cuts_on_current_face += 1
	
	# Perform visual flat cut using CSG Subtraction!
	_update_csg_cut_position()

## Put the sawn product where the cut piece is, standing on edge off the saw line (thickness
## along the cut face's normal, the rounded side of a slab outward), then let it fall away from
## the blade onto the outfeed: moving on with the log, tipping outward.
func _take_over_peel(product: RigidBody3D, frame: Array, is_roundback: bool) -> void:
	var centre: Vector3 = frame[0]
	var along: Vector3 = frame[1]
	var normal: Vector3 = frame[2]
	var shift := 0.0
	if "product_length" in product and product.product_length < LOG_PRODUCT_LENGTH - 0.01:
		# A short board from a crooked log: somewhere along the cut.
		var slack: float = (LOG_PRODUCT_LENGTH - product.product_length) * 0.5
		shift = randf_range(-slack, slack)
	var width_axis := along.cross(normal).normalized()
	product.global_transform = Transform3D(Basis(along, normal, width_axis), centre + along * shift)
	product.linear_velocity = along * CUT_PRODUCT_FORWARD_SPEED + normal * 0.25
	# Tip over outward about the long axis (top edge away from the log).
	var tip := along * (1.8 if is_roundback else 1.4)
	if tip.cross(Vector3.UP).dot(normal) < 0.0:
		tip = -tip
	product.angular_velocity = tip
	var slab_look := product.get_node_or_null("CSGCombiner3D") as GeometryInstance3D
	if slab_look:
		apply_wood(slab_look)


## Length of the side board this cut makes, in whole 2 ft steps from 6 to 16 ft: full length on
## a straight log; on a crooked one the first board in from the slab is shortest and the next
## longer, as the cut gets deeper into the log.
func _board_length() -> float:
	if sweep < 0.0:
		# Roughly two logs in three are straight enough for full-length boards.
		sweep = 0.0 if randf() < 0.65 else randf_range(0.03, 0.12)
	var lose := sweep / 0.12 * (10.0 if cuts_on_current_face <= 1 else 5.0)
	var feet := clampi(16 - 2 * int(round(lose * 0.5)), 6, 16)
	return feet * 0.3048


func start_new_cut_face() -> void:
	cuts_on_current_face = 0
	current_cut_face = mini(current_cut_face + 1, 1)

func get_current_radius() -> float:
	return 0.245

func get_cut_depth_per_pass() -> float:
	return CUT_DEPTH_PER_PASS
