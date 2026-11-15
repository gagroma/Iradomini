shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec2 quad_size = vec2(0.8, 0.9);
uniform float arch_radius = 0.26;
uniform float spring = 0.42;
uniform float thickness = 0.018;
uniform float strength = 1.0;
uniform float seed = 0.0;
uniform bool floor_ring = false;

void vertex() {
	if (!floor_ring) {
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
		vec3 fwd = normalize(cross(side, up));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	}
}

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7) + seed);
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 fire(float heat) {
	vec3 c = mix(vec3(0.55, 0.07, 0.01), vec3(1.0, 0.42, 0.06), smoothstep(0.0, 0.5, heat));
	return mix(c, vec3(1.0, 0.86, 0.5), smoothstep(0.55, 1.0, heat));
}

void fragment() {
	float t = TIME * 1.0 + seed * 10.0;
	vec3 col = vec3(0.0);
	if (floor_ring) {
		vec2 p = (UV - 0.5) * quad_size;
		float r = length(p);
		float a = atan(p.y, p.x);
		float flick = noise(vec2(a * 4.0, t * 2.5)) * 0.6 + noise(vec2(a * 11.0, t * 4.0)) * 0.4;
		float ring = exp(-abs(r - arch_radius) / (thickness * (0.7 + flick)));
		float glow = exp(-r / (arch_radius * 0.6)) * 0.25;
		float heat = ring * (0.5 + 0.6 * flick);
		col = fire(clamp(heat, 0.0, 1.0)) * (heat * 1.2 + glow);
	} else {
		vec2 p = vec2((UV.x - 0.5) * quad_size.x, (1.0 - UV.y) * quad_size.y);
		float d;
		float along;
		if (p.y < spring) {
			d = abs(abs(p.x) - arch_radius);
			along = p.y;
		} else {
			vec2 q = p - vec2(0.0, spring);
			d = abs(length(q) - arch_radius);
			along = spring + atan(abs(q.x), q.y) * arch_radius;
		}
		float lick = noise(vec2(along * 18.0 - t * 5.0, sign(p.x) * 3.0 + seed));
		float tongue = noise(vec2(p.x * 22.0, p.y * 9.0 - t * 3.2));
		float signed_out = p.y > spring ? length(p - vec2(0.0, spring)) - arch_radius : abs(p.x) - arch_radius;
		float outward = max(0.0, signed_out);
		float w = thickness * (0.8 + 0.9 * lick);
		float core = exp(-d / w);
		float flame = exp(-outward / (thickness * (1.5 + 3.0 * tongue))) * smoothstep(0.0, 0.01, signed_out) * tongue * 0.9;
		float heat = clamp(core * (0.65 + 0.5 * lick) + flame * 0.6, 0.0, 1.0);
		float base = smoothstep(0.0, 0.08, p.y);
		float pulse = 0.85 + 0.15 * sin(t * 2.3);
		col = fire(heat) * heat * base * pulse * 1.6;
		col += vec3(1.0, 0.5, 0.15) * exp(-d / 0.09) * 0.12 * base;
	}
	ALBEDO = col * strength;
}
