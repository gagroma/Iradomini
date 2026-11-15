shader_type spatial;
render_mode specular_disabled;

// PSX-STYLE SURFACE (walls, floor, pews).
// Inspiration: the well-known "PS1 shader" trick. The first PlayStation had no
// sub-pixel precision, so every corner of every polygon snapped to whole pixels
// and the world wobbled slightly as the camera moved. We copy that on purpose.
// The texture is laid out from world position, so boxes need no UV work.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tex_scale = 0.5;                  // texture repeats per metre
uniform vec2 snap_res = vec2(3840.0, 2160.0);      // smaller numbers = stronger wobble

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (clip.w > 0.01) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_res + 0.5) / snap_res;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 n = abs(normalize(world_nrm));
	vec2 uv = world_pos.xz;
	if (n.x > n.y && n.x > n.z) {
		uv = world_pos.zy;
	} else if (n.z > n.y) {
		uv = world_pos.xy;
	}
	vec3 c = texture(tex, uv * tex_scale).rgb;
	ALBEDO = c * tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
