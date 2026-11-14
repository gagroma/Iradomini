shader_type canvas_item;
render_mode unshaded;

uniform float floor_amount = 0.0;
uniform float interact_amount = 0.0;
uniform float erase_progress = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.11369));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
	           mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 24.0;
	float distance_to_center = length(p);
	float angle = atan(p.y, p.x + 0.0001);
	float t = TIME;
	vec2 swirl = vec2(cos(angle + t * 0.30), sin(angle + t * 0.30));
	float cloud = noise(swirl * 5.7 + vec2(t * 0.22, 11.0));
	float lumps = noise(p * 0.91 + swirl * 0.65);
	float grain = hash(floor(p * 1.85));

	float erasing = smoothstep(0.0, 0.09, erase_progress);
	float radius = mix(7.45 + sin(t * 2.0) * 0.27, 4.0, erase_progress);
	float fractured = (cloud - 0.5) * 2.85 + (lumps - 0.5) * 1.85;
	float band = abs(distance_to_center - radius + fractured);
	float breaks = smoothstep(0.21, 0.68, cloud * 0.66 + lumps * 0.34);
	float dust = (1.0 - smoothstep(0.10, 0.74 + cloud * 0.75, band)) * breaks;
	float haze = exp(-band * band * 0.39) * smoothstep(0.38, 0.92, grain) * breaks * 0.55;
	float clockwise = fract((angle + 1.5707963) / 6.2831853 + 1.0);
	float fill = step(clockwise, erase_progress) * erasing;
	float ring = (dust * mix(0.84, 1.0, fill) + haze) * floor_amount * (1.0 - interact_amount);

	vec3 ash = vec3(0.87, 0.87, 0.82);
	vec3 crimson = mix(vec3(0.64, 0.47, 0.45), vec3(1.0, 0.71, 0.68), fill);
	vec3 ring_color = mix(ash, crimson, erasing);
	float active = max(floor_amount, interact_amount);
	float core_radius = mix(mix(0.95, 1.21, active), 1.63, interact_amount);
	float core = 1.0 - smoothstep(0.10, core_radius, distance_to_center);
	float glow = exp(-distance_to_center * distance_to_center * mix(0.63, 0.52, interact_amount)) * mix(0.14, 0.44, active);
	float dot_amount = (core * mix(0.50, 0.96, active) + glow) * (1.0 - erasing * 0.18);
	vec3 dot_color = mix(vec3(1.0, 0.99, 0.95), vec3(1.0, 0.77, 0.39), interact_amount);
	vec3 ink = mix(ring_color, dot_color, clamp(dot_amount / max(ring + dot_amount, 0.001), 0.0, 1.0));
	float shadow = max((1.0 - smoothstep(0.83, 2.4, distance_to_center)) * mix(0.24, 0.58, interact_amount), haze * floor_amount * 0.21);
	float light = clamp(ring + dot_amount, 0.0, 1.0);
	float alpha = max(light, shadow);
	COLOR = vec4(ink * light / max(alpha, 0.001), alpha);
}
