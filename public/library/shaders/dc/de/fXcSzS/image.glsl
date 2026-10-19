// =====================================================================
//  LUMINOUS LOTUS GATES  ::  IMAGE tab
//  iChannel0 = Buffer A   (filter: nearest, wrap: clamp)
//  A fly-through of iridescent gates: lotus lattices, chrome eye-orbs,
//  halftone bead rings, rainbow zebra bands and crystal rims, inside
//  reef / chrome / smoke tunnel walls, all converging on a violet core.
// =====================================================================

#define SP    1.0     // world distance between gates
#define RG    .78     // gate radius (tunnel wall radius = 1)
#define FOCAL .6      // lens: wall hits the screen corners at depth .6
#define SEG   6.      // gates per scene before the motif changes

// ---------- per-frame state (filled once in mainImage) ----------
float gT, gHue, gBass, gMid, gHigh, gBeat, gRot, gCam;
vec4  gPar;            // parallax weights: x helix, y drift, z accordion, w counter-spin
const vec3 gL = vec3(-.4192, .4990, .7585);   // fake key light (pre-normalised)

float spec(float x){   // 0..1 -> smoothed spectrum (or a travelling wave when audio is off)
#if AUDIO_REACTIVE
    return texelFetch(iChannel0, ivec2(int(clamp(x, 0., 1.) * 63.), 1), 0).x;
#else
    return .55 + .4 * sin(x * 9. - iTime * 2.2);
#endif
}

// ---------- parallax machinery ----------
vec2 path (float z){ return vec2(sin(z * .31) * 1.1 + sin(z * .13) * .6, cos(z * .23) * .9); }
vec2 dpath(float z){ return vec2(cos(z * .31) * .341 + cos(z * .13) * .078, -sin(z * .23) * .207); }

// screen-space shift of the tunnel axis at depth dz: camera rides the path and looks
// along its tangent, so near gates swing hard and the vanishing point drifts.
vec2 gP0, gD0;   // path + tangent at the camera: hoisted, computed once per pixel not per gate
vec2 axisOff(float dz){
    if (gPar.y < .001) return vec2(0);        // drift off: skip 3 trig calls per gate
    return gPar.y * FOCAL * ((path(gCam + dz) - gP0) / dz - gD0);
}
// accordion: travelling wave in depth spacing (monotonic, so draw order stays valid)
float breathe(float dz){ if (gPar.z < .001) return 0.; return gPar.z * .3 * sin(dz * 1.7 - iTime * 2.2) * smoothstep(0., 1.5, dz); }

vec4 parFor(int m){
    return m == 2 ? vec4(1, 0, 0, 0) : m == 3 ? vec4(0, 1, 0, 0) :
           m == 4 ? vec4(0, 0, 1, 0) : m == 5 ? vec4(0, 0, 0, 1) : vec4(0);
}

// ---------- compositing primitives (premultiplied rgba) ----------
vec4 over(vec4 f, vec4 b){ return f + b * (1. - f.a); }

// chrome tube cross-section: d = distance to centreline, w = radius, t = film colour
vec4 tube(float d, float w, float t, float px){
    if (d > w * 7.) return vec4(0);                       // halo < 0.3%: skip all the maths
    float x  = min(d / w, 1.);
    float n  = sqrt(1. - x * x);
    float n2 = n * n, n4 = n2 * n2, n16 = n4 * n4 * n4 * n4;
    vec3  c  = iri(t + x * .35 + gHue);
    float al = smoothstep(w + px, w - px, d);
    float hw = w * w * .5;
    vec3 halo = c * (hw / (d * d + hw)) * .3;              // soft neon bleed
    return vec4((c * (.18 + .95 * n) + n16 * .75) * al + halo * (1. - al), al);
}

// glossy sphere
vec4 ball(vec2 o, float rad, float t, float px){
    float l = length(o);
    if (l > rad + px) return vec4(0);
    vec2  nn = o / rad;
    float nz = sqrt(max(1. - dot(nn, nn), 0.));
    float s  = max(dot(vec3(nn, nz), gL), 0.); s *= s; s *= s; s *= s; s *= s; s *= s; // ^32
    vec3  c  = iri(t + nz * .6 + gHue);
    float al = smoothstep(rad + px, rad - px, l);
    return vec4((c * (.12 + .85 * nz) + s * 1.1) * al, al);
}

