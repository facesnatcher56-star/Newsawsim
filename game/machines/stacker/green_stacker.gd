@tool
class_name GreenStacker
extends Node3D

## Green stacker line after the bin sorter. Model and layout: dev/blender/green_stacker/
## stacker_build.py, in the sorter's own local frame (+X board travel, +Y up, +Z along the
## board length), so this node takes the sorter's transform.
##
## Every step of the board path is a physical contact; this script runs the drives:
## 1. Surge chains: the sorter's haul-out runs each pack on to the surge chains, where packs
##    queue against the pack stop. When the unscrambler pocket runs low the stop drops; a short
##    run-out at the head (faster) pulls the front pack away from the queue so the stop can
##    come back up behind it, and the pack tips off the head into the pocket.
## 2. Unscrambler: the incline chains run up through the pile in the pocket; each lug is only
##    as tall as half a 2x, so it carries one board and any board riding on top slides back.
##    Over the head the board drops onto a powered dead plate and the stacker infeed chains.
## 3. Infeed: the line-up drum rolls drive every board endwise against the line-up fence, so
##    all board ends are even. Past the course divider the layer-forming chains run faster, which
##    opens a gap after each board. The overhead course divider's fingers hang over the
##    chains at the doubles gauge: a single board passes under, a board riding on another is
##    held back and drops onto the chains behind it. Once a layer's worth has passed, the
##    fingers drop into the gap and hold the next boards. The layer gathers against the layer
##    stops, and only a whole layer of one size, every board flat and square, goes to the forks.
##    Every other layer is even-ended at the far (+Z) end instead: the ending drums between the
##    forming chains rise under the gathered layer, lift it off the chains and drive it endwise
##    against the far fence, then drop back. A package of mixed lengths so gets its short boards
##    at both ends, both faces even every other layer, instead of all the holes on one face.
## 4. Fork cycle: the layer stops drop, the forks lift the layer and carry it out over the
##    hoist, the pull-back fence drops behind it and the forks pull back: the fence holds the
##    layer and it falls onto the package. The stick gates drop a stick on every stick line,
##    and the hoist lowers one board plus one stick.
## 5. After package_layers layers (or when the next layer is another size) the hoist lowers the
##    package onto the outfeed chains, which run it out to the landing deck; the landing lift
##    raises it off the chains for the forklift.
## Steps 1-3 are all physics. From step 4 the stacker holds the layer (guided layer drop): the
## boards are squared up, carried out on the forks, held by the fence and set straight down
## on the package; sticks come down the same way. The package is moved as one with the hoist,
## outfeed and landing lift, so it always comes out square.

const FrameScene := preload("res://game/assets/models/green_stacker/stacker_frame.glb")
const SurgeStopScene := preload("res://game/assets/models/green_stacker/stacker_surge_stop.glb")
const LayerStopsScene := preload("res://game/assets/models/green_stacker/stacker_layer_stops.glb")
const DIVIDER_MODEL := "res://game/assets/models/green_stacker/stacker_course_divider.glb"
const ForksScene := preload("res://game/assets/models/green_stacker/stacker_forks.glb")
const TrolleyScene := preload("res://game/assets/models/green_stacker/stacker_fork_trolley.glb")
const FenceScene := preload("res://game/assets/models/green_stacker/stacker_fence.glb")
const GatesScene := preload("res://game/assets/models/green_stacker/stacker_stick_gates.glb")
const HoistScene := preload("res://game/assets/models/green_stacker/stacker_hoist.glb")
const LandingScene := preload("res://game/assets/models/green_stacker/stacker_landing_lift.glb")
const LinkScene := preload("res://game/assets/models/green_stacker/stacker_link.glb")
const LugScene := preload("res://game/assets/models/green_stacker/stacker_uns_lug.glb")
const RollScene := preload("res://game/assets/models/green_stacker/stacker_roll.glb")
const END_LIFT_MODEL := "res://game/assets/models/green_stacker/stacker_ending_lift.glb"
const END_ROLL_MODEL := "res://game/assets/models/green_stacker/stacker_ending_roll.glb"
const FAR_FENCE_MODEL := "res://game/assets/models/green_stacker/stacker_far_fence.glb"
const StickScene := preload("res://game/assets/models/green_stacker/stacker_stick.glb")
const CutBoardScript := preload("res://game/lumber/cut_board.gd")

const INCH := 0.0254
# ── Surge ────────────────────────────────────────────────────────────────────
const SURGE_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const SURGE_SPR := 0.10
const SURGE_SHAFT_Y := 0.217
const SURGE_TOP := 0.332
const SURGE_TAIL := 15.30
const SURGE_HEAD := 21.30
const SURGE_STOP_X := 21.0                 # pack stop finger face
const SURGE_STOP_Z: Array[float] = [-2.1, -1.05, 0.0, 1.05, 2.1]
const SURGE_STOP_DROP := 0.22
const RUNOUT_X := 20.85                    # faster run-out from here to the head
const POCKET_LIP := Vector2(21.45, 0.302)
# ── Unscrambler ──────────────────────────────────────────────────────────────
const UNS_Z: Array[float] = [-2.1, -1.05, 0.0, 1.05, 2.1]
const UNS_ANGLE := 0.61087                 # 35 degrees
const UNS_SPR := 0.13066
const UNS_PLATE_H := 0.015
const UNS_LUG_EVERY := 6
const UNS_LUG_HOLD := 0.045                # lug face above the chain tops (the model's lug): the pocket adjusters set how much stands above them
# Pocket adjusters (stacker_build.build_pocket_adjusters): tapered plates between the strands
# over the upper incline, raised square to the bed for the board thickness.
const ADJ_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const ADJ_W := 0.10
const ADJ_T0 := 0.9                        # up the incline from the foot pin line: just above the pocket pile
const ADJ_TAPER := 0.35
const ADJ_T1 := 2.7                        # low on the incline, so a shed board drops straight back into the pocket
const ADJ_DEPTH := 0.05
const ADJ_MODEL := "res://game/assets/models/green_stacker/stacker_pocket_adjusters.glb"
const UNS_HEAD := Vector2(25.35, 2.46934)
const UNS_FOOT := Vector2(21.85197, 0.02)
const CHAIN_PITCH := 0.10
const CHAIN_PLATE_H := 0.015
# ── Infeed ───────────────────────────────────────────────────────────────────
const INFEED_TOP := 2.60
const INF_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const INF_SPR := 0.13066
const INF_SHAFT_Y := 2.45434
const INF_TAIL := 25.58
const INF_HEAD := 29.15
const LINEUP_FENCE_Z := -2.48
const ROLL_Z: Array[float] = [-2.1, -1.05, 0.0, 1.05, 2.1]
const ROLL_R := 0.075
const ROLL_X0 := 25.92
const ROLL_X1 := 26.88
const LAYER_STOP_X := 28.99
const HOLD_STOP_X := 27.33                 # course divider fingers' upstream face
const DIVIDER_DOWN := 0.03                 # dividing: finger tips this far under the chain tops
const DIVIDER_FINGER_H := 0.21
# Far-end ending (stacker_build.build_far_fence / build_ending_lift): a fence at the 16 ft
# board's far end, and pop-up drum rolls between the forming chains that drive a gathered layer
# against it.
const FAR_FENCE_Z := LINEUP_FENCE_Z + 16.0 * 0.3048 + 0.005
const END_Z: Array[float] = [-2.32, -1.31, -0.26, 0.26, 1.31, 2.32]
const END_X0 := 27.45
const END_X1 := 28.98
const END_TOP := INFEED_TOP + 0.018        # raised drum tops: the layer rides clear of the chains
const END_DROP := 0.05                     # lowered: drum tops 3.2 cm under the chain tops
const END_TIME := 0.4                      # air cylinders: seconds up or down
const END_TIMEOUT := 20.0
# Short-board idler rails (stacker_build.SKID_*, idler_rail): rows of free-spinning rollers at
# +-SKID_Z, their tops level with the chain tops, that carry the short end of a 6 ft board whose
# middle would otherwise sit over a single chain strand. The idlers turn as a board rides over
# them, so they don't drag its end (which would skew the layer): frictionless colliders.
const SKID_DROP := 0.002
const SKID_Z := 2.21
const SKID_X0 := 26.99
const SKID_X1 := 29.10
# ...and on the surge chains' side guides (stacker_build.SURGE_SKID_*), from the tail to short of
# the pack stop.
const SURGE_SKID_Z := 2.25
const SURGE_SKID_X0 := SURGE_TAIL + SURGE_SPR + 0.08
const SURGE_SKID_X1 := SURGE_STOP_X - 0.05
# Holdover rack off the +Z catwalk's outer rail (stacker_build.build_holdover_rack): three arms,
# a pin at each end. Boards lie along X, two across between the pins.
const RACK_ARM_X: Array[float] = [25.9, 27.6, 29.3]
const RACK_Y := 3.25                       # arm tops
const RACK_Z := Vector2(3.97, 4.42)
const RACK_PIN_H := 0.30
const ODD_PILE := Vector3(18.44, 0.0, 5.9)     # floor pile beside the pocket for odd-size boards, along X: clear of both crews' walkways
const STOP_Z: Array[float] = [-1.31, -0.26, 0.26, 1.31]   # course divider fingers
# Layer stop fingers: each between a chain way and the next fork tine out, so every board from 6 ft
# up, even-ended at either fence, bears on two fingers either side of its chain strand.
const LAYER_STOP_Z: Array[float] = [-1.84, -0.79, 0.79, 1.84]
const STOP_RISE := 0.12
const STOP_DROP := 0.17                    # down: finger tops 5 cm under the chain tops
# ── Forks, fence, sticks, hoist ──────────────────────────────────────────────
const FORK_Z: Array[float] = [-2.1, -1.05, 0.0, 1.05, 2.1]
const FORK_X0 := 27.40
const FORK_LEN := 1.55
const FORK_STROKE := 1.50
const FORK_T := 0.05
const FORK_HOME_TOP := 2.59
const FORK_LIFT := 0.035
const FORK_PARK := -0.035                  # tines sit this far below their model home between cycles
const FENCE_X := 29.10
const FENCE_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const FENCE_DOWN := 2.629
const FENCE_RAISE := 0.20
const STICK_Z: Array[float] = [-2.40, -1.80875, -1.2175, -0.62625, -0.035, 0.55625, 1.1475, 1.73875, 2.33]
const STICK_X0 := 29.15
const STICK_LEN := 1.3208
const STICK_T := 0.01905
const STICK_W := 0.0381
const MAG_BOTTOM := 2.75
const HOIST_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const HOIST_X0 := 29.15
const HOIST_X1 := 30.60
const HOIST_TOP := 2.565
const HOIST_LOW := 0.40
const HOIST_SHAFTS: Array[String] = ["SurgeHeadShaft", "SurgeTailShaft", "UnscramblerHeadShaft", "UnscramblerFootShaft",
	"InfeedHeadShaft", "InfeedTailSprockets", "OutfeedHeadShaft", "OutfeedTailShaft"]
# ── Outfeed and landing ──────────────────────────────────────────────────────
const OUT_Z: Array[float] = [-2.1, -1.05, 0.0, 1.05, 2.1]
const OUT_SPR := 0.10
const OUT_SHAFT_Y := 0.335
const OUT_TOP := 0.45
const OUT_TAIL := 28.95
const OUT_HEAD := 36.60
const LANDING_STOP_X := 36.45
const LAND_RISE := 0.18
const LAND_Z: Array[float] = [-1.575, -0.525, 0.525, 1.575]
const LAND_X0 := 33.0
const LAND_X1 := 36.45
const LAND_TOP_DOWN := 0.42
## Widest layer the forks and hoist take, metres.
const MAX_LAYER_W := 1.42

# ── Settings ─────────────────────────────────────────────────────────────────
@export_group("Package")
## Package width, inches: boards per layer = as many as fit (a 1x10 is 5 wide in 52 in).
@export_range(12.0, 56.0, 0.5) var package_width_in: float = 52.0
## Layers per package.
@export_range(1, 40, 1) var package_layers: int = 31
## Per-size overrides: nominal size -> Vector2i(boards per layer, layers). Sizes not listed use
## package_width_in and package_layers.
@export var size_overrides: Dictionary = {}
## Seconds a package sits on the landing deck before it is taken away (stand-in for the
## forklift); 0 = it stays until take_package() is called.
@export_range(0.0, 300.0, 1.0) var auto_take_after: float = 0.0

@export_group("Drives")
@export_range(0.05, 1.0, 0.05) var surge_speed: float = 0.3
@export_range(0.2, 2.0, 0.05) var runout_speed: float = 1.0
## One lug (one board) every 0.6 m.
@export_range(0.1, 1.5, 0.05) var unscrambler_speed: float = 0.6
@export_range(0.2, 2.0, 0.05) var infeed_speed: float = 1.0
## Layer-forming chains past the course divider: faster, to open a gap after each board.
@export_range(0.2, 3.0, 0.05) var forming_speed: float = 1.3
## Endwise speed the line-up rolls give a board.
@export_range(0.1, 1.5, 0.05) var lineup_speed: float = 0.3
## Endwise speed the far-end ending drums give a layer.
@export_range(0.1, 1.5, 0.05) var ending_speed: float = 0.5
## Even-end every other layer of a package at the far end, so a package of mixed lengths has
## its short boards at both ends instead of a hole-riddled face at one.
@export var alternate_ends: bool = true
@export_range(0.05, 1.0, 0.05) var outfeed_speed: float = 0.35
@export_range(0.05, 1.0, 0.05) var hoist_speed: float = 0.35

