shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D snow_color : filter_linear, repeat_disable;
uniform sampler2D snow_depth : filter_nearest, repeat_disable;
uniform bool foreground_only = false;
uniform float depth_cutoff = 10000.0;
uniform float stair_top;
uniform float stair_height;

void fragment() {
	vec4 color = texture(snow_color, UV);
	if (foreground_only) {
		vec4 hit = texture(snow_depth, UV);
		float packed_depth = dot(round(hit.rg * 255.0), vec2(256.0, 1.0));
		float ground_y = stair_top + packed_depth * stair_height / 65535.0;
		if (hit.a < 0.5 || ground_y < depth_cutoff) { color = vec4(0.0); }
	}
	COLOR = color;
}
