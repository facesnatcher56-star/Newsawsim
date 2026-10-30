extends Node3D

## waste_system.gd
## Slashers, vibrating pan conveyors and the big drum chipper by the east wall.
##
## The model (game/assets/models/waste, built by dev/blender/waste) is in mill coordinates, like
## this node. All the sawing waste comes here and is chopped short so it can turn corners:
##   - the slab slasher's chains carry kicked slabs sideways (-Z) over three saws; as a slab's
##     leading edge reaches the saw line it is cut into short pieces that ride on over the saws
##     together and fall off the chain head into the slab pan
##   - the edging slashers do the same for the edgings the picker belt's pickers sweep onto them,
##     and drop the pieces down chutes into the edging pans
##   - the pans shake on their springs; that walks the pieces along (a moving surface under them)
##     and each pan drops them off its end into the next, down to the collector and the chipper
##   - the chipper's feed roll pulls each piece into the drum and it is gone up the blow pipe; now
##     and then the throat chokes and the feed roll stalls and backs off before taking it again

const ChainLoop := preload("res://game/transport/chains/chain_loop.gd")

const SLAB_SL_X: Array[float] = [30.6, 32.7, 34.8]
const SLAB_SL_Z := Vector2(4.55, 3.15)
const SLAB_SL_Y := -0.45
const SLAB_SAW_X: Array[float] = [31.48, 32.70, 33.92]
const SLAB_SAW_Z := 3.95
const EDGE_Y := 0.30
const EDGE_NEAR_Z := Vector2(20.65, 19.85)
const EDGE_FAR_Z := Vector2(22.55, 24.45)
const EDGE_X: Array[float] = [46.9, 48.4, 49.9, 51.4, 52.4]
const EDGE_SAW_X: Array[float] = [47.75, 48.95, 50.15, 51.35]
const EDGE_NEAR_SAW_Z := 20.25
const EDGE_FAR_SAW_Z := 23.5
const SL_R := 0.08
const PAN_W := 1.4
const PAN_WALL := 0.15
## (name, start (x, z), end (x, z), floor y): pieces travel start -> end.
const PANS := [
	["Pan1", Vector2(29.6, 2.7), Vector2(54.4, 2.7), -0.62],
	["Pan2", Vector2(54.4, 2.0), Vector2(54.4, 11.45), -0.79],
	["Pan3", Vector2(46.4, 19.2), Vector2(54.4, 19.2), -0.62],
	["Pan4", Vector2(46.4, 25.3), Vector2(54.4, 25.3), -0.62],
	["Pan5", Vector2(54.4, 26.0), Vector2(54.4, 12.55), -0.79],
	["Pan6", Vector2(53.4, 12.0), Vector2(55.45, 12.0), -0.96],
]
const CHIP_Z := 12.0
const THROAT_X := 55.45
const DRUM_X := 56.75
const FEED_ROLL_R := 0.24
const LINK_PITCH := 0.06627
const LINK_SCENE := "res://game/assets/models/board_line/board_line_roller_link.glb"

@export var slasher_speed: float = 0.35
@export var pan_speed: float = 0.45
@export var feed_speed: float = 0.9
## Chance per piece that the chipper throat chokes for a moment.
@export var jam_chance: float = 0.04
@export var debug_log: bool = false

