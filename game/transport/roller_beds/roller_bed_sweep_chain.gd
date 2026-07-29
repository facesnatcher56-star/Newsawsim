@tool
class_name RollerBedSweepChain
extends RefCounted

const SWEEP_SPROCKET_R := 0.08
const SWEEP_PITCH := 0.12

var _bed = null
var _sweep_lugs: Array[AnimatableBody3D] = []
var _sweep_lug_push_areas: Array[Area3D] = []
var _sweep_sprockets: Array[MeshInstance3D] = []
var _sweep_chain_nodes: Array[Node3D] = []
var _sweep_chain_gzipped: Array[float] = []
var _sweep_chain_slots: Array[float] = []
var _sweep_travel: float = 0.0
var _sweep_active: bool = false
var _sweep_sensor: Area3D = null


func setup(bed: Node) -> void:
	_bed = bed


func physics_process(delta: float) -> void:
	if _bed == null or not _bed.sweep_chain_present or not _sweep_active or _sweep_lugs.is_empty():
		return

	_sweep_travel += _bed.sweep_speed * delta
	if _sweep_travel >= _sweep_loop_length():
		_sweep_travel = 0.0
		_sweep_active = false

	_update_sweep_visuals(_sweep_travel)
	_apply_sweep_push(delta)


func rebuild(travel: Vector3, local_up: Vector3, radius: float) -> void:
	if _bed == null:
		return

	_clear_generated_nodes()
	_clear_runtime_state()

	if not _bed.sweep_chain_present:
		return

	var sweep_container := Node3D.new()
	sweep_container.name = "GeneratedSweepSystem"
	_bed.add_child(sweep_container)

	var R: float = SWEEP_SPROCKET_R
	var Y_top: float = radius - 0.02
	var Y_center: float = Y_top - R

	var X_start: float = -_bed.roller_length * 0.5 - 0.15
	var X_end: float = _bed.roller_length * 0.5 + 0.15
	var L_span: float = X_end - X_start
	var loop_len: float = 2.0 * L_span + 2.0 * PI * R

	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.22, 0.24, 0.25)
	mat_metal.metallic = 0.85
	mat_metal.roughness = 0.35

	var mat_lug := StandardMaterial3D.new()
	mat_lug.albedo_color = Color(0.9, 0.75, 0.1)
	mat_lug.metallic = 0.3
	mat_lug.roughness = 0.4

	var mat_chain := StandardMaterial3D.new()
	mat_chain.albedo_color = Color(0.15, 0.15, 0.17)
	mat_chain.metallic = 0.9
	mat_chain.roughness = 0.4

	var center_offset: float = float(_bed.roller_count - 1) * 0.5
	var gap_z_offsets: Array[float] = []
	if _bed.roller_count > 1:
		for index in range(_bed.roller_count - 1):
			gap_z_offsets.append((float(index) + 0.5 - center_offset) * _bed.roller_spacing)
	else:
		gap_z_offsets.append(0.0)

	var sweep_statics := StaticBody3D.new()
	sweep_statics.name = "Statics"
	sweep_container.add_child(sweep_statics)

	for gz in gap_z_offsets:
		var gap_pos: Vector3 = travel * gz

		var sp_l := MeshInstance3D.new()
		var sp_l_mesh := CylinderMesh.new()
		sp_l_mesh.top_radius = R
		sp_l_mesh.bottom_radius = R
		sp_l_mesh.height = 0.03
		sp_l_mesh.radial_segments = 10
		sp_l.mesh = sp_l_mesh
		sp_l.material_override = mat_metal
		sp_l.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), gap_pos + Vector3(X_start, Y_center, 0.0))
		sweep_statics.add_child(sp_l)
		_sweep_sprockets.append(sp_l)

		var sp_r := MeshInstance3D.new()
		var sp_r_mesh := CylinderMesh.new()
		sp_r_mesh.top_radius = R
		sp_r_mesh.bottom_radius = R
		sp_r_mesh.height = 0.03
		sp_r_mesh.radial_segments = 10
		sp_r.mesh = sp_r_mesh
		sp_r.material_override = mat_metal
		sp_r.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), gap_pos + Vector3(X_end, Y_center, 0.0))
		sweep_statics.add_child(sp_r)
		_sweep_sprockets.append(sp_r)

		var guide := MeshInstance3D.new()
		var guide_mesh := BoxMesh.new()
		guide_mesh.size = Vector3(L_span, 0.03, 0.04)
		guide.mesh = guide_mesh
		guide.material_override = mat_metal
		guide.transform = Transform3D(Basis.IDENTITY, gap_pos + Vector3(0.0, Y_center, 0.0))
		sweep_statics.add_child(guide)

	var lug_mesh := PrismMesh.new()
	lug_mesh.size = Vector3(_bed.lug_base_length, _bed.lug_height, 0.05)
	lug_mesh.left_to_right = 1.0

	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(_bed.lug_base_length + 0.03, 0.008, 0.055)

	var lug_shape := BoxShape3D.new()
	lug_shape.size = Vector3(_bed.lug_base_length, _bed.lug_height, 0.05)

	var lug_collision_y: float = 0.008 + _bed.lug_height * 0.5

	for i in range(gap_z_offsets.size()):
		var lug := AnimatableBody3D.new()
		lug.name = "Lug_%d" % i
		lug.sync_to_physics = true
		sweep_container.add_child(lug)
		_sweep_lugs.append(lug)

		var plate_mi := MeshInstance3D.new()
		plate_mi.name = "MountingPlate"
		plate_mi.mesh = plate_mesh
		plate_mi.material_override = mat_lug
		plate_mi.position = Vector3(0.0, 0.004, 0.0)
		lug.add_child(plate_mi)

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = lug_mesh
		mi.material_override = mat_lug
		mi.position = Vector3(0.0, lug_collision_y, 0.0)
		lug.add_child(mi)

		var col := CollisionShape3D.new()
		col.name = "Collision"
		col.shape = lug_shape
		col.position = Vector3(0.0, lug_collision_y, 0.0)
		lug.add_child(col)

		var push_area := Area3D.new()
		push_area.name = "PushArea"
		push_area.monitoring = true
		push_area.monitorable = false
		var push_col := CollisionShape3D.new()
		push_col.shape = lug_shape
		push_col.position = col.position
		push_area.add_child(push_col)
		lug.add_child(push_area)
		_sweep_lug_push_areas.append(push_area)

	var n_links: int = int(ceil(loop_len / SWEEP_PITCH)) + 2

	var link_plate_mesh := BoxMesh.new()
	link_plate_mesh.size = Vector3(SWEEP_PITCH * 0.85, 0.024, 0.005)

	var link_roller_mesh := CylinderMesh.new()
	link_roller_mesh.top_radius = 0.015
	link_roller_mesh.bottom_radius = 0.015
	link_roller_mesh.height = 0.035
	link_roller_mesh.radial_segments = 6

	for i in range(gap_z_offsets.size()):
		var gz: float = gap_z_offsets[i]
		for j in range(n_links):
			var slot_pos: float = float(j) * SWEEP_PITCH

			var link := Node3D.new()
			link.name = "ChainLink_%d_%d" % [i, j]

			var lp := MeshInstance3D.new()
			lp.mesh = link_plate_mesh
			lp.material_override = mat_chain
			lp.position = Vector3(0.0, 0.0, -0.016)
			link.add_child(lp)

			var rp := MeshInstance3D.new()
			rp.mesh = link_plate_mesh
			rp.material_override = mat_chain
			rp.position = Vector3(0.0, 0.0, 0.016)
			link.add_child(rp)

			var ro := MeshInstance3D.new()
			ro.mesh = link_roller_mesh
			ro.material_override = mat_chain
			ro.rotation_degrees.x = 90.0
			link.add_child(ro)

			sweep_container.add_child(link)

			_sweep_chain_nodes.append(link)
			_sweep_chain_gzipped.append(gz)
			_sweep_chain_slots.append(slot_pos)

	var last_roller_pos: Vector3 = travel * (center_offset * _bed.roller_spacing + _bed.sweep_trigger_offset)
	var sensor := Area3D.new()
	sensor.name = "SweepSensor"
	sensor.transform = Transform3D(Basis.IDENTITY, last_roller_pos + local_up * (radius + 0.15))
	_bed.add_child(sensor)
	_sweep_sensor = sensor

	var sensor_shape := CollisionShape3D.new()
	sensor_shape.name = "Collision"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(_bed.roller_length, 0.5, 0.25)
	sensor_shape.shape = box_shape
	sensor.add_child(sensor_shape)

	sensor.body_entered.connect(_on_sweep_sensor_body_entered)

	_update_sweep_visuals(0.0)


