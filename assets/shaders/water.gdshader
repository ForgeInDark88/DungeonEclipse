shader_type canvas_item;
// Water of a pond (DungeonLevel._spawn_water): a body that darkens with
// depth, a moving surface line with a lit crest, slow light bands under the
// surface, sparkles, rain rings when it rains, and ripples where something
// broke the surface (`ripple_*`, set by the level on a splash).
uniform vec4 shallow : source_color = vec4(0.32, 0.56, 0.78, 0.62);
uniform vec4 deep : source_color = vec4(0.10, 0.22, 0.40, 0.86);
uniform vec2 size = vec2(64.0, 32.0);   // px
uniform float rain = 0.0;               // 0..1
uniform vec3 ripple = vec3(0.0, 0.0, 9.0);  // x (px), unused, age (s; set by a tween)
uniform float seed = 0.0;
uniform float glow = 0.0;               // underground: glimmers drifting in the deep

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 px = floor(UV * size);           // whole pixels: crisp pixel art
	float t = TIME;
	// the surface: a gentle 1 px wave
	float wave = floor(sin(px.x * 0.35 + t * 1.6 + seed) * 0.6 + sin(px.x * 0.13 - t * 0.9) * 0.6 + 0.5);
	float surf = 2.0 + wave;
	if (px.y < surf - 1.0) { discard; }
	float depth = clamp((px.y - surf) / max(8.0, size.y - surf), 0.0, 1.0);
	vec4 c = mix(shallow, deep, depth * depth * 0.9 + depth * 0.1);
	// light bands drifting under the surface
	float band = sin(px.x * 0.18 + px.y * 0.5 - t * 0.8 + seed) * sin(px.x * 0.07 - t * 0.35);
	if (band > 0.72 && depth < 0.6) { c.rgb += 0.06; }
	// underground: specks of fungus light drifting slowly up through the water
	if (glow > 0.0) {
		vec2 cell = floor(vec2(px.x / 5.0, (px.y + t * 3.0) / 5.0));
		float h = hash(cell + seed);
		if (h > 0.93 && mod(px.x, 5.0) == 2.0 && mod(floor(px.y + t * 3.0), 5.0) == 2.0) {
			float tw = 0.5 + 0.5 * sin(t * 2.0 + h * 40.0);
			c.rgb = mix(c.rgb, vec3(0.45, 1.0, 0.85), 0.55 * tw * glow);
		}
		if (band > 0.6) { c.rgb += vec3(0.0, 0.05, 0.05) * glow; }
	}
	// the crest: a lit line and a darker line under it
	if (px.y < surf) { c = vec4(mix(shallow.rgb, vec3(0.95, 1.0, 1.0), 0.55), 0.95); }
	else if (px.y < surf + 1.0) { c.rgb = mix(c.rgb, vec3(0.85, 0.95, 1.0), 0.25); }
	// sparkles on the crest and just below
	float sp = hash(vec2(px.x, floor(t * 2.0 + px.x * 0.37)));
	if (px.y < surf + 2.0 && sp > 0.985) { c = vec4(1.0, 1.0, 1.0, 0.95); }
	// rain: little rings on the surface
	if (rain > 0.0 && px.y < surf + 2.0) {
		float cell = floor(px.x / 9.0);
		float phase = fract(t * 0.9 + hash(vec2(cell, seed)));
		float cx = cell * 9.0 + 4.0 + floor(hash(vec2(cell, 7.0)) * 3.0);
		float r = phase * 4.0;
		if (abs(abs(px.x - cx) - r) < 0.6 && hash(vec2(cell, 3.0)) < rain) { c.rgb += 0.25 * (1.0 - phase); }
	}
	// a ripple running out from where something broke the surface
	float age = ripple.z;
	if (age >= 0.0 && age < 1.6 && px.y < surf + 3.0) {
		float r = age * 22.0;
		if (abs(abs(px.x - ripple.x) - r) < 1.0) { c.rgb += 0.3 * (1.0 - age / 1.6); }
	}
	COLOR = c;
}
