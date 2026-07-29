extends Node

const LOG_ROOT := "res://dev/performance/logs"
const SAMPLE_INTERVAL_SECONDS := 0.25
const SUMMARY_CHECKPOINT_INTERVAL_SECONDS := 60.0
const SESSION_WARMUP_SECONDS := 5.0
const SPIKE_THRESHOLD_MS := 25.0
const MAX_FRAME_SAMPLES := 120000
const ISOLATION_WARMUP_SECONDS := 4.0
const ISOLATION_SETTLE_SECONDS := 1.5
const ISOLATION_MEASURE_SECONDS := 5.0

const ISOLATION_CANDIDATES: PackedStringArray = [
	"SkyClouds",
	"Ground",
	"DebarkerStation",
	"LogFeedStation",
	"HeadrigStation",
	"InclineOutfeed",
	"EdgerTakeAway",
	"SawmillEdger",
	"BinSorter",
]

var _enabled := false
var _elapsed_seconds := 0.0
var _sample_accumulator := 0.0
var _summary_checkpoint_accumulator := 0.0
var _session_id := ""
var _session_dir := ""
var _samples_file: FileAccess
var _spikes_file: FileAccess
var _frame_times_ms: Array[float] = []
var _process_times_ms: Array[float] = []
var _physics_times_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _active_physics: Array[float] = []
var _phase := "startup"
var _warmup_complete := false
var _benchmark_running := false
var _phase_measuring := false
var _phase_frame_sum_ms := 0.0
var _phase_frame_max_ms := 0.0
var _phase_frame_count := 0
var _phase_monitor_sums: Dictionary = {}
var _phase_monitor_count := 0
var _isolation_results: Array[Dictionary] = []


func _ready() -> void:
	if not OS.is_debug_build():
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	_enabled = true
	process_priority = -1000
	set_process_unhandled_input(true)
	_start_session()
	call_deferred("_capture_inventory")
	print("[PerformanceRecorder] Recording to: %s" % _session_dir)
	print("[PerformanceRecorder] Press F10 in the running game to start the controlled station-isolation benchmark.")


func _process(delta: float) -> void:
	if not _enabled:
		return

	_elapsed_seconds += delta
	_sample_accumulator += delta
	_summary_checkpoint_accumulator += delta
	if not _warmup_complete and _elapsed_seconds >= SESSION_WARMUP_SECONDS:
		_warmup_complete = true
		_phase = "normal"
		_frame_times_ms.clear()
		_process_times_ms.clear()
		_physics_times_ms.clear()
		_draw_calls.clear()
		_active_physics.clear()
		print("[PerformanceRecorder] Startup warmup complete; steady-state summary collection started.")
	var frame_ms := delta * 1000.0
	_append_bounded(_frame_times_ms, frame_ms)

	if _phase_measuring:
		_phase_frame_sum_ms += frame_ms
		_phase_frame_max_ms = maxf(_phase_frame_max_ms, frame_ms)
		_phase_frame_count += 1

	if frame_ms >= SPIKE_THRESHOLD_MS:
		_write_spike(frame_ms)

	if _sample_accumulator >= SAMPLE_INTERVAL_SECONDS:
		_sample_accumulator = fmod(_sample_accumulator, SAMPLE_INTERVAL_SECONDS)
		_write_sample(frame_ms)

	if _summary_checkpoint_accumulator >= SUMMARY_CHECKPOINT_INTERVAL_SECONDS:
		_summary_checkpoint_accumulator = fmod(
			_summary_checkpoint_accumulator,
			SUMMARY_CHECKPOINT_INTERVAL_SECONDS
		)
		_write_summary()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _enabled or _benchmark_running:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		_start_isolation_benchmark()


func _exit_tree() -> void:
	if not _enabled:
		return
	_write_summary()
	if _samples_file != null:
		_samples_file.flush()
		_samples_file.close()
	if _spikes_file != null:
		_spikes_file.flush()
		_spikes_file.close()


