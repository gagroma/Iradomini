// Room shell kit surfaces (walls, pilasters, floors, ceilings). World-space and pixel-snapped,
// so neighbouring kit pieces join without seams. Matches the Blender preview materials in
// _tools/props/make_kit.py. Vertex COLOR carries a per-block / per-slab tone from the kit.
//   kind: 0 stone   1 plaster   2 floor flagstone   3 grout   4 wood (ceiling)
shader_type spatial;

#include "res://shaders/kit/noise.gdshaderinc"

uniform int kind = 0;
uniform float texels_per_meter = 384.0;
uniform float tone_scale = 1.0;
uniform float bump_strength = 0.0;  // bump on snapped noise gives stripes; geometry carries the relief

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float fbm_aa(vec2 p, float dp) {
	float s = 0.0;
	float a = 0.5;
	float f = 1.0;
	for (int i = 0; i < 5; i++) {
		s += a * mix(0.5, vnoise(p), 1.0 - smoothstep(0.25, 0.6, dp * f));
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
		f *= 2.03;
	}
	return s / 0.96875;
}

float keep(float dp) {
	return 1.0 - smoothstep(0.25, 0.6, dp);
}

float crack(vec2 p, float scale, float width, float amount, float px) {
	vec2 w = p + (vec2(fbm_aa(p * 3.0, px * 3.0), fbm_aa(p * 3.0 + 7.7, px * 3.0)) - 0.5) * 0.4;
	float e = voronoi(w * scale).y;
	float m = 1.0 - smoothstep(0.0, width, e);
	float thin = 1.0 - smoothstep(0.6, 1.6, px * scale / width);
	return m * thin * smoothstep(0.55 - amount * 0.1, 0.62, fbm_aa(p * 5.0 + 3.3, px * 5.0));
}

void fragment() {
	vec3 sp = texel_snap3(world_pos, texels_per_meter);
	vec2 uv = plane_uv(sp, world_normal);
	float h = sp.y;
	float px = length(fwidth(world_pos)) * 0.7;
	float tone = COLOR.r * tone_scale;
	vec3 col;
	float rough = 0.85;
	float height = 0.0;

	if (kind == 0) {            // stone
		float n = fbm_aa(uv * 4.0, px * 4.0);
		col = mix(vec3(0.085, 0.078, 0.068), vec3(0.14, 0.127, 0.11), smoothstep(0.25, 0.75, n));
		col = mix(col, vec3(0.035, 0.032, 0.03), smoothstep(0.66, 0.74, vnoise(uv * 18.0)) * 0.5 * keep(px * 18.0));
		col = mix(col, vec3(0.02, 0.018, 0.016), crack(uv, 2.5, 0.03, 0.6, px));
		float grime = (1.0 - smoothstep(0.0, 0.7, h)) * 0.85 * mix(0.4, 1.0, fbm_aa(uv * 5.0, px * 5.0));
		col = mix(col, vec3(0.035, 0.032, 0.027), grime);
		col = mix(col, vec3(0.04, 0.06, 0.025), (1.0 - smoothstep(0.0, 0.25, h)) * 0.6 * smoothstep(0.5, 0.65, fbm_aa(uv * 12.0, px * 12.0)));
		height = n;
	} else if (kind == 1) {     // plaster
		float n = fbm_aa(uv * 2.5, px * 2.5);
		col = mix(vec3(0.17, 0.155, 0.13), vec3(0.29, 0.27, 0.23), smoothstep(0.3, 0.75, n));
		float damp = (1.0 - smoothstep(1.3, 2.4, h)) * mix(0.3, 1.0, smoothstep(0.3, 0.6, fbm_aa(uv * 3.0, px * 3.0)));
		col = mix(col, vec3(0.08, 0.06, 0.035), damp);
		float drip = smoothstep(0.6, 0.72, fbm_aa(vec2(uv.x * 14.0, uv.y * 0.7), px * 14.0)) * smoothstep(2.6, 4.2, h);
		col = mix(col, vec3(0.05, 0.045, 0.035), drip);
		col = mix(col, vec3(0.04, 0.035, 0.03), crack(uv, 1.2, 0.02, 0.5, px));
		rough = 0.92;
		height = n * 0.5;
	} else if (kind == 2) {     // floor flagstones
		float n = fbm_aa(uv * 6.0, px * 6.0);
		col = mix(vec3(0.07, 0.064, 0.057), vec3(0.115, 0.106, 0.093), smoothstep(0.25, 0.75, n));
		col = mix(col, vec3(0.03, 0.028, 0.025), smoothstep(0.66, 0.74, vnoise(uv * 20.0)) * 0.4 * keep(px * 20.0));
		col = mix(col, vec3(0.015, 0.014, 0.012), crack(uv, 3.0, 0.025, 0.6, px));
		col = mix(col, vec3(0.03, 0.027, 0.022), smoothstep(0.5, 0.75, fbm_aa(uv * 2.0, px * 2.0)) * 0.55);
		rough = 0.75;
		height = n;
	} else if (kind == 3) {     // grout
		col = mix(vec3(0.012, 0.011, 0.01), vec3(0.035, 0.03, 0.025), smoothstep(0.3, 0.8, fbm_aa(uv * 8.0, px * 8.0)));
		tone = 1.0;
		rough = 0.95;
	} else {                    // wood
		float g = fbm_aa(vec2(uv.x * 3.0, uv.y * 27.0), px * 27.0);
		col = mix(vec3(0.014, 0.006, 0.003), vec3(0.07, 0.028, 0.012), smoothstep(0.2, 0.8, g));
		rough = 0.7;
		height = g * 0.6;
	}

	ALBEDO = col * tone;
	ROUGHNESS = rough;
	if (bump_strength > 0.0) {
		NORMAL = bump_normal(NORMAL, VERTEX, height, bump_strength);
	}
}
