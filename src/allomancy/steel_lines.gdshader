// Steel/iron lines: camera-facing additive ribbons, one MultiMesh instance each.
// Instance transform: origin = line start, basis Y = start->end vector.
// INSTANCE_CUSTOM: x = width (m), y = brightness, z = highlight (0 none, 1 target, 2 active).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform vec4 line_color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float intensity = 1.4;
uniform float min_pixel_width = 1.4;

varying float v_bright;
varying float v_across;
varying float v_along;
varying float v_hl;

void vertex() {
	vec3 a = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 b = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 1.0)).xyz;
	vec3 p = mix(a, b, VERTEX.y);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - p;
	vec3 side = cross(b - a, to_cam);
	float sl = length(side);
	side = sl > 1e-6 ? side / sl : vec3(1.0, 0.0, 0.0);
	float depth = max(length(to_cam), 0.05);
	// World size of one pixel at this depth, so distant lines stay >= ~1px.
	float px = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = INSTANCE_CUSTOM.x;
	float wmin = px * min_pixel_width;
	float thin_fade = clamp(w / wmin, 0.3, 1.0);
	w = max(w, wmin);
	v_across = VERTEX.x * 2.0;
	v_along = VERTEX.y;
	v_bright = INSTANCE_CUSTOM.y * thin_fade;
	v_hl = INSTANCE_CUSTOM.z;
	vec3 wp = p + side * (VERTEX.x * w);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float edge = 1.0 - abs(v_across);
	edge = edge * edge * (3.0 - 2.0 * edge);
	float along = smoothstep(0.0, 0.06, v_along) * (0.6 + 0.4 * v_along);
	float hl = clamp(v_hl, 0.0, 1.0);
	float active = clamp(v_hl - 1.0, 0.0, 1.0);
	float pulse = active * (0.5 + 0.5 * sin(TIME * 30.0 - v_along * 12.0));
	vec3 col = mix(line_color.rgb, highlight_color.rgb, hl);
	float b = v_bright * edge * along * intensity * (1.0 + hl * 0.8 + active * 0.8 + pulse * 0.6);
	ALBEDO = col * b;
	ALPHA = 1.0;
}
