shader_type spatial;
render_mode cull_back, shadows_disabled;
// Far-LOD city skyline. Discards fragments inside chunks that are currently
// streamed in at full detail (loaded_mask), and fakes scattered lit windows
// on vertical faces. Vertex colour rgb = shade, a = window density factor.

uniform sampler2D loaded_mask : filter_nearest;
uniform bool use_mask = true;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_cells = vec2(1.0);
uniform float chunk_size = 128.0;
uniform vec3 base_color : source_color = vec3(0.09, 0.088, 0.086);
uniform vec3 window_color : source_color = vec3(1.0, 0.55, 0.22);
uniform float window_density = 0.1;
uniform float window_energy = 2.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (use_mask) {
		vec2 cell = floor((wpos.xz - mask_origin) / chunk_size);
		if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < mask_cells.x && cell.y < mask_cells.y) {
			if (texelFetch(loaded_mask, ivec2(cell), 0).r > 0.5) {
				discard;
			}
		}
	}
	ALBEDO = base_color * COLOR.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	if (abs(wnorm.y) < 0.3 && COLOR.a > 0.01 && wpos.y > 1.0) {
		vec2 g = vec2(dot(wpos.xz, vec2(wnorm.z, -wnorm.x)), wpos.y - 1.0);
		vec2 grid = vec2(2.7, 3.2);
		vec2 c = floor(g / grid);
		vec2 f = fract(g / grid);
		float win = step(0.32, f.x) * step(f.x, 0.68) * step(0.25, f.y) * step(f.y, 0.75);
		float lit = step(1.0 - window_density * COLOR.a, hash(c + floor(wpos.xz * 0.013) * 17.0));
		EMISSION = window_color * win * lit * window_energy;
	}
}
