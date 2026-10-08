class_name SorterChainSystem
extends Node3D

## High-performance, physically synchronized closed-loop chain drive system.
## Simulates continuous roller chains wrapping around drive and idler sprockets
## with zero slip, rigid-link chordal seating, and synchronized push lugs.

# -----------------------------------------------------------------------------
# TOP OVERHEAD CONVEYOR PARAMETERS
# -----------------------------------------------------------------------------
const TOP_PITCH: float = 0.20
const TOP_TEETH: int = 10
const TOP_SPROCKET_R: float = 0.3236068 # P / (2 * sin(PI / 10))
const TOP_SHAFT_Y: float = 5.00
const TOP_X_TAIL: float = -0.70
const TOP_X_HEAD: float = 50.70
const TOP_SPAN: float = TOP_X_HEAD - TOP_X_TAIL # 51.40 m
const TOP_STRANDS: Array[float] = [-1.8, -0.6, 0.6, 1.8]

# -----------------------------------------------------------------------------
# BOTTOM HAUL-OUT CONVEYOR PARAMETERS
# -----------------------------------------------------------------------------
const HAUL_PITCH: float = 0.10
const HAUL_TEETH: int = 6
const HAUL_SPROCKET_R: float = 0.100 # P / (2 * sin(PI / 6))
const HAUL_SHAFT_Y: float = 0.10
const HAUL_X_TAIL: float = -0.70
const HAUL_X_HEAD: float = 51.20
const HAUL_SPAN: float = HAUL_X_HEAD - HAUL_X_TAIL # 51.90 m
const HAUL_STRANDS: Array[float] = [-2.0, -1.0, 0.0, 1.0, 2.0]

# Path lengths
var _top_loop_len: float = 0.0
var _haul_loop_len: float = 0.0

var _top_links_per_strand: int = 0
var _top_lugs_per_strand: int = 0
var _haul_links_per_strand: int = 0

# MultiMesh nodes
var _mm_top_links: MultiMeshInstance3D = null
var _mm_top_lugs: MultiMeshInstance3D = null
var _mm_haul_links: MultiMeshInstance3D = null

# One synchronized AnimatableBody3D per lug pitch. Each station has a collision
# post at all four chain lanes; the MultiMeshes are visuals only.
var _top_lug_bodies: Array[AnimatableBody3D] = []
var _top_lug_shapes: Array[Array] = []

# Current continuous distance along closed paths
var current_top_dist: float = 0.0
var current_haul_dist: float = 0.0

func _ready() -> void:
	_calculate_loop_geometry()
	_setup_multimeshes()
	_setup_physical_lugs()
	update_chains(0.0, 0.0)

func _calculate_loop_geometry() -> void:
	# Overhead loop: 2 straight spans + 2 semicircle wraps
	_top_loop_len = 2.0 * TOP_SPAN + 2.0 * PI * TOP_SPROCKET_R
	_top_links_per_strand = int(round(_top_loop_len / TOP_PITCH))
	_top_lugs_per_strand = int(round(_top_loop_len / (TOP_PITCH * 5.0))) # 1.0m spacing (every 5th link)

	# Haul-out loop: 2 straight spans + 2 semicircle wraps
	_haul_loop_len = 2.0 * HAUL_SPAN + 2.0 * PI * HAUL_SPROCKET_R
	_haul_links_per_strand = int(round(_haul_loop_len / HAUL_PITCH))

func _extract_mesh_from_glb(glb_path: String) -> Mesh:
	var res = load(glb_path)
	if not res:
		push_error("Failed to load GLB: " + glb_path)
		return null
	var inst = res.instantiate()
	var mesh: Mesh = null
	for child in inst.get_children():
		if child is MeshInstance3D and child.mesh:
			mesh = child.mesh
			break
	inst.queue_free()
	return mesh

