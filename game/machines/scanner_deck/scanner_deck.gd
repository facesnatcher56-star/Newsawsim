extends Node3D

## scanner_deck.gd
## Raised deck of the 3338 board line: lug loader, scanner lug chains, zero rollers and scanner.
##
## The model (game/assets/models/board_line/board_deck_*, built by dev/blender/board_line/bd_build)
## is in mill coordinates, like this node. Boards come off the unscrambler's take-away onto the lug
## loader, which runs as two interleaved chain sections overlapping across the halfway stops (the
## downstream one faster):
##   - the halfway stops hold the queue; the board against them sits over the flipper D's and is
##     now and then rolled over its long edge by a quarter turn of the D shaft
##   - when the end section is clear the halfway stops drop; the front board crosses onto the fast
##     section and pulls away from the queue, and the stops pop up again in the gap
##   - the end stops hold that board until the gap between two scanner lugs comes round, then let
##     it go over the dead plate onto the scanner chains, so there is one board to a lug space
##   - on the scanner chains, upstream of the scanner, pop-up rollers between the chains lift each
##     board a little and drive it endwise against the zero line fence
## While the lug loader's queue is full the unscrambler and its take-away are held. A board at the
## scanner chain head waits there until the edger line's positioners are ready for it.

const ChainLoop := preload("res://game/transport/chains/chain_loop.gd")

const LUG_X: Array[float] = [43.1698, 42.5094, 42.0395, 41.3791, 40.7187, 39.8805, 39.3979, 38.2422]
const LUG_B_OFFSET := -0.07
const LUG_A_Z := Vector2(14.1832, 14.996)
const LUG_B_Z := Vector2(14.6912, 15.6564)
const LUG_R := 0.0889
const SCAN_X: Array[float] = [43.2714, 42.611, 41.9506, 41.2902, 40.6298, 39.9694, 39.309, 38.6486, 37.9882]
const SCAN_Z := Vector2(15.8342, 20.4951)
const SCAN_R := 0.1016
const SCAN_LUG_PITCH := 0.6604
const SCAN_LUG_H := 0.0635
## Chain tops step down a few millimetres at each hand-off: take-away 1.114, dead plate 1.111,
## lug loader 1.108, dead plate 1.1045, scanner chains 1.101.
const CHAIN_Y := 1.108
const SCAN_Y := 1.101
const DEAD_IN_Y := 1.111
const DEAD_OUT_Y := 1.1045
const TAKE_END_Z := 14.0308
const STOP_HALF_Z := 14.8436
const STOP_END_Z := 15.5294
const STOP_UP := 0.0635
const STOP_DROP := 0.0889
const FLIP_Z := 14.7928
const ZERO_Z := 16.6216
const ZERO_X: Array[float] = [38.3184, 38.9788, 39.6392, 40.2996, 40.96, 41.6204, 42.2808, 42.9412]
const ZERO_TOP := 1.1239
const ZERO_LIFT := 0.03
const FENCE_X := 43.65
const SCANNER_Z := 18.5266
const DECK_X := Vector2(36.3, 45.0)
const DECK_Z := Vector2(13.853, 22.6)
const DECK_Y := 0.0233
## 81X roller chain, modelled with its plate tops at the link origin (the chain-top line).
const LINK_PITCH := 0.06627
const CHAIN_SCENE := "res://game/assets/models/board_line/board_line_roller_link.glb"
const LUG_SCENE := "res://game/assets/models/board_line/board_deck_lug.glb"

@export var loader_slow_speed: float = 0.45
@export var loader_fast_speed: float = 1.0
@export var scanner_speed: float = 0.6
@export var zero_roll_speed: float = 0.8
@export var stop_time: float = 0.12
@export var flip_time: float = 0.8
## Chance that the operator rolls the board at the halfway stops over before it goes on.
@export_range(0.0, 1.0) var flip_chance: float = 0.25
## Boards queued on the lug loader at which the unscrambler is held.
@export var queue_full: int = 4
@export_group("Links")
@export var unscrambler_path: NodePath
## The positioners and lineal infeed (can_take()).
@export var edger_path: NodePath
@export var debug_log: bool = false

