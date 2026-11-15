shader_type spatial;

// Shade every polygon flat, with one normal per face, as the polygon boxers of
// the early nineties were drawn: the normal comes from the screen-space
// derivatives of the position, so even a low-poly sphere looks faceted.
// `flash` blends in `flash_color` (e.g., white when hit, red in a wind-up).
// With `stripes` above zero, wavy bands of `stripe_color` cross the part (a
// texture drawn in the part's own space: e.g., the fur of a tiger), about
// `stripes` radians a meter along its height.

render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 stripe_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stripes = 0.0;

varying vec3 local;

void vertex() {
    local = VERTEX;
}

void fragment() {
    NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    vec3 color = albedo.rgb;
    if (stripes > 0.0) {
        // Bands across the height which wobble around the part, narrowing to
        // points at their ends, as a tiger's.
        float around = atan(local.x, local.z);
        float wave = sin(local.y * stripes + sin(around * 3.0) * 1.3 + sin(around * 7.0) * 0.4);
        float width = 0.55 + 0.3 * abs(cos(around * 2.0));
        color = mix(color, stripe_color.rgb, smoothstep(width, width + 0.08, wave));
    }
    ALBEDO = mix(color, flash_color.rgb, flash * 0.6);
    EMISSION = flash_color.rgb * flash * 0.4;
    ROUGHNESS = 1.0;
}
