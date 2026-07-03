@tool
extends RefCounted

## Builds the chain trough conveyor's drive/idle shafts, sprockets, and the
## chain multimesh (plates + rollers). Also owns the loop-transform math used
## both to lay out the chain initially and to animate it every frame.

var conveyor: Node


func _init(p_conveyor: Node) -> void:
	conveyor = p_conveyor


func build_shafts_and_sprockets() -> void:
	var visuals_root: Node3D = conveyor._visuals_root
	var conveyor_length: float = conveyor.conveyor_length
	var sprocket_radius: float = conveyor.sprocket_radius
	var sprocket_cy: float = conveyor._sprocket_cy
	var track_x_positions: Array = conveyor.track_x_positions
	var sprocket_hub_t: float = conveyor.SPROCKET_HUB_T
	var sprocket_segs: int = conveyor.SPROCKET_SEGS

	var mat_hardware := StandardMaterial3D.new()
	mat_hardware.albedo_color = Color(0.3, 0.32, 0.35)
	mat_hardware.metallic = 0.9
	mat_hardware.roughness = 0.35

	var half_z: float = conveyor_length * 0.5

	# Drive and Idle shafts
	for end_idx in range(2):
		var z: float = -half_z if end_idx == 0 else half_z
		var suffix: String = "Infeed" if end_idx == 0 else "Discharge"

		var shaft := MeshInstance3D.new()
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.03
		shaft_mesh.bottom_radius = 0.03
		shaft_mesh.height = 0.45
		shaft.mesh = shaft_mesh
		shaft.name = "%sShaft" % suffix
		shaft.material_override = mat_hardware
		shaft.rotation_degrees.z = 90.0
		shaft.position = Vector3(0.0, sprocket_cy, z)
		visuals_root.add_child(shaft)
		conveyor._rotating_parts.append(shaft)

		# 4 sprockets per shaft
		for i in range(track_x_positions.size()):
			var tx: float = track_x_positions[i]

			var spr := MeshInstance3D.new()
			var spr_mesh := CylinderMesh.new()
			spr_mesh.top_radius = sprocket_radius
			spr_mesh.bottom_radius = sprocket_radius
			spr_mesh.height = sprocket_hub_t
			spr_mesh.radial_segments = sprocket_segs
			spr.mesh = spr_mesh
			spr.name = "%sSprocket_%d" % [suffix, i]
			spr.material_override = mat_hardware
			spr.rotation_degrees.z = 90.0
			spr.position = Vector3(tx, sprocket_cy, z)
			visuals_root.add_child(spr)
			conveyor._rotating_parts.append(spr)


func build_chains() -> void:
	var visuals_root: Node3D = conveyor._visuals_root
	var loop_len: float = conveyor._loop_len
	var link_spacing: float = conveyor.link_spacing
	var track_x_positions: Array = conveyor.track_x_positions
	var chain_plate_w: float = conveyor.CHAIN_PLATE_W
	var chain_plate_h: float = conveyor.CHAIN_PLATE_H
	var chain_plate_d: float = conveyor.CHAIN_PLATE_D
	var chain_span: float = conveyor.CHAIN_SPAN
	var chain_roller_r: float = conveyor.CHAIN_ROLLER_R

	var num_links: int = int(ceil(loop_len / link_spacing)) + 2
	conveyor._num_links = num_links
	var num_tracks: int = track_x_positions.size()

	var mat_chain := StandardMaterial3D.new()
	mat_chain.albedo_color = Color(0.18, 0.18, 0.19)
	mat_chain.metallic = 0.95
	mat_chain.roughness = 0.3

	# 1. Plates MultiMesh
	var multimesh_plates := MultiMeshInstance3D.new()
	multimesh_plates.name = "PlatesMultiMesh"
	var mm_plates := MultiMesh.new()
	mm_plates.transform_format = MultiMesh.TRANSFORM_3D
	mm_plates.use_custom_data = false
	mm_plates.use_colors = false

	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(chain_plate_w, chain_plate_h, chain_plate_d)
	mm_plates.mesh = plate_mesh
	mm_plates.instance_count = num_links * num_tracks * 2
	multimesh_plates.multimesh = mm_plates
	multimesh_plates.material_override = mat_chain
	visuals_root.add_child(multimesh_plates)
	conveyor._multimesh_plates = multimesh_plates

	# 2. Rollers MultiMesh
	var multimesh_rollers := MultiMeshInstance3D.new()
	multimesh_rollers.name = "RollersMultiMesh"
	var mm_rollers := MultiMesh.new()
	mm_rollers.transform_format = MultiMesh.TRANSFORM_3D
	mm_rollers.use_custom_data = false
	mm_rollers.use_colors = false

	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = chain_roller_r
	roller_mesh.bottom_radius = chain_roller_r
	roller_mesh.height = chain_span + chain_plate_w * 2.0 + 0.005
	roller_mesh.radial_segments = 6
	mm_rollers.mesh = roller_mesh
	mm_rollers.instance_count = num_links * num_tracks
	multimesh_rollers.multimesh = mm_rollers
	multimesh_rollers.material_override = mat_chain
	visuals_root.add_child(multimesh_rollers)
	conveyor._multimesh_rollers = multimesh_rollers

	conveyor._update_chain_positions(0.0)
