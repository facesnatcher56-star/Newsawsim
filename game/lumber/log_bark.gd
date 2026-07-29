extends RefCounted

var log = null
var bark_enabled: bool = true
var debarker_node_path: NodePath
var debarker_peel_radius: float = 0.04
var debarker_alignment_radius: float = 0.85
var fallback_debarker_pos: Vector3 = Vector3.ZERO

var bark_sections: Array[Node3D] = []
var bark_coat: CSGCylinder3D = null

func setup(
	owner_log: RigidBody3D,
	initial_bark_enabled: bool,
	initial_debarker_node_path: NodePath,
	initial_debarker_peel_radius: float,
	initial_debarker_alignment_radius: float,
	initial_fallback_debarker_pos: Vector3
) -> void:
	log = owner_log
	bark_enabled = initial_bark_enabled
	debarker_node_path = initial_debarker_node_path
	debarker_peel_radius = initial_debarker_peel_radius
	debarker_alignment_radius = initial_debarker_alignment_radius
	fallback_debarker_pos = initial_fallback_debarker_pos

	_create_bark()
	_create_bark_coat()
	_collect_bark_sections()
	_update_bark_coat()

func update() -> void:
	if bark_enabled:
		_update_bark_peeling()

func remove_bark() -> void:
	var bark := log.get_node_or_null("Bark") as Node3D
	if bark_enabled and bark:
		bark.visible = false
		bark_enabled = false

func is_enabled() -> bool:
	return bark_enabled

# Create visual bark as a simple box mesh matching the log size.
func _create_bark() -> void:
	if not bark_enabled:
		return
	if log.has_node("Bark"):
		return
	var bark_node = MeshInstance3D.new()
	bark_node.name = "Bark"
	var box = BoxMesh.new()
	box.size = Vector3(0.32, 1.9, 0.35)
	bark_node.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)
	bark_node.material_override = mat
	log.add_child(bark_node)

# A continuous, visual-only shell hides the seams between functional bark
# sections. The sections still control peeling and spawn the physical scraps.
func _create_bark_coat() -> void:
	if not bark_enabled:
		return
	var bark_root := log.get_node_or_null("Bark") as Node3D
	if bark_root == null:
		return
	bark_coat = bark_root.get_node_or_null("BarkCoat") as CSGCylinder3D
	if bark_coat:
		return

	bark_coat = CSGCylinder3D.new()
	bark_coat.name = "BarkCoat"
	bark_coat.radius = 0.291
	bark_coat.height = log.get_log_core_length()
	bark_coat.sides = 48
	bark_coat.smooth_faces = true
	bark_coat.rotation.z = PI * 0.5
	bark_coat.material = _create_bark_coat_material()
	bark_root.add_child(bark_coat)

func _create_bark_coat_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;

varying vec3 bark_pos;

void vertex() {
	bark_pos = VERTEX;
}

void fragment() {
	float angle = atan(bark_pos.z, bark_pos.x);
	float long_furrow = sin(angle * 11.0 + bark_pos.y * 3.5);
	float broken_furrow = sin(angle * 19.0 - bark_pos.y * 8.0 + sin(angle * 5.0));
	float fine_grain = sin(bark_pos.y * 37.0 + angle * 7.0);
	float grain = long_furrow * 0.16 + broken_furrow * 0.10 + fine_grain * 0.035;
	vec3 dark_bark = vec3(0.105, 0.047, 0.018);
	vec3 light_bark = vec3(0.285, 0.135, 0.045);
	ALBEDO = mix(dark_bark, light_bark, clamp(0.52 + grain, 0.0, 1.0));
	ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _collect_bark_sections() -> void:
	bark_sections.clear()
	var bark = log.get_node_or_null("Bark")
	if not bark:
		return
	for child in bark.get_children():
		if child is Node3D and String(child.name).begins_with("BarkSection"):
			bark_sections.append(child)
	if bark_sections.is_empty() and bark is Node3D:
		bark_sections.append(bark)

func _update_bark_peeling() -> void:
	var debarker_pos = _get_debarker_position()
	var remaining_sections := 0
	var coat_changed := false
	for section: Node3D in bark_sections:
		if not is_instance_valid(section):
			continue
		if section.visible:
			remaining_sections += 1
			if _section_is_inside_debarker(section, debarker_pos):
				section.visible = false
				remaining_sections -= 1
				coat_changed = true
				_spawn_bark_piece(section.global_position)
	if coat_changed:
		_update_bark_coat()
	if remaining_sections <= 0 and not bark_sections.is_empty():
		bark_enabled = false

func _update_bark_coat() -> void:
	if bark_coat == null:
		return
	var first_x := INF
	var last_x := -INF
	var visible_count := 0
	for section in bark_sections:
		if is_instance_valid(section) and section.visible:
			first_x = minf(first_x, section.position.x)
			last_x = maxf(last_x, section.position.x)
			visible_count += 1
	if visible_count == 0:
		bark_coat.visible = false
		return
	bark_coat.visible = true
	var section_length := _get_bark_section_length()
	bark_coat.height = maxf(section_length, last_x - first_x + section_length)
	bark_coat.position.x = (first_x + last_x) * 0.5

func _get_bark_section_length() -> float:
	for section in bark_sections:
		if not is_instance_valid(section):
			continue
		var body := section.get_node_or_null("Body") as CSGCylinder3D
		if body:
			return body.height
	if bark_sections.size() >= 2:
		var positions: Array[float] = []
		for section in bark_sections:
			if is_instance_valid(section):
				positions.append(section.position.x)
		positions.sort()
		if positions.size() >= 2:
			return absf(positions[1] - positions[0])
	return 0.161109

func _spawn_bark_piece(pos: Vector3) -> void:
	var bark_scene = load("res://game/lumber/bark_piece.tscn")
	if bark_scene:
		var bark = bark_scene.instantiate()
		for l_node in log.get_tree().get_nodes_in_group("logs"):
			if l_node is RigidBody3D:
				bark.add_collision_exception_with(l_node)

		log.get_parent().add_child(bark)
		bark.global_position = pos

		var angle = randf_range(0.0, 2.0 * PI)
		var peel_vel = Vector3(
			randf_range(-0.3, 0.3),
			cos(angle) * randf_range(0.6, 1.5),
			sin(angle) * randf_range(0.6, 1.5)
		)
		bark.linear_velocity = peel_vel + Vector3(0.0, -0.4, 0.0)
		bark.angular_velocity = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0)
		)

func _section_is_inside_debarker(section: Node3D, debarker_pos: Vector3) -> bool:
	var section_pos = section.global_position
	var cross_axis_distance = Vector2(section_pos.y - debarker_pos.y, section_pos.z - debarker_pos.z).length()
	if cross_axis_distance > debarker_alignment_radius:
		return false
	return abs(section_pos.x - debarker_pos.x) <= debarker_peel_radius

func _get_debarker_position() -> Vector3:
	var debarker = log.get_node_or_null(debarker_node_path)
	if debarker is Node3D:
		return debarker.global_position
	return fallback_debarker_pos