var _unscrambler: Node
var _edger: Node
var _loop_a
var _loop_b
var _loop_scan
var _travel_a: float = 0.0
var _travel_b: float = 0.0
var _travel_scan: float = 0.0
var _scan_v: float = 0.0
var _surf_a: StaticBody3D
var _surf_b: StaticBody3D
var _surf_scan: StaticBody3D
var _stops := {}
var _flipper: Node3D
var _flip_board: RigidBody3D = null
var _flip_t: float = -1.0
var _flip_start := Transform3D()
var _decided := {}
var _zero_rolls: Array[AnimatableBody3D] = []
var _zero_meshes: Array[Node3D] = []
var _zero_lift: float = 0.0
var _zero_spin: float = 0.0
var _lug_rows: Array[AnimatableBody3D] = []
var _mm := {}
var _shafts := {}
var _scanned := {}
var _counts := {"flipped": 0, "loaded": 0, "scanned": 0}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_unscrambler = get_node_or_null(unscrambler_path)
	_edger = get_node_or_null(edger_path)
	_loop_a = ChainLoop.from_path(PackedVector2Array([Vector2(LUG_A_Z.x, CHAIN_Y), Vector2(LUG_A_Z.y, CHAIN_Y)]), LUG_R)
	_loop_b = ChainLoop.from_path(PackedVector2Array([Vector2(LUG_B_Z.x, CHAIN_Y), Vector2(LUG_B_Z.y, CHAIN_Y)]), LUG_R)
	_loop_scan = ChainLoop.from_path(PackedVector2Array([Vector2(SCAN_Z.x, SCAN_Y), Vector2(SCAN_Z.y, SCAN_Y)]), SCAN_R)
	for n in ["BD_LugTail", "BD_LugMidA", "BD_LugMidB", "BD_LugHead", "BD_ScanTail", "BD_ScanHead"]:
		_shafts[n] = find_child(n, true, false)
	_flipper = find_child("BD_Flipper", true, false) as Node3D
	for i in ZERO_X.size():
		_zero_meshes.append(find_child("BD_ZeroRoll%d" % (i + 1), true, false) as Node3D)
	_build_bodies()
	_build_visuals()


# --- Bodies -------------------------------------------------------------------------------------

