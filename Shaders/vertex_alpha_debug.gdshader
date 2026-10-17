shader_type spatial;
render_mode unshaded;

uniform vec3 color_low : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 color_mid : source_color = vec3(0.0, 1.0, 0.0);
uniform vec3 color_high : source_color = vec3(1.0, 0.0, 0.0);
uniform float mid_stop : hint_range(0.01, 0.99) = 0.5;

vec3 color_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < mid_stop) {
		return mix(color_low, color_mid, t / mid_stop);
	}
	return mix(color_mid, color_high, (t - mid_stop) / (1.0 - mid_stop));
}

void fragment() {
	ALBEDO = color_ramp(COLOR.a);
}