func _start_session() -> void:
	_session_id = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	_session_dir = LOG_ROOT.path_join(_session_id)
	var absolute_dir := ProjectSettings.globalize_path(_session_dir)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK:
		_session_dir = "user://performance_logs".path_join(_session_id)
		absolute_dir = ProjectSettings.globalize_path(_session_dir)
		DirAccess.make_dir_recursive_absolute(absolute_dir)

	_samples_file = FileAccess.open(_session_dir.path_join("samples.csv"), FileAccess.WRITE)
	_spikes_file = FileAccess.open(_session_dir.path_join("spikes.csv"), FileAccess.WRITE)
	if _samples_file == null or _spikes_file == null:
		push_error("[PerformanceRecorder] Could not open performance log files in %s" % _session_dir)
		_enabled = false
		return

	_samples_file.store_line("elapsed_s,phase,fps,frame_ms,process_ms,physics_ms,navigation_ms,draw_calls,objects_drawn,primitives,video_mem_mb,texture_mem_mb,buffer_mem_mb,static_mem_mb,node_count,object_count,resource_count,orphan_nodes,physics_active,collision_pairs,physics_islands,audio_latency_ms")
	_spikes_file.store_line("elapsed_s,phase,frame_ms,fps,process_ms,physics_ms,draw_calls,objects_drawn,primitives,physics_active,collision_pairs,node_count,video_mem_mb")


func _write_sample(frame_ms: float) -> void:
	var metrics := _read_metrics()
	_append_bounded(_process_times_ms, metrics.process_ms)
	_append_bounded(_physics_times_ms, metrics.physics_ms)
	_append_bounded(_draw_calls, metrics.draw_calls)
	_append_bounded(_active_physics, metrics.physics_active)

	_samples_file.store_csv_line(PackedStringArray([
		_fmt(_elapsed_seconds), _phase, _fmt(metrics.fps), _fmt(frame_ms),
		_fmt(metrics.process_ms), _fmt(metrics.physics_ms), _fmt(metrics.navigation_ms),
		_fmt(metrics.draw_calls), _fmt(metrics.objects_drawn), _fmt(metrics.primitives),
		_fmt(metrics.video_mem_mb), _fmt(metrics.texture_mem_mb), _fmt(metrics.buffer_mem_mb),
		_fmt(metrics.static_mem_mb), _fmt(metrics.node_count), _fmt(metrics.object_count),
		_fmt(metrics.resource_count), _fmt(metrics.orphan_nodes), _fmt(metrics.physics_active),
		_fmt(metrics.collision_pairs), _fmt(metrics.physics_islands), _fmt(metrics.audio_latency_ms),
	]))

	if _phase_measuring:
		_accumulate_phase_metrics(metrics)

	if int(_elapsed_seconds * 4.0) % 4 == 0:
		_samples_file.flush()
		_spikes_file.flush()


func _write_spike(frame_ms: float) -> void:
	if _spikes_file == null:
		return
	var metrics := _read_metrics()
	_spikes_file.store_csv_line(PackedStringArray([
		_fmt(_elapsed_seconds), _phase, _fmt(frame_ms), _fmt(metrics.fps),
		_fmt(metrics.process_ms), _fmt(metrics.physics_ms), _fmt(metrics.draw_calls),
		_fmt(metrics.objects_drawn), _fmt(metrics.primitives), _fmt(metrics.physics_active),
		_fmt(metrics.collision_pairs), _fmt(metrics.node_count), _fmt(metrics.video_mem_mb),
	]))


func _read_metrics() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"navigation_ms": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"static_mem_mb": _bytes_to_mb(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_active": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_islands": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		"audio_latency_ms": Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY) * 1000.0,
	}


