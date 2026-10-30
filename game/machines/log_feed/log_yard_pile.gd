extends Node3D

## log_yard_pile.gd
## A decked pile of 16 ft logs on two timber bearers between steel stakes, in the yard
## beside a knuckleboom loader. Logs lie along local X and stay frozen until the loader
## takes them. When the pile is empty it is restocked (a yard loader dropping a new load).

const LOG_SCENE := preload("res://game/lumber/log.tscn")
const LOG_RADIUS := 0.292
const BEARER_HEIGHT := 0.20

@export var bottom_row: int = 5
@export var layers: int = 3
## Centre-to-centre spacing across the pile; a little over one log diameter.
@export var spacing: float = 0.60
## Random end-to-end stagger and roll so the pile does not look machine-stacked.
@export var stagger: float = 0.18

var _logs: Array[RigidBody3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_cribbing()
	restock()


func log_count() -> int:
	_prune()
	return _logs.size()


func top_height() -> float:
	_prune()
	var top := global_position.y + BEARER_HEIGHT
	for l in _logs:
		top = maxf(top, l.global_position.y + LOG_RADIUS)
	return top


## Picks up to max_n logs that a grapple can bite together: the highest log plus its
## nearest neighbours on the same layer or one layer down. They leave the pile.
func take_bundle(max_n: int) -> Array[RigidBody3D]:
	_prune()
	var out: Array[RigidBody3D] = []
	if _logs.is_empty():
		return out
	var first := _logs[0]
	for l in _logs:
		if l.global_position.y > first.global_position.y + 0.01:
			first = l
	var candidates := _logs.duplicate()
	candidates.erase(first)
	var origin := to_local(first.global_position)
	candidates.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool:
		return absf(to_local(a.global_position).z - origin.z) < absf(to_local(b.global_position).z - origin.z))
	out.append(first)
	for l in candidates:
		if out.size() >= max_n:
			break
		var p := to_local(l.global_position)
		if absf(p.z - origin.z) <= spacing * 1.6 and origin.y - p.y <= spacing:
			out.append(l)
	for l in out:
		_logs.erase(l)
	return out


## Takes back logs the loader set down on the pile (it could not put them on the deck).
## They settle as a new top row and are frozen in place like the rest of the pile.
func return_logs(returned: Array[RigidBody3D]) -> void:
	_prune()
	var top := top_height() - global_position.y
	for i in range(returned.size()):
		var l := returned[i]
		if not is_instance_valid(l):
			continue
		l.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		l.freeze = true
		var z := (i - (returned.size() - 1) * 0.5) * spacing
		l.global_transform = global_transform * Transform3D(Basis(Vector3.RIGHT, _rng.randf_range(-PI, PI)),
			Vector3(_rng.randf_range(-stagger, stagger), top + LOG_RADIUS - 0.05, z))
		_logs.append(l)


func restock() -> void:
	_prune()
	if not _logs.is_empty():
		return
	var row_y := BEARER_HEIGHT + LOG_RADIUS
	var layer_rise := spacing * 0.866
	for layer in range(layers):
		var count := bottom_row - layer
		for i in range(count):
			var log_body := LOG_SCENE.instantiate() as RigidBody3D
			log_body.freeze = true
			log_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			add_child(log_body)
			var z := (i - (count - 1) * 0.5) * spacing
			var x := _rng.randf_range(-stagger, stagger)
			var roll := _rng.randf_range(-PI, PI)
			# Alternate butt ends, the way logs come off a truck.
			var yaw := 0.0 if _rng.randf() < 0.5 else PI
			log_body.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, roll),
				Vector3(x, row_y + layer * layer_rise, z))
			_logs.append(log_body)


func _prune() -> void:
	for i in range(_logs.size() - 1, -1, -1):
		if not is_instance_valid(_logs[i]):
			_logs.remove_at(i)


func _build_cribbing() -> void:
	var timber := StandardMaterial3D.new()
	timber.albedo_color = Color(0.22, 0.15, 0.09)
	timber.roughness = 0.95
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.18, 0.18, 0.19)
	steel.metallic = 0.7
	steel.roughness = 0.5
	var width := bottom_row * spacing + 0.5
	for x in [-1.6, 1.6]:
		var bearer := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.25, BEARER_HEIGHT, width)
		bearer.mesh = box
		bearer.material_override = timber
		bearer.position = Vector3(x, BEARER_HEIGHT * 0.5, 0.0)
		add_child(bearer)
		for side in [-1.0, 1.0]:
			var stake := MeshInstance3D.new()
			var post := BoxMesh.new()
			post.size = Vector3(0.15, 1.7, 0.15)
			stake.mesh = post
			stake.material_override = steel
			stake.position = Vector3(x, 0.85, side * (width * 0.5 + 0.05))
			add_child(stake)
