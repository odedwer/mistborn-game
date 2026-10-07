shader_type spatial;
// Weathered statuary bronze (WorldMaterials.Mat.BRONZE). The verdigris is not
// a random mottle: it gathers where weathering puts it on a real statue.
//  - Recesses: the mesh's vertex colour darkens folds, the waist, under the
//    arms, the eye sockets and the mouth (1 = open surface), and the patina
//    builds up there.
//  - Ledges: faces turned up (shoulders, the head, the base plate, the
//    banner's top edge) hold rainwater and go green.
//  - Runs: on the upright faces it streaks downward from the shoulders, the
//    belt and the head, fading towards the hem, in thin vertical runs.
// Works in model space, so each statue weathers the same way relative to its
// own folds; the instance position only offsets the runs, so no two match.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 metal_color : source_color = vec3(0.3, 0.225, 0.15);
uniform vec3 patina_color : source_color = vec3(0.25, 0.34, 0.29);
uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform float rim_amount = 0.25;

varying vec3 lp;
varying vec3 ln;
varying float seed;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vec2 o = MODEL_MATRIX[3].xz;
	seed = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(ln);
	float cavity = smoothstep(0.86, 0.62, COLOR.r);
	float ledge = smoothstep(0.45, 0.9, n.y);
	// Runs, projected on the two upright planes and blended by the normal.
	vec2 wv = abs(n.xz) + 0.001;
	wv /= wv.x + wv.y;
	float v = lp.y * 0.34 + seed * 5.0;
	float wob = 0.03 * sin(lp.y * 9.0 + (lp.x + lp.z) * 5.0);
	float s = texture(streaks, vec2(lp.z * 2.2 + seed + wob, v)).r * wv.x
			+ texture(streaks, vec2(lp.x * 2.2 + seed * 1.7 + wob, v + 0.37)).r * wv.y;
	// Strongest just under the ledges water runs off, fading below each.
	float y = lp.y;
	float drip = max(max(
			exp(-max(1.5 - y, 0.0) / 0.5) * step(y, 1.56),
			0.8 * exp(-max(1.15 - y, 0.0) / 0.35) * step(y, 1.2)),
			0.7 * exp(-max(1.74 - y, 0.0) / 0.12) * step(y, 1.76));
	drip = max(drip, 0.15);
	float run = smoothstep(0.5, 0.8, s) * drip * (1.0 - ledge);
	float m = max(max(cavity, ledge * 0.85), run * 0.9);
	// A fine grain so the areas between aren't flat.
	float f = texture(mottle, vec2(lp.x + lp.z, lp.y) * 1.6 + seed).r;
	m = clamp(m * (0.6 + 0.8 * f), 0.0, 1.0);
	vec3 bronze = metal_color * (0.82 + 0.36 * f);
	ALBEDO = mix(bronze, patina_color * (0.9 + 0.2 * f), m) * COLOR.rgb;
	ROUGHNESS = mix(0.45, 0.88, m);
	METALLIC = 0.35 * (1.0 - 0.6 * m);
	SPECULAR = 0.5;
	// A faint rim along the silhouette picks the figure out of a dark street.
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
