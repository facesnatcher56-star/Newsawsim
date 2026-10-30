extends StaticBody3D

## vroll_conveyor.gd
## Double-cone (V-roll) log conveyor. A log rides centred in the vee and is driven along
## world +X. `speed` is set by whoever runs the line (the deck stops stop it while a log
## settles, then restore it); `hold` lets the debarker stop it while it is busy. The rolls
## in the imported model are found by name prefix and spun to match.

## Contact radius of a seated log on the cones, for the roll spin.
const CONTACT_RADIUS := 0.27

@export var speed: float = 0.8
@export var model_path: NodePath
@export var roll_prefix: String = "IN_Roll"

var hold: bool = false
var _rolls: Array[Node3D] = []


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model:
		for node in model.find_children(roll_prefix + "*", "Node3D", true, false):
			if not String(node.name).ends_with("Mesh"):
				_rolls.append(node)


func _physics_process(delta: float) -> void:
	var v := 0.0 if hold else speed
	constant_linear_velocity = Vector3.RIGHT * v
	# Roll tops move with the log (+X), so the rolls turn negative about Z.
	for roll in _rolls:
		roll.rotation.z -= v / CONTACT_RADIUS * delta


func is_running() -> bool:
	return not hold and speed > 0.0