var _slashers: Array[Dictionary] = []
var _pans: Array[Dictionary] = []
var _chipping: Array[RigidBody3D] = []
var _jam_timer: float = 0.0
var _feed_travel: float = 0.0
var _spin: float = 0.0
var _time: float = 0.0
var _feed_roll: Node3D
var _drum: Node3D
var _dust: CPUParticles3D
var _counts := {"slabs": 0, "edgings": 0, "pieces": 0, "chipped": 0, "jams": 0}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_add_slasher("slab", SLAB_SL_X, SLAB_SL_Z, SLAB_SL_Y, SLAB_SAW_X, SLAB_SAW_Z, "WS_SlabArbor", "WS_SlabTail",
			"WS_SlabHead", false)
	_add_slasher("near", EDGE_X, EDGE_NEAR_Z, EDGE_Y, EDGE_SAW_X, EDGE_NEAR_SAW_Z, "WS_EdgeArborNear",
			"WS_EdgeNearTail", "WS_EdgeNearHead", true)
	_add_slasher("far", EDGE_X, EDGE_FAR_Z, EDGE_Y, EDGE_SAW_X, EDGE_FAR_SAW_Z, "WS_EdgeArborFar",
			"WS_EdgeFarTail", "WS_EdgeFarHead", true)
	for spec in PANS:
		_add_pan(spec)
	for s in [-1.0, 1.0]:
		_edge_chute(s)
	_build_chipper_bodies()
	_feed_roll = find_child("WS_FeedRoll", true, false) as Node3D
	_drum = find_child("WS_Drum", true, false) as Node3D
	_build_dust()
	_build_chains()


## The slab slasher takes another slab only when its chains are clear of the last one.
func slab_room() -> bool:
	var sl: Dictionary = _slashers[0]
	return sl["cutting"].is_empty() and _pieces_on(sl).is_empty()


func _physics_process(delta: float) -> void:
	_time += delta
	for sl in _slashers:
		_run_slasher(sl, delta)
	_shake_pans()
	_run_chipper(delta)
	_spin += delta * 35.0
	for sl in _slashers:
		if sl["arbor"]:
			(sl["arbor"] as Node3D).rotation.x = -_spin * signf(sl["dir"])
		sl["travel"] += slasher_speed * delta
		for n in ["tail", "head"]:
			if sl[n]:
				(sl[n] as Node3D).rotation.x = -sl["travel"] / SL_R * signf(sl["dir"])
		_lay_chain(sl)
	if _drum:
		_drum.rotation.z = -_spin * 0.5
	if _feed_roll:
		_feed_roll.rotation.z = -_feed_travel / FEED_ROLL_R


# --- Slashers -------------------------------------------------------------------------------------

func _add_slasher(key: String, xs: Array[float], zs: Vector2, y: float, saw_xs: Array[float], saw_z: float,
		arbor: String, tail: String, head: String, edgings: bool) -> void:
	var dir := signf(zs.y - zs.x)
	var body := StaticBody3D.new()
	body.name = "Slasher_" + key
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(xs.max() - xs.min() + 0.6, 0.06, absf(zs.y - zs.x))
	cs.shape = box
	cs.position = Vector3((xs.min() + xs.max()) * 0.5, y - 0.03, (zs.x + zs.y) * 0.5)
	body.add_child(cs)
	body.constant_linear_velocity = Vector3(0.0, 0.0, dir * slasher_speed)
	var loop = ChainLoop.from_path(PackedVector2Array([Vector2(dir * zs.x, y), Vector2(dir * zs.y, y)]), SL_R)
	_slashers.append({"key": key, "xs": xs, "zs": zs, "y": y, "dir": dir, "saw_xs": saw_xs, "saw_z": saw_z,
			"edgings": edgings, "cutting": [], "travel": 0.0, "loop": loop,
			"arbor": find_child(arbor, true, false), "tail": find_child(tail, true, false),
			"head": find_child(head, true, false)})


