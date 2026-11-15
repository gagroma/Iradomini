shader_type canvas_item;

uniform vec2 page_size = vec2(204.0, 214.0);
uniform float side = 1.0;
uniform float shade = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 px = UV * page_size;
	float from_spine = side > 0.0 ? px.x : page_size.x - px.x;
	float outer = page_size.x - from_spine;
	float edge_y = min(px.y, page_size.y - px.y);

	float tone = vnoise(px * 0.05) * 0.55 + vnoise(px * 0.2) * 0.3 + vnoise(px * 0.9) * 0.15;
	vec3 paper = mix(vec3(0.82, 0.75, 0.6), vec3(0.87, 0.81, 0.66), tone);
	float fiber = vnoise(vec2(px.x * 2.5, px.y * 0.4)) - 0.5;
	paper += fiber * 0.025;
	float fox = smoothstep(0.7, 0.95, vnoise(px * 0.045 + 3.1));
	paper = mix(paper, vec3(0.7, 0.58, 0.41), fox * 0.18);

	float gutter = exp(-from_spine / 10.0);
	paper *= 1.0 - gutter * 0.45;
	float curl = smoothstep(26.0, 0.0, from_spine) * 0.08;
	paper *= 1.0 - curl;
	float rim = smoothstep(7.0, 0.0, min(outer, edge_y));
	paper = mix(paper, vec3(0.6, 0.5, 0.35), rim * 0.35);

	paper *= 1.0 - shade;
	COLOR = vec4(paper, 1.0);
}
