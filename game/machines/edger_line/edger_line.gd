extends Node3D

## edger_line.gd
## Positioners, lineal infeed, 4TA36 edger and picker belt: the end of the 3338 board line.
##
## The models (game/assets/models/board_line/board_edger_*, built by dev/blender/board_line/ed_build)
## are in mill coordinates, like this node. A board pushed off the scanner chains onto the skids is:
##   1. picked up by the four positioner heads, which pivot up behind it, and pushed across onto the
##      parking ramps against the cushion shoes to where the scanner's solution puts the best board
##      in it (2x4 to 2x12 inside the wane) square on the edger's centre line
##   2. set down onto the sharp chain as the ramps drop, held by the hold-down rolls, and fed
##      end-first into the edger
##   3. sawn: the saws take an edging off each side (flitches); a board already square (from the
##      gang) passes with the saws open. Now and then an over-thick board gets a pass under the top
##      re-man chip head. The pieces grow out of the saws as the board feeds through.
##   4. carried down the picker belt; the pendulum pickers sweep each edging off its side into the
##      chutes, the board rides on to the end.
## The board is held by the heads and shoes, then the chain points and hold-downs, then the feed
## rolls, so it moves with them; the pieces are let go onto the belt as they leave the edger.

enum Pos { WAIT, CATCH, PUSH, SET, LOWER, HAND_OFF }

const Z_LINE := 21.6
const X0 := 43.6969                                   # edger infeed
const STATION_X: Array[float] = [42.9793, 41.7855, 40.8203, 39.4995]
const HOLD_X: Array[float] = [43.0873, 41.9544, 40.9536]
const INFEED_X := Vector2(37.6072, 43.5445)
const BELT_X := Vector2(46.5417, 52.6377)
const BELT_HALF := 0.3048
const PICKER_X: Array[float] = [48.5229, 51.0629]
const SKID_Z := Vector2(20.4151, 21.2444)
const SKID_Y := 1.098
const RAMP_Y := 1.104
const RAMP_DROP_DEG := 25.0
const SHARP_Y := 1.095
const SHARP_R := 0.1016
const EDGER_LL := 1.090
const BELT_Y := 1.086
const BELT_R := 0.1016
const POS_PARK_Z := 20.3751
const CUSH_PARK_Z := 21.8032
const HEAD_DOWN_DEG := -40.0
const HOLD_UP := 0.12
const HOLD_ROLL_R := 0.1016
const SAW_X := 44.4271
const CHIP_X := 45.4304
const SAW_AXIS := Vector3(44.4271, 1.2983, 21.6)
const CHIP_AXIS := Vector3(45.4304, 1.3821, 21.6)
const EDGER_END_X := 46.3766
const KERF := 0.004
const DECK_Y := 0.0233
const EXT_X := Vector2(45.0, 53.6)
const EXT_Z := Vector2(19.8, 24.6)
## Nominal widths the scanner can choose, narrowest first.
const WIDTHS := [["2x4", 0.089], ["2x6", 0.140], ["2x8", 0.184], ["2x10", 0.235], ["2x12", 0.286]]
const SHARP_PITCH := 0.0381                      # 1 1/2 in sharp-top chain
const SHARP_POINT := 0.012                       # point height over the link side bars
const SHARP_LINK_SCENE := "res://game/assets/models/board_line/board_edger_sharp_link.glb"

@export var position_time: float = 1.4
@export var feed_speed: float = 1.5
@export var belt_speed: float = 1.5
@export var picker_time: float = 0.5
## Boards at least this thick get a pass under the re-man chip head.
@export var reman_over: float = 0.0405
@export var debug_log: bool = false

var pos: Pos = Pos.WAIT