## Unfrozen pieces of the right kind lying on a slasher's chains.
func _pieces_on(sl: Dictionary) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var zs: Vector2 = sl["zs"]
	var xs: Array[float] = sl["xs"]
	for node in get_tree().get_nodes_in_group("cut_slabs"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.is_in_group("waste_piece"):
			continue
		if sl["edgings"] != b.is_in_group("edgings"):
			continue
		var p := b.global_position
		if p.x > xs.min() - 3.0 and p.x < xs.max() + 3.0 and p.z > minf(zs.x, zs.y) - 0.1 \
				and p.z < maxf(zs.x, zs.y) + 0.1 and absf(p.y - sl["y"]) < 0.3:
			out.append(b)
	return out


func _run_slasher(sl: Dictionary, delta: float) -> void:
	var dir: float = sl["dir"]
	var saw_z: float = sl["saw_z"]
	for b in _pieces_on(sl):
		var lead := b.global_position.z + dir * _half_w(b)
		if (lead - saw_z) * dir > -0.02:
			_start_cut(sl, b)
	# Pieces being cut ride across the saws with the chain, then go back to physics.
	for c in sl["cutting"].duplicate():
		var pieces: Array = c["pieces"]
		var trail := INF
		for p: RigidBody3D in pieces:
			if is_instance_valid(p):
				p.global_position.z += dir * slasher_speed * delta
				trail = p.global_position.z - dir * c["half_w"]
		if trail == INF or (trail - saw_z) * dir > 0.03:
			for p: RigidBody3D in pieces:
				if is_instance_valid(p):
					p.freeze = false
					p.linear_velocity = Vector3(0.0, 0.0, dir * slasher_speed)
					p.angular_velocity = Vector3.ZERO
			sl["cutting"].erase(c)


## Cut a slab or edging at the saws into short pieces lying exactly where it was.
func _start_cut(sl: Dictionary, b: RigidBody3D) -> void:
	var half := _half_len(b)
	var xform := b.global_transform
	var along := xform.basis.x.normalized()
	var cx := b.global_position.x
	var cuts: Array[float] = []
	for x in sl["saw_xs"]:
		if x > cx - half + 0.15 and x < cx + half - 0.15:
			cuts.append(x)
	var edges: Array[float] = [cx - half]
	edges.append_array(cuts)
	edges.append(cx + half)
	var scene := load(b.scene_file_path) as PackedScene
	var pieces: Array = []
	for i in edges.size() - 1:
		var length := edges[i + 1] - edges[i] - (0.003 if i > 0 else 0.0)
		var mid := (edges[i] + edges[i + 1]) * 0.5
		var p := scene.instantiate() as RigidBody3D
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		p.freeze = true
		b.get_parent().add_child(p)
		if sl["edgings"]:
			p.configure_dimensions(length, b.board_thickness, b.board_width)
			p.nominal_size = "edging"
			p.add_to_group("cut_slabs")
			p.add_to_group("edgings")
		else:
			p.configure_length(length)
		p.add_to_group("waste_piece")
		var t := xform
		t.origin = xform.origin + along * ((mid - cx) * signf(along.x if absf(along.x) > 0.01 else 1.0))
		p.global_transform = t
		pieces.append(p)
		_counts["pieces"] += 1
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			(pieces[i] as RigidBody3D).add_collision_exception_with(pieces[j])
	sl["cutting"].append({"pieces": pieces, "half_w": _half_w(b)})
	_counts["edgings" if sl["edgings"] else "slabs"] += 1
	if debug_log:
		print("[%s] %.1f s %s slasher cut a %.1f m %s into %d" % [name, Time.get_ticks_msec() / 1000.0, sl["key"],
				half * 2.0, "edging" if sl["edgings"] else "slab", pieces.size()])
	b.queue_free()


# --- Pans --------------------------------------------------------------------------------------------

func _add_pan(spec: Array) -> void:
	var a: Vector2 = spec[1]
	var b: Vector2 = spec[2]
	var fy: float = spec[3]
	var d := (b - a).normalized()
	var dir := Vector3(d.x, 0.0, d.y)
	var across := Vector3(-d.y, 0.0, d.x)
	var length := a.distance_to(b)
	var mid := Vector3((a.x + b.x) * 0.5, fy, (a.y + b.y) * 0.5)
	var body := StaticBody3D.new()
	body.name = "Pan_" + str(spec[0])
	add_child(body)
	# Floor, side walls and the tail plate.
	var parts := [
		[Vector3.ZERO + Vector3(0, -0.03, 0), _sz(d, length, 0.06, PAN_W)],
		[across * (PAN_W * 0.5) + Vector3(0, PAN_WALL * 0.5, 0), _sz(d, length, PAN_WALL, 0.012)],
		[-across * (PAN_W * 0.5) + Vector3(0, PAN_WALL * 0.5, 0), _sz(d, length, PAN_WALL, 0.012)],
		[-dir * (length * 0.5) + Vector3(0, PAN_WALL * 0.5, 0), _sz(d, 0.012, PAN_WALL, PAN_W)],
	]
	for p in parts:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = p[1]
		cs.shape = box
		cs.position = mid + p[0]
		body.add_child(cs)
	body.constant_linear_velocity = dir * pan_speed
	var phys := PhysicsMaterial.new()
	phys.friction = 0.6
	body.physics_material_override = phys
	var mesh := find_child("WS_" + str(spec[0]), true, false) as Node3D
	_pans.append({"body": body, "mesh": mesh, "home": mesh.position if mesh else Vector3.ZERO, "dir": dir,
			"phase": _rng.randf() * TAU})


## Box size for a pan part: `along` metres in the pan's direction, `h` high, `w` across.
func _sz(d: Vector2, along: float, h: float, w: float) -> Vector3:
	return Vector3(w, h, along) if absf(d.y) > 0.5 else Vector3(along, h, w)


## The pans shake forward-and-up on their springs (shown on the pan meshes; the moving surface
## under the pieces does the conveying).
func _shake_pans() -> void:
	for pan in _pans:
		var m := pan["mesh"] as Node3D
		if m == null:
			continue
		var s := sin(_time * TAU * 11.0 + pan["phase"])
		var d: Vector3 = pan["dir"]
		# The mesh sits under a node with the model's y offset; its axes are the mill's.
		m.position = pan["home"] + d * 0.004 * s + Vector3.UP * 0.003 * s


# --- Chutes and chipper ----------------------------------------------------------------------------

## Chute from an edging slasher's head over the deck edge into its edging pan.
func _edge_chute(side: float) -> void:
	var z1 := EDGE_NEAR_Z.y if side < 0.0 else EDGE_FAR_Z.y
	var pan_z := 19.2 if side < 0.0 else 25.3
	var a := Vector2(z1 + side * 0.02, EDGE_Y - 0.02)
	var b := Vector2(pan_z - side * 0.45, -0.40)
	var dv := (b - a).normalized()
	var t := Vector3(0.0, dv.y, dv.x)
	var n := Vector3(0.0, t.z, -t.y)
	if n.y < 0.0:
		n = -n
	var body := StaticBody3D.new()
	body.name = "EdgingChute%s" % ("Near" if side < 0.0 else "Far")
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(EDGE_X.max() - EDGE_X.min() + 0.4, 0.02, a.distance_to(b))
	cs.shape = box
	cs.transform = Transform3D(Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n)),
			Vector3((EDGE_X.min() + EDGE_X.max()) * 0.5, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5) - n * 0.01)
	body.add_child(cs)


