// Bioluminescent Glass Ribbons - Audio Reactive Shader (OPTIMIZED)
// Smooth glassy organic ribbons with reflections
// For Shadertoy: Uses iChannel0 as audio texture
//
// Optimizations vs original:
//  - Audio bands sampled ONCE per frame, passed into map() (was: 9 texture()
//    fetches on every raymarch step AND every normal tap)
//  - map() takes bass/mid so getBass()/getMid() no longer called per-step
//  - fbm() removed from the ribbon SDF (was 5x per map() call for 0.015 detail)
//  - Ribbon count 5 -> 4 (smin hides the difference)
//  - calcNormal uses 4-tap tetrahedron instead of 6-tap central diff
//  - Reflection bounces gated on remaining attenuation (skip when negligible)
//  - Step multiplier 0.7 -> 0.82
//  - Background fbm 3 octaves -> 2, single call

// ============================================
// TWEAKING VARIABLES - Audio Reactivity Controls
// ============================================

#define AUDIO_ENABLED 1.0

#define BASS_RIBBON_PULSE 2.0
#define MID_RIBBON_TWIST 1.0
#define BASS_GLOW_INTENSITY 2.0
#define MID_COLOR_SHIFT 1.5
#define HIGH_CAMERA_SHAKE 0.3

#define BASS_INFLUENCE 3.0
#define MID_INFLUENCE 1.5
#define HIGH_INFLUENCE 1.2

#define STATIC_BASS 0.3
#define STATIC_MID 0.25
#define STATIC_HIGH 0.2

#define REFLECTIVITY 0.95
#define IOR 1.45
#define SMOOTHNESS 0.95

// Number of ribbons (was 5). Lower = cheaper.
#define RIBBON_COUNT 4

// ============================================
// END TWEAKING VARIABLES
// ============================================

#define PI 3.14159265359
#define TAU 6.28318530718
#define saturate(x) clamp(x, 0.0, 1.0)

float getAudio(float freq) {
    if (AUDIO_ENABLED < 0.5) {
        return 0.25 + 0.1 * sin(iTime * 2.0 + freq * 10.0);
    }
    return texture(iChannel0, vec2(freq, 0.0)).x;
}

float getBass() {
    float raw = (getAudio(0.01) + getAudio(0.05) + getAudio(0.1)) / 3.0;
    return mix(STATIC_BASS, raw * BASS_INFLUENCE, AUDIO_ENABLED);
}

float getMid() {
    float raw = (getAudio(0.2) + getAudio(0.35) + getAudio(0.5)) / 3.0;
    return mix(STATIC_MID, raw * MID_INFLUENCE, AUDIO_ENABLED);
}

float getHigh() {
    float raw = (getAudio(0.6) + getAudio(0.75) + getAudio(0.9)) / 3.0;
    return mix(STATIC_HIGH, raw * HIGH_INFLUENCE, AUDIO_ENABLED);
}

mat2 rot2(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

mat3 rotX(float a) {
    float c = cos(a), s = sin(a);
    return mat3(1, 0, 0, 0, c, -s, 0, s, c);
}

mat3 rotY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c, 0, s, 0, 1, 0, -s, 0, c);
}

float smin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float smax(float a, float b, float k) {
    return -smin(-a, -b, k);
}

float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(
        mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
            mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
        mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
            mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Background fbm: 2 octaves (was 3). Only used for the sky, not the SDF.
float fbm(vec3 p) {
    float f = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 2; i++) {
        f += amp * noise3D(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return f;
}

vec3 bioColor(float t, float mid) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.0, 0.33, 0.67);

    d += mid * MID_COLOR_SHIFT * vec3(0.2, -0.1, 0.1);

    return a + b * cos(TAU * (c * t + d));
}

