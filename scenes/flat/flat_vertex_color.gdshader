shader_type spatial;

// As flat.gdshader, but the color comes from the vertices (e.g., of a model
// imported from glTF with COLOR_0): every polygon shaded flat, with one
// normal per face.

render_mode specular_disabled, cull_disabled;

#include "res://scenes/flat/bend.gdshaderinc"

void vertex() {
    VERTEX = bent(VERTEX, MODEL_MATRIX);
}

void fragment() {
    NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
}
