extends Node3D

## unscrambler_line.gd
## Feed chains, pocket, unscrambler and take-away chains: the first part of the 3338 board line.
##
## The model (game/assets/models/board_line, built by dev/blender/board_line) is in mill
## coordinates, like this node. Everything here is moved by its chains:
##   - the feed chains carry boards from the headrig outfeed's board kickers and the gang's lift
##     rolls (+Z) and drop them off their sloped head down the pocket's back plate
##   - in the pocket the boards pile against the unscrambler; the lugs come round the foot
##     sprocket under them and each lug takes the board lying across it up the 40 deg incline;
##     a board lying on another one has nothing to hold it and slides back (the chains are
##     slippery under a board at that angle), so the boards go up one to a lug
##   - over the 6 ft radius they come onto the faster take-away chains, which space them out
## Chain links, carrier bars and lugs are instanced along their loops and the lugs are physical
## bodies moving with the chain. The feed chains stop while the pocket is full.

const ChainLoop := preload("res://game/transport/chains/chain_loop.gd")

const FEED_X: Array[float] = [38.5, 39.5, 40.5, 41.5, 42.5]
const FEED_PATH := [Vector2(6.25, -0.2), Vector2(9.3064, -0.2), Vector2(9.5604, -0.3524)]
const FEED_R := 0.09
const POCKET_TOP := Vector2(9.5807, -0.4004)
const POCKET_LOW := Vector2(10.2668, -1.0466)
## Foot sprocket centre (z, y): the chain wrapped round it closes the bottom of the pocket.
const UNS_FOOT := Vector2(10.4466, -0.9852)
## Tip of the pocket's comb fingers (z, y), just off the chain wrap.
const FINGER_TIP := Vector2(10.3094, -1.0321)
const POCKET_X := Vector2(37.95, 43.8)
const UNS_PATH := [Vector2(10.365, -0.888), Vector2(12.246, 0.69), Vector2(12.329, 0.756), Vector2(12.416, 0.817),
	Vector2(12.507, 0.873), Vector2(12.6, 0.923), Vector2(12.697, 0.968), Vector2(12.796, 1.008),
	Vector2(12.897, 1.041), Vector2(12.999, 1.069), Vector2(13.104, 1.09), Vector2(13.209, 1.106),
	Vector2(13.315, 1.115), Vector2(13.421, 1.118), Vector2(13.472, 1.118)]
const UNS_R := 0.127
## Chain pairs (x of each chain) and the lugs on each carrier bar.
const UNS_PAIRS := [Vector2(42.865, 42.3062), Vector2(41.9252, 41.3664), Vector2(40.9854, 40.3250),
	Vector2(39.9440, 39.2836), Vector2(38.9026, 38.2422)]
const LUG_INSET := 0.05
const LUG_TOP := 0.05
const CARRIER_PITCH := 0.762
const TAKE_X: Array[float] = [42.973, 42.198, 41.258, 40.217, 39.176, 38.134]
## A few millimetres under the unscrambler's top run so boards step down onto it.
const TAKE_PATH := [Vector2(13.6371, 1.114), Vector2(14.0308, 1.114)]
const TAKE_R := 0.0762
## Double reject: photo eye station along the straight incline, the arm shaft over it, arm swing.
const REJECT_S := 1.9
const REJECT_PIVOT := Vector2(11.2098, 1.0611)
const REJECT_REST_DEG := -50.0
const REJECT_FIRE_DEG := 50.0
## 81X roller chain, modelled with its plate tops at the link origin (the chain-top line).
const LINK_PITCH := 0.06627
const CHAIN_SCENE := "res://game/assets/models/board_line/board_line_roller_link.glb"
const CARRIER_SCENE := "res://game/assets/models/board_line/board_line_carrier.glb"

