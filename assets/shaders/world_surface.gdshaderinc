// World-space triplanar PBR surface for the generated city (streets, walls,
// roofs): albedo/normal/roughness/AO/height sets from tools/gen_textures_hd.py.
//  * Parallax occlusion mapping on the upward projection (streets, squares,
//    flat roofs), so setts and joints have real depth at grazing angles.
//  * Macro variation (large-scale tone and roughness drift) so a tiled
//    texture doesn't repeat visibly across a square.
//  * Wetness (global `world_wetness`, 0..1, set by the day/night driver):
//    darker, glossier stone, and puddles that collect in low spots and in
//    the joints, mirror-smooth for screen-space reflections of lanterns.
// Vertex colour carries the per-building tint and soot (as the old
// triplanar StandardMaterial3D did).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 tint : source_color = vec4(1.0);
uniform float world_size = 1.6;          // metres per texture tile
uniform float sharpness = 6.0;
uniform float normal_strength = 1.0;
uniform float roughness_scale = 1.0;
uniform float ao_strength = 0.8;
uniform float height_depth = 0.03;       // metres of parallax relief (0 = off)
uniform int pom_steps = 16;
uniform float macro_amount = 0.18;
uniform float puddle_amount = 1.0;       // 0 on walls/roofs that never pool
global uniform float world_wetness;
// distance fade (pixel dither, opaque pass): opaque up to fade_from metres,
// gone at fade_to; off while fade_to <= fade_from
uniform float fade_from = 0.0;
uniform float fade_to = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 pom(vec2 uv, vec3 v_ts) {
	// v_ts: view direction in the projection's tangent space (z = along the
	// surface normal). Linear search, then one secant refinement.
	float steps = float(pom_steps);
	float layer = 1.0 / steps;
	vec2 delta = v_ts.xy / max(v_ts.z, 0.15) * (height_depth / world_size) / steps;
	float depth = 0.0;
	vec2 cur = uv;
	float h = 1.0 - texture(height_tex, cur).r;
	float prev_h = h;
	vec2 prev = cur;
	for (int i = 0; i < pom_steps; i++) {
		if (depth >= h) {
			break;
		}
		prev = cur;
		prev_h = h - depth;
		cur -= delta;
		depth += layer;
		h = 1.0 - texture(height_tex, cur).r;
	}
	float after = h - depth;
	float w = after / (after - prev_h + 1e-5);
	return mix(cur, prev, clamp(w, 0.0, 1.0));
}

vec3 unpack_n(vec4 t) {
	vec3 n = t.xyz * 2.0 - 1.0;
	n.xy *= normal_strength;
	return normalize(n);
}

void fragment() {
	if (fade_to > fade_from) {
		float d = length(CAMERA_POSITION_WORLD - wpos);
		float keep = 1.0 - clamp((d - fade_from) / (fade_to - fade_from), 0.0, 1.0);
		// 4x4 Bayer threshold
		int ix = int(FRAGCOORD.x) % 4, iy = int(FRAGCOORD.y) % 4;
		const float bayer[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
		if (keep < (bayer[iy * 4 + ix] + 0.5) / 16.0) {
			discard;
		}
	}
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(sharpness));
	bw /= (bw.x + bw.y + bw.z);
	float s = 1.0 / world_size;
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - wpos);

	// projections: X (zy), Y (xz), Z (xy)
	vec2 uvx = wpos.zy * s;
	vec2 uvy = wpos.xz * s;
	vec2 uvz = wpos.xy * s;
	// parallax on the dominant projection (u, v = the projection's world
	// axes; z = along the outward normal)
	if (height_depth > 0.0) {
		if (bw.y > 0.5) {
			uvy = pom(uvy, vec3(view_w.x, view_w.z, view_w.y * sign(n.y)));
		} else if (bw.x > 0.5) {
			uvx = pom(uvx, vec3(view_w.z, view_w.y, view_w.x * sign(n.x)));
		} else if (bw.z > 0.5) {
			uvz = pom(uvz, vec3(view_w.x, view_w.y, view_w.z * sign(n.z)));
		}
	}
	vec4 cx = texture(albedo_tex, uvx), cy = texture(albedo_tex, uvy), cz = texture(albedo_tex, uvz);
	vec3 alb = cx.rgb * bw.x + cy.rgb * bw.y + cz.rgb * bw.z;
	float rough = texture(rough_tex, uvx).r * bw.x + texture(rough_tex, uvy).r * bw.y + texture(rough_tex, uvz).r * bw.z;
	float ao = texture(ao_tex, uvx).r * bw.x + texture(ao_tex, uvy).r * bw.y + texture(ao_tex, uvz).r * bw.z;
	float hgt = texture(height_tex, uvy).r * bw.y + texture(height_tex, uvx).r * bw.x + texture(height_tex, uvz).r * bw.z;

	// whiteout-blended triplanar normals, in world space
	vec3 tnx = unpack_n(texture(normal_tex, uvx));
	vec3 tny = unpack_n(texture(normal_tex, uvy));
	vec3 tnz = unpack_n(texture(normal_tex, uvz));
	vec3 axs = sign(n);
	vec3 nx = vec3(tnx.z * axs.x, tnx.y, tnx.x);
	vec3 ny = vec3(tny.x, tny.z * axs.y, tny.y);
	vec3 nz = vec3(tnz.x, tnz.y, tnz.z * axs.z);
	vec3 nw = normalize(nx * bw.x + ny * bw.y + nz * bw.z);

	// macro variation: two scales of world-space noise
	float m1 = texture(macro_noise, wpos.xz * 0.031 + wpos.y * 0.017).r;
	float m2 = texture(macro_noise, wpos.zx * 0.0073 + 0.37).r;
	float macro = (m1 * 0.6 + m2 * 0.4) - 0.5;
	alb *= 1.0 + macro * macro_amount * 2.0;
	rough = clamp(rough * roughness_scale + macro * 0.15, 0.04, 1.0);

	// wetness and puddles (upward surfaces only)
	float wet = clamp(world_wetness, 0.0, 1.0);
	float up = smoothstep(0.6, 0.95, n.y);
	float pud_field = texture(macro_noise, wpos.xz * 0.045 + 0.71).r;
	float level = mix(0.0, 0.62, wet) * puddle_amount * up;
	float pud = smoothstep(level - 0.08, level + 0.02, (1.0 - hgt) * 0.55 + pud_field * 0.6) * up * puddle_amount * wet;
	float damp = wet * mix(0.55, 1.0, up);
	alb *= mix(1.0, 0.62, damp);
	rough = mix(rough, rough * 0.45, damp);
	alb = mix(alb, alb * 0.45, pud);
	rough = mix(rough, 0.03, pud);
	nw = normalize(mix(nw, n, pud));

	ALBEDO = alb * COLOR.rgb * tint.rgb;
	ROUGHNESS = rough;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.35;
	SPECULAR = mix(0.5, 0.6, pud);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