func _build_chipper_bodies() -> void:
	var body := StaticBody3D.new()
	body.name = "ChipperThroat"
	add_child(body)
	# Throat floor a few mm under the collector's, so nothing catches on the seam.
	for p in [[Vector3((THROAT_X + DRUM_X) * 0.5, -1.0, CHIP_Z), Vector3(DRUM_X - THROAT_X, 0.06, 1.2)],
			[Vector3((THROAT_X + DRUM_X) * 0.5, -0.6, CHIP_Z - 0.62), Vector3(DRUM_X - THROAT_X, 0.8, 0.04)],
			[Vector3((THROAT_X + DRUM_X) * 0.5, -0.6, CHIP_Z + 0.62), Vector3(DRUM_X - THROAT_X, 0.8, 0.04)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = p[1]
		cs.shape = box
		cs.position = p[0]
		body.add_child(cs)


func _run_chipper(delta: float) -> void:
	# Take in anything that reaches the throat.
	for node in get_tree().get_nodes_in_group("cut_slabs"):
		var b := node as RigidBody3D
		if b == null or b.freeze or _chipping.has(b):
			continue
		var p := b.global_position
		# The feed roll reaches out over the mouth and grips whatever arrives under it.
		if p.x + _half_extent_x(b) > THROAT_X - 0.1 and absf(p.z - CHIP_Z) < 0.65 and p.y < -0.6 and p.x < DRUM_X:
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.freeze = true
			_chipping.append(b)
			if _rng.randf() < jam_chance:
				_jam_timer = _rng.randf_range(1.2, 2.5)
				_counts["jams"] += 1
				if debug_log:
					print("[%s] %.1f s chipper throat choked" % [name, Time.get_ticks_msec() / 1000.0])
	var v := feed_speed
	if _jam_timer > 0.0:
		# Choked: the feed roll stalls, then backs off a little before taking it again.
		_jam_timer -= delta
		v = 0.0 if _jam_timer > 0.6 else -0.35
	_feed_travel += v * delta
	for b in _chipping.duplicate():
		if not is_instance_valid(b):
			_chipping.erase(b)
			continue
		b.global_position.x += v * delta
		if b.global_position.x - _half_extent_x(b) > DRUM_X - 0.5:
			_chipping.erase(b)
			b.queue_free()
			_counts["chipped"] += 1
	if _dust:
		_dust.emitting = v > 0.0 and not _chipping.is_empty()


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "ChipDust"
	_dust.position = Vector3(THROAT_X - 0.05, -0.75, CHIP_Z)
	_dust.emitting = false
	_dust.amount = 50
	_dust.lifetime = 0.9
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.03, 0.15, 0.5)
	_dust.direction = Vector3(-1.0, 0.4, 0.0)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 0.6
	_dust.initial_velocity_max = 1.6
	_dust.gravity = Vector3(0.0, -6.0, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.018)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.38)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	_dust.mesh = quad
	add_child(_dust)


