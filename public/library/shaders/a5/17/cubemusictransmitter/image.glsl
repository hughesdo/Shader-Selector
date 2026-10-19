#version 330 core

// Low Frequency Flow by OneHung
// A corner-balanced transmitter cube hovering over a glossy floor. Bass swells the
// cube and pushes ripples and spectrum rings outward across the floor; a ring of
// equalizer pillars tracks the spectrum.

uniform float iTime;
uniform vec2 iResolution;
uniform sampler2D iChannel0;  // music: row 0 = spectrum, rest = waveform

out vec4 fragColor;

#define PI      3.14159265
#define TAU     6.28318531
#define N_BARS  36.0
#define BAR_R   2.7
#define FLOOR_Y -1.0
#define MAX_D   40.0

// ---------------------------------------------------------------- audio

float fft(float x) { return texture(iChannel0, vec2(clamp(x, 0.0, 1.0), 0.002)).r; }

float gBass, gMid, gHigh, gHue;

void readAudio() {
    // 512 bins over ~22 kHz, so one bin is ~43 Hz: bass lives in the first few bins.
    gBass = (fft(0.002) + fft(0.005) + fft(0.008) + fft(0.011)) * 0.25;
    gMid  = (fft(0.03) + fft(0.06) + fft(0.10) + fft(0.14)) * 0.25;
    gHigh = (fft(0.25) + fft(0.35) + fft(0.45)) / 3.0;
    gBass = smoothstep(0.15, 0.95, gBass);
    gHue  = iTime * 0.02 + gMid * 0.25;
}

// teal -> violet -> magenta, mirrored so it loops without a seam
vec3 pal(float t) {
    t = abs(fract(t) * 2.0 - 1.0);
    vec3 a = vec3(0.05, 0.85, 1.00);
    vec3 b = vec3(0.50, 0.25, 1.00);
    vec3 c = vec3(1.00, 0.22, 0.58);
    return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}

// ---------------------------------------------------------------- scene

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float cubeSize() { return 0.55 * (1.0 + 0.2 * gBass); }

vec3 toCube(vec3 p) {
    p.y -= 0.35 + 0.1 * sin(iTime * 0.8);
    p.xz = rot(iTime * 0.4) * p.xz;
    p.yz = rot(0.785398) * p.yz;   // stand the cube on a corner
    p.xy = rot(0.615480) * p.xy;
    return p;
}

float ripple(vec2 xz) {
    float r = length(xz);
    float amp = 0.025 + 0.11 * gBass;
    return amp * sin(r * 5.0 - iTime * 3.0) * exp(-0.3 * max(r - 1.2, 0.0)) * smoothstep(0.8, 1.6, r);
}

float barHeight(float id) {
    // mirrored around the ring so the spectrum reads symmetrically
    float k = abs(id / N_BARS * 2.0 - 1.0);
    float f = fft(0.004 + 0.4 * k * k);
    float idle = 0.12 * (0.5 + 0.5 * sin(id * 0.9 + iTime * 1.7));
    return 0.06 + idle * (1.0 - smoothstep(0.0, 0.3, f)) + 1.5 * f * f;
}

float gDCube, gDBars, gBarId, gBarH;

float sdBars(vec3 p) {
    float sector = TAU / N_BARS;
    float i = floor(atan(p.z, p.x) / sector + 0.5);
    vec2 q = rot(-i * sector) * p.xz;
    q.x -= BAR_R;
    gBarId = mod(i, N_BARS);
    gBarH = barHeight(gBarId);
    vec3 bp = vec3(q.x, p.y - (FLOOR_Y + gBarH * 0.5), q.y);
    return sdRoundBox(bp, vec3(0.055, gBarH * 0.5, 0.055), 0.02);
}

// x = distance, y = material (1 floor, 2 cube, 3 bars)
vec2 map(vec3 p) {
    float s = cubeSize();
    gDCube = sdRoundBox(toCube(p), vec3(s), 0.035);
    gDBars = sdBars(p);
    float dFloor = p.y - FLOOR_Y - ripple(p.xz);
    vec2 r = vec2(dFloor, 1.0);
    if (gDCube < r.x) r = vec2(gDCube, 2.0);
    if (gDBars < r.x) r = vec2(gDBars, 3.0);
    return r;
}

vec3 normal(vec3 p) {
    const vec2 k = vec2(1.0, -1.0) * 0.0015;
    return normalize(k.xyy * map(p + k.xyy).x + k.yyx * map(p + k.yyx).x +
                     k.yxy * map(p + k.yxy).x + k.xxx * map(p + k.xxx).x);
}

// Marches and accumulates volumetric glow around the cube and pillars.
vec2 march(vec3 ro, vec3 rd, int steps, out vec3 glow) {
    float t = 0.05;
    glow = vec3(0.0);
    vec3 cubeCol = pal(gHue + 0.1);
    for (int i = 0; i < 160; i++) {
        if (i >= steps) break;
        vec2 h = map(ro + rd * t);
        glow += cubeCol * (0.005 + 0.02 * gBass) / (1.0 + 60.0 * gDCube * gDCube);
        glow += pal(gHue + gBarId / N_BARS) * 0.004 * (0.3 + gBarH) / (1.0 + 400.0 * gDBars * gDBars);
        if (h.x < 0.001 * t) return vec2(t, h.y);
        t += h.x * 0.75;
        if (t > MAX_D) break;
    }
    return vec2(MAX_D, 0.0);
}

