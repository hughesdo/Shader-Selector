// ============================================================
// Saw Wave Particle Stream — Audio-Reactive 3D Plasma Flow
// For oneoff.py — iChannel0 = audio texture
// ============================================================

#version 330 core

out vec4 fragColor;

uniform vec2 iResolution;
uniform float iTime;
uniform sampler2D iChannel0;

// -------------------- TWEAKABLES ----------------------------
#define NUM_LAYERS        8        // depth layers
#define BASE_SIZE         0.04     // base particle radius (in grid cells)
#define GLOW_STRENGTH     2.8      // bloom intensity
#define GLOW_FALLOFF      4.5      // bloom tightness
#define CORE_HOTNESS      3.0      // white-hot center multiplier
#define SAW_FREQUENCY     2.5      // sawtooth color repetitions
#define SAW_SHARPNESS     0.7      // 0=smooth ramp, 1=hard saw edge
#define FLOW_SPEED        0.25     // stream velocity
#define TURBULENCE_AMP    0.35     // curl noise displacement
#define TURBULENCE_FREQ   2.5      // curl noise scale
#define STREAM_WIDTH      0.6      // vertical spread of stream
#define STREAM_ANGLE      -0.3     // tilt angle (radians)
#define CAMERA_DIST       3.0      // camera pullback
#define AUDIO_GLOW_MULT   4.0      // audio → glow
#define AUDIO_SIZE_MULT   2.5      // audio → particle grow
#define AUDIO_SAW_MULT    1.5      // audio → saw frequency shift
#define AUDIO_SPREAD_MULT 1.5      // audio → stream spread
#define AUDIO_FLOW_MULT   2.0      // audio → flow surge

// Stream axis, computed once (cos/sin of STREAM_ANGLE)
const vec2 FLOW_DIR = vec2(cos(STREAM_ANGLE), sin(STREAM_ANGLE));

// -------------------- HASH / NOISE ---------------------------

// Integer hash: stays uncorrelated at large coordinates, unlike fract(sin())
// hashes, which lose precision as iTime grows and start drawing grid lines.
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v;
}

vec3 hash33(vec3 p) {
    return vec3(pcg3d(uvec3(ivec3(p)))) * (1.0 / 4294967295.0);
}

vec3 grad3(vec3 p) { return hash33(p) * 2.0 - 1.0; }

// Gradient noise with analytic derivatives (value in .x, gradient in .yzw).
// One call replaces the 12 finite-difference samples curl noise used to take.
vec4 noised(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    vec3 u  = f * f * (3.0 - 2.0 * f);
    vec3 du = 6.0 * f * (1.0 - f);

    vec3 ga = grad3(i + vec3(0,0,0)), gb = grad3(i + vec3(1,0,0));
    vec3 gc = grad3(i + vec3(0,1,0)), gd = grad3(i + vec3(1,1,0));
    vec3 ge = grad3(i + vec3(0,0,1)), gf = grad3(i + vec3(1,0,1));
    vec3 gg = grad3(i + vec3(0,1,1)), gh = grad3(i + vec3(1,1,1));

    float va = dot(ga, f - vec3(0,0,0)), vb = dot(gb, f - vec3(1,0,0));
    float vc = dot(gc, f - vec3(0,1,0)), vd = dot(gd, f - vec3(1,1,0));
    float ve = dot(ge, f - vec3(0,0,1)), vf = dot(gf, f - vec3(1,0,1));
    float vg = dot(gg, f - vec3(0,1,1)), vh = dot(gh, f - vec3(1,1,1));

    float k0 = vb - va, k1 = vc - va, k2 = ve - va;
    float k3 = va - vb - vc + vd, k4 = va - vc - ve + vg, k5 = va - vb - ve + vf;
    float k6 = -va + vb + vc - vd + ve - vf - vg + vh;

    return vec4(
        va + u.x * k0 + u.y * k1 + u.z * k2 + u.x * u.y * k3 + u.y * u.z * k4 + u.z * u.x * k5 + u.x * u.y * u.z * k6,
        ga + u.x * (gb - ga) + u.y * (gc - ga) + u.z * (ge - ga)
           + u.x * u.y * (ga - gb - gc + gd) + u.y * u.z * (ga - gc - ge + gg)
           + u.z * u.x * (ga - gb - ge + gf) + u.x * u.y * u.z * (-ga + gb + gc - gd + ge - gf - gg + gh)
           + du * (vec3(k0, k1, k2) + u.yzx * vec3(k3, k4, k5) + u.zxy * vec3(k5, k3, k4) + u.yzx * u.zxy * k6));
}

// Curl noise for organic flow — same field as before, from one analytic gradient
vec3 curlNoise(vec3 p) {
    vec3 g = noised(p).yzw;
    return vec3(g.y - g.z, g.z - g.x, g.x - g.y);
}

// -------------------- AUDIO ----------------------------------

// Each tap sits on a bin boundary so linear filtering averages two bins for free:
// 17 fetches instead of 170.
float getAudioBass() {
    float v = 0.0;
    for (int i = 0; i < 5; i++)
        v += texture(iChannel0, vec2(float(2 * i + 1) / 512.0, 0.0)).x;
    return v / 5.0;
}