func _setup_multimeshes() -> void:
	# 1. Top chain links
	var top_link_mesh := _extract_mesh_from_glb("res://game/assets/models/bin_sorter/sorter_chain_link.glb")
	if top_link_mesh:
		_mm_top_links = MultiMeshInstance3D.new()
		_mm_top_links.name = "TopChainLinks"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = _top_links_per_strand * TOP_STRANDS.size()
		mm.mesh = top_link_mesh
		_mm_top_links.multimesh = mm
		add_child(_mm_top_links)

	# 2. Top chain lugs
	var top_lug_mesh := _extract_mesh_from_glb("res://game/assets/models/bin_sorter/sorter_chain_lug.glb")
	if top_lug_mesh:
		_mm_top_lugs = MultiMeshInstance3D.new()
		_mm_top_lugs.name = "TopChainLugs"
		var mm_lugs := MultiMesh.new()
		mm_lugs.transform_format = MultiMesh.TRANSFORM_3D
		mm_lugs.instance_count = _top_lugs_per_strand * TOP_STRANDS.size()
		mm_lugs.mesh = top_lug_mesh
		_mm_top_lugs.multimesh = mm_lugs
		add_child(_mm_top_lugs)

	# 3. Haul-out chain links
	var haul_link_mesh := _extract_mesh_from_glb("res://game/assets/models/bin_sorter/haulout_chain_link.glb")
	if haul_link_mesh:
		_mm_haul_links = MultiMeshInstance3D.new()
		_mm_haul_links.name = "HaulOutChainLinks"
		var mm_haul := MultiMesh.new()
		mm_haul.transform_format = MultiMesh.TRANSFORM_3D
		mm_haul.instance_count = _haul_links_per_strand * HAUL_STRANDS.size()
		mm_haul.mesh = haul_link_mesh
		_mm_haul_links.multimesh = mm_haul
		add_child(_mm_haul_links)


func _setup_physical_lugs() -> void:
	_top_lug_bodies.clear()
	_top_lug_shapes.clear()
	var lug_material: PhysicsMaterial = PhysicsMaterial.new()
	lug_material.friction = 0.45
	lug_material.bounce = 0.0
	for lug_index: int in _top_lugs_per_strand:
		var station: AnimatableBody3D = AnimatableBody3D.new()
		station.name = "SorterLugStation_%03d" % lug_index
		station.sync_to_physics = true
		station.physics_material_override = lug_material
		add_child(station)
		var shapes: Array[CollisionShape3D] = []
		for lane_z: float in TOP_STRANDS:
			var collision: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			# The post descends from the overhead chain far enough to meet the
			# trailing face of a board resting on the 4.30 m slide rails.
			box.size = Vector3(0.11, 0.38, 0.14)
			collision.shape = box
			collision.position = Vector3(0.0, -0.19, lane_z)
			station.add_child(collision)
			shapes.append(collision)
		_top_lug_bodies.append(station)
		_top_lug_shapes.append(shapes)
	_place_physical_lugs()


func _place_physical_lugs() -> void:
	for lug_index: int in _top_lug_bodies.size():
		var s: float = fposmod(current_top_dist + float(lug_index) * TOP_PITCH * 5.0, _top_loop_len)
		var station: AnimatableBody3D = _top_lug_bodies[lug_index]
		var station_transform: Transform3D = get_top_lug_transform(lug_index, 0)
		station_transform.origin.z = 0.0
		station.transform = station_transform
		var on_working_run: bool = s < TOP_SPAN
		for shape: CollisionShape3D in _top_lug_shapes[lug_index]:
			shape.disabled = not on_working_run


## Samples the 2D path coordinates at distance s along the overhead loop.
## Starts at tail sprocket bottom tangent (X_TAIL, SHAFT_Y - R), travels +X along working run,
## wraps head sprocket, returns -X along return run (on top of race), wraps tail sprocket.
func sample_top_path(s: float) -> Vector2:
	s = fmod(s, _top_loop_len)
	if s < 0.0:
		s += _top_loop_len

	var arc_len: float = PI * TOP_SPROCKET_R
	if s < TOP_SPAN:
		# Bottom working run: moving +X
		return Vector2(TOP_X_TAIL + s, TOP_SHAFT_Y - TOP_SPROCKET_R)
	elif s < TOP_SPAN + arc_len:
		# Head sprocket wrap (right): from -PI/2 to +PI/2
		var ds: float = s - TOP_SPAN
		var phi: float = -PI * 0.5 + (ds / TOP_SPROCKET_R)
		return Vector2(TOP_X_HEAD + TOP_SPROCKET_R * cos(phi), TOP_SHAFT_Y + TOP_SPROCKET_R * sin(phi))
	elif s < 2.0 * TOP_SPAN + arc_len:
		# Top return run: moving -X (riding on top of race)
		var ds: float = s - (TOP_SPAN + arc_len)
		return Vector2(TOP_X_HEAD - ds, TOP_SHAFT_Y + TOP_SPROCKET_R)
	else:
		# Tail sprocket wrap (left): from +PI/2 to +3PI/2
		var ds: float = s - (2.0 * TOP_SPAN + arc_len)
		var phi: float = PI * 0.5 + (ds / TOP_SPROCKET_R)
		return Vector2(TOP_X_TAIL + TOP_SPROCKET_R * cos(phi), TOP_SHAFT_Y + TOP_SPROCKET_R * sin(phi))