func _build_bodies() -> void:
	_static_box("DeckFloor", Vector3((DECK_X.x + DECK_X.y) * 0.5, DECK_Y - 0.02, (DECK_Z.x + DECK_Z.y) * 0.5),
			Vector3(DECK_X.y - DECK_X.x, 0.04, DECK_Z.y - DECK_Z.x))
	var xa: float = LUG_X.min() + LUG_B_OFFSET - 0.05
	var xb: float = LUG_X.max() + 0.05
	_surf_a = _static_box("LugLoaderA", Vector3((xa + xb) * 0.5, CHAIN_Y - 0.03, (LUG_A_Z.x + LUG_A_Z.y) * 0.5),
			Vector3(xb - xa, 0.06, LUG_A_Z.y - LUG_A_Z.x))
	_surf_b = _static_box("LugLoaderB", Vector3((xa + xb) * 0.5, CHAIN_Y - 0.03, (LUG_B_Z.x + LUG_B_Z.y) * 0.5),
			Vector3(xb - xa, 0.06, LUG_B_Z.y - LUG_B_Z.x))
	# Dead plates across the gaps: take-away to lug loader, lug loader to scanner chains.
	_static_box("DeadPlateIn", Vector3((xa + xb) * 0.5, DEAD_IN_Y - 0.03, (TAKE_END_Z + LUG_A_Z.x) * 0.5),
			Vector3(xb - xa + 0.1, 0.06, LUG_A_Z.x - TAKE_END_Z))
	_static_box("DeadPlateOut", Vector3((SCAN_X.min() + SCAN_X.max()) * 0.5, DEAD_OUT_Y - 0.03,
			(LUG_B_Z.y + SCAN_Z.x) * 0.5), Vector3(SCAN_X.max() - SCAN_X.min() + 0.2, 0.06, SCAN_Z.x - LUG_B_Z.y))
	_surf_scan = _static_box("ScannerChains", Vector3((SCAN_X.min() + SCAN_X.max()) * 0.5, SCAN_Y - 0.03,
			(SCAN_Z.x + SCAN_Z.y) * 0.5), Vector3(SCAN_X.max() - SCAN_X.min() + 0.1, 0.06, SCAN_Z.y - SCAN_Z.x))
	_static_box("ZeroFence", Vector3(FENCE_X + 0.01, SCAN_Y + 0.05, (SCAN_Z.x + SCAN_Z.y) * 0.5),
			Vector3(0.02, 0.14, SCAN_Z.y - SCAN_Z.x - 0.2))
	for key in ["half", "end"]:
		var z := STOP_HALF_Z if key == "half" else STOP_END_Z
		var body := AnimatableBody3D.new()
		body.name = "Stops_" + key
		body.sync_to_physics = false
		add_child(body)
		var line_mid: float = (LUG_X.min() + LUG_X.max()) * 0.5
		for x in LUG_X:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.03, 0.16, 0.03)
			cs.shape = box
			# Body origin sits at the middle of the line; blades just beside each chain.
			cs.position = Vector3(x + 0.0635 - line_mid, -0.08, 0.0)
			body.add_child(cs)
		_stops[key] = {"body": body, "z": z, "down": 0.0, "want_down": false, "board": null,
				"node": find_child("BD_Stops" + ("Half" if key == "half" else "End"), true, false)}
		_place_stop(key)
	for i in ZERO_X.size():
		var roll := AnimatableBody3D.new()
		roll.name = "ZeroRoll%d" % (i + 1)
		roll.sync_to_physics = false
		add_child(roll)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.08, 0.04, 0.305)
		cs.shape = box
		roll.add_child(cs)
		_zero_rolls.append(roll)
	_place_zero_rolls()
	var n := int(_loop_scan.length / SCAN_LUG_PITCH)
	var xm: float = (SCAN_X.min() + SCAN_X.max()) * 0.5
	for i in n:
		var row := AnimatableBody3D.new()
		row.name = "ScanLugs%d" % i
		row.sync_to_physics = false
		add_child(row)
		for x in SCAN_X:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.035, SCAN_LUG_H + 0.012, 0.019)
			cs.shape = box
			cs.position = Vector3(-(x - xm), (SCAN_LUG_H - 0.012) * 0.5, 0.0)
			row.add_child(cs)
		_lug_rows.append(row)
	_move_lug_rows()