@export_group("Jams")
## Steer boards square on the chains automatically. Off: boards twist and jam as they do in a
## real mill, and the crew (stacker_crew.gd) stops the line and clears them.
@export var auto_square: bool = false
## Course divider gauge, in board thicknesses: while boards pass, the finger tips sit this high
## over the chains, so a single board goes under and one riding on another is held back.
@export_range(1.2, 1.9, 0.05) var doubles_gauge: float = 1.5

@export_group("Debug")
@export var log_events: bool = false

enum Phase { FORM, STOPS_DOWN, LIFT, EXTEND, FENCE_DOWN, RETRACT, SETTLE, STICKS, STICK_SETTLE, LOWER, RESET }
const PHASE_TIME: Dictionary = {
	Phase.STOPS_DOWN: 0.25, Phase.LIFT: 0.4, Phase.EXTEND: 1.5, Phase.FENCE_DOWN: 0.35, Phase.RETRACT: 1.5,
	Phase.SETTLE: 0.6, Phase.STICKS: 0.9, Phase.STICK_SETTLE: 0.2, Phase.LOWER: 0.6, Phase.RESET: 0.4,
}


## Chain loop round two equal sprockets: carrying run on top from a to b, wrap round b,
## return underneath, wrap round a (the same path as stacker_build.loop_path).
class ChainLoop:
	var a: Vector2
	var b: Vector2
	var r: float
	var d: Vector2
	var n: Vector2
	var span: float
	var arc: float
	var total: float
	var phi0: float
	var links: int
	var spacing: float
	var dist: float = 0.0
	var speed: float = 0.0

	func _init(p_a: Vector2, p_b: Vector2, p_r: float, pitch: float) -> void:
		a = p_a
		b = p_b
		r = p_r
		d = (b - a).normalized()
		n = Vector2(-d.y, d.x)
		span = (b - a).length()
		arc = PI * r
		phi0 = atan2(n.y, n.x)
		total = 2.0 * span + 2.0 * arc
		links = int(round(total / pitch))
		spacing = total / float(links)

	func at(s: float) -> Vector2:
		s = fposmod(s, total)
		if s < span:
			return a + n * r + d * s
		s -= span
		if s < arc:
			var phi: float = phi0 - s / r
			return b + Vector2(cos(phi), sin(phi)) * r
		s -= arc
		if s < span:
			return b - n * r - d * s
		s -= span
		var phi2: float = phi0 + PI - s / r
		return a + Vector2(cos(phi2), sin(phi2)) * r


var _clock: float = 0.0
var _boards: Array[RigidBody3D] = []
var _wet: PhysicsMaterial

var _surge: ChainLoop
var _uns: ChainLoop
var _inf: ChainLoop
var _out: ChainLoop
var _roll_turn: float = 0.0
var _visual_elapsed: float = 0.0

var _surge_stop: float = 0.0        # 0 up, 1 down
var _surge_target: float = 0.0
var _layer_stop: float = 0.0
var _hold_stop: float = 1.0             # course divider: 1 at the doubles gauge, 0 down dividing
var _hold_target: float = 1.0
var _gauge_t: float = 0.038             # board thickness the divider is gauged to
var _fork_dx: float = 0.0
var _fork_dy: float = FORK_PARK
var _fence_up: float = FENCE_RAISE
var _gate: float = 0.0
var _placer_dy: float = 0.0               # stick placer travel below its home (negative: down)
var _hoist_y: float = HOIST_TOP
var _landing_up: float = 0.0
var _uns_on: bool = true

var _phase: int = Phase.FORM
var _phase_t: float = 0.0
var _layer: Array[RigidBody3D] = []
var _layer_size: String = ""
var _passed: Array[RigidBody3D] = []    # boards past the course divider for the forming layer
var _still_t: float = 0.0
var _wait_t: float = 0.0                 # layer held at the divider, not yet taken
var _gather_t: float = 0.0               # forming chains run on gathering the layer since the divider dropped
var _wait_why: String = ""
var _stall_logged: bool = false
var _locked: bool = false                # stopped by the crew (lockout) to clear a jam
var _stall_count: int = -1
var _stall_t: float = 0.0
var _infeed_hold: bool = false          # infeed chains slowed while the divider finds a gap
var _fault: String = ""                 # what's wrong with the layer waiting for the forks ("extra", "short")
var _fault_boards: Array[RigidBody3D] = []
var _rider_t: Dictionary = {}           # board -> seconds it has been riding on another
var _twist_t: Dictionary = {}           # board -> seconds it has sat skewed and still
var _rack: Array[RigidBody3D] = []      # boards on the holdover rack
var _odd: int = 0                       # boards on the odd-size floor pile
var _fill_back: float = 0.0             # filling a short layer from the rack: upstream edge so far
var _reserved: Dictionary = {}          # board in a worker's hands -> stacker x of the infeed spot it's going to
var _new_sticks: Array[RigidBody3D] = []
var _layer_from: Array[Transform3D] = []   # gripped layer: where each board was (stacker space)
var _layer_home: Array[Vector3] = []      # ...and its squared-up place on the forming chains
var _layer_back: float = 0.0              # upstream edge of the squared layer
var _layer_far: bool = false               # gripped layer is even-ended at the far fence
var _prev_far: bool = false                # the package's top layer is even-ended at the far fence
var _ending: bool = false                  # far-end ending drums working on the waiting layer
var _end_up: float = 0.0                   # ending drums: 0 down, 1 raised
var _end_target: float = 0.0
var _end_t: float = 0.0
var _end_squaring: bool = false            # squaring the layer before the drums rise
var _square_from: Array[Transform3D] = []
var _square_to: Array[Transform3D] = []
var _end_turn: float = 0.0

var _package: Array[RigidBody3D] = []   # frozen into the package on the hoist
var _pkg_size: String = ""
var _pkg_layers: int = 0
var _pkg_t: float = 0.0
var _finish: bool = false
var _lowering: int = 0                  # 1: hoist taking a finished package down; 2: going back up
var _outgoing: Array[RigidBody3D] = []  # on the outfeed chains
var _out_front: float = 0.0
var _out_back: float = 0.0
var _landed: Array[RigidBody3D] = []
var _landed_t: float = 0.0
var _deck_package: RigidBody3D           # merged package body on the landing deck
var _packages_done: int = 0

var _parts: Node3D
var _surge_chains: StaticBody3D
var _runout: StaticBody3D
var _uns_chains: StaticBody3D
var _dead_plate: StaticBody3D
var _inf_chains: StaticBody3D
var _form_chains: StaticBody3D
var _rolls: StaticBody3D
var _end_rolls: StaticBody3D               # ending drum tops (moved with the lift)
var _end_roll_nodes: Array[Node3D] = []
var _surge_stop_body: AnimatableBody3D
var _layer_stop_body: AnimatableBody3D
var _divider: AnimatableBody3D
var _adjusters: AnimatableBody3D
var _adj_up: float = 0.0                 # pocket adjusters' raise, metres along the bed normal
var _adj_target: float = 0.0
var _forks: AnimatableBody3D
var _fence: AnimatableBody3D
var _hoist: AnimatableBody3D
var _trolley: Node3D
var _gates: Node3D
var _landing: AnimatableBody3D
var _out_chains: StaticBody3D
var _lugs: Array[AnimatableBody3D] = []
var _lug_on: Array[bool] = []
var _roll_nodes: Array[Node3D] = []
var _shafts: Dictionary = {}
var _link_mms: Dictionary = {}          # ChainLoop -> [MultiMeshInstance3D, strands]
var _lug_mm: MultiMeshInstance3D


func _ready() -> void:
	_surge = ChainLoop.new(Vector2(SURGE_TAIL, SURGE_SHAFT_Y), Vector2(SURGE_HEAD, SURGE_SHAFT_Y), SURGE_SPR, CHAIN_PITCH)
	_uns = ChainLoop.new(UNS_FOOT, UNS_HEAD, UNS_SPR, CHAIN_PITCH)
	_inf = ChainLoop.new(Vector2(INF_TAIL, INF_SHAFT_Y), Vector2(INF_HEAD, INF_SHAFT_Y), INF_SPR, CHAIN_PITCH)
	_out = ChainLoop.new(Vector2(OUT_TAIL, OUT_SHAFT_Y), Vector2(OUT_HEAD, OUT_SHAFT_Y), OUT_SPR, CHAIN_PITCH)
	_wet = PhysicsMaterial.new()
	_wet.friction = 0.25          # green lumber slides on itself
	_wet.rough = false
	_wet.bounce = 0.0
	_build_parts()
	for shaft_name: String in HOIST_SHAFTS:
		var shaft := find_child(shaft_name, true, false) as Node3D
		if shaft != null:
			_shafts[shaft_name] = shaft
	_place_all()
	_place_chain_visuals()


# ─────────────────────────────────────────────────────────────────────────────
#  INTERFACE (the sorter, demos)
# ─────────────────────────────────────────────────────────────────────────────

## Take charge of a board arriving on the surge chains (the sorter hands each one over as it
## leaves the haul-out).
func receive(board: RigidBody3D) -> void:
	if board == null or _boards.has(board):
		return
	_boards.append(board)
	board.physics_material_override = _wet



## Trailing edge (stacker x) of the rearmost pack standing in the surge queue, or INF. Only
## boards wholly on the surge chains count: one still being handed over from the haul-out is
## the haul-out's to move, and counting it would hold the haul-out that has to finish moving it.
func surge_back() -> float:
	var back: float = INF
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.y > 0.15 and p.y < 1.0 and p.x - _half_w(b) >= SURGE_TAIL - 0.01 and p.x < SURGE_HEAD + 0.1 \
				and absf(b.linear_velocity.length()) < 0.05:
			back = minf(back, p.x - _half_w(b))
	return back


## True when the surge queue reaches back to the surge tail: the sorter must hold its packs.
func surge_full() -> bool:
	return _locked or surge_back() < SURGE_TAIL + 0.5


## The forklift: clear the package off the landing deck, and any loose board that came out
## with it.
func take_package() -> void:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if not _landed.has(b) and p.x > LAND_X0 - 0.3 and p.x < OUT_HEAD + 0.3 and p.y < 1.3:
			_landed.append(b)
	for b: RigidBody3D in _landed:
		if is_instance_valid(b):
			_boards.erase(b)
			b.queue_free()
	_landed.clear()
	if is_instance_valid(_deck_package):
		_deck_package.queue_free()
	_deck_package = null
	_log("package taken off the landing deck")


func packages_done() -> int:
	return _packages_done


## Boards per layer and layers for a nominal size.
func layer_plan(size: String) -> Vector2i:
	if size_overrides.has(size):
		var o: Variant = size_overrides[size]
		if o is Vector2i:
			return o
	var w: float = 0.184
	if CutBoardScript.LUMBER_SPECS.has(size):
		w = float(CutBoardScript.LUMBER_SPECS[size]["width"])
	var per: int = maxi(1, floori(minf(package_width_in * INCH, MAX_LAYER_W) / w + 0.001))
	return Vector2i(per, package_layers)


# ─────────────────────────────────────────────────────────────────────────────
#  RUN
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	for i in range(_boards.size() - 1, -1, -1):
		if not is_instance_valid(_boards[i]):
			_boards.remove_at(i)
	if _locked:
		_hold_everything()
		return
	if auto_square:
		_square_boards()
	_update_surge(delta)
	_update_unscrambler(delta)
	_update_forming(delta)
	_update_cycle(delta)
	_update_package(delta)
	_drive(delta)


# ─────────────────────────────────────────────────────────────────────────────
#  JAMS (used by the crew: game/machines/stacker/stacker_crew.gd)
# ─────────────────────────────────────────────────────────────────────────────

