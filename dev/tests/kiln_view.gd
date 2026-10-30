extends Node3D

## Looks at the dry kiln in the running mill from a few angles. Keys 1-3 switch views.
## Run: godot --path . res://dev/tests/kiln_view.tscn

const MILL_SCENE := preload("res://game/levels/mill_prototype.tscn")

const VIEWS: Array = [
	[Vector3(36.0, 7.0, 99.0), Vector3(55.0, 3.0, 116.0)],     # 1 front corner, green yard side
	[Vector3(70.0, 9.0, 104.0), Vector3(53.0, 3.0, 118.0)],    # 2 the other front corner
	[Vector3(52.0, 3.0, 104.0), Vector3(52.0, 2.5, 112.0)],    # 3 close on the front doors
]

var _cam: Camera3D


func _ready() -> void:
	add_child(MILL_SCENE.instantiate())
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_set_view(1)


func _process(_delta: float) -> void:
	_cam.current = true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode >= KEY_1 and key.keycode <= KEY_3:
		_set_view(key.keycode - KEY_0)


func _set_view(n: int) -> void:
	var v: Array = VIEWS[n - 1]
	_cam.position = v[0]
	_cam.look_at(v[1])
