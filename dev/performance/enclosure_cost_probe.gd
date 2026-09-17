extends SceneTree

## A/B probe for the mill enclosure's runtime cost.
##
## Loads the level, prints the per-section inventory, then measures the running
## scene four times so the drift of the continuously simulated mill can be told
## apart from a real difference:
##
##   A  full scene, building with its 12 shadow-casting work lights
##   B  building present but work_lights off (geometry only, no lights)
##   C  building removed entirely
##   D  full scene again (drift bracket)
##
## Run with:
##   godot --headless --path . --script res://dev/performance/enclosure_cost_probe.gd
## The absolute frame times are headless/offscreen numbers; the deltas between
## phases are the point.

const LEVEL := "res://game/levels/mill_prototype.tscn"
const SETTLE_FRAMES := 60
const MEASURE_FRAMES := 300

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mill: Node = load(LEVEL).instantiate()
	root.add_child(mill)
	current_scene = mill
	await _advance(SETTLE_FRAMES * 2)

	var recorder: Node = root.get_node("PerformanceRecorder")
	print("\n=== SECTION INVENTORY ===")
	print("%-18s %7s %8s %9s %7s %7s %6s %10s" % ["section", "nodes", "visuals", "multimesh", "shapes", "bodies", "lights", "tris"])
	for child in mill.get_children():
		var row: Dictionary = recorder.call("_inventory_for_subtree", child)
		print("%-18s %7d %8d %9d %7d %7d %6d %10d" % [
			String(child.name), int(row.total_nodes), int(row.visual_instances),
			int(row.multimesh_instances), int(row.collision_shapes), int(row.physics_bodies),
			int(row.lights), int(row.estimated_triangles)])

	var building: Node = mill.get_node("MillBuilding")
	var parent: Node = building.get_parent()
	var index: int = building.get_index()
	var sun: DirectionalLight3D = mill.get_node("DirectionalLight3D")

	print("\n=== PHASES ===")
	if Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) <= 0.0:
		print("NOTE: this run has no rendering device, so draw calls, rendered fps and vram below are")
		print("      meaningless - only the process/physics deltas mean anything. Measure the render")
		print("      cost from a windowed run instead, with the in-game F10 isolation benchmark.")
	await _measure("A  full scene", MEASURE_FRAMES)
	building.set("work_lights", false)
	await _advance(SETTLE_FRAMES)
	await _measure("B  no work lights", MEASURE_FRAMES)
	building.set("work_lights", true)
	parent.remove_child(building)
	await _advance(SETTLE_FRAMES)
	await _measure("C  no building at all", MEASURE_FRAMES)
	parent.add_child(building)
	parent.move_child(building, index)
	sun.shadow_enabled = false
	await _advance(SETTLE_FRAMES)
	await _measure("D  no sun shadow", MEASURE_FRAMES)
	sun.shadow_enabled = true
	await _advance(SETTLE_FRAMES)
	await _measure("E  full scene again", MEASURE_FRAMES)
	quit()

func _advance(frames: int) -> void:
	for i in range(frames):
		await physics_frame

func _measure(label: String, frames: int) -> void:
	var draws: float = 0.0
	var objects: float = 0.0
	var primitives: float = 0.0
	var video: float = 0.0
	var process_ms: float = 0.0
	var physics_ms: float = 0.0
	var samples: int = 0
	var started: int = Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		video += Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		samples += 1
	var divisor: float = maxf(1.0, float(samples))
	var wall_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	print("%-22s %7.0f draws | %7.0f objects | %9.0f prims | %5.0f MB vram | render fps %6.1f | process %6.2f ms | physics %6.2f ms" % [
		label, draws / divisor, objects / divisor, primitives / divisor, video / divisor,
		float(samples) * 1000.0 / maxf(wall_ms, 1.0), process_ms / divisor, physics_ms / divisor])
