shader_type spatial;

#include "res://shaders/kit/noise.gdshaderinc"

uniform vec2 road_start = vec2(0.0);
uniform vec2 road_dir = vec2(0.0, 1.0);
uniform float road_half = 1.2;
uniform float road_length = 22.0;
uniform float texels_per_meter = 48.0;

varying vec3 world_pos;

vec3 cobble(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = 0.5 + 0.35 * (vec2(hash21(n + g), hash21(n + g + vec2(31.7, 11.3))) - 0.5);
			float d = length((g + o - f) * vec2(1.0, 1.25));
			if (d < f1) { f2 = f1; f1 = d; id = n + g; }
			else if (d < f2) { f2 = d; }
		}
	}
	return vec3(f1, f2 - f1, hash21(id * 1.37 + 4.1));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 sp = texel_snap(world_pos.xz, texels_per_meter);
	vec2 rel = sp - road_start;
	vec2 side_dir = vec2(-road_dir.y, road_dir.x);
	float along = dot(rel, road_dir);
	float across = dot(rel, side_dir);
	vec2 ruv = vec2(across, along);

	float g1 = fbm(sp * 1.3);
	float g2 = fbm(sp * 7.0 + 3.1);
	vec3 dirt = mix(vec3(0.06, 0.05, 0.04), vec3(0.11, 0.09, 0.065), g1);
	vec3 grass = mix(vec3(0.04, 0.055, 0.03), vec3(0.08, 0.1, 0.05), g2);
	vec3 ground = mix(dirt, grass, smoothstep(0.4, 0.62, fbm(sp * 0.6 + 9.0) + g2 * 0.25));
	ground *= 0.8 + 0.4 * vnoise(sp * 23.0);

	float edge = road_half + (fbm(vec2(along * 1.7, sign(across) * 5.0)) - 0.5) * 0.5;
	float fade_end = smoothstep(road_length, road_length - 4.0, along) * step(-0.1, along);
	float on_road = (1.0 - smoothstep(edge - 0.08, edge + 0.08, abs(across))) * fade_end;
	float missing = smoothstep(0.62, 0.7, fbm(sp * 2.2 + 1.7)) * (0.4 + 0.6 * smoothstep(edge - 0.6, edge, abs(across)));
	on_road *= 1.0 - missing;

	vec3 c = cobble(ruv * vec2(6.2, 5.0));
	float stone = smoothstep(0.03, 0.09, c.y);
	vec3 rock = mix(vec3(0.12, 0.11, 0.1), vec3(0.24, 0.22, 0.2), c.z);
	rock *= 0.75 + 0.45 * fbm(sp * 9.0);
	rock = mix(rock, rock * 0.55, smoothstep(0.25, 0.55, c.x));
	float moss = smoothstep(0.55, 0.75, fbm(sp * 3.0 + 5.0)) * (1.0 - stone);
	vec3 joint = mix(vec3(0.02, 0.018, 0.015), vec3(0.03, 0.045, 0.02), moss);
	vec3 road = mix(joint, rock, stone);
	float wet = smoothstep(0.45, 0.7, fbm(sp * 0.9 + 2.0));

	ALBEDO = mix(ground, road, on_road);
	ROUGHNESS = mix(0.95, mix(0.62, 0.32, wet * stone), on_road);
	SPECULAR = mix(0.3, 0.5, on_road);
	float height = mix(g2 * 0.3, stone * (1.0 - c.x * 0.8), on_road);
	NORMAL = bump_normal(NORMAL, VERTEX, height, 0.012);
}