func trigger() -> void:
	if _bed == null or not _bed.sweep_chain_present or _sweep_active:
		return
	_sweep_active = true
	_sweep_travel = 0.0


func _clear_generated_nodes() -> void:
	if _bed == null:
		return

	var old_sweep: Node = _bed.get_node_or_null("GeneratedSweepSystem")
	if old_sweep != null:
		if Engine.is_editor_hint():
			_bed.remove_child(old_sweep)
		old_sweep.queue_free()

	var old_sensor: Node = _bed.get_node_or_null("SweepSensor")
	if old_sensor != null:
		if Engine.is_editor_hint():
			_bed.remove_child(old_sensor)
		old_sensor.queue_free()


func _clear_runtime_state() -> void:
	_sweep_lugs.clear()
	_sweep_lug_push_areas.clear()
	_sweep_sprockets.clear()
	_sweep_chain_nodes.clear()
	_sweep_chain_gzipped.clear()
	_sweep_chain_slots.clear()
	_sweep_sensor = null
	_sweep_active = false
	_sweep_travel = 0.0


func _sweep_loop_span() -> float:
	return _bed.roller_length + 0.30


func _sweep_loop_length() -> float:
	return 2.0 * _sweep_loop_span() + 2.0 * PI * SWEEP_SPROCKET_R


