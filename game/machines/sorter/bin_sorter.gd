@tool
class_name BinSorter
extends Node3D

## 10-bay lumber drop sorter. Model and layout: dev/blender/bin_sorter/sorter_build.py.
##
## Sorter-local frame: +X board travel, +Y up, +Z along the board length, origin on the
## floor below where the incline hands boards over. Every step of the board path is a
## physical contact; this script only runs the drives and decides when gates open:
## 1. The incline's lugs push a board off its crest onto the live chain transfer, whose four
##    smooth-top chains carry it up to the pop-up stop. The incline never has to stop.
## 2. The overhead lug chain indexes to the boards: a lug waits just above the deck behind
##    the stop, and as soon as a board reaches the stop the stop drops and that lug pushes the
##    board along the deck's wear rails, so every lug carries a board.
## 3. Over its bay (its own size's bay, or while that one is discharging, the nearest free
##    one) the gate arms swing down and the board falls onto the fork carriage, landing and
##    settling however it falls. The forks hold still until the pile breaks the bay's photo eye
##    near the top, then lower until the beam is clear.
## 4. A full bay lowers its forks below the haul-out chains. The chains carry the pile to
##    the end table stops and the forks go back up to catch height. Piles stay on the end
##    table; later ones queue up behind them.
##
## Static collision (Deck, TransferChains, HaulChains, EndStops, InfeedZone) is saved in
## bin_sorter.tscn. After changing a layout constant below, rerun
## dev/tools/build_bin_sorter_scene.gd to regenerate it. Gates, carriages, overhead lugs
## and the stop are built by this script when the scene loads.

const FrameScene := preload("res://game/assets/models/bin_sorter/sorter_frame.glb")
const GateScene := preload("res://game/assets/models/bin_sorter/sorter_gate.glb")
const CarriageScene := preload("res://game/assets/models/bin_sorter/sorter_carriage.glb")
const StopScene := preload("res://game/assets/models/bin_sorter/sorter_infeed_stop.glb")
const TopLinkScene := preload("res://game/assets/models/bin_sorter/sorter_top_link.glb")
const TopLugScene := preload("res://game/assets/models/bin_sorter/sorter_top_lug.glb")
const HaulLinkScene := preload("res://game/assets/models/bin_sorter/sorter_haul_link.glb")
const TransferLinkScene := preload("res://game/assets/models/bin_sorter/sorter_transfer_link.glb")
const CutBoardScript := preload("res://game/lumber/cut_board.gd")

# ── Layout (must match sorter_build.py) ───────────────────────────────────────
const NB := 10
const BAY := 1.0
const BX0 := 1.0
const DECK_Y := 4.30
const DECK_T := 0.03
const DECK_HALF := 2.8
const COL_Z := 3.05

const GATE_X0 := 0.1
const GATE_W := 0.8
const GATE_AXIS_DY := -0.06
const GATE_ARM_Z: Array[float] = [-2.40, -1.75, -1.05, -0.35, 0.35, 1.05, 1.75, 2.40]
const GATE_CYL_Z := 2.70
const GATE_LEVER_PIN := Vector2(0.095, -0.07)
const RAIL_W := 0.05
const RAIL_GAP := 0.05
const FRONT_X := 0.985
const FRONT_BOTTOM := 1.2
const FRONT_Z: Array[float] = [-2.4, -1.7, -1.0, -0.3, 0.3, 1.0, 1.7, 2.4]

const CATCH_Y := 3.20
const CARRIAGE_X := 0.20
const END_BLOCK_Z := 2.85
const HANG_H := 0.70
const TINE_Z: Array[float] = [-2.05, -0.65, 0.65, 2.05]
const TINE_LEN := 0.77

const TOP_STRANDS: Array[float] = [-2.25, -1.375, 0.0, 1.375]   # boards come even-ended at -z (landing_transfer)
const TOP_PITCH := 0.20
const TOP_SPR := 0.3236068          # TOP_PITCH / (2 sin(pi / 10))
const TOP_SHAFT_Y := 5.00
const TOP_X_TAIL := 0.3
const TOP_X_HEAD := 11.3
const LUG_EVERY := 5
const LUG_FACE := 0.12              # lug's pushing face, ahead of its chain pin
const LUG_LEN := TOP_SHAFT_Y - TOP_SPR - DECK_Y - 0.01

const CREST_X := -0.58              # where the incline's lugs push boards off its crest
const PLATE_TOP := DECK_Y - 0.004  # infeed dead plate, just under the transfer chain tops
const DEAD_X0 := 0.55              # a board this far in has reached the stop

const XFER_Z: Array[float] = [-1.35, -0.3, 0.3, 1.35]
const XFER_TAIL := -0.52
const XFER_HEAD := 0.70
const XFER_PITCH := 0.0508
const XFER_SPR := 0.0508          # XFER_PITCH / (2 sin(pi / 6))
const XFER_PIN_Y := DECK_Y - 0.010
const XFER_SHAFT_Y := XFER_PIN_Y - XFER_SPR
const STOP_X := BX0 - 0.15
const STOP_ZS: Array[float] = [-2.05, -0.95, 0.6, 2.0]   # an even-ended 6 ft board meets the first two
const STOP_PIVOT := Vector3(STOP_X - 0.03, DECK_Y - DECK_T - 0.08, 0.0)

const HAUL_STRANDS: Array[float] = [-2.25, -1.375, 0.0, 1.375]   # boards come even-ended at -z (landing_transfer)
const HAUL_PITCH := 0.10
const HAUL_SPR := 0.10              # HAUL_PITCH / (2 sin(pi / 6))
const HAUL_SHAFT_Y := 0.22
const HAUL_X_TAIL := BX0 - 0.40
const HAUL_X_HEAD := BX0 + NB + 4.40
const HAUL_TOP := HAUL_SHAFT_Y + HAUL_SPR + 0.012
const TABLE_X0 := BX0 + NB + 0.6
const STACK_STOP_X := HAUL_X_HEAD - HAUL_SPR - 0.25
const END_STOP_Z: Array[float] = [-1.9, -0.65, 0.65, 1.9]

const HOIST_Y := 5.75
const DRUM_R := 0.065

## Bay index = position in this list (1x4 into bay 0 ... 2x12 into bay 9).
const PROFILES: Array[String] = ["1x4", "1x6", "1x8", "1x10", "1x12", "2x4", "2x6", "2x8", "2x10", "2x12"]

# ── Settings ─────────────────────────────────────────────────────────────────
@export_group("Drives")
## Overhead lug chain speed, metres per second, when it isn't geared to a feeder (see
## ``lug_drive``). Lugs are 1 m apart, one bay pitch.
@export_range(0.1, 2.0, 0.05) var lug_chain_speed: float = 0.5
## The lug chain feeding this sorter (the board incline). The overhead lug chain is geared to
## it, one sorter lug per infeed lug, so a full infeed fills every sorter lug.
@export var lug_drive: NodePath
## How fast the overhead chain speeds up and slows down, metres per second every second.
@export_range(0.5, 10.0, 0.1) var lug_chain_acceleration: float = 2.0
## Speed of the infeed transfer chains that carry boards up to the stop.
@export_range(0.1, 3.0, 0.05) var infeed_chain_speed: float = 0.6
## Haul-out chain speed, metres per second.
@export_range(0.1, 2.0, 0.05) var haul_speed: float = 0.4
## Haul-out speed for the last half metre before the end stops or a stack already waiting
## there, so a tall narrow stack does not topple when it arrives.
@export_range(0.02, 1.0, 0.01) var haul_approach_speed: float = 0.08

@export_group("Gates and carriages")
## How far the gate arms swing down to drop a board, degrees. Far enough that the arm tips
## end up behind the board, so it falls clear of them. 50 is the most the model allows:
## past that the arms hit the carriage hanger beam below.
@export_range(20.0, 50.0, 1.0) var gate_open_deg: float = 50.0
## Gate swing speed, degrees per second, like an air cylinder: the board slides off the arms,
## hits the bay front and settles wherever it ends up.
@export_range(30.0, 1440.0, 10.0) var gate_speed_deg: float = 200.0
## The gate opens when the board's leading edge is this far short of the arm tips, metres.
@export_range(0.0, 0.6, 0.01) var gate_open_lead: float = 0.04
## Real valves and cylinders never fire quite the same twice. Each drop opens up to this much
## (metres of board travel) later or earlier than `gate_open_lead`...
@export_range(0.0, 0.4, 0.01) var gate_timing_spread: float = 0.2
## ...and swings up to this fraction faster or slower than `gate_speed_deg`, so boards land
## somewhere different each time instead of on the same spot.
@export_range(0.0, 0.8, 0.05) var gate_speed_spread: float = 0.35
## Boards per bay before the pile is lowered onto the haul-out chains.
@export_range(1, 20, 1) var max_boards_per_bay: int = 10
## Which nominal size each bay takes, bay 0 first. A size not listed goes to the bay with the
## nearest dressed size.
@export var bay_sizes: Array[String] = ["1x4", "1x6", "1x8", "1x10", "1x12", "2x4", "2x6", "2x8", "2x10", "2x12"]
## Boards per pack for each bay, same order as bay_sizes; a missing or 0 entry uses
## max_boards_per_bay. With a stacker connected, every pack is rounded to whole stacker
## layers (its boards per layer for that size), at least one layer.
@export var bay_pack_boards: Array[int] = []
## The green stacker the haul-out runs packs on to. Its surge chains take the place of the
## end table: packs leave the haul-out onto them and the bays only wait when the surge queue
## has backed up onto the haul-out.
@export var stacker: NodePath
## How long a bay's photo eye must stay blocked before its forks lower, seconds; a board
## falling past the beam doesn't count.
@export_range(0.1, 2.0, 0.05) var eye_delay: float = 0.4
## Carriage speed while stepping down for each board and returning, metres per second.
@export_range(0.05, 1.5, 0.05) var carriage_speed: float = 0.5
## Carriage speed while lowering a full stack to the haul-out chains.
@export_range(0.05, 1.5, 0.05) var discharge_speed: float = 0.6