func _capture_inventory() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		await get_tree().process_frame
		scene = get_tree().current_scene
	if scene == null:
		return

	var inventory_file := FileAccess.open(_session_dir.path_join("inventory.csv"), FileAccess.WRITE)
	if inventory_file == null:
		return
	inventory_file.store_line("section,total_nodes,scripted_nodes,process_nodes,physics_process_nodes,physics_bodies,areas,collision_shapes,visual_instances,multimesh_instances,estimated_triangles,lights,particles,animation_players,audio_players")
	for child in scene.get_children():
		var row := _inventory_for_subtree(child)
		inventory_file.store_csv_line(PackedStringArray([
			str(child.name), str(row.total_nodes), str(row.scripted_nodes), str(row.process_nodes),
			str(row.physics_process_nodes), str(row.physics_bodies), str(row.areas),
			str(row.collision_shapes), str(row.visual_instances), str(row.multimesh_instances),
			str(row.estimated_triangles), str(row.lights), str(row.particles),
			str(row.animation_players), str(row.audio_players),
		]))
	inventory_file.close()


func _inventory_for_subtree(root: Node) -> Dictionary:
	var result := {
		"total_nodes": 0,
		"scripted_nodes": 0,
		"process_nodes": 0,
		"physics_process_nodes": 0,
		"physics_bodies": 0,
		"areas": 0,
		"collision_shapes": 0,
		"visual_instances": 0,
		"multimesh_instances": 0,
		"estimated_triangles": 0,
		"lights": 0,
		"particles": 0,
		"animation_players": 0,
		"audio_players": 0,
	}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		result.total_nodes += 1
		if node.get_script() != null:
			result.scripted_nodes += 1
		if node.is_processing():
			result.process_nodes += 1
		if node.is_physics_processing():
			result.physics_process_nodes += 1
		if node is PhysicsBody3D:
			result.physics_bodies += 1
		if node is Area3D:
			result.areas += 1
		if node is CollisionShape3D and not node.disabled:
			result.collision_shapes += 1
		if node is VisualInstance3D:
			result.visual_instances += 1
		if node is MeshInstance3D and node.mesh != null:
			result.estimated_triangles += _mesh_triangle_count(node.mesh)
		if node is MultiMeshInstance3D and node.multimesh != null:
			result.multimesh_instances += node.multimesh.instance_count
			if node.multimesh.mesh != null:
				result.estimated_triangles += _mesh_triangle_count(node.multimesh.mesh) * node.multimesh.instance_count
		if node is Light3D:
			result.lights += 1
		if node is GPUParticles3D or node is CPUParticles3D:
			result.particles += 1
		if node is AnimationPlayer:
			result.animation_players += 1
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			result.audio_players += 1
		for child in node.get_children():
			stack.append(child)
	return result


func _mesh_triangle_count(mesh: Mesh) -> int:
	var triangles := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			triangles += int(indices.size() / 3)
		else:
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if vertices != null:
				triangles += int(vertices.size() / 3)
	return triangles


func _start_isolation_benchmark() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	_isolation_results.clear()
	print("[PerformanceRecorder] Isolation benchmark started. Do not interact with the game until it finishes.")
	_phase = "isolation:warmup"
	await get_tree().create_timer(ISOLATION_WARMUP_SECONDS).timeout
	await _measure_phase("baseline", ISOLATION_MEASURE_SECONDS)

	var scene := get_tree().current_scene
	for candidate_name in ISOLATION_CANDIDATES:
		var candidate := scene.get_node_or_null(NodePath(candidate_name))
		if candidate == null or candidate.get_parent() == null:
			continue
		var parent := candidate.get_parent()
		var original_index := candidate.get_index()
		parent.remove_child(candidate)
		_phase = "settling_without:%s" % candidate_name
		await get_tree().create_timer(ISOLATION_SETTLE_SECONDS).timeout
		await _measure_phase("without:%s" % candidate_name, ISOLATION_MEASURE_SECONDS)
		parent.add_child(candidate)
		parent.move_child(candidate, original_index)
		_phase = "restoring:%s" % candidate_name
		await get_tree().create_timer(ISOLATION_SETTLE_SECONDS).timeout

	_phase = "normal"
	_write_isolation_results()
	_write_summary()
	_benchmark_running = false
	print("[PerformanceRecorder] Isolation benchmark finished: %s" % _session_dir.path_join("isolation.csv"))