# --- Slasher chains ---------------------------------------------------------------------------------

func _build_chains() -> void:
	var scene := load(LINK_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var mesh := (src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	src.free()
	for sl in _slashers:
		var loop = sl["loop"]
		var per := int(loop.length / LINK_PITCH)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = per * (sl["xs"] as Array).size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "SlasherChain_" + str(sl["key"])
		mmi.multimesh = mm
		add_child(mmi)
		var dir: float = sl["dir"]
		sl["mm"] = mm
		sl["per"] = per
		sl["shown"] = -1
		sl["baked"] = loop.bake(per, sl["xs"], func(smp: Array, x: float) -> Transform3D: return _frame(smp, x, dir), 8)


## A link on a slasher loop: loop u runs along dir * z.
func _frame(smp: Array, x: float, dir: float) -> Transform3D:
	var p: Vector2 = smp[0]
	var t2: Vector2 = smp[1]
	var t := Vector3(0.0, t2.y, t2.x * dir)
	# Across chosen so the link's +Y faces out of the loop whichever way the chain runs.
	var across := Vector3.LEFT if dir > 0.0 else Vector3.RIGHT
	return Transform3D(Basis(across, across.cross(t), -t), Vector3(x, p.y, p.x * dir))


func _lay_chain(sl: Dictionary) -> void:
	if not sl.has("mm"):
		return
	var k: int = sl["loop"].phase_index(sl["travel"], sl["per"], 8)
	if k != sl["shown"]:
		sl["shown"] = k
		(sl["mm"] as MultiMesh).buffer = sl["baked"][k]


# --- Helpers ------------------------------------------------------------------------------------------

func _half_len(b: Node) -> float:
	return float(b.get("product_length")) * 0.5 if b.get("product_length") != null else 2.44


func _half_w(b: Node) -> float:
	return float(b.get("board_width")) * 0.5 if b.get("board_width") != null else 0.12


## Half the piece's extent along X (it lies along X or along Z).
func _half_extent_x(b: Node3D) -> float:
	return absf(b.global_basis.x.normalized().x) * _half_len(b) + absf(b.global_basis.z.normalized().x) * _half_w(b)


## One line for debug HUDs.
func status_text() -> String:
	return "slabs %d, edgings %d -> %d pieces, chipped %d%s" % [_counts["slabs"], _counts["edgings"], _counts["pieces"],
			_counts["chipped"], ", throat choked" if _jam_timer > 0.0 else ""]
