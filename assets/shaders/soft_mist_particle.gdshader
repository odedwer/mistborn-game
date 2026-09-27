shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Soft billboard mist puffs: fades a particle out where it would cut a hard
// edge into nearby opaque geometry (the classic "soft particles" trick,
// using the depth prepass) instead of leaving a visible quad silhouette,
// AND fades out by world height so a whole field of particles never ends in
// a visible band where the emission volume happens to stop (see
// `fade_height_min/max` below) -- that band, not any one particle's own
// edge, is what read as a hard horizontal line across the sky before.

uniform sampler2D albedo_tex : source_color, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.55, 0.56, 0.62);
uniform float fade_distance = 3.0;
// Additive blending sums every overlapping puff, so each one needs to stay
// faint on its own (matching how thin real mist reads) or a cluster of
// puffs washes the whole view out to white.
uniform float alpha_scale = 0.16;
// World-Y band the mist is allowed to be visible in, with a soft fade at
// both ends -- independent of wherever the emitter's own bounding volume
// happens to end.
uniform float fade_height_min = -9.0;
uniform float fade_height_max = -2.0;
uniform float fade_height_soft = 1.5;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_view_z = -view.z;
	float particle_view_z = -VERTEX.z;
	float depth_fade = clamp((scene_view_z - particle_view_z) / fade_distance, 0.0, 1.0);
	float height_fade = smoothstep(fade_height_min, fade_height_min + fade_height_soft, v_world_y)
			* (1.0 - smoothstep(fade_height_max - fade_height_soft, fade_height_max, v_world_y));
	ALBEDO = tint;
	ALPHA = tex.a * depth_fade * alpha_scale * height_fade;
}
