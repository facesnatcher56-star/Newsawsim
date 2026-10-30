extends RefCounted

## Helper owned by log.gd: builds, peels and removes a log's bark coat as it passes the debarker.

var log_node: RigidBody3D = null
var bark_enabled: bool = true
var debarker_node_path: NodePath
var debarker_peel_radius: float = 0.04
var debarker_alignment_radius: float = 0.85
var fallback_debarker_pos: Vector3 = Vector3.ZERO

## Spacing of the BarkSection markers in log.tscn; each one peels a 16 cm band.
const BARK_SECTION_LENGTH := 0.161109
## Bark is thicker at the butt end (+X) than at the top end, like a real stem.
const BARK_BUTT_RADIUS := 0.300
const BARK_TOP_RADIUS := 0.284

static var _coat_material: ShaderMaterial = null

var bark_sections: Array[Node3D] = []
var bark_coat: MeshInstance3D = null

func setup(
	owner_log: RigidBody3D,
	initial_bark_enabled: bool,
	initial_debarker_node_path: NodePath,
	initial_debarker_peel_radius: float,
	initial_debarker_alignment_radius: float,
	initial_fallback_debarker_pos: Vector3
) -> void:
	log_node = owner_log
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
	var bark := log_node.get_node_or_null("Bark") as Node3D
	if bark_enabled and bark:
		bark.visible = false
		bark_enabled = false

func is_enabled() -> bool:
	return bark_enabled

# Create visual bark as a simple box mesh matching the log size.
func _create_bark() -> void:
	if not bark_enabled:
		return
	if log_node.has_node("Bark"):
		return
	var bark_node = MeshInstance3D.new()
	bark_node.name = "Bark"
	var box = BoxMesh.new()
	box.size = Vector3(0.32, 1.9, 0.35)
	bark_node.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)
	bark_node.material_override = mat
	log_node.add_child(bark_node)

# A continuous, visual-only shell hides the seams between functional bark
# sections. The sections still control peeling and spawn the physical scraps.
func _create_bark_coat() -> void:
	if not bark_enabled:
		return
	var bark_root := log_node.get_node_or_null("Bark") as Node3D
	if bark_root == null:
		return
	bark_coat = bark_root.get_node_or_null("BarkCoat") as MeshInstance3D
	if bark_coat:
		return

	var mesh := CylinderMesh.new()
	# CylinderMesh runs along local Y; rotated +90 deg about Z its bottom lands at +X,
	# so the butt (bottom) radius goes at +X and the log tapers toward -X.
	mesh.bottom_radius = BARK_BUTT_RADIUS
	mesh.top_radius = BARK_TOP_RADIUS
	mesh.height = log_node.get_log_core_length()
	mesh.radial_segments = 40
	mesh.rings = 1
	bark_coat = MeshInstance3D.new()
	bark_coat.name = "BarkCoat"
	bark_coat.mesh = mesh
	bark_coat.rotation.z = PI * 0.5
	bark_coat.material_override = _get_bark_coat_material()
	bark_root.add_child(bark_coat)

func _get_bark_coat_material() -> ShaderMaterial:
	if _coat_material != null:
		return _coat_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;

varying vec3 bark_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	bark_pos = VERTEX;
}

void fragment() {
	// Plates of bark split by deep, wandering vertical furrows (conifer bark).
	float angle = atan(bark_pos.z, bark_pos.x);
	vec2 uv = vec2(angle * 2.6, bark_pos.y * 2.2);
	float wander = vnoise(uv * vec2(0.6, 0.35)) * 2.0;
	float furrow = abs(sin(angle * 9.0 + wander + bark_pos.y * 0.6));
	float plates = smoothstep(0.05, 0.45, furrow);
	float cracks = smoothstep(0.82, 0.95, vnoise(uv * vec2(3.0, 9.0)));
	float tone = vnoise(uv * 1.7) * 0.6 + vnoise(uv * 6.0) * 0.4;
	vec3 furrow_col = vec3(0.045, 0.022, 0.010);
	vec3 plate_dark = vec3(0.11, 0.055, 0.024);
	vec3 plate_light = vec3(0.22, 0.12, 0.055);
	vec3 col = mix(plate_dark, plate_light, tone);
	col = mix(furrow_col, col, plates * (1.0 - cracks * 0.7));
	// Odd patches of grey-green lichen on the plate faces.
	float lichen = smoothstep(0.84, 0.9, vnoise(uv * vec2(1.3, 2.4) + 17.0)) * plates;
	col = mix(col, vec3(0.20, 0.21, 0.17), lichen * 0.5);
	ALBEDO = col;
	ROUGHNESS = mix(0.98, 0.88, plates);
	// Furrows read as recessed.
	AO = mix(0.35, 1.0, plates);
	AO_LIGHT_AFFECT = 0.6;
}
"""
	_coat_material = ShaderMaterial.new()
	_coat_material.shader = shader
	return _coat_material

func _collect_bark_sections() -> void:
	bark_sections.clear()
	var bark = log_node.get_node_or_null("Bark")
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
	var section_length := BARK_SECTION_LENGTH
	var mesh := bark_coat.mesh as CylinderMesh
	if mesh:
		mesh.height = maxf(section_length, last_x - first_x + section_length)
	bark_coat.position.x = (first_x + last_x) * 0.5

func _spawn_bark_piece(pos: Vector3) -> void:
	var bark_scene = load("res://game/lumber/bark_piece.tscn")
	if bark_scene:
		var bark = bark_scene.instantiate()
		for l_node in log_node.get_tree().get_nodes_in_group("logs"):
			if l_node is RigidBody3D:
				bark.add_collision_exception_with(l_node)

		log_node.get_parent().add_child(bark)
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
	var debarker = log_node.get_node_or_null(debarker_node_path)
	if debarker is Node3D:
		return debarker.global_position
	# The ring debarker's rotor joins this group; logs come from anywhere (yard piles,
	# the mill root), so a fixed relative path rarely resolves.
	var best: Node3D = null
	for ring in log_node.get_tree().get_nodes_in_group("debarker_ring"):
		if ring is Node3D and (best == null or ring.global_position.distance_squared_to(log_node.global_position)
				< best.global_position.distance_squared_to(log_node.global_position)):
			best = ring
	if best:
		return best.global_position
	return fallback_debarker_pos