## Stop (lock out) or restart the whole line: every chain, roll and the layer cycle.
func set_locked(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	_stall_t = 0.0
	_stall_logged = false
	_log("line %s" % ("STOPPED (lockout)" if on else "restarted"))


func is_locked() -> bool:
	return _locked


func _hold_everything() -> void:
	for loop: ChainLoop in [_surge, _uns, _inf, _out]:
		loop.speed = 0.0
	for body: StaticBody3D in [_surge_chains, _runout, _uns_chains, _dead_plate, _inf_chains, _form_chains, _rolls, _end_rolls, _out_chains]:
		body.constant_linear_velocity = Vector3.ZERO


## The first jam on the line, or {} if none. Kinds:
##   "twisted"  a board on the infeed or forming chains turned more than 8 degrees off square
##   "rider"    a board riding up on another on the infeed or at the stops
##   "dropped"  a board that fell off the line onto the floor
##   "stalled"  the layer hasn't grown for a while with boards waiting upstream
## "at" is where a worker has to get to (stacker frame), "board" the board to deal with.
func find_jam() -> Dictionary:
	var dt: float = get_physics_process_delta_time()
	for b: RigidBody3D in _boards:
		if not is_instance_valid(b) or b.freeze or b.get("board_width") == null:
			continue
		var p: Vector3 = _local(b)
		# A board turned crosswise on the surge chains (lying along the travel) would wedge across
		# the pocket and stall the unscrambler: it is taken off before it gets there.
		var on_surge: bool = p.x > SURGE_TAIL - 0.3 and p.x < SURGE_STOP_X + 0.3 and p.y > 0.2 and p.y < 1.2 and absf(p.z) < 2.8
		if on_surge and absf(_twist(b)) > deg_to_rad(30.0):
			return {"kind": "twisted", "board": b, "at": p}
		var on_infeed: bool = p.x > UNS_HEAD.x + 0.1 and p.x < LAYER_STOP_X + 0.1 and p.y > 2.4 and p.y < 3.0
		# A board a little off square squares itself when it reaches the divider fingers or the
		# layer stops (the chains push it flat against them), and the grip squares a layer
		# anyway. Only a board turned right across, or one skewed and stuck while the chains run
		# on under it, is a jam.
		var twist: float = absf(_twist(b))
		if on_infeed and twist > deg_to_rad(8.0):
			# Held still on purpose (against the dropped divider, or in the layer at the stops)
			# doesn't count: only stuck upstream with the divider up and the chains running.
			var held: bool = p.x > HOLD_STOP_X or _hold_stop < 0.5 or _inf.speed < 0.1
			_twist_t[b] = float(_twist_t.get(b, 0.0)) + dt if b.linear_velocity.length() < 0.05 and not held else 0.0
			if twist > deg_to_rad(25.0) or float(_twist_t[b]) > 3.0:
				return {"kind": "twisted", "board": b, "at": p}
		else:
			_twist_t.erase(b)
		# A board riding on another upstream of the divider is the divider's to sort out: it
		# holds the rider back until the board under it has gone. Only one past the divider, or
		# one still riding after a few seconds, needs the crew.
		# (The ending drums lift a waiting layer END_TOP - INFEED_TOP clear of the chains.)
		var lift: float = (END_TOP - INFEED_TOP) * _end_up if p.x > HOLD_STOP_X else 0.0
		if on_infeed and (p.y > INFEED_TOP + float(b.get("board_thickness")) * 0.5 + 0.025 + lift or _overlaps_below(b)):
			_rider_t[b] = float(_rider_t.get(b, 0.0)) + dt
			if p.x > HOLD_STOP_X or float(_rider_t[b]) > 4.0:
				# Riding on a board of another size in the layer: that one is the stray. It
				# goes on the holdover rack (the crew lifts this one off it first).
				var under: RigidBody3D = _board_below(b)
				if under != null and _layer_size != "" and _local(under).x > HOLD_STOP_X 						and str(under.get("nominal_size")) != _layer_size:
					_fault = "extra"
					_fault_boards = [under]
					return {"kind": "extra", "board": under, "boards": [under], "at": _local(under)}
				if log_events and not b.has_meta("rider_logged"):
					b.set_meta("rider_logged", true)
					_log("rider %s %s at x%.3f y%.3f on %s" % [b.name, b.get("nominal_size"), p.x, p.y,
						"nothing (raised)" if under == null else "%s %s at x%.3f y%.3f" % [under.name, under.get("nominal_size"), _local(under).x, _local(under).y]])
				return {"kind": "rider", "board": b, "at": p}
		else:
			_rider_t.erase(b)
		# The pocket floor is at ground level: a board lying in the bottom of the pocket is still
		# in the line (a pocket tangle is the stall check's), not one that fell off.
		var pocket: bool = p.x < UNS_FOOT.x + 0.8 and absf(p.z) < 2.6
		if p.y < 0.25 and p.x > SURGE_HEAD + 0.6 and not pocket and absf(p.z) < 7.0 and b.linear_velocity.length() < 0.05:
			return {"kind": "dropped", "board": b, "at": p}
	if _fault != "":
		var left: Array[RigidBody3D] = []
		for b: RigidBody3D in _fault_boards:
			if not is_instance_valid(b):
				continue
			# fill: still on the rack; short / extra: still on the forming chains.
			if (b.is_in_group("holdover") if _fault == "fill" else (not b.is_in_group("holdover") and _local(b).x > HOLD_STOP_X)):
				left.append(b)
		if left.is_empty():
			_fault = ""
		else:
			return {"kind": _fault, "board": left[0], "boards": left, "at": _local(left[0])}
	if _phase == Phase.FORM and _line_sizes().is_empty():
		_stall_t = 0.0                        # nothing on its way: waiting for lumber, not jammed
	if _phase == Phase.FORM and _stall_t > 25.0 and not _passed.is_empty():
		if log_events and not _stall_logged:
			_stall_logged = true
			var parts: PackedStringArray = []
			for b: RigidBody3D in _boards:
				var q: Vector3 = _local(b)
				if q.x > 25.3 and q.x < 29.2 and q.y > 2.4 and q.y < 3.0:
					parts.append("%s%s x%.3f y%.3f v%.2f tw%.0f" % ["*" if _passed.has(b) else "", b.get("nominal_size"), q.x, q.y,
						b.linear_velocity.length(), rad_to_deg(_twist(b))])
			_log("STALL: divider %.2f->%.0f gauge t %.3f tip y %.3f, passed %d %s, infeed %.2f hold %s: %s" % [_hold_stop, _hold_target,
				_gauge_t, _divider.position.y + INFEED_TOP - DIVIDER_DOWN, _passed.size(), _layer_size, _inf.speed, _infeed_hold, ", ".join(parts)])
		var tangle: Array[RigidBody3D] = _pocket_tangle()
		if tangle.is_empty():
			for b: RigidBody3D in _boards:
				if b.freeze or _package.has(b):
					continue
				var q: Vector3 = _local(b)
				if q.y > 2.45 and q.y < 2.8 and q.x > UNS_HEAD.x and q.x - _half_w(b) < HOLD_STOP_X + 0.05 						and (_overlaps_below(b) or q.x + _half_w(b) > HOLD_STOP_X + 0.01):
					tangle.append(b)
		if not tangle.is_empty():
			return {"kind": "stalled", "board": tangle[0], "boards": tangle, "at": _local(tangle[0])}
		var at := Vector3(UNS_HEAD.x + 0.4, INFEED_TOP, 0.0)
		return {"kind": "stalled", "board": null, "at": at}
	return {}


## A board's twist off the line, radians (its length axis against the stacker's Z, from above).
func _twist(b: RigidBody3D) -> float:
	var up: Vector3 = global_basis.y
	var axis: Vector3 = b.global_basis.x
	axis -= up * axis.dot(up)
	if axis.length_squared() < 0.01:
		return PI * 0.5
	axis = axis.normalized()
	var line: Vector3 = global_basis.z
	if axis.dot(line) < 0.0:
		axis = -axis
	return line.signed_angle_to(axis, up)


## Where a worker puts a board back: square on the infeed chains in the first clear gap
## upstream of the course divider, or, if there's no room, on the pile in the unscrambler pocket.
func put_back_spot(b: RigidBody3D) -> Transform3D:
	var w: float = float(b.get("board_width"))
	var t: float = float(b.get("board_thickness"))
	var length: float = float(b.get("product_length"))
	var square := Basis(Vector3.UP, -PI * 0.5)
	# Only boards of the size now running go back in the line; another size would only end up
	# in the wrong layer, so it goes on the odd-boards pile on the floor beside the pocket.
	var running: Dictionary = _line_sizes()
	if _layer_size != "":
		running[_layer_size] = true
	if not running.is_empty() and not running.has(str(b.get("nominal_size"))):
		_boards.erase(b)
		_passed.erase(b)
		b.add_to_group("odd_boards")
		_odd += 1
		_log("odd-size board put on the floor pile by the pocket (%d there)" % _odd, b)
		return global_transform * Transform3D(Basis(), ODD_PILE + Vector3(0.0, t * (float(_odd) - 0.5) + 0.01 * _odd, 0.0))
	var x: float = HOLD_STOP_X - 0.15 - w * 0.5
	for r: Variant in _reserved.keys():
		if not is_instance_valid(r) or not (r as RigidBody3D).freeze:
			_reserved.erase(r)                  # set down: it's on the chains now, seen below
	while x > INF_TAIL + 0.3:
		var clear: bool = true
		for r: Variant in _reserved.keys():
			if r != b and absf(float(_reserved[r]) - x) < w + 0.03:
				clear = false
		for o: RigidBody3D in _boards:
			if o == b or not is_instance_valid(o) or o.get("board_width") == null:
				continue
			var q: Vector3 = _local(o)
			if q.y > 2.4 and q.y < 3.0 and absf(q.x - x) < (w + float(o.get("board_width"))) * 0.5 + 0.03:
				clear = false
				break
		if clear:
			_reserved[b] = x                    # the other worker may be putting one back too
			return global_transform * Transform3D(square, Vector3(x, INFEED_TOP + t * 0.5 + 0.003, LINEUP_FENCE_Z + length * 0.5))
		x -= 0.1
	return global_transform * Transform3D(square, Vector3(UNS_FOOT.x - 0.25, 0.75, 0.0))


## Squares up every board on the infeed and lays riders down behind the queue (a worker
## clearing a stall walks along and straightens the line by hand).
func straighten_infeed() -> Array[RigidBody3D]:
	var moved: Array[RigidBody3D] = []
	for b: RigidBody3D in _boards:
		if not is_instance_valid(b) or b.freeze or b.get("board_width") == null:
			continue
		var p: Vector3 = _local(b)
		if p.x > UNS_HEAD.x - 0.3 and p.x < LAYER_STOP_X + 0.1 and p.y > 2.3 and p.y < 3.0:
			moved.append(b)
	return moved


## Keep boards square to the line, as real multi-strand chains and the line-up fence do: a
## board's twist (its length axis off the stacker's Z, seen from above) is steered back with
## a yaw rate. Nothing else is touched, so the chains still carry it and it can still tumble,
## roll and tip. Without this, small friction differences between strands twist a board
## until it wedges across the forming chains.
func _square_boards() -> void:
	var up: Vector3 = global_basis.y
	var line: Vector3 = global_basis.z
	for b: RigidBody3D in _boards:
		if b.freeze or b.get("board_width") == null:
			continue
		var axis: Vector3 = b.global_basis.x            # cut_board: length along its local X
		axis -= up * axis.dot(up)
		if axis.length_squared() < 0.25:
			continue                                     # standing on end: leave it
		axis = axis.normalized()
		if axis.dot(line) < 0.0:
			axis = -axis
		var twist: float = line.signed_angle_to(axis, up)
		var w: Vector3 = b.angular_velocity
		b.angular_velocity = w - up * w.dot(up) - up * clampf(twist * 6.0, -1.5, 1.5)


func _update_surge(delta: float) -> void:
	var on_surge: bool = false
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.y < 1.0 and p.x < SURGE_HEAD + 0.15:
			on_surge = true
			break
	_surge.speed = move_toward(_surge.speed, surge_speed if on_surge else 0.0, 0.5 * delta)
	# Pocket and incline: every board past the surge head that hasn't reached the crest.
	var in_pocket: int = 0
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		# From the pack stop on: boards on the run-out are on their way into the pocket.
		if p.x > SURGE_STOP_X + 0.10 and p.x < UNS_HEAD.x and p.y < 2.3 and p.y > -0.05 and absf(p.z) < 2.6:
			in_pocket += 1
	# Drop the stop for the front pack when the pocket runs low; raise it once that pack's
	# trailing edge is past the fingers and nothing stands over them.
	if _surge_target < 0.5:
		var size: String = _waiting_pack_size()
		var line: Dictionary = _line_sizes()
		# A pack of another size waits until the pocket, unscrambler and infeed have run out of
		# the last one, so sizes never mix on the way to the divider.
		if in_pocket <= 8 and size != "" and not _pack_dropping() and (line.is_empty() or (line.size() == 1 and line.has(size))):
			_surge_target = 1.0
			_log("pocket low (%d boards): releasing a %s pack" % [in_pocket, size])
			_set_adjusters(size)
	elif _surge_stop >= 1.0 and not _over_surge_stop():
		_surge_target = 0.0
	_surge_stop = move_toward(_surge_stop, _surge_target, delta / 0.2)


## Is a released pack still on its way into the pocket (on the run-out or tipping off the
## head)? The next one waits until it has landed, so packs go in one at a time.
func _pack_dropping() -> bool:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.x > SURGE_STOP_X + 0.05 and p.x < POCKET_LIP.x + 0.4 and p.y < 1.0 and b.linear_velocity.length() > 0.05:
			return true
	return false


## Boards tangled in the unscrambler pocket: turned across the line, or on edge or end. If
## none are, the top few of the pile (the lugs can't get under it). Top ones first.
func _pocket_tangle() -> Array[RigidBody3D]:
	var pile: Array[RigidBody3D] = []
	var bad: Array[RigidBody3D] = []
	for b: RigidBody3D in _boards:
		if b.freeze:
			continue
		var p: Vector3 = _local(b)
		if p.x < SURGE_HEAD or p.x > UNS_HEAD.x or p.y < -0.05 or p.y > 2.4 or absf(p.z) > 2.6:
			continue
		pile.append(b)
		var flat: float = absf((global_basis.inverse() * b.global_basis.y).normalized().y)
		if absf(_twist(b)) > deg_to_rad(8.0) or flat < 0.9:
			bad.append(b)
	var pick: Array[RigidBody3D] = bad if not bad.is_empty() else pile
	pick.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return a.global_position.y > c.global_position.y)
	return pick.slice(0, 4)