// ---------- GATE MOTIFS: p local (tunnel units), r = |p|, a = angle ----------

// 0: lotus gate - geodesic lattice of chrome tubes, flower-of-life petals, node pearls
vec4 gLotus(vec2 p, float r, float a, float h, float px){
    if (r > RG + .12) return vec4(0);
    float n   = h < .5 ? 6. : 8.;
    float sec = TAU / n;
    float aa  = mod(a + (fract(h * 13.) < .5 ? 0. : sec * .5), sec) - sec * .5;
    vec2  q   = r * vec2(cos(aa), sin(aa));
    float w   = .02 * (1. + .6 * gBeat);
    float pr  = RG * .5;
    float dp  = 1e3;
    int jn = n > 7. ? 2 : 1;                                // 8-fold needs +-2 neighbours, 6-fold +-1
    for (int j = -2; j <= 2; j++){                       // petals from this + neighbour sectors
        if (abs(j) > jn) continue;
        float ca = float(j) * sec;
        dp = min(dp, abs(length(q - pr * vec2(cos(ca), sin(ca))) - pr));
    }
    float ds = (r > RG * .14 && r < RG) ? abs(q.y) : 1e3; // spokes
    vec4 o = ball(q - vec2(RG, 0), w * 2.4, h + .2, px);  // pearls on the rim
    float hs = sec * .5;                                   // pearls where neighbour petals cross
    o = over(o, ball(vec2(q.x, abs(q.y)) - RG * cos(hs) * vec2(cos(hs), sin(hs)), w * 1.5, h + .5, px));
    o = over(o, tube(abs(r - RG), w * 1.25, a / TAU * 3. + h, px));
    o = over(o, tube(dp, w * .75, .33 + r * .9 + h, px));
    o = over(o, tube(ds, w * .5, .6 + r * 1.2 + h, px));
    return o;
}

// 1: chrome eye-orbs on stalks
vec4 gEyes(vec2 p, float r, float a, float h, float px, float gi){
    if (r > RG + .5 || r < RG * .4) return vec4(0);
    float n   = floor(7. + h * 5.);
    float sec = TAU / n;
    float id  = floor(a / sec + .5);
    float aa  = a - id * sec;
    vec2  q   = r * vec2(cos(aa), sin(aa));
    float ro  = RG * sin(sec * .5) * .78;
    vec2  o   = q - vec2(RG, 0);
    float l   = length(o) / ro;
    vec4  e   = vec4(0);
    if (l < 1. + px / ro){
        float hh  = hash11(id + gi * 7.31);
        float nz  = sqrt(max(1. - l * l, 0.));
        float an  = atan(o.y, o.x);
        vec3  ic  = iri(hh * 2.3 + gHue + .1);
        float iris = smoothstep(.62, .57, l) * smoothstep(.2, .25, l);
        float stri = .55 + .45 * sin(an * 44. + hh * 20.);
        float ringd = abs(l - .4);
        vec3 col = vec3(.02, .01, .045)
                 + iri(nz * .9 + an / TAU + gHue) * .4 * (1. - nz)
                 + ic * iris * (stri + .5 * smoothstep(.05, 0., ringd)) * (1.3 + gMid)
                 + ic * smoothstep(.7, .63, l) * smoothstep(.6, .66, l) * .5;
        float s = max(dot(vec3(o / ro, nz), gL), 0.); s *= s; s *= s; s *= s; s *= s; s *= s;
        col += s * 1.2;
        float al = smoothstep(1. + px / ro, 1. - px / ro, l);
        e = vec4(col * al, al);
    }
    float sx = clamp(q.x, RG * .42, RG + .45);              // stalk, inward + outward
    vec4 st = tube(length(q - vec2(sx, 0)), .022, .15 + q.x * 1.5 + h, px);
    st.rgb *= .75;
    return over(e, st);
}

