@tool
class_name LumberLibrary
extends RefCounted

## Utility library for creating and querying standard North American dimensional lumber:
## Sizes: 1x4, 1x6, 1x8, 1x10, 1x12, 2x4, 2x6, 2x8, 2x10, 2x12
## Lengths: 6ft, 8ft, 10ft, 12ft, 14ft, 16ft (Even Foot Increments)

const CutBoardScene := preload("res://game/lumber/cut_board.tscn")

const NOMINAL_SIZES: Array[String] = [
	"1x4", "1x6", "1x8", "1x10", "1x12",
	"2x4", "2x6", "2x8", "2x10", "2x12"
]

const EVEN_LENGTHS_FEET: Array[int] = [6, 8, 10, 12, 14, 16]

const SPECS: Dictionary = {
	"1x4":  {"thickness": 0.019, "width": 0.089, "nominal": "1x4"},
	"1x6":  {"thickness": 0.019, "width": 0.140, "nominal": "1x6"},
	"1x8":  {"thickness": 0.019, "width": 0.184, "nominal": "1x8"},
	"1x10": {"thickness": 0.019, "width": 0.235, "nominal": "1x10"},
	"1x12": {"thickness": 0.019, "width": 0.286, "nominal": "1x12"},
	"2x4":  {"thickness": 0.038, "width": 0.089, "nominal": "2x4"},
	"2x6":  {"thickness": 0.038, "width": 0.140, "nominal": "2x6"},
	"2x8":  {"thickness": 0.038, "width": 0.184, "nominal": "2x8"},
	"2x10": {"thickness": 0.038, "width": 0.235, "nominal": "2x10"},
	"2x12": {"thickness": 0.038, "width": 0.286, "nominal": "2x12"},
}

static func feet_to_meters(feet: float) -> float:
	return feet * 0.3048

static func create_board(nominal_type: String = "2x8", length_feet: int = 16) -> RigidBody3D:
	if CutBoardScene == null:
		return null
	var board := CutBoardScene.instantiate() as RigidBody3D
	if board.has_method("configure_lumber"):
		board.configure_lumber(nominal_type, length_feet)
	return board

static func spawn_random_board(parent: Node, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> RigidBody3D:
	var rand_size: String = NOMINAL_SIZES[randi() % NOMINAL_SIZES.size()]
	var rand_len: int = EVEN_LENGTHS_FEET[randi() % EVEN_LENGTHS_FEET.size()]
	var board := create_board(rand_size, rand_len)
	if board != null:
		board.position = pos
		board.rotation = rot
		parent.add_child(board)
	return board

static func get_all_combinations() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for size_str in NOMINAL_SIZES:
		var spec: Dictionary = SPECS[size_str]
		for len_ft in EVEN_LENGTHS_FEET:
			var len_m: float = feet_to_meters(float(len_ft))
			list.append({
				"nominal": size_str,
				"length_feet": len_ft,
				"length_meters": len_m,
				"thickness_meters": spec["thickness"],
				"width_meters": spec["width"],
			})
	return list