## Samples the 2D path coordinates at distance s along the haul-out drag loop.
## Starts at tail sprocket top tangent (X_TAIL, SHAFT_Y + R), travels +X along carrying run,
## wraps head sprocket, returns -X along floor return run, wraps tail sprocket.
func sample_haul_path(s: float) -> Vector2:
	s = fmod(s, _haul_loop_len)
	if s < 0.0:
		s += _haul_loop_len

	var arc_len: float = PI * HAUL_SPROCKET_R
	if s < HAUL_SPAN:
		# Top carrying run: moving +X at Y = SHAFT_Y + R (0.20m)
		return Vector2(HAUL_X_TAIL + s, HAUL_SHAFT_Y + HAUL_SPROCKET_R)
	elif s < HAUL_SPAN + arc_len:
		# Head sprocket wrap (right): from +PI/2 to -PI/2
		var ds: float = s - HAUL_SPAN
		var phi: float = PI * 0.5 - (ds / HAUL_SPROCKET_R)
		return Vector2(HAUL_X_HEAD + HAUL_SPROCKET_R * cos(phi), HAUL_SHAFT_Y + HAUL_SPROCKET_R * sin(phi))
	elif s < 2.0 * HAUL_SPAN + arc_len:
		# Bottom floor return run: moving -X at Y = SHAFT_Y - R (0.00m)
		var ds: float = s - (HAUL_SPAN + arc_len)
		return Vector2(HAUL_X_HEAD - ds, HAUL_SHAFT_Y - HAUL_SPROCKET_R)
	else:
		# Tail sprocket wrap (left): from -PI/2 to +PI/2
		var ds: float = s - (2.0 * HAUL_SPAN + arc_len)
		var phi: float = -PI * 0.5 - (ds / HAUL_SPROCKET_R)
		return Vector2(HAUL_X_TAIL + HAUL_SPROCKET_R * cos(phi), HAUL_SHAFT_Y + HAUL_SPROCKET_R * sin(phi))

## Builds a 3D rigid-link transform from pin 1 (p1) to pin 2 (p2) at lateral coordinate z.
## Local +X points along the link chord from p1 to p2.
## Local +Z is along global Z (shaft axis).
## Local +Y is u_Z x u_X.
func _make_link_transform(p1: Vector2, p2: Vector2, z: float) -> Transform3D:
	var d := p2 - p1
	var dir := d.normalized()
	var ux := Vector3(dir.x, dir.y, 0.0)
	var uz := Vector3(0.0, 0.0, 1.0)
	var uy := uz.cross(ux)
	var link_basis: Basis = Basis(ux, uy, uz)
	var origin: Vector3 = Vector3(p1.x, p1.y, z)
	return Transform3D(link_basis, origin)

## Advances collision-driving chain state every physics tick. Rendering is
## refreshed separately at 30 Hz; the physical lugs must never jump at 30 Hz.
func advance_physics(top_dist_delta: float, haul_dist_delta: float) -> void:
	current_top_dist = fposmod(current_top_dist + top_dist_delta, _top_loop_len)
	current_haul_dist = fposmod(current_haul_dist + haul_dist_delta, _haul_loop_len)
	_place_physical_lugs()


## Compatibility helper used by tests and standalone callers.
func update_chains(top_dist_delta: float, haul_dist_delta: float) -> void:
	advance_physics(top_dist_delta, haul_dist_delta)
	refresh_visuals()


