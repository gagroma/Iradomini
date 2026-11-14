shader_type canvas_item;

uniform vec2 point = vec2(0.5);
uniform float cover = 0.0;
uniform float ember = 0.0;
uniform float reveal = 0.0;

void fragment() {
	vec2 delta = (floor(UV / SCREEN_PIXEL_SIZE) - floor(point / SCREEN_PIXEL_SIZE));
	float tick = floor(TIME * 24.0) / 24.0;
	float flicker = 0.92 + 0.08 * sin(tick * 31.0);
	float flame = length(vec2((delta.x + delta.y * 0.16) / 1.8, (delta.y + 1.2) / 3.7));
	float core = 1.0 - smoothstep(0.36, 1.0, flame);
	float halo = exp(-length(delta * vec2(1.0, 0.86)) * 0.17) * 0.55;
	float heat = max(core, halo) * ember * flicker;
	// Through the cut, the same ember is the only bright point in the frame.
	vec3 color = mix(vec3(0.017, 0.008, 0.010), mix(vec3(0.97, 0.19, 0.027), vec3(1.0, 0.91, 0.65), core), heat);
	float aspect = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	float distance_from_wick = length((UV - point) * vec2(1.0, aspect));
	float radius = mix(-0.18, length(vec2(1.0, aspect)) + 0.16, reveal);
	float veil = cover * smoothstep(radius - 0.12, radius + 0.12, distance_from_wick);
	COLOR = vec4(color, veil + (1.0 - veil) * heat);
}