var _t: float = 0.0
var _board: RigidBody3D = null
var _start := Transform3D()
var _target := Transform3D()
var _solution := {}
var _feeding: Array[Dictionary] = []      # boards on the sharp chain / in the edger
var _belt: StaticBody3D
var _heads: Array[Node3D] = []
var _carriages: Array[Node3D] = []
var _shoes: Array[Node3D] = []
var _holds: Array[Node3D] = []
var _hold_home: Array[float] = []
var _hold_amt: Array[float] = [0.0, 0.0, 0.0]
var _ramps: Node3D
var _ramp_amt: float = 0.0
var _pickers: Array[Node3D] = []
var _picker_t: Array[float] = [-1.0, -1.0]
var _picked := {}
var _picker_piece: Array = [null, null]
var _picker_from: Array = [Transform3D(), Transform3D()]
var _saw_pivot: Node3D
var _chip_pivot: Node3D
var _reman: Node3D
var _reman_home: float = 0.0
var _reman_amt: float = 0.0
var _spin: float = 0.0
var _chain_travel: float = 0.0
var _belt_travel: float = 0.0
var _loop
var _links: MultiMesh
var _counts := {"edged": 0, "edgings": 0, "remanned": 0}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in STATION_X.size():
		_carriages.append(find_child("ED_Pos%d" % (i + 1), true, false) as Node3D)
		_heads.append(find_child("ED_PosHead%d" % (i + 1), true, false) as Node3D)
		_shoes.append(find_child("ED_Cush%d" % (i + 1), true, false) as Node3D)
	for i in HOLD_X.size():
		var h := find_child("ED_Hold%d" % (i + 1), true, false) as Node3D
		_holds.append(h)
		_hold_home.append(h.position.y if h else 0.0)
	for i in PICKER_X.size():
		_pickers.append(find_child("ED_Picker%d" % (i + 1), true, false) as Node3D)
	_ramps = find_child("ED_Ramps", true, false) as Node3D
	_reman = find_child("RemanSection", true, false) as Node3D
	if _reman:
		_reman_home = _reman.position.z
	_saw_pivot = _make_pivot(["Saws", "SawArbor"], SAW_AXIS, "SawPivot")
	_chip_pivot = _make_pivot(["ChipHead_Arbor", "ChipHead_Segments"], CHIP_AXIS, "ChipPivot")
	_set_heads(0.0, POS_PARK_Z, CUSH_PARK_Z)
	_build_bodies()
	_build_chain()


## The scanner deck pushes the next board off its chains only while this is true.
func can_take() -> bool:
	return pos == Pos.WAIT and _skid_board() == null and not _belt_held


## The picker belt stops with a board near its end while the landing table can't take it
## (rolls down or a board still on it); boards on the belt wait there.
@export var landing_path: NodePath = ^"../LandingTransfer"
var _belt_held: bool = false
var _belt_v: float = 0.0


func _run_belt(delta: float) -> void:
	var landing := get_node_or_null(landing_path)
	var waiting := false
	for node in get_tree().get_nodes_in_group("cut_boards"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.is_in_group("cut_slabs"):
			continue
		var p := b.global_position
		var half: float = b.product_length * 0.5 if "product_length" in b else 2.44
		# Only a board whose nose is coming up to the belt end waits; one already running off onto
		# the table is carried on (stopping it there would leave it across the belt and the rolls).
		if absf(p.z - Z_LINE) < BELT_HALF + 0.05 and absf(p.y - BELT_Y) < 0.15 and p.x + half > BELT_X.y - 0.6 \
				and p.x + half < BELT_X.y + 0.02:
			waiting = true
	_belt_held = waiting and landing != null and landing.has_method("can_take") and not landing.can_take()
	_belt_v = move_toward(_belt_v, 0.0 if _belt_held else belt_speed, delta * 3.0)
	_belt.constant_linear_velocity = Vector3(_belt_v, 0.0, 0.0)


# --- Pivots and bodies --------------------------------------------------------------------------

## Put the named meshes under a new node on their arbor's axis, so it can spin them.
func _make_pivot(names: Array, axis_world: Vector3, pivot_name: String) -> Node3D:
	var first := find_child(names[0], true, false) as Node3D
	if first == null:
		return null
	var parent := first.get_parent() as Node3D
	var pivot := Node3D.new()
	pivot.name = pivot_name
	parent.add_child(pivot)
	pivot.global_position = axis_world
	for n in names:
		var m := find_child(n, true, false) as Node3D
		if m:
			var keep := m.global_transform
			m.get_parent().remove_child(m)
			pivot.add_child(m)
			m.global_transform = keep
	return pivot


func _build_bodies() -> void:
	_static_box("DeckExtension", Vector3((EXT_X.x + EXT_X.y) * 0.5, DECK_Y - 0.02, (EXT_Z.x + EXT_Z.y) * 0.5),
			Vector3(EXT_X.y - EXT_X.x, 0.04, EXT_Z.y - EXT_Z.x), Basis.IDENTITY)
	_static_box("Skids", Vector3(40.6, SKID_Y - 0.02, (SKID_Z.x + SKID_Z.y) * 0.5),
			Vector3(5.6, 0.04, SKID_Z.y - SKID_Z.x), Basis.IDENTITY)
	_belt = _static_box("PickerBelt", Vector3((BELT_X.x + BELT_X.y) * 0.5, BELT_Y - 0.02, Z_LINE),
			Vector3(BELT_X.y - BELT_X.x, 0.04, BELT_HALF * 2.0), Basis.IDENTITY)
	_belt.constant_linear_velocity = Vector3(belt_speed, 0.0, 0.0)
	# Edging chutes down off each side of the belt to the deck.
	for s in [-1.0, 1.0]:
		var a := Vector2(Z_LINE + s * (BELT_HALF + 0.02), BELT_Y - 0.03)
		# Down onto the tail of that side's edging slasher (waste system), just over its chains.
		var b := Vector2(Z_LINE + s * 0.95, 0.335)
		var d := (b - a).normalized()
		var t := Vector3(0.0, d.y, d.x)
		var n := Vector3(0.0, t.z, -t.y) * (-1.0 if s < 0.0 else 1.0)
		if n.y < 0.0:
			n = -n
		var chute_basis := Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n))
		var mid := Vector3((BELT_X.x + BELT_X.y) * 0.5, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5) - n * 0.01
		_static_box("EdgingChute%s" % ("Near" if s < 0.0 else "Far"), mid,
				Vector3(BELT_X.y - BELT_X.x - 0.8, 0.02, a.distance_to(b)), chute_basis)


