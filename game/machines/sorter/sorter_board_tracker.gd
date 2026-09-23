class_name SorterBoardTracker
extends RefCounted

## Manages board classification, overhead routing, drop gate triggering, and cradle indexing.

class BoardTrackingData:
	var board: RigidBody3D
	var target_bin: int
	var infeed_time: float
	var active: bool = true
	var gate_triggered: bool = false
	var dropped_into_bay: bool = false
	var released: bool = false

static func get_board_sorting_grade(body: Node3D, num_bins: int) -> int:
	var nominal: String = "2x8"
	var len_ft: int = 16

	if body.has_method("get"):
		if body.get("nominal_size") != null:
			nominal = str(body.get("nominal_size"))
		if body.get("length_feet") != null:
			len_ft = int(body.get("length_feet"))
		elif body.get("product_length") != null:
			var len_m: float = float(body.get("product_length"))
			len_ft = int(round(len_m / 0.3048))

	var profiles: Array[String] = [
		"1x4", "1x6", "1x8", "1x10", "1x12",
		"2x4", "2x6", "2x8", "2x10", "2x12"
	]
	var profile_idx: int = profiles.find(nominal)
	if profile_idx == -1:
		profile_idx = 7

	var is_long: bool = (len_ft > 12)
	var grade: int = profile_idx + (10 if is_long else 0)
	return grade % num_bins

static func can_accept_board(body: Node3D, num_bins: int, bay_counts: Array[int], bay_discharging: Array[bool], max_boards: int, tracked_boards: Array[BoardTrackingData]) -> bool:
	if not (body is RigidBody3D) or not body.is_in_group("cut_boards") or body.is_in_group("cut_slabs"):
		return false
	var target: int = get_board_sorting_grade(body, num_bins)
	if target >= bay_counts.size() or target >= bay_discharging.size():
		return false
	if bay_discharging[target] or bay_counts[target] >= max_boards:
		return false
	for data in tracked_boards:
		if is_instance_valid(data.board) and not data.dropped_into_bay:
			return false
	return true