func _measure_phase(label: String, duration_seconds: float) -> void:
	_phase = label
	_reset_phase_accumulator()
	_phase_measuring = true
	await get_tree().create_timer(duration_seconds).timeout
	_phase_measuring = false
	_isolation_results.append(_finish_phase_result(label))


func _reset_phase_accumulator() -> void:
	_phase_frame_sum_ms = 0.0
	_phase_frame_max_ms = 0.0
	_phase_frame_count = 0
	_phase_monitor_sums = {
		"fps": 0.0, "process_ms": 0.0, "physics_ms": 0.0, "draw_calls": 0.0,
		"objects_drawn": 0.0, "primitives": 0.0, "physics_active": 0.0,
		"collision_pairs": 0.0, "video_mem_mb": 0.0,
	}
	_phase_monitor_count = 0


func _accumulate_phase_metrics(metrics: Dictionary) -> void:
	for key in _phase_monitor_sums:
		_phase_monitor_sums[key] = float(_phase_monitor_sums[key]) + float(metrics[key])
	_phase_monitor_count += 1


func _finish_phase_result(label: String) -> Dictionary:
	var divisor := maxf(1.0, float(_phase_monitor_count))
	var result := {
		"phase": label,
		"frame_ms_avg": _phase_frame_sum_ms / maxf(1.0, float(_phase_frame_count)),
		"frame_ms_max": _phase_frame_max_ms,
	}
	for key in _phase_monitor_sums:
		result[key] = float(_phase_monitor_sums[key]) / divisor
	return result


func _write_isolation_results() -> void:
	var file := FileAccess.open(_session_dir.path_join("isolation.csv"), FileAccess.WRITE)
	if file == null:
		return
	file.store_line("phase,fps_avg,frame_ms_avg,frame_ms_max,process_ms_avg,physics_ms_avg,draw_calls_avg,objects_drawn_avg,primitives_avg,physics_active_avg,collision_pairs_avg,video_mem_mb_avg")
	for row in _isolation_results:
		file.store_csv_line(PackedStringArray([
			row.phase, _fmt(row.fps), _fmt(row.frame_ms_avg), _fmt(row.frame_ms_max),
			_fmt(row.process_ms), _fmt(row.physics_ms), _fmt(row.draw_calls),
			_fmt(row.objects_drawn), _fmt(row.primitives), _fmt(row.physics_active),
			_fmt(row.collision_pairs), _fmt(row.video_mem_mb),
		]))
	file.close()


func _write_summary() -> void:
	if _frame_times_ms.is_empty():
		return
	var file := FileAccess.open(_session_dir.path_join("summary.csv"), FileAccess.WRITE)
	if file == null:
		return
	file.store_line("metric,average,p50,p95,p99,maximum")
	_write_summary_row(file, "frame_ms", _frame_times_ms)
	_write_summary_row(file, "process_ms", _process_times_ms)
	_write_summary_row(file, "physics_ms", _physics_times_ms)
	_write_summary_row(file, "draw_calls", _draw_calls)
	_write_summary_row(file, "active_physics", _active_physics)
	file.close()


func _write_summary_row(file: FileAccess, metric: String, values: Array[float]) -> void:
	if values.is_empty():
		return
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	file.store_csv_line(PackedStringArray([
		metric, _fmt(total / values.size()), _fmt(_percentile(sorted, 0.50)),
		_fmt(_percentile(sorted, 0.95)), _fmt(_percentile(sorted, 0.99)),
		_fmt(sorted.back()),
	]))


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil((sorted_values.size() - 1) * fraction)), 0, sorted_values.size() - 1)
	return sorted_values[index]


func _append_bounded(values: Array[float], value: float) -> void:
	values.append(value)
	if values.size() > MAX_FRAME_SAMPLES:
		values.pop_front()


func _bytes_to_mb(bytes: float) -> float:
	return bytes / (1024.0 * 1024.0)


func _fmt(value: Variant) -> String:
	return "%.4f" % float(value)
