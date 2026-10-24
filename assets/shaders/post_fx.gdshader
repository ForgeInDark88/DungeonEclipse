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
uniform float outline_strength : hint_range(0.0, 1.0) = 0.35;
uniform float outline_scale : hint_range(1.0, 6.0) = 3.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint.rgb;
	float n = texture(noise_tex, UV * vec2(1.6, 0.9) + TIME * fog_speed).r;
	float n2 = texture(noise_tex, UV * vec2(0.8, 0.5) - TIME * fog_speed * 0.6).r;
	c = mix(c, fog_color.rgb, clamp(fog_amount * (n + n2) * (0.5 + 0.5 * UV.y), 0.0, 1.0));
	// Pixel outline: darken pixels whose game-pixel neighbours differ in
	// brightness - every sprite gets a crisp hand-drawn rim.
	vec2 px = SCREEN_PIXEL_SIZE * outline_scale;
	vec3 w = vec3(0.299, 0.587, 0.114);
	float l0 = dot(c, w);
	float l1 = dot(texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb, w);
	float l2 = dot(texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb, w);
	float l3 = dot(texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb, w);
	float l4 = dot(texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb, w);
	float edge = clamp(max(abs(l0 - l1), max(abs(l0 - l2), max(abs(l0 - l3), abs(l0 - l4)))) * 3.0 - 0.12, 0.0, 1.0);
	c *= 1.0 - outline_strength * edge;
	// Gentle vignette pulling the view toward the centre of the light.
	float vig = smoothstep(0.9, 0.35, length(UV - vec2(0.5)));
	c *= 1.0 - vignette_strength * (1.0 - vig);
	c *= brightness;
	COLOR = vec4(c, 1.0);
}
