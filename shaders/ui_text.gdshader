shader_type canvas_item;
render_mode unshaded;

varying vec4 ink;

void vertex() {
	ink = COLOR;
}

void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	float grain = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	float wash = smoothstep(0.18, 0.75, dot(ink.rgb, vec3(0.24, 0.62, 0.14)));
	vec3 aged = ink.rgb * mix(vec3(1.0), vec3(1.0, 0.974, 0.916), wash * 0.55);
	aged *= 0.96 + 0.08 * grain;
	float coverage = texture(TEXTURE, UV).a;
	coverage = mix(coverage, smoothstep(0.10, 0.88, coverage), 0.24);
	// Keep the softened glyph edge and the crisp, offset theme shadow.
	COLOR = vec4(aged, ink.a * coverage);
}
