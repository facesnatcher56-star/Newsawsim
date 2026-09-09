@tool
extends Node3D
## Blender-built edger receiver. Local +X entry; signed local Z carry.
## Origin is chain top at the landing lane center. Keep scale at (1,1,1).
@export_range(0.0, 3.0, 0.05) var chain_speed: float = 0.55
@export var running: bool = true
@export var reverse_direction: bool = false
@export var external_stop: bool = false
@export_range(0.1, 8.0, 0.1) var acceleration: float = 1.2
const TRACKS = [-2.75, -1.375, 0.0, 1.375, 2.75]
const RUN := 4.0
const RADIUS := 0.145
const LOOP := 2.0 * RUN + TAU * RADIUS
const LINK_COUNT := 105
var actual_speed: float = 0.0
var _travel: float = 0.0
var _belts: Array[StaticBody3D] = []
var _chains: MultiMeshInstance3D
var _shafts: Array[Node] = []

func _ready() -> void:
	_belts.clear()
	_shafts = get_node("BlenderFrame").find_children("DriveShaft_*", "Node3D", true, false)
	var old := get_node_or_null("RuntimeParts")
	if old: old.free()
	var parts := Node3D.new()
	parts.name = "RuntimeParts"
	add_child(parts)
	var grip := PhysicsMaterial.new()
	grip.friction = 0.85
	var slip := PhysicsMaterial.new()
	slip.friction = 0.08
	slip.rough = false
	for x in TRACKS:
		var belt := StaticBody3D.new()
		belt.name = "ChainSurface_%d" % _belts.size()
		belt.physics_material_override = grip
		parts.add_child(belt)
		_box(belt, Vector3(x, -0.035, 1.35), Vector3(0.115, 0.07, RUN))
		_belts.append(belt)
	var ramps := StaticBody3D.new()
	ramps.name = "LandingRampCollisions"
	ramps.physics_material_override = slip
	parts.add_child(ramps)
	for i in TRACKS.size():
		var start: float = -3.10 if i == 0 else TRACKS[i - 1] + 0.075
		var end: float = TRACKS[i] - 0.075
		var rise := 0.084
		var col := _box(ramps, Vector3((start + end) * 0.5, -0.052, 0), Vector3(Vector2(end-start, rise).length(), 0.008, 0.8))
		col.rotation.z = atan2(rise, end-start)
	var frame := StaticBody3D.new()
	frame.name = "FrameCollisions"
	parts.add_child(frame)
	for z in [-0.65, 1.35, 3.35]:
		_box(frame, Vector3(0, -0.4, z), Vector3(5.95, 0.18, 0.12))
		for x in [-2.7, 2.7]:
			_box(frame, Vector3(x, -1.04, z), Vector3(0.12, 1.36, 0.12))
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

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	var target := chain_speed * (-1.0 if reverse_direction else 1.0) if running and not external_stop else 0.0
	actual_speed = move_toward(actual_speed, target, acceleration * delta)
	var velocity := global_basis.z.normalized() * actual_speed
	for belt in _belts:
		belt.constant_linear_velocity = velocity
	_travel = fposmod(_travel + actual_speed * delta, LOOP)
	for shaft in _shafts:
		(shaft as Node3D).rotate_x(actual_speed * delta / RADIUS)
	_update_links()

func _update_links() -> void:
	if not is_instance_valid(_chains): return
	for t in TRACKS.size():
		for i in LINK_COUNT:
			var s := fposmod(float(i) * LOOP / LINK_COUNT + _travel, LOOP)
			var z: float
			var y: float
			var angle: float = 0.0
			if s < RUN:
				z = -0.65 + s
				y = -0.015
			elif s < RUN + PI * RADIUS:
				angle = (s - RUN) / RADIUS
				z = 3.35 + RADIUS * sin(angle)
				y = -0.16 + RADIUS * cos(angle)
			elif s < 2.0 * RUN + PI * RADIUS:
				angle = PI
				z = 3.35 - (s - RUN - PI * RADIUS)
				y = -0.305
			else:
				angle = PI + (s - 2.0 * RUN - PI * RADIUS) / RADIUS
				z = -0.65 + RADIUS * sin(angle)
				y = -0.16 + RADIUS * cos(angle)
			var basis := Basis(Vector3.RIGHT, angle)
			var pos := Vector3(TRACKS[t], y, z) + basis * Vector3(0, 0.015, 0)
			_chains.multimesh.set_instance_transform(t * LINK_COUNT + i, Transform3D(basis, pos))
