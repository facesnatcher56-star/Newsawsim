class_name RenderRegressionProbe
extends SceneTree

## Windowed A/B probe for the current mill render regression.
## Run without --headless so RenderingServer timing and draw counts are real.

const LEVEL := "res://game/levels/mill_prototype.tscn"
const SETTLE_FRAMES := 20
const MEASURE_FRAMES := 60

var _mill: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mill = load(LEVEL).instantiate() as Node3D
	root.add_child(_mill)
	current_scene = _mill
	await _advance(60)

	var sorter: Node3D = _mill.get_node("BinSorter") as Node3D
	var cradles: Node3D = sorter.get_node("CradleVisuals") as Node3D
	var chains: Node3D = sorter.get_node("SorterChainSystem") as Node3D
	var incline: Node3D = _mill.get_node("BoardLugIncline") as Node3D
	var landing: Node3D = _mill.get_node("landing_deck_frame") as Node3D
	var building: Node3D = _mill.get_node("MillBuilding") as Node3D
	var sun: DirectionalLight3D = _mill.get_node("DirectionalLight3D") as DirectionalLight3D

	print("\n=== WINDOWED RENDER REGRESSION PROBE ===")
	await _measure("baseline")

	cradles.visible = false
	await _settle_measure("no cradle visuals")
	cradles.visible = true

	chains.visible = false
	await _settle_measure("no sorter chains")
	chains.visible = true

	sorter.visible = false
	await _settle_measure("sorter hidden")
	sorter.visible = true

	incline.visible = false
	await _settle_measure("incline hidden")
	incline.visible = true

	landing.visible = false
	await _settle_measure("landing deck hidden")
	landing.visible = true

	building.set("work_lights", false)
	await _settle_measure("no work lights")
	building.set("work_lights", true)

	var original_sun_shadows: bool = sun.shadow_enabled
	sun.shadow_enabled = not original_sun_shadows
	await _settle_measure("sun shadows enabled" if sun.shadow_enabled else "sun shadows disabled")
	sun.shadow_enabled = original_sun_shadows

	await _settle_measure("baseline restored")
	quit()


func _settle_measure(label: String) -> void:
	await _advance(SETTLE_FRAMES)
	await _measure(label)


func _advance(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await process_frame


func _measure(label: String) -> void:
	var draws: float = 0.0
	var objects: float = 0.0
	var primitives: float = 0.0
	var process_ms: float = 0.0
	var physics_ms: float = 0.0
	var started_usec: int = Time.get_ticks_usec()
	for _index: int in range(MEASURE_FRAMES):
		await process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	var divisor: float = float(MEASURE_FRAMES)
	print("%-24s fps=%6.1f draws=%7.0f objects=%7.0f prims=%9.0f process=%6.2fms physics=%6.2fms" % [
		label,
		divisor * 1000.0 / maxf(elapsed_ms, 1.0),
		draws / divisor,
		objects / divisor,
		primitives / divisor,
		process_ms / divisor,
		physics_ms / divisor,
	])