@export_group("Debug")
## Print each board's progress (queued, released, gate opened, landed) and bay discharges.
@export var log_boards: bool = false

enum BayPhase { CATCH, FULL, LOWER, HAUL, RAISE }
enum BoardState { CARRY, DROP, LAND }

class Bay:
	var phase: int = BayPhase.CATCH
	var count: int = 0
	var size: String = ""            # nominal size this bay is collecting, "" while empty
	var eye_blocked: float = 0.0      # seconds the photo eye has been blocked
	var boards: Array[RigidBody3D] = []
	var carriage_y: float = CATCH_Y
	var gate_deg: float = 0.0
	var gate_open: bool = false
	var gate_speed: float = 200.0     # this swing's speed, deg/s

class Carried:
	var board: RigidBody3D
	var bay: int
	var state: int = BoardState.CARRY
	var timer: float = 0.0
	var open_lead: float = 0.04       # when this board's gate fires, see gate_timing_spread

var _rng := RandomNumberGenerator.new()

## True while the sorter can't take another board (its infeed transfer stopped with no bay free,
## or boards already waiting on it): the lug incline (lug_drive) holds, and it stops boards
## being pushed off its crest onto a full infeed.
var feed_hold: bool = false
## Boards that may wait on the infeed transfer before the incline holds.
@export_range(1, 6, 1) var infeed_queue_max: int = 2

var _bays: Array[Bay] = []
var _queue: Array[RigidBody3D] = []
var _carried: Array[Carried] = []
var _hauled: Dictionary = {}          # board -> seconds it has been still
var _parked: Array[RigidBody3D] = []  # boards resting on the end table
var _table_full_logged: bool = false
var _stacker: Node = null              # GreenStacker taking packs off the haul-out head
var _locked: bool = false              # stopped by the crew (lockout) to clear a jam
var _loose_t: Dictionary = {}          # board -> seconds lying still outside the sorter's hands
var _wedged_since: Dictionary = {}    # board left above the chains in a hauling bay -> clock first seen still
var _carry_check: Dictionary = {}     # carried board -> [sorter-local x, clock] when it last moved
var _tilted_since: Dictionary = {}     # board in a bay -> clock when it was first seen lying badly
## Boards come even-ended (landing_transfer): their ends line up here, sorter-local Z.
const EVEN_END_Z := -2.44
## A board settled in a bay standing up past this is a jam the crew lays flat (gate timing spreads
## make the odd one land on its edge).
const BAY_TILT_DEG := 55.0

var _top_loop: float = 0.0
var _top_span: float = TOP_X_HEAD - TOP_X_TAIL
var _top_links: int = 0
var _top_spacing: float = TOP_PITCH
var _lug_count: int = 0
var _top_dist: float = 0.0
var _top_speed: float = 0.0
var _haul_loop: float = 0.0
var _haul_links: int = 0
var _haul_spacing: float = HAUL_PITCH
var _haul_dist: float = 0.0
var _haul_current: float = 0.0
var _stop_down: bool = false
var _infeed_on: bool = true
var _infeed_current: float = 0.0
var _xfer_loop: float = 0.0
var _xfer_links: int = 0
var _xfer_spacing: float = XFER_PITCH
var _xfer_dist: float = 0.0
var _stop_deg: float = 0.0
var _visual_elapsed: float = 0.0
var _clock: float = 0.0

var _parts: Node3D
var _gates: Array[AnimatableBody3D] = []
var _carriages: Array[AnimatableBody3D] = []
var _lugs: Array[AnimatableBody3D] = []
var _lug_on_run: Array[bool] = []
var _stop: AnimatableBody3D
var _links_mm: MultiMeshInstance3D
var _lugs_mm: MultiMeshInstance3D
var _haul_mm: MultiMeshInstance3D
var _xfer_mm: MultiMeshInstance3D
var _cylinders: Array[MeshInstance3D] = []
var _rods: Array[MeshInstance3D] = []
var _cables: Array[MeshInstance3D] = []
var _shafts: Dictionary = {}


func _ready() -> void:
	_top_loop = 2.0 * _top_span + TAU * TOP_SPR
	_top_links = int(round(_top_loop / TOP_PITCH))
	_top_spacing = _top_loop / float(_top_links)
	_lug_count = floori(float(_top_links) / LUG_EVERY)
	_haul_loop = 2.0 * (HAUL_X_HEAD - HAUL_X_TAIL) + TAU * HAUL_SPR
	_haul_links = int(round(_haul_loop / HAUL_PITCH))
	_haul_spacing = _haul_loop / float(_haul_links)
	_xfer_loop = 2.0 * (XFER_HEAD - XFER_TAIL) + TAU * XFER_SPR
	_xfer_links = int(round(_xfer_loop / XFER_PITCH))
	_xfer_spacing = _xfer_loop / float(_xfer_links)
	# Park with a lug just past the stop, so none stands on the deck behind a board.
	_top_dist = fposmod(STOP_X + 0.1 - LUG_FACE - TOP_X_TAIL, _top_spacing * LUG_EVERY)

	_bays.clear()
	for i in NB:
		_bays.append(Bay.new())
	_build_parts()
	for shaft_name: String in ["TopDriveShaft", "TopTailShaft", "HaulDriveShaft", "HaulTailShaft",
			"TransferHeadShaft", "TransferTailSprockets"]:
		var shaft := find_child(shaft_name, true, false) as Node3D
		if shaft != null:
			_shafts[shaft_name] = shaft
	if Engine.is_editor_hint():
		return
	if not stacker.is_empty():
		_stacker = get_node_or_null(stacker)
	if _stacker != null:
		var stops := get_node_or_null("EndStops")
		if stops != null:
			stops.queue_free()
	var zone := get_node_or_null("InfeedZone") as Area3D
	if zone != null:
		zone.body_entered.connect(_on_infeed_body_entered)


static func bay_x(i: int) -> float:
	return BX0 + float(i) * BAY


func _on_infeed_body_entered(body: Node3D) -> void:
	var board := body as RigidBody3D
	if board == null or not board.is_in_group("cut_boards") or board.is_in_group("cut_slabs"):
		return
	if _queue.has(board) or _is_carried(board):
		return
	_queue.append(board)
	_log("queued for bay %d" % _bay_for(board), board)


# ─────────────────────────────────────────────────────────────────────────────
#  JAMS (used by the crew: game/machines/sorter/sorter_crew.gd)
# ─────────────────────────────────────────────────────────────────────────────

## Stop (lock out) or restart the sorter and the lug incline feeding it.
## One line for debug HUDs and probes.
func status_text() -> String:
	var bays := PackedStringArray()
	for i in NB:
		var b: Bay = _bays[i]
		if b.count > 0 or b.phase != BayPhase.CATCH:
			bays.append("%d:%s %d%s" % [i, BayPhase.keys()[b.phase], b.count, (" " + b.size) if b.size != "" else ""])
	return "queue %d, carried %d, infeed %s%s%s, bays [%s]" % [_queue.size(), _carried.size(),
			"on" if _infeed_on else "STOPPED", ", HOLDING incline" if feed_hold else "",
			", end table full" if _end_table_full() else "", ", ".join(bays)]