float getAudioMid() {
    float v = 0.0;
    for (int i = 0; i < 6; i++)
        v += texture(iChannel0, vec2(float(21 + i * 10) / 512.0, 0.0)).x;
    return v / 6.0;
}

float getAudioHigh() {
    float v = 0.0;
    for (int i = 0; i < 6; i++)
        v += texture(iChannel0, vec2(float(108 + i * 17) / 512.0, 0.0)).x;
    return v / 6.0;
}

float getFreqAt(float f) {
    return texture(iChannel0, vec2(f, 0.0)).x;
}

// -------------------- SAW WAVE COLOR -------------------------

// Palette ramp magenta → purple → blue → cyan → green, t in [0,1]
vec3 palette(float t) {
    float s = t * 4.0;
    vec3 c = mix(vec3(1.0, 0.05, 0.6), vec3(0.55, 0.05, 0.85), clamp(s, 0.0, 1.0));
    c = mix(c, vec3(0.1, 0.2, 0.95), clamp(s - 1.0, 0.0, 1.0));
    c = mix(c, vec3(0.0, 0.8, 0.85), clamp(s - 2.0, 0.0, 1.0));
    return mix(c, vec3(0.1, 0.9, 0.3), clamp(s - 3.0, 0.0, 1.0));
}

// The magic: sawtooth ramp through the palette with sharp "reset" edges
// like a saw oscillator
vec3 sawColor(float t, float audioMod) {
    float saw = fract(t * (SAW_FREQUENCY + audioMod * AUDIO_SAW_MULT));
    saw = mix(saw, step(0.5, saw), SAW_SHARPNESS * 0.3);
    return palette(smoothstep(0.0, 1.0, saw));
}

// Same palette run as a triangle wave: no reset edge, so large smooth
// areas (the background glow) don't get hard stripes across the screen.
vec3 smoothSawColor(float t) {
    return palette(smoothstep(0.0, 1.0, abs(fract(t * 0.5) * 2.0 - 1.0)));
}

// -------------------- STREAM DENSITY -------------------------

// Defines the flowing stream shape — high near stream center, falls off
float streamDensity(vec3 p, float width) {
    // Rotate into stream space
    vec2 rp = vec2(dot(p.xy, FLOW_DIR), dot(p.xy, vec2(-FLOW_DIR.y, FLOW_DIR.x)));

    float yDist = rp.y / width;
    float zDist = p.z / (width * 1.5);
    float density = exp(-yDist * yDist * 3.0 - zDist * zDist * 2.0);

    // Taper at the ends
    return density * smoothstep(-2.5, -1.0, rp.x) * smoothstep(2.5, 1.0, rp.x);
}

