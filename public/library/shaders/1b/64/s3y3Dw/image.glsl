// ============================================================================
//  SPECTRUM VORTEX (audio reactive)            -- IMAGE tab --
//  iChannel0 = Buffer A
// ============================================================================

vec4 st(int x, int y){ return texelFetch(iChannel0, ivec2(x, y), 0); }

// wrap an integer-valued cell index into [0, n) so hashes match across the atan seam
float wrapCell(float c, float n){ return floor(mod(c + 0.5, n)); }

// original procedural bars (the base look)
float fakeSpec(float x, float id, float t){
    float b = floor(x*48.0);
    float n = h21(vec2(b, id));
    float env = 0.55 + 0.45*sin(x*9.0 + id*1.3 + t*0.7);
    return clamp(env*(0.35 + 0.75*n*n), 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (fragCoord - 0.5*iResolution.xy)/iResolution.y;
    float px = 1.5/iResolution.y;

    // ---- audio state from Buffer A
    vec4 sFast = st(0,0), sSlow = st(1,0), sClk = st(2,0), sKick = st(3,0);
    float T = sClk.x;            // audio clock (= time when speed is off/silent)
    float kickEnv = sClk.y;
    float highSm = sClk.w;
    vec2 kickNow = kickSat(sKick.xy);

    float tw = TWIST;
#if ENABLE_TWIST
    tw *= clamp(1.0 + TWIST_AMT*(sSlow.y - sSlow.z)*5.0, 0.55, 1.9);
#endif

    vec3 col = vec3(0.0);
    float tr = T*RATE;
    float base = floor(tr);
    float fr = fract(tr);
    float nBars = floor(NBARS + 0.5);

    for (float k = 0.0; k < NR; k++){
        float id = base - k;
        float u = (k + fr)/NR;                 // 0 = newborn, 1 = gone
        float R = 0.018*exp(u*5.6);            // perspective growth
        float tb = id/RATE;                    // birth time (audio clock)

        // ring snapshot (valid once Buffer A has written this ring)
        int row = 2 + int(posMod(id, float(NSLOT)));
        vec4 meta = st(NBINS, row);
        vec4 meta2 = st(NBINS + 1, row);
        bool have = (meta.x == idKey(id));
        vec2 kb = have ? kickSat(meta.yz) : kickNow;
        float kickBirth = have ? meta.w : 0.0;

        vec2 c = wander(tb) + kb;              // ring keeps the center it was born at
        vec2 p = uv - c;
        float r = length(p);
        if (r > R*2.4 || r < R*0.5) continue;

        float a = atan(p.y, p.x);
        float spin = T*0.35 + id*0.37;
        float aw = a + swirl(r, tw) - spin;    // spiral warp, unwinds as r grows

        float cw = TAU/nBars;
        float cell = floor(aw/cw);             // unwrapped: used for geometry
        float cellH = wrapCell(cell, nBars);   // wrapped: used for hashes (seam fix)
        float ac = (cell + 0.5)*cw;
        float da = aw - ac;
        float bin = abs(fract(ac/TAU + 0.5) - 0.5)*2.0;   // mirrored around the ring
        int bi = int(clamp(bin*float(NBINS), 0.0, float(NBINS) - 1.0));

        // wobbly base curve
        float ph = h11(id)*TAU;
        float lobes = 7.0 + floor(h11(id + 3.1)*4.0);
        float wob = 1.0 + 0.10*sin(ac*lobes + ph) + 0.06*sin(ac*3.0 - ph*1.7);
#if ENABLE_WAVE_OUTLINE
        if (have) wob += WAVE_AMT*(st(bi, row).y - 0.5)*2.0;
#endif
        float r0 = R*wob;

        // bar length: original bars + real spectrum added on top
        float fs = fakeSpec(bin, id, T);
        float sv = fs;
#if ENABLE_SPECTRUM_RINGS
        float real = have ? smoothstep(SPEC_FLOOR, SPEC_CEIL, st(bi, row).x) : 0.0;
        real *= 0.85 + 0.3*h21(vec2(cellH, id + 7.0));
        sv = BASE_BARS*fs + AUDIO_BARS*real;
#endif
        float len = R*(0.06 + 0.42*clamp(sv, 0.0, 1.4));
        float r1 = r0 + len;

        float th = max(R*0.009, px);
        float dperp = abs(da)*r;
        float dr = max(max(r0 - r, r - r1), 0.0);
        float d = length(vec2(dperp, dr));

        float core = smoothstep(th, th*0.25, d);
        float glow = 0.35*th*th/(d*d + th*th*4.0);
        float line = 0.5*smoothstep(th*1.2, 0.0, abs(r - r0));

        float fadeIn  = smoothstep(0.0, 0.10, u);
        float fadeOut = 1.0 - smoothstep(0.80, 1.0, u);
        float flick = 0.6 + 0.4*h21(vec2(cellH, id));

        vec3 rc = palette(h11(id*1.618 + 0.3));
#if ENABLE_RING_COLOR
        if (have){
            float bright = meta2.x/(meta2.x + meta.w + 0.3);
            bool brightSet = h11(id*3.7) < bright*1.4;
            float pick = step(0.5, h11(id*5.3));
            rc = brightSet ? palIdx(pick*2.0) : palIdx(1.0 + pick*2.0);
        }
#endif
        rc = mix(vec3(1.0, 0.95, 0.85), rc, smoothstep(0.02, 0.18, R));
        float beat = 1.0 + RING_BEAT_GLOW*kickBirth;
        col += rc*(core*flick + glow + line)*fadeIn*fadeOut*1.6*beat;
    }

    // current center (with kick)
    vec2 cn = wander(T) + kickNow;
    vec2 q = uv - cn;
    float rq = length(q);
    float aq = atan(q.y, q.x);

    // warp streaks
    float hi = 0.0;
#if ENABLE_STREAKS
    hi = smoothstep(HIGH_FLOOR, 0.95, highSm)*STREAK_AMT;
#endif
    for (float L = 0.0; L < 3.0; L++){
        float n = 90.0 + L*40.0;
        float cw = TAU/n;
        float a2 = aq + L*0.37 + swirl(rq, tw)*0.5;
        float cell = wrapCell(floor(a2/cw), n);   // seam fix
        float sd = h11(cell + L*91.7);
        float spd = 0.25 + 0.35*h11(cell*3.3 + L);
        float z = fract(T*spd + sd);
        float gen = floor(T*spd + sd);
        float rs = 0.08*exp(z*3.8);
        float slen = rs*(0.25 + 0.35*h11(cell + 17.0))*(1.0 + 0.4*hi);
        float da = (fract(a2/cw) - 0.5)*cw;
        float th = max(rs*0.006 + 0.001, px);
        float dr = max(max((rs - slen) - rq, rq - rs), 0.0);
        float d = length(vec2(abs(da)*rq, dr));
        // density rises smoothly with highs (streaks fade in, never pop)
        float thr = 0.45 - 0.3*hi;
        float on = smoothstep(thr - 0.06, thr + 0.06, h11(cell*7.7 + gen*13.1 + L));
        vec3 sc = palette(h11(cell*1.3 + gen + L*5.0));
        float I = smoothstep(th, th*0.2, d) + 0.25*th*th/(d*d + th*th*4.0);
        col += sc*I*on*smoothstep(0.0, 0.3, z)*0.9*(1.0 + 0.4*hi);
    }

    // dense swirling core strands
    float lr = log(rq);
    for (float L = 0.0; L < 3.0; L++){
        float n = 70.0 + L*33.0;
        float cw = TAU/n;
        float a3 = aq + swirl(rq, tw) - T*(0.5 + 0.15*L) + L*1.9;
        float cell = wrapCell(floor(a3/cw), n);   // seam fix
        float da = (fract(a3/cw) - 0.5)*cw;
        float seg = 0.45;
        float v = lr - T*(0.9 + 0.15*L) + h11(cell + L*31.0)*7.0;
        float sc = floor(v/seg);
        float fv = fract(v/seg);
        float rnd = h21(vec2(cell + L*57.0, sc));
        float s0 = 0.15*rnd, s1 = s0 + 0.35 + 0.5*h11(rnd*91.0);
        float dv = max(max(s0 - fv, fv - s1), 0.0)*seg*rq;
        float th = max(rq*0.032, px);
        float d = length(vec2(abs(da)*rq, dv));
        vec3 scol = mix(palette(h11(rnd*13.7 + L)), vec3(1.0, 0.95, 0.8), 0.2*h11(rnd*5.1));
        float I = smoothstep(th, th*0.2, d) + 0.3*th*th/(d*d + th*th*4.0);
        float mask = step(0.3, rnd)*exp(-rq*rq/0.05)*smoothstep(0.0, 0.03, rq);
        col += scol*I*mask*1.3;
    }

    // hot core + pupil (pulse on kicks)
    float pulse = 0.0;
#if ENABLE_CORE_PULSE
    pulse = kickEnv;
#endif
    col += vec3(1.0, 0.97, 0.92)*(0.06/(rq + 0.03))*smoothstep(0.3 + 0.1*pulse*PULSE_AMT, 0.0, rq)
           *1.6*(1.0 + PULSE_AMT*pulse);
    float pr = 1.0 + PULSE_PUPIL*pulse;
    col *= smoothstep(0.010*pr, 0.014*pr, rq);

    col = 1.0 - exp(-col*1.1);
    col = pow(col, vec3(0.9));
    fragColor = vec4(col, 1.0);
}