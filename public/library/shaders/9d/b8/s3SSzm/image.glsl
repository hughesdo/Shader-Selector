// ============================================================
//  PHYLLOTAXIS CHORUS — Image (smooth audio + beat hue-cycle)
//  iChannel0 = Audio,  iChannel1 = Buffer A (hue counter)
// ============================================================

// ── DEBUG ────────────────────────────────────────────────────
#define DEBUG_STRIP  0     // 1 = show counter/transient strips on left; 0 = off
// ─────────────────────────────────────────────────────────────

// ── AUDIO TWEAKABLES (smooth, breathing) ─────────────────────
#define AU_SMOOTH   3.0    // FFT bins averaged per band; higher = steadier
#define AU_GAMMA    1.5    // >1 makes quiet quieter, peaks gentler; <1 always-on
#define AU_MASTER   1.0    // overall audio strength

#define BASS_X      0.04   // kick / low end
#define MID_X       0.22   // body
#define HIGH_X      0.55   // shimmer

#define BASS_ZOOM   0.18   // bass swells the breathing zoom
#define BASS_RIPPLE 0.14   // bass deepens the radius ripple
#define MID_SIZE    0.30   // mids gently fatten the dots
#define MID_TRAIL   2.0    // mids light the spiral trails
#define HIGH_SPARK  1.2    // treble lifts the spark shimmer
#define HEART_AUDIO 0.5    // overall energy swells the center heart

// ── HUE CYCLE (driven by Buffer A counter) ───────────────────
#define HUE_STEPS   6.0    // MUST match Buffer A's HUE_STEPS
// ─────────────────────────────────────────────────────────────

#define PI  3.14159265
#define PHI 2.39996323
#define N   420.0

vec3 hue(float h){
    return clamp(abs(mod(h*6.0 + vec3(0,4,2), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float band(float cx){
    float s = 0.0;
    for(float k = -AU_SMOOTH; k <= AU_SMOOTH; k++)
        s += texture(iChannel0, vec2(cx + k*0.004, 0.0)).x;  // FFT row (0.25 was waveform)
    s /= (2.0*AU_SMOOTH + 1.0);
    return pow(clamp(s, 0.0, 1.0), AU_GAMMA) * AU_MASTER;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    float bass   = band(BASS_X);
    float mids   = band(MID_X);
    float treble = band(HIGH_X);
    float energy = (bass + mids + treble) / 3.0;

    // beat-stepped hue counter from Buffer A
    vec4 stateTex   = texture(iChannel1, vec2(0.5)/iResolution.xy);
    float counter   = stateTex.x;
    float rawTr     = stateTex.z;
    float hueOffset = counter / HUE_STEPS;

#if DEBUG_STRIP
    // strip 1 (0-24px): SOLID RED — proves the Image tab + debug block run at all
    if(fragCoord.x < 24.0){
        fragColor = vec4(1.0, 0.0, 0.0, 1.0);
        return;
    }
    // strip 2 (24-48px): counter as a hue — color itself proves Buffer A is wired,
    // and it CHANGES (red->yellow->green->cyan...) one notch per beat
    if(fragCoord.x < 48.0){
        fragColor = vec4(hue(counter / HUE_STEPS), 1.0);
        return;
    }
    // strip 3 (48-72px): raw transient, floored to dim blue so it's never pure black
    if(fragCoord.x < 72.0){
        float v = clamp(rawTr*4.0, 0.0, 1.0);
        fragColor = vec4(0.0, 0.0, 0.15 + v, 1.0);
        return;
    }
#endif

    vec2 uv = (2.0*fragCoord - iResolution.xy)/iResolution.y;
    float t = iTime;

    float rotA = t*0.05 + 0.15*sin(t*0.21);
    float cg = cos(rotA), sg = sin(rotA);
    uv = mat2(cg,-sg,sg,cg)*uv;

    float zoom = 1.15 + 0.25*sin(t*0.13) + bass*BASS_ZOOM;
    uv *= zoom;

    vec3 col = vec3(0.0);
    for(float i = 1.0; i < N; i++){
        float frac = i/N;
        float ripple = (0.12 + bass*BASS_RIPPLE)*sin(6.0*sqrt(frac)*PI - t*1.4);
        float r = sqrt(frac)*1.35 * (1.0 + ripple);
        float a = i*PHI + t*0.1*(1.0 - frac*1.6);
        vec2 p = r*vec2(cos(a), sin(a));
        float d = length(uv - p);

        float size = 0.009 + 0.007*sin(i*0.618 + t*2.0)
                           + 0.013*frac
                           + mids*MID_SIZE*0.012;
        float g = exp(-d*d/(size*size)*8.0);
        float spark = size*0.02/(d*d + 0.0004) * (1.0 + treble*HIGH_SPARK);

        // only change: + hueOffset clicks every dot's color one notch per beat
        vec3 c = hue(fract(frac*2.0 - t*0.04 + sin(a)*0.05 + hueOffset));
        c = pow(c, vec3(1.6));
        c = mix(c, vec3(1.0, 0.92, 0.75), pow(g, 6.0)*0.45);
        col += c * (g*1.1 + spark*0.45) * (0.35 + 0.65*frac);
    }

//   center heart
//    float dc = length(uv);
//    col += vec3(1.0, 0.85, 0.6) * 0.010/(dc*dc + 0.012)
//         * (0.6 + 0.4*sin(t*1.7) + energy*HEART_AUDIO);


//     static spiral in the center is the trail overlay
//    float ang = atan(uv.y, uv.x);
//    float trail = sin(ang*8.0 - log(dc + 0.05)*9.0 + t*0.6);
//    col += vec3(0.08, 0.03, 0.16) * (1.0 + mids*MID_TRAIL)
//         * smoothstep(0.92, 1.0, trail) * smoothstep(1.6, 0.4, dc);

    col = 1.0 - exp(-col*1.6);
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, 1.45);
    col = clamp(col, 0.0, 1.0);
    col = col*col*(3.0 - 2.0*col);
    col *= 1.0 - 0.3*dot(uv/zoom, uv/zoom)*0.4;
    col = pow(col, vec3(0.4545));
    fragColor = vec4(col, 1.0);
}