vec3 sky(vec3 rd) {
    vec3 col = mix(vec3(0.004, 0.005, 0.012), vec3(0.012, 0.008, 0.03), smoothstep(-0.1, 0.7, rd.y));
    col += pal(gHue + 0.3) * 0.02 * exp(-abs(rd.y) * 14.0) * (1.0 + gBass);
    return col;
}

// Emission plus a little direct light. Shared by the primary and reflected rays.
vec3 surface(vec3 p, vec3 n, vec3 rd, float mat) {
    vec3 light = normalize(vec3(0.4, 1.0, -0.3));
    float dif = max(dot(n, light), 0.0);
    vec3 cubeCol = pal(gHue + 0.1);

    if (mat == 2.0) {
        float s = cubeSize();
        vec3 q = abs(toCube(p)) / s;
        // second largest axis -> close to 1 only along the edges
        float e = max(min(q.x, q.y), min(max(q.x, q.y), q.z));
        float edge = smoothstep(0.84, 0.97, e);
        float inset = smoothstep(0.025, 0.0, abs(e - 0.62));
        float scan = pow(0.5 + 0.5 * sin(p.y * 24.0 - iTime * 5.0), 8.0) * gHigh;
        float fres = pow(1.0 - max(dot(-rd, n), 0.0), 3.0);
        vec3 base = vec3(0.02, 0.025, 0.04) * (0.4 + dif) + sky(reflect(rd, n)) * 0.2 + fres * cubeCol * 0.15;
        float pulse = 0.6 + 3.5 * gBass;
        return base + cubeCol * (edge * pulse + inset * (0.25 + 1.5 * gMid) + scan * 0.6);
    }

    if (mat == 3.0) {
        sdBars(p);
        float top = FLOOR_Y + gBarH;
        float grad = smoothstep(FLOOR_Y, top, p.y);
        vec3 c = pal(gHue + gBarId / N_BARS);
        return c * (0.15 + grad * grad * (0.8 + 2.5 * gBarH)) + vec3(0.02) * dif;
    }

    // floor: rings of spectrum flowing outward, lit by the cube
    float r = length(p.xz);
    float phase = r * 1.6 - iTime * (0.45 + 0.4 * gBass);
    float ring = pow(0.5 + 0.5 * cos(phase * TAU), 30.0);
    float fr = fft(0.003 + 0.1 * clamp((r - 1.0) / 9.0, 0.0, 1.0));
    vec3 ringCol = pal(gHue + r * 0.07) * ring * (0.04 + 1.6 * fr * fr) * exp(-0.12 * r);
    float pool = (0.25 + 1.4 * gBass) / (1.0 + 0.8 * r * r);
    return vec3(0.008, 0.01, 0.016) * (0.3 + dif) + ringCol + cubeCol * pool * 0.16;
}

vec3 aces(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
    readAudio();
    vec2 uv = (2.0 * gl_FragCoord.xy - iResolution.xy) / iResolution.y;

    // slow orbit, gentle bob, a small bass push-in
    float a = iTime * 0.12 + 0.6;
    vec3 ro = vec3(sin(a) * 6.8, 1.35 + 0.35 * sin(iTime * 0.21), cos(a) * 6.8);
    vec3 ta = vec3(0.0, -0.1, 0.0);
    vec3 fw = normalize(ta - ro);
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(rt, fw);
    float zoom = 1.9 + 0.12 * gBass;
    vec3 rd = normalize(uv.x * rt + uv.y * up + zoom * fw);

    vec3 glow;
    vec2 h = march(ro, rd, 140, glow);
    vec3 col;

    if (h.y > 0.0) {
        vec3 p = ro + rd * h.x;
        vec3 n = normal(p);
        col = surface(p, n, rd, h.y);

        if (h.y == 1.0) {
            // glossy floor reflection
            // damp the ripple normal so reflections shimmer instead of lensing
            vec3 rn = normalize(mix(vec3(0.0, 1.0, 0.0), n, 0.15));
            vec3 rr = reflect(rd, rn);
            vec3 rglow;
            vec2 rh = march(p + n * 0.03, rr, 70, rglow);
            vec3 rc = sky(rr);
            if (rh.y > 1.0) {
                vec3 rp = p + rr * rh.x;
                rc = surface(rp, normal(rp), rr, rh.y);
            }
            rc += rglow;
            float fres = 0.08 + 0.92 * pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
            col += rc * mix(0.35, 1.0, fres);
        }

        float fog = 1.0 - exp(-0.0016 * h.x * h.x);
        col = mix(col, sky(rd), fog);
    } else {
        col = sky(rd);
    }

    col += glow;
    col *= 1.0 + 0.25 * gBass;

    col = aces(col * 0.95);
    col = pow(col, vec3(1.0 / 2.2));

    vec2 q = gl_FragCoord.xy / iResolution.xy;
    col *= 0.35 + 0.65 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.2);
    // tiny dither against banding in the dark gradients
    col += (fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;

    fragColor = vec4(col, 1.0);
}
