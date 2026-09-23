@tool
class_name EdgerLandingDeck
extends Node3D
## Blender-built edger receiver. Local +X entry; signed local Z carry.
## Origin is chain top at the landing lane center. Keep scale at (1,1,1).
@export_range(0.0, 3.0, 0.05) var chain_speed: float = 0.55
@export var running: bool = true
@export var reverse_direction: bool = false
@export var external_stop: bool = false
## Set by a downstream machine that has taken the board off this deck's end. The
## chains stop driving and go slippery rather than merely slowing: a board that is
## still being dragged by this deck while a lug pushes it up an incline at a
## different speed is sheared between the two, which swings it across the bed.
var downstream_takeover: bool = false
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.2
const TRACKS: Array[float] = [-2.75, -1.375, 0.0, 1.375, 2.75]
## Incline lanes are centered between landing-deck lanes. These are also the
## centres of the pickup slots through the deck's discharge cross member.
const INCLINE_PICKUP_TRACKS: Array[float] = [-2.0625, -0.6875, 0.6875, 2.0625]
const PICKUP_SLOT_WIDTH := 0.24
const PICKUP_SLOT_LENGTH := 0.90
const RUN := 4.0
const RADIUS := 0.145
const LOOP: float = 2.0 * RUN + TAU * RADIUS
const LINK_COUNT: int = 104
const PITCH: float = (2.0 * RUN + TAU * RADIUS) / 104.0
var actual_speed: float = 0.0
var _travel: float = 0.0
var _grip_material: PhysicsMaterial
var _slip_material: PhysicsMaterial
var _belts_slippery: bool = false
var _belts: Array[StaticBody3D] = []
var _chains: MultiMeshInstance3D
var _shafts: Array[Node] = []
var _chain_link_nodes: Array[Array] = []

func _ready() -> void:
	_belts.clear()
	_chain_link_nodes.clear()
	var frame_node := get_node_or_null("BlenderFrame")
	if not frame_node:
		frame_node = self
	if frame_node:
		_shafts = frame_node.find_children("DriveShaft_*", "Node3D", true, false)
		for t in TRACKS.size():
			var track_links: Array[Node3D] = []
			for i in LINK_COUNT:
				var link_node := frame_node.get_node_or_null("Chain_%d_Link_%03d" % [t, i]) as Node3D
				if link_node:
					track_links.append(link_node)
			if not track_links.is_empty():
				_chain_link_nodes.append(track_links)
	var old := get_node_or_null("RuntimeParts")
	if old: old.free()
	var parts := Node3D.new()
	parts.name = "RuntimeParts"
	add_child(parts)
	_grip_material = PhysicsMaterial.new()
	_grip_material.friction = 0.35
	_slip_material = PhysicsMaterial.new()
	_slip_material.friction = 0.04
	_slip_material.rough = false
	var grip := _grip_material
	var slip := _slip_material
	for x in TRACKS:
		var belt := StaticBody3D.new()
		belt.name = "ChainSurface_%d" % _belts.size()
		belt.physics_material_override = grip
		parts.add_child(belt)
		_box(belt, Vector3(x, -0.035, 1.35), Vector3(0.115, 0.07, RUN))
		_belts.append(belt)
	# Dead plate across the arrival corridor. Boards come in broadside, sliding
	# along +X across the chain tracks, and the tracks are proud plates with gaps
	# dropping away between them: a nose that pitches down even slightly catches
	# the leading face of the next track and stops the board dead, which leaves it
	# straddling the edger. This plate gives the arrival corridor one continuous
	# surface, flush with the chain tops, so a board slides in on a single plane
	# instead of catching an edge. It is part of the carrying surface like the
	# tracks (so a board lying on it is still carried, and it goes slippery along
	# with the tracks while a board is being received).
	var entry := StaticBody3D.new()
	entry.name = "EntryPlate"
	entry.physics_material_override = grip
	_box(entry, Vector3(-0.11, -0.0025, 0.05), Vector3(6.10, 0.005, 1.40))
	parts.add_child(entry)
	_belts.append(entry)
	var ramps := StaticBody3D.new()
	ramps.name = "LandingRampCollisions"
	ramps.physics_material_override = slip
	parts.add_child(ramps)
	for i in TRACKS.size():
		var start: float = -3.10 if i == 0 else TRACKS[i - 1] + 0.062
		var end: float = TRACKS[i] - 0.062
		var rise := 0.084
		var col := _box(ramps, Vector3((start + end) * 0.5, -0.049, 0), Vector3(Vector2(end-start, rise).length(), 0.008, 0.8))
		col.rotation.z = atan2(rise, end-start)
	var frame := StaticBody3D.new()
	frame.name = "FrameCollisions"
	parts.add_child(frame)
	for z: float in [-0.65, 1.35]:
		_box(frame, Vector3(0, -0.4, z), Vector3(5.95, 0.18, 0.12))
		for x: float in [-2.7, 2.7]:
			_box(frame, Vector3(x, -1.04, z), Vector3(0.12, 1.36, 0.12))
	# The discharge cross member is split around the four incline lanes. The
	# incline begins below this deck, so its lugs need real openings to rise
	# through rather than striking one full-width collision beam at the seam.
	_add_slotted_discharge_member(frame, 3.35)
	for x: float in [-2.7, 2.7]:
		_box(frame, Vector3(x, -1.04, 3.35), Vector3(0.12, 1.36, 0.12))
	for x in TRACKS:
		_box(frame, Vector3(x, -0.10, 1.35), Vector3(0.12, 0.05, RUN))
	var link_scene := load("res://game/assets/models/edger_landing_deck/roller_chain_link.glb") as PackedScene
	if link_scene:
		var model := link_scene.instantiate()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			_chains = MultiMeshInstance3D.new()
			_chains.name = "AnimatedRollerChains"
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = (meshes[0] as MeshInstance3D).mesh
			mm.instance_count = LINK_COUNT * TRACKS.size()
			_chains.multimesh = mm
			if not _chain_link_nodes.is_empty():
				_chains.visible = false
			parts.add_child(_chains)
			_update_links()
		model.free()

