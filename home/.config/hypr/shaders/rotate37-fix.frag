#version 300 es
precision mediump float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float time;

void main() {
    float angle = radians(time * 10.0);
    mat2 rot = mat2(
        cos(angle), -sin(angle),
        sin(angle),  cos(angle)
    );

    vec2 centered = v_texcoord - vec2(0.5);
    
    // масштабування по аспекту 1920/1080
    centered.x *= 1920.0 / 1080.0;

    vec2 rotated = rot * centered;

    // повертаємо в [0,1]
    rotated.x /= 1920.0 / 1080.0;
    rotated += vec2(0.5);

    if (rotated.x < 0.0 || rotated.x > 1.0 ||
        rotated.y < 0.0 || rotated.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    fragColor = texture(tex, rotated);
}
