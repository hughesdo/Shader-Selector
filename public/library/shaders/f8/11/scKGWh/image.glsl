// =============================================================================
//  Ink Nebula — audio-reactive fluid acrylic / alcohol-ink burst
//
//  INK MODEL.  Not noise: 7 translucent SHEETS, each a warped field cut at its
//  own threshold. Two things make it read as ink rather than as fog:
//    * the cut threshold is itself perturbed by high-frequency fbm, so edges
//      come out lobed and dendritic like ink pushing into ink, never smooth;
//    * every edge is a WET EDGE — pigment concentrates into a dark line just
//      inside the boundary, and the solvent leaves a bright halo just outside.
//      That dark-then-bright pair is the whole signature of a dried pour.
//
//  RAYS.  Space is scaled away from each attractor by an amount that depends
//  only on DIRECTION — fbm sampled on the unit circle, normalize(p-A). Seam-
//  free, so no branch cut across the canvas the way log-polar/atan would give.
//
//  AUDIO.  Method borrowed from ArthurTent, who has ~95 audio visualisers on
//  Shadertoy and a house style worth stealing:
//    * texelFetch on integer FFT bins, hard-gated by pow(x, 5.) — that gate is
//      why his shaders punch on transients instead of wobbling on loudness;
//    * narrow bin slices per instrument rather than one "bass" number;
//    * and the good idea: audio advances the CLOCK (his iAmplifiedTime), so
//      every rotation, drift and warp downstream inherits the reaction for
//      free. The ink surges forward on the beat rather than being poked.
//  Silent input is a no-op: every audio term is additive over the still image.
//
//  BEAT COLOUR.  Buffer A finds kick onsets against the kick's own running
//  average (so it adapts to quiet and loud tracks) and steps the ink palette
//  one anchor colour per hit, eased — beats land as colour, not just light.
//  It also INTEGRATES the amplified clock, so the pour surges forward on a
//  hit and never rewinds when the music drops back.
//
//  iChannel1 = Buffer A (music/mic goes on Buffer A's iChannel0 — one stream,
//  not one per pass).  Mouse: drag the main attractor.  2 passes; all FFT
//  analysis runs once per frame in Buffer A.
// =============================================================================

#define T        iTime
#define TAU      6.28318530718
#define LAYERS   7


