@tool
extends EditorPlugin

var dock: Control
var _selection: EditorSelection

func _enter_tree() -> void:
	dock = preload("res://addons/global_transform_inspector/dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)

	_selection = get_editor_interface().get_selection()
	_selection.selection_changed.connect(_on_selection_changed)

func _exit_tree() -> void:
	if _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	remove_control_from_docks(dock)
	dock.queue_free()

func _process(_delta: float) -> void:
	var nodes := _selection.get_selected_nodes()
	if nodes.size() > 0 and nodes[0] is Node3D:
		dock.update_transform(nodes[0])
	else:
		dock.clear()

func _on_selection_changed() -> void:
	var nodes := _selection.get_selected_nodes()
	if nodes.size() > 0 and nodes[0] is Node3D:
		dock.update_transform(nodes[0])
	else:
		dock.clear()
