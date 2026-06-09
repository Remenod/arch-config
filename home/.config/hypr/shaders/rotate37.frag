#version 300 es
precision mediump float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float time;

void main() {
    //float angle = radians(37.0);
    float angle = radians(time * 18.0);
    mat2 rot = mat2(
        cos(angle), -sin(angle),
        sin(angle),  cos(angle)
    );

    vec2 centered = v_texcoord - vec2(0.5);
    vec2 rotated = rot * centered + vec2(0.5);

    // Fixed the missing logical OR operators (||) from your snippet
    if (rotated.x < 0.0 || rotated.x > 1.0 ||
        rotated.y < 0.0 || rotated.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        //fragColor = vec4(1.0, 1.0, 1.0, 1.0);
        //fragColor = vec4(mod(time * 3.0, 1.0), mod(time * 2.0, 1.0), mod(time, 1.0), 1.0);
        return;
    }

    fragColor = texture(tex, rotated);
}