## Pocket adjusters for a size: raised so the lugs stand only three quarters of a board above
## the plates. The bottom board rides up on them pushed by its lug; one lying on top of it has
## nothing behind it and slides back into the pocket. The pocket only ever holds one size.
func _set_adjusters(size: String) -> void:
	var t: float = 0.038
	if CutBoardScript.LUMBER_SPECS.has(size):
		t = float(CutBoardScript.LUMBER_SPECS[size]["thickness"])
	# Plate tops sit 4 mm under the chain tops when down.
	var raise: float = maxf(UNS_LUG_HOLD - t * 0.75 + 0.004, 0.0)
	if not is_equal_approx(raise, _adj_target):
		_adj_target = raise
		_log("pocket adjusters set for %s: %.0f mm up" % [size, raise * 1000.0])


## A point on the unscrambler bed: t metres up the incline from the foot's pin line, off metres
## out along its normal (stacker_build.along).
static func _uns_at(t: float, off: float) -> Vector2:
	var dir := Vector2(cos(UNS_ANGLE), sin(UNS_ANGLE))
	var nrm := Vector2(-dir.y, dir.x)
	return UNS_FOOT + nrm * (UNS_SPR + off) + dir * t


## Size of the pack standing at the surge stop, or "" if none.
func _waiting_pack_size() -> String:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.y < 1.0 and absf(p.x + _half_w(b) - SURGE_STOP_X) < 0.03:
			return str(b.get("nominal_size"))
	return ""


## Sizes of the boards on their way from the surge stop to the divider (run-out, pocket,
## unscrambler, infeed), as a set.
func _line_sizes() -> Dictionary:
	var sizes: Dictionary = {}
	for b: RigidBody3D in _boards:
		if b.freeze:
			continue
		var p: Vector3 = _local(b)
		var in_pocket: bool = p.x < UNS_FOOT.x + 0.8 and absf(p.z) < 2.6
		if p.x > SURGE_STOP_X + 0.10 and p.x - _half_w(b) < HOLD_STOP_X and p.y > (-0.05 if in_pocket else 0.15) and p.y < 3.0:
			sizes[str(b.get("nominal_size"))] = true
	return sizes


func _pack_at_stop() -> bool:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.y < 1.0 and absf(p.x + _half_w(b) - SURGE_STOP_X) < 0.03:
			return true
	return false


func _over_surge_stop() -> bool:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		if p.y < 1.2 and p.x + _half_w(b) > SURGE_STOP_X - 0.03 and p.x - _half_w(b) < SURGE_STOP_X + 0.10:
			return true
	return false


## The unscrambler meters the layers: it runs only while the forming layer still needs boards
## (counting those already over the crest and on the infeed), and waits through the fork
## cycle. Boards so arrive spaced a lug apart and never queue against the divider.
func _update_unscrambler(delta: float) -> void:
	var committed: int = _passed.size()
	var size: String = _layer_size
	for b: RigidBody3D in _boards:
		if _passed.has(b) or _package.has(b):
			continue
		var p: Vector3 = _local(b)
		if p.y > 2.4 and p.y < 2.9 and p.x > UNS_HEAD.x - 0.12 and p.x < LAYER_STOP_X + 0.05:
			committed += 1
			if size == "":
				size = str(b.get("nominal_size"))
	var need: int = layer_plan(size).x if size != "" else 1
	var run: bool = _phase == Phase.FORM and _hold_target > 0.5 and committed < need
	if not run and _crest_busy():
		run = true            # finish putting the crest board over before stopping
	if run != _uns_on:
		_uns_on = run
		_log("unscrambler %s: %d of %d boards committed to the layer (%s)" % ["runs" if run else "waits", committed, need,
			"forming" if _phase == Phase.FORM and _hold_target > 0.5 else "fork cycle"])
	_uns.speed = move_toward(_uns.speed, unscrambler_speed if _uns_on else 0.0, 3.0 * delta)


## Is a board lying over the crest (still partly on the incline chains)? Stopped there, most
## of its weight stays on the stopped chains and the dead plate can't pull it off.
func _crest_busy() -> bool:
	for b: RigidBody3D in _boards:
		var p: Vector3 = _local(b)
		# Centre past the crest (x 25.27) but not yet off the incline chains. A board still
		# climbing on its lug sits at x < 25.2.
		if p.y > 2.55 and p.y < 2.75 and p.x > UNS_HEAD.x - 0.08 and p.x < UNS_HEAD.x + 0.15:
			return true
	return false


## Counts boards into the forming layer and drops the course divider behind a full layer (or
## in front of another size). The layer-forming chains start at the divider's face and run
## faster than the infeed: a board counts once its middle is on them. At a full count the
## infeed chains slow right down for a moment, so the last board pulls away from the next one
## and the fingers drop into the gap.
func _update_forming(delta: float) -> void:
	if _phase != Phase.FORM:
		return
	if _hold_target < 0.5:
		return            # raised: the layer is complete and waiting for the forks
	var per: int = layer_plan(_layer_size).x if _layer_size != "" else 999
	if _passed.size() < per:
		for b: RigidBody3D in _boards:
			if _passed.has(b) or _package.has(b):
				continue
			var p: Vector3 = _local(b)
			if p.y > 2.55 and p.y < 2.8 and p.x > HOLD_STOP_X + 0.01 and p.x < LAYER_STOP_X + 0.05:
				var size: String = str(b.get("nominal_size"))
				if _layer_size != "" and size != _layer_size:
					continue
				_passed.append(b)
				if _layer_size == "":
					_layer_size = size
					per = layer_plan(size).x
				if _passed.size() >= per:
					break
	if _passed.size() != _stall_count:
		_stall_count = _passed.size()
		_stall_t = 0.0
	else:
		_stall_t += delta
		if log_events and _stall_t > 45.0 and not _passed.is_empty():
			_stall_t = 0.0
			var parts: PackedStringArray = []
			for b: RigidBody3D in _boards:
				var p: Vector3 = _local(b)
				if p.x > SURGE_TAIL - 1.0 and p.x < 29.1 and not _package.has(b):
					parts.append("%s%s x%.2f y%.2f z%.2f v%.2f" % ["*" if _passed.has(b) else "", b.name, p.x, p.y, p.z, b.linear_velocity.length()])
			_log("forming stalled (%d passed, hold %.2f, infeed %.2f, uns %.2f, surge %.2f, stop %.1f): %s" % [_passed.size(), _hold_stop,
				_inf.speed, _uns.speed, _surge.speed, _surge_stop, ", ".join(parts)])
	var next: RigidBody3D = _next_at_hold()
	if next != null and (_passed.is_empty() or str(next.get("nominal_size")) == _layer_size):
		# Doubles gauge for the next board of this layer (one of another size is held back
		# instead): raising the fingers is always safe; lowering them waits until nothing is
		# under them.
		var t_next: float = float(next.get("board_thickness"))
		if t_next > _gauge_t or not _over_hold_stops():
			_gauge_t = t_next
	if _passed.is_empty():
		return
	var full: bool = _passed.size() >= per
	var other: bool = (next != null and str(next.get("nominal_size")) != _layer_size) or _stray_in_layer()
	# A short layer is never stacked: it waits for more boards of its size, and if another
	# size comes first the divider holds that back and the crew sets the short layer aside.
	if full or other:
		_infeed_hold = true
		if not _over_hold_stops():
			_hold_target = 0.0
			_log("layer of %d %s past the course divider%s" % [_passed.size(), _layer_size,
				"" if full else " (short: next board is another size)"])


## Any board still on its way: on the surge, in the pocket, on the incline or the infeed.
func _boards_upstream() -> bool:
	for b: RigidBody3D in _boards:
		if _passed.has(b) or _package.has(b) or _layer.has(b):
			continue
		var p: Vector3 = _local(b)
		if p.x < HOLD_STOP_X and p.y > 0.0 and p.y < 2.9:
			return true
	return false


## Is any board under the course divider fingers (they can't drop)? With counted = false, only
## boards not yet counted into the layer.
func _over_hold_stops(counted: bool = true) -> bool:
	for b: RigidBody3D in _boards:
		if _package.has(b) or (not counted and _passed.has(b)):
			continue
		var p: Vector3 = _local(b)
		# Under the fingers, not just up against their face (they can drop in front of that one).
		if p.y > 2.5 and p.y < 2.8 and p.x + _half_w(b) > HOLD_STOP_X + 0.003 and p.x - _half_w(b) < HOLD_STOP_X + 0.05:
			return true
	return false


## A board of another size already past the divider (a board put back by hand, say)? The
## divider then closes so the layer check (_check_layer) has it taken out.
func _stray_in_layer() -> bool:
	for b: RigidBody3D in _boards:
		if b.freeze or _package.has(b) or _passed.has(b):
			continue
		var p: Vector3 = _local(b)
		if p.x - _half_w(b) > HOLD_STOP_X + 0.04 and p.x < LAYER_STOP_X + 0.1 and p.y > 2.45 and p.y < 2.8 				and str(b.get("nominal_size")) != _layer_size:
			return true
	return false


## Is this board lying partly on top of another (shingled)? Thin boards riding each other sit
## too low for a height check, so: another board under it, overlapping it across the line by
## more than a few cm, with its centre lower.
func _overlaps_below(b: RigidBody3D) -> bool:
	return _board_below(b) != null


## The board this one lies partly on top of, or null. Past the course divider the layer is
## pushed together against the stops, where neighbours' footprints overlap a few cm while both
## still lie on the chains, so there a board has to sit a third of a board higher to be riding.
func _board_below(b: RigidBody3D) -> RigidBody3D:
	var p: Vector3 = _local(b)
	var rise: float = 0.006 if p.x < HOLD_STOP_X else float(b.get("board_thickness")) * 0.33
	for o: RigidBody3D in _boards:
		if o == b or o.freeze or _package.has(o):
			continue
		var q: Vector3 = _local(o)
		if absf(q.y - p.y) > 0.1 or q.y > p.y - rise:
			continue
		if absf(q.x - p.x) < _half_w(b) + _half_w(o) - 0.03:
			return o
	return null


## Is a board up against the course divider's fingers (waiting there)?
func _board_at_divider() -> bool:
	for b: RigidBody3D in _boards:
		if b.freeze or _package.has(b):
			continue
		var p: Vector3 = _local(b)
		if p.y > 2.5 and p.y < 2.8 and p.x < HOLD_STOP_X and p.x + _half_w(b) > HOLD_STOP_X - 0.06:
			return true
	return false


## Nearest board still upstream of (or crossing) the course divider.
func _next_at_hold() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_x: float = -INF
	for b: RigidBody3D in _boards:
		if _passed.has(b) or _package.has(b):
			continue
		var p: Vector3 = _local(b)
		if p.y > 2.5 and p.y < 2.8 and p.x > 25.0 and p.x - _half_w(b) <= HOLD_STOP_X + 0.04 and p.x > best_x:
			best_x = p.x
			best = b
	return best


