shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
varying vec4 instance_tint;

void vertex() {
	float frame = round(INSTANCE_CUSTOM.r * 16.0);
	UV = (UV + vec2(mod(frame, 4.0), floor(frame / 4.0))) / vec2(4.0, 3.0);
	instance_tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	COLOR = vec4(texel.rgb * instance_tint.rgb * instance_tint.a, texel.a * instance_tint.a);
}