func _static_box(body_name: String, centre: Vector3, size: Vector3, box_basis: Basis) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = Transform3D(box_basis, centre)
	body.add_child(cs)
	return body


# --- Main loop ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_run_positioning(delta)
	_run_feed(delta)
	_run_pickers(delta)
	_animate(delta)


func _boards_in(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, group := "cut_boards") -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_tree().get_nodes_in_group(group):
		var b := node as RigidBody3D
		if b == null or b.freeze:
			continue
		if group == "cut_boards" and b.is_in_group("cut_slabs"):
			continue
		var p := b.global_position
		if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1 and p.y > y0 and p.y < y1:
			out.append(b)
	return out


## A board lying still on the skids, clear of the scanner chains.
func _skid_board() -> RigidBody3D:
	for b in _boards_in(37.0, 44.5, SKID_Z.x - 0.05, SKID_Z.y, 1.0, 1.25):
		if b.linear_velocity.length() < 0.08:
			return b
	return null


# --- Positioning --------------------------------------------------------------------------------

func _run_positioning(delta: float) -> void:
	match pos:
		Pos.WAIT:
			var b := _skid_board()
			if b != null and _infeed_clear():
				_take_board(b)
		Pos.CATCH:
			# Carriages come up to the board's back edge, then the heads pivot up behind it.
			_t += delta / 0.5
			var back := _start.origin.z - _half_w(_board)
			_set_heads(_ease(minf(_t, 1.0)), lerpf(POS_PARK_Z, back, minf(_t * 2.0, 1.0)), CUSH_PARK_Z)
			if _t >= 1.0:
				_enter(Pos.PUSH)
		Pos.PUSH:
			_t += delta / position_time
			var s := _ease(minf(_t, 1.0))
			var xf := _start.interpolate_with(_target, s)
			xf.origin.y = RAMP_Y + _board_t(_board) * 0.5 + 0.002
			_place(_board, xf)
			var back := xf.origin.z - _half_w(_board)
			var front := xf.origin.z + _half_w(_board)
			# The shoes come in to meet the front edge as the heads bring the board over.
			_set_heads(1.0, back, lerpf(CUSH_PARK_Z, front + 0.012, s))
			if _t >= 1.0:
				_enter(Pos.SET)
		Pos.SET:
			_t += delta / 0.3
			if _t >= 1.0:
				_enter(Pos.LOWER)
		Pos.LOWER:
			# The ramps drop and the board settles onto the chain points; the hold-downs come down.
			_t += delta / 0.45
			var s := _ease(minf(_t, 1.0))
			_ramp_amt = s
			var xf := _target
			xf.origin.y = lerpf(RAMP_Y, SHARP_Y, s) + _board_t(_board) * 0.5
			_place(_board, xf)
			if _t >= 1.0:
				_feeding.append({"board": _board, "x": xf.origin.x, "split": false, "pieces": [], "sol": _solution,
						"remanned": false})
				_board = null
				_enter(Pos.HAND_OFF)
		Pos.HAND_OFF:
			# Shoes back, heads down and back to park, ramps up again.
			_t += delta / 0.6
			var s := _ease(minf(_t, 1.0))
			_set_heads(1.0 - s, lerpf(_carriage_z(), POS_PARK_Z, s), lerpf(_shoe_z(), CUSH_PARK_Z, s))
			_ramp_amt = 1.0 - s
			if _t >= 1.0:
				_enter(Pos.WAIT)