func _update_cycle(delta: float) -> void:
	if _phase == Phase.FORM:
		if _hold_stop > 0.01 or _hold_target > 0.5 or _lowering != 0 or not _hoist_ready():
			if _hold_target < 0.5 and _lowering == 0:
				_wait_t += delta
				if _wait_t > 10.0:
					_wait_t = 0.0
					_log("layer waiting for the forks: divider %.2f, passed %d, lowering %d, hoist %.3f (want %.3f), forks %.3f" % [
						_hold_stop, _passed.size(), _lowering, _hoist_y, HOIST_TOP - float(_pkg_layers) * (_pkg_t + STICK_T), _fork_dx])
			return
		if _ending:
			if not _update_ending(delta):
				return
		else:
			if not _check_layer():
				_wait_t += delta
				if _wait_t > 10.0:
					_wait_t = 0.0
					_log("layer waiting for the forks: %s" % _wait_why)
				return
			_wait_t = 0.0
			if _pkg_size != "" and _layer_size != _pkg_size:
				_finish = true             # this layer is another size: send the package out first
				_start_lowering()
				return
			# Every other layer of the package goes to the far end: the one after a near-ended layer.
			_layer_far = alternate_ends and _pkg_layers > 0 and not _prev_far
			if _layer_far:
				_ending = true
				_end_t = 0.0
				_end_squaring = true
				_log("layer %d to the far end" % (_pkg_layers + 1))
				return
		_ending = false
		_layer = _passed.duplicate()
		_passed.clear()
		_grip_layer()
		_set_phase(Phase.STOPS_DOWN)
		return
	_phase_t += delta
	var dur: float = float(PHASE_TIME[_phase])
	var u: float = _ease(_phase_t / dur)
	match _phase:
		Phase.STOPS_DOWN:
			_layer_stop = u
		Phase.LIFT:
			_fork_dy = lerpf(FORK_PARK, FORK_LIFT, u)
		Phase.EXTEND:
			_fork_dx = FORK_STROKE * u
			if u >= 1.0:
				_layer_stop = 0.0
		Phase.FENCE_DOWN:
			_fence_up = FENCE_RAISE * (1.0 - u)
		Phase.RETRACT:
			_fork_dx = FORK_STROKE * (1.0 - u)
		Phase.SETTLE:
			if _phase_t >= dur:
				_place_layer(1.0)            # final spot first: placing uses the layer count
				_freeze_layer()
		Phase.STICKS:
			# The stick placer: the bottom stick of each magazine is taken in the placer's
			# fingers, the placer travels down until the sticks sit on the layer that was just
			# put out, the fingers open, and the placer goes back up out of the way. No sticks
			# on a package's last layer.
			if _pkg_layers >= layer_plan(_pkg_size).y and not _finish:
				_placer_dy = 0.0
			else:
				if _new_sticks.is_empty():
					_drop_sticks()
				var down: float = _stick_top() + STICK_T * 0.5 - (MAG_BOTTOM - STICK_T * 0.5 - 0.004)
				var t: float = _phase_t
				if t < 0.35:
					_placer_dy = down * _ease(t / 0.35)
					_place_sticks(_placer_dy)
				elif t < 0.5:
					_placer_dy = down
					_gate = clampf((t - 0.35) / 0.1, 0.0, 1.0)            # fingers open
				else:
					_placer_dy = down * (1.0 - _ease((t - 0.5) / 0.35))
					_gate = clampf(1.0 - (t - 0.75) / 0.1, 0.0, 1.0)
		Phase.STICK_SETTLE:
			if _phase_t >= dur:
				_package.append_array(_new_sticks)
				_new_sticks.clear()
		Phase.LOWER:
			var step_h: float = _pkg_t + STICK_T
			var target: float = HOIST_TOP - float(_pkg_layers) * step_h
			_move_hoist(lerpf(target + step_h, target, u) - _hoist_y)
			_fence_up = FENCE_RAISE * u
		Phase.RESET:
			_fork_dy = lerpf(FORK_LIFT, FORK_PARK, u)
	if (_phase < Phase.SETTLE or (_phase == Phase.SETTLE and _phase_t < dur)) and not _layer.is_empty():
		_place_layer(u)
	if _phase_t >= dur:
		var next_phase: int = _phase + 1
		if next_phase > Phase.RESET:
			_phase = Phase.FORM
			_phase_t = 0.0
			_hold_target = 1.0
			_layer.clear()
			_layer_size = ""
			var plan: Vector2i = layer_plan(_pkg_size)
			if _pkg_layers >= plan.y or _finish:
				_start_lowering()
		else:
			_set_phase(next_phase)


## Far-end ending of the layer waiting at the stops: the drums rise under it and drive it
## endwise until every board's end is at the far fence (or a timeout), then drop back under the
## chains. True once they are down again and the forks can have it.
func _update_ending(delta: float) -> bool:
	_end_t += delta
	if _end_squaring:
		# A layer skewed against the stops, or with boards pressed into each other, wedges when it
		# is driven endwise. So it is squared first, as the grip squares every layer: each board
		# set square against the stops (or the board ahead), 2 mm apart, where it lies endwise.
		if _square_from.is_empty():
			_passed.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return _local(a).x > _local(c).x)
			var front: float = LAYER_STOP_X
			for b: RigidBody3D in _passed:
				var w: float = float(b.get("board_width"))
				var from: Transform3D = global_transform.affine_inverse() * b.global_transform
				_square_from.append(from)
				_square_to.append(Transform3D(Basis(Vector3.UP, -PI * 0.5),
					Vector3(front - w * 0.5, INFEED_TOP + float(b.get("board_thickness")) * 0.5 + 0.002, from.origin.z)))
				front -= w + 0.002
				b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				b.freeze = true
		var u: float = _ease(_end_t / 0.3)
		for i in _passed.size():
			if is_instance_valid(_passed[i]):
				_passed[i].global_transform = global_transform * _square_from[i].interpolate_with(_square_to[i], u)
		if u >= 1.0:
			for b: RigidBody3D in _passed:
				if is_instance_valid(b):
					b.freeze = false
					b.linear_velocity = Vector3.ZERO
					b.angular_velocity = Vector3.ZERO
			_square_from.clear()
			_square_to.clear()
			_end_squaring = false
			_end_t = 0.0
			_end_target = 1.0
			_log("layer squared: ending drums up")
		return false
	if _end_target > 0.5:
		if _end_up < 1.0:
			return false
		var home: bool = true
		for b: RigidBody3D in _passed:
			if not is_instance_valid(b):
				continue
			var far: float = _local(b).z + float(b.get("product_length")) * 0.5
			if far < FAR_FENCE_Z - 0.012 or absf(b.linear_velocity.dot(global_basis.z)) > 0.03:
				home = false
		if home or _end_t > END_TIMEOUT:
			_end_target = 0.0
			_log("layer even-ended at the far fence%s: ending drums down%s" % ["" if home else " (timed out)", "" if home else _forming_dump()])
		return false
	return _end_up <= 0.0


func _set_phase(p: int) -> void:
	_phase = p
	_phase_t = 0.0


## The last check before the forks take a layer, made on the boards actually lying on the
## forming chains (a worker may have moved some since they were counted). Only a whole layer of
## one size, every board flat and square, goes. Short with more of its size to come: the
## divider opens again. Too many boards, or another size among them: the crew puts the extras
## back upstream ("extra"). Short with another size next: the crew sets the layer aside on the
## holdover rack ("short"). Twisted or riding boards are left to find_jam.
func _check_layer() -> bool:
	_fault = ""
	_fault_boards = []
	var mine: Array[RigidBody3D] = []
	var others: Array[RigidBody3D] = []
	for b: RigidBody3D in _boards:
		if not is_instance_valid(b) or b.freeze or _package.has(b) or b.get("board_width") == null:
			continue
		var p: Vector3 = _local(b)
		if p.x + _half_w(b) < HOLD_STOP_X + 0.03 or p.x > LAYER_STOP_X + 0.1 or p.y < 2.45 or p.y > 3.0:
			continue
		if absf(_twist(b)) > deg_to_rad(25.0) or p.y > INFEED_TOP + float(b.get("board_thickness")) * 0.5 + 0.025:
			_wait_why = "%s turned across or riding" % b.name
			_still_t = 0.0
			return false
		if str(b.get("nominal_size")) == _layer_size:
			mine.append(b)
		else:
			others.append(b)
	# Gathered and at rest: every board there still for 0.4 s, the front one up at the stops.
	# (Not squared against the stops: the grip, _grip_layer, squares a layer up anyway.)
	var front: float = -INF
	var still: bool = true
	for b: RigidBody3D in mine + others:
		front = maxf(front, _local(b).x + _half_w(b))
		if b.linear_velocity.length() > 0.05:
			still = false
	_still_t = _still_t + get_physics_process_delta_time() if still and front > LAYER_STOP_X - 1.2 else 0.0
	if _still_t <= 0.4:
		_wait_why = "%d boards settling (front %.2f)" % [mine.size() + others.size(), front]
		return false
	if _layer_size == "" and not others.is_empty():
		# Nothing counted (the list was lost or never made): the layer is the front board's size.
		others.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return _local(a).x > _local(c).x)
		_layer_size = str(others[0].get("nominal_size"))
		for b: RigidBody3D in others.duplicate():
			if str(b.get("nominal_size")) == _layer_size:
				mine.append(b)
				others.erase(b)
	var per: int = layer_plan(_layer_size).x
	mine.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return _local(a).x > _local(c).x)
	if not others.is_empty() or mine.size() > per:
		_fault = "extra"
		_fault_boards = others.duplicate()
		_fault_boards.append_array(mine.slice(per))
		return false
	_passed = mine.duplicate()
	_wait_why = "%d of %d %s" % [mine.size(), per, _layer_size]
	if mine.size() == per:
		return true
	var next: RigidBody3D = _next_at_hold()
	var coming: bool = next != null or _line_sizes().has(_layer_size)
	var waiting: String = _waiting_pack_size()
	var stuck: bool = not coming and waiting != "" and waiting != _layer_size
	if mine.is_empty() or (next == null and not stuck) or (next != null and str(next.get("nominal_size")) == _layer_size):
		if mine.is_empty():
			_layer_size = ""
		_hold_target = 1.0
		_log("layer short (%d of %d %s): the divider lets more through%s" % [mine.size(), per, _layer_size, _forming_dump()])
		return false
	var spare: Array[RigidBody3D] = _rack_boards(_layer_size)
	if spare.size() >= per - mine.size():
		# The holdover rack has enough of this size: the crew fills the layer from it.
		_fault = "fill"
		_fault_boards = spare.slice(0, per - mine.size())
		_fill_back = INF
		for b: RigidBody3D in mine:
			_fill_back = minf(_fill_back, _local(b).x - _half_w(b))
		return false
	_fault = "short"
	_fault_boards = mine.duplicate()
	return false


## Debug: every loose board around the forming section, for the log.
func _forming_dump() -> String:
	if not log_events:
		return ""
	var parts: PackedStringArray = []
	for b: RigidBody3D in _boards:
		if not is_instance_valid(b) or b.freeze or b.get("board_width") == null:
			continue
		var q: Vector3 = _local(b)
		if q.x > HOLD_STOP_X - 0.3 and q.x < 31.0 and q.y > 1.5:
			parts.append("%s%s %dft x%.3f y%.3f z%.2f end%.3f vz%.2f tw%.0f" % ["*" if _passed.has(b) else "", b.name, int(b.get("length_feet")),
				q.x, q.y, q.z, q.z + float(b.get("product_length")) * 0.5, b.linear_velocity.dot(global_basis.z), rad_to_deg(_twist(b))])
	return ": " + ", ".join(parts)


## Boards of a size on the holdover rack, top ones first (they come off first).
func _rack_boards(size: String) -> Array[RigidBody3D]:
	var found: Array[RigidBody3D] = []
	for b: RigidBody3D in _rack:
		if is_instance_valid(b) and str(b.get("nominal_size")) == size:
			found.append(b)
	found.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return a.global_position.y > c.global_position.y)
	return found


## Where a worker puts a board for the layer fault being fixed: an extra goes back on the
## infeed upstream of the divider; a short layer's boards go on the holdover rack, out of the
## line (the stacker lets go of them).
func fix_spot(b: RigidBody3D) -> Transform3D:
	var t: float = float(b.get("board_thickness"))
	var w: float = float(b.get("board_width"))
	if _fault == "fill":
		# Off the rack, square onto the forming chains behind the layer.
		_rack.erase(b)
		b.remove_from_group("holdover")
		_boards.append(b)
		_fill_back -= w + 0.004
		_log("short layer filled from the holdover rack (%d left there)" % _rack.size(), b)
		return global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(_fill_back + w * 0.5, INFEED_TOP + t * 0.5 + 0.003, LINEUP_FENCE_Z + float(b.get("product_length")) * 0.5))
	# An extra of the layer's own size goes back on the infeed for the next layer; one of
	# another size would only come round again, so it is set aside like a short layer.
	if _fault != "short" and (_fault != "extra" or _layer_size == "" or str(b.get("nominal_size")) == _layer_size):
		return put_back_spot(b)
	_boards.erase(b)
	_passed.erase(b)
	b.add_to_group("holdover")
	# Two across between the pins; onto whichever side is lower, just clear of what's there,
	# and left to settle on the arms.
	var across: int = 2 if 2.0 * w + 0.01 < RACK_Z.y - RACK_Z.x - 0.06 else 1
	var zs: Array[float] = [RACK_Z.x + 0.03 + w * 0.5 + 0.005, RACK_Z.y - 0.03 - w * 0.5 - 0.005]
	var best_z: float = zs[0]
	var best_top: float = INF
	for c in across:
		var top: float = RACK_Y
		for o: RigidBody3D in _rack:
			if is_instance_valid(o) and absf(_local(o).z - zs[c]) < (w + float(o.get("board_width"))) * 0.5:
				top = maxf(top, _local(o).y + float(o.get("board_thickness")) * 0.5)
		if top < best_top:
			best_top = top
			best_z = zs[c]
	_rack.append(b)
	if best_top + t > RACK_Y + RACK_PIN_H:
		push_warning("GreenStacker: holdover rack full")
	if _passed.is_empty():
		_layer_size = ""
		_hold_target = 1.0
	_log("%s board set aside on the holdover rack (%d there)" % ["short layer" if _fault == "short" else "odd-size", _rack.size()], b)
	return global_transform * Transform3D(Basis(), Vector3(RACK_ARM_X[1], best_top + t * 0.5 + 0.01, best_z))


