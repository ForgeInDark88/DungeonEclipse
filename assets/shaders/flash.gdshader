shader_type canvas_item;
// The sprite shader of monsters and highlighted objects (AssetPaths.flash_material):
//  - hit flash: `flash` 0..1 toward `flash_color` (as before);
//  - pixel outline: `outline_width` whole texture pixels of `outline_color`
//    around the opaque shape (elites in their affix colour, the object the hero
//    can use); alpha 0 = no outline;
//  - dissolve: `dissolve` 0..1 eats the sprite pixel by pixel (death), the
//    pixels about to go glow in `dissolve_edge`.
// All off by default: a plain material looks exactly like before.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float outline_width : hint_range(0.0, 3.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(1.0, 0.8, 0.4, 1.0);

float pixel_noise(vec2 uv, vec2 px) {
	vec2 cell = floor(uv / px);
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 rgb = mix(c.rgb, flash_color.rgb, flash);
	float a = c.a;
	if (a < 0.1 && outline_color.a > 0.0 && outline_width > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float n = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (n > 0.1) {
			rgb = outline_color.rgb;
			a = outline_color.a;
		}
	}
	if (dissolve > 0.0) {
		float k = pixel_noise(UV, TEXTURE_PIXEL_SIZE);
		if (k < dissolve) {
			a = 0.0;
		} else if (k < dissolve + 0.12 && a > 0.1) {
			rgb = dissolve_edge.rgb;
		}
	}
	COLOR = vec4(rgb, a);
}