func _is_sweep_on_top_run(d: float) -> bool:
	return fposmod(d, _sweep_loop_length()) < _sweep_loop_span()


func _update_sweep_visuals(p_travel: float) -> void:
	var R: float = SWEEP_SPROCKET_R
	var X_start: float = -_bed.roller_length * 0.5 - 0.15
	var X_end: float = _bed.roller_length * 0.5 + 0.15
	var L_span: float = X_end - X_start
	var loop_len: float = 2.0 * L_span + 2.0 * PI * R

	var center_offset: float = float(_bed.roller_count - 1) * 0.5
	for i in range(_sweep_lugs.size()):
		var lug := _sweep_lugs[i]
		if is_instance_valid(lug):
			var gz: float = (float(i) + 0.5 - center_offset) * _bed.roller_spacing if _bed.roller_count > 1 else 0.0
			lug.transform = _get_sweep_loop_xform(p_travel, gz)

	for i in range(_sweep_chain_nodes.size()):
		var node = _sweep_chain_nodes[i]
		if is_instance_valid(node):
			var slot: float = fposmod(_sweep_chain_slots[i] + p_travel, loop_len)
			node.transform = _get_sweep_loop_xform(slot, _sweep_chain_gzipped[i])

	var ang_rad: float = -p_travel / R
	for sp in _sweep_sprockets:
		if is_instance_valid(sp):
			sp.rotation.y = ang_rad


func _get_sweep_loop_xform(d: float, gz: float) -> Transform3D:
	var R: float = SWEEP_SPROCKET_R
	var Y_top: float = (_bed.roller_diameter * 0.5) - 0.02
	var Y_center: float = Y_top - R
	var Y_bot: float = Y_center - R

	var X_start: float = -_bed.roller_length * 0.5 - 0.15
	var X_end: float = _bed.roller_length * 0.5 + 0.15
	var L_span: float = X_end - X_start

	var loop_len: float = 2.0 * L_span + 2.0 * PI * R
	d = fposmod(d, loop_len)

	var x: float
	var y: float
	var rot_z: float

	if d < L_span:
		x = X_start + d
		y = Y_top
		rot_z = 0.0
	elif d < L_span + PI * R:
		var theta: float = (d - L_span) / R
		x = X_end + R * sin(theta)
		y = Y_center + R * cos(theta)
		rot_z = theta
	elif d < 2.0 * L_span + PI * R:
		var d_ret: float = d - (L_span + PI * R)
		x = X_end - d_ret
		y = Y_bot
		rot_z = PI
	else:
		var theta: float = (d - (2.0 * L_span + PI * R)) / R
		x = X_start - R * sin(theta)
		y = Y_center - R * cos(theta)
		rot_z = PI + theta

	return Transform3D(Basis(Vector3.FORWARD, rot_z), Vector3(x, y, gz))


func _apply_sweep_push(delta: float) -> void:
	if not _sweep_active or not _is_sweep_on_top_run(_sweep_travel):
		return

	var travel: Vector3 = _bed._local_travel_direction()
	var roller_axis: Vector3 = travel.cross(Vector3.UP).normalized()
	var push_dir: Vector3 = (_bed.global_transform.basis * roller_axis).normalized()
	var target_vel: Vector3 = push_dir * _bed.sweep_speed
	var accel: float = _bed.sweep_speed * 4.0

	for area in _sweep_lug_push_areas:
		if not is_instance_valid(area):
			continue
		for body in area.get_overlapping_bodies():
			if not (body is RigidBody3D):
				continue
			if not (body.is_in_group("logs") or body.is_in_group("cut_boards")):
				continue
			if body.freeze:
				continue
			body.sleeping = false
			var horizontal_velocity: Vector3 = Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
			var target_horizontal: Vector3 = Vector3(target_vel.x, 0.0, target_vel.z)
			horizontal_velocity = horizontal_velocity.move_toward(target_horizontal, accel * delta)
			body.linear_velocity = Vector3(
				horizontal_velocity.x,
				body.linear_velocity.y,
				horizontal_velocity.z
			)


func _on_sweep_sensor_body_entered(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if _bed == null or not _bed.sweep_chain_present or not _bed.auto_sweep:
		return
	if _sweep_active:
		return

	if body is RigidBody3D and (body.is_in_group("logs") or body.is_in_group("cut_boards")):
		_sweep_active = true
		_sweep_travel = 0.0