// -------------------- MAIN IMAGE -----------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // Audio
    float bass = getAudioBass();
    float mid  = getAudioMid();
    float high = getAudioHigh();
    float audioAll = (bass * 2.0 + mid + high) / 4.0;

    // ---- Camera: slow orbit with audio sway ----
    float camAngle = iTime * 0.06 + bass * 0.2;
    float camPitch = 0.15 + sin(iTime * 0.1) * 0.1 + mid * 0.1;
    vec3 camPos = vec3(
        CAMERA_DIST * cos(camAngle) * cos(camPitch),
        CAMERA_DIST * sin(camPitch) * 0.4 + 0.2,
        CAMERA_DIST * sin(camAngle) * cos(camPitch)
    );
    vec3 fwd = normalize(vec3(0.0, -0.1, 0.0) - camPos);
    vec3 rgt = normalize(cross(fwd, vec3(0,1,0)));
    vec3 up  = cross(rgt, fwd);
    vec3 rd = normalize(uv.x * rgt + uv.y * up + (1.6 - bass * 0.2) * fwd);

    // Flow distance. Bass adds a bounded surge rather than scaling iTime,
    // which made particles jump further and further on every beat as time grew.
    float flowT = iTime * FLOW_SPEED + bass * FLOW_SPEED * AUDIO_FLOW_MULT;

    float width    = STREAM_WIDTH * (1.0 + bass * AUDIO_SPREAD_MULT);
    float turbAmp  = TURBULENCE_AMP * (1.0 + bass * 0.8);
    float hotBoost = CORE_HOTNESS * (1.0 + bass * 2.0);
    float sizeBase = BASE_SIZE;
    const float cellSize = 0.18;

    // ---- Accumulate particles ----
    vec3 col = vec3(0.0);

    for (int layer = 0; layer < NUM_LAYERS; layer++) {
        float fl = float(layer);
        float layerDepth = 0.8 + fl * 0.65;
        vec3 pos = camPos + rd * layerDepth;

        // Turbulence warps the stream shape, not the particle grid
        // (warping the grid lookup smears each particle into a sliver)
        vec3 warp = curlNoise(pos * TURBULENCE_FREQ + iTime * 0.15) * turbAmp;

        // The stream envelope stays put; only the particles inside it flow.
        // (Testing density after the flow offset pushed every sample out of
        // the stream within a couple of seconds, leaving it empty.)
        float density = streamDensity(pos + warp, width);
        if (density < 0.01) continue;

        // Per-layer camera-facing particle grid, scrolling along the stream axis.
        // Facing the camera keeps particles round as it orbits (a world-XY grid
        // is seen edge-on from the side); the cell id has no depth component,
        // so there are no seams where a layer crosses a cell boundary in z.
        vec3 q = pos - vec3(FLOW_DIR, 0.0) * flowT * (0.8 + fl * 0.1);
        vec2 gp = vec2(dot(q, rgt), dot(q, up)) / cellSize;
        vec2 cell = floor(gp);
        vec2 localP = gp - cell;

        float fog = exp(-layerDepth * 0.08) * density;
        float hotness = min(density * density * hotBoost, 1.5);
        float colorBase = dot(pos.xy, FLOW_DIR) * 0.3 + fl * 0.12 + iTime * 0.15;

        for (int cx = -1; cx <= 1; cx++)
        for (int cy = -1; cy <= 1; cy++) {
            vec2 off = vec2(float(cx), float(cy));
            vec3 h = hash33(vec3(cell + off, fl * 11.0 + 3.0));
            float rnd = h.x;

            // Cull for performance + natural sparse look
            if (rnd > 0.55 + density * 0.4) continue;

            // Micro-animation
            float freqVal = getFreqAt(fract(rnd * 0.5 + 0.02));
            vec2 pPos = off + h.yz
                      + 0.06 * sin(iTime * (1.0 + rnd * 3.0) + h.yz * 6.28)
                      + freqVal * 0.04 * vec2(cos(rnd * 40.0), sin(rnd * 40.0));

            float dist = length(localP - pPos);

            // Size grows with audio & density
            float pSize = sizeBase * (0.4 + rnd * 1.2) * (1.0 + freqVal * AUDIO_SIZE_MULT) * (0.5 + density);

            // Skip particles whose glow can't reach this pixel
            if (dist > pSize * 4.0) continue;

            float core = smoothstep(pSize, pSize * 0.15, dist);
            float glow = exp(-dist * GLOW_FALLOFF / pSize) * GLOW_STRENGTH * (1.0 + freqVal * AUDIO_GLOW_MULT);

            // Saw ramp runs along the stream axis
            vec3 pCol = sawColor(colorBase + freqVal * 0.3, audioAll);

            // Particles near stream center glow white-hot
            vec3 hotCol = mix(pCol, vec3(1.0, 0.85, 0.95), clamp(hotness * core, 0.0, 0.85));

            float brightness = (core * (1.0 + hotness) + glow * 0.4) * density;
            col += (hotCol * core * (1.0 + hotness)
                  + pCol * glow * 0.5
                  + pCol * 0.195 * brightness) * fog;
        }
    }

    // ---- Scattered trailing wisps (outer particles) ----
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        vec3 rh = hash33(vec3(fi, 17.0, 5.0));

        // Spread along stream direction, tilted with it
        vec2 w = (rh.xy - 0.5) * vec2(3.0, 1.2);
        vec2 wispUV = vec2(FLOW_DIR.x * w.x + FLOW_DIR.y * w.y,
                          -FLOW_DIR.y * w.x + FLOW_DIR.x * w.y);

        // Drift, wrap, wobble
        wispUV += FLOW_DIR * flowT * 0.3 * (0.5 + rh.z);
        wispUV = mod(wispUV + 2.0, 4.0) - 2.0;
        wispUV += 0.1 * sin(iTime * 0.3 + fi * 2.0 + rh.xy * 10.0);

        float d = length(uv - wispUV);
        if (d > 0.35) continue; // glow is < 1e-4 beyond this

        float freqVal = getFreqAt(fract(fi * 0.029 + 0.01));
        float wSize = 0.004 + 0.004 * freqVal * AUDIO_SIZE_MULT;
        float wCore = smoothstep(wSize, 0.0, d);
        float wGlow = exp(-d * 30.0) * (0.3 + freqVal * 2.0);

        vec3 wCol = sawColor(dot(wispUV, FLOW_DIR) * 0.5 + iTime * 0.1 + fi * 0.1, audioAll);
        col += wCol * (wCore * 1.5 + wGlow * 0.4);
    }

    // ---- Soft background glow along the stream ----
    {
        float streamCoord = dot(uv, FLOW_DIR);
        float bgMask = exp(-abs(uv.y * FLOW_DIR.x - uv.x * FLOW_DIR.y) * 2.0 / STREAM_WIDTH);
        col += smoothSawColor(streamCoord * 0.5 + iTime * 0.05) * bgMask * 0.015 * (1.0 + bass * 2.0);
    }

    // ---- Tonemap ----
    col = 1.0 - exp(-col * 1.5);
    col = pow(col, vec3(0.9));

    fragColor = vec4(col, 1.0);
}

void main() {
    mainImage(fragColor, gl_FragCoord.xy);
}
