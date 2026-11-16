shader_type spatial;

// A hole in the road of a run (see RhythmNote), drawn on a quad lying on the
// road: an irregular pit, wider than long, its outline wobbling. Seen from
// above and ahead, the near wall hides and the far one shows: the far wall in
// the layers of the earth (or the ice of a crevasse), lit at its top and
// falling into the dark; the bottom black, darkest under the near rim. Around
// it a rim of crumbs and stones, and cracks running out into the road, which
// fade into it.

render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled;

#include "res://scenes/flat/bend.gdshaderinc"

uniform vec4 rim : source_color = vec4(0.54, 0.42, 0.27, 1.0);
uniform vec4 wall : source_color = vec4(0.48, 0.34, 0.2, 1.0);
uniform vec4 strata : source_color = vec4(0.36, 0.24, 0.13, 1.0);
uniform vec4 deep : source_color = vec4(0.03, 0.02, 0.015, 1.0);
// The size of the quad, and of the hole in it (half width, half length), in
// meters.
uniform vec2 size = vec2(5.4, 1.6);
uniform vec2 hole = vec2(2.4, 0.5);
uniform float seed = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
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

void vertex() {
    VERTEX = bent(VERTEX, MODEL_MATRIX);
}

void fragment() {
    // Meters from the middle: x across, y along the road (negative ahead).
    vec2 p = (UV - 0.5) * size;
    // The outline: a squarish ellipse, wobbling.
    float wobble = (noise(p * 2.2) - 0.5) * 0.45 + (noise(p * 7.0) - 0.5) * 0.15;
    float e = pow(abs(p.x) / hole.x, 5.0) + pow(abs(p.y) / hole.y, 2.0) + wobble;
    float v = clamp(p.y / hole.y, -1.0, 1.0);
    vec3 color;
    float alpha = 1.0;
    if (e < 1.0) {
        // Inside: the far wall shows near the far rim (v < 0), in layers,
        // lit at its top; the rest is the dark bottom, darkest near.
        float far_wall = smoothstep(0.35, 0.95, e) * smoothstep(0.25, -0.45, v);
        float layers = 0.5 + 0.5 * sin(e * 46.0 + noise(p * 3.0) * 4.0);
        vec3 wall_color = mix(wall.rgb, strata.rgb, step(0.62, layers));
        wall_color *= mix(0.45, 1.05, smoothstep(0.55, 1.0, e));
        color = mix(deep.rgb, wall_color, far_wall);
        color *= mix(1.0, 0.55, smoothstep(0.0, 0.9, v) * smoothstep(0.5, 1.0, e));
    } else {
        // The rim, of crumbs and stones, then the cracks into the road.
        float out_e = e - 1.0;
        float crumbs = noise(p * 18.0);
        color = mix(rim.rgb, rim.rgb * 0.6, step(0.62, crumbs));
        float rim_alpha = 1.0 - smoothstep(0.12, 0.3, out_e + (crumbs - 0.5) * 0.15);
        float crack = 1.0 - smoothstep(0.0, 0.025, abs(noise(p * 3.5 + 7.0) - 0.5));
        crack *= 1.0 - smoothstep(0.2, 1.2, out_e);
        color = mix(color, rim.rgb * 0.35, crack * (1.0 - rim_alpha));
        alpha = max(rim_alpha, crack * 0.85);
    }
    NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    ALBEDO = color;
    ALPHA = alpha;
    ROUGHNESS = 1.0;
}
