@tool
class_name EdgerInfeedSystem
extends Node3D

var edger: SawmillEdger

@export_category("Infeed Chain")
@export_range(0.1, 8.0, 0.1, "or_greater") var infeed_chain_feed_speed: float = 1.4
@export_range(0.0, 20.0, 0.1, "or_greater") var feed_roller_spin_speed: float = 1.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var board_feed_force: float = 420.0

var feed_rollers: Array[Node3D] = []
var chain_links: Array[Node3D] = []
var chain_bases: Array[Vector3] = []
var chain_travel: float = 0.0


func _ready() -> void:
	edger = get_parent() as SawmillEdger


func clear() -> void:
	feed_rollers.clear()
	chain_links.clear()
	chain_bases.clear()
	chain_travel = 0.0


func spin(delta: float) -> void:
	var any_down := false
	for station in edger._infeed_hold_down_stations:
		if bool(station.get("down", false)):
			any_down = true
			break
	if not any_down:
		for station in edger._hold_down_stations:
			if bool(station.get("down", false)):
				any_down = true
				break
	if not any_down:
		return

	var feed_step := (infeed_chain_feed_speed / maxf(edger.FEED_ROLLER_RADIUS, 0.001)) * feed_roller_spin_speed * delta
	for roller in feed_rollers:
		if is_instance_valid(roller):
			roller.rotate_object_local(Vector3.UP, -feed_step)

	var chain_start_x := edger._infeed_chain_start_x()
	var chain_length := edger.INFEED_CHAIN_END_X - chain_start_x
	if chain_length > 0.0:
		var chain_step := infeed_chain_feed_speed * delta
		chain_travel = fmod(chain_travel + chain_step, chain_length)
		for i in range(chain_links.size()):
			var link := chain_links[i]
			if is_instance_valid(link):
				var base_x := chain_bases[i].x
				link.position.x = chain_start_x + fmod((base_x - chain_start_x) + chain_travel, chain_length)


func apply_feed_contact(body: RigidBody3D, local_center: Vector3) -> void:
	if not edger._board_overlaps_x_range(local_center.x, edger._infeed_chain_start_x(), edger.bed_length * 0.5):
		return
	if not edger._real_ramps_are_home(edger._parking_ramp_nodes()):
		return

	var x_axis := edger.global_transform.basis.x.normalized()
	var current_speed := body.linear_velocity.dot(x_axis)
	var speed_error := infeed_chain_feed_speed - current_speed
	var force := clampf(speed_error * body.mass * 18.0, -board_feed_force, board_feed_force)
	body.apply_central_force(x_axis * force)