func set_locked(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	var drive := get_node_or_null(lug_drive)
	if drive != null:
		drive.set("running", not on)
	_log("sorter %s" % ("STOPPED (lockout)" if on else "restarted"))


func is_locked() -> bool:
	return _locked


## Is this board in the sorter's hands (queued, carried, in a bay, hauling or parked)?
func _owned(b: RigidBody3D) -> bool:
	if _queue.has(b) or _is_carried(b) or _hauled.has(b) or _parked.has(b):
		return true
	for bay: Bay in _bays:
		if bay.boards.has(b):
			return true
	return false


## A board handed to a lug that hasn't moved for a while (piled up at the stop, or caught) is no
## longer the sorter's: it becomes a loose deck board the crew lays in its bay by hand.
func _check_carried_progress() -> void:
	for c: Carried in _carried.duplicate():
		if c.state != BoardState.CARRY or not is_instance_valid(c.board):
			continue
		var x: float = to_local(c.board.global_position).x
		var last: Array = _carry_check.get(c.board, [x, _clock])
		# Only while the chain runs: the sorter stops it on purpose at times (gates, no bay free).
		if absf(x - float(last[0])) > 0.03 or _top_speed < 0.05:
			_carry_check[c.board] = [x, _clock]
		elif _clock - float(last[1]) > 8.0:
			_carry_check.erase(c.board)
			_carried.erase(c)
			_log("STUCK on the deck, handed to the crew", c.board)
		else:
			_carry_check[c.board] = last
	for b: Variant in _carry_check.keys():
		if not is_instance_valid(b) or not _is_carried(b):
			_carry_check.erase(b)


## Time each loose board (not the sorter's, not culled) has lain still near the sorter.
func _track_loose(delta: float) -> void:
	for b: Variant in _loose_t.keys():
		if not is_instance_valid(b):
			_loose_t.erase(b)
	for n: Node in get_tree().get_nodes_in_group("cut_boards"):
		var b := n as RigidBody3D
		if b == null or b.freeze or b.is_in_group("cull") or _owned(b):
			_loose_t.erase(b)
			continue
		var p: Vector3 = to_local(b.global_position)
		if p.x < -0.8 or p.x > HAUL_X_HEAD or absf(p.z) > 6.0 or p.y > DECK_Y + 0.6:
			_loose_t.erase(b)
			continue
		_loose_t[b] = float(_loose_t.get(b, 0.0)) + delta if b.linear_velocity.length() < 0.05 else 0.0


## The first sorter jam, or {}: "deck" a board lying loose on the deck (it missed its lug or
## its bay), "floor" a board that fell off onto the floor. "at" is in sorter coordinates.
func find_jam() -> Dictionary:
	# Highest first: off the top of a pile before the board under it.
	var loose: Array = _loose_t.keys().filter(func(b: Variant) -> bool: return is_instance_valid(b) and float(_loose_t[b]) >= 4.0)
	loose.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return a.global_position.y > b.global_position.y)
	for b: Variant in loose:
		var board := b as RigidBody3D
		var p: Vector3 = to_local(board.global_position)
		# On the deck, or caught up in a bay above the haul-out: either way the catwalk worker
		# reaches it and lays it in a bay of its size.
		if p.y > 1.0 and p.x > CREST_X and p.x < TOP_X_HEAD:
			return {"kind": "deck", "board": board, "at": p}
		if p.y < 1.0:
			return {"kind": "floor", "board": board, "at": p}
	for i in NB:
		var bay: Bay = _bays[i]
		if bay.phase != BayPhase.CATCH:
			continue
		for o: RigidBody3D in bay.boards:
			# Only boards lying loose on this bay's forks: not ones already handed on (held by the
			# haul-out or the stacker) or below the forks.
			if not is_instance_valid(o) or o.freeze or to_local(o.global_position).y < bay.carriage_y - 0.3:
				continue
			var a: float = rad_to_deg(o.global_basis.y.angle_to(Vector3.UP))
			if minf(a, 180.0 - a) < BAY_TILT_DEG or o.linear_velocity.length() > 0.05:
				_tilted_since.erase(o)
				continue
			if not _tilted_since.has(o):
				_tilted_since[o] = _clock
			elif _clock - float(_tilted_since[o]) > 2.0:
				return {"kind": "bay", "board": o, "at": to_local(o.global_position)}
	return {}


## Where a worker lays a board that landed badly in its bay: flat on top of the rest of that
## bay's pile, even-ended. It is already counted.
func restack_place(board: RigidBody3D) -> Transform3D:
	_tilted_since.erase(board)
	for i in NB:
		var bay: Bay = _bays[i]
		if bay.boards.has(board):
			var top: float = bay.carriage_y
			for o: RigidBody3D in bay.boards:
				if is_instance_valid(o) and o != board:
					top = maxf(top, to_local(o.global_position).y + float(o.get("board_thickness")) * 0.5)
			return global_transform * Transform3D(Basis(), Vector3(bay_x(i) + CARRIAGE_X + 0.35,
					top + float(board.get("board_thickness")) * 0.5 + 0.01, _even_z(board)))
	return board.global_transform


## Sorter-local Z of an even-ended board's centre.
func _even_z(board: RigidBody3D) -> float:
	return EVEN_END_Z + float(board.get("product_length")) * 0.5


## The bay a loose deck board can go in by hand (one taking its size, with room), or -1:
## then it goes to the cull pile, never into another size's pack.
func hand_bay(board: RigidBody3D) -> int:
	return _choose_bay(board)


## Where a worker puts a loose deck board by hand: flat on top of the pile in the bay taking
## its size (hand_bay), and the bay counts it.
func hand_place(board: RigidBody3D) -> Transform3D:
	var i: int = maxi(_choose_bay(board), 0)
	var bay: Bay = _bays[i]
	var top: float = bay.carriage_y
	for o: RigidBody3D in bay.boards:
		if is_instance_valid(o):
			top = maxf(top, to_local(o.global_position).y + float(o.get("board_thickness")) * 0.5)
	bay.boards.append(board)
	bay.count += 1
	if bay.count >= _bay_capacity(i):
		bay.phase = BayPhase.FULL
	_loose_t.erase(board)
	var t: float = float(board.get("board_thickness"))
	return global_transform * Transform3D(Basis(), Vector3(bay_x(i) + CARRIAGE_X + 0.35, top + t * 0.5 + 0.01, _even_z(board)))


func _log(text: String, board: RigidBody3D = null) -> void:
	if not log_boards:
		return
	var who: String = ""
	if is_instance_valid(board):
		var at: Vector3 = to_local(board.global_position)
		who = " %s %s at (%.2f, %.2f)" % [board.name, str(board.get("nominal_size")), at.x, at.y]
	print("[BinSorter %.2f] %s%s" % [_clock, text, who])


func _is_carried(board: RigidBody3D) -> bool:
	for c: Carried in _carried:
		if c.board == board:
			return true
	return false


# ─────────────────────────────────────────────────────────────────────────────
#  RUN
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	_track_loose(delta)
	if _locked:
		_top_speed = 0.0
		_haul_current = 0.0
		_infeed_current = 0.0
		for n: String in ["TransferChains", "HaulChains"]:
			var body := get_node_or_null(n) as StaticBody3D
			if body != null:
				body.constant_linear_velocity = Vector3.ZERO
		return
	_update_infeed()
	_check_carried_progress()
	# Only boards already pushed off the crest and down on the transfer count: the infeed zone
	# also reaches boards still on the incline's lugs, which only the incline can deliver.
	var waiting: int = 0
	for b: RigidBody3D in _queue:
		var p: Vector3 = to_local(b.global_position)
		if p.x > CREST_X + 0.1 and p.y < DECK_Y + 0.15:
			waiting += 1
	feed_hold = not _infeed_on or waiting >= infeed_queue_max
	var feeder := get_node_or_null(lug_drive)
	if feeder != null and "hold" in feeder:
		feeder.hold = feed_hold
	_update_top_chain(delta)
	_update_carried(delta)
	_update_bays(delta)
	_update_haul(delta)
	_drive_bodies(delta)


## Boards waiting on the infeed, oldest first. Releases the head board to the next lug,
## or asks the chain to hold when its bay has no room.
var _hold_chain: bool = false
## Set while a board would otherwise reach an open gate that is not its own.
var _gate_wait: bool = false

func _update_infeed() -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if not is_instance_valid(_queue[i]) or to_local(_queue[i].global_position).y < DECK_Y - 0.3:
			_queue.remove_at(i)
	# The head is the board furthest in, not the first seen: the infeed zone reaches back over the
	# incline crest, and a board still on the incline's lugs can't come in while it is held.
	_queue.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return _trailing(a) > _trailing(b))
	_hold_chain = false
	# The stop's fingers swing up on an arc that pokes above the deck from STOP_X - 0.05 to
	# STOP_X + 0.1; keep them down until every released board is past that, and never raise
	# them under a board that has just rolled in over them.
	var releasing: bool = false
	for c: Carried in _carried:
		if c.state == BoardState.CARRY and _trailing(c.board) < STOP_X + 0.13:
			releasing = true
	if _stop_down or _stop_deg > 0.0:
		for b: RigidBody3D in _queue:
			if _leading(b) > STOP_X - 0.06 and _trailing(b) < STOP_X + 0.13:
				releasing = true
	if not _queue.is_empty():
		var head: RigidBody3D = _queue[0]
		var bay: int = _choose_bay(head)
		var trailing: float = _trailing(head)
		var lug_face: float = _collector_face(trailing)
		# Release a board once it has reached the stop (or the end of the transfer) and its lug
		# is close behind. One still travelling in on the transfer would run on past the dropped stop
		# with no lug behind it; one not released in time would be pushed into the raised stop.
		# Its trailing edge must be past where the lugs come down: releasing it empties the
		# queue and stops the transfer, and a board left over that spot would have the next lug
		# land inside it. Every width is clear of it at the stop.
		var arrived: bool = trailing > TOP_X_TAIL + LUG_FACE + 0.01
		# Already past the stop (a lug has it): track it from here.
		var taken: bool = trailing > STOP_X
		var room: bool = bay >= 0
		if room:
			if taken or (arrived and lug_face >= trailing - 0.30):
				_queue.remove_at(0)
				var c := Carried.new()
				c.board = head
				c.bay = bay
				_bays[bay].size = str(head.get("nominal_size"))
				c.open_lead = maxf(gate_open_lead + _rng.randf_range(-0.5, 1.0) * gate_timing_spread, 0.0)
				_carried.append(c)
				releasing = true
				_log("released to the lug at %.2f" % lug_face, head)
		elif _leading(head) > TOP_X_TAIL - 0.05:
			# Every bay that could take it is busy (rare: all bays full or claimed by other sizes).
			# Too far in to hold on the transfer (the lugs come down here): stop the lug chain short
			# of it. Boards still out on the deck wait too.
			var braking: float = _top_speed * _top_speed / (2.0 * lug_chain_acceleration)
			if lug_face >= trailing - braking - 0.08:
				_hold_chain = true
		# Last resort when no bay can take it: the board waits on the stopped transfer, upstream of
		# where the lugs come down, while the boards out on the deck land and bays discharge.
		if _infeed_on == not room:
			_infeed_on = room
			_log("infeed transfer %s" % ("restarted" if room else "stopped: no bay free for its size"), head)
	elif not _infeed_on:
		_infeed_on = true
	_stop_down = releasing


