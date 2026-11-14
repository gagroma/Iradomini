shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// CANDLE FLAME - the flame of the candle in your hand.
// The mesh is only an invisible box around the wick. For every pixel of the
// box a ray walks through it and adds up the light of a glowing gas, so the
// flame has real depth from any angle (looking down at it while drawing chalk
// too). The box never turns: candle.gd keeps it upright in the world,
// because a flame always burns upwards, whatever the hand does.
//
// What a real candle flame looks like, and what is copied here:
//  - a teardrop, widest about a third of the way up;
//  - a dark zone of wax vapour around the wick, a small blue skirt at the
//    bottom, a white-yellow body, an orange-red tip;
//  - it sways a little in still air and leans away from the way it moves;
//  - in wind it stretches, gets ragged, and tongues tear off its tip.
// candle.gd drives "lean", "size" and "turbulence" from how the candle
// moves, how close the demon is, and how much wax is left.

uniform vec3 wick_offset = vec3(0.0, -0.025, 0.0);  // flame base, from the box centre
uniform vec3 box_half = vec3(0.05, 0.05, 0.05);     // half the size of the box mesh
uniform float height = 0.03;       // metres, a calm full flame
uniform float radius = 0.0058;     // metres, at the widest point
uniform vec2 lean = vec2(0.0);     // tip bend in world x/z, in flame heights
uniform float size : hint_range(0.0, 1.5) = 1.0;
uniform float turbulence : hint_range(0.0, 2.5) = 0.15;
uniform float brightness = 1.0;
uniform float seed = 0.0;

const int STEPS = 32;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float g = hash13(i + vec3(1.0, 0.0, 1.0));
	float h = hash13(i + vec3(0.0, 1.0, 1.0));
	float k = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
	           mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

// Light given off by the gas at point p (metres, from the flame base).
vec3 flame(vec3 p, float t, vec2 sway, float H) {
	float h = p.y / H;                       // 0 at the base, 1 at the tip
	if (h < -0.35 || h > 1.7) {
		return vec3(0.0);
	}
	float hc = clamp(h, 0.0, 1.6);

	// gas rises, so the noise scrolls upwards; faster in wind
	vec3 q = vec3(p.x / H * 7.0, h * 3.2 - t * (2.6 + 5.0 * turbulence), p.z / H * 7.0);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.03 + 7.1) * 0.35;

	// the axis bends: wind and a slow sway, more at the top than the bottom
	vec2 bend = lean + sway;
	bend += (vec2(vnoise(q + 11.0), vnoise(q + 23.0)) - 0.5) * turbulence * 0.45;
	vec2 axis = bend * H * hc * hc;
	float r = length(p.xz - axis);

	// teardrop profile, widest at 40% of the height
	float s = clamp((h + 0.12) / 1.12, 0.0, 1.0);
	float prof = 2.32 * sqrt(s) * pow(1.0 - s, 0.75);
	float R = radius * mix(1.0, size, 0.5) * (1.0 + 0.3 * turbulence) * prof;
	R *= 1.0 + (n - 0.5) * (0.25 + 0.9 * turbulence) * s;
	if (R <= 1e-5) {
		return vec3(0.0);
	}
	float d = 1.0 - r / R;                   // 1 on the axis, 0 on the surface
	if (d < -0.4) {
		return vec3(0.0);
	}
	float body = smoothstep(0.0, 0.45, d);
	// wind tears the top into tongues that break away
	float tear = smoothstep(0.0, 0.3, n + 0.6 - s * turbulence * 0.85);
	body *= mix(1.0, tear, smoothstep(0.35, 0.75, s));

	// temperature: hot inside, cooler towards the tip
	float temp = clamp(d * 1.3, 0.0, 1.0) * (1.0 - 0.55 * smoothstep(0.5, 1.0, s));
	vec3 col = mix(vec3(0.85, 0.16, 0.02), vec3(1.0, 0.48, 0.1), smoothstep(0.0, 0.35, temp));
	col = mix(col, vec3(1.0, 0.8, 0.42), smoothstep(0.3, 0.7, temp));
	col = mix(col, vec3(1.0, 0.96, 0.86), smoothstep(0.72, 1.0, temp));
	float lum = body * (0.22 + 2.4 * temp * temp);

	// dark zone of unburnt vapour around the wick
	float dark = smoothstep(0.35, 0.9, d) * (1.0 - smoothstep(0.05, 0.32, h));
	lum *= 1.0 - 0.85 * dark;

	// blue skirt at the very bottom
	float blue = smoothstep(0.32, 0.0, h) * smoothstep(-0.3, -0.02, h)
	           * smoothstep(-0.35, 0.05, d) * (1.0 - smoothstep(0.15, 0.6, d));
	return col * lum + vec3(0.1, 0.22, 1.0) * blue * 0.7;
}

void fragment() {
	if (size <= 0.002) {
		discard;
	}
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wpos - ro);
	vec3 centre = NODE_POSITION_WORLD;
	vec3 inv = 1.0 / (rd + vec3(1e-6));
	vec3 t0 = (centre - box_half - ro) * inv;
	vec3 t1 = (centre + box_half - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float tn = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float tf = min(min(tmax.x, tmax.y), tmax.z);
	if (tf <= tn) {
		discard;
	}

	float t = TIME + seed * 17.0;
	float H = height * size * (1.0 - 0.18 * min(length(lean), 1.0));
	// slow sway of the whole flame, the same for every pixel
	vec2 sway = (vec2(vnoise(vec3(t * 1.7, seed, 0.0)), vnoise(vec3(seed, t * 1.9, 3.0))) - 0.5)
	          * (0.16 + 0.8 * turbulence);
	vec3 base = centre + wick_offset;
	// soft glow around the flame (light scattered by the air)
	vec3 glow_c = vec3((lean.x + sway.x) * H * 0.2, H * 0.38, (lean.y + sway.y) * H * 0.2);
	float glow_r = 0.004 + 0.009 * size;

	float stp = (tf - tn) / float(STEPS);
	float jitter = hash13(vec3(FRAGCOORD.xy, fract(TIME) * 97.0));
	vec3 acc = vec3(0.0);
	for (int i = 0; i < STEPS; i++) {
		vec3 p = ro + rd * (tn + (float(i) + jitter) * stp) - base;
		acc += flame(p, t, sway, H) * stp;
		vec3 e = (p - glow_c) / box_half;
		float edge = 1.0 - smoothstep(0.55, 1.0, max(max(abs(e.x), abs(e.y)), abs(e.z)));
		acc += vec3(1.0, 0.45, 0.14) * exp(-length(p - glow_c) / glow_r) * 0.22 * edge * stp;
	}
	ALBEDO = acc * brightness * 95.0;
}
