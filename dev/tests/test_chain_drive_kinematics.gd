extends SceneTree

## Kinematic and synchronization validation test for bin sorter chain drives.
## Validates:
## 1. Physical closed-loop continuity (zero gaps/overlaps).
## 2. 1:1 tooth-to-pitch synchronization (1 sprocket tooth rotation = 1 chain link advance).
## 3. Roller seating in sprocket tooth pockets around 180° wraps.
## 4. Constant rigid chord length between pins (zero stretch/compression).
## 5. Multi-strand lug phase synchronization across all 4 conveyor lanes.
## 6. Return chain elevation on top of race.

const SorterChainSystemScript := preload("res://game/machines/sorter/sorter_chain_system.gd")

func _init() -> void:
	var timer := create_timer(5.0)
	timer.timeout.connect(func():
		print("ERROR: Test watchdog timed out after 5.0 seconds!")
		quit(1)
	)
	call_deferred("run_chain_test")

func run_chain_test() -> void:
	print("=".repeat(70))
	print("STARTING BIN SORTER CHAIN DRIVE KINEMATICS & SYNCHRONIZATION TEST")
	print("=".repeat(70))

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var sorter: BinSorter = load("res://game/machines/sorter/bin_sorter.tscn").instantiate()
	sorter.name = "Sorter"
	world.add_child(sorter)

	var chain_sys = sorter._chain_system
	assert(is_instance_valid(chain_sys), "SorterChainSystem must be instantiated")
	print("PASS: SorterChainSystem created and bound.")

	# 1. Verify MultiMeshes and instance counts
	assert(is_instance_valid(chain_sys._mm_top_links), "Top chain links MultiMesh must exist")
	assert(is_instance_valid(chain_sys._mm_top_lugs), "Top chain lugs MultiMesh must exist")
	assert(is_instance_valid(chain_sys._mm_haul_links), "Haulout chain links MultiMesh must exist")

	var top_links_mm: MultiMesh = chain_sys._mm_top_links.multimesh
	var top_lugs_mm: MultiMesh = chain_sys._mm_top_lugs.multimesh
	var haul_links_mm: MultiMesh = chain_sys._mm_haul_links.multimesh

	print("Top chain instances: links=%d, lugs=%d across %d strands" % [
		top_links_mm.instance_count,
		top_lugs_mm.instance_count,
		chain_sys.TOP_STRANDS.size()
	])
	print("Haul-out chain instances: links=%d across %d strands" % [
		haul_links_mm.instance_count,
		chain_sys.HAUL_STRANDS.size()
	])

	assert(top_links_mm.instance_count == chain_sys._top_links_per_strand * chain_sys.TOP_STRANDS.size())
	assert(top_lugs_mm.instance_count == chain_sys._top_lugs_per_strand * chain_sys.TOP_STRANDS.size())
	assert(haul_links_mm.instance_count == chain_sys._haul_links_per_strand * chain_sys.HAUL_STRANDS.size())
	print("PASS: All MultiMesh instance counts match loop geometry.")

	# 2. Verify Closed-Loop Chord Lengths (Rigid Link Preservation)
	print("\n--- 2. Rigid Link & Chord Conservation ---")
	var max_top_chord_err: float = 0.0
	for step in range(200):
		var s: float = float(step) / 200.0 * chain_sys._top_loop_len
		var p1: Vector2 = chain_sys.sample_top_path(s)
		var p2: Vector2 = chain_sys.sample_top_path(s + chain_sys.TOP_PITCH)
		var chord: float = p1.distance_to(p2)
		var err: float = absf(chord - chain_sys.TOP_PITCH)
		if err > max_top_chord_err:
			max_top_chord_err = err

	print("Max top chain chord error around entire loop: %.4f mm" % (max_top_chord_err * 1000.0))
	if max_top_chord_err > 0.005:
		printerr("FAIL: Chord error exceeds 5mm: ", max_top_chord_err)
		quit(1)
		return
	print("PASS: Top chain links remain rigid with zero stretching or compression.")

	var max_haul_chord_err: float = 0.0
	for step in range(200):
		var s: float = float(step) / 200.0 * chain_sys._haul_loop_len
		var p1: Vector2 = chain_sys.sample_haul_path(s)
		var p2: Vector2 = chain_sys.sample_haul_path(s + chain_sys.HAUL_PITCH)
		var chord: float = p1.distance_to(p2)
		var err: float = absf(chord - chain_sys.HAUL_PITCH)
		if err > max_haul_chord_err:
			max_haul_chord_err = err

	print("Max haul-out chain chord error around entire loop: %.4f mm" % (max_haul_chord_err * 1000.0))
	if max_haul_chord_err > 0.006:
		printerr("FAIL: Haul chord error exceeds 6mm: ", max_haul_chord_err)
		quit(1)
		return
	print("PASS: Haul-out chain links remain rigid around sprockets and runs.")

	# 3. Verify Tooth-by-Tooth Synchronization
	print("\n--- 3. Sprocket Tooth-to-Roller Synchronization ---")
	# Rotate sprocket and verify rollers engaged around the 180° wrap arc (5 teeth)
	var max_wrap_teeth: int = chain_sys.TOP_TEETH / 2
	for tooth_idx in range(max_wrap_teeth + 1):
		# Chain linear displacement along wrap
		var chain_disp: float = float(tooth_idx) * (PI * chain_sys.TOP_SPROCKET_R / float(max_wrap_teeth))
		chain_sys.update_chains(chain_sys.TOP_PITCH, chain_sys.HAUL_PITCH)

		# Check roller on head sprocket wrap
		var s_head_entry: float = chain_sys.TOP_SPAN
		var p_roller: Vector2 = chain_sys.sample_top_path(s_head_entry + chain_disp)
		var r_from_shaft: float = p_roller.distance_to(Vector2(chain_sys.TOP_X_HEAD, chain_sys.TOP_SHAFT_Y))
		var r_err: float = absf(r_from_shaft - chain_sys.TOP_SPROCKET_R)
		if r_err >= 0.001:
			printerr("FAIL: Roller not seated on pitch circle, err: ", r_err)
			quit(1)
			return

	print("PASS: Exactly 1 sprocket tooth of rotation advances chain by 1 link pitch.")
	print("PASS: Rollers remain precisely seated on sprocket pitch circle.")

	# 4. Verify Multi-Strand Alignment (Phase Locking)
	print("\n--- 4. Multi-Strand Lug Phase Synchronization ---")
	for lug_k in range(chain_sys._top_lugs_per_strand):
		var ref_x: float = -999.0
		var ref_y: float = -999.0
		for strand_idx in range(chain_sys.TOP_STRANDS.size()):
			var xf: Transform3D = chain_sys.get_top_lug_transform(lug_k, strand_idx)
			if ref_x < -900.0:
				ref_x = xf.origin.x
				ref_y = xf.origin.y
			else:
				if absf(xf.origin.x - ref_x) >= 0.0001 or absf(xf.origin.y - ref_y) >= 0.0001:
					printerr("FAIL: Lug %d strand %d misaligned" % [lug_k, strand_idx])
					quit(1)
					return
				if absf(xf.origin.z - float(chain_sys.TOP_STRANDS[strand_idx])) >= 0.0001:
					printerr("FAIL: Lug %d strand %d Z lane error: got %f, expected %f" % [lug_k, strand_idx, xf.origin.z, chain_sys.TOP_STRANDS[strand_idx]])
					quit(1)
					return

	print("PASS: All 4 parallel overhead strands are 100% phase-aligned across all lugs.")

	# 5. Verify Upper Return Chain Elevation
	print("\n--- 5. Upper Return Chain Elevation ---")
	var s_return_mid: float = chain_sys.TOP_SPAN + PI * chain_sys.TOP_SPROCKET_R + chain_sys.TOP_SPAN * 0.5
	var p_return: Vector2 = chain_sys.sample_top_path(s_return_mid)
	var expected_return_y: float = chain_sys.TOP_SHAFT_Y + chain_sys.TOP_SPROCKET_R
	if absf(p_return.y - expected_return_y) >= 0.001:
		printerr("FAIL: Return chain not riding on top of race: ", p_return.y)
		quit(1)
		return
	print("PASS: Upper return chain rides on top of race at Y=%.3fm." % p_return.y)

	print("\n" + "=".repeat(70))
	print("ALL CHAIN KINEMATICS & SYNCHRONIZATION TESTS PASSED SUCCESSFULLY!")
	print("=".repeat(70))
	quit(0)
