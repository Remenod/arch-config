#version 300 es
precision mediump float;

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;

const float ASPECT = 1920.0 / 1080.0;
const float ANGLE = __ANGLE__;

void main() {
    float s = sin(ANGLE);
    float c = cos(ANGLE);

    mat2 rot = mat2(
        c, -s,
        s,  c
    );

    vec2 centered = v_texcoord - vec2(0.5);
    centered.x *= ASPECT;

    vec2 rotated = rot * centered;

    rotated.x /= ASPECT;
    rotated += vec2(0.5);

    if (rotated.x < 0.0 || rotated.x > 1.0 ||
        rotated.y < 0.0 || rotated.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    fragColor = texture(tex, rotated);
}
