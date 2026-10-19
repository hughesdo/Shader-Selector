// =====================================================================
//  BUFFER A  ::  audio analyser + "iAmplifiedTime" integrator
//  iChannel0 = Music / SoundCloud      iChannel1 = Buffer A (itself)
//  Only a 64x2 corner is ever written; every other pixel exits at once.
//   (0,0) = smoothed bass, mid, high, beat envelope
//   (1,0) = amplified time, hue accumulator, rotation accumulator, slow bass avg
//   (x,1) = 64-bin smoothed spectrum (fast attack, slow fall)
// =====================================================================

float fft(float u){ return texture(iChannel0, vec2(u, .25)).x; }

void mainImage(out vec4 O, in vec2 F){
    ivec2 p = ivec2(F);
    O = vec4(0);
    if (p.y > 1 || p.x > 63) return;                 // 99.99% of pixels: done

    float dt = clamp(iTimeDelta, 0., .1);
    bool first = iFrame < 2;

    if (p.y == 1){                                    // spectrum strip for the dot rings
        float prev = first ? 0. : texelFetch(iChannel1, p, 0).x;
        float u = pow((float(p.x) + .5) / 64., 1.6) * .6;   // log-ish, lows get more bins
#if AUDIO_REACTIVE
        float v = fft(u);
#else
        float v = 0.;
#endif
        O = vec4(max(v, prev - dt * 1.2), 0., 0., 1.);
        return;
    }
    if (p.x > 1) return;

    vec4 s0 = first ? vec4(0) : texelFetch(iChannel1, ivec2(0, 0), 0);
    vec4 s1 = first ? vec4(0) : texelFetch(iChannel1, ivec2(1, 0), 0);

#if AUDIO_REACTIVE
    float bass = (fft(.01) + fft(.025) + fft(.04)) / 3.;
    float mid  = (fft(.12) + fft(.20) + fft(.30)) / 3.;
    float high = (fft(.45) + fft(.60) + fft(.75)) / 3.;
#else
    float bass = 0., mid = 0., high = 0.;
#endif

    float slow  = mix(s1.w, bass, 1. - exp(-dt * 1.5));     // long-run bass average
    float onset = smoothstep(.03, .12, bass - slow);         // kick = bass above its average
    float decayed = s0.w * exp(-dt * 6.);
    float beat  = max(decayed, onset);

    if (p.x == 0){
        O = vec4(mix(s0.xyz, vec3(bass, mid, high), 1. - exp(-dt * 18.)), beat);
    } else {
        float energy = bass * .7 + mid * .3;
        float ampT = s1.x + dt * (.7 + 1.2 * energy * energy + .8 * beat);   // iAmplifiedTime
        float hue  = fract(s1.y + dt * .012 + max(beat - decayed, 0.) * .2); // colour jump per kick
        float rotA = s1.z + dt * (.035 + .3 * energy);                       // slow spin, nudged
        O = vec4(ampT, hue, rotA, slow);
    }
}