func _enter(p: Pos) -> void:
	pos = p
	_t = 0.0


## Nothing left on the infeed chain where the next board will come down.
func _infeed_clear() -> bool:
	for f in _feeding:
		var b := f["board"] as RigidBody3D
		if is_instance_valid(b) and b.global_position.x - _half_len(b) < INFEED_X.y + 0.3:
			return false
	return true


func _take_board(b: RigidBody3D) -> void:
	_board = b
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	# Square it on the skids: along +X, keeping whichever face is up.
	var up := Vector3.UP if b.global_basis.y.y >= 0.0 else Vector3.DOWN
	var square := Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up))
	_start = Transform3D(square, b.global_position)
	_solution = _solve(b, square)
	_target = Transform3D(square, Vector3(_start.origin.x, RAMP_Y + _board_t(b) * 0.5, _solution["centre_z"]))
	_place(b, _start)
	if debug_log:
		print("[%s] %.1f s positioning a %.0f mm board: %s, edgings %.0f / %.0f mm" % [name, Time.get_ticks_msec() / 1000.0,
				_board_w(b) * 1000.0, _solution["size"], _solution["edge_lo"] * 1000.0, _solution["edge_hi"] * 1000.0])
	_enter(Pos.CATCH)


## The scanner's answer: the widest nominal board inside the wane, and where to put the flitch so
## that board is centred on the saw line. Square boards (no wane) keep their size.
func _solve(b: RigidBody3D, square: Basis) -> Dictionary:
	var w := _board_w(b)
	var wl: float = b.get("wane_left") if b.get("wane_left") != null else 0.0
	var wr: float = b.get("wane_right") if b.get("wane_right") != null else 0.0
	# The board's local -Z edge is on the world -Z side when its square z points +Z.
	var flip := square.z.z < 0.0
	var lo := wr if flip else wl                     # wane on the world -Z edge
	var hi := wl if flip else wr
	var size := ""
	var width := 0.0
	var nominal: String = str(b.get("nominal_size"))
	if lo <= 0.0 and hi <= 0.0 and nominal != "flitch":
		size = nominal
		width = w
	else:
		for entry in WIDTHS:
			if entry[1] <= w - lo - hi:
				size = entry[0]
				width = entry[1]
	if size == "":
		size = "2x4"
		width = minf(0.089, w)
	# Product centred on the usable part between the wanes.
	var product_off := (lo - hi) * 0.5            # from the board centre toward +Z
	var edge_lo := maxf((w * 0.5 + product_off) - width * 0.5 - KERF, 0.0)
	var edge_hi := maxf((w * 0.5 - product_off) - width * 0.5 - KERF, 0.0)
	return {"size": size, "width": width, "centre_z": Z_LINE - product_off, "edge_lo": edge_lo, "edge_hi": edge_hi,
			"product_off": product_off}


func _set_heads(up: float, head_z: float, shoe_z: float) -> void:
	for i in _carriages.size():
		if _carriages[i]:
			_carriages[i].global_position.z = head_z
		if _heads[i]:
			_heads[i].rotation.x = deg_to_rad(HEAD_DOWN_DEG) * (1.0 - up)
		if _shoes[i]:
			_shoes[i].global_position.z = shoe_z + 0.012


