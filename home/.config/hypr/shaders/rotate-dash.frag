 #version 300 es

precision mediump float;


in vec2 v_texcoord;

out vec4 fragColor;

uniform sampler2D tex;

uniform float time;


const float PI = 3.14159265359;


void main() {

    // 1. Обмежуємо час до 5 секунд

    float t = clamp(time, 0.0, 5.0);

    

    // 2. Нормалізуємо час у діапазон [0.0, 1.0]

    float x = t / 5.0;


    // 3. Створюємо плавну криву від 0.0 до 1.0 (Ease-In-Out)

    // Швидкість = 0 на початку (x=0) і в кінці (x=1), максимум посередині (x=0.5)

    float ease = smoothstep(0.0, 1.0, x);


    // 4. Вказуємо кількість ПОВНИХ обертів, які треба зробити за 5 секунд.

    // 2.0 оберти дадуть максимальну швидкість в центрі близько 36 RPM 

    // (що найближче до ваших бажаних 30 RPM з попереднього запиту).

    float turns = 2.0; 


    // Обчислюємо кут: плавна прогресія * кількість обертів * 360 градусів (2π радіан)

    float angle = ease * turns * 2.0 * PI;


    // Матриця повороту

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


    // Відсікання країв

    if (rotated.x < 0.0 || rotated.x > 1.0 ||

        rotated.y < 0.0 || rotated.y > 1.0) {

        fragColor = vec4(0.0, 0.0, 0.0, 1.0);

        return;

    }


    fragColor = texture(tex, rotated);

} 
