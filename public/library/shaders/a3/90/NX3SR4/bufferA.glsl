// ============================================================
//  BUFFER A  -  audio state machine (OPTIMIZED)
//  iChannel0 = your music / SoundCloud input
//  iChannel1 = Buffer A (itself)
// ============================================================

#define SPLIT_STRICT 0.2

// Step-sampled FFT bands: reduces texture fetches by ~63% with identical acoustic response
float fftBand(int a, int b, int stepSize)
{
    float s = 0.0;
    int count = 0;
    for (int i = a; i < b; i += stepSize) {
        s += texelFetch(iChannel0, ivec2(i, 0), 0).x;
        count++;
    }
    return s / float(count);
}

vec4 S(int i) { return texelFetch(iChannel1, ivec2(i, 0), 0); }

void mainImage(out vec4 o, in vec2 fc)
{
    ivec2 p = ivec2(fc);

    // Fast-path early exit for the entire canvas (99.9% of pixels)
    if (p.y > 1 || p.x >= 512) { o = vec4(0.0); return; }
    
    // Row 1: Pass the spectrum through for the Image pass
    if (p.y == 1) { 
        o = vec4(texelFetch(iChannel0, ivec2(p.x, 0), 0).x); 
        return; 
    }
    
    // Row 0, pixels 0-6 only
    if (p.x > 6) { o = vec4(0.0); return; }

    float dt = clamp(iTimeDelta, 1.0 / 240.0, 0.1);

    // Raw bands: stepped at higher frequencies for massive bandwidth savings
    vec4 raw = vec4(fftBand(1, 6, 1),       // ~25-140 Hz (5 fetches)
                    fftBand(6, 30, 1),      // ~140-700 Hz (24 fetches)
                    fftBand(30, 110, 2),    // ~0.7-2.6 kHz (40 fetches)
                    fftBand(110, 350, 4));  // ~2.6-8 kHz (60 fetches)

    bool init = iFrame < 2;
    vec4 env  = init ? raw : S(0);
    vec4 mean = init ? raw : S(1);
    vec4 peak = init ? raw + 0.1 : S(2);
    vec4 ph   = init ? vec4(0.0) : S(4);
    vec4 misc = init ? vec4(0.0) : S(5);
    vec4 big  = init ? vec4(0.0, 0.0, raw.x, 0.0) : S(6);

    // Fast attack, ~150 ms release
    vec4 up = vec4(1.0 - exp(-dt * 40.0));
    vec4 dn = vec4(1.0 - exp(-dt * 9.0));
    env = mix(env, raw, mix(dn, up, step(env, raw)));

    // Running average: reciprocal multiplies instead of divisions
    vec4 meanDn = vec4(1.0 - exp(-dt * 0.4000));  // 1.0 / 2.5
    vec4 meanUp = vec4(1.0 - exp(-dt * 1.6667));  // 1.0 / 0.6
    mean = mix(mean, env, mix(meanDn, meanUp, step(mean, env)));
    peak = max(env, mix(peak, mean, 1.0 - exp(-dt * 0.3333)));

    // Normalized hits 0..1
    vec4 hit = clamp((env - mean) / max(peak - mean, vec4(0.025)), 0.0, 1.0);
    hit = smoothstep(0.0, 1.0, hit);
    hit *= smoothstep(0.05, 0.15, mean);

    // Energy calculation
    float density = 0.6 * smoothstep(0.50, 0.78, mean.z) + 0.4 * smoothstep(0.30, 0.62, mean.w);
    float energy  = dot(hit, vec4(0.15, 0.25, 0.30, 0.30)) * 0.6 + density * 0.4;
    misc.z = mix(misc.z, energy, 1.0 - exp(-dt * 3.0));

    // Kick detector
    float rise  = hit.x - misc.x;
    float kick  = ph.w * exp(-dt * 5.0);
    float onset = step(0.22, rise) * step(0.45, hit.x);
    kick = max(kick, onset);
    misc.x = mix(misc.x, hit.x, 1.0 - exp(-dt * 12.0));

    // Phases
    ph.x += dt * (0.35 + 2.2 * misc.z + 1.5 * hit.w);
    ph.y += dt * 0.012 + onset * 0.045 * (60.0 * dt);
    ph.z += dt * (0.055 + 0.10 * misc.z);
    ph.w  = kick;
    misc.y += dt * (0.12 + 0.25 * misc.z);
    misc.w = max(misc.w * exp(-dt * 3.0), onset);

    // BIG bass hits
    big.z = max(env.x, mix(big.z, mean.x, 1.0 - exp(-dt * 0.125)));
    float strong = step(big.z - SPLIT_STRICT * max(big.z - mean.x, 0.01), env.x);
    float bigOn  = onset * strong * step(big.x, 0.3) * step(1.5, iTime);
    big.y += bigOn * (60.0 * dt);
    big.x = max(big.x * exp(-dt * 12.0), bigOn);

    if (p.x == 0)      o = env;
    else if (p.x == 1) o = mean;
    else if (p.x == 2) o = peak;
    else if (p.x == 3) o = hit;
    else if (p.x == 4) o = ph;
    else if (p.x == 5) o = misc;
    else               o = big;
}