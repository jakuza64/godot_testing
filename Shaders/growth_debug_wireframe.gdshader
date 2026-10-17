shader_type spatial;
render_mode unshaded, wireframe;

// Use this as the Next Pass of the growth debug material to overlay the mesh's
// triangle edges on top of the growth colors.

uniform vec3 line_color : source_color = vec3(0.0, 0.0, 0.0);
// Pushes the lines slightly off the surface so they don't z-fight with the
// filled pass underneath. Raise it if the lines look broken up at a distance.
uniform float normal_offset = 0.003;

void vertex() {
	VERTEX += NORMAL * normal_offset;
}

void fragment() {
	ALBEDO = line_color;
}
