extends SceneTree

## Test: feeds boards onto the bin sorter's infeed transfer on its own and checks where each one
## physically ends up: counted boards must be on their own bay's forks (lying however they
## settled), and a full bay's pile must be hauled out to the end table.
## Run: godot --headless --fixed-fps 60 --path . --script res://dev/tests/bin_sorter_flow_test.gd
## Extra args after `--`: `--log` prints the sorter's board log, `--trace` a status line each
## second, `--random` feeds 60 random boards (4 sizes, 10-16 ft) so several bays fill and
## their piles queue on the end table; `--mill` feeds 35 16 ft 2x8s, what the mill cuts today;
## `--dense` feeds a board every 2.2 s, as fast as the lugs can take them. The feed never stops.
## Boards arrive where the incline's lugs leave them, with a little scatter (a few cm across,
## a degree of skew).
## (8 ft boards are too short for the sorter: they reach only the middle one of its three lug
## and haul-out chain lines, 2.75 m apart.)

const SORTER_SCENE := "res://game/machines/sorter/bin_sorter.tscn"
const BOARD_SCENE := "res://game/lumber/cut_board.tscn"
const SPAWN_GAP := 3.7          # seconds between boards, the incline's delivery rate
# 2x8 goes to bay 7: ten of them fill it and send the stack out.
const FEED: Array[String] = ["2x8", "1x4", "2x8", "2x12", "2x8", "1x10", "2x8", "2x4", "2x8",
	"1x6", "2x8", "2x8", "1x12", "2x8", "2x8", "2x10", "1x8", "2x6", "2x8", "1x4"]


func _init() -> void:
	call_deferred("_run")


