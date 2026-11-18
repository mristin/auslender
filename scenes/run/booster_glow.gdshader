shader_type spatial;

// The glow of a booster on the road (see Boosters), which draws the eye to
// it: in "ground" mode, on a flat quad under it, pulsing rings of light which
// spread out from under it and a bright pool in the middle; in "aura" mode,
// on an open cylinder around it, a column of light which fades upwards, with
// streaks rising through it. Light is added (it glows, never darkens), and
// bends with the road (see bend.gdshaderinc).

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://scenes/flat/bend.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform bool aura = false;
uniform float strength = 1.0;
// A different phase for every booster, so that they do not pulse together.
uniform float phase = 0.0;

void vertex() {
    VERTEX = bent(VERTEX, MODEL_MATRIX);
}

void fragment() {
    float t = TIME * 1.6 + phase;
    float light;
    if (aura) {
        // UV.y runs from the top (0) to the bottom (1) of the cylinder.
        float up = 1.0 - UV.y;
        float fade = pow(1.0 - up, 1.6);
        float streaks = 0.55 + 0.45 * sin(UV.x * 6.2832 * 7.0 + sin(UV.x * 18.0) * 0.8);
        float rising = 0.6 + 0.4 * sin(up * 14.0 - t * 4.0 + UV.x * 12.0);
        light = fade * streaks * rising * 0.8;
    } else {
        float r = length(UV - vec2(0.5)) * 2.0;
        float pool = pow(clamp(1.0 - r / 0.55, 0.0, 1.0), 1.5);
        float rings = 0.0;
        for (int k = 0; k < 3; k++) {
            float age = fract(t * 0.5 + float(k) / 3.0);
            float edge = age;
            float ring = smoothstep(0.09, 0.0, abs(r - edge));
            rings += ring * (1.0 - age);
        }
        float pulse = 0.8 + 0.2 * sin(t * 3.0);
        light = (pool * pulse + rings * 0.9) * smoothstep(1.0, 0.85, r);
    }
    // NOTE (mristin):
    // Unshaded: the light is the albedo, added to what is behind.
    ALBEDO = color.rgb * light * strength;
}
