shader_type canvas_item;
render_mode unshaded;

uniform sampler2D front_art : source_color, filter_linear, repeat_disable;
uniform sampler2D turn_art : source_color, filter_linear, repeat_disable;
uniform vec2 canvas_size = vec2(280.0, 360.0);
uniform vec2 front_size = vec2(571.0, 1008.0);
uniform vec2 sheet_size = vec2(1536.0, 1024.0);
uniform vec4 from_region = vec4(0.0);
uniform vec4 to_region = vec4(0.0);
uniform bool from_front = true;
uniform bool to_front = true;
uniform float pose_mix = 0.0;
uniform float outline_width = 0.0;
uniform vec4 outline_color : source_color = vec4(0.956, 0.843, 0.494, 1.0);
varying vec4 item_color;

void vertex() { item_color = COLOR; }

vec4 sample_pose(vec2 point, bool front, vec4 region) {
	vec2 dimensions = front ? front_size : region.zw;
	float scale_factor = canvas_size.y / max(1.0, dimensions.y);
	vec2 pixel = vec2(point.x / scale_factor + dimensions.x * 0.5, point.y / scale_factor);
	if (pixel.x < 0.0 || pixel.y < 0.0 || pixel.x >= dimensions.x || pixel.y >= dimensions.y) return vec4(0.0);
	if (front) return texture(front_art, pixel / front_size);
	return texture(turn_art, (region.xy + pixel) / sheet_size);
}

vec4 body_at(vec2 point) {
	vec4 a = sample_pose(point, from_front, from_region);
	vec4 b = sample_pose(point, to_front, to_region);
	float alpha = mix(a.a, b.a, pose_mix);
	vec3 premultiplied = mix(a.rgb * a.a, b.rgb * b.a, pose_mix);
	return vec4(alpha > 0.00001 ? premultiplied / alpha : vec3(0.0), alpha);
}

void fragment() {
	vec2 point = vec2((UV.x - 0.5) * canvas_size.x, UV.y * canvas_size.y);
	vec4 body = body_at(point);
	float surround = body.a;
	if (outline_width > 0.0) {
		surround = max(surround, body_at(point + vec2(outline_width, 0.0)).a);
		surround = max(surround, body_at(point - vec2(outline_width, 0.0)).a);
		surround = max(surround, body_at(point + vec2(0.0, outline_width)).a);
		surround = max(surround, body_at(point - vec2(0.0, outline_width)).a);
		surround = max(surround, body_at(point + vec2(outline_width, outline_width) * 0.7071).a);
		surround = max(surround, body_at(point - vec2(outline_width, outline_width) * 0.7071).a);
		surround = max(surround, body_at(point + vec2(outline_width, -outline_width) * 0.7071).a);
		surround = max(surround, body_at(point - vec2(outline_width, -outline_width) * 0.7071).a);
	}
	float edge = max(0.0, surround - body.a) * outline_color.a;
	float alpha = body.a + edge;
	vec3 rgb = alpha > 0.00001 ? (body.rgb * body.a + outline_color.rgb * edge) / alpha : vec3(0.0);
	COLOR = vec4(rgb, alpha) * item_color;
}
