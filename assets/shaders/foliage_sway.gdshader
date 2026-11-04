shader_type canvas_item;
// Trees, bushes and reeds bend a little in the wind: the top of the sprite
// leans by up to `amount` px and back, the base stays put. Each plant has
// its own phase from its place in the world (one shared material).
uniform float amount = 1.2;
uniform float speed = 0.8;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	// VERTEX.y is negative above the base (the sprites stand on their offset)
	float height = clamp(-VERTEX.y / 80.0, 0.0, 1.0);
	float gust = sin(TIME * speed + world.x * 0.031) * 0.7 + sin(TIME * speed * 1.9 + world.x * 0.07) * 0.3;
	VERTEX.x += gust * amount * height;  // a shear: the base vertices stay
}
