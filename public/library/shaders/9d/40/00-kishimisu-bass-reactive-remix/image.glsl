// https://www.shadertoy.com/view/ffjGW1
// 00 - kishimisu Bass-reactive remix
// Converted to OneOffRender format

#version 330 core

uniform float iTime;
uniform vec2 iResolution;
uniform sampler2D iChannel0; // Audio FFT (512x2: row 0 = FFT, row 1 = waveform)

out vec4 fragColor;

/* Interference by @kishimisu (2026) - https://www.shadertoy.com/view/scSGD1
   Bass-reactive remix — set iChannel0 to an audio source

   TWEAKABLES
*/
// ArthurTent-style: slow steady spin, small audio nudge, colour pop on bass hits
#define ROT_SPEED       0.08  // base xy spin (rad/s); original was 0.25
#define ROT_NUDGE       0.35  // extra spin angle from audio energy (not multiplied by time)
#define HIT_LO          0.25  // bass level where the colour pop starts
#define HIT_HI          0.55  // bass level where the colour pop is full
#define HIT_HUE_SHIFT   2.4   // palette phase shift on a bass hit
#define MID_BIN         0.08  // ~2kHz mids, for overall energy
#define BASS_GLOW_AMT   1.2   // bass multiplier on glow brightness (was 1.8)
#define EXPOSURE        0.55  // pre-tonemap gain; lower = less white blowout
#define MAX_BRIGHT      0.9   // output ceiling so highlights never hit pure white
#define BASS_STEP_AMT   0.002 // bass influence on ray step size (was 0.008, read as warping)
// FIXED: original 0.03 mapped to ~700Hz in our 48kHz/512-bin system (not bass).
// Multi-bin average across true sub-bass / kick range (50-350Hz).
#define BASS_BIN_A      0.003  // ~72Hz  sub-bass
#define BASS_BIN_B      0.008  // ~192Hz kick fundamental
#define BASS_BIN_C      0.014  // ~336Hz upper-bass

#define R(a) *= mat2(cos(a + vec4(0,33,11,0)))
#define L(x) length(x)

void mainImage(out vec4 O, vec2 F) {
    float a, r, t = iTime;

    // --- Bass sampling (multi-bin average across true bass range) ---
    float bass = (texture(iChannel0, vec2(BASS_BIN_A, 0.0)).x
               + texture(iChannel0, vec2(BASS_BIN_B, 0.0)).x
               + texture(iChannel0, vec2(BASS_BIN_C, 0.0)).x) / 3.0;
    bass = pow(bass, 1.5);                    // milder compression (was 2.0)
    float mid    = texture(iChannel0, vec2(MID_BIN, 0.0)).x;
    float energy = bass * 0.7 + mid * 0.3;
    // Spin angle = slow time spin + bounded audio offset. The old t*(1+bass)
    // made each beat jump the angle further the longer the track played.
    float spin = t * ROT_SPEED + energy * ROT_NUDGE;
    float hit  = smoothstep(HIT_LO, HIT_HI, bass);    // beat gate
    float hue  = hit * HIT_HUE_SHIFT;                 // palette shift on bass hits
    float bassGlow = 1.0 + bass * BASS_GLOW_AMT;

    for (O *= a; a < 40.; a++) {
        vec3 i = iResolution.xyy, f,
             p = r * normalize(vec3((F+F-i.xy)/i.y, 1));

        p.z -= 3.;
        p.xz R(.3);
        p.zy R(sin(t/4.)*.3 + .9);
        p.xy R(spin);                        // slow spin, nudged by audio
        p.x = abs(p.x) - 1.;

        O += bassGlow *                       // bass pumps the glow
             (.04 + .12*smoothstep(.9, 1., cos(L(p.xy+p.z)*2.-t)))*
             (1. + cos(L(p.xy)*2. + a*.2 + hue + vec4(0,1,2,0)))/L(p.xy);  // hue pops on bass

        p.yx R(atan(p.y, p.x));
        p.zx R(atan(max(p.z, 0.), p.x));

        f.x = pow(.67, floor(t - log(p.x)/.4) - t);
        r += min(L(p.xy), min(
             abs(L(p - f) - f.x*.2),
             abs(L(p - f*.67) - f.x*.134)
        )) + .01 + bass * BASS_STEP_AMT;    // subtle geometry pulse on beat
    }

    O = tanh(O * EXPOSURE) * MAX_BRIGHT;  // tamed: was tanh(O), saturated to white
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;  // no Y flip: selector uses bottom-left origin like Shadertoy
    mainImage(fragColor, fragCoord);
}