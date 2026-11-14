shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float burn_front = -1.0;

float hash(float n) {
	return fract(sin(n * 91.73) * 21843.17);
}

float noise(float n) {
	float cell = floor(n);
	return mix(hash(cell), hash(cell + 1.0), smoothstep(0.0, 1.0, fract(n)));
}

void fragment() {
	// UV.x goes around the ring. Both fronts start at the near edge.
	float around = (1.0 - abs(2.0 * UV.x - 1.0));
	float distance_to_front = around - burn_front;
	float wake = smoothstep(-0.21, -0.025, distance_to_front)
		* (1.0 - smoothstep(0.015, 0.065, distance_to_front));
	float end = 1.0 - smoothstep(0.97, 1.08, burn_front);

	// Quantize the noise so each tongue of flame fits the game's pixel art.
	float along = floor(UV.x * 420.0) / 420.0;
	float height = floor(UV.y * 40.0) / 40.0;
	float tick = floor(TIME * 24.0) / 24.0;
	float flicker = noise(along * 340.0 + tick * 14.0);
	float tongues = noise(along * 170.0 - height * 8.0 + tick * 11.0);
	float tip = wake * (0.21 + 0.58 * tongues + 0.18 * flicker);
	float silhouette = 1.0 - smoothstep(tip - 0.07, tip, height);
	float base = wake * (1.0 - smoothstep(0.025, 0.14, height));
	float core = (1.0 - smoothstep(0.04, 0.53, height)) * (0.45 + 0.55 * flicker);

	ALBEDO = mix(vec3(0.94, 0.13, 0.018), vec3(1.0, 0.88, 0.48), core);
	ALPHA = end * max(base * 0.75, silhouette * wake * (0.65 + 0.30 * tongues));
}
