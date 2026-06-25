@tool
extends RefCounted

var edger: SawmillEdger


func _init(p_edger: SawmillEdger) -> void:
	edger = p_edger


func build_sample_board() -> void:
	edger._push_editor_group("ReferenceBoardAssembly")
	var board := edger._create_reference_board()
	board.position = Vector3(edger._preview_board_start_x(), edger._board_center_y(), edger.side_load_start_z)
	edger._current_part_parent().add_child(board)
	edger._sample_board = board
	edger._preview_board_home_global = board.global_position
	edger._pop_editor_group()