## The bay a board goes to: its own size's bay, or while that one is busy (lowering a full
## pile, or holding another size), the nearest bay that is empty or already collecting this
## size and has room, like a real sorter assigning more than one bin to a product. -1 if none.
func _choose_bay(board: RigidBody3D) -> int:
	var size: String = str(board.get("nominal_size"))
	var home: int = _bay_for(board)
	for offset in NB:
		for b: int in [home + offset, home - offset]:
			if b < 0 or b >= NB or (offset == 0 and b != home):
				continue
			if _bay_has_room(b) and (_bays[b].size == "" or _bays[b].size == size):
				return b
	return -1


## Face position of the lug that will reach a board whose trailing edge is at `trailing`:
## the lead lug still behind it. Lugs still coming round the tail sprocket count as
## behind the deck start by their remaining distance.
func _collector_face(trailing: float) -> float:
	var best: float = -INF
	for k in _lug_count:
		var s: float = fposmod(_top_dist + float(k * LUG_EVERY) * _top_spacing, _top_loop)
		var face: float
		if s < _top_span:
			face = TOP_X_TAIL + s + LUG_FACE
		else:
			face = TOP_X_TAIL + LUG_FACE - (_top_loop - s)
		if face < trailing and face > best:
			best = face
	return best


## The lug chain indexes to the boards so every lug carries one and none waits: with a board
## coming in on the transfer (or nothing to do) it parks a lug at READY_FACE, coming down off
## the tail sprocket high enough for boards to pass under; the moment a board reaches the stop
## that lug comes down behind it. It also runs to carry boards on to their gates when no new
## board is on its way.
const READY_FACE := TOP_X_TAIL + LUG_FACE - 0.15

func _update_top_chain(delta: float) -> void:
	var head_arrived: bool = not _queue.is_empty() and _trailing(_queue[0]) > TOP_X_TAIL + LUG_FACE + 0.01
	var incoming: bool = not _queue.is_empty() and not head_arrived
	var target: float = lug_chain_speed
	var drive := get_node_or_null(lug_drive)
	# While this sorter holds the incline, the overhead chain is declutched from it and indexes on
	# its own, so it can work off the boards waiting on the infeed and those on its lugs.
	if drive != null and feed_hold:
		drive = null
	if drive != null:
		target = _geared_speed(drive, head_arrived, delta)
	if _hold_chain or _gate_wait:
		target = 0.0
	elif drive != null:
		pass
	elif not head_arrived and (incoming or _carried.is_empty()):
		# Park the next lug at the ready point, braking so it stops right there.
		var gap: float = _distance_to_ready()
		target = minf(lug_chain_speed, sqrt(2.0 * lug_chain_acceleration * maxf(gap - 0.002, 0.0)))
	_top_speed = move_toward(_top_speed, target, lug_chain_acceleration * delta)
	_top_dist = fposmod(_top_dist + _top_speed * delta, _top_loop)


## Lug chain speed when geared to the infeed's lug chain: one sorter lug for every infeed
## lug, so with a board in each infeed lug every sorter lug carries one. The gearing is
## trimmed board by board: when a board reaches the stop, any gap between it and the lug
## coming for it (beyond a short lead) is made up over the next few seconds, so lugs arrive
## just as boards do and nothing waits.
var _phase_debt: float = 0.0
var _measured: RigidBody3D

func _geared_speed(drive: Node, head_arrived: bool, delta: float) -> float:
	var stations: Array = drive.get("_stations")
	var loop: float = float(drive.get("_loop_len"))
	if stations.is_empty() or loop <= 0.0:
		return lug_chain_speed
	var ratio: float = (_top_spacing * LUG_EVERY) / (loop / float(stations.size()))
	var base: float = absf(float(drive.get("actual_speed"))) * ratio
	if head_arrived and _queue[0] != _measured:
		_measured = _queue[0]
		var trailing: float = _trailing(_measured)
		var gap: float = trailing - _collector_face(trailing)
		_phase_debt = clampf(_phase_debt + gap - 0.12, -0.4, _top_spacing * LUG_EVERY)
	if base < 0.01 and _queue.is_empty():
		# The infeed has stopped with nothing coming: run on to clear the deck.
		return lug_chain_speed if not _carried.is_empty() else 0.0
	var trim: float = clampf(_phase_debt * 0.8, -0.3 * base, maxf(0.6 * base, 0.15))
	_phase_debt -= trim * delta
	return maxf(base + trim, 0.0)


## Chain travel until the next lug coming round the tail reaches READY_FACE.
func _distance_to_ready() -> float:
	var best: float = INF
	for k in _lug_count:
		var s: float = fposmod(_top_dist + float(k * LUG_EVERY) * _top_spacing, _top_loop)
		var face: float = TOP_X_TAIL + s + LUG_FACE if s < _top_span else TOP_X_TAIL + LUG_FACE - (_top_loop - s)
		var d: float = READY_FACE - face
		if d >= -0.001 and d < best:
			best = d
	return best


func _update_carried(delta: float) -> void:
	var tip_y: float = DECK_Y + GATE_AXIS_DY - GATE_W * sin(deg_to_rad(gate_open_deg))
	_gate_wait = false
	var i: int = _carried.size() - 1
	while i >= 0:
		var c: Carried = _carried[i]
		i -= 1
		if not is_instance_valid(c.board):
			_carried.erase(c)
			continue
		var at: Vector3 = to_local(c.board.global_position)
		var gate_tip: float = bay_x(c.bay) + GATE_X0 + GATE_W
		match c.state:
			BoardState.CARRY:
				# A board must never meet an open gate that is not its own: pause the lug
				# chain short of it until that gate has dropped its board and closed. Should
				# it get there anyway, shut the gate in front of it.
				var lead: float = _leading(c.board)
				var braking: float = _top_speed * _top_speed / (2.0 * lug_chain_acceleration)
				for b in NB:
					if b == c.bay or _bays[b].gate_deg <= 0.0 and not _bays[b].gate_open:
						continue
					var shaft: float = bay_x(b) + GATE_X0
					if lead > shaft - 0.05 and lead < bay_x(b) + BAY:
						if _bays[b].gate_open:
							_bays[b].gate_open = false
							_log("closed gate %d ahead of a board for bay %d" % [b, c.bay], c.board)
					elif lead > shaft - 0.12 - braking and lead < shaft:
						_gate_wait = true
				# Fire early by however far the lug will push the board while the arms swing down,
				# or a narrow board rides past the tips onto the next bay's rails.
				var travel_while_opening: float = _top_speed * gate_open_deg / gate_speed_deg
				if lead >= gate_tip - c.open_lead - travel_while_opening:
					_bays[c.bay].gate_open = true
					_bays[c.bay].gate_speed = gate_speed_deg * (1.0 + _rng.randf_range(-gate_speed_spread, gate_speed_spread))
					c.state = BoardState.DROP
					_log("gate %d opened" % c.bay, c.board)
				elif at.x > TOP_X_HEAD + 0.5 or at.y < DECK_Y - 0.5:
					_carried.erase(c)      # off the end or fell somewhere else
					_log("LOST before bay %d" % c.bay, c.board)
			BoardState.DROP:
				c.timer += delta
				if at.y < tip_y - 0.05 or c.timer > 1.5:
					_bays[c.bay].gate_open = false
					c.state = BoardState.LAND
					c.timer = 0.0
			BoardState.LAND:
				c.timer += delta
				var still: bool = c.board.linear_velocity.length() < 0.15 and at.y < DECK_Y - 0.5
				var in_bay: bool = at.x > bay_x(c.bay) and at.x < bay_x(c.bay) + BAY
				if still and c.timer > 0.3 and not in_bay:
					_carried.erase(c)
					_log("LOST: came to rest outside bay %d" % c.bay, c.board)
				elif still and c.timer > 0.3:
					_land(c)
					_carried.erase(c)
					_log("landed in bay %d (%d boards)" % [c.bay, _bays[c.bay].count], c.board)
				elif c.timer > 6.0:
					_carried.erase(c)
					_log("LOST: never settled after gate %d" % c.bay, c.board)


func _land(c: Carried) -> void:
	var bay: Bay = _bays[c.bay]
	bay.boards.append(c.board)
	bay.count += 1
	if bay.count >= _bay_capacity(c.bay):
		bay.phase = BayPhase.FULL


