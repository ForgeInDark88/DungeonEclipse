shader_type canvas_item;
// Biome color grading + light drifting fog + the brightness setting over the
// game world (the HUD is drawn above it and is not affected). No vignette:
// the dungeon is evenly lit.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D noise_tex : repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float brightness = 1.0;
uniform vec4 fog_color : source_color = vec4(0.5, 0.5, 0.6, 1.0);
uniform float fog_amount = 0.08;
uniform vec2 fog_speed = vec2(0.012, 0.004);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint.rgb;
	float n = texture(noise_tex, UV * vec2(1.6, 0.9) + TIME * fog_speed).r;
	float n2 = texture(noise_tex, UV * vec2(0.8, 0.5) - TIME * fog_speed * 0.6).r;
	c = mix(c, fog_color.rgb, clamp(fog_amount * (n + n2) * (0.5 + 0.5 * UV.y), 0.0, 1.0));
	c *= brightness;
	COLOR = vec4(c, 1.0);
}