func _hoist_ready() -> bool:
	return _lowering == 0 and is_equal_approx(_hoist_y, HOIST_TOP - float(_pkg_layers) * (_pkg_t + STICK_T)) \
		and _fork_dx == 0.0


## Guided layer drop. Up to here every board got where it is by physics; from the moment the
## layer stops drop, the stacker holds the layer: each board is squared up against the layer
## stops and the line-up fence (it's already within a few cm), rides the forks out, is held
## by the pull-back fence while the forks pull out, and is set straight down onto the
## package. So every package comes out square.
func _grip_layer() -> void:
	_layer.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return _local(a).x > _local(b).x)
	_layer_from.clear()
	_layer_home.clear()
	var front: float = LAYER_STOP_X
	_layer_back = LAYER_STOP_X
	for b: RigidBody3D in _layer:
		var w: float = float(b.get("board_width"))
		var t: float = float(b.get("board_thickness"))
		var length: float = float(b.get("product_length"))
		_layer_from.append(global_transform.affine_inverse() * b.global_transform)
		var z: float = FAR_FENCE_Z - length * 0.5 if _layer_far else LINEUP_FENCE_Z + length * 0.5
		_layer_home.append(Vector3(front - w * 0.5, INFEED_TOP + t * 0.5, z))
		front -= w + 0.002
		_layer_back = front
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true


func _place_layer(u: float) -> void:
	var lift: float = maxf(FORK_HOME_TOP + _fork_dy - INFEED_TOP, 0.0)
	var dx: float = _fork_dx
	if _phase >= Phase.RETRACT:
		dx = maxf(_fork_dx, FENCE_X + 0.02 - _layer_back)     # the fence holds the layer back
	var drop: float = 0.0
	if _phase == Phase.SETTLE:
		# Set down onto the package top as the last tine tips pass out from under it.
		var top: float = _hoist_y + float(_pkg_layers) * (_pkg_t + STICK_T)
		drop = (INFEED_TOP + lift - top) * u
	var square := Basis(Vector3.UP, -PI * 0.5)
	for i in _layer.size():
		var b: RigidBody3D = _layer[i]
		if not is_instance_valid(b):
			continue
		var pose := Transform3D(square, _layer_home[i] + Vector3(dx, lift - drop, 0.0))
		if _phase == Phase.STOPS_DOWN:
			pose = _layer_from[i].interpolate_with(pose, u)
		b.global_transform = global_transform * pose


func _freeze_layer() -> void:
	if _pkg_size == "":
		_pkg_size = _layer_size
		_pkg_t = float(_layer[0].get("board_thickness")) if not _layer.is_empty() and is_instance_valid(_layer[0]) else 0.038
	for b: RigidBody3D in _layer:
		if is_instance_valid(b):
			_package.append(b)
	_pkg_layers += 1
	_prev_far = _layer_far
	_log("layer %d of %d (%d boards) on the package" % [_pkg_layers, layer_plan(_pkg_size).y, _layer.size()])


func _freeze(b: RigidBody3D) -> void:
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	_package.append(b)


## Sticks out of the magazines: guided straight down onto the new layer (see _place_sticks).
func _drop_sticks() -> void:
	for z: float in STICK_Z:
		var stick := RigidBody3D.new()
		stick.name = "Stick"
		stick.mass = 0.6
		stick.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		stick.freeze = true
		stick.physics_material_override = _wet
		var shape := BoxShape3D.new()
		shape.size = Vector3(STICK_LEN, STICK_T, STICK_W)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		stick.add_child(cs)
		var model: Node3D = StickScene.instantiate()
		model.position = Vector3(-STICK_LEN * 0.5, -STICK_T * 0.5, 0.0)
		stick.add_child(model)
		get_parent().add_child(stick)
		stick.global_transform = global_transform * Transform3D(Basis(), Vector3(STICK_X0 + STICK_LEN * 0.5, MAG_BOTTOM - STICK_T * 0.5 - 0.004, z))
		_boards.append(stick)
		_new_sticks.append(stick)


## Top of the layer just put out (where its sticks go).
func _stick_top() -> float:
	return _hoist_y + float(_pkg_layers) * _pkg_t + float(_pkg_layers - 1) * STICK_T


## Sticks held in the placer's fingers, `dy` below their place at the magazine bottom.
func _place_sticks(dy: float) -> void:
	var y: float = MAG_BOTTOM - STICK_T * 0.5 - 0.004 + dy
	for i in _new_sticks.size():
		var s: RigidBody3D = _new_sticks[i]
		if is_instance_valid(s):
			s.global_transform = global_transform * Transform3D(Basis(), Vector3(STICK_X0 + STICK_LEN * 0.5, y, STICK_Z[i]))


func _start_lowering() -> void:
	if _package.is_empty():
		_finish = false
		_pkg_size = ""
		_pkg_layers = 0
		return
	_lowering = 1
	_log("package of %d layers %s done: lowering it onto the outfeed" % [_pkg_layers, _pkg_size])


## Finished package: hoist down until the package sits on the outfeed chains, chains run it
## to the landing deck, the landing lift raises it, the hoist goes back up.
func _update_package(delta: float) -> void:
	if _lowering == 1:
		var target: float = HOIST_LOW
		var before: float = _hoist_y
		var after: float = move_toward(_hoist_y, target, hoist_speed * delta)
		# The package rides the arms down until it meets the chains.
		var pkg_before: float = maxf(before, OUT_TOP)
		var pkg_after: float = maxf(after, OUT_TOP)
		_shift(_package, Vector3(0.0, pkg_after - pkg_before, 0.0))
		_hoist_y = after
		if is_equal_approx(_hoist_y, target):
			_outgoing = _package.duplicate()
			_package.clear()
			_out_back = FENCE_X + 0.02
			_out_front = _out_back
			for b: RigidBody3D in _outgoing:
				if is_instance_valid(b) and b.get("board_width") != null:
					_out_front = maxf(_out_front, _local(b).x + _half_w(b))
			_pkg_size = ""
			_pkg_layers = 0
			_finish = false
			_lowering = 2
	elif _lowering == 2 and (_outgoing.is_empty() or _out_back > HOIST_X1 + 0.05):
		_hoist_y = move_toward(_hoist_y, HOIST_TOP, hoist_speed * delta)
		if is_equal_approx(_hoist_y, HOIST_TOP):
			_lowering = 0
			_log("hoist back up for the next package")
	# Outfeed: run the package out while the landing deck is free.
	var deck_free: bool = _landed.is_empty() and not _deck_busy()
	var run: bool = not _outgoing.is_empty() and (deck_free or _out_front < LANDING_STOP_X - 2.0)
	if run and _out_front >= LANDING_STOP_X:
		run = false
		if deck_free:
			_landed = _outgoing.duplicate()
			_outgoing.clear()
			_landed_t = 0.0
			_packages_done += 1
			_log("package on the landing deck")
	_out.speed = move_toward(_out.speed, outfeed_speed if run else 0.0, 0.5 * delta)
	if not _outgoing.is_empty() and _out.speed > 0.0:
		var dx: float = minf(_out.speed * delta, maxf(LANDING_STOP_X - _out_front, 0.0))
		_shift(_outgoing, Vector3(dx, 0.0, 0.0))
		_out_front += dx
		_out_back += dx
	# Landing lift: up under a landed package, down when it's gone.
	var lift_target: float = LAND_RISE if not _landed.is_empty() or _deck_busy() else 0.0
	var before_lift: float = _landing_up
	_landing_up = move_toward(_landing_up, lift_target, 0.15 * delta)
	if not _landed.is_empty():
		_shift(_landed, Vector3(0.0, _landing_up - before_lift, 0.0))
		if is_equal_approx(_landing_up, LAND_RISE):
			_make_package_body()
	if _deck_busy():
		_landed_t += delta
		if auto_take_after > 0.0 and _landed_t > auto_take_after:
			take_package()


## The package on the landing deck, raised and ready for a forklift; null if none.
func ready_package() -> RigidBody3D:
	return _deck_package if _deck_busy() and is_equal_approx(_landing_up, LAND_RISE) else null


## A package body still on (or just over) the landing deck.
func _deck_busy() -> bool:
	if not is_instance_valid(_deck_package):
		return false
	var p: Vector3 = _local(_deck_package)
	return p.x > LAND_X0 - 1.0 and p.x < LANDING_STOP_X + 1.0 and absf(p.z) < 2.5


## Merge the landed boards and sticks into one package: a RigidBody3D with a single box
## collider and the real weight of green lumber (about 900 kg/m3). The boards' meshes move
## into it unchanged, so it looks the same. It sits frozen on the lift until a forklift
## takes it; a forklift sets it down as a free body.
func _make_package_body() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var volume: float = 0.0
	var size: String = ""
	for b: RigidBody3D in _landed:
		if not is_instance_valid(b):
			continue
		var p: Vector3 = _local(b)
		var w: Variant = b.get("board_width")
		var half := Vector3(STICK_LEN * 0.5, STICK_T * 0.5, STICK_W * 0.5)
		if w != null:
			half = Vector3(float(w) * 0.5, float(b.get("board_thickness")) * 0.5, float(b.get("product_length")) * 0.5)
			volume += 8.0 * half.x * half.y * half.z
			size = str(b.get("nominal_size"))
		else:
			volume += STICK_LEN * STICK_T * STICK_W
		lo = lo.min(p - half)
		hi = hi.max(p + half)
	if lo.x == INF:
		_landed.clear()
		return
	var pkg := RigidBody3D.new()
	pkg.name = "Package_%d" % _packages_done
	pkg.mass = maxf(volume * 900.0, 50.0)
	pkg.set_meta("nominal_size", size)
	pkg.set_meta("bottom_offset", (hi.y - lo.y) * 0.5)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	pkg.physics_material_override = mat
	pkg.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	pkg.freeze = true
	var shape := BoxShape3D.new()
	shape.size = hi - lo
	var cs := CollisionShape3D.new()
	cs.shape = shape
	pkg.add_child(cs)
	get_parent().add_child(pkg)
	pkg.global_transform = Transform3D(global_basis, to_global((lo + hi) * 0.5))
	for b: RigidBody3D in _landed:
		if not is_instance_valid(b):
			continue
		for c: Node in b.get_children():
			if c is CollisionShape3D:
				continue
			var n3 := c as Node3D
			var keep: Transform3D = n3.global_transform if n3 != null else Transform3D()
			b.remove_child(c)
			pkg.add_child(c)
			if n3 != null:
				n3.global_transform = keep
		_boards.erase(b)
		b.queue_free()
	_landed.clear()
	_deck_package = pkg
	_landed_t = 0.0
	_log("package %s made into one body: %.0f kg, %.2f x %.2f x %.2f m" % [pkg.name, pkg.mass, shape.size.x, shape.size.y, shape.size.z])


func _move_hoist(dy: float) -> void:
	_hoist_y += dy
	_shift(_package, Vector3(0.0, dy, 0.0))


func _shift(bodies: Array[RigidBody3D], local_delta: Vector3) -> void:
	if local_delta == Vector3.ZERO:
		return
	var d: Vector3 = global_basis * local_delta
	for b: RigidBody3D in bodies:
		if is_instance_valid(b):
			b.global_position += d