## Photo eyes near the top of each bay: two beams across the bay (along the boards' length)
## at EYE_Y. True if a board blocks either one.
const EYE_Y := 3.55                 # below where the gate arm tips swing to
const EYE_XS: Array[float] = [0.45, 0.8]
const EYE_Z := 2.95

func _eye_blocked(bay: int) -> bool:
	var space := get_world_3d().direct_space_state
	for ex: float in EYE_XS:
		var from := to_global(Vector3(bay_x(bay) + ex, EYE_Y, -EYE_Z))
		var to := to_global(Vector3(bay_x(bay) + ex, EYE_Y, EYE_Z))
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var skip: Array[RID] = []
		for n in 4:
			query.exclude = skip
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			if (hit["collider"] as Node).is_in_group("cut_boards"):
				return true
			skip.append(hit["rid"])
	return false


## Lowest the forks index to before the bay counts as full (pile room used up).
const FORK_MIN_Y := 1.5


func _update_bays(delta: float) -> void:
	var discharging: bool = false
	for bay: Bay in _bays:
		if bay.phase in [BayPhase.LOWER, BayPhase.HAUL, BayPhase.RAISE]:
			discharging = true
	for i in NB:
		var bay: Bay = _bays[i]
		var target: float = bay.carriage_y
		var speed: float = carriage_speed
		match bay.phase:
			BayPhase.CATCH:
				# The forks hold still while the pile builds and only lower while the pile breaks
				# the photo eye near the top, until the beam is clear again.
				bay.eye_blocked = bay.eye_blocked + delta if _eye_blocked(i) else 0.0
				if bay.eye_blocked >= eye_delay:
					target = maxf(bay.carriage_y - 1.0, FORK_MIN_Y)
					if bay.carriage_y <= FORK_MIN_Y + 0.001:
						bay.phase = BayPhase.FULL
						_log("bay %d forks at their lowest: full with %d boards" % [i, bay.count])
			BayPhase.FULL:
				# One bay at a time: a lowered carriage's uprights would stop another stack.
				# Stacks stay on the end table; once their queue reaches back to the table's
				# start, wait for some to be taken away.
				if not discharging and _in_flight(i) == 0 and not _end_table_full():
					bay.phase = BayPhase.LOWER
					discharging = true
					_log("bay %d full: lowering the stack onto the haul-out chains (worst tilt %.0f deg)" % [i, _worst_tilt(bay.boards)])
			BayPhase.LOWER:
				target = HAUL_TOP - 0.1
				speed = discharge_speed
				# Never set a stack down on moving chains (still hauling an earlier stack out):
				# its bottom boards would be dragged out from under the rest. Wait just above.
				if not _hauled.is_empty() or _haul_current > 0.0:
					target = maxf(HAUL_TOP + 0.03, minf(bay.carriage_y, target))
				# Creep through the last stretch so the forks set the stack down on the chains
				# instead of dropping it.
				if bay.carriage_y < HAUL_TOP + 0.12:
					speed = 0.05
				if is_equal_approx(bay.carriage_y, target):
					bay.phase = BayPhase.HAUL
					_log("bay %d stack on the haul-out chains (worst tilt %.0f deg)" % [i, _worst_tilt(bay.boards)])
					for b: RigidBody3D in bay.boards:
						if is_instance_valid(b):
							_hauled[b] = 0.0
			BayPhase.HAUL:
				target = HAUL_TOP - 0.1
				var clear: bool = true
				for b: RigidBody3D in bay.boards.duplicate():
					# A board that fell off the pile below the chains can't be hauled; don't wait on it.
					if is_instance_valid(b) and to_local(b.global_position).y < HAUL_TOP - 0.05:
						continue
					# One left wedged up in the bay (the stack tumbled as it went down) won't come out
					# on the chains: after a few seconds still, it is the crew's to take out by hand.
					if is_instance_valid(b) and to_local(b.global_position).y > HAUL_TOP + 0.3 							and b.linear_velocity.length() < 0.05:
						if not _wedged_since.has(b):
							_wedged_since[b] = _clock
						elif _clock - float(_wedged_since[b]) > 5.0:
							_wedged_since.erase(b)
							bay.boards.erase(b)
							_hauled.erase(b)
							_log("wedged in bay %d, left for the crew" % i, b)
							continue
					elif is_instance_valid(b):
						_wedged_since.erase(b)
					if is_instance_valid(b) and _trailing(b) < bay_x(i) + BAY + 0.05:
						clear = false
				if clear:
					bay.phase = BayPhase.RAISE
					_log("bay %d stack hauled clear, forks going back up (worst tilt %.0f deg)" % [i, _worst_tilt(bay.boards)])
					bay.boards.clear()
					bay.count = 0
					bay.size = ""
			BayPhase.RAISE:
				target = CATCH_Y
				if is_equal_approx(bay.carriage_y, target):
					bay.phase = BayPhase.CATCH
		bay.carriage_y = move_toward(bay.carriage_y, target, speed * delta)
		var gate_target: float = gate_open_deg if bay.gate_open else 0.0
		bay.gate_deg = move_toward(bay.gate_deg, gate_target, (bay.gate_speed if bay.gate_open else gate_speed_deg) * delta)


## Largest angle, degrees, between a board's face and level (debug log only).
func _worst_tilt(boards: Array[RigidBody3D]) -> float:
	var worst: float = 0.0
	for b: RigidBody3D in boards:
		if is_instance_valid(b):
			var a: float = rad_to_deg(b.global_basis.y.angle_to(Vector3.UP))
			worst = maxf(worst, minf(a, 180.0 - a))
	return worst


func _in_flight(bay: int) -> int:
	var n: int = 0
	for c: Carried in _carried:
		if c.bay == bay:
			n += 1
	return n


func _bay_has_room(bay: int) -> bool:
	return _bays[bay].phase == BayPhase.CATCH and _bays[bay].count + _in_flight(bay) < _bay_capacity(bay)


func _bay_capacity(bay: int) -> int:
	var wanted: int = bay_pack_boards[bay] if bay < bay_pack_boards.size() and bay_pack_boards[bay] > 0 else max_boards_per_bay
	if _stacker == null:
		return wanted
	# Feeding the stacker, every pack is whole layers (the stacker's boards per layer for the
	# size in the bay), so a size change on the stacker always comes between layers. A set pack
	# size is rounded to the nearest whole layers; the default is as many layers as fit in
	# max_boards_per_bay. Never less than one layer.
	var size: String = _bays[bay].size if bay < _bays.size() and _bays[bay].size != "" else bay_sizes[mini(bay, bay_sizes.size() - 1)]
	var per: int = int((_stacker.call("layer_plan", size) as Vector2i).x)
	var layers: int = roundi(float(wanted) / per) if bay < bay_pack_boards.size() and bay_pack_boards[bay] > 0 		else floori(float(wanted) / per)
	return per * maxi(layers, 1)


## The haul-out chains run while a stack is moving on them and stop once every stack has
## come to rest against the end stops (or the stack ahead of it).
func _update_haul(delta: float) -> void:
	if _stacker != null:
		_update_haul_to_stacker(delta)
		return
	for b: Variant in _hauled.keys():
		if not is_instance_valid(b):
			_hauled.erase(b)
			continue
		var board := b as RigidBody3D
		if _stacker != null and _trailing(board) > HAUL_X_HEAD:
			# Off the haul-out and on the surge chains: the stacker's now.
			_hauled.erase(b)
			_stacker.call("receive", board)
			continue
		var moving: bool = absf(board.linear_velocity.x) > 0.03 or to_local(board.global_position).y > HAUL_TOP + 0.6
		_hauled[b] = 0.0 if moving or _haul_current < haul_approach_speed * 0.5 else float(_hauled[b]) + delta
		if float(_hauled[b]) > 0.5:
			_hauled.erase(b)
			if to_local(board.global_position).x > TABLE_X0:
				_parked.append(board)
	var run: bool = false
	for bay: Bay in _bays:
		if bay.phase == BayPhase.HAUL:
			run = true
	run = run or not _hauled.is_empty()
	var target: float = 0.0
	if run:
		target = haul_approach_speed if _stack_arriving() else haul_speed
	_haul_current = move_toward(_haul_current, target, 0.25 * delta)
	_haul_dist = fposmod(_haul_dist + _haul_current * delta, _haul_loop)


## With a green stacker: each stack set down on the haul-out is run straight on to the
## stacker's surge chains (no waiting for other bays). Every board is followed until it is
## off the haul-out head, then handed to the stacker. The chains only stop when the surge
## queue has backed up to the haul-out head; they slow for the last half metre before it.
func _update_haul_to_stacker(delta: float) -> void:
	_parked.clear()
	for b: Variant in _hauled.keys():
		if not is_instance_valid(b):
			_hauled.erase(b)
			continue
		var board := b as RigidBody3D
		if _trailing(board) > HAUL_X_HEAD:
			_hauled.erase(b)
			_stacker.call("receive", board)
			_log("handed to the green stacker", board)
		elif to_local(board.global_position).y < HAUL_TOP - 0.15:
			_hauled.erase(b)          # fell off the chains
	var target: float = 0.0
	if not _hauled.is_empty() and not bool(_stacker.call("is_locked")):
		var back: float = float(_stacker.call("surge_back"))
		var lead: float = -INF
		for b: Variant in _hauled.keys():
			lead = maxf(lead, _leading(b as RigidBody3D))
		var room: float = back - lead
		if room < 0.05:
			target = 0.0
		elif room < 0.5 + _haul_current * _haul_current / (2.0 * 0.25):
			target = haul_approach_speed
		else:
			target = haul_speed
	_haul_current = move_toward(_haul_current, target, 0.25 * delta)
	_haul_dist = fposmod(_haul_dist + _haul_current * delta, _haul_loop)