// 2: halftone bead ring (each row = one spectrum band)
vec4 gDots(vec2 p, float r, float a, float h, float px){
    float r0 = RG * .5, r1 = RG * 1.02;
    if (r < r0 || r > r1) return vec4(0);
    float dr  = (r1 - r0) / 11.;
    float row = floor((r - r0) / dr);
    float rr  = r0 + (row + .5) * dr;
    float m   = floor(TAU * rr / dr);
    float ca  = TAU / m;
    float an  = a + row * .37 + gT * .15 * (mod(row, 2.) * 2. - 1.); // rows counter-rotate
    float idx = floor(an / ca);
    vec2  l2  = vec2(r - rr, (an - (idx + .5) * ca) * rr);
    float sz  = dr * .44 * (.4 + .6 * spec(row / 10.));
    float d   = length(l2);
    if (d > sz + px) return vec4(0);
    float nz  = sqrt(max(1. - d * d / (sz * sz), 0.));
    vec3  c   = iri(row * .075 + (idx + .5) / m * 2. + h + gHue);
    float al  = smoothstep(sz + px, sz - px, d);
    return vec4((c * (.35 + 1. * nz) + nz * nz * nz * nz * .35) * al, al);
}

// 3: rainbow zebra band (fat torus with warped radial stripes)
vec4 gWave(vec2 p, float r, float a, float h, float px){
    float ri = RG * .7, ro = RG * 1.02;
    if (r < ri - .03 || r > ro + .03) return vec4(0);
    float st   = sin(a * 32. + sin(r * 22. + h * 6.) * (.9 + 1.4 * gBass) - gT * .8 * (h < .5 ? 1. : -1.));
    float band = smoothstep(-.35, .55, st);
    vec3  c    = iri(r * 1.3 + a / TAU * 3. + st * .06 + h + gHue);
    float x    = (r - ri) / (ro - ri) * 2. - 1.;
    float nz   = sqrt(max(1. - x * x, 0.));
    float sb   = nz * band; sb *= sb; sb *= sb; sb *= sb;  // ^8
    vec3  col  = c * band * (.2 + 1. * nz) + sb * .3 + c * .025;
    float al   = smoothstep(ri - px, ri + px, r) * smoothstep(ro + px, ro - px, r);
    vec4  o    = vec4(col * al, al * (.55 + .43 * band));
    o = over(o, tube(abs(r - ri), .012, h + .5, px));
    return o;
}

// 4: crystal rim - wobbly chromatic edge with tumbling gems
vec4 gCrystal(vec2 p, float r, float a, float h, float px){
    if (r < RG * .8 || r > RG * 1.4) return vec4(0);
    float rr = RG * (1. + .05 * sin(a * 5. + h * 9.) + .03 * (1. + 3. * gMid) * sin(a * 11. - gT * 1.3));
    float d  = r - rr;
    float wd = .016 * (1. + gBeat);
    vec3  e  = vec3(d + .014, d, d - .014) / wd;
    vec3 rim = exp(-e * e) * mix(vec3(1), iri(a / TAU * 2. + h + gHue), .55) * 1.6;
    vec4 o = vec4(rim, max(rim.r, max(rim.g, rim.b)) * .5);
    float n = 12., sec = TAU / n;
    float id = floor(a / sec + .5);
    float hh = hash11(id + h * 91.);
    float aa = a - id * sec + (hh - .5) * sec * .5;
    vec2  q  = r * vec2(cos(aa), sin(aa)) - vec2(RG * 1.18 + (hh - .5) * .12, 0);
    q = rot2(gT * (1. + hh) + hh * 6.) * q;
    float s  = .028 + .015 * hh;
    vec2  bq = abs(q) - s;
    float bd = length(max(bq, 0.)) + min(max(bq.x, bq.y), 0.);
    if (bd < px){
        float facet = .55 + .45 * sign(q.x) * .5 + .25 * sign(q.y);
        vec3  gc = iri(hh * 3. + gHue) * facet * 1.3 + smoothstep(-.012, 0., bd) * .4;
        float al = smoothstep(px, -px, bd);
        o = over(vec4(gc * al, al), o);
    }
    return o;
}

// spacer: fat iridescent chrome torus hugging the wall, studded with pearls
vec4 gRing(vec2 p, float r, float a, float h, float px){
    float rr = RG * 1.12;
    float d  = abs(r - rr);
    if (d > .12) return vec4(0);
    float n = floor(10. + h * 8.), sec = TAU / n;
    float aa = a - floor(a / sec + .5) * sec;
    vec4 o = ball(r * vec2(cos(aa), sin(aa)) - vec2(rr - .055, 0), .022, h + .4, px);
    return over(o, tube(d, .05, a / TAU * 2. + h, px));
}