func _drive(delta: float) -> void:
	_hold_stop = move_toward(_hold_stop, _hold_target, delta / 0.25)
	_adj_up = move_toward(_adj_up, _adj_target, 0.05 * delta)        # hydraulic: a few cm a second
	if _infeed_hold and _hold_stop <= 0.01:
		_infeed_hold = false
	# Accumulating infeed: with the divider down and a board waiting against it, the infeed
	# chains stop, so the boards behind it queue without being shoved into each other (that
	# is what made them ride up).
	var queued: bool = _hold_stop < 0.5 and _board_at_divider()
	# Layer counted: the infeed stops, and while a board not in the layer is still under the
	# fingers it backs up slowly, so that board backs out from under them. While only the layer's
	# last board is under them (counted the moment it crept past, say, after waiting at the
	# fingers) the infeed creeps on instead and hands it to the forming chains. Then the fingers
	# drop into the gap.
	var back: bool = _infeed_hold and _over_hold_stops(false)
	var creep: bool = _infeed_hold and not back and _over_hold_stops()
	_inf.speed = move_toward(_inf.speed, -0.2 if back else (0.3 if creep else (0.0 if queued or _infeed_hold else infeed_speed)), 10.0 * delta)
	var xb: Vector3 = global_basis.x
	var zb: Vector3 = global_basis.z
	_surge_chains.constant_linear_velocity = xb * _surge.speed
	_runout.constant_linear_velocity = xb * (runout_speed if _surge.speed > 0.0 or _surge_stop > 0.5 else 0.0)
	_uns_chains.constant_linear_velocity = global_basis * Vector3(cos(UNS_ANGLE), sin(UNS_ANGLE), 0.0) * _uns.speed
	_dead_plate.constant_linear_velocity = xb * 0.8
	_out_chains.constant_linear_velocity = xb * _out.speed
	_inf_chains.constant_linear_velocity = xb * _inf.speed
	# Stopped while the forks cycle: the lifted layer sits only a few cm above them.
	# Also stopped once the layer has gathered against the stops, so it isn't squeezed.
	var forming: bool = _phase == Phase.FORM
	if forming and _hold_target < 0.5:
		# Divider down: run on a little to gather the layer against the stops, then stop so
		# the boards aren't shoved into each other (the grip squares up any gap left).
		_gather_t += delta
		forming = _gather_t < 3.0 and not _layer_gathered()
	else:
		_gather_t = 0.0
	_form_chains.constant_linear_velocity = xb * (forming_speed if forming else 0.0)
	_rolls.constant_linear_velocity = xb * _inf.speed - zb * lineup_speed * (absf(_inf.speed) / maxf(infeed_speed, 0.01))
	# Ending drums: air cylinders lift them; the drum motors run only while they're up.
	var end_before: float = _end_up
	_end_up = move_toward(_end_up, _end_target, delta / END_TIME)
	var end_run: bool = _end_target > 0.5 and _end_up >= 1.0
	_end_rolls.constant_linear_velocity = zb * ending_speed if end_run else Vector3.ZERO
	if end_run:
		_end_turn += ending_speed * delta / ROLL_R
	if _end_up != end_before:
		for b: RigidBody3D in _passed:
			if is_instance_valid(b):
				b.sleeping = false
	_surge.dist = fposmod(_surge.dist + _surge.speed * delta, _surge.total)
	_uns.dist = fposmod(_uns.dist + _uns.speed * delta, _uns.total)
	_inf.dist = fposmod(_inf.dist + _inf.speed * delta, _inf.total)
	_out.dist = fposmod(_out.dist + _out.speed * delta, _out.total)
	_roll_turn += lineup_speed * delta / ROLL_R
	_place_all()
	for shaft_name: String in _shafts:
		var loop: ChainLoop = _surge if shaft_name.begins_with("Surge") else (_uns if shaft_name.begins_with("Unscrambler") \
			else (_inf if shaft_name.begins_with("Infeed") else _out))
		(_shafts[shaft_name] as Node3D).rotate_z(-loop.speed * delta / loop.r)
	_visual_elapsed += delta
	if _visual_elapsed >= 1.0 / 30.0:
		_visual_elapsed = 0.0
		_place_chain_visuals()


## Have the boards on the forming chains gathered up against the layer stops (the front one at
## the stops, each of the others against the one ahead)? Until they have, the forming chains
## run on; then they stop so the layer isn't squeezed.
func _layer_gathered() -> bool:
	var on: Array[RigidBody3D] = []
	for b: RigidBody3D in _boards:
		if not is_instance_valid(b) or b.freeze or _package.has(b) or b.get("board_width") == null:
			continue
		var p: Vector3 = _local(b)
		if p.x + _half_w(b) > HOLD_STOP_X + 0.04 and p.x < LAYER_STOP_X + 0.1 and p.y > 2.45 and p.y < 2.8:
			on.append(b)
	if on.is_empty():
		return true
	on.sort_custom(func(a: RigidBody3D, c: RigidBody3D) -> bool: return _local(a).x > _local(c).x)
	var edge: float = LAYER_STOP_X
	for b: RigidBody3D in on:
		var p: Vector3 = _local(b)
		if p.x + _half_w(b) < edge - 0.03:
			return false                       # a gap ahead of this board: run on
		edge = p.x - _half_w(b)
	return true


func _local(b: Node3D) -> Vector3:
	return to_local(b.global_position)


## Half the board's width along stacker X (boards lie broadside); sticks count as narrow.
func _half_w(b: RigidBody3D) -> float:
	var w: Variant = b.get("board_width")
	return (float(w) if w != null else STICK_W) * 0.5


static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _log(text: String, board: RigidBody3D = null) -> void:
	if not log_events:
		return
	var who: String = ""
	if is_instance_valid(board):
		var at: Vector3 = _local(board)
		who = " %s %s at (%.2f, %.2f)" % [board.name, str(board.get("nominal_size")), at.x, at.y]
	print("[GreenStacker %.2f] %s%s" % [_clock, text, who])


# ─────────────────────────────────────────────────────────────────────────────
#  BUILD (runtime parts and collision)
# ─────────────────────────────────────────────────────────────────────────────

func _build_parts() -> void:
	var old := get_node_or_null("RuntimeParts")
	if old != null:
		old.free()
	_parts = Node3D.new()
	_parts.name = "RuntimeParts"
	add_child(_parts)
	_lugs.clear()
	_lug_on.clear()
	_roll_nodes.clear()

	var slick := _mat(0.3, false)
	var drag := _mat(0.35, false)
	var chain := _mat(0.6, true)
	# Surge chains: carrying run of each strand; the run-out is the same chains' last stretch.
	_surge_chains = _static("SurgeChains", drag)
	_runout = _static("SurgeRunout", drag)
	for z: float in SURGE_Z:
		_lead_in(_surge_chains, Vector3(SURGE_TAIL, SURGE_TOP - 0.024, z - 0.025), Vector3(RUNOUT_X, SURGE_TOP, z + 0.025))
		_lead_in(_runout, Vector3(RUNOUT_X, SURGE_TOP - 0.024, z - 0.025), Vector3(SURGE_HEAD + 0.08, SURGE_TOP, z + 0.025))
	# Pocket: floor sloping from the surge head down to the foot of the incline, and cheeks.
	var pocket := _static("Pocket", slick)
	var dir := Vector2(cos(UNS_ANGLE), sin(UNS_ANGLE))
	var nrm := Vector2(-dir.y, dir.x)
	var base: Vector2 = UNS_FOOT + nrm * UNS_SPR
	var low: Vector2 = base + dir * 0.05 + nrm * (UNS_PLATE_H - 0.007)
	_slab(pocket, POCKET_LIP, low, -2.45, 2.45, 0.02)
	for z: float in [-2.55, 2.55]:
		_span_box(pocket, Vector3(POCKET_LIP.x - 0.05, 0.0, z - 0.006), Vector3(base.x + 1.2, 1.3, z + 0.006))
		# Incline side guards (stacker_build.build_unscrambler) on up from the cheeks: a short
		# board skewed on the lugs slides along them instead of off the side of the bed.
		_slab(pocket, _uns_at(1.4, 0.15), _uns_at((UNS_HEAD - UNS_FOOT).length() - 0.4, 0.15), z - 0.006, z + 0.006, 0.23)
	# Incline: chain strands (live) and the bed between them (just under the chain tops).
	var top0: Vector2 = UNS_FOOT + nrm * (UNS_SPR + UNS_PLATE_H)
	var top1: Vector2 = UNS_HEAD + nrm * (UNS_SPR + UNS_PLATE_H)
	_uns_chains = _static("UnscramblerChains", chain)
	for z: float in UNS_Z:
		_slab(_uns_chains, top0, top1, z - 0.025, z + 0.025, 0.025)
	var bed := _static("UnscramblerBed", slick)
	_slab(bed, top0 - nrm * 0.006, top1 - nrm * 0.006, -2.45, 2.45, 0.01)
	# Dead plate over the head to the infeed chains: powered, so a board the lug has pushed
	# over the crest carries on onto the chains.
	_dead_plate = _static("DeadPlate", chain)
	# Its collision starts right at the crest (the model's plate starts a little past the head
	# shaft): a board tipping over must land on it, not in a gap between incline and plate.
	_lead_in(_dead_plate, Vector3(top1.x - 0.02, INFEED_TOP - 0.05, -2.45), Vector3(INF_TAIL + 0.15, INFEED_TOP - 0.001, 2.45))
	# Infeed chains to the course divider, then the faster layer-forming run.
	_inf_chains = _static("InfeedChains", chain)
	_form_chains = _static("FormingChains", drag)
	# Every section's upstream end is chamfered (lead-in): a board sunk a few mm into the
	# section it's leaving would otherwise catch its edge on the next one's square end.
	for z: float in INF_Z:
		_lead_in(_inf_chains, Vector3(INF_TAIL, INFEED_TOP - 0.02, z - 0.03), Vector3(HOLD_STOP_X, INFEED_TOP, z + 0.03))
		_lead_in(_form_chains, Vector3(HOLD_STOP_X, INFEED_TOP - 0.02, z - 0.03), Vector3(INF_HEAD, INFEED_TOP, z + 0.03))
	# Line-up drums: top line of each drum, driving endwise toward the fence.
	_rolls = _static("LineupRolls", _mat(0.9, true))
	for z: float in ROLL_Z:
		_lead_in(_rolls, Vector3(ROLL_X0, INFEED_TOP - 0.02, z - 0.03), Vector3(ROLL_X1, INFEED_TOP, z + 0.03))
		var roll: Node3D = RollScene.instantiate()
		roll.position = Vector3((ROLL_X0 + ROLL_X1) * 0.5, INFEED_TOP - ROLL_R, z)
		_parts.add_child(roll)
		_roll_nodes.append(roll)
	# The board ends slide along the fence while the chains carry them on: no drag on one end,
	# or the board twists.
	var fence := _static("LineupFence", _mat(0.0, false))
	_span_box(fence, Vector3(25.75, INFEED_TOP - 0.03, LINEUP_FENCE_Z - 0.012), Vector3(INF_HEAD, INFEED_TOP + 0.20, LINEUP_FENCE_Z))
	# Flared lead-in on the fence's upstream end (as on the model): a board whose end comes off
	# the unscrambler past the fence line is steered back in instead of butting the fence's end.
	var a := Vector2(25.45, LINEUP_FENCE_Z - 0.30)
	var b := Vector2(25.76, LINEUP_FENCE_Z - 0.006)
	var flare_shape := BoxShape3D.new()
	flare_shape.size = Vector3(a.distance_to(b), 0.23, 0.012)
	var flare := CollisionShape3D.new()
	flare.shape = flare_shape
	var d: Vector2 = (b - a).normalized()
	flare.transform = Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3((a.x + b.x) * 0.5, INFEED_TOP + 0.085, (a.y + b.y) * 0.5))
	fence.add_child(flare)

	# Far fence and its flared lead-in (stacker_build.build_far_fence), the mirror of the
	# line-up fence: the ends slide along it, so no drag.
	var far := _static("FarFence", _mat(0.0, false))
	far.add_child(_load_glb(FAR_FENCE_MODEL))
	_span_box(far, Vector3(26.95, INFEED_TOP - 0.03, FAR_FENCE_Z), Vector3(29.15, INFEED_TOP + 0.20, FAR_FENCE_Z + 0.012))
	var fa := Vector2(26.75, FAR_FENCE_Z + 0.25)
	var fb := Vector2(26.95, FAR_FENCE_Z + 0.006)
	var far_flare_shape := BoxShape3D.new()
	far_flare_shape.size = Vector3(fa.distance_to(fb), 0.23, 0.012)
	var far_flare := CollisionShape3D.new()
	far_flare.shape = far_flare_shape
	var fd: Vector2 = (fb - fa).normalized()
	far_flare.transform = Transform3D(Basis(Vector3.UP, atan2(-fd.y, fd.x)), Vector3((fa.x + fb.x) * 0.5, INFEED_TOP + 0.085, (fa.y + fb.y) * 0.5))
	far.add_child(far_flare)
	var skids := _static("ShortBoardIdlers", _mat(0.0, false))
	for s: float in [-1.0, 1.0]:
		_lead_in(skids, Vector3(SKID_X0, INFEED_TOP - SKID_DROP - 0.02, s * SKID_Z - 0.015), Vector3(SKID_X1, INFEED_TOP - SKID_DROP, s * SKID_Z + 0.015))
		_lead_in(skids, Vector3(SURGE_SKID_X0, SURGE_TOP - SKID_DROP - 0.02, s * SURGE_SKID_Z - 0.02),
			Vector3(SURGE_SKID_X1, SURGE_TOP - SKID_DROP, s * SURGE_SKID_Z + 0.02))
	# Ending drums on their lift (model home: raised), the whole body moving with the lift. Each
	# drum collides as the round drum it is: a board sunk a few mm into a flat-sided collider
	# would butt its end against the next drum as it slides across.
	_end_rolls = _static("EndingRolls", _mat(0.9, true))
	_end_rolls.add_child(_load_glb(END_LIFT_MODEL))
	_end_roll_nodes.clear()
	for z: float in END_Z:
		var drum_shape := CylinderShape3D.new()
		drum_shape.radius = ROLL_R
		drum_shape.height = END_X1 - END_X0
		var drum_col := CollisionShape3D.new()
		drum_col.shape = drum_shape
		drum_col.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3((END_X0 + END_X1) * 0.5, END_TOP - ROLL_R, z))
		_end_rolls.add_child(drum_col)
		var drum: Node3D = _load_glb(END_ROLL_MODEL)
		drum.position = Vector3((END_X0 + END_X1) * 0.5, END_TOP - ROLL_R, z)
		_end_rolls.add_child(drum)
		_end_roll_nodes.append(drum)

	# Package squaring guides hanging from the stick frame (stacker_build.build_package_guides):
	# front stop bars along the package's far side and plates at both board ends, over the
	# top few layers, so a board can't slide off the package as a layer drops onto it.
	var guides := _static("PackageGuides", slick)
	for z: float in [-1.95, -0.92, 0.26, 1.44, 2.03]:
		_span_box(guides, Vector3(STICK_X0 + STICK_LEN, 2.30, z - 0.04), Vector3(STICK_X0 + STICK_LEN + 0.05, MAG_BOTTOM, z + 0.04))
	for z: float in [LINEUP_FENCE_Z - 0.022, LINEUP_FENCE_Z + 4.887]:
		_span_box(guides, Vector3(STICK_X0 + 0.05, 2.30, z), Vector3(STICK_X0 + STICK_LEN - 0.05, MAG_BOTTOM - 0.02, z + 0.012))

	# Moving parts, each at its home (its model's origin) and moved by offsets.
	var steel := _mat(0.3, false)
	_surge_stop_body = _body("SurgeStop", steel, SurgeStopScene)
	for z: float in SURGE_STOP_Z:
		_span_box(_surge_stop_body, Vector3(SURGE_STOP_X, 0.06, z - 0.04), Vector3(SURGE_STOP_X + 0.06, SURGE_TOP + 0.18, z + 0.04))
	_layer_stop_body = _pop_stops("LayerStops", LayerStopsScene, LAYER_STOP_X, steel)
	_adjusters = _body("PocketAdjusters", _mat(0.15, false), null)        # UHMW: boards slide up them on the lugs
	_adjusters.add_child(_load_glb(ADJ_MODEL))
	var top: float = UNS_PLATE_H - 0.004
	var t1: float = ADJ_T1
	for z: float in ADJ_Z:
		_slab(_adjusters, _uns_at(ADJ_T0, top - 0.03), _uns_at(ADJ_T0 + ADJ_TAPER, top), z - ADJ_W * 0.5, z + ADJ_W * 0.5, ADJ_DEPTH)
		_slab(_adjusters, _uns_at(ADJ_T0 + ADJ_TAPER, top), _uns_at(t1, top), z - ADJ_W * 0.5, z + ADJ_W * 0.5, ADJ_DEPTH)
	var rack := _static("HoldoverRack", steel)
	for x: float in RACK_ARM_X:
		_span_box(rack, Vector3(x - 0.03, RACK_Y - 0.06, RACK_Z.x), Vector3(x + 0.03, RACK_Y, RACK_Z.y))
		for z0: float in [RACK_Z.x, RACK_Z.y - 0.03]:
			_span_box(rack, Vector3(x - 0.02, RACK_Y, z0), Vector3(x + 0.02, RACK_Y + RACK_PIN_H, z0 + 0.03))
	_divider = _body("CourseDivider", steel, null)
	_divider.add_child(_load_glb(DIVIDER_MODEL))
	for z: float in STOP_Z:
		_span_box(_divider, Vector3(HOLD_STOP_X, INFEED_TOP - DIVIDER_DOWN, z - 0.025),
			Vector3(HOLD_STOP_X + 0.035, INFEED_TOP - DIVIDER_DOWN + DIVIDER_FINGER_H, z + 0.025))
	# UHMW wear strips on the tines: the eased stroke needs at most ~4 m/s2, which 0.15 grip at
	# the boards' 4.5 g still carries, and pulling back they slide out from under the layer
	# instead of dragging it hard into the fence (boards then ride up over each other).
	_forks = _body("Forks", _mat(0.15, false), ForksScene)
	for z: float in FORK_Z:
		_span_box(_forks, Vector3(FORK_X0, FORK_HOME_TOP - FORK_T, z - 0.03), Vector3(FORK_X0 + FORK_LEN, FORK_HOME_TOP, z + 0.03))
	_trolley = TrolleyScene.instantiate()
	_parts.add_child(_trolley)
	_fence = _body("PullbackFence", slick, FenceScene)
	for z: float in FENCE_Z:
		_span_box(_fence, Vector3(FENCE_X - 0.02, FENCE_DOWN, z - 0.03), Vector3(FENCE_X + 0.02, 3.0, z + 0.03))
	_gates = GatesScene.instantiate()
	_parts.add_child(_gates)
	_hoist = _body("Hoist", chain, HoistScene)
	for z: float in HOIST_Z:
		_span_box(_hoist, Vector3(HOIST_X0, HOIST_TOP - 0.10, z - 0.04), Vector3(HOIST_X1, HOIST_TOP, z + 0.04))
	# Outfeed chains and the landing lift rails are real surfaces too: a board that ever comes
	# off the stack lands on them, rides out with the package and is lifted with it, ready for
	# the forklift.
	_out_chains = _static("OutfeedChains", drag)
	for z: float in OUT_Z:
		_lead_in(_out_chains, Vector3(OUT_TAIL, OUT_TOP - 0.02, z - 0.03), Vector3(OUT_HEAD, OUT_TOP, z + 0.03))
	_landing = _body("LandingLift", chain, LandingScene)
	for z: float in LAND_Z:
		_span_box(_landing, Vector3(LAND_X0, LAND_TOP_DOWN - 0.12, z - 0.05), Vector3(LAND_X1, LAND_TOP_DOWN, z + 0.05))
	# Unscrambler lugs: one body per lug, a pusher on every strand.
	var lug_grip := _mat(0.4, false)
	for k in floori(float(_uns.links) / UNS_LUG_EVERY):
		var lug := _body("Lug_%02d" % k, lug_grip, null)
		for z: float in UNS_Z:
			_span_box(lug, Vector3(0.035, UNS_PLATE_H - 0.01, z - 0.035), Vector3(0.062, UNS_PLATE_H + UNS_LUG_HOLD, z + 0.035))
		_lugs.append(lug)
		_lug_on.append(true)
	# Chains and the sticks waiting in the magazines.
	_link_mms[_surge] = [_multimesh("SurgeLinks", LinkScene, _surge.links * SURGE_Z.size()), SURGE_Z, 0]
	_link_mms[_uns] = [_multimesh("UnscramblerLinks", LinkScene, _uns.links * UNS_Z.size()), UNS_Z, UNS_LUG_EVERY]
	_link_mms[_inf] = [_multimesh("InfeedLinks", LinkScene, _inf.links * INF_Z.size()), INF_Z, 0]
	_link_mms[_out] = [_multimesh("OutfeedLinks", LinkScene, _out.links * OUT_Z.size()), OUT_Z, 0]
	_lug_mm = _multimesh("UnscramblerLugs", LugScene, _lugs.size() * UNS_Z.size())
	var mag := _multimesh("MagazineSticks", StickScene, STICK_Z.size() * 12)
	var i: int = 0
	for z: float in STICK_Z:
		for k in 12:
			mag.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(STICK_X0, MAG_BOTTOM + 0.002 + k * (STICK_T + 0.001), z)))
			i += 1


