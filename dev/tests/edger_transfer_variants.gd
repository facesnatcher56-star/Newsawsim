extends SceneTree

## Controlled experiments on the edger -> landing deck transfer.
##
## Watches one board leave the edger and reports where it comes to rest, how
## much of the tail is still over the edger, and the peak deceleration it saw.
## Variants change one thing at a time so the cause of the hang-up can be
## attributed rather than guessed:
##
##   baseline          nothing changed
##   no_ramps          the deck's lead-in ramp collision is removed
##   slippery_chains   the deck's chain surfaces are made slippery (0.04) so a
##                     board can slide in along X without being braked
##   no_holddowns      the edger's outfeed hold-down pressure is released
##
## Run with:
##   godot --headless --path . --script res://dev/tests/edger_transfer_variants.gd -- <variant>

const LEVEL := "res://game/levels/mill_prototype.tscn"
const EDGER_END_X := 47.80      # world X where the edger's bed finishes
const BOARD_HALF := 2.479
const FRAMES := 1400

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var variant := "baseline"
	var verbose := false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for argument in args:
		if argument == "verbose":
			verbose = true
		elif not argument.begins_with("--"):
			variant = argument

	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await physics_frame
	await physics_frame

	var deck: Node = mill.get_node_or_null("landing_deck_frame")
	var edger: Node = mill.get_node_or_null("SawmillEdger")
	if deck == null or edger == null:
		print("!! missing deck or edger")
		quit()
		return
	_apply_variant(variant, deck, edger)

	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no board")
		quit()
		return
	if active_keeper != null:
		active_keeper.board = board
	print("=== variant: %s | board start x=%.2f ===" % [variant, board.global_position.x])

	var peak_deceleration: float = 0.0
	var previous_vx: float = 0.0
	var settled_frame: int = -1
	var stopped_x: float = 0.0
	for frame in range(FRAMES):
		await physics_frame
		var pos: Vector3 = board.global_position
		var vx: float = board.linear_velocity.x
		if previous_vx > 0.5 and vx < previous_vx:
			peak_deceleration = maxf(peak_deceleration, (previous_vx - vx) * 60.0)
		previous_vx = vx
		if verbose and pos.x > 48.4 and frame % 2 == 0:
			print("      f%04d x=%.3f y=%.3f z=%.3f vx=%.2f freeze=%s sleeping=%s | %s" % [
				frame, pos.x, pos.y, pos.z, vx, str(board.freeze), str(board.sleeping), _braking(board)])
		if frame > 400 and pos.x > 46.0 and absf(board.linear_velocity.length()) < 0.05:
			settled_frame = frame
			stopped_x = pos.x
			break

	if settled_frame < 0:
		print("   board never settled (still at x=%.2f, v=%.2f)" % [
			board.global_position.x, board.linear_velocity.length()])
	else:
		var tail_x: float = stopped_x - BOARD_HALF
		print("   settled at x=%.3f  (tail at %.3f, edger ends at %.2f)  after %d frames" % [
			stopped_x, tail_x, EDGER_END_X, settled_frame])
		print("   tail clearance over the edger: %+.3f m  ->  %s" % [
			tail_x - EDGER_END_X,
			"CLEARED the edger" if tail_x > EDGER_END_X else "STILL ON THE EDGER (%.2f m of board)" % (EDGER_END_X - tail_x)])
		print("   peak deceleration: %.1f m/s^2" % peak_deceleration)
	print("   final z=%.2f  speed=%.3f  rot_y=%.1f" % [
		board.global_position.z, board.linear_velocity.length(), rad_to_deg(board.rotation.y)])
	_probe_ahead_of(board)
	quit()


## Ask the physics space what is sitting right in front of the board's nose,
## and just under it, so the obstruction is named rather than inferred.
func _probe_ahead_of(board: RigidBody3D) -> void:
	var space: PhysicsDirectSpaceState3D = board.get_world_3d().direct_space_state
	if space == null:
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.24, 0.10, 0.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	for offset in [Vector3(2.35, 0.0, 0.0), Vector3(2.7, 0.0, 0.0), Vector3(2.35, -0.06, 0.0)]:
		query.transform = Transform3D(Basis(), board.global_position + offset)
		var hits: Array[Dictionary] = space.intersect_shape(query, 12)
		var names: Array[String] = []
		for hit in hits:
			var collider: Object = hit.get("collider")
			if collider is Node and collider != board:
				names.append(String((collider as Node).get_path()).replace("/root/MillPrototype/", ""))
		print("   probe at nose%+s: %s" % [str(offset), ", ".join(names) if not names.is_empty() else "empty"])

## Emulates an outfeed that keeps driving: the edger's belt and feed rollers are
## re-driven every frame, after the mill's own physics, so a board leaving the
## last hold-down is still being pushed towards the deck.
class DriveKeeper extends Node:
	var edger: Node
	var deck: Node
	var board: RigidBody3D
	var feed_speed: float = 3.8
	var hold_deck_until_clear: bool = false
	const BOARD_HALF := 2.479
	const CLEAR_LOCAL_X := -2.90     # deck-local X of the edger's bed end

	func _physics_process(delta: float) -> void:
		var infeed: Node = edger.get("infeed_system")
		if infeed != null:
			var belt: StaticBody3D = infeed.get("feed_belt")
			if belt != null:
				belt.constant_linear_velocity = (edger as Node3D).global_transform.basis.x.normalized() * feed_speed
			var step: float = (feed_speed / 0.075) * 1.66 * delta
			for roller in infeed.get("feed_rollers"):
				if is_instance_valid(roller):
					(roller as Node3D).rotate_object_local(Vector3.UP, -step)
		if not hold_deck_until_clear or not is_instance_valid(board) or deck == null:
			return
		# Keep the landing deck's chains from carrying (and rotating) the board
		# until the whole board has cleared the edger's bed.
		var tail_local: float = (deck as Node3D).to_local(board.global_position).x - BOARD_HALF
		if tail_local < CLEAR_LOCAL_X:
			for belt in deck.get("_belts"):
				(belt as StaticBody3D).constant_linear_velocity = Vector3.ZERO