var _fine_from: float = INF
var _watch: int = -1


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--watch="):
			_watch = int(arg.substr(8))
		if arg.begins_with("--fine="):
			_fine_from = float(arg.substr(7))
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 20)
	floor_shape.shape = box
	floor_shape.position = Vector3(5, -0.5, 0)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var sorter: BinSorter = load(SORTER_SCENE).instantiate()
	sorter.log_boards = OS.get_cmdline_user_args().has("--log")
	world.add_child(sorter)

	var feed: Array[String] = FEED.duplicate()
	var lengths: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if OS.get_cmdline_user_args().has("--mill"):
		feed.clear()
		for n in 35:
			feed.append("2x8")
	if OS.get_cmdline_user_args().has("--random"):
		feed.clear()
		for n in 60:
			feed.append(["2x4", "2x6", "1x8", "2x10"][rng.randi() % 4])
	for n in feed.size():
		lengths.append([10, 12, 14, 16][rng.randi() % 4] if feed.size() > FEED.size() else 16)
	var boards: Array[RigidBody3D] = []
	var t := 0.0
	var next_spawn := 0.5
	var fed := 0
	var dt := 1.0 / 60.0
	var dense: bool = OS.get_cmdline_user_args().has("--dense")
	var idle := 0.0
	var binned := {}                  # every board the sorter ever counted onto a bay's forks
	var last_fed := -10.0
	# Run until every board is fed and the sorter has finished with them (cap 25 minutes).
	while (fed < feed.size() or idle < 3.0) and t < 1500.0:
		if fed < feed.size() and t >= next_spawn:
			var board: RigidBody3D = load(BOARD_SCENE).instantiate()
			board.nominal_size = feed[fed]
			board.length_feet = lengths[fed]
			board.rotation.y = PI * 0.5 + deg_to_rad(rng.randf_range(-1.0, 1.0))
			world.add_child(board)
			board.contact_monitor = true          # after _ready, which turns it off
			board.max_contacts_reported = 8
			board.position = Vector3(-0.25, BinSorter.DECK_Y + board.board_thickness * 0.5 + 0.005, rng.randf_range(-0.05, 0.05))
			boards.append(board)
			fed += 1
			last_fed = t
			next_spawn += 2.2 if dense else SPAWN_GAP
		await physics_frame
		t += dt
		for sb: BinSorter.Bay in sorter._bays:
			for bb: RigidBody3D in sb.boards:
				binned[bb] = true
		var busy: bool = not sorter._queue.is_empty() or not sorter._carried.is_empty() or not sorter._hauled.is_empty()
		for sb: BinSorter.Bay in sorter._bays:
			busy = busy or sb.phase != BinSorter.BayPhase.CATCH
		idle = 0.0 if busy or fed < feed.size() else idle + dt
		if _watch >= 0 and sorter._bays[_watch].phase in [BinSorter.BayPhase.LOWER, BinSorter.BayPhase.HAUL] and fmod(t, 0.25) < dt:
			var bay: BinSorter.Bay = sorter._bays[_watch]
			var w := "t=%.2f bay %d phase=%d carriage=%.3f haul=%.2f |" % [t, _watch, bay.phase, bay.carriage_y, sorter._haul_current]
			for sb: RigidBody3D in bay.boards:
				if is_instance_valid(sb):
					var sp: Vector3 = sorter.to_local(sb.global_position)
					w += " (%.2f,%.3f)%.0f" % [sp.x, sp.y, rad_to_deg(sb.global_basis.y.angle_to(Vector3.UP))]
			print(w)
		var fine: bool = t > _fine_from and t < _fine_from + 3.0
		if OS.get_cmdline_user_args().has("--trace") and (fmod(t, 1.0) < dt or fine):
			var line := "t=%.2f chain=%.2f hold=%s stop=%.0f q=%d |" % [t, sorter._top_speed, sorter._hold_chain, sorter._stop_deg, sorter._queue.size()]
			for b: RigidBody3D in sorter._queue:
				var qp: Vector3 = sorter.to_local(b.global_position)
				line += " Q%s@(%.2f,%.3f)v%.2f" % [b.nominal_size, qp.x, qp.y, b.linear_velocity.length()]
				if fine:
					var names := []
					for cb: Node in b.get_colliding_bodies():
						names.append(String(cb.name))
					line += " infeed=%.2f touching=%s" % [sorter._infeed_current, names]
			for c: BinSorter.Carried in sorter._carried:
				if is_instance_valid(c.board):
					line += " %s>%d@%.2f/%d v%.2f" % [c.board.nominal_size, c.bay, sorter.to_local(c.board.global_position).x, c.state, c.board.linear_velocity.x]
					if fine and c.board.nominal_size == "1x4":
						var ctouch := []
						for cb: Node in c.board.get_colliding_bodies():
							ctouch.append(String(cb.name))
						line += " ctouch=%s" % [ctouch]
			if fine:
				line += " gate0=%.0f y1x4=%s" % [sorter._bays[0].gate_deg, str(snappedf(sorter.to_local(boards[1].global_position).y, 0.001)) if boards.size() > 1 else "-"]
				var lugs := []
				for k in sorter._lugs.size():
					var lx: float = sorter._lugs[k].position.x + BinSorter.LUG_FACE
					if lx > 0.0 and lx < 1.5 and sorter._lugs[k].position.y < 4.8:
						lugs.append("%.2f%s" % [lx, "" if sorter._lug_on_run[k] else "(off)"])
				line += " lugs=%s" % [lugs]
			print(line)

	var problems := 0
	var physical: Array[int] = []
	physical.resize(BinSorter.NB)
	physical.fill(0)
	print("bay counts: ", sorter._bays.map(func(b: BinSorter.Bay) -> int: return b.count))
	print("bay phases: ", sorter._bays.map(func(b: BinSorter.Bay) -> int: return b.phase))
	for i in boards.size():
		var b := boards[i]
		if not is_instance_valid(b):
			print("  #%d %s FREED (fell out of the world)" % [i, feed[i]])
			problems += 1
			continue
		var p: Vector3 = sorter.to_local(b.global_position)
		# A size may use more than one bay (its own is discharging), so: in whichever bay the
		# sorter assigned it, and no bay mixes sizes.
		var bay: int = floori((p.x - BinSorter.BX0) / BinSorter.BAY)
		var where := "?"
		if bay >= 0 and bay < BinSorter.NB and p.y > 1.2 and p.y < BinSorter.DECK_Y - 0.3 and p.x > BinSorter.bay_x(bay) + 0.15:
			if sorter._bays[bay].boards.has(b) and sorter._bays[bay].size == feed[i]:
				where = "in bay %d" % bay
				physical[bay] += 1
		elif p.y < 1.2 and p.x > BinSorter.STACK_STOP_X - 4.0 and binned.has(b):
			where = "hauled out"
		else:
			problems += 1
		var tilt: float = rad_to_deg(b.global_basis.y.angle_to(Vector3.UP))
		# Boards fall and settle naturally; leaning or on edge is fine, only the bay matters.
		if where != "?" and tilt > 20.0 and tilt < 160.0:
			where += " (leaning)"
		print("  #%d %s -> pos (%.2f, %.2f, %.2f) tilt %.0f deg  %s" % [i, feed[i], p.x, p.y, p.z, tilt, where])
	for i in BinSorter.NB:
		if physical[i] != sorter._bays[i].count:
			print("  bay %d: sorter counts %d, %d boards are on its forks" % [i, sorter._bays[i].count, physical[i]])
			problems += 1
	print("RESULT ", "PASS" if problems == 0 else "FAIL (%d problems)" % problems)
	quit()
