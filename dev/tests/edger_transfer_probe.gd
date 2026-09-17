extends SceneTree

## Diagnostic probe for the board transfer from the edger onto the landing deck.
##
## Prints, per physics frame, the tracked board's speed and where it is, which
## bodies it is touching, and whether the landing deck's chain drive is engaged.
## That separates the two candidate causes:
##   - the board is caught on something hard that eats its momentum, or
##   - the board is simply no longer being driven across the gap.
##
## Run with:
##   godot --headless --path . --script res://dev/tests/edger_transfer_probe.gd

const LEVEL := "res://game/levels/mill_prototype.tscn"
const FRAMES := 900
const REPORT_EVERY := 10

class BoardMonitor extends Node:
	var board: RigidBody3D
	var deck: Node
	var edger: Node
	var events: Array[String] = []

	func _ready() -> void:
		if board == null:
			return
		board.contact_monitor = true
		board.max_contacts_reported = 8
		board.body_entered.connect(_on_entered)
		board.body_exited.connect(_on_exited)

	func _on_entered(body: Node) -> void:
		if body == null:
			return
		events.append("      f%04d  START touching %s" % [Engine.get_physics_frames(), _label(body)])

	func _on_exited(body: Node) -> void:
		if body == null:
			return
		events.append("      f%04d  STOP  touching %s" % [Engine.get_physics_frames(), _label(body)])

	func _label(body: Node) -> String:
		return String(body.get_path()).replace("/root/MillPrototype/", "")

	func colliders() -> Array[String]:
		var out: Array[String] = []
		if board == null:
			return out
		for body in board.get_colliding_bodies():
			var name := _label(body)
			if not out.has(name):
				out.append(name)
		return out

func _init() -> void:
	call_deferred("run")

func run() -> void:
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

	var board: RigidBody3D = _pick_board(mill)
	if board == null:
		print("!! no cut board found in the mill")
		quit()
		return
	print("tracking %s  start=%s" % [board.name, board.global_position.snapped(Vector3(0.01, 0.01, 0.01))])
	print("deck origin=%s   edger origin=%s" % [
		(deck as Node3D).global_position, (edger as Node3D).global_position])

	var monitor := BoardMonitor.new()
	monitor.board = board
	monitor.deck = deck
	monitor.edger = edger
	root.add_child(monitor)
	await physics_frame

	print("\n frame     x       z       y    |v|     v.x    | deck speed  entering | touching")
	for frame in range(FRAMES):
		await physics_frame
		if frame % REPORT_EVERY != 0:
			continue
		var pos: Vector3 = board.global_position
		var vel: Vector3 = board.linear_velocity
		var colliders: Array = monitor.colliders()
		print("%5d  %7.3f %7.3f %7.3f  %5.2f  %6.2f   | %7.3f  %s | %s" % [
			frame, pos.x, pos.z, pos.y, vel.length(), vel.x,
			float(deck.get("actual_speed")), str(deck.call("_is_board_entering")),
			", ".join(colliders) if not colliders.is_empty() else "-"])
		if frame > 120 and pos.x > 50.0 and vel.length() < 0.05:
			print("      board settled at x=%.3f after %d frames" % [pos.x, frame])
			break

	print("\n=== contact event log ===")
	for entry in monitor.events:
		print(entry)
	quit()

func _pick_board(mill: Node) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_distance: float = 1e9
	for node in mill.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if body == null or body.freeze or not body.is_in_group("cut_boards"):
			continue
		if body.global_position.x > 46.0:
			continue
		var distance: float = absf(body.global_position.z - 18.29)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best
