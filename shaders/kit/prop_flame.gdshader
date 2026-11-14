// Small flickering candle flame. Bright HDR emission so the Environment's glow blooms it.
shader_type spatial;
render_mode shadows_disabled, cull_disabled;

#include "res://shaders/kit/noise.gdshaderinc"

uniform vec3 flame_color : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 core_color : source_color = vec3(1.0, 0.9, 0.6);
uniform float energy = 6.0;

void vertex() {
	float seed = hash31(floor(MODEL_MATRIX[3].xyz * 31.0));
	float t = TIME * (7.0 + seed * 4.0) + seed * 50.0;
	float flick = 0.85 + 0.15 * sin(t) * sin(t * 1.7 + 1.3);
	float up = clamp(VERTEX.y * 10.0 + 0.5, 0.0, 1.0);
	VERTEX.y *= flick;
	VERTEX.x += sin(t * 0.7) * 0.006 * up;
}

void fragment() {
	float core = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = mix(flame_color, core_color, core * core) * energy;
}
