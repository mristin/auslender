shader_type spatial;

// The strip on the floor ahead of the player in a run (see PathStrip): the
// path he is heading on, as wide as his body, all the way to the horizon. A
// soft glowing core, brighter rims, and chevrons pointing ahead which roll
// with the run (`scroll`, in the chevrons' spacing); it fades a little into
// the distance, and out at his feet. Added to the scene, so that it glows over
// the road.

render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.3, 1.0);
uniform float scroll = 0.0;
// How many chevrons along the whole strip.
uniform float chevrons = 60.0;

void fragment() {
    // UV.y: 0 far ahead, 1 at his feet; UV.x across, 0.5 in the middle.
    float across = abs(UV.x - 0.5) * 2.0;
    float near = UV.y;
    // The chevrons: a V of each, its tip ahead, rolling towards him.
    float along = (1.0 - near) * chevrons + scroll;
    float phase = fract(along + across * 0.7);
    float chevron = smoothstep(0.0, 0.06, phase) * smoothstep(0.3, 0.22, phase);
    float core = pow(1.0 - across, 1.5);
    float rim = smoothstep(0.7, 0.92, across) * smoothstep(1.0, 0.94, across);
    float glow = 0.25 * core + 0.75 * chevron * (1.0 - 0.4 * across) + 0.7 * rim;
    float fade = (0.3 + 0.7 * pow(near, 2.0)) * smoothstep(1.0, 0.985, near);
    ALBEDO = mix(color.rgb, vec3(1.0, 0.97, 0.85), chevron * 0.6) * glow * fade * color.a;
}