func _carriage_z() -> float:
	return _carriages[0].global_position.z if _carriages[0] else POS_PARK_Z


func _shoe_z() -> float:
	return (_shoes[0].global_position.z - 0.012) if _shoes[0] else CUSH_PARK_Z


# --- Lineal infeed, edger, belt -------------------------------------------------------------------

func _run_feed(delta: float) -> void:
	var moving := not _feeding.is_empty()
	_chain_travel += (feed_speed if moving else 0.0) * delta
	for f in _feeding.duplicate():
		var b := f["board"] as RigidBody3D
		var dx := feed_speed * delta
		f["x"] += dx
		var front: float = f["x"] + (_half_len(b) if is_instance_valid(b) else 2.44)
		var tail: float = f["x"] - (_half_len(b) if is_instance_valid(b) else 2.44)
		if is_instance_valid(b):
			b.global_position.x = f["x"]
		if not f["split"] and front >= SAW_X and is_instance_valid(b):
			_split(f)
		for p: RigidBody3D in f["pieces"]:
			if is_instance_valid(p):
				p.global_position.x = f["x"]
		_grow(f, front)
		# Re-man: the chip head comes down while an over-thick board passes under it.
		var thick := is_instance_valid(b) and _board_t(b) >= reman_over
		if thick and front >= CHIP_X - 0.3 and tail <= CHIP_X:
			_reman_amt = move_toward(_reman_amt, 1.0, delta * 3.0)
			if not f["remanned"]:
				f["remanned"] = true
				_counts["remanned"] += 1
				if debug_log:
					print("[%s] %.1f s re-man head planing an over-thick board" % [name, Time.get_ticks_msec() / 1000.0])
		if f["split"] and tail >= SAW_X and is_instance_valid(b):
			b.queue_free()
			f["board"] = null
		# Out of the edger: the pieces go onto the belt.
		if tail >= EDGER_END_X:
			for p: RigidBody3D in f["pieces"]:
				_release(p)
			if is_instance_valid(f["board"]):
				_release(f["board"])
			_feeding.erase(f)
	if _feeding.is_empty() or not _any_under_chip():
		_reman_amt = move_toward(_reman_amt, 0.0, delta * 2.0)
	# Hold-downs are down while a board on the chain is under them.
	for i in HOLD_X.size():
		var on := false
		for f in _feeding:
			var half := 2.44
			if abs(f["x"] - HOLD_X[i]) < half:
				on = true
		_hold_amt[i] = move_toward(_hold_amt[i], 1.0 if on else 0.0, delta / 0.25)
	_run_belt(delta)
	_belt_travel += _belt_v * delta


func _any_under_chip() -> bool:
	for f in _feeding:
		if f["remanned"] and f["x"] - 2.44 < CHIP_X:
			return true
	return false


## Saw the board: the product and an edging each side as kinematic pieces riding with it.
func _split(f: Dictionary) -> void:
	f["split"] = true
	var b := f["board"] as RigidBody3D
	var sol: Dictionary = f["sol"]
	var t := minf(_board_t(b), 0.038) if f["remanned"] or _board_t(b) >= reman_over else _board_t(b)
	var y := b.global_position.y - (_board_t(b) - t) * 0.5
	var scene := load("res://game/lumber/cut_board.tscn") as PackedScene
	var pieces: Array[RigidBody3D] = []
	var product := scene.instantiate() as RigidBody3D
	product.nominal_size = sol["size"]
	product.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	product.freeze = true
	b.get_parent().add_child(product)
	product.configure_dimensions(_product_len(b), t, sol["width"])
	product.nominal_size = sol["size"]
	product.global_transform = Transform3D(Basis.IDENTITY, Vector3(f["x"], y, Z_LINE))
	pieces.append(product)
	var w := _board_w(b)
	var bc: float = sol["centre_z"]
	for side in [-1.0, 1.0]:
		var ew: float = sol["edge_lo"] if side < 0.0 else sol["edge_hi"]
		if ew < 0.008:
			continue
		var e := scene.instantiate() as RigidBody3D
		e.nominal_size = "edging"
		e.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		e.freeze = true
		b.get_parent().add_child(e)
		e.configure_dimensions(_product_len(b), t, ew)
		e.nominal_size = "edging"
		e.add_to_group("cut_slabs")
		e.add_to_group("edgings")
		# Bark on its outer edge.
		if e.has_method("set_wane"):
			e.set_wane(minf(ew, 0.02) if side < 0.0 else 0.0, minf(ew, 0.02) if side > 0.0 else 0.0)
		var z: float = bc + side * (w * 0.5 - ew * 0.5)
		e.global_transform = Transform3D(Basis.IDENTITY, Vector3(f["x"], y, z))
		pieces.append(e)
		_counts["edgings"] += 1
	for i in pieces.size():
		pieces[i].add_collision_exception_with(b)
		for j in range(i + 1, pieces.size()):
			pieces[i].add_collision_exception_with(pieces[j])
	f["pieces"] = pieces
	_counts["edged"] += 1
	if debug_log:
		print("[%s] %.1f s saws in: %s with %d edgings" % [name, Time.get_ticks_msec() / 1000.0, sol["size"], pieces.size() - 1])


