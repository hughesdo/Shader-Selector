// Common tab: shared by every pass (Shadertoy semantics).
#define TAU 6.28318530718

vec3 palette(float t) {
    return 0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

// Music texture helpers (512x256 layout: row 0 spectrum, upper rows waveform)
float fft(sampler2D s, float x) { return texture(s, vec2(x, 0.0)).r; }
float band(sampler2D s, float a, float b) {
    float sum = 0.0;
    for (int i = 0; i < 8; i++) sum += fft(s, mix(a, b, float(i) / 7.0));
    return sum / 8.0;
}
