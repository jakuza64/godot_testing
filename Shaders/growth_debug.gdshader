shader_type spatial;
render_mode unshaded;

// Set by vertex_growth.gd at runtime.
uniform sampler2D welded_ids : filter_nearest, hint_default_black;
uniform sampler2D growth_weights : filter_nearest, hint_default_black;

uniform vec3 color_low : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 color_mid : source_color = vec3(0.0, 1.0, 0.0);
uniform vec3 color_high : source_color = vec3(1.0, 0.0, 0.0);
uniform float mid_stop : hint_range(0.01, 0.99) = 0.5;

varying float growth;

vec3 color_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < mid_stop) {
		return mix(color_low, color_mid, t / mid_stop);
	}
	return mix(color_mid, color_high, (t - mid_stop) / (1.0 - mid_stop));
}

void vertex() {
	// raw vertex index -> welded vertex index
	ivec2 id_size = textureSize(welded_ids, 0);
	int welded = int(texelFetch(welded_ids, ivec2(VERTEX_ID % id_size.x, VERTEX_ID / id_size.x), 0).r + 0.5);

	// welded vertex index -> weight
	ivec2 weight_size = textureSize(growth_weights, 0);
	growth = texelFetch(growth_weights, ivec2(welded % weight_size.x, welded / weight_size.x), 0).r;
}

void fragment() {
	ALBEDO = color_ramp(growth);
}