## While a board feeds through the saws, show only the part of it upstream of the saw line and
## only the part of each piece downstream.
func _grow(f: Dictionary, front: float) -> void:
	if not f["split"]:
		return
	var b := f["board"] as RigidBody3D
	if is_instance_valid(b):
		var length := _product_len(b)
		var keep := clampf((SAW_X - (front - length)) / length, 0.01, 1.0)
		var mi := b.get_node_or_null("MeshInstance3D") as Node3D
		if mi:
			mi.scale.x = keep
			mi.position.x = -length * 0.5 * (1.0 - keep)
	for p: RigidBody3D in f["pieces"]:
		if not is_instance_valid(p):
			continue
		var length := _product_len(p)
		var shown := clampf((front - SAW_X) / length, 0.01, 1.0)
		var pm := p.get_node_or_null("MeshInstance3D") as Node3D
		if pm:
			pm.scale.x = shown
			pm.position.x = length * 0.5 * (1.0 - shown)


func _release(p: RigidBody3D) -> void:
	if not is_instance_valid(p):
		return
	var pm := p.get_node_or_null("MeshInstance3D") as Node3D
	if pm:
		pm.scale.x = 1.0
		pm.position.x = 0.0
	p.freeze = false
	p.linear_velocity = Vector3(belt_speed, 0.0, 0.0)
	p.angular_velocity = Vector3.ZERO
	p.sleeping = false


# --- Pickers ---------------------------------------------------------------------------------------

## Picker 1 hangs over the near (-Z) half of the belt, picker 2 over the far half. Each swings out
## when an edging on its side is passing under it and sweeps it off into that side's chute.
func _run_pickers(delta: float) -> void:
	for i in _pickers.size():
		var side := -1.0 if i == 0 else 1.0
		if _picker_t[i] < 0.0:
			for e in _boards_in(BELT_X.x, BELT_X.y + 0.5, Z_LINE - 0.4, Z_LINE + 0.4, BELT_Y - 0.05, BELT_Y + 0.2, "edgings"):
				if _picked.has(e.get_instance_id()):
					continue
				var on_side := (e.global_position.z - Z_LINE) * side > 0.1
				var half := _half_len(e)
				var under := absf(e.global_position.x - PICKER_X[i]) < half - 0.3
				if on_side and under:
					_picker_t[i] = 0.0
					_picked[e.get_instance_id()] = true
					# The paddle comes down behind the edging and carries it out over the belt
					# edge; it is the paddle that moves it, so it rides with the paddle.
					e.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					e.freeze = true
					_picker_piece[i] = e
					_picker_from[i] = e.global_transform
					if debug_log:
						print("[%s] %.1f s picker %d sweeps an edging off" % [name, Time.get_ticks_msec() / 1000.0, i + 1])
					break
			continue
		_picker_t[i] += delta / picker_time
		var swing := sin(PI * minf(_picker_t[i], 1.0))
		if _pickers[i]:
			_pickers[i].rotation.x = -side * deg_to_rad(38.0) * swing
		var e := _picker_piece[i] as RigidBody3D
		if e != null and is_instance_valid(e):
			# Out to just past the belt edge over the first half of the stroke, then let go onto
			# the chute.
			var s := clampf(_picker_t[i] * 2.0, 0.0, 1.0)
			var from: Transform3D = _picker_from[i]
			var xf := from
			xf.origin.x += belt_speed * _picker_t[i] * picker_time
			xf.origin.z = lerpf(from.origin.z, Z_LINE + side * (BELT_HALF + 0.06), _ease(s))
			xf.origin.y = from.origin.y + 0.02 * sin(PI * s)
			e.global_transform = xf
			if s >= 1.0:
				e.freeze = false
				e.linear_velocity = Vector3(0.0, -0.2, side * 0.8)
				e.angular_velocity = Vector3.ZERO
				_picker_piece[i] = null
		if _picker_t[i] >= 1.0:
			_picker_t[i] = -1.0


