// A joint of the pose wire: a quad around the joint (UV in [0, 1]), drawn as
// a bright dot in a soft round glow of the vertex color. Added onto the camera
// picture.
shader_type canvas_item;
render_mode blend_add;

void fragment() {
    float r = length(UV * 2.0 - 1.0);
    float glow = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
    float dot = 1.0 - smoothstep(0.18, 0.28, r);
    vec3 color = COLOR.rgb * glow + vec3(1.0) * dot;
    COLOR = vec4(color * COLOR.a, 1.0);
}
