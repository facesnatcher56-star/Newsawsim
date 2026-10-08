@tool
extends Node3D

## Editor-only note marker: shows `note_content` as a label on a coloured point.

@export_multiline var note_content: String = "Marker Point":
	set(value):
		note_content = value
		_update_label()

func _ready() -> void:
	_update_label()
	if not Engine.is_editor_hint():
		hide()

func _update_label() -> void:
	if has_node("Label3D"):
		$Label3D.text = note_content