# --- Animation -----------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	_spin += delta * 30.0
	if _saw_pivot:
		# The arbors run across the machine: the edger's Blender Y, its local Z in Godot.
		_saw_pivot.rotation.z = _spin
	if _chip_pivot:
		_chip_pivot.rotation.z = _spin * 0.6
	if _reman:
		_reman.position.z = _reman_home - 0.012 * _reman_amt
	if _ramps:
		_ramps.rotation.x = deg_to_rad(RAMP_DROP_DEG) * _ease(_ramp_amt)
	for i in _holds.size():
		if _holds[i]:
			_holds[i].position.y = _hold_home[i] - HOLD_UP * _ease(_hold_amt[i])
	for n in ["ED_InfeedTail", "ED_InfeedHead"]:
		var s := find_child(n, true, false) as Node3D
		if s:
			s.rotation.z = -_chain_travel / SHARP_R
	for n in ["ED_BeltTail", "ED_BeltHead"]:
		var s := find_child(n, true, false) as Node3D
		if s:
			s.rotation.z = -_belt_travel / BELT_R
	_update_chain()


func _build_chain() -> void:
	var CL := preload("res://game/transport/chains/chain_loop.gd")
	# Link side bars run along the loop; each point stands SHARP_POINT above them, the board rides
	# on the points.
	var line_y := SHARP_Y - SHARP_POINT
	_loop = CL.from_path(PackedVector2Array([Vector2(INFEED_X.x + 0.2, line_y), Vector2(INFEED_X.y - 0.1, line_y)]), SHARP_R)
	var scene := load(SHARP_LINK_SCENE) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate()
	var link: Mesh = null
	for c in src.find_children("*", "MeshInstance3D", true, false):
		link = (c as MeshInstance3D).mesh
		break
	src.free()
	if link == null:
		return
	_links = _mm(link, int(_loop.length / SHARP_PITCH), "SharpChain")
	_update_chain()


func _mm(mesh: Mesh, count: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mm


## The sharp chain runs along X; every other link carries a point.
func _update_chain() -> void:
	if _links == null:
		return
	var total := _links.instance_count
	for i in total:
		var smp: Array = _loop.sample(i * _loop.length / total + _chain_travel)
		var p: Vector2 = smp[0]
		var t2: Vector2 = smp[1]
		var t := Vector3(t2.x, t2.y, 0.0)
		var across := Vector3.BACK
		_links.set_instance_transform(i, Transform3D(Basis(across, across.cross(t), -t), Vector3(p.x, p.y, Z_LINE)))


# --- Helpers ---------------------------------------------------------------------------------------

func _place(b: RigidBody3D, t: Transform3D) -> void:
	if is_instance_valid(b):
		b.global_transform = t


func _half_w(b: Node) -> float:
	return _board_w(b) * 0.5


func _board_w(b: Node) -> float:
	return float(b.get("board_width")) if b and b.get("board_width") != null else 0.184


func _board_t(b: Node) -> float:
	return float(b.get("board_thickness")) if b and b.get("board_thickness") != null else 0.038


func _product_len(b: Node) -> float:
	return float(b.get("product_length")) if b and b.get("product_length") != null else 4.877


func _half_len(b: Node) -> float:
	return _product_len(b) * 0.5


func _ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


## One line for debug HUDs.
func status_text() -> String:
	return "%s, on chain %d, edged %d, edgings %d, re-manned %d" % [Pos.keys()[pos], _feeding.size(), _counts["edged"],
			_counts["edgings"], _counts["remanned"]]