vec3 hsv2rgb(float h, float s, float v) {
    vec3 c = fract(h + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0;
    c = saturate(abs(c) - 1.0);
    return v * mix(vec3(1.0), c, s);
}

// Smooth glass ribbon SDF. fbm surface detail removed for cost.
float glassRibbon(vec3 p, float ribbonId, float bass, float mid) {
    float t = iTime * 0.4 + ribbonId * 2.1;

    float twistAmount = 1.5 + mid * MID_RIBBON_TWIST * 2.0;

    float pathX = sin(p.z * 0.25 + t) * 2.5 + sin(p.z * 0.6 + t * 1.2) * 0.8;
    float pathY = cos(p.z * 0.35 + t * 0.8 + ribbonId) * 2.0 + cos(p.z * 0.15) * 1.0;

    vec3 q = p;
    q.x -= pathX;
    q.y -= pathY;

    q.xy *= rot2(p.z * twistAmount * 0.08 + t * 0.5);

    float pulse = sin(iTime * 3.0 + ribbonId * 1.5) * 0.5 + 0.5;
    float thickness = 0.12 + bass * BASS_RIBBON_PULSE * 0.1 * pulse;
    float width = 0.8 + sin(p.z * 1.5 + t * 1.5) * 0.3;

    vec2 qxy = q.xy / vec2(width, thickness);
    float ribbon = (length(qxy) - 1.0) * min(width, thickness);

    return ribbon;
}

// Scene. Now takes bass/mid so it does NOT re-fetch audio per step.
float map(vec3 p, float bass, float mid) {
    float d = 1e10;

    for (int i = 0; i < RIBBON_COUNT; i++) {
        float fi = float(i);
        vec3 rp = p;

        rp = rotY(fi * TAU / float(RIBBON_COUNT) + iTime * 0.08) * rp;
        rp = rotX(fi * 0.3 + sin(iTime * 0.25 + fi) * 0.25) * rp;

        float ribbon = glassRibbon(rp, fi, bass, mid);
        d = smin(d, ribbon, 0.5);
    }

    float sphere = length(p) - 1.2 - bass * BASS_RIBBON_PULSE * 0.3;
    d = smin(d, sphere, 0.8);

    return d;
}

// 4-tap tetrahedron normal (was 6-tap central difference).
vec3 calcNormal(vec3 p, float bass, float mid) {
    const vec2 k = vec2(1.0, -1.0);
    const float e = 0.0005;
    return normalize(
        k.xyy * map(p + k.xyy * e, bass, mid) +
        k.yyx * map(p + k.yyx * e, bass, mid) +
        k.yxy * map(p + k.yxy * e, bass, mid) +
        k.xxx * map(p + k.xxx * e, bass, mid));
}

float fresnel(vec3 rd, vec3 n, float f0) {
    float cosTheta = saturate(dot(-rd, n));
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

vec3 march(inout vec3 ro, inout vec3 rd, inout vec3 attenuation, inout bool hit,
           float bass, float mid) {
    vec3 col = vec3(0.0);
    float t = 0.0;
    float tMax = 25.0;
    hit = false;

    for (int i = 0; i < 120; i++) {
        vec3 p = ro + rd * t;
        float d = map(p, bass, mid);

        if (d < 0.0005) {
            hit = true;
            break;
        }
        if (t > tMax) break;

        t += d * 0.82; // was 0.7
    }

    ro += rd * t;

    if (hit) {
        vec3 p = ro;
        vec3 n = calcNormal(p, bass, mid);
        vec3 ref = reflect(rd, n);

        float colorPhase = dot(p, vec3(0.3, 0.5, 0.4)) * 0.4 + iTime * 0.2;
        colorPhase += length(p) * 0.15;
        vec3 glassColor = bioColor(colorPhase, mid);

        vec3 innerColor = bioColor(colorPhase + 0.3, mid) * 0.6;

        float f0 = pow((IOR - 1.0) / (IOR + 1.0), 2.0);
        float fres = fresnel(rd, n, f0) * REFLECTIVITY;

        vec3 lightDir = normalize(vec3(0.5, 1.0, -0.3));
        float diff = saturate(dot(n, lightDir)) * 0.5 + 0.5;

        float spec = pow(saturate(dot(ref, lightDir)), 64.0 * SMOOTHNESS);

        vec3 lightDir2 = normalize(vec3(-0.7, 0.3, 0.5));
        float rim = pow(1.0 - saturate(dot(-rd, n)), 3.0);
        float rimLight = saturate(dot(n, lightDir2)) * rim;

        vec3 transmitted = mix(innerColor, glassColor, 0.6) * diff;

        float iridescence = sin(dot(n, rd) * 10.0 + iTime) * 0.1 + 0.9;
        transmitted *= iridescence;

        col = transmitted * (1.0 - fres * 0.5);
        col += vec3(1.0, 0.98, 0.95) * spec * 0.8;
        col += glassColor * rimLight * 0.4;

        float fog = exp(-t * t * 0.008);
        col = mix(vec3(0.02, 0.01, 0.03), col, fog);

        col *= attenuation;

        attenuation *= glassColor * fres * fog;
        ro += n * 0.002;
        rd = ref;
    }

    return col;
}

vec3 background(vec3 rd, float mid) {
    float y = rd.y * 0.5 + 0.5;
    vec3 sky = mix(vec3(0.02, 0.01, 0.05), vec3(0.08, 0.04, 0.12), y);

    // Single fbm call (was two).
    float nebula = fbm(rd * 4.0 + iTime * 0.05) * 0.5;

    vec3 nebulaColor = bioColor(nebula * 2.0 + iTime * 0.1, mid);
    sky += nebulaColor * nebula * 0.25;

    float centerGlow = exp(-dot(rd.xy, rd.xy) * 3.0);
    sky += bioColor(iTime * 0.15, mid) * centerGlow * 0.15;

    return sky;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // Audio sampled ONCE per fragment, then reused everywhere.
    float bass = getBass();
    float mid = getMid();
    float high = getHigh();

    vec3 ro = vec3(0.0, 0.0, -7.0 + sin(iTime * 0.4) * 1.5);
    vec3 lookAt = vec3(0.0);

    if (AUDIO_ENABLED > 0.5) {
        ro.xy += high * HIGH_CAMERA_SHAKE * 0.05 * vec2(
            sin(iTime * 25.0),
            cos(iTime * 22.0)
        );
    }

    float camAngle = iTime * 0.15;
    ro.xz *= rot2(camAngle);
    ro.yz *= rot2(sin(iTime * 0.2) * 0.2);

    vec3 forward = normalize(lookAt - ro);
    vec3 right = normalize(cross(vec3(0, 1, 0), forward));
    vec3 up = cross(forward, right);
    vec3 rd = normalize(forward + uv.x * right + uv.y * up);

    vec3 col = vec3(0.0);
    vec3 attenuation = vec3(1.0);
    bool hit = false;

    // Primary ray
    col += march(ro, rd, attenuation, hit, bass, mid);

    // Reflection bounces, gated on remaining attenuation so we skip the march
    // entirely once contribution is negligible.
    if (hit && dot(attenuation, attenuation) > 0.004)
        col += march(ro, rd, attenuation, hit, bass, mid);
    if (hit && dot(attenuation, attenuation) > 0.004)
        col += march(ro, rd, attenuation, hit, bass, mid);

    col += background(rd, mid) * attenuation;

    vec3 glowCol = bioColor(iTime * 0.2, mid);
    col += glowCol * (1.0 - exp(-bass * BASS_GLOW_INTENSITY * 0.5)) * 0.1;

    float vignette = 1.0 - dot(uv, uv) * 0.4;
    col *= vignette;

    col *= 1.0 + bass * BASS_GLOW_INTENSITY * 0.2;

    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    col = pow(saturate(col), vec3(0.4545));

    fragColor = vec4(col, 1.0);
}