// ---------- tunnel wall ----------
vec3 wallMix(float s){   // (chrome, reef, smoke) weights per scene
    return s < .5 ? vec3(.3, .25, .9) : s < 1.5 ? vec3(1, 0, .15) : s < 2.5 ? vec3(.1, 0, 1) :
           s < 3.5 ? vec3(.8, 0, .5)  : vec3(.05, 1, .25);
}

vec3 wall(vec2 uv){
    vec2  q  = uv;
    float zw = FOCAL / max(length(q), 1e-3);
    if (gPar.y > .001){                        // re-centre on the bent axis (2 fixed-point steps)
        q = uv - axisOff(zw); zw = FOCAL / max(length(q), 1e-3);
        q = uv - axisOff(zw); zw = FOCAL / max(length(q), 1e-3);
    }
    float a  = atan(q.y, q.x) + gPar.x * zw * .5 - gPar.w * iTime * .1;
    float v  = zw - breathe(zw) + gCam;        // world depth along the tunnel
    float lod   = smoothstep(4., 11., zw);     // far wall averages out: kills centre moire
    float light = smoothstep(.45, 1.5, zw) * (.6 + .4 * exp(-zw * .06));

    float sv = v / (SEG * SP) + 4.;            // same scene index as the gates
    float s0 = mod(floor(sv), 5.);
    vec3  W  = mix(wallMix(s0), wallMix(mod(s0 + 1., 5.)), smoothstep(.8, 1., fract(sv)));

    vec3 col = vec3(.012, .006, .03);
    if (W.x > .01){                            // iridescent chrome swirl bands
        float f = v * 2.2 + .55 * sin(a * 3. + v * 1.1) + .35 * sin(a * 5. - v * 1.7 + gT * .6);
        float b = .5 + .5 * sin(f * TAU);
        float b2 = b * b, b8 = b2 * b2 * b2 * b2;
        vec3  c = iri(f * .12 + a / TAU * 2. + gHue);
        vec3 ch = c * (.1 + 1.25 * b2 * (1. + .6 * gMid)) + b8 * b8 * .5;
        col += W.x * mix(ch, c * .3, lod);
    }
    if (W.z > .01){                            // smoky thin-film nebula
        float n = sin(a * 2. + v * .6 + 1.7 * sin(v * .9 + a * 3. + gT * .2)) * sin(v * .7 - a + gT * .25);
        col += W.z * iri(n * .5 + v * .08 + gHue + .5) * (.05 + .42 * smoothstep(-.1, 1., n));
    }
    if (W.y > .01){                            // neon reef: cell grid + glowing flora
        vec2  cu = vec2(a / TAU * 28., v * 2.6);
        vec2  id = floor(cu), f = fract(cu) - .5;
        vec2  e  = .5 - abs(f);
        vec3  rc = vec3(.12, .08, .3) * smoothstep(.07, 0., min(e.x, e.y)) * .5;
        float h  = hash21(mod(id, vec2(28., 1e4)));
        if (h < .55){
            float t  = fract(h * 7.13);
            vec2  g  = f + (vec2(hash21(id + 3.), hash21(id + 7.)) - .5) * .25;
            float rr = length(g), an = atan(g.y, g.x), m;
            if (t < .33){                       // spiky anemone
                float sp = abs(cos(an * 4.5)); sp *= sp; sp *= sp;
                m = smoothstep(.07 + .25 * sp, .04 + .2 * sp, rr) * (.5 + .5 * sp);
            } else if (t < .66){                // sea-fan: ribbed half disc, bright rim
                float rib = .5 + .5 * cos(an * 14.);
                m = smoothstep(.32, .28, rr) * smoothstep(-.1, .02, g.y) * (.25 + .75 * rib * rib) * (.4 + 2. * rr);
            } else {                            // bead pad (honeycomb dots)
                vec2 d = fract(g * 9. + vec2(.5 * step(.5, fract(g.y * 4.5)), 0.)) - .5;
                m = smoothstep(.3, .26, rr) * smoothstep(.4, .2, length(d)) * 1.2;
            }
            m += .18 * exp(-rr * rr * 30.);       // soft bloom under each critter
            rc += iri(h * 3. + gHue) * m * 1.7 * (1. + 2.5 * gHigh * step(.8, fract(h * 31.)));
        }
        col += W.y * mix(rc, vec3(.06, .04, .12), lod);
    }
    return col * light;
}