@export var feed_speed: float = 0.5
## 0.4 m/s with a carrier every 30 in is about 31 lugs a minute (the drive allows 45).
@export var unscrambler_speed: float = 0.4
@export var takeaway_speed: float = 0.9
## Friction between a board and the unscrambler chains: low enough that a board with no lug
## under it slides back down the incline.
@export var chain_friction: float = 0.22
## Boards in the pocket at which the feed chains stop.
@export var pocket_full: int = 8
## Reject arm stroke time (down-slope sweep and back) in seconds.
@export var reject_stroke: float = 0.7
## Prints feed stops and boards over the top (for demos).
@export var debug_log: bool = false

var _feed_loop
var _uns_loop
var _take_loop
var _feed_travel: float = 0.0
var _uns_travel: float = 0.0
var _take_travel: float = 0.0
var _feed_on: bool = true
## Set by the lug loader while it is full: the unscrambler and take-away stop.
var hold: bool = false

var _feed_surfaces: Array[StaticBody3D] = []
var _feed_dirs: Array[Vector3] = []
var _uns_surfaces: Array[StaticBody3D] = []
var _uns_dirs: Array[Vector3] = []
var _take_surface: StaticBody3D
var _lugs: Array[AnimatableBody3D] = []
var _links := {}
var _carriers: MultiMesh
var _shafts := {}
var _over_top: int = 0
var _seen_top := {}
var _reject: Node3D
var _reject_t: float = -1.0
var _reject_board: RigidBody3D = null
var _rejected: int = 0


func _ready() -> void:
	_feed_loop = ChainLoop.from_path(PackedVector2Array(FEED_PATH), FEED_R)
	_uns_loop = ChainLoop.from_path(PackedVector2Array(UNS_PATH), UNS_R)
	_take_loop = ChainLoop.from_path(PackedVector2Array(TAKE_PATH), TAKE_R)
	for n in ["BL_FeedTail", "BL_FeedHead", "BL_UnsFoot", "BL_UnsHead", "BL_TakeTail", "BL_TakeHead"]:
		_shafts[n] = find_child(n, true, false)
	_reject = find_child("BL_Reject", true, false) as Node3D
	if _reject:
		_reject.rotation.x = deg_to_rad(REJECT_REST_DEG)
	_build_bodies()
	_build_lugs()
	_build_chains()


## Room for another board on the feed chains where the kickers and the gang put them down.
func has_room() -> bool:
	return _feed_on and _boards_in(38.0, 44.0, 6.2, 7.2, -0.6, 0.4).is_empty()


func _physics_process(delta: float) -> void:
	var pocket := _boards_in(38.0, 44.0, 9.5, 10.6, -1.3, -0.3).size()
	var was := _feed_on
	_feed_on = pocket < pocket_full
	if debug_log and was != _feed_on:
		print("[%s] %.1f s feed chains %s (%d in the pocket)" % [name, Time.get_ticks_msec() / 1000.0,
				"on" if _feed_on else "held, pocket full", pocket])
	var fv := feed_speed if _feed_on else 0.0
	for i in _feed_surfaces.size():
		_feed_surfaces[i].constant_linear_velocity = _feed_dirs[i] * fv
	_feed_travel += fv * delta
	# The lug loader holds the unscrambler and take-away while it is full.
	var uv := 0.0 if hold else unscrambler_speed
	var tv := 0.0 if hold else takeaway_speed
	for i in _uns_surfaces.size():
		_uns_surfaces[i].constant_linear_velocity = _uns_dirs[i] * uv
	if _take_surface:
		_take_surface.constant_linear_velocity = Vector3(0.0, 0.0, tv)
	_uns_travel += uv * delta
	_take_travel += tv * delta
	_move_lugs()
	_run_reject(delta)
	_update_chains()
	_spin_shafts()
	if debug_log:
		_count_over_top()


