extends SceneTree

## Bench: average wall-clock cost per physics frame for the whole mill, headless (no rendering).
## Compare before/after a change. Run: godot --headless --path . --script res://dev/performance/physics_cost_bench.gd

const FRAMES := 900
const WARMUP := 120


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mill: Node = (load("res://game/levels/mill_prototype.tscn") as PackedScene).instantiate()
	root.add_child(mill)
	current_scene = mill
	for i in WARMUP:
		await physics_frame
	var start: int = Time.get_ticks_usec()
	for i in FRAMES:
		await physics_frame
	var per_frame_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(FRAMES)
	print("BENCH ms per physics frame: %.3f" % per_frame_ms)
	quit()
