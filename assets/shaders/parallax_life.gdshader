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
// the hour (SurfaceSky): night 0..1, the tint of dawn / evening, the stars
// and the moon on the sky, slow shafts of light through the land by day
uniform bool is_sky = false;
uniform float night = 0.0;
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform sampler2D stars : repeat_enable, filter_nearest;
uniform bool has_stars = false;
uniform vec2 moon = vec2(0.74, 0.22);
uniform float rays = 0.0;
uniform float life = 1.0;  // Settings → «Живость мира» (0, 0.5, 1)
// underground: what glows (candles, fungus, lava, crystals, runes) breathes
uniform sampler2D glow_mask : filter_nearest;
uniform bool has_glow = false;

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
	c.rgb *= mix(vec3(1.0), sky_tint.rgb, is_sky ? 1.0 : 0.6);
	if (is_sky) {
		vec3 night_col = mix(vec3(0.04, 0.06, 0.15), vec3(0.11, 0.14, 0.27), UV.y);
		c.rgb = mix(c.rgb, night_col, night * 0.93);
		if (has_stars && night > 0.01) {
			vec4 st = texture(stars, vec2(fract(UV.x + TIME * 0.0004), UV.y));
			float tw = 0.65 + 0.35 * sin(TIME * 2.3 + floor(UV.x * tex_size.x) * 1.7 + floor(UV.y * tex_size.y) * 3.1);
			c.rgb += st.rgb * st.a * night * tw;
		}
		vec2 d = (UV - moon) * tex_size;
		float r = length(d);
		if (r < 5.5) {
			vec3 mc = vec3(0.93, 0.94, 0.86);
			if (d.x > 2.0 && d.y > -1.0) { mc *= 0.86; }  // the shaded limb
			if (length(d - vec2(-1.5, -1.0)) < 1.2 || length(d - vec2(1.0, 2.0)) < 0.9) { mc *= 0.88; }  // craters
			c.rgb = mix(c.rgb, mc, night);
		} else if (r < 16.0) {
			c.rgb += vec3(0.07, 0.08, 0.11) * night * (1.0 - r / 16.0);
		}
	} else {
		c.rgb = mix(c.rgb, c.rgb * vec3(0.3, 0.36, 0.6), night);
	}
	if (rays * life > 0.0 && !is_sky) {
		float b = fract(UV.x * 2.6 + UV.y * 1.3 + sin(TIME * 0.05) * 0.15);
		float ray = smoothstep(0.0, 0.06, b) * smoothstep(0.2, 0.08, b);
		c.rgb += vec3(1.0, 0.95, 0.75) * ray * rays * life * (1.0 - UV.y * 0.6) * c.a;
	}
	if (has_glow && texture(glow_mask, UV).a > 0.5) {
		float br = 0.5 + 0.5 * sin(TIME * 1.3 + UV.x * 31.0 + UV.y * 17.0);
		c.rgb *= 1.08 + 0.22 * br * max(life, 0.25);
	}
	if (shimmer * life > 0.0) {
		float band = 0.5 + 0.5 * sin(TIME * 0.25 + UV.x * 5.0 - UV.y * 2.0);
		c.rgb *= 1.0 + shimmer * life * (band * band - 0.35);
	}
	COLOR = c * COLOR;
}