func _pop_stops(stop_name: String, scene: PackedScene, x_face: float, mat: PhysicsMaterial) -> AnimatableBody3D:
	var body := _body(stop_name, mat, scene)
	# Round-edged fingers: the layer's front board, pressed a few mm into their faces, slides
	# endwise past them when the layer is even-ended at the far fence instead of catching an end.
	for z: float in LAYER_STOP_Z:
		var shape := CylinderShape3D.new()
		shape.radius = 0.025
		shape.height = STOP_RISE + 0.02
		var finger := CollisionShape3D.new()
		finger.shape = shape
		finger.position = Vector3(x_face + 0.025, INFEED_TOP - 0.02 + shape.height * 0.5, z)
		body.add_child(finger)
	return body


## A model by path: the imported scene, or straight from the .glb if the editor hasn't
## imported it yet.
static func _load_glb(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("GreenStacker: can't load " + path)
		return Node3D.new()
	return doc.generate_scene(state) as Node3D


func _static(body_name: String, mat: PhysicsMaterial) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.physics_material_override = mat
	_parts.add_child(body)
	return body


func _body(body_name: String, mat: PhysicsMaterial, scene: PackedScene) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = body_name
	body.sync_to_physics = true
	body.physics_material_override = mat
	if scene != null:
		body.add_child(scene.instantiate())
	_parts.add_child(body)
	return body


func _mat(friction: float, rough: bool) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.rough = rough
	m.bounce = 0.0
	return m


func _span_box(body: Node3D, p0: Vector3, p1: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = (p1 - p0).abs()
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = (p0 + p1) * 0.5
	body.add_child(node)


## Collider from p0 to p1 (top at p1.y) made 5 cm deep, its upstream end chamfered 3.5 cm
## over 10 cm: boards sink about 2 cm into chain colliders (Jolt's contact slop under the
## boards' 4.5 g), so a shallower ramp still catches their leading edge.
func _lead_in(body: Node3D, p0: Vector3, p1: Vector3) -> void:
	var node := CollisionShape3D.new()
	node.shape = BinSorter.lead_in_shape(Vector3(p0.x, p1.y - 0.05, p0.z), p1, 0.10, 0.035)
	body.add_child(node)


## A slab whose top face runs from p0 to p1 in the XY plane, z0..z1 across, t thick.
func _slab(body: Node3D, p0: Vector2, p1: Vector2, z0: float, z1: float, t: float) -> void:
	var d: Vector2 = p1 - p0
	var span: float = d.length()
	var u: Vector2 = d / span
	var nrm := Vector2(-u.y, u.x)
	if nrm.y < 0.0:
		nrm = -nrm
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, t, z1 - z0)
	var node := CollisionShape3D.new()
	node.shape = shape
	var mid: Vector2 = (p0 + p1) * 0.5 - nrm * t * 0.5
	node.transform = Transform3D(Basis(Vector3.BACK, atan2(u.y, u.x)), Vector3(mid.x, mid.y, (z0 + z1) * 0.5))
	body.add_child(node)


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

func _place_all() -> void:
	_surge_stop_body.position = Vector3(0.0, -SURGE_STOP_DROP * _surge_stop, 0.0)
	_layer_stop_body.position = Vector3(0.0, -STOP_DROP * _layer_stop, 0.0)
	_divider.position = Vector3(0.0, (DIVIDER_DOWN + doubles_gauge * _gauge_t) * _hold_stop, 0.0)
	var n := Vector2(-sin(UNS_ANGLE), cos(UNS_ANGLE))
	_adjusters.position = Vector3(n.x, n.y, 0.0) * _adj_up
	_forks.position = Vector3(_fork_dx, _fork_dy, 0.0)
	_trolley.position = Vector3(_fork_dx, 0.0, 0.0)
	_fence.position = Vector3(0.0, _fence_up, 0.0)
	_gates.position = Vector3(0.0, _placer_dy, 0.008 * _gate)
	_hoist.position = Vector3(0.0, _hoist_y - HOIST_TOP, 0.0)
	_landing.position = Vector3(0.0, _landing_up, 0.0)
	for roll: Node3D in _roll_nodes:
		roll.basis = Basis(Vector3.RIGHT, -_roll_turn)
	_end_rolls.position = Vector3(0.0, -END_DROP * (1.0 - _end_up), 0.0)
	for drum: Node3D in _end_roll_nodes:
		drum.basis = Basis(Vector3.RIGHT, _end_turn)
	for k in _lugs.size():
		var s: float = _uns.dist + float(k * UNS_LUG_EVERY) * _uns.spacing
		_lugs[k].transform = _link_frame(_uns.at(s), _uns.at(s + _uns.spacing), 0.0)
		# Lugs push from halfway round the foot sprocket (below the pocket floor, so they come
		# up into the pile from underneath) to just past the crest, where the board meets the
		# powered dead plate. Wrapping the head, a lug sits on top of its board and presses it
		# into the plate and the board ahead.
		var m: float = fposmod(s, _uns.total)
		var on: bool = m < _uns.span + 0.05 or m > _uns.total - _uns.arc * 0.5
		if on != _lug_on[k]:
			_lug_on[k] = on
			for shape: Node in _lugs[k].get_children():
				if shape is CollisionShape3D:
					(shape as CollisionShape3D).disabled = not on


func _place_chain_visuals() -> void:
	var lug_i: int = 0
	for loop: ChainLoop in _link_mms:
		var entry: Array = _link_mms[loop]
		var mmi: MultiMeshInstance3D = entry[0]
		var strands: Array[float] = entry[1]
		var every: int = entry[2]
		var i: int = 0
		for k in loop.links:
			var s: float = loop.dist + float(k) * loop.spacing
			var p1: Vector2 = loop.at(s)
			var p2: Vector2 = loop.at(s + loop.spacing)
			for z: float in strands:
				var t: Transform3D = _link_frame(p1, p2, z)
				if every > 0 and k % every == 0 and lug_i < _lug_mm.multimesh.instance_count:
					_lug_mm.multimesh.set_instance_transform(lug_i, t)
					lug_i += 1
					mmi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin))
				else:
					mmi.multimesh.set_instance_transform(i, t)
				i += 1


## Link frame: origin on pin 1, +X along the chord to pin 2, +Z along the pin.
func _link_frame(p1: Vector2, p2: Vector2, z: float) -> Transform3D:
	var d: Vector2 = (p2 - p1).normalized()
	var ux := Vector3(d.x, d.y, 0.0)
	var uz := Vector3.BACK
	return Transform3D(Basis(ux, uz.cross(ux), uz), Vector3(p1.x, p1.y, z))