func refresh_visuals() -> void:
	# 1. Update Top Overhead Chain Links & Lugs
	if is_instance_valid(_mm_top_links) and is_instance_valid(_mm_top_links.multimesh):
		var mm := _mm_top_links.multimesh
		var mm_lugs: MultiMesh = _mm_top_lugs.multimesh if is_instance_valid(_mm_top_lugs) else null
		var lug_spacing_links: int = 5

		# Precompute 2D pin positions and link bases once per link index
		for k in range(_top_links_per_strand):
			var s1: float = current_top_dist + float(k) * TOP_PITCH
			var s2: float = s1 + TOP_PITCH
			var p1 := sample_top_path(s1)
			var p2 := sample_top_path(s2)

			var d := (p2 - p1).normalized()
			var ux := Vector3(d.x, d.y, 0.0)
			var uz := Vector3(0.0, 0.0, 1.0)
			var uy := uz.cross(ux)
			var b := Basis(ux, uy, uz)

			# Replicate across all 4 parallel strands
			for strand_idx in range(TOP_STRANDS.size()):
				var z_pos: float = TOP_STRANDS[strand_idx]
				var inst_idx: int = strand_idx * _top_links_per_strand + k
				mm.set_instance_transform(inst_idx, Transform3D(b, Vector3(p1.x, p1.y, z_pos)))

			# If this link has a downward pusher lug (every 5th link = 1.0m)
			if mm_lugs and (k % lug_spacing_links == 0):
				var lug_k: int = int(float(k) / float(lug_spacing_links))
				if lug_k < _top_lugs_per_strand:
					for strand_idx in range(TOP_STRANDS.size()):
						var z_pos: float = TOP_STRANDS[strand_idx]
						var lug_inst_idx: int = strand_idx * _top_lugs_per_strand + lug_k
						mm_lugs.set_instance_transform(lug_inst_idx, Transform3D(b, Vector3(p1.x, p1.y, z_pos)))

	# 2. Update Haul-Out Plain Drag Chain Links
	if is_instance_valid(_mm_haul_links) and is_instance_valid(_mm_haul_links.multimesh):
		var mm_h := _mm_haul_links.multimesh
		for k in range(_haul_links_per_strand):
			var s1: float = current_haul_dist + float(k) * HAUL_PITCH
			var s2: float = s1 + HAUL_PITCH
			var p1 := sample_haul_path(s1)
			var p2 := sample_haul_path(s2)

			var d := (p2 - p1).normalized()
			var ux := Vector3(d.x, d.y, 0.0)
			var uz := Vector3(0.0, 0.0, 1.0)
			var uy := uz.cross(ux)
			var b := Basis(ux, uy, uz)

			# Replicate across all 5 haulout strands
			for strand_idx in range(HAUL_STRANDS.size()):
				var z_pos: float = HAUL_STRANDS[strand_idx]
				var inst_idx: int = strand_idx * _haul_links_per_strand + k
				mm_h.set_instance_transform(inst_idx, Transform3D(b, Vector3(p1.x, p1.y, z_pos)))

## Returns the exact 3D world transform for a specific lug on a specific strand.
func get_top_lug_transform(lug_k: int, strand_idx: int) -> Transform3D:
	var k: int = lug_k * 5
	var s1: float = current_top_dist + float(k) * TOP_PITCH
	var s2: float = s1 + TOP_PITCH
	var p1 := sample_top_path(s1)
	var p2 := sample_top_path(s2)
	var d := (p2 - p1).normalized()
	var ux := Vector3(d.x, d.y, 0.0)
	var uz := Vector3(0.0, 0.0, 1.0)
	var uy := uz.cross(ux)
	var b := Basis(ux, uy, uz)
	var z_pos: float = TOP_STRANDS[strand_idx]
	return Transform3D(b, Vector3(p1.x, p1.y, z_pos))

## Returns the exact 3D world transform for a specific link on a specific strand.
func get_top_link_transform(k: int, strand_idx: int) -> Transform3D:
	var s1: float = current_top_dist + float(k) * TOP_PITCH
	var s2: float = s1 + TOP_PITCH
	var p1 := sample_top_path(s1)
	var p2 := sample_top_path(s2)
	var d := (p2 - p1).normalized()
	var ux := Vector3(d.x, d.y, 0.0)
	var uz := Vector3(0.0, 0.0, 1.0)
	var uy := uz.cross(ux)
	var b := Basis(ux, uy, uz)
	var z_pos: float = TOP_STRANDS[strand_idx]
	return Transform3D(b, Vector3(p1.x, p1.y, z_pos))

