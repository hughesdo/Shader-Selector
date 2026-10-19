// ============================================================
//  PHYLLOTAXIS CHORUS — Buffer A (hue step counter)
//  iChannel0 = Audio,  iChannel1 = Buffer A (self-feedback)
//  State texel (0,0): .x = hue counter, .y = refractory timer, .z = last transient,
//                     .w = slow running average of the bass FFT
// ============================================================

// ── BEAT / STEP TWEAKABLES ───────────────────────────────────
#define BEAT_X         0.04   // bass band x-position for kick detection
#define BEAT_THRESH    0.06   // transient must exceed this to count (raise = fewer)
#define REFRACTORY     0.16   // seconds locked out after a kick (no double-fire)
#define HUE_STEPS      6.0    // wheel divided into this many slots; counter wraps
#define WAVE_MULT      1.4    // how far above the slow avg counts as a transient
#define AVG_TAU        0.35   // seconds; time constant of the slow bass average
#define FFT_Y          0.0    // FFT row (rows below are spectrum, the rest is waveform)
// ─────────────────────────────────────────────────────────────

// Average a few FFT bins around x.
float fftAvg(float x){
    float s = 0.0;
    for(float k = -2.0; k <= 2.0; k++)
        s += texture(iChannel0, vec2(x + k*0.004, FFT_Y)).x;
    return s / 5.0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    // single state texel at bottom-left
    bool isStateTexel = (fragCoord.x < 1.0 && fragCoord.y < 1.0);

    vec4 st = texture(iChannel1, vec2(0.5)/iResolution.xy);
    float counter = st.x;
    float timer   = st.y;
    float slowAvg = st.w;

    if(iFrame < 2){ counter = 0.0; timer = 0.0; slowAvg = 0.0; }

    float dt = clamp(iTimeDelta, 1.0/240.0, 1.0/15.0);
    timer = max(0.0, timer - dt);

    // Transient: instant bass FFT minus its own slow running average.
    // (The old version subtracted the waveform row, which idles at ~0.5.)
    float fft = fftAvg(BEAT_X);
    float tr  = max(0.0, fft - slowAvg * WAVE_MULT);
    slowAvg   = mix(slowAvg, fft, 1.0 - exp(-dt / AVG_TAU));
    if(tr > BEAT_THRESH && timer <= 0.0){
        counter = mod(counter + 1.0, HUE_STEPS);
        timer   = REFRACTORY;
    }

    // store last transient in .z so the Image debug can show the raw signal too
    fragColor = vec4(counter, timer, tr, slowAvg);
}