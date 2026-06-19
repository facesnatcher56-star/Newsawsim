@tool
extends Control

@onready var node_label: Label = $VBox/NodeName
@onready var pos_label: Label = $VBox/PosLabel
@onready var rot_label: Label = $VBox/RotLabel
@onready var scale_label: Label = $VBox/ScaleLabel
@onready var basis_label: Label = $VBox/BasisLabel

func update_transform(node: Node3D) -> void:
	var gt := node.global_transform
	var pos := gt.origin
	var rot := gt.basis.get_euler() * (180.0 / PI)
	var sc := gt.basis.get_scale()

	node_label.text = node.name
	pos_label.text   = "Pos  X: %.4f  Y: %.4f  Z: %.4f" % [pos.x, pos.y, pos.z]
	rot_label.text   = "Rot  X: %.2f°  Y: %.2f°  Z: %.2f°" % [rot.x, rot.y, rot.z]
	scale_label.text = "Scale  X: %.4f  Y: %.4f  Z: %.4f" % [sc.x, sc.y, sc.z]
	basis_label.text = (
		"Basis\n  X: (%.4f, %.4f, %.4f)\n  Y: (%.4f, %.4f, %.4f)\n  Z: (%.4f, %.4f, %.4f)" % [
		gt.basis.x.x, gt.basis.x.y, gt.basis.x.z,
		gt.basis.y.x, gt.basis.y.y, gt.basis.y.z,
		gt.basis.z.x, gt.basis.z.y, gt.basis.z.z,
	])

func clear() -> void:
	node_label.text  = "(no Node3D selected)"
	pos_label.text   = ""
	rot_label.text   = ""
	scale_label.text = ""
	basis_label.text = ""