mat2 rot(float a){ float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

float hash21(vec2 p){
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3. - 2. * f);
    return mix(mix(hash21(i),             hash21(i + vec2(1, 0)), f.x),
               mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p, int oct){
    float s = 0., a = .5;
    for(int i = 0; i < 6; i++){
        if(i >= oct) break;
        s += a * vnoise(p);
        p  = rot(.5) * p * 2.03;
        a *= .5;
    }
    return s;
}

// ------------------------------------------------------------------ audio
// Analysis lives in Buffer A and runs once per frame — here it is 3 fetches.
//  (0,0) amplified clock, beat pulse, beat hue
//  (1,0) kick, snare, mid, high envelopes      (2,0).x spectral energy
//  row 1: raw FFT spectrum, bins 0..127
#define AUD(x)  texelFetch(iChannel1, ivec2(x, 0), 0)

// ---------------------------------------------------------------- palette
// Six anchor inks lifted from the reference, walked as a wrapping ramp.
// A cosine palette drifts olive where R and G peak together; explicit stops
// keep the colour story exactly where the painting put it.
vec3 inkPalette(float t){
    t = fract(t) * 6.;
    vec3 c0 = vec3(.020, .050, .300);   // deep navy
    vec3 c1 = vec3(.050, .290, .880);   // cobalt
    vec3 c2 = vec3(.070, .680, .830);   // cyan
    vec3 c3 = vec3(.100, .550, .480);   // teal
    vec3 c4 = vec3(.900, .150, .580);   // magenta
    vec3 c5 = vec3(.420, .120, .820);   // violet
    vec3 c = c0;
    c = mix(c, c1, smoothstep(0., 1., t - 0.));
    c = mix(c, c2, smoothstep(0., 1., t - 1.));
    c = mix(c, c3, smoothstep(0., 1., t - 2.));
    c = mix(c, c4, smoothstep(0., 1., t - 3.));
    c = mix(c, c5, smoothstep(0., 1., t - 4.));
    c = mix(c, c0, smoothstep(0., 1., t - 5.));
    return c * .80;
}
const vec3 GOLD  = vec3(1.00, .78, .34);
const vec3 EMBER = vec3(1.00, .34, .06);

// ------------------------------------------------------------------ stars
vec2 hash22(vec2 p){
    vec3 a = fract(p.xyx * vec3(123.34, 234.34, 345.65));
    a += dot(a, a + 34.45);
    return fract(vec2(a.x * a.y, a.y * a.z));
}

// Real stellar classification, O/B through M. Colour carries temperature, so
// the field reads as a sky rather than as confetti.
vec3 starColor(float h){
    h = clamp(h, 0., 1.) * 4.;
    vec3 c = vec3(.55, .70, 1.00);                       // O/B  blue
    c = mix(c, vec3(1.00, 1.00, 1.00), smoothstep(0.,1., h - 0.));  // A  white
    c = mix(c, vec3(1.00, .95, .72), smoothstep(0.,1., h - 1.));    // G  yellow
    c = mix(c, vec3(1.00, .74, .42), smoothstep(0.,1., h - 2.));    // K  orange
    c = mix(c, vec3(1.00, .48, .34), smoothstep(0.,1., h - 3.));    // M  red
    return c;
}

// Each star is assigned its OWN FFT bin by hash, so the field is a spectrum
// analyser scattered across the sky: bass stars throb, treble stars shimmer.
float starBin(float h){
    return pow(texelFetch(iChannel1, ivec2(int(4. + h * 110.), 1), 0).x, 2.5);  // FFT copy, Buffer A row 1
}

// Depth-sliced starfield flying at the camera. Slices cycle in depth, so stars
// grow, brighten and streak radially as they pass.
vec3 starField(vec2 uv, float t, float twT, float lo, float hi, float gain){
    vec3 acc = vec3(0.);
    for(int i = 0; i < 14; i++){
        float fi = float(i);
        float d  = fract(fi / 14. + t * .045);            // 0 far -> 1 near
        if(d < lo || d > hi) continue;

        float sc   = mix(15., 1.1, d);                    // far dense, near spread
        float fade = smoothstep(0., .18, d) * smoothstep(1., .70, d);

        vec2 p  = uv * sc + vec2(fi * 31.7, fi * 17.3);
        vec2 id = floor(p);
        vec2 gv = fract(p) - .5;

        float h = hash21(id + fi * 37.1);
        if(h > .13) continue;                             // sparse — most cells empty

        vec2  o = (hash22(id + fi) - .5) * .50;
        vec2  s = gv - o;

        // radial streak: elongate along the direction of travel
        vec2  rd = normalize(uv + 1e-4);
        float st = .35 + .65 * d;
        s -= rd * dot(s, rd) * st * .55;

        float hh = hash21(id + 5.7);
        float tw = .55 + .45 * sin(twT * (1.1 + hh * 2.2) + hh * 40.);  // twinkle
        float au = starBin(hh);                                        // own bin
        float br = min((.55 + .45 * tw) * (1. + au * 3.0), 2.6);

        float sz  = .45 + 1.7 * hash21(id + 19.1);                 // size variety
        float rad = min((.010 + .022 * d) * sz * (1. + au * .35), .085);
        float g   = smoothstep(rad, 0., length(s));
        float glow= exp(-length(s) / (rad * 1.2)) * .30;
        // window the glow to zero at the cell wall — otherwise the tail is
        // clipped by fract() and the field shows its grid as bright squares
        float win = 1. - smoothstep(.36, .50, length(gv));

        vec3 sc0 = starColor(hash21(id + 11.3));
        sc0 = clamp(mix(vec3(dot(sc0, vec3(.3333))), sc0, 1.75), 0., 1.);
        acc += (sc0 * glow * 2.0 + mix(sc0, vec3(1.), .55) * g) * fade * br * gain * win;
    }
    return acc;
}

// ---------------------------------------------------------------- planets
// Lit by the nebula burst itself, so the whole frame shares one light.
vec3 planet(vec2 uv, vec2 pc, float rad, float seed, vec2 lightPos,
            float t, float aud, out float cov){
    cov = 0.;
    vec2  d  = uv - pc;
    float r2 = dot(d, d) / (rad * rad);

    vec3 atmo = starColor(fract(seed * .77)) * .5 + vec3(.15, .25, .55);

    if(r2 > 1.){                                          // atmosphere halo only
        float e = (sqrt(r2) - 1.) / .55;
        return atmo * exp(-e * 3.2) * (.30 + aud * 1.4);
    }
    cov = smoothstep(1., .985, r2);

    vec3 n = vec3(d / rad, sqrt(max(1. - r2, 0.)));

    // AXIAL TILT, then spin. Tilting the frame BEFORE taking sphere coords is
    // what makes the bands sit at an angle and the rotation read as a spin
    // about a tilted pole, instead of a texture sliding sideways.
    float tilt = (fract(seed * 2.3) - .5) * 1.15;
    vec3  nn = n;
    nn.yz = rot(tilt) * nn.yz;
    float spin = T * (.075 + fract(seed * 5.1) * .065);   // ~25-45 s, NEVER audio-warped

    // atan seam sits at nn.z<0 — the far side, unseen.
    vec2 sph = vec2(atan(nn.x, nn.z) * .55 + spin, nn.y * 1.6);
    float b  = fbm(sph * 3.2 + seed * 21.3, 5);
    b = mix(b, .5 + .5 * sin(sph.y * 7. + b * 4.), .45);  // banding

    // one persistent storm, carried around by the same spin so you can read
    // the rotation off it — bands alone are too self-similar to track
    vec2  stp = vec2(fract(sph.x * .289 + .5) - .5, nn.y - (fract(seed * 7.7) - .5) * .55);
    float storm = smoothstep(.17, .03, length(stp * vec2(2.1, 3.3)));

    vec3 base = mix(inkPalette(seed + b * .35), starColor(fract(seed * 3.1)), .30);
    base *= .55 + .85 * b;
    base = mix(base, base * vec3(1.55, .78, .55) + .06, storm * .80);
    base *= 1. - .38 * pow(abs(nn.y), 3.);              // pole darkening

    vec3  l = normalize(vec3(lightPos - pc, .55));
    float df = max(dot(n, l), 0.);
    df = pow(df, .75);                                    // soft terminator

    vec3 c = base * (.06 + 1.15 * df);
    c += atmo * pow(1. - n.z, 3.) * (.55 + aud * 1.8);     // rim / atmosphere
    c += pow(max(dot(reflect(-l, n), vec3(0, 0, 1)), 0.), 28.) * .25 * df;
    return c;
}

// ------------------------------------------------------ attractor ray warp
vec2 rayWarp(vec2 p, vec2 c, float k, float amt, float ph){
    vec2  d = p - c;
    float r = max(length(d), 1e-3);
    float s = fbm(normalize(d) * k + ph, 4) - .5;
    return c + d * (1. + s * amt * exp(-r * .9));
}

vec2 warpDomain(vec2 p, vec2 A, vec2 B, float t, float kick){
    p = rayWarp(p, A, 3.4, 2.20 + kick * 2.6, t * .05);
    p = rayWarp(p, B, 2.6, 1.30 + kick * 1.1, 11.3 - t * .04);
    vec2 q = vec2(fbm(p * 1.6 + vec2(.0, t * .05), 5),
                  fbm(p * 1.6 + vec2(5.2, 1.3 - t * .04), 5));
    vec2 r = vec2(fbm(p * 1.6 + 3.4 * q + vec2(1.7, 9.2), 5),
                  fbm(p * 1.6 + 3.4 * q + vec2(8.3, 2.8), 5));
    return p + 1.15 * r;
}

float speckle(vec2 p, float density, float size){
    vec2  id = floor(p);
    vec2  gv = fract(p) - .5;
    if(hash21(id) > density) return 0.;
    vec2  o  = (vec2(hash21(id + 3.1), hash21(id + 7.7)) - .5) * .7;
    float rr = size * (.35 + .9 * hash21(id + 13.3));
    return smoothstep(rr, rr * .25, length(gv - o));
}

void mainImage(out vec4 O, in vec2 F){
    vec2 R  = iResolution.xy;
    vec2 uv = (2. * F - R) / R.y;

    vec4  a0 = AUD(0), a1 = AUD(1);
    float snd   = AUD(2).x;
    float kick  = a1.x, snare = a1.y, mid = a1.z, high = a1.w;
    float pulse = a0.y;                // 1 on a kick onset, decays ~200 ms
    float hue   = a0.z;                // palette offset, one step per kick

    // Two clocks, deliberately.  The INK clock is audio-warped (ArthurTent's
    // iAmplifiedTime) so the pour surges on the beat.  The FLIGHT clock stays
    // near-steady: putting the same jump into star depth teleported them
    // between slices every transient, which is what read as bouncing.
    float aTime = a0.x;                // integrated in Buffer A: never rewinds
    float t     = aTime * .5;
    float fly   = T * 1.05 + snd * .55;
    float twT   = T;                          // twinkle: never audio-warped

    // ---------------------------------------------------------- camera
    // Mouse looks around; released, it drifts on its own. A real pinhole ray,
    // then a gnomonic projection back to 2D — so the whole scene, nebula
    // included, pans and stretches the way a view should.
    // camT is deliberately NOT the ink clock. Driving the camera from the
    // audio-warped clock turns a slow look-around into a shake on every
    // transient — the drift reads as camera judder, not as looking.
    float camT  = T;
    float yaw   = .38 * sin(camT * .105) + .13 * sin(camT * .041 + 2.1);
    float pitch = .17 * sin(camT * .073 + 1.7);
    if(iMouse.z > 0.){
        vec2 m = (2. * iMouse.xy - R) / R;
        yaw   =  m.x * 1.15;
        pitch = -m.y * .70;
    }
    vec3 rd = normalize(vec3(uv, 1.55));
    rd.yz *= rot(pitch);
    rd.xz *= rot(yaw);

    // STEREOGRAPHIC, not gnomonic.  rd.xy/rd.z blows up as rd.z -> 0 and
    // smears the ink into horizontal streaks at the edge of a wide look.
    // rd.xy/(rd.z+1) is conformal: it stretches scale but never shears, so
    // the pour stays locally undistorted however far you turn, and it stays
    // finite at 90 degrees so no clamp is needed.
    // World +z (the direction of travel) still maps to sky = (0,0), so the
    // star streaks converge on the true velocity vector for free — look
    // sideways and the vanishing point slides off-centre as it should.
    vec2 sky = rd.xy / (rd.z + 1.) * 2.30;
    sky *= 1. - .10 * sin(camT * .04);           // slow drift toward / away

    // ---------------------------------------------------------- nebula
    vec2 A = vec2(.62, .12) + .06 * vec2(cos(t * .21), sin(t * .17));
    vec2 B = vec2(-.78, -.42) + .05 * vec2(cos(t * .13 + 2.), sin(t * .19 + 1.));

    vec2  q  = warpDomain(sky, A, B, t, kick);
    float rA = length(sky - A), rB = length(sky - B);
    float heat = (.55 + kick * .45) / (.30 + rA * rA)
               + (.22 + mid  * .25) / (.45 + rB * rB);

    float conc = .10 + .90 * exp(-rA * .62) + .34 * exp(-rB * .90);
    float dens = smoothstep(.34, .64, fbm(q * .85 + 12., 4)) * clamp(conc, 0., 1.);

    // ---- deep space + far stars, BEHIND the ink
    vec3 col = mix(vec3(.004, .006, .026), vec3(.010, .022, .070), fbm(sky * 1.1 + 4., 4));
    col += starField(sky, fly, twT, 0., .62, 1.0);
    col += vec3(.30, .15, .05) * (.030 + kick * .05) / (.06 + rA * rA);
    col += vec3(.09, .05, .20) * (.022 + mid  * .05) / (.10 + rB * rB);

    // ---- the ink sheets
    for(int i = 0; i < LAYERS; i++){
        float fi = float(i);

        vec2 lp = q * (1. + fi * .22) + fi * 17.31;
        lp = rot(fi * 1.31 + t * .012) * lp;
        lp += .40 * vec2(fbm(lp * .7 + fi, 3), fbm(lp * .7 + fi + 20., 3));

        float f = fbm(lp * 1.05, 5);

        float th = .552 + .074 * sin(fi * 2.39 + 1.1) + .022 * sin(t * .11 + fi);
        th += .052 * (fbm(lp * 5.2 + 7., 4) - .5) * 2.;
        th -= snare * .075;

        float w = max(fwidth(f), 2e-4) * 1.1;
        float e = f - th;
        float a = smoothstep(-w, w, e);

        vec3 c = inkPalette(f * .95 + fi * .137 + t * .012 + hue);
        c = mix(c, EMBER, smoothstep(.70, 2.00, heat) * .74);

        vec2  g = vec2(dFdx(f), dFdy(f));
        vec3  n = normalize(vec3(-g * 24., 1.));
        vec3  l = normalize(vec3(A - sky, .55));
        c += pow(max(dot(n, l), 0.), 30.) * (.30 + high * .9) * mix(vec3(1.), GOLD, .5);
        c *= 1. + .32 * pow(1. - max(n.z, 0.), 3.);

        float bandE = exp(-abs(e) / (w * 3.0));
        float ins   = step(0., e);
        c *= 1. - .55 * bandE * ins;

        float cover = a * (.74 - fi * .055) * dens;
        col = mix(col, c, cover);
        col += bandE * (1. - ins) * c * 2.1 * (.30 - fi * .028)
                     * (.12 + .88 * dens) * (1. + high * 1.6);
    }

    float vf   = fbm(q * 2.1 + 31.7, 5);
    float vw   = max(fwidth(vf), 2e-4) * 2.0;
    float vein = smoothstep(vw, 0., abs(fract(vf * 7.) - .5) - .040);
    float vmask= smoothstep(.48, .74, fbm(sky * .9 + 60., 4));
    col = mix(col, GOLD * (1.30 + high * 1.4), vein * vmask * .88);

    float smask = .30 + .70 * smoothstep(.42, .74, fbm(sky * 1.3 + 90., 4));
    col += GOLD * (1. + high * 2.6)
         * (speckle(sky *  9. +  5., .20, .100) * 2.20
          + speckle(sky * 19. + 17., .14, .120) * 1.30
          + speckle(sky * 34. + 31., .09, .150) *  .80) * smask;

    // ---- planets, in front of the ink, lit by the burst
    for(int i = 0; i < 3; i++){
        float fi = float(i);
        float sd = .17 + fi * .29;
        float pz = fract(fi * .37 + fly * .020);
        float rad= mix(.012, .40, pz * pz);
        float vis= smoothstep(0., .12, pz) * smoothstep(1., .80, pz);

        vec2 dir = vec2(cos(sd * 31.7), sin(sd * 47.3));
        vec2 pc  = dir * (.20 + pz * 1.55)
                 + vec2(sin(camT * .07 + fi) * .06, cos(camT * .05 + fi) * .05);

        float aud = (i == 0) ? kick : ((i == 1) ? mid : high);
        float cov;
        vec3  pcol = planet(sky, pc, rad, sd, A, camT, aud, cov);
        col = mix(col, pcol, cov * vis);
        col += pcol * (1. - cov) * vis;
    }

    // ---- near stars streaking past, IN FRONT of everything
    col += starField(sky, fly, twT, .62, 1., 1.35);

    col += EMBER * min(.0040 / (.0011 + rA * rA * rA), 1.15) * (1. + kick * 2.0 + pulse * 1.5);
    col += vec3(.50, .26, .82) * min(.005 / (.0090 + rB * rB * rB), 1.0) * (1. + mid * 2.5);

    // ---- post. vignette stays in SCREEN space, not sky space.
    vec2 vn = F / R;
    col *= .40 + .60 * pow(16. * vn.x * vn.y * (1. - vn.x) * (1. - vn.y), .16);
    col  = 1. - exp(-col * (1.00 + snd * .5));
    col  = mix(vec3(dot(col, vec3(.299, .587, .114))), col, 1.30 + mid * .5 + pulse * .25);
    col  = pow(max(col, 0.), vec3(1.07));
    col  = pow(max(col, 0.), vec3(.4545));
    col += (hash21(F + fract(T)) - .5) * .014;

    O = vec4(col, 1.);
}
