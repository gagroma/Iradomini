shader_type spatial;
render_mode specular_schlick_ggx;

// PSX-STYLE MODEL (models made in Blender, like the pews).
// Same vertex wobble as psx.gdshader, so models sit in the world the same
// way the walls do, but the texture follows the model's own UVs (the wood
// grain runs along each plank) instead of being laid out from world space.
// Vertex colours come baked from Blender:
//   R = ambient occlusion (dark in corners, under the seat, near the floor)
//   G = wear (polished, lighter wood where hands and people touch it)

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ao_strength = 1.0;
uniform float wear_strength = 1.0;
uniform float roughness = 0.72;
uniform vec2 snap_res = vec2(160.0, 90.0);      // smaller numbers = stronger wobble

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (clip.w > 0.01) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_res + 0.5) / snap_res;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb * tint.rgb;
	float ao = mix(1.0, clamp(COLOR.r * 1.15, 0.3, 1.0), ao_strength);
	float wear = COLOR.g * wear_strength;
	c *= 1.0 + 0.3 * wear;
	ALBEDO = c * ao;
	ROUGHNESS = mix(roughness, 0.38, wear);
	SPECULAR = 0.4 * ao;
	METALLIC = 0.0;
}