## Has the queue of stacks on the end table reached back to the table's start?
func _end_table_full() -> bool:
	if _stacker != null:
		return bool(_stacker.call("surge_full"))
	for p: RigidBody3D in _parked:
		if is_instance_valid(p) and _trailing(p) < TABLE_X0 + 0.5:
			if not _table_full_logged:
				_table_full_logged = true
				_log("end table full: bays wait to discharge until stacks are taken away")
			return true
	_table_full_logged = false
	return false


## Is a moving stack within half a metre of the end stops or of a stack waiting there?
## (Plus the distance the chains need to slow down.)
func _stack_arriving() -> bool:
	for i in range(_parked.size() - 1, -1, -1):
		if not is_instance_valid(_parked[i]):
			_parked.remove_at(i)
	var margin: float = 0.5 + _haul_current * _haul_current / (2.0 * 0.25)
	for b: Variant in _hauled.keys():
		var board := b as RigidBody3D
		if not is_instance_valid(board):
			continue
		var lead: float = _leading(board)
		var obstacle: float = STACK_STOP_X if _stacker == null else float(_stacker.call("surge_back"))
		for p: RigidBody3D in _parked:
			var t: float = _trailing(p)
			if t > lead - 0.05 and t < obstacle:
				obstacle = t
		if obstacle - lead < margin:
			return true
	return false


## Move every driven body to where this tick's state says it is.
func _drive_bodies(delta: float) -> void:
	# The transfer runs while it has a board to carry (or is bringing one to the stop).
	_infeed_current = move_toward(_infeed_current, infeed_chain_speed if _infeed_on and not _queue.is_empty() else 0.0, 2.0 * delta)
	_xfer_dist = fposmod(_xfer_dist + _infeed_current * delta, _xfer_loop)
	var transfer := get_node_or_null("TransferChains") as StaticBody3D
	if transfer != null:
		transfer.constant_linear_velocity = global_basis.x * _infeed_current
	var haul := get_node_or_null("HaulChains") as StaticBody3D
	if haul != null:
		haul.constant_linear_velocity = global_basis.x * _haul_current

	var stop_target: float = 70.0 if _stop_down else 0.0
	_stop_deg = move_toward(_stop_deg, stop_target, 420.0 * delta)
	_place_stop()
	for i in NB:
		_place_gate(i)
		_place_carriage(i)
	for k in _lugs.size():
		_place_lug(k)

	var top_turn: float = _top_speed * delta / TOP_SPR
	var haul_turn: float = _haul_current * delta / HAUL_SPR
	var xfer_turn: float = _infeed_current * delta / XFER_SPR
	for shaft_name: String in _shafts:
		var turn: float = top_turn if shaft_name.begins_with("Top") else (-haul_turn if shaft_name.begins_with("Haul") else -xfer_turn)
		(_shafts[shaft_name] as Node3D).rotate_z(turn)
	_visual_elapsed += delta
	if _visual_elapsed >= 1.0 / 30.0 and (_top_speed > 0.0 or _haul_current > 0.0 or _infeed_current > 0.0):
		_visual_elapsed = 0.0
		_place_chain_visuals()


# ─────────────────────────────────────────────────────────────────────────────
#  BOARDS
# ─────────────────────────────────────────────────────────────────────────────

## Board width runs along sorter X (boards travel broadside).
func _half_width(board: RigidBody3D) -> float:
	return maxf(float(board.get("board_width")), 0.05) * 0.5


func _trailing(board: RigidBody3D) -> float:
	return to_local(board.global_position).x - _half_width(board)


func _leading(board: RigidBody3D) -> float:
	return to_local(board.global_position).x + _half_width(board)


## One nominal size per bay (bay_sizes). Anything else goes to the bay with the nearest
## dressed size.
func _bay_for(board: RigidBody3D) -> int:
	var nominal: String = str(board.get("nominal_size"))
	var index: int = bay_sizes.find(nominal)
	if index >= 0 and index < NB:
		return index
	index = 0
	var t: float = float(board.get("board_thickness"))
	var w: float = float(board.get("board_width"))
	var best: float = INF
	for i in mini(bay_sizes.size(), NB):
		if not CutBoardScript.LUMBER_SPECS.has(bay_sizes[i]):
			continue
		var spec: Dictionary = CutBoardScript.LUMBER_SPECS[bay_sizes[i]]
		var d: float = absf(float(spec["thickness"]) - t) * 4.0 + absf(float(spec["width"]) - w)
		if d < best:
			best = d
			index = i
	return index


# ─────────────────────────────────────────────────────────────────────────────
#  CHAIN PATHS
# ─────────────────────────────────────────────────────────────────────────────

## Overhead loop from the tail sprocket's bottom tangent: working run +X, head wrap,
## return run -X along the race, tail wrap.
func _top_path(s: float) -> Vector2:
	s = fposmod(s, _top_loop)
	var arc: float = PI * TOP_SPR
	if s < _top_span:
		return Vector2(TOP_X_TAIL + s, TOP_SHAFT_Y - TOP_SPR)
	s -= _top_span
	if s < arc:
		var phi: float = -PI * 0.5 + s / TOP_SPR
		return Vector2(TOP_X_HEAD + TOP_SPR * cos(phi), TOP_SHAFT_Y + TOP_SPR * sin(phi))
	s -= arc
	if s < _top_span:
		return Vector2(TOP_X_HEAD - s, TOP_SHAFT_Y + TOP_SPR)
	s -= _top_span
	var phi2: float = PI * 0.5 + s / TOP_SPR
	return Vector2(TOP_X_TAIL + TOP_SPR * cos(phi2), TOP_SHAFT_Y + TOP_SPR * sin(phi2))


## Haul-out loop from the tail sprocket's top tangent: carrying run +X, head wrap,
## return run -X underneath, tail wrap.
func _haul_path(s: float) -> Vector2:
	s = fposmod(s, _haul_loop)
	var span: float = HAUL_X_HEAD - HAUL_X_TAIL
	var arc: float = PI * HAUL_SPR
	if s < span:
		return Vector2(HAUL_X_TAIL + s, HAUL_SHAFT_Y + HAUL_SPR)
	s -= span
	if s < arc:
		var phi: float = PI * 0.5 - s / HAUL_SPR
		return Vector2(HAUL_X_HEAD + HAUL_SPR * cos(phi), HAUL_SHAFT_Y + HAUL_SPR * sin(phi))
	s -= arc
	if s < span:
		return Vector2(HAUL_X_HEAD - s, HAUL_SHAFT_Y - HAUL_SPR)
	s -= span
	var phi2: float = -PI * 0.5 - s / HAUL_SPR
	return Vector2(HAUL_X_TAIL + HAUL_SPR * cos(phi2), HAUL_SHAFT_Y + HAUL_SPR * sin(phi2))


## Transfer chain loop from the tail's top tangent: carrying run +X, head wrap, return run
## -X underneath, tail wrap.
func _xfer_path(s: float) -> Vector2:
	s = fposmod(s, _xfer_loop)
	var span: float = XFER_HEAD - XFER_TAIL
	var arc: float = PI * XFER_SPR
	if s < span:
		return Vector2(XFER_TAIL + s, XFER_PIN_Y)
	s -= span
	if s < arc:
		var phi: float = PI * 0.5 - s / XFER_SPR
		return Vector2(XFER_HEAD + XFER_SPR * cos(phi), XFER_SHAFT_Y + XFER_SPR * sin(phi))
	s -= arc
	if s < span:
		return Vector2(XFER_HEAD - s, XFER_SHAFT_Y - XFER_SPR)
	s -= span
	var phi2: float = -PI * 0.5 - s / XFER_SPR
	return Vector2(XFER_TAIL + XFER_SPR * cos(phi2), XFER_SHAFT_Y + XFER_SPR * sin(phi2))


## Link frame: origin on pin 1, +X along the chord to pin 2, +Z along the pin.
func _link_frame(p1: Vector2, p2: Vector2, z: float) -> Transform3D:
	var d: Vector2 = (p2 - p1).normalized()
	var ux := Vector3(d.x, d.y, 0.0)
	var uz := Vector3.BACK
	return Transform3D(Basis(ux, uz.cross(ux), uz), Vector3(p1.x, p1.y, z))


# ─────────────────────────────────────────────────────────────────────────────
#  BUILD
# ─────────────────────────────────────────────────────────────────────────────

