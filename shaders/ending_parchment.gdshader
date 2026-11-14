shader_type canvas_item;
render_mode unshaded;

float grain(vec2 pixel) {
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	float fleck = (grain(pixel) - 0.5) * 0.028;
	float fibre = (grain(floor(pixel / vec2(3.0, 2.0))) - 0.5) * 0.016;
	float edge = smoothstep(0.08, 0.48, dot(UV - 0.5, UV - 0.5));
	vec3 paper = mix(vec3(0.98, 0.95, 0.87), vec3(0.89, 0.82, 0.70), edge * 0.58);
	COLOR = vec4(paper + fleck + fibre, COLOR.a);
}
