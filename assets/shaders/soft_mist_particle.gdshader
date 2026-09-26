shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Soft billboard mist puffs: fades a particle out where it would cut a hard
// edge into nearby opaque geometry (the classic "soft particles" trick,
// using the depth prepass) instead of leaving a visible quad silhouette.

uniform sampler2D albedo_tex : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.55, 0.56, 0.62);
uniform float fade_distance = 3.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float scene_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_view_z = -view.z;
	float particle_view_z = -VERTEX.z;
	float depth_fade = clamp((scene_view_z - particle_view_z) / fade_distance, 0.0, 1.0);
	ALBEDO = tint;
	ALPHA = tex.a * depth_fade;
}
