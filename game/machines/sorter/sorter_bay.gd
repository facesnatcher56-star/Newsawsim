class_name SorterBay
extends Node3D

## One bin of the sorter, built from real nodes you can see and move in sorter_bay.tscn.
## Origin is the bay's left edge on the floor. Every bay is a copy of this scene, so
## editing it changes all 50.
##
## - TopSurface: the slide plane boards ride along. It doubles as the gate: when the bay
##   is the target the surface switches off and the board drops into the bay.
## - Cradle: the lift the boards land on. The sorter moves it up and down as the stack grows.
## - Divider: the wall between this bay and the previous one.

@onready var top_surface: StaticBody3D = $TopSurface  # a CarrySurface
@onready var cradle: AnimatableBody3D = $Cradle

var _top_shape: CollisionShape3D


func _ready() -> void:
	_top_shape = top_surface.get_node("CollisionShape3D") as CollisionShape3D


## Speed boards are carried along the slide plane, in metres per second.
func set_top_speed(value: float) -> void:
	top_surface.set("speed", value)


## Open the gate: the slide plane under this bay disappears and a board drops through.
func set_gate_open(open: bool) -> void:
	if _top_shape.disabled != open:
		_top_shape.set_deferred("disabled", open)


func set_cradle_height(height: float) -> void:
	cradle.position.y = height
