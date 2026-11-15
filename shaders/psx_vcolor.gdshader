shader_type spatial;
render_mode specular_schlick_ggx;

// PSX VERTEX-COLOUR MODEL (the dead exorcist, the claw gouges, your hands).
// Blender bakes colour and shadow into the vertex colours
// (tools/make_exorcist.py); vertex alpha is gloss (blood, leather, beads).
// The same PS1 vertex wobble as the walls, and the same small pull towards
// the camera as wall decor (decor.gdshader), because these lie on the floor,
// which wobbles too.

uniform vec2 snap_res = vec2(3840.0, 2160.0);
uniform float roughness = 0.85;
uniform bool snap = true;                  // off for the player's own hands (they hold unsnapped things)

const float PULL = 0.002;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = max(abs(dot(normalize(v.xyz), vn)), 0.15);
	v.xyz *= 1.0 - PULL / facing;
	vec4 clip = PROJECTION_MATRIX * v;
	if (snap && clip.w > 0.01) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_res + 0.5) / snap_res;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(roughness, 0.18, COLOR.a);
	SPECULAR = mix(0.25, 0.6, COLOR.a);
	METALLIC = 0.0;
}
