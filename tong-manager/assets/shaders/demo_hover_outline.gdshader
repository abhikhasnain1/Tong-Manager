shader_type canvas_item;
render_mode unshaded;

uniform float pop_scale = 1.0;
uniform vec2 pop_pivot = vec2(0.0);
uniform float hover_tilt = 0.0;
uniform vec2 outline_texels = vec2(2.5);
uniform bool outline_enabled = true;
uniform vec4 stroke_color : source_color = vec4(1.0);

void vertex() {
	// Only rendered vertices move. Physics, placement and pouring anchors do not.
	vec2 offset = (VERTEX - pop_pivot) * pop_scale;
	float c = cos(hover_tilt);
	float s = sin(hover_tilt);
	VERTEX = pop_pivot + vec2(c * offset.x - s * offset.y, s * offset.x + c * offset.y);
}

float region_mask(vec2 point, vec4 region) {
	if (point.x < region.x || point.y < region.y || point.x > region.x + region.z || point.y > region.y + region.w) {
		return 0.0;
	}
	return 1.0;
}

void fragment() {
	if (outline_enabled) {
		vec2 step_uv = TEXTURE_PIXEL_SIZE * outline_texels;
		float neighbor = 1.0;
		vec2 point = UV + vec2(step_uv.x, 0.0);
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV - vec2(step_uv.x, 0.0);
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV + vec2(0.0, step_uv.y);
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV - vec2(0.0, step_uv.y);
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV + step_uv * 0.7071;
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV - step_uv * 0.7071;
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV + vec2(step_uv.x, -step_uv.y) * 0.7071;
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		point = UV + vec2(-step_uv.x, step_uv.y) * 0.7071;
		neighbor = min(neighbor, texture(TEXTURE, point).a * region_mask(point, REGION_RECT));
		float edge = smoothstep(0.06, 0.65, texture(TEXTURE, UV).a - neighbor);
		// An inner alpha edge avoids rectangular borders and atlas-neighbor bleed.
		COLOR.rgb = mix(COLOR.rgb, stroke_color.rgb, edge * stroke_color.a);
	}
}
