// Buffer A — audio analysis, run ONCE per frame instead of once per pixel.
// iChannel0 = music/mic (the ONLY audio input — each pass that takes music
// gets its own stream, so Image reads the spectrum from row 1 here instead),
// iChannel1 = Buffer A (itself).
//
//  texel (0,0): x = amplified ink clock — integrated, so it surges forward on
//                   the beat and NEVER runs backwards when the music drops
//               y = beat pulse   (1 on a kick onset, decays ~200 ms)
//               z = beat hue     (eases toward w)
//               w = beat hue target (steps on every kick onset)
//  texel (1,0): enveloped kick, snare, mid, high (fast attack, slow release)
//  texel (2,0): x = enveloped spectral energy, y = slow kick average (AGC),
//               z = slow energy average, w = onset refractory timer
//  row 1:       raw FFT copy, bins 0..127 (Image's per-star spectrum)

#define FFT(i)  pow(texelFetch(iChannel0, ivec2(i, 0), 0).x, 5.)

float band(int lo, int hi){
    float s = 0.;
    for(int i = lo; i <= hi; i++) s += FFT(i);
    return s / float(hi - lo + 1);
}
// frequency-WEIGHTED spectral sum: reports brightness/energy, not volume
float spectral(){
    float s = 0.;
    for(int i = 1; i < 100; i++) s += FFT(i) * float(i);
    return s / 2000.;
}

void mainImage(out vec4 O, in vec2 F){
    ivec2 p = ivec2(F);
    if(p.y == 1 && p.x < 128){ O = vec4(texelFetch(iChannel0, ivec2(p.x, 0), 0).x); return; }
    if(p.y > 0 || p.x > 2){ O = vec4(0); return; }

    float dt = clamp(iTimeDelta, 0., .1);
    vec4 s0 = texelFetch(iChannel1, ivec2(0, 0), 0);
    vec4 s1 = texelFetch(iChannel1, ivec2(1, 0), 0);
    vec4 s2 = texelFetch(iChannel1, ivec2(2, 0), 0);
    if(iFrame == 0){ float e0 = spectral(); s0 = vec4(iTime, 0., 0., 0.); s1 = vec4(0.); s2 = vec4(e0, 0., e0, 0.); }

    // ---- envelopes: snap up on a transient, fall away gently
    vec4 raw  = vec4(band(1, 6), band(7, 14), band(16, 44), band(52, 120));
    vec4 rate = mix(vec4(5., 7., 4., 8.), vec4(45., 60., 30., 60.), step(s1, raw));
    s1 += (raw - s1) * (1. - exp(-dt * rate));

    float snd  = spectral();
    float sndE = s2.x + (snd - s2.x) * (1. - exp(-dt * (snd > s2.x ? 30. : 4.)));

    // ---- adaptive kick onset: beat = kick jumps well above its own recent
    // average, so detection tracks quiet and loud tracks alike
    float avgK = s2.y + (raw.x - s2.y) * (1. - exp(-dt * 1.2));
    float cool = max(s2.w - dt, 0.);
    float pulse  = s0.y * exp(-dt * 5.);
    float target = s0.w;
    if(raw.x > avgK * 1.20 + .015 && cool <= 0.){
        pulse   = 1.;
        target += .17;          // a sixth of the ink ramp: one anchor colour on
        cool    = .22;          // ~270 bpm ceiling, ignores double triggers
    }
    float hue = s0.z + (target - s0.z) * (1. - exp(-dt * 7.));
    float wrap = floor(hue);    // palette is fract()-periodic: keep values small
    hue -= wrap; target -= wrap;

    // ---- iAmplifiedTime, integrated. Rate follows energy RELATIVE to its own
    // running average, so it averages ~1x like the original clock: surges on
    // swells and hits, eases in lulls, never stops and never runs backwards.
    float avgS  = s2.z + (sndE - s2.z) * (1. - exp(-dt * .5));
    float clock = s0.x + dt * clamp(1. + (sndE - avgS) * 12. + pulse * .8, .35, 3.);

    if(p.x == 0)      O = vec4(clock, pulse, hue, target);
    else if(p.x == 1) O = s1;
    else              O = vec4(sndE, avgK, avgS, cool);
}
