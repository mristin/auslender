// The glow of a button while a cursor (a hand or the mouse) is over it (see
// DwellButton): a gold rim around its rounded box, pulsing softly, and a
// sheen which sweeps across it. It is drawn added on top of the button, on a
// rect a margin larger than the button, so that the rim glows past its edge.

shader_type canvas_item;
render_mode blend_add, unshaded;

// How much the cursor is over it, in [0, 1] (it fades in and out).
uniform float hover : hint_range(0.0, 1.0) = 0.0;
// The size of the button and of the rect drawn, in pixels.
uniform vec2 button_size = vec2(600.0, 110.0);
uniform vec2 rect_size = vec2(632.0, 142.0);
// The radius of the button's corners, in pixels.
uniform float radius = 14.0;
uniform vec4 glow : source_color = vec4(0.949, 0.757, 0.306, 1.0);

// The signed distance from the rounded box (negative inside).
float rounded_box(vec2 p, vec2 half_size, float r) {
    vec2 q = abs(p) - half_size + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
    vec2 p = (UV - 0.5) * rect_size;
    float d = rounded_box(p, button_size * 0.5, radius);
    float inside = 1.0 - smoothstep(-1.0, 1.0, d);
    float rim = exp(-abs(d) / 5.0);
    float pulse = 0.5 + 0.5 * sin(TIME * 4.0);

    // The sheen: a slanted band which sweeps from left to right.
    float along = p.x + p.y * 0.6;
    float span = button_size.x + button_size.y * 2.0;
    float band = fract(TIME * 0.5) * span * 1.5 - span * 0.5 - button_size.x * 0.25;
    float sheen = exp(-pow((along - band) / (button_size.y * 0.3), 2.0));

    float strength = hover * (inside * (0.05 + 0.22 * sheen) + rim * (0.35 + 0.3 * pulse));
    COLOR = vec4(glow.rgb, clamp(strength, 0.0, 1.0));
}
