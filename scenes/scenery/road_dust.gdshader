shader_type spatial;

// The dusty path of a prehistoric run (see Scenery): patches of dust over the
// earth (or the ice, or the floor of the cave), small stones, and two worn
// tracks along it, flat-shaded as the rest of the world. It scrolls with the
// run (`scroll`, in meters), so that the path rolls towards the player.

render_mode specular_disabled;

uniform vec4 base : source_color = vec4(0.48, 0.35, 0.21, 1.0);
uniform vec4 dust : source_color = vec4(0.66, 0.53, 0.36, 1.0);
uniform vec4 stone : source_color = vec4(0.32, 0.27, 0.22, 1.0);
uniform float scroll = 0.0;
// How far apart the two worn tracks are from the middle, in meters.
uniform float tracks = 0.9;

varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
        u.y);
}

void fragment() {
    vec2 p = vec2(world.x, world.z - scroll);
    // Patches of dust, large and small.
    float patches = noise(p * 0.8) * 0.55 + noise(p * 2.7) * 0.3 + noise(p * 9.0) * 0.15;
    vec3 color = mix(base.rgb, dust.rgb, smoothstep(0.35, 0.75, patches));
    // The worn tracks, darker, wavering a little.
    float wobble = (noise(vec2(0.0, p.y * 0.3)) - 0.5) * 0.3;
    float track = min(abs(p.x - tracks + wobble), abs(p.x + tracks + wobble));
    color = mix(color, base.rgb * 0.8, smoothstep(0.25, 0.05, track) * 0.6);
    // Small stones: a few cells of a fine grid, darker.
    vec2 cell = floor(p * 6.0);
    float pebble = step(0.93, hash(cell)) * smoothstep(0.45, 0.2, length(fract(p * 6.0) - 0.5));
    color = mix(color, stone.rgb, pebble);
    NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    ALBEDO = color;
    ROUGHNESS = 1.0;
}
