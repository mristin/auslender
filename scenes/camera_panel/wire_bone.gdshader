// A bone of the pose wire: a quad along the bone (UV.x along it, UV.y across),
// drawn as a white core in a soft glow of the vertex color, with a pulse
// running along it. Added onto the camera picture, so that it lights up.
shader_type canvas_item;
render_mode blend_add;

// How wide the white core is, as a share of the quad's width.
uniform float core_width = 0.18;

void fragment() {
    float across = abs(UV.y * 2.0 - 1.0);
    float glow = pow(1.0 - across, 2.2);
    float core = 1.0 - smoothstep(core_width * 0.5, core_width, across);
    // NOTE (mristin):
    // Fade the ends, so that the bones melt into the joints.
    float ends = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
    float pulse = 0.8 + 0.2 * sin(UV.x * 9.0 - TIME * 5.0);
    vec3 color = COLOR.rgb * glow * pulse + vec3(0.9) * core;
    COLOR = vec4(color * ends * COLOR.a, 1.0);
}