func _boards_in(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.is_in_group("cut_slabs"):
			continue
		var p := b.global_position
		if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1 and p.y > y0 and p.y < y1:
			out.append(b)
	return out


# --- Physics surfaces --------------------------------------------------------------------------

func _build_bodies() -> void:
	var slick := PhysicsMaterial.new()
	slick.friction = chain_friction
	var steel := PhysicsMaterial.new()
	steel.friction = 0.35
	# Feed chains: one moving surface per run of the path.
	for i in FEED_PATH.size() - 1:
		var body := _surface("FeedRun%d" % i, FEED_PATH[i], FEED_PATH[i + 1], FEED_X[0] - 0.1, FEED_X[-1] + 0.1, null,
				0.004 * i)
		_feed_surfaces.append(body)
		_feed_dirs.append(_dir3(FEED_PATH[i], FEED_PATH[i + 1]))
	# Pocket back plate and end cheeks (fixed), wider than the longest board.
	var xs := _pair_xs()
	var xa := POCKET_X.x
	var xb := POCKET_X.y
	_surface("PocketPlate", POCKET_TOP, POCKET_LOW, xa, xb, steel)
	for x in [xa - 0.02, xb + 0.02]:
		var cheek := StaticBody3D.new()
		cheek.name = "PocketCheek"
		add_child(cheek)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.03, 1.6, 1.2)
		cs.shape = box
		cs.position = Vector3(x, -0.6, 10.1)
		cheek.add_child(cs)
	# The chains wrapped round the foot sprocket, and the back plate's comb fingers reaching in
	# to them between the chain pairs: no board can drop through, and the lugs come round in
	# the slots under whatever lies on the fingers.
	var foot := StaticBody3D.new()
	foot.name = "FootWrap"
	foot.physics_material_override = slick
	add_child(foot)
	var wcs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = UNS_R
	cyl.height = xs.max() - xs.min() + 0.1
	wcs.shape = cyl
	wcs.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3((xs.min() + xs.max()) * 0.5, UNS_FOOT.y, UNS_FOOT.x))
	foot.add_child(wcs)
	var x := POCKET_X.x
	var slots: Array = UNS_PAIRS.duplicate()
	slots.sort_custom(func(p, q): return minf(p.x, p.y) < minf(q.x, q.y))
	var spans: Array[Vector2] = []
	for p: Vector2 in slots:
		spans.append(Vector2(x, minf(p.x, p.y) - 0.04))
		x = maxf(p.x, p.y) + 0.04
	spans.append(Vector2(x, POCKET_X.y))
	for i in spans.size():
		_surface("Finger%d" % i, POCKET_LOW, FINGER_TIP, spans[i].x, spans[i].y, steel)
	# Unscrambler chains: a moving surface per segment of the carrying run.
	for i in UNS_PATH.size() - 1:
		_uns_surfaces.append(_surface("UnsRun%d" % i, UNS_PATH[i], UNS_PATH[i + 1], xs.min() - 0.05, xs.max() + 0.05,
				slick, 0.002 * i))
		_uns_dirs.append(_dir3(UNS_PATH[i], UNS_PATH[i + 1]))
	# Dead plate from the top of the unscrambler across to the take-away, between their heights.
	var top: Vector2 = UNS_PATH[-1]
	var take0: Vector2 = TAKE_PATH[0]
	_surface("TopDeadPlate", Vector2(top.x, 1.116), Vector2(take0.x, 1.116), TAKE_X[-1] - 0.15, TAKE_X[0] + 0.15, null)
	# Take-away chains.
	_take_surface = _surface("TakeAway", TAKE_PATH[0], TAKE_PATH[1], TAKE_X[-1] - 0.05, TAKE_X[0] + 0.05, null)


