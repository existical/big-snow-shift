shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D snow_mask : filter_linear, repeat_disable;
uniform float stair_left;
uniform float stair_width;
uniform float stair_top;
uniform float stair_height;
uniform float tread_left[16];
uniform float tread_right[16];
uniform float tread_edges[17];
uniform bool output_depth = false;
uniform vec2 cache_uv_origin = vec2(0.0);
uniform vec2 cache_uv_size = vec2(1.0);
const float PAD = 60.0;

float noise(vec2 p) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 n = fract(sin(vec4(dot(c,vec2(127.1,311.7)), dot(c+vec2(1,0),vec2(127.1,311.7)), dot(c+vec2(0,1),vec2(127.1,311.7)), dot(c+vec2(1,1),vec2(127.1,311.7)))) * 43758.5453);
	return mix(mix(n.x,n.y,f.x), mix(n.z,n.w,f.x),f.y);
}

// Orthographic height-field intersection. Each occupied ground cell is a real
// column: its top projects upward, and an exposed edge reveals a vertical face.
// A second depth-filtered pass lets these SAME columns occlude the shovel/boots.
void fragment() {
	vec2 at = cache_uv_origin + UV * cache_uv_size;
	vec2 pixel = vec2(stair_left + at.x * stair_width, stair_top - PAD + at.y * (stair_height + PAD));
	int initial_row = 15;
	for (int r = 0; r < 16; r++) {
		if (pixel.y < tread_edges[r + 1]) { initial_row = r; break; }
	}
	vec4 result = vec4(0.0);
	for (int step = 0; step < 61; step++) {
		float z = PAD - float(step);
		float ground_y = pixel.y + z;
		if (ground_y < stair_top || ground_y > stair_top + stair_height) { continue; }
		int row = initial_row;
		for (int advance = 0; advance < 5; advance++) {
			if (row < 15 && ground_y >= tread_edges[row + 1]) { row++; } else { break; }
		}
		float phase = clamp((ground_y - tread_edges[row]) / (tread_edges[row + 1] - tread_edges[row]), 0.0, 1.0);
		float widen = row > 0 ? smoothstep(0.0, .15, phase) : 1.0;
		float left = mix(tread_left[max(0,row-1)], tread_left[row], widen);
		float right = mix(tread_right[max(0,row-1)], tread_right[row], widen);
		float side = min(pixel.x - left, right - pixel.x);
		if (side <= 0.0) { continue; }
		vec2 ground = vec2((pixel.x - left) / (right - left), (ground_y - stair_top) / stair_height);
		vec3 field = texture(snow_mask, ground).rgb;
		float amount = field.r;
		if (amount + field.b < .002) { continue; }
		float coverage = smoothstep(.0, .85, field.g);
		float roll = .40 + .60 * smoothstep(0.0, .54, phase) - .12 * smoothstep(.78, 1.0, phase);
		float drift = noise(vec2(pixel.x * .035, float(row) * 2.71));
		float base_height = amount > .002 ? mix(11.5, 19.0, ground.y) * sqrt(amount) * roll : 0.0;
		// The blue channel is a smooth extra-height field. A deposited mound
		// tapers all the way down. Both layers shrink as scoops remove depth.
		float mound = 36.0 * sqrt(max(field.b, 0.0));
		float height = (base_height + mound) * coverage * smoothstep(0.0, 4.0, side);
		height += (drift - .5) * 3.0 * coverage * smoothstep(0.0, 5.0, base_height);
		if (z > height) { continue; }
		// Stop at the first visible column even when it is behind the player.
		// Continuing would incorrectly draw a farther column over the character.
		if (!output_depth) {
			float wall = smoothstep(1.1, 2.8, height - z);
			// Fractional coverage is the rounded slope of an exposed cut. Shade
			// it as a face, even when the ray enters through its curved surface.
			wall = max(wall, 1.0 - smoothstep(.55, .98, field.g));
			wall *= smoothstep(1.0, 5.0, base_height + mound);
			float light = clamp(z / max(height, .1), 0.0, 1.0);
			float round_light = .35 + .65 * smoothstep(0.0, .65, phase);
			vec3 cap = mix(vec3(.72,.86,.94), vec3(.97,.99,1.0), round_light);
			// A partly dug base can itself become a small rounded heap. Light
			// that slope without exposing the height ray's discrete contour bands.
			// Coverage still shades the actual cut faces at the footprint edges.
			float shaved = 1.0 - smoothstep(.65, .95, amount);
			wall = mix(wall, 1.0 - smoothstep(.55, .98, field.g), shaved);
			if (field.b > .001) {
				vec2 texel = vec2(1.0 / 144.0, 1.0 / 72.0);
				float west = sqrt(max(texture(snow_mask, ground - vec2(texel.x, 0)).b, 0.0));
				float north = sqrt(max(texture(snow_mask, ground - vec2(0, texel.y)).b, 0.0));
				float slope_light = clamp(1.0 - (sqrt(field.b) - west) * .9 - (sqrt(field.b) - north) * .6, .76, 1.08);
				float pile_blend = amount > .002 ? smoothstep(0.0, 4.0, mound) : 1.0;
				cap = mix(cap, vec3(.94,.98,1.0) * slope_light, pile_blend);
				// A smooth dome is lit by its slope, never by the quantized ray
				// depth: that produced contour stripes across rounded mounds.
				wall = mix(wall, 1.0 - smoothstep(.55,.98,field.g), pile_blend);
			}
			cap += (drift - .5) * .022;
			vec3 face = mix(vec3(.40,.64,.80), vec3(.73,.87,.95), light);
			vec3 snow = mix(cap, face, wall);
			snow += (noise(pixel * .42) - .5) * .028;
			// Soft upper lip; avoid shading by quantized ray-step fractions.
			snow += (1.0 - wall) * vec3(.012,.009,.004);
			float alpha = smoothstep(0.0, 2.0, side) * smoothstep(.0, .4, field.g);
			result = vec4(snow * alpha, alpha);
		} else {
			// Store the FIRST hit, independent of the moving actor cutoff.
			float depth = round(clamp((ground_y - stair_top) / stair_height, 0.0, 1.0) * 65535.0);
			result = vec4(floor(depth / 256.0) / 255.0, mod(depth, 256.0) / 255.0, 0.0, 1.0);
		}
		break;
	}
	COLOR = result;
}
