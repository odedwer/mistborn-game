shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Compatibility-renderer mist: the same world-height fade as
// soft_mist_particle.gdshader but without sampling the depth prepass (not
// reliably available on the Compatibility/GLES3 path), so the mist still
// renders there instead of silently failing to compile.

uniform sampler2D albedo_tex : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.55, 0.56, 0.62);
uniform float alpha_scale = 0.16;
uniform float fade_height_min = -9.0;
uniform float fade_height_max = -2.0;
uniform float fade_height_soft = 1.5;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float height_fade = smoothstep(fade_height_min, fade_height_min + fade_height_soft, v_world_y)
			* (1.0 - smoothstep(fade_height_max - fade_height_soft, fade_height_max, v_world_y));
	ALBEDO = tint;
	ALPHA = tex.a * alpha_scale * height_fade;
}
