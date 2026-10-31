// Debarked log wood: growth rings on sawn faces and end grain, long streaky grain and darker
// blotches on the round, a darker heart. Each log sets its own tint, seed and ring spacing
// (log.gd), so no two look the same.
shader_type spatial;
render_mode diffuse_burley;

// The log's long axis is local Y (CSG cylinder) unless along_x; axis_offset moves the ring
// centre (a slab's cylinder sits off its body origin).
uniform bool along_x = false;
uniform vec3 axis_offset = vec3(0.0);

instance uniform vec3 tint = vec3(1.0);
instance uniform float seed = 0.0;
instance uniform float ring_scale = 160.0;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX - axis_offset;
	if (along_x) {
		local_pos = local_pos.yxz;
	}
}

void fragment() {
	vec3 p = local_pos;
	vec3 s = vec3(seed * 17.3, seed * 5.1, seed * 11.7);
	// Rings: distance from the pith, wobbled so they are not perfect circles.
	float warp = noise(vec3(p.x * 14.0, p.y * 0.9, p.z * 14.0) + s) - 0.5;
	float r = length(p.xz) + warp * 0.018 + sin(p.y * 1.7 + seed * 6.0) * 0.004;
	float rings = smoothstep(0.35, 0.95, 0.5 + 0.5 * sin(r * ring_scale + seed * 9.0));
	// Long grain: thin streaks along the log.
	float streak = noise(vec3(p.x * 70.0, p.y * 1.4, p.z * 70.0) + s);
	streak = smoothstep(0.35, 0.8, streak);
	float streak2 = smoothstep(0.5, 0.9, noise(vec3(p.x * 160.0, p.y * 3.0, p.z * 160.0) + s * 0.7));
	float fine = noise(vec3(p.x * 240.0, p.y * 9.0, p.z * 240.0) + s);
	// Blotches where the cambium dried darker, and bark scraps the ring missed.
	float blot = smoothstep(0.5, 0.85, noise(vec3(p.x * 5.0, p.y * 0.7, p.z * 5.0) + s * 1.3));
	// Bark the debarker's tools skipped: patches and strips on the round, never on sawn faces.
	float scrap = smoothstep(0.66, 0.82, noise(vec3(p.x * 9.0, p.y * 2.2, p.z * 9.0) + s * 2.1))
			* smoothstep(0.235, 0.244, length(p.xz));
	vec3 light = vec3(0.50, 0.36, 0.21) * tint;
	vec3 dark = vec3(0.28, 0.17, 0.08) * tint;
	float g = clamp(rings * 0.45 + streak * 0.35 + streak2 * 0.2 + fine * 0.12 + blot * 0.3, 0.0, 1.0);
	vec3 col = mix(light, dark, g);
	// Heartwood a touch darker and redder.
	col = mix(col, col * vec3(0.82, 0.70, 0.62), smoothstep(0.13, 0.05, r) * 0.6);
	col = mix(col, vec3(0.16, 0.10, 0.06), scrap * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
}