func _build_parts() -> void:
	var old := get_node_or_null("RuntimeParts")
	if old != null:
		old.free()
	_parts = Node3D.new()
	_parts.name = "RuntimeParts"
	add_child(_parts)
	_gates.clear()
	_carriages.clear()
	_lugs.clear()
	_lug_on_run.clear()
	_cylinders.clear()
	_rods.clear()
	_cables.clear()

	var arm_grip := _physics_material(0.3)
	var steel_grip := _physics_material(0.6)
	var grey := _material(Color(0.09, 0.1, 0.12), 0.3, 0.55)
	var bright := _material(Color(0.5, 0.5, 0.5), 1.0, 0.3)
	var wire := _material(Color(0.12, 0.12, 0.13), 0.9, 0.4)

	for i in NB:
		var gate := _body("Gate_%02d" % i, arm_grip)
		gate.add_child(GateScene.instantiate())
		var top: float = -GATE_AXIS_DY
		for z: float in GATE_ARM_Z:
			var arm := CollisionShape3D.new()
			arm.shape = lead_in_shape(Vector3(0.0, top - 0.03, z - RAIL_W * 0.5), Vector3(GATE_W, top, z + RAIL_W * 0.5))
			gate.add_child(arm)
		_gates.append(gate)
		_place_gate(i)

		var carriage := _body("Carriage_%02d" % i, steel_grip)
		carriage.add_child(CarriageScene.instantiate())
		for z: float in TINE_Z:
			_box(carriage, Vector3(TINE_LEN * 0.5, -0.035, z), Vector3(TINE_LEN, 0.07, 0.08))
			_box(carriage, Vector3(-0.04, (HANG_H - 0.07) * 0.5, z), Vector3(0.08, HANG_H + 0.07, 0.09))
		_box(carriage, Vector3(-0.03, HANG_H + 0.07, 0.0), Vector3(0.12, 0.14, 2.0 * END_BLOCK_Z))
		_carriages.append(carriage)
		_place_carriage(i)

		for _side in 2:
			_cylinders.append(_rod_mesh(0.035, grey))
			_rods.append(_rod_mesh(0.014, bright))
			_cables.append(_rod_mesh(0.008, wire))
		# Photo eye on each beam: sensor on the drive side, reflector on the catwalk side.
		for ex: float in EYE_XS:
			for side in 2:
				var eye := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.05, 0.06, 0.04) if side == 0 else Vector3(0.06, 0.06, 0.01)
				eye.mesh = box
				eye.material_override = grey if side == 0 else _material(Color(0.7, 0.1, 0.05), 0.2, 0.4)
				eye.position = Vector3(bay_x(i) + ex, EYE_Y, -EYE_Z - 0.03 if side == 0 else EYE_Z + 0.01)
				_parts.add_child(eye)

	# Overhead lugs: one body per lug position, a pusher on each of the three strands. The
	# model's lug clears the deck by 10 mm; its collision reaches down to 2 mm (it only ever
	# meets boards, never the deck) so it squarely catches a 19 mm board.
	var lug_grip := _physics_material(0.4)
	# Collision reaches 3 cm below the deck line (the lug never meets the deck, only boards), so a
	# thin board that has settled a little into its support is pushed square on its back edge;
	# with the lug's bottom corner on its top edge it was being driven down into the deck.
	var lug_reach: float = LUG_LEN + 0.04
	for k in _lug_count:
		var lug := _body("Lug_%02d" % k, lug_grip)
		for z: float in TOP_STRANDS:
			_box(lug, Vector3(0.085, -0.06 - (lug_reach - 0.06) * 0.5, z), Vector3(0.07, lug_reach - 0.06, 0.10))
		_lugs.append(lug)
		_lug_on_run.append(true)
		_place_lug(k)

	_stop = _body("InfeedStop", steel_grip)
	var stop_model: Node3D = StopScene.instantiate()
	stop_model.position = -STOP_PIVOT
	_stop.add_child(stop_model)
	var finger_bottom: float = STOP_PIVOT.y
	var finger_top: float = DECK_Y + 0.06
	for z: float in STOP_ZS:
		_box(_stop, Vector3(STOP_X - 0.025, (finger_bottom + finger_top) * 0.5, z) - STOP_PIVOT,
			Vector3(0.05, finger_top - finger_bottom, 0.05))
	_place_stop()

	_links_mm = _multimesh("TopChainLinks", TopLinkScene, (_top_links - _lug_count) * TOP_STRANDS.size())
	_lugs_mm = _multimesh("TopChainLugs", TopLugScene, _lug_count * TOP_STRANDS.size())
	_haul_mm = _multimesh("HaulChainLinks", HaulLinkScene, _haul_links * HAUL_STRANDS.size())
	_xfer_mm = _multimesh("TransferChainLinks", TransferLinkScene, _xfer_links * XFER_Z.size())
	_place_chain_visuals()


func _body(body_name: String, mat: PhysicsMaterial) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = body_name
	body.sync_to_physics = true
	body.physics_material_override = mat
	_parts.add_child(body)
	return body