func _static_box(body_name: String, centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = centre
	body.add_child(cs)
	return body


# --- Main loop ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var boards := _loader_boards()
	_run_half_stop(boards, delta)
	_run_end_stop(boards)
	_run_flip(delta)
	for key in _stops:
		var st: Dictionary = _stops[key]
		st["down"] = move_toward(st["down"], 1.0 if st["want_down"] else 0.0, delta / stop_time)
		_place_stop(key)
	# A board coming up to the head is pushed off onto the positioning skids only when the edger
	# line is ready for it; otherwise the scanner chains wait.
	_scan_v = scanner_speed
	var edger_ready: bool = _edger != null and _edger.has_method("can_take") and _edger.can_take()
	if not edger_ready:
		for b in _boards_in(37.5, 44.5, SCAN_Z.y - 0.25, SCAN_Z.y + 0.3, CHAIN_Y - 0.1, CHAIN_Y + 0.3):
			_scan_v = 0.0
	_surf_a.constant_linear_velocity = Vector3(0.0, 0.0, loader_slow_speed)
	_surf_b.constant_linear_velocity = Vector3(0.0, 0.0, loader_fast_speed)
	_surf_scan.constant_linear_velocity = Vector3(0.0, 0.0, _scan_v)
	_travel_a += loader_slow_speed * delta
	_travel_b += loader_fast_speed * delta
	_travel_scan += _scan_v * delta
	_move_lug_rows()
	_run_zero_rolls(delta)
	_note_scans()
	if _unscrambler and "hold" in _unscrambler:
		var queued := 0
		for b in boards:
			if b.global_position.z < STOP_HALF_Z:
				queued += 1
		_unscrambler.hold = queued >= queue_full
	_animate()


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


func _loader_boards() -> Array[RigidBody3D]:
	return _boards_in(37.5, 44.5, LUG_A_Z.x - 0.1, LUG_B_Z.y + 0.1, CHAIN_Y - 0.08, CHAIN_Y + 0.3)


func _half_width(b: Node) -> float:
	return (b.board_width if "board_width" in b else 0.184) * 0.5


## The board standing against a set of stops (front edge at the stop face, nearly still).
func _board_at(boards: Array[RigidBody3D], z: float) -> RigidBody3D:
	for b in boards:
		var front := b.global_position.z + _half_width(b)
		if front > z - 0.06 and front < z + 0.005 and absf(b.linear_velocity.z) < 0.15:
			return b
	return null


# --- Stops --------------------------------------------------------------------------------------

func _run_half_stop(boards: Array[RigidBody3D], _delta: float) -> void:
	var st: Dictionary = _stops["half"]
	if st["want_down"]:
		var b := st["board"] as RigidBody3D
		# Up again once the released board is clear and the fast chains have opened a gap behind it.
		if _released_past(b, STOP_HALF_Z) and _line_clear(boards, STOP_HALF_Z, b):
			st["want_down"] = false
			st["board"] = null
		return
	if _flip_t >= 0.0:
		return
	var held := _board_at(boards, STOP_HALF_Z)
	if held == null:
		return
	var id := held.get_instance_id()
	if not _decided.has(id):
		_decided[id] = true
		if _rng.randf() < flip_chance:
			_start_flip(held)
			return
	# Let it go once the end section is empty.
	for b in boards:
		if b != held and b.global_position.z > STOP_HALF_Z:
			return
	if _stops["end"]["want_down"]:
		return
	st["want_down"] = true
	st["board"] = held


func _run_end_stop(boards: Array[RigidBody3D]) -> void:
	var st: Dictionary = _stops["end"]
	if st["want_down"]:
		var b := st["board"] as RigidBody3D
		if _released_past(b, STOP_END_Z):
			st["want_down"] = false
			st["board"] = null
			_counts["loaded"] += 1
			if debug_log:
				print("[%s] %.1f s board %d onto the scanner chains" % [name, Time.get_ticks_msec() / 1000.0, _counts["loaded"]])
		return
	var held := _board_at(boards, STOP_END_Z)
	if held == null or _scan_v <= 0.0:
		return
	# Let it go just after a lug has come up round the tail sprocket, so it lands in that space
	# ahead of the next lug.
	if _lug_phase() > 0.06 and _lug_phase() < 0.22:
		st["want_down"] = true
		st["board"] = held


## True once board b's trailing edge is clear past the stop face at z.
func _released_past(b: RigidBody3D, z: float) -> bool:
	if b == null or not is_instance_valid(b):
		return true
	return b.global_position.z - _half_width(b) > z + 0.02


## Nothing but `except` straddles the stop line at z (so the blades can come up).
func _line_clear(boards: Array[RigidBody3D], z: float, except: RigidBody3D) -> bool:
	for b in boards:
		if b == except:
			continue
		var p := b.global_position.z
		var w := _half_width(b)
		if p - w < z + 0.025 and p + w > z - 0.025:
			return false
	return true


func _place_stop(key: String) -> void:
	var st: Dictionary = _stops[key]
	var y := CHAIN_Y + STOP_UP - STOP_DROP * _ease(st["down"])
	var body := st["body"] as AnimatableBody3D
	body.global_transform = Transform3D(Basis.IDENTITY, Vector3((LUG_X.min() + LUG_X.max()) * 0.5, y, st["z"]))
	var node := st["node"] as Node3D
	if node:
		if not st.has("home"):
			st["home"] = node.position.y
		node.position.y = st["home"] - STOP_DROP * _ease(st["down"])


# --- Flipper ------------------------------------------------------------------------------------

func _start_flip(b: RigidBody3D) -> void:
	_flip_board = b
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	_flip_start = b.global_transform
	_flip_t = 0.0
	_counts["flipped"] += 1
	if debug_log:
		print("[%s] %.1f s flipping a board at the halfway stops" % [name, Time.get_ticks_msec() / 1000.0])


## The D's turn a quarter under the board and back: the flat sides tip it up onto its long edge
## and it rolls over onto its other face where it lay.
func _run_flip(delta: float) -> void:
	if _flip_t < 0.0:
		return
	_flip_t += delta / flip_time
	var p := minf(_flip_t, 1.0)
	if _flipper:
		_flipper.rotation.x = deg_to_rad(90.0) * sin(PI * p)
	if is_instance_valid(_flip_board):
		var w := _half_width(_flip_board)
		var t := _flip_start
		t.basis = Basis(Vector3.RIGHT, PI * _ease(p)) * _flip_start.basis
		t.origin = _flip_start.origin + Vector3(0.0, w * sin(PI * p), 0.0)
		_flip_board.global_transform = t
	if _flip_t >= 1.0:
		if is_instance_valid(_flip_board):
			_flip_board.freeze = false
			_flip_board.linear_velocity = Vector3.ZERO
			_flip_board.angular_velocity = Vector3.ZERO
		_flip_board = null
		_flip_t = -1.0


# --- Scanner chains and zero rollers ------------------------------------------------------------

## How far the lug that last came up round the tail sprocket has gone along the top run.
func _lug_phase() -> float:
	var spacing: float = _loop_scan.length / _lug_rows.size()
	return fposmod(_travel_scan, spacing)


func _move_lug_rows() -> void:
	var xm: float = (SCAN_X.min() + SCAN_X.max()) * 0.5
	for i in _lug_rows.size():
		var s: float = i * _loop_scan.length / _lug_rows.size() + _travel_scan
		_lug_rows[i].global_transform = _frame(_loop_scan.sample(s), xm)


func _run_zero_rolls(delta: float) -> void:
	# Up while a board is passing over the roller line and short of the fence.
	var want := false
	for b in _boards_in(37.5, 44.5, ZERO_Z - 0.35, ZERO_Z + 0.35, CHAIN_Y - 0.05, CHAIN_Y + 0.25):
		var w := _half_width(b)
		var over := b.global_position.z + w > ZERO_Z - 0.15 and b.global_position.z - w < ZERO_Z + 0.15
		if over and _board_end_x(b) < FENCE_X - 0.01:
			want = true
	_zero_lift = move_toward(_zero_lift, 1.0 if want else 0.0, delta / 0.15)
	_zero_spin += (zero_roll_speed if _zero_lift > 0.5 else 0.0) * delta
	_place_zero_rolls()


func _board_end_x(b: Node3D) -> float:
	var half: float = b.product_length * 0.5 if "product_length" in b else 2.44
	return b.global_position.x + absf(b.global_basis.x.x) * half


func _place_zero_rolls() -> void:
	for i in _zero_rolls.size():
		var r := _zero_rolls[i]
		var top := ZERO_TOP - ZERO_LIFT + ZERO_LIFT * _zero_lift
		r.global_transform = Transform3D(Basis.IDENTITY, Vector3(ZERO_X[i], top - 0.02, ZERO_Z))
		r.constant_linear_velocity = Vector3(zero_roll_speed if _zero_lift > 0.5 else 0.0, 0.0, 0.0)
		var m := _zero_meshes[i] if i < _zero_meshes.size() else null
		if m:
			if not m.has_meta("home"):
				m.set_meta("home", m.position.y)
			m.position.y = float(m.get_meta("home")) - ZERO_LIFT + ZERO_LIFT * _zero_lift
			m.rotation.z = -_zero_spin / 0.0508


func _note_scans() -> void:
	for b in _boards_in(37.5, 44.5, SCANNER_Z - 0.05, SCANNER_Z + 0.05, CHAIN_Y - 0.05, CHAIN_Y + 0.3):
		var id := b.get_instance_id()
		if not _scanned.has(id):
			_scanned[id] = true
			_counts["scanned"] += 1
			if debug_log:
				print("[%s] %.1f s scanned board %d, end at x %.3f" % [name, Time.get_ticks_msec() / 1000.0,
						_counts["scanned"], _board_end_x(b)])


# --- Visuals ------------------------------------------------------------------------------------

func _build_visuals() -> void:
	var scene := load(CHAIN_SCENE) as PackedScene
	if scene:
		var src := scene.instantiate()
		var link := (src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var xb: Array[float] = []
		for x in LUG_X:
			xb.append(x + LUG_B_OFFSET)
		_mm["a"] = _chain_set(link, _loop_a, LUG_X, "LugLoaderChainsA")
		_mm["b"] = _chain_set(link, _loop_b, xb, "LugLoaderChainsB")
		_mm["scan"] = _chain_set(link, _loop_scan, SCAN_X, "ScannerChains")
		src.free()
	var lscene := load(LUG_SCENE) as PackedScene
	if lscene:
		var src := lscene.instantiate()
		for c in src.find_children("*", "MeshInstance3D", true, false):
			_mm["lugs"] = _multimesh((c as MeshInstance3D).mesh, _lug_rows.size() * SCAN_X.size(), "ScannerLugs")
			break
		src.free()
	_animate()


func _multimesh(mesh: Mesh, count: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _animate() -> void:
	if _mm.has("a"):
		_lay(_mm["a"], _travel_a)
		_lay(_mm["b"], _travel_b)
		_lay(_mm["scan"], _travel_scan)
	if _mm.has("lugs"):
		var k := 0
		for i in _lug_rows.size():
			var smp: Array = _loop_scan.sample(i * _loop_scan.length / _lug_rows.size() + _travel_scan)
			for x in SCAN_X:
				_mm["lugs"].set_instance_transform(k, _frame(smp, x))
				k += 1
	for pair in [["BD_LugTail", _travel_a, LUG_R], ["BD_LugMidA", _travel_a, LUG_R], ["BD_LugMidB", _travel_b, LUG_R],
			["BD_LugHead", _travel_b, LUG_R], ["BD_ScanTail", _travel_scan, SCAN_R], ["BD_ScanHead", _travel_scan, SCAN_R]]:
		var n := _shafts.get(pair[0]) as Node3D
		if n:
			n.rotation.x = pair[1] / pair[2]


## A set of strands of chain on one loop, with its link positions baked for animation.
func _chain_set(mesh: Mesh, loop, xs: Array[float], node_name: String) -> Dictionary:
	var per := int(loop.length / LINK_PITCH)
	var mm := _multimesh(mesh, per * xs.size(), node_name)
	return {"mm": mm, "loop": loop, "per": per, "baked": loop.bake(per, xs, _frame, 8), "shown": -1}


func _lay(chain: Dictionary, travel: float) -> void:
	var k: int = chain["loop"].phase_index(travel, chain["per"], 8)
	if k != chain["shown"]:
		chain["shown"] = k
		(chain["mm"] as MultiMesh).buffer = chain["baked"][k]


## The chain frame at a loop sample, at world x: (across, out of the loop, -travel).
func _frame(smp: Array, x: float) -> Transform3D:
	var p: Vector2 = smp[0]
	var t2: Vector2 = smp[1]
	var t := Vector3(0.0, t2.y, t2.x)
	var across := Vector3.BACK.cross(Vector3.UP)
	return Transform3D(Basis(across, across.cross(t), -t), Vector3(x, p.y, p.x))


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


## One line for debug HUDs.
func status_text() -> String:
	return "halfway %s, end %s, scanner %.1f m/s, loaded %d, flipped %d, scanned %d" % [
			"down" if _stops["half"]["want_down"] else "up", "down" if _stops["end"]["want_down"] else "up",
			_scan_v, _counts["loaded"], _counts["flipped"], _counts["scanned"]]