## A static surface whose top runs from a to b ((z, y) points) across x0..x1, `drop` below the
## line: each run after a bend sits a few millimetres low, so a board's leading edge comes off
## the end of one run onto the next instead of jamming on the corner where they meet.
func _surface(body_name: String, a: Vector2, b: Vector2, x0: float, x1: float, mat: PhysicsMaterial,
		drop: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	if mat:
		body.physics_material_override = mat
	add_child(body)
	var t := _dir3(a, b)
	var up := Vector3(0.0, t.z, -t.y)
	var run := a.distance_to(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Exactly the segment's length: any overlap leaves a lip where a run bends down that a
	# board's square edge catches on.
	box.size = Vector3(x1 - x0, 0.06, run)
	cs.shape = box
	var mid := Vector3((x0 + x1) * 0.5, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5) - up * (0.03 + drop)
	cs.transform = Transform3D(Basis(Vector3.RIGHT, up, t), mid)
	body.add_child(cs)
	return body


func _dir3(a: Vector2, b: Vector2) -> Vector3:
	var d := (b - a).normalized()
	return Vector3(0.0, d.y, d.x)


func _pair_xs() -> Array[float]:
	var xs: Array[float] = []
	for p: Vector2 in UNS_PAIRS:
		xs.append(p.x)
		xs.append(p.y)
	return xs


# --- Lugs ---------------------------------------------------------------------------------------

func _build_lugs() -> void:
	var n := int(_uns_loop.length / CARRIER_PITCH)
	var xm := _lug_mid()
	for i in n:
		var body := AnimatableBody3D.new()
		body.name = "Lugs%d" % i
		body.sync_to_physics = false
		add_child(body)
		for p: Vector2 in UNS_PAIRS:
			for x in [maxf(p.x, p.y) - LUG_INSET, minf(p.x, p.y) + LUG_INSET]:
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(0.05, LUG_TOP + 0.02, 0.025)
				cs.shape = box
				# Body basis is (across = -X, out, -travel), so world x maps to local -x.
				cs.position = Vector3(-(x - xm), (LUG_TOP - 0.02) * 0.5, 0.0)
				body.add_child(cs)
		_lugs.append(body)
	_move_lugs()


func _lug_mid() -> float:
	var xs := _pair_xs()
	return (xs.min() + xs.max()) * 0.5


func _move_lugs() -> void:
	var xm := _lug_mid()
	for i in _lugs.size():
		var s: float = i * _uns_loop.length / _lugs.size() + _uns_travel
		_lugs[i].global_transform = _frame(_uns_loop.sample(s), xm)
	if _carriers:
		var k := 0
		for i in _lugs.size():
			var s: float = i * _uns_loop.length / _lugs.size() + _uns_travel
			var smp: Array = _uns_loop.sample(s)
			for p: Vector2 in UNS_PAIRS:
				_carriers.set_instance_transform(k, _frame(smp, (p.x + p.y) * 0.5))
				k += 1


## The chain frame at a loop sample, at world x: (across, out of the loop, -travel).
func _frame(smp: Array, x: float) -> Transform3D:
	var p: Vector2 = smp[0]
	var t2: Vector2 = smp[1]
	var t := Vector3(0.0, t2.y, t2.x)
	var across := Vector3.BACK.cross(Vector3.UP)
	var out := across.cross(t)
	return Transform3D(Basis(across, out, -t), Vector3(x, p.y, p.x))


# --- Double reject ------------------------------------------------------------------------------

## The photo eye looks across the incline just over a lug's height: a board that high off the
## chains is riding on another one. The arms then sweep down-slope over the lug tips; their
## pads catch the upper board and knock it back over the lug, and it slides down to the pocket.
func _run_reject(delta: float) -> void:
	var foot: Vector2 = UNS_PATH[0]
	var up_slope: Vector2 = (UNS_PATH[1] - UNS_PATH[0]).normalized()
	var n := Vector2(-up_slope.y, up_slope.x)
	if _reject_t < 0.0:
		for b in _boards_in(37.5, 44.5, 10.5, 12.4, -0.9, 1.0):
			var rel := Vector2(b.global_position.z, b.global_position.y) - foot
			var s := rel.dot(up_slope)
			var off := rel.dot(n)
			# Centre of a board lying on another: about one and a half thicknesses off the chains.
			if absf(s - REJECT_S) < 0.12 and off > 0.045 and off < 0.12:
				_reject_t = 0.0
				_reject_board = b
				_rejected += 1
				if debug_log:
					print("[%s] %.1f s double on a lug, reject %d" % [name, Time.get_ticks_msec() / 1000.0, _rejected])
				break
		return
	_reject_t += delta / reject_stroke
	var p := minf(_reject_t, 1.0)
	# Out and back: the sweep down-slope takes the first half of the stroke.
	var swing := sin(PI * p)
	if _reject:
		_reject.rotation.x = deg_to_rad(lerpf(REJECT_REST_DEG, REJECT_FIRE_DEG, swing))
	# The pads reach the board as the arm passes straight down over it.
	if _reject_board and p >= 0.25:
		if is_instance_valid(_reject_board):
			var push := Vector3(0.0, -up_slope.y, -up_slope.x) * 1.3 + Vector3(0.0, n.y, n.x) * 0.25
			_reject_board.linear_velocity = push
			_reject_board.angular_velocity = Vector3.ZERO
		_reject_board = null
	if _reject_t >= 1.0:
		_reject_t = -1.0
		if _reject:
			_reject.rotation.x = deg_to_rad(REJECT_REST_DEG)


# --- Chains and shafts --------------------------------------------------------------------------

func _build_chains() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene:
		var src := scene.instantiate()
		var link := src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_links["feed"] = _chain_set(link.mesh, _feed_loop, FEED_X, "FeedChains")
		_links["uns"] = _chain_set(link.mesh, _uns_loop, _pair_xs(), "UnscramblerChains")
		_links["take"] = _chain_set(link.mesh, _take_loop, TAKE_X, "TakeAwayChains")
		src.free()
	var cscene := load(CARRIER_SCENE) as PackedScene
	if cscene:
		var src := cscene.instantiate()
		var mi: MeshInstance3D = null
		for c in src.find_children("*", "MeshInstance3D", true, false):
			mi = c as MeshInstance3D
			break
		if mi:
			_carriers = MultiMesh.new()
			_carriers.transform_format = MultiMesh.TRANSFORM_3D
			_carriers.mesh = mi.mesh
			_carriers.instance_count = _lugs.size() * UNS_PAIRS.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "CarrierBars"
			mmi.multimesh = _carriers
			add_child(mmi)
		src.free()
	_update_chains()
	_move_lugs()


## A set of strands of chain on one loop, with its link positions baked for animation.
func _chain_set(mesh: Mesh, loop, xs: Array, node_name: String) -> Dictionary:
	var per := int(loop.length / LINK_PITCH)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = per * xs.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return {"mm": mm, "loop": loop, "per": per, "baked": loop.bake(per, xs, _frame, 8), "shown": -1}


func _update_chains() -> void:
	if _links.is_empty():
		return
	_lay(_links["feed"], _feed_travel)
	_lay(_links["uns"], _uns_travel)
	_lay(_links["take"], _take_travel)


func _lay(chain: Dictionary, travel: float) -> void:
	var k: int = chain["loop"].phase_index(travel, chain["per"], 8)
	if k != chain["shown"]:
		chain["shown"] = k
		(chain["mm"] as MultiMesh).buffer = chain["baked"][k]


func _spin_shafts() -> void:
	for pair in [["BL_FeedTail", _feed_travel, FEED_R], ["BL_FeedHead", _feed_travel, FEED_R],
			["BL_UnsFoot", _uns_travel, UNS_R], ["BL_UnsHead", _uns_travel, UNS_R],
			["BL_TakeTail", _take_travel, TAKE_R], ["BL_TakeHead", _take_travel, TAKE_R]]:
		var n := _shafts.get(pair[0]) as Node3D
		if n:
			n.rotation.x = pair[1] / pair[2]


func _count_over_top() -> void:
	for b in _boards_in(37.5, 44.5, 13.45, 14.2, 0.9, 1.6):
		if not _seen_top.has(b.get_instance_id()):
			_seen_top[b.get_instance_id()] = true
			_over_top += 1
			print("[%s] %.1f s board %d over the top" % [name, Time.get_ticks_msec() / 1000.0, _over_top])


## One line for debug HUDs.
func status_text() -> String:
	return "%sfeed %s, pocket %d, over the top %d, doubles rejected %d" % ["HELD by lug loader, " if hold else "",
			"on" if _feed_on else "held",
			_boards_in(38.0, 44.0, 9.5, 10.6, -1.3, -0.3).size(), _over_top, _rejected]
