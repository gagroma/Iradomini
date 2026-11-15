shader_type spatial;
render_mode specular_schlick_ggx;

// PAINTING - an old painting on a church wall (textures from assets/art/,
// public-domain works, see assets/art/CREDITS.md).
// Centuries of varnish make it warmer and darker, grime gathers along the
// edges under the frame, and the varnish catches a little candlelight.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform float age = 0.6;            // 0 = clean, 1 = very old varnish

// Pulled a little towards the camera so the wobbling (PSX-snapped) wall
// behind cannot cut into it; see decor.gdshader.
const float PULL = 0.0045;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// the wall's depth error grows as 1/sin of the viewing angle, so the pull does too
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = max(abs(dot(normalize(v.xyz), vn)), 0.15);
	v.xyz *= 1.0 - PULL / facing;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	c = mix(c, c * vec3(0.95, 0.84, 0.6), age * 0.55);
	vec2 e = min(UV, 1.0 - UV);
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.07, min(e.x, e.y)));
	ALBEDO = c;
	ROUGHNESS = 0.42;
	SPECULAR = 0.35;
}