var active_keeper: Node = null
var _variant_full: String = ""

func _apply_variant(variant: String, deck: Node, edger: Node) -> void:
	# Variants combine with "+": keep_driving+deck_gate
	_variant_full = variant
	for single in variant.split("+"):
		_apply_single(single, deck, edger)

func _apply_single(variant: String, deck: Node, edger: Node) -> void:
	match variant:
		"no_entry_plate":
			var plate: Node = deck.get_node_or_null("RuntimeParts/EntryPlate")
			if plate != null:
				plate.get_parent().remove_child(plate)
				plate.queue_free()
			print("   [variant] entry plate removed (present now: %s)" % str(deck.get_node_or_null("RuntimeParts/EntryPlate") != null))
		"raise_ramps":
			var ramps: Node = deck.get_node_or_null("RuntimeParts/LandingRampCollisions")
			var lifted: int = 0
			if ramps != null:
				for shape in ramps.get_children():
					if shape is CollisionShape3D:
						(shape as CollisionShape3D).position.y += 0.005
						lifted += 1
			print("   [variant] lifted %d deck ramp plates by 5 mm so their tops meet the chain surface" % lifted)
		"no_downforce":
			var hold_downs: Node = edger.get_node_or_null("HoldDownSystem")
			if hold_downs != null:
				hold_downs.set("hold_down_board_force", 0.0)
			print("   [variant] hold-down downforce disabled (was 260 N)")
		"no_ramps":
			var ramps: Node = deck.get_node_or_null("RuntimeParts/LandingRampCollisions")
			if ramps != null:
				ramps.get_parent().remove_child(ramps)
				ramps.queue_free()
			print("   [variant] ramps still present after removal: %s" % str(deck.get_node_or_null("RuntimeParts/LandingRampCollisions") != null))
		"slippery_chains":
			var slip := PhysicsMaterial.new()
			slip.friction = 0.04
			slip.rough = false
			var belts: Array = deck.get("_belts")
			for belt in belts:
				(belt as StaticBody3D).physics_material_override = slip
			var observed: Array[String] = []
			for belt in belts:
				observed.append("%.2f" % (belt as StaticBody3D).physics_material_override.friction)
			print("   [variant] %d chain surfaces now at friction %s" % [belts.size(), ", ".join(observed)])
		"no_holddowns":
			var raised: float = 0.24
			for station in edger.get("_hold_down_stations"):
				(bump_hold_downs(station, raised))
			print("   [variant] released edger hold-downs")
		"keep_driving":
			var infeed: Node = edger.get("infeed_system")
			var keeper := DriveKeeper.new()
			keeper.edger = edger
			keeper.deck = deck
			keeper.hold_deck_until_clear = _variant_full.contains("deck_gate")
			if infeed != null:
				keeper.feed_speed = float(infeed.get("infeed_chain_feed_speed"))
			keeper.process_priority = 1000
			root.add_child(keeper)
			active_keeper = keeper
			print("   [variant] edger outfeed forced to keep running at %.2f m/s | deck chains held until clear: %s" % [
				keeper.feed_speed, str(keeper.hold_deck_until_clear)])
		_:
			print("   [variant] baseline")

## Top braking contributors for one frame: whoever is pushing the board back
## along -X, ranked by the X component of the impulse they delivered.
func _braking(board: RigidBody3D) -> String:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(board.get_rid())
	if state == null:
		return "no state"
	var per_collider: Dictionary = {}
	var total: float = 0.0
	for i in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(i)
		var name: String = "-"
		if other is Node:
			name = String((other as Node).get_path()).replace("/root/MillPrototype/", "")
		var impulse: Vector3 = state.get_contact_impulse(i)
		if not per_collider.has(name):
			per_collider[name] = [0.0, 0]
		var entry: Array = per_collider[name]
		entry[0] = float(entry[0]) + impulse.x
		entry[1] = int(entry[1]) + 1
		total += impulse.x
	var ranked: Array = []
	for key in per_collider:
		ranked.append([absf(float(per_collider[key][0])), key, float(per_collider[key][0]), int(per_collider[key][1])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts: Array[String] = []
	for entry in ranked.slice(0, 3):
		parts.append("%s %+.1f x%d" % [entry[1], entry[2], entry[3]])
	return "sum_x=%+.1f | %s" % [total, " ; ".join(parts)]

func bump_hold_downs(station: Dictionary, raised: float) -> void:
	var nodes: Array = station.get("nodes", [])
	var bases: Array = station.get("bases", [])
	for i in range(nodes.size()):
		var node := nodes[i] as Node3D
		if node == null or i >= bases.size():
			continue
		node.position = (bases[i] as Vector3) + Vector3(0.0, raised, 0.0)

func _pick_board(mill: Node) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_distance: float = 1e9
	for node in mill.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if body == null or body.freeze or not body.is_in_group("cut_boards"):
			continue
		if body.global_position.x > 44.0:
			continue
		var distance: float = absf(body.global_position.z - 18.29)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best
