extends Node

## jack_ladder_controller.gd
## Master controller for the jack ladder + live log deck system.
## State machine:
##   IDLE → LOG_AT_STOP → WAITING_CARRIAGE_HOME → TIPPING → RETRACTING → IDLE
##
## Also absorbs carriage flip-assist from the old headrig_log_loader.gd:
##   When carriage enters UNDOGGING_FOR_FLIP or FLIPPING_LOG the tilter arm
##   rises to help roll the log, then retracts after the flip is done.

# ─── Exported node paths ────────────────────────────────────────────────────
@export_node_path("Node3D") var carriage_path: NodePath
@export_node_path("StaticBody3D") var incline_path: NodePath
@export_node_path("StaticBody3D") var deck_path: NodePath

# ─── State machine ────────────────────────────────────────────────────────
enum State {
	IDLE,
	LOG_AT_STOP,
	WAITING_CARRIAGE_HOME,
	TIPPING,
	RETRACTING,
	FLIP_ASSIST,
	FLIP_RETRACTING
}

# ─── Carriage state constants (mirror headrig_carriage.gd enums) ───────────
const CARRIAGE_WAITING_FOR_LOG     := 0
const CARRIAGE_UNDOGGING_FOR_FLIP  := 6   # State.UNDOGGING_FOR_FLIP
const CARRIAGE_FLIPPING_LOG        := 7   # State.FLIPPING_LOG

var _state: State = State.IDLE
var _carriage: Node3D = null
var _incline: Node3D = null
var _deck: Node3D = null
var _stop: Node3D = null       # log_stop.gd AnimatableBody3D
var _tilter: Node3D = null     # pneumatic_tilter.gd AnimatableBody3D
var _trigger: Area3D = null    # Area3D just before the stop — detects log presence

func _ready() -> void:
	# Resolve node references after scene is ready
	await get_tree().process_frame
	_carriage = get_node_or_null(carriage_path) as Node3D
	_incline   = get_node_or_null(incline_path) as Node3D
	_deck      = get_node_or_null(deck_path) as Node3D

	if _deck:
		_stop    = _deck.get_node_or_null("LogStop")
		_tilter  = _deck.get_node_or_null("PneumaticTilter")
		_trigger = _deck.get_node_or_null("LogStop/TriggerArea")

	if _trigger:
		_trigger.body_entered.connect(_on_log_entered_stop)

	# Connect tilter signals
	if _tilter:
		_tilter.tip_complete.connect(_on_tip_complete)
		_tilter.retract_complete.connect(_on_retract_complete)

	print("[JACK LADDER CTRL] Ready. Carriage: ", _carriage != null,
		"  Incline: ", _incline != null, "  Deck: ", _deck != null)

func _physics_process(_delta: float) -> void:
	if _carriage == null:
		_carriage = get_node_or_null(carriage_path) as Node3D
		if _carriage == null:
			return

	var cs := _carriage.get("current_state") as int

	# ── Flip assist intercept (highest priority) ─────────────────────────
	if (cs == CARRIAGE_UNDOGGING_FOR_FLIP or cs == CARRIAGE_FLIPPING_LOG):
		if _state != State.FLIP_ASSIST and _state != State.FLIP_RETRACTING:
			_enter_flip_assist()
		return

	# ── If we were flip-assisting and carriage has finished, clean up ────
	if _state == State.FLIP_ASSIST:
		if cs != CARRIAGE_UNDOGGING_FOR_FLIP and cs != CARRIAGE_FLIPPING_LOG:
			_state = State.FLIP_RETRACTING
			_retract_tilter()
		return

	if _state == State.FLIP_RETRACTING:
		# Wait for retract_complete signal
		return

	# ── Normal loading state machine ─────────────────────────────────────
	match _state:
		State.IDLE:
			_set_deck_running(true)
			_set_incline_running(true)

		State.LOG_AT_STOP:
			# Stop the deck chains so trailing logs don't pile into the stop
			_set_deck_running(false)
			# Check if carriage is home and waiting
			var carriage_at_home := _carriage_is_home()
			if cs == CARRIAGE_WAITING_FOR_LOG and carriage_at_home:
				_state = State.WAITING_CARRIAGE_HOME
				print("[JACK LADDER CTRL] Carriage home & waiting. Preparing to tip log.")

		State.WAITING_CARRIAGE_HOME:
			# Small guard — only tip if stop has a log
			if _trigger and _has_log_in_area(_trigger):
				_state = State.TIPPING
				_begin_tip()
			else:
				# Log somehow left — back to idle
				_state = State.IDLE

		State.TIPPING:
			# Awaiting tip_complete signal
			pass

		State.RETRACTING:
			# Awaiting retract_complete signal
			pass

func _on_log_entered_stop(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("logs"):
		if _state == State.IDLE:
			_state = State.LOG_AT_STOP
			print("[JACK LADDER CTRL] Log reached stop. Pausing deck chains.")

func _on_tip_complete() -> void:
	if _state == State.TIPPING:
		print("[JACK LADDER CTRL] Tip complete. Retracting tilter.")
		_state = State.RETRACTING
		_retract_after_tip()

func _on_retract_complete() -> void:
	match _state:
		State.RETRACTING:
			# Extend the stop again and resume deck for next log
			if _stop:
				_stop.extend()
			_state = State.IDLE
			# Allow a half-second for next log to settle before running
			await get_tree().create_timer(0.5).timeout
			_set_deck_running(true)
			print("[JACK LADDER CTRL] Tilter retracted. Deck resuming.")

		State.FLIP_RETRACTING:
			_state = State.IDLE
			print("[JACK LADDER CTRL] Flip assist retracted. Returning to IDLE.")

# ─── Helpers ────────────────────────────────────────────────────────────────

func _begin_tip() -> void:
	# Retract the stop bar, then fire the tilter
	if _stop:
		_stop.retract()
	if _tilter:
		_tilter.tip()
	print("[JACK LADDER CTRL] Tilter firing.")

func _retract_after_tip() -> void:
	if _tilter:
		_tilter.retract()

func _retract_tilter() -> void:
	if _tilter:
		_tilter.retract()

func _enter_flip_assist() -> void:
	_state = State.FLIP_ASSIST
	_set_deck_running(false)
	if _tilter:
		_tilter.tip()
	print("[JACK LADDER CTRL] Flip assist active — tilter raised.")

func _set_deck_running(on: bool) -> void:
	if _deck and _deck.has_method("set_running"):
		_deck.set_running(on)

func _set_incline_running(on: bool) -> void:
	if _incline and _incline.has_method("set_running"):
		_incline.set_running(on)

func _carriage_is_home() -> bool:
	if _carriage == null:
		return false
	# Carriage home: progress ~0. Check via current_state being WAITING or position Z close to start
	# We use the carriage's own "current_progress" if exposed
	var prog = _carriage.get("current_progress")
	if prog != null:
		return prog < 0.05
	return false

func _has_log_in_area(area: Area3D) -> bool:
	for body in area.get_overlapping_bodies():
		if body is RigidBody3D and body.is_in_group("logs"):
			return true
	return false