func _box(body: StaticBody3D, pos: Vector3, size: Vector3) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)
	return col


func _add_slotted_discharge_member(frame: StaticBody3D, z: float) -> void:
	const HALF_WIDTH := 5.95 * 0.5
	var cursor: float = -HALF_WIDTH
	for slot_x: float in INCLINE_PICKUP_TRACKS:
		var slot_left: float = slot_x - PICKUP_SLOT_WIDTH * 0.5
		var segment_width: float = slot_left - cursor
		if segment_width > 0.001:
			_box(frame, Vector3(cursor + segment_width * 0.5, -0.4, z),
				Vector3(segment_width, 0.18, 0.12))
		cursor = slot_x + PICKUP_SLOT_WIDTH * 0.5
	var final_width: float = HALF_WIDTH - cursor
	if final_width > 0.001:
		_box(frame, Vector3(cursor + final_width * 0.5, -0.4, z),
			Vector3(final_width, 0.18, 0.12))


## Local X a board's tail has to pass before the deck considers it fully on.
const ARRIVAL_X: float = -2.90
## Below this speed along the arrival axis the edger is no longer delivering.
const DELIVERED_SPEED: float = 0.05
## How long a board must sit still before the chains take it over.
const STRANDED_DWELL: float = 0.25

## Board instance ids and how long each has been waiting, still overlapping the
## edger bed, for a push that is not coming.
var _resting_seconds: Dictionary = {}

## Returns the board the chains must take over because the edger has finished
## with it, or null.
##
## Waiting for the tail to clear the edger bed is right while a delivery is in
## progress, but it is a deadlock once the delivery has stopped: the edger will
## not push a board it has released, and until the tail is clear this deck refuses
## to drive, so the board sits on the chains forever. A short dwell tells the two
## states apart - still being pushed, or finished and stranded - without letting a
## momentary pause mid-delivery hand the board to the wrong machine.
func _stranded_board_on_deck(delta: float) -> RigidBody3D:
	var stranded: RigidBody3D = null
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var body := node as RigidBody3D
		if not is_instance_valid(body) or body.freeze:
			continue
		var local_pos := to_local(body.global_position)
		var half_len: float = _board_half_length(body)
		var in_corridor: bool = absf(local_pos.z) < 0.6 and local_pos.y > -0.3 and local_pos.y < 0.6
		var tail_on_edger: bool = local_pos.x - half_len < ARRIVAL_X
		var pushed: bool = absf(body.linear_velocity.dot(global_basis.x)) >= DELIVERED_SPEED
		if not in_corridor or not tail_on_edger or pushed:
			continue
		var key: int = body.get_instance_id()
		seen[key] = true
		var resting: float = float(_resting_seconds.get(key, 0.0)) + delta
		_resting_seconds[key] = resting
		if resting >= STRANDED_DWELL and stranded == null:
			stranded = body
	for key in _resting_seconds.keys():
		if not seen.has(key):
			_resting_seconds.erase(key)
	return stranded

