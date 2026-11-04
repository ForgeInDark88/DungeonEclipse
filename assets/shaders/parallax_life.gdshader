shader_type canvas_item;
// Quiet life in the parallax backgrounds (never eye-catching):
//  - sky: the cloud layer drifts slowly over the sky (tiles in x);
//  - land: only foliage (white in `sway_mask`) sways in the wind, in whole
//    texels, slowly, by at most `sway` texels; hills and ruins stand still;
//  - dungeon: a soft band of light breathes across the layer.

uniform sampler2D clouds : repeat_enable, filter_nearest;
uniform bool has_clouds = false;
uniform float cloud_speed = 0.0025;  // layer widths per second
uniform sampler2D sway_mask : filter_nearest;
uniform bool has_sway = false;
uniform float sway = 1.0;            // texels
uniform float shimmer = 0.0;         // brightness swing (0.03 = 3%)
uniform vec2 tex_size = vec2(320.0, 180.0);

void fragment() {
	vec2 uv = UV;
	vec4 c = texture(TEXTURE, uv);
	if (has_sway) {
		// a gust travels across the layer; neighbours move together
		float g = sin(TIME * 0.7 + UV.x * 9.0) * 0.6 + sin(TIME * 1.3 + UV.x * 23.0 + UV.y * 4.0) * 0.4;
		float off = floor(g * sway + 0.5) / tex_size.x;
		vec2 suv = vec2(uv.x - off, uv.y);
		if (texture(sway_mask, suv).a > 0.5 || texture(sway_mask, uv).a > 0.5) {
			c = texture(TEXTURE, suv);
		}
	}
	if (has_clouds) {
		vec4 cl = texture(clouds, vec2(fract(UV.x + TIME * cloud_speed), UV.y));
		c.rgb = mix(c.rgb, cl.rgb, cl.a);
	}
	if (shimmer > 0.0) {
		float band = 0.5 + 0.5 * sin(TIME * 0.25 + UV.x * 5.0 - UV.y * 2.0);
		c.rgb *= 1.0 + shimmer * (band * band - 0.35);
	}
	COLOR = c * COLOR;
}
