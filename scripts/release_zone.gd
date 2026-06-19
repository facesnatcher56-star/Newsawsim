extends Area3D

## ReleaseZone.gd
## When a body enters this zone, it is told to ignore collisions with a specific target.
## This allows the log to "fall through" a conveyor or incline even if it's still inside its bounds.

@export var target_to_ignore: NodePath = "../InclinePart2"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is RigidBody3D:
		var target = get_node_or_null(target_to_ignore)
		if target and target is PhysicsBody3D:
			# This tells the physics engine to stop calculating collisions 
			# between this specific log and the target incline.
			body.add_collision_exception_with(target)
