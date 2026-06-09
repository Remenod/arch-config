#version 300 es
precision mediump float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float time;

void main() {
    float angle = radians(time * 18.0);
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);

    float aspect = 1920.0 / 1080.0;

    // 1. Центруємо координати
    vec2 uv = v_texcoord - vec2(0.5);

    // 2. Обчислюємо динамічний масштаб, щоб нічого не обрізалося
    // Формула розраховує огороджувальний прямокутник (Bounding Box)
    float absC = abs(c);
    float absS = abs(s);
    
    // Ширина і висота, яку займав би повернутий прямокутник
    float newW = aspect * absC + 1.0 * absS;
    float newH = aspect * absS + 1.0 * absC;

    // Коефіцієнт стиснення (щоб вмістити повернуту форму в межі екрана)
    float fitScale = min(aspect / newW, 1.0 / newH);

    // 3. Коригуємо простір для правильного повороту (робимо "квадратним")
    uv.x *= aspect;

    // 4. Масштабуємо (ділимо, бо це UV-координати: більше значення = менше зображення)
    uv /= fitScale;

    // 5. Повертаємо
    uv = rot * uv;

    // 6. Повертаємо в початковий простір
    uv.x /= aspect;
    vec2 rotatedUV = uv + vec2(0.5);

    // 7. Малюємо чорне тло там, де немає текстури
    if (rotatedUV.x < 0.0 || rotatedUV.x > 1.0 ||
        rotatedUV.y < 0.0 || rotatedUV.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        fragColor = texture(tex, rotatedUV);
    }
}
