extends StaticBody3D

## A plain solid floor for boards to be dragged across (used by InclineBottom and InclineTop).
## It does not move or carry anything by itself: the lugs do the pushing.

## How rough the floor is. 0 = like ice, the board slides very easily.
## Higher = the board is harder to drag across it. Too high and the lugs may not be able to push the board.
@export_range(0.0, 5.0, 0.05, "or_greater") var grip: float = 0.3:
	set(value):
		grip = value
		_apply_grip()

var _material := PhysicsMaterial.new()


func _ready() -> void:
	_apply_grip()


func _apply_grip() -> void:
	_material.friction = grip
	_material.rough = true
	_material.bounce = 0.0
	physics_material_override = _material
