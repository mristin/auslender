// The curve of the road in a run (see Run and Scenery.set_bend): everything
// ahead of the player is pushed to the side by `road_bend` times the square of
// how far ahead it is, so that the road seems to curve away to the left or
// the right, as in Out Run. Only the look: the player still runs straight
// ahead, and the game measures everything on the straight road. Both are
// global uniforms (see project.godot), zero outside a run.

global uniform float road_bend;
global uniform float road_spot_z;

// The vertex (in the model's space) of the model, bent with the road.
vec3 bent(vec3 vertex, mat4 model) {
    vec3 world = (model * vec4(vertex, 1.0)).xyz;
    float ahead = max(0.0, road_spot_z - world.z);
    vec3 shift = vec3(road_bend * ahead * ahead, 0.0, 0.0);
    return vertex + inverse(mat3(model)) * shift;
}