func _board_half_length(body: Node) -> float:
	return float(body.get("product_length")) * 0.5 if "product_length" in body else 2.44

func _is_board_entering(ignore: RigidBody3D = null) -> bool:
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var body := node as RigidBody3D
		if not is_instance_valid(body) or body == ignore or body.freeze:
			continue
		var local_pos := to_local(body.global_position)
		if absf(local_pos.z) < 0.6 and local_pos.y > -0.3 and local_pos.y < 0.6:
			var half_len: float = _board_half_length(body)
			var tail_x: float = local_pos.x - half_len
			# The edger bed ends at local x = -3.00 (world 47.80). Holding the
			# chains off until the tail is clear of it matters: carrying a board
			# in Z while it still overlaps the edger drags the tail back across
			# the edger's outfeed rollers instead of letting it transfer.
			if tail_x < ARRIVAL_X:
				return true
			if local_pos.x < 1.0 and body.linear_velocity.dot(global_basis.x) > 0.4:
				return true
	return false

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	var target := chain_speed * (-1.0 if reverse_direction else 1.0) if running and not external_stop else 0.0
	actual_speed = move_toward(actual_speed, target, acceleration * delta)
	var velocity := global_basis.z.normalized() * actual_speed
	# While a board is still being received the chains must neither drive nor
	# grip: their carry direction is across the board's travel, so grip here acts
	# as a brake and can stall the board half on the edger. Deliveries are
	# slippery; carrying starts once the board is clear and on the deck.
	var receiving: bool = downstream_takeover or _is_board_entering(_stranded_board_on_deck(delta))
	if receiving != _belts_slippery:
		_belts_slippery = receiving
		for belt in _belts:
			if is_instance_valid(belt):
				belt.physics_material_override = _slip_material if receiving else _grip_material
	var drive_belts: bool = not receiving
	for belt in _belts:
		belt.constant_linear_velocity = velocity if drive_belts else Vector3.ZERO
	_travel = fposmod(_travel + actual_speed * delta, LOOP)
	for shaft in _shafts:
		(shaft as Node3D).rotate_x(actual_speed * delta / RADIUS)
	_update_links()

func _pin_pos(s: float) -> Vector2:
	var r := fposmod(s, LOOP)
	if r < RUN:
		return Vector2(-0.018, -0.65 + r)
	r -= RUN
	var arc := PI * RADIUS
	if r < arc:
		var ang := r / RADIUS
		return Vector2(-0.163 + RADIUS * cos(ang), 3.35 + RADIUS * sin(ang))
	r -= arc
	if r < RUN:
		return Vector2(-0.308, 3.35 - r)
	r -= RUN
	var ang := PI + r / RADIUS
	return Vector2(-0.163 + RADIUS * cos(ang), -0.65 + RADIUS * sin(ang))

func _update_links() -> void:
	for t in TRACKS.size():
		for i in LINK_COUNT:
			var s0: float = float(i) * PITCH + _travel
			var s1: float = s0 + PITCH
			var p0: Vector2 = _pin_pos(s0)
			var p1: Vector2 = _pin_pos(s1)
			var dy: float = p1.x - p0.x
			var dz: float = p1.y - p0.y
			var angle: float = atan2(-dy, dz)
			var basis: Basis = Basis(Vector3.RIGHT, angle)
			var pos: Vector3 = Vector3(TRACKS[t], p0.x, p0.y)
			if t < _chain_link_nodes.size() and i < _chain_link_nodes[t].size():
				_chain_link_nodes[t][i].transform = Transform3D(basis, pos)
			if is_instance_valid(_chains) and is_instance_valid(_chains.multimesh):
				_chains.multimesh.set_instance_transform(t * LINK_COUNT + i, Transform3D(basis, pos))