func _box(parent: Node3D, centre: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = centre
	parent.add_child(node)


func _physics_material(friction: float) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce = 0.0
	return mat


func _material(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _rod_mesh(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_parts.add_child(mi)
	return mi


## Stretch a unit cylinder between two sorter-local points.
func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var axis: Vector3 = b - a
	var length: float = axis.length()
	if length < 0.001:
		mi.visible = false
		return
	var y: Vector3 = axis / length
	var x: Vector3 = Vector3.BACK.cross(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.transform = Transform3D(Basis(x, y * length, x.cross(y)), (a + b) * 0.5)


func _multimesh(mm_name: String, source: PackedScene, count: int) -> MultiMeshInstance3D:
	var root: Node = source.instantiate()
	var mesh: Mesh = null
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (child as MeshInstance3D).mesh
		break
	root.free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	_parts.add_child(mmi)
	return mmi


# ─────────────────────────────────────────────────────────────────────────────
#  PLACE
# ─────────────────────────────────────────────────────────────────────────────

func _place_gate(i: int) -> void:
	var deg: float = _bays[i].gate_deg if i < _bays.size() else 0.0
	var axis := Vector3(bay_x(i) + GATE_X0, DECK_Y + GATE_AXIS_DY, 0.0)
	_gates[i].transform = Transform3D(Basis(Vector3.BACK, -deg_to_rad(deg)), axis)
	# Cylinder barrel pinned on the next deck beam, rod to the lever pin on the shaft.
	var a: float = deg_to_rad(deg)
	var pin := Vector2(
		GATE_LEVER_PIN.x * cos(a) + GATE_LEVER_PIN.y * sin(a),
		-GATE_LEVER_PIN.x * sin(a) + GATE_LEVER_PIN.y * cos(a))
	var anchor := Vector2(bay_x(i + 1) - 0.035, DECK_Y - 0.15)
	var pin_world := Vector2(axis.x, axis.y) + pin
	var mid: Vector2 = anchor + (pin_world - anchor) * 0.55
	for side in 2:
		var z: float = -GATE_CYL_Z if side == 0 else GATE_CYL_Z
		var index: int = i * 2 + side
		if index < _cylinders.size():
			_span(_cylinders[index], Vector3(anchor.x, anchor.y, z), Vector3(mid.x, mid.y, z))
			_span(_rods[index], Vector3(mid.x, mid.y, z), Vector3(pin_world.x, pin_world.y, z))


func _place_carriage(i: int) -> void:
	var y: float = _bays[i].carriage_y if i < _bays.size() else CATCH_Y
	_carriages[i].transform = Transform3D(Basis(), Vector3(bay_x(i) + CARRIAGE_X, y, 0.0))
	var cable_x: float = bay_x(i) + 0.06 + DRUM_R
	for side in 2:
		var z: float = -END_BLOCK_Z if side == 0 else END_BLOCK_Z
		var index: int = i * 2 + side
		if index < _cables.size():
			_span(_cables[index], Vector3(cable_x, HOIST_Y, z), Vector3(cable_x, y + HANG_H + 0.30, z))


func _place_lug(k: int) -> void:
	var s: float = _top_dist + float(k * LUG_EVERY) * _top_spacing
	var frame: Transform3D = _link_frame(_top_path(s), _top_path(s + _top_spacing), 0.0)
	_lugs[k].transform = frame
	# Only lugs on the working run can push; the rest ride round with the chain. A lug coming
	# down off the tail sprocket onto a board rolling in underneath it stays passive until
	# the board has run out ahead of it, then pushes it from behind; switched on inside the
	# board it would press it down into the transfer and jam it.
	var on_run: bool = fposmod(s, _top_loop) < _top_span
	if on_run and not _lug_on_run[k] and _board_under_lug(frame.origin.x):
		on_run = false
	if _lug_on_run[k] != on_run:
		_lug_on_run[k] = on_run
		for shape: Node in _lugs[k].get_children():
			(shape as CollisionShape3D).disabled = not on_run


## Is any board the sorter knows about under the pusher of a lug whose pin is at `pin_x`?
func _board_under_lug(pin_x: float) -> bool:
	var boards: Array[RigidBody3D] = _queue.duplicate()
	for c: Carried in _carried:
		boards.append(c.board)
	for b: RigidBody3D in boards:
		# Overlapping the pusher, not merely just ahead of its face (that board it must push).
		if is_instance_valid(b) and _leading(b) > pin_x + 0.04 and _trailing(b) < pin_x + LUG_FACE - 0.005 \
				and to_local(b.global_position).y > DECK_Y - 0.05:
			return true
	return false


func _place_stop() -> void:
	_stop.transform = Transform3D(Basis(Vector3.BACK, -deg_to_rad(_stop_deg)), STOP_PIVOT)


func _place_chain_visuals() -> void:
	var link_i: int = 0
	var lug_i: int = 0
	for k in _top_links:
		var s: float = _top_dist + float(k) * _top_spacing
		var p1: Vector2 = _top_path(s)
		var p2: Vector2 = _top_path(s + _top_spacing)
		for z: float in TOP_STRANDS:
			var t: Transform3D = _link_frame(p1, p2, z)
			if k % LUG_EVERY == 0:
				_lugs_mm.multimesh.set_instance_transform(lug_i, t)
				lug_i += 1
			else:
				_links_mm.multimesh.set_instance_transform(link_i, t)
				link_i += 1
	var h: int = 0
	for k in _haul_links:
		var s: float = _haul_dist + float(k) * _haul_spacing
		var p1: Vector2 = _haul_path(s)
		var p2: Vector2 = _haul_path(s + _haul_spacing)
		for z: float in HAUL_STRANDS:
			_haul_mm.multimesh.set_instance_transform(h, _link_frame(p1, p2, z))
			h += 1
	var x: int = 0
	for k in _xfer_links:
		var s: float = _xfer_dist + float(k) * _xfer_spacing
		var p1: Vector2 = _xfer_path(s)
		var p2: Vector2 = _xfer_path(s + _xfer_spacing)
		for z: float in XFER_Z:
			_xfer_mm.multimesh.set_instance_transform(x, _link_frame(p1, p2, z))
			x += 1


# ─────────────────────────────────────────────────────────────────────────────
#  SAVED COLLISION (run from dev/tools/build_bin_sorter_scene.gd)
# ─────────────────────────────────────────────────────────────────────────────

## Adds the sorter's static collision to `root` and owns it, so it saves with the scene.
static func build_static_colliders(root: Node3D) -> void:
	for old_name: String in ["Deck", "InfeedRolls", "TransferChains", "HaulChains", "EndStops", "InfeedZone"]:
		var old := root.get_node_or_null(old_name)
		if old != null:
			root.remove_child(old)
			old.free()

	# Deck: dead plate, wear rails between the gates, deck support beams and bay fronts.
	var deck := StaticBody3D.new()
	deck.name = "Deck"
	deck.physics_material_override = _static_material(0.3, false)     # UHMW: boards slide on it
	_attach(root, deck)
	# Collision runs on up to the gate shaft's hub (5 mm short of the arms), so no board
	# edge can drop into the gap the model leaves there for the hub.
	# Over the transfer the plate's collision sits well below the chain tops: boards pressing
	# into the narrow chains under 4.5 g (Jolt lets contacts sink a little) would otherwise
	# settle onto the plate and stop while the chains slid under them.
	_span_box(root, deck, "DeadPlateAtCrest", Vector3(CREST_X, PLATE_TOP - DECK_T, -DECK_HALF),
		Vector3(XFER_TAIL, PLATE_TOP, DECK_HALF))
	_span_box(root, deck, "DeadPlateUnderTransfer", Vector3(XFER_TAIL, DECK_Y - 0.065, -DECK_HALF),
		Vector3(XFER_HEAD + 0.03, DECK_Y - 0.035, DECK_HALF))
	# From the transfer's head on, the collision is at deck height (a few mm above the plate you
	# see) so a thin board meets the first gate's arms level, not edge-on.
	_lead_in(root, deck, "DeadPlate", Vector3(XFER_HEAD + 0.03, DECK_Y - DECK_T, -DECK_HALF),
		Vector3(BX0 + GATE_X0 - 0.005, DECK_Y, DECK_HALF))
	var spans: Array[Vector2] = []
	for i in range(1, NB):
		spans.append(Vector2(bay_x(i) - (BAY - GATE_X0 - GATE_W) + 0.005, bay_x(i) + GATE_X0 - 0.005))
	spans.append(Vector2(BX0 + NB - (BAY - GATE_X0 - GATE_W) + 0.005, TOP_X_HEAD - 0.03))
	for n in spans.size():
		for zi in GATE_ARM_Z.size():
			var z: float = GATE_ARM_Z[zi]
			_lead_in(root, deck, "Rail_%02d_%d" % [n, zi], Vector3(spans[n].x, DECK_Y - DECK_T, z - RAIL_W * 0.5),
				Vector3(spans[n].y, DECK_Y, z + RAIL_W * 0.5))
	for i in NB + 1:
		_span_box(root, deck, "DeckBeam_%02d" % i, Vector3(bay_x(i) - 0.05, DECK_Y - DECK_T - 0.18, -COL_Z),
			Vector3(bay_x(i) + 0.05, DECK_Y - DECK_T, COL_Z))
	var front_top: float = DECK_Y - DECK_T - 0.18 - 0.05
	for i in NB:
		for z: float in FRONT_Z:
			_span_box(root, deck, "BayFront_%02d" % i, Vector3(bay_x(i) + FRONT_X - 0.01, FRONT_BOTTOM, z - 0.025),
				Vector3(bay_x(i) + FRONT_X + 0.01, front_top, z + 0.025))

	# Live chain transfer: the carrying run of each smooth-top chain, 2 mm proud of the dead
	# plate. Its speed is set as the body's constant velocity; with modest grip a board held
	# at the stop just lets the chains slide on under it.
	var transfer := StaticBody3D.new()
	transfer.name = "TransferChains"
	transfer.physics_material_override = _static_material(0.5, false)
	_attach(root, transfer)
	for z: float in XFER_Z:
		_span_box(root, transfer, "Chain", Vector3(XFER_TAIL, XFER_PIN_Y - 0.008, z - 0.012),
			Vector3(XFER_HEAD, XFER_PIN_Y + 0.008, z + 0.012))

	# Haul-out drag chains: the carrying run of each strand. Low friction, like a real
	# accumulating chain: plenty to carry a stack, without crushing the queue on the end table
	# when the chains slide on under it.
	var haul := StaticBody3D.new()
	haul.name = "HaulChains"
	haul.physics_material_override = _static_material(0.35, false)
	_attach(root, haul)
	for z: float in HAUL_STRANDS:
		_span_box(root, haul, "Strand", Vector3(HAUL_X_TAIL, HAUL_TOP - 0.024, z - 0.025), Vector3(HAUL_X_HEAD, HAUL_TOP, z + 0.025))

	# End table stops the stacks run up against.
	var stops := StaticBody3D.new()
	stops.name = "EndStops"
	_attach(root, stops)
	for z: float in END_STOP_Z:
		_span_box(root, stops, "Stop", Vector3(STACK_STOP_X, 0.0, z - 0.08), Vector3(STACK_STOP_X + 0.12, 0.9, z + 0.08))

	# Boards entering the infeed are queued from here.
	var zone := Area3D.new()
	zone.name = "InfeedZone"
	zone.collision_layer = 0
	zone.collision_mask = 1
	_attach(root, zone)
	_span_box(root, zone, "CollisionShape3D", Vector3(CREST_X - 0.14, DECK_Y - 0.05, -DECK_HALF),
		Vector3(STOP_X + 0.05, DECK_Y + 0.5, DECK_HALF))


static func _attach(root: Node3D, node: Node, parent: Node = null) -> void:
	(parent if parent != null else root).add_child(node, true)
	node.owner = root


## Wear-strip collision from p0 (low corner) to p1 (high corner) whose upstream (-X) end
## is chamfered down: a board's leading edge rides up the lead-in instead of butting
## into a square end when it crosses from one support to the next.
static func lead_in_shape(p0: Vector3, p1: Vector3, lead: float = 0.06, drop: float = 0.02) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(p0.x, p0.y, p0.z), Vector3(p0.x, p0.y, p1.z), Vector3(p1.x, p0.y, p0.z), Vector3(p1.x, p0.y, p1.z),
		Vector3(p1.x, p1.y, p0.z), Vector3(p1.x, p1.y, p1.z), Vector3(p0.x + lead, p1.y, p0.z), Vector3(p0.x + lead, p1.y, p1.z),
		Vector3(p0.x, p1.y - drop, p0.z), Vector3(p0.x, p1.y - drop, p1.z)])
	return shape


static func _lead_in(root: Node3D, body: Node3D, shape_name: String, p0: Vector3, p1: Vector3) -> void:
	var node := CollisionShape3D.new()
	node.name = shape_name
	node.shape = lead_in_shape(p0, p1)
	_attach(root, node, body)


static func _span_box(root: Node3D, body: Node3D, shape_name: String, p0: Vector3, p1: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = (p1 - p0).abs()
	var node := CollisionShape3D.new()
	node.name = shape_name
	node.shape = shape
	node.position = (p0 + p1) * 0.5
	_attach(root, node, body)


## `rough` makes the surface grip with the higher friction of the pair (driven surfaces);
## otherwise the lower one wins, so a slippery surface stays slippery under any board.
static func _static_material(friction: float, rough: bool = true) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = friction
	mat.rough = rough
	mat.bounce = 0.0
	return mat
