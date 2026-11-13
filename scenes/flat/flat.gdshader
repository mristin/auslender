shader_type spatial;

// Shade every polygon flat, with one normal per face, as the polygon boxers of
// the early nineties were drawn: the normal comes from the screen-space
// derivatives of the position, so even a low-poly sphere looks faceted.
// `flash` blends in `flash_color` (e.g., white when hit, red in a wind-up).

render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    ALBEDO = mix(albedo.rgb, flash_color.rgb, flash * 0.6);
    EMISSION = flash_color.rgb * flash * 0.4;
    ROUGHNESS = 1.0;
}
