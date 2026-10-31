shader_type spatial;

// ---- Surface textures --------------------------------------------------------
// Plain textures (or atlases). The mesh's UVs decide which part is used.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_tex : filter_linear_mipmap_anisotropic, repeat_disable;

// ---- Growth data (set by vertex_growth.gd at runtime) -----------------------
uniform sampler2D welded_ids : filter_nearest, hint_default_black;
uniform sampler2D growth_weights : filter_nearest, hint_default_black;

// ---- Growth look ------------------------------------------------------------
// Assign a NoiseTexture2D with a FastNoiseLite and Seamless turned on.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// Noise features per metre. Smaller = bigger blobs.
uniform float noise_scale = 0.4;
// How far the noise can push the edge, in growth-weight units. Keep this below
// 2 * (void_threshold - edge_softness) so zero growth never shows void.
uniform float noise_strength = 0.6;
// Growth weight (plus noise) at which the surface turns into the void.
uniform float void_threshold = 0.5;
uniform float edge_softness = 0.04;
// A band just before the void where the surface darkens and turns glossy.
uniform float creep_width = 0.25;
uniform float creep_darkening = 0.6;
uniform float creep_roughness = 0.25;
// Shows the raw growth weight as blue (0) to red (1) instead of the surface.
uniform bool debug_weights = false;

varying float growth;
varying vec3 world_pos;
varying vec3 world_normal;

float triplanar_noise(vec3 p, vec3 n) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.zy).r * w.x
		+ texture(noise_tex, p.xz).r * w.y
		+ texture(noise_tex, p.xy).r * w.z;
}

void vertex() {
	// raw vertex index -> welded vertex index
	ivec2 id_size = textureSize(welded_ids, 0);
	int welded = int(texelFetch(welded_ids, ivec2(VERTEX_ID % id_size.x, VERTEX_ID / id_size.x), 0).r + 0.5);

	// welded vertex index -> growth weight
	ivec2 weight_size = textureSize(growth_weights, 0);
	growth = texelFetch(growth_weights, ivec2(welded % weight_size.x, welded / weight_size.x), 0).r;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb;
	float roughness = texture(roughness_tex, UV).r;
	NORMAL_MAP = texture(normal_tex, UV).rgb;

	// Noise in world space pushes the growth edge around, so it no longer
	// follows the vertex grid.
	float noise = triplanar_noise(world_pos * noise_scale, normalize(world_normal));
	float g = growth + (noise - 0.5) * noise_strength;

	float creep = smoothstep(void_threshold - creep_width, void_threshold, g);
	float void_amount = smoothstep(void_threshold - edge_softness, void_threshold + edge_softness, g);

	albedo *= 1.0 - creep * creep_darkening;
	roughness = mix(roughness, creep_roughness, creep);

	// The void: black albedo and no specular, so lights add nothing.
	ALBEDO = mix(albedo, vec3(0.0), void_amount);
	ROUGHNESS = mix(roughness, 1.0, void_amount);
	SPECULAR = mix(0.5, 0.0, void_amount);
	METALLIC = 0.0;

	if (debug_weights) {
		ALBEDO = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), growth);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
}