// ---------- main ----------
void mainImage(out vec4 O, in vec2 F){
    vec2 uv = (F - .5 * iResolution.xy) / iResolution.y;

#if AUDIO_REACTIVE
    vec4 s0 = texelFetch(iChannel0, ivec2(0, 0), 0);
    vec4 s1 = texelFetch(iChannel0, ivec2(1, 0), 0);
    gBass = s0.x; gMid = s0.y; gHigh = s0.z; gBeat = s0.w;
    gT = s1.x; gHue = s1.y + gBeat * .06; gRot = s1.z;
#else
    gBass = gMid = gHigh = gBeat = 0.;
    gT = iTime; gHue = iTime * .012; gRot = iTime * .035;
#endif
    gCam = gT * .85;

#if PARALLAX_MODE == 0
    float ph = iTime / 14., i0 = mod(floor(ph), 5.);
    gPar = mix(parFor(int(i0) + 1), parFor(int(mod(i0 + 1., 5.)) + 1), smoothstep(.75, 1., fract(ph)));
#else
    gPar = parFor(PARALLAX_MODE);
#endif

    gP0 = path(gCam); gD0 = dpath(gCam);

    uv *= 1. - .06 * gBeat;                    // kick punch-in
    uv  = rot2(gRot) * uv;
    float px0 = 1. / iResolution.y;

    // ---- gates, front to back, early-out once the view is covered ----
    vec3  acc = vec3(0);
    float tr  = 1.;
    float g0  = floor(gCam / SP) + 1.;
    const float FAR = float(GATES) * SP;
    for (int k = 0; k < GATES; k++){
        float gi  = g0 + float(k);
        float dz  = gi * SP - gCam;
        float fade = smoothstep(.22, .8, dz) * smoothstep(FAR, FAR - 2.5, dz);
        if (fade < .001) continue;
        float dze = dz + breathe(dz);
        vec2  p   = (uv - axisOff(dz)) * (dze / FOCAL);
        float r   = length(p);
        if (r > RG * 1.65) continue;           // outside every motif's footprint
        float sc  = mod(gi, 2.) > .5 ? 5. : mod(floor(gi / SEG) + 4., 5.);   // 5 = spacer ring
        float h   = hash11(gi * 1.37);
        float spin = gPar.x * dz * .5 + gPar.w * (mod(gi, 2.) * 2. - 1.) * iTime * (.35 + .3 * h)
                   + (h - .5) * .6;
        float a   = atan(p.y, p.x) + spin;
        float px  = px0 * dze / FOCAL * 1.2;
        vec4 g;                                // real branches: sc is the same for every pixel
        if      (sc > 4.5) g = gRing   (p, r, a, h, px);   // of a gate, so GPUs skip the rest
        else if (sc < .5)  g = gLotus  (p, r, a, h, px);
        else if (sc < 1.5) g = gEyes   (p, r, a, h, px, gi);
        else if (sc < 2.5) g = gDots   (p, r, a, h, px);
        else if (sc < 3.5) g = gWave   (p, r, a, h, px);
        else               g = gCrystal(p, r, a, h, px);
        g *= fade;
        g.rgb *= (1. + .7 * gBeat) * mix(1., .55, smoothstep(3., FAR, dz));  // depth haze
        acc += tr * g.rgb;
        tr  *= 1. - g.a;
        if (tr < .02) break;
    }

    // ---- wall + core (only if anything still shows through) ----
    vec2  cc = uv - axisOff(FAR + 3.);
    float rc = length(cc);
    if (tr > .01){
        vec3 w = wall(uv);
        float ca = atan(cc.y, cc.x);
        float star = abs(cos(ca * 4. + gT * .3)); star *= star; star *= star; star *= star; star *= star;
        w += vec3(.85, .8, 1.) * (.02 / (rc + .015)) * (1. + 1.6 * gBass)
           + vec3(.55, .35, 1.) * exp(-rc * 5.) * .9
           + vec3(.9, .8, 1.) * star * exp(-rc * 14.) * .6 * (1. + gBeat);
        acc += tr * w;
    }
    acc += vec3(.5, .4, 1.) * (.004 / (rc + .02));    // core bloom bleeds over everything

    vec3 col = 1. - exp(-acc * 1.25);                 // soft tonemap, keeps neon from clipping
    col *= 1. - .22 * dot(uv, uv);
    O = vec4(col, 1);
}
