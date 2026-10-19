// "Tentacle Skull Quartet" : four scenes, one shader. Image tab.
// iChannel0 = Buffer A (only needed with AUDIO_REACTIVE 1)

#define XFADE 1.15        // ring-wipe duration in seconds
#define ZERO min(iFrame, 0)   // non-constant loop start: stops the compiler unrolling/inlining map() dozens of times

// ---------- frame globals ----------
int   gScene;
float gT, gTwist, gPivot, gPx, gPy, gSwell, gBeat, gBass, gMid, gHigh, gHue, gRot;
float gBound, gPix;
vec3  gRo;
bool  gEyes, gBnd;

// ---------- closest-candidate record ----------
float bD, bW, bM, bS, bU;
vec2  bUV;
vec4  gHex;

float spec(float x){
#if AUDIO_REACTIVE
    return texelFetch(iChannel0, ivec2(int(clamp(x, 0., 1.)*63.), 1), 0).x;
#else
    return .35 + .15*sin(x*9. - gT*2.);
#endif
}

// ---------- skull, unit size, faces -z ----------
float sdSkull(vec3 p, out float m){
    p.x = abs(p.x);
    float d = sdEllipsoid(p - vec3(0, .22, .1), vec3(.86, .8, .9));
    d = smin(d, sdEllipsoid(p - vec3(0, -.28, -.24), vec3(.62, .5, .58)), .25);
    d = smin(d, sdEllipsoid(p - vec3(.42, -.22, -.42), vec3(.22, .15, .2)), .12);
    d = smin(d, sdEllipsoid(p - vec3(0, -.74, -.3), vec3(.38, .25, .42)), .14);
    d = smax(d, -sdEllipsoid(p - vec3(.6, -.5, -.3), vec3(.2, .22, .4)), .12);
    d = smax(d, -sdEllipsoid(p - vec3(.3, -.06, -.74), vec3(.24, .21, .32)), .05);
    d = smax(d, -sdEllipsoid(p - vec3(0, -.37, -.8), vec3(.1, .15, .26)), .03);
    vec3 mq = p - vec3(0, -.69, -.6);
    d = max(d, -max(max(mq.x - .3, abs(mq.y) - .012), abs(mq.z) - .3));
    m = 0.;
    if(gEyes){
        float ball = length(p - vec3(.3, -.06, -.6)) - .15;
        if(ball < d){ d = ball; m = 1.; }
    }
    return d;
}

// skull candidate. mb = surface material for bone (0 beads, 1 lattice)
void skullC(vec3 p, float sc, float slot, float mb){
    vec3 q = p/sc;
    if(gBnd && (length(q) - 1.3)*sc >= bD) return;     // bounding sphere: can't beat the current best
    float m, d = sdSkull(q, m)*sc;
    if(d >= bD) return;
    vec3 a = vec3(abs(q.x), q.yz);
    bD = d; bS = slot; bU = .5;
    if(m > .5){ bM = 2.; bUV = (a.xy - vec2(.3, -.06))*14.; bW = .02*sc; }
    else if(a.y < -.55 && a.y > -.88 && q.z < -.42 && a.x < .3){ bM = 3.; bUV = vec2(a.x*13., a.y); bW = .08*sc; }
    else {                                           // texture pole tilted to the back of the head
        vec2 yz = q.yz*mat2(.94, .34, -.34, .94);
        bM = mb; bUV = vec2(atan(a.x, -yz.y), yz.x/.8)*(mb > .5 ? 4.6 : 5.6); bW = (mb > .5 ? .17 : .14)*sc;
    }
}

// arc tentacle in the local xy plane around the origin. span < 0 = clockwise.
// R = arc radius start/end (spiral when they differ), r = tube radius start/end, N = cells around
// 3D twist: the tip slowly lifts out of the arc plane, and the skin rolls and winds about the tube axis.
// Both ride on ph, so wob = 0, ph = 0 (the mandala halo) stays still. No lift in the tunnel: its kaleido folds would clip it.
// sp: the neon skull and tunnel arms twist 35% further and faster than the mandala's.
void tentC(vec3 p, float a0, float span, vec2 R, vec2 r, float wob, float ph, float N, float m, float slot){
    // bound: thickened annulus that contains the whole tube (z slab covers the wobble plus the tip lift)
    float rm = max(r.x, r.y), sp = gScene == 0 ? 1. : 1.35, lf = gScene < 3 ? 2.5*sp : 0.;
    vec2 bb = vec2(abs(length(p.xy) - (R.x + R.y)*.5) - abs(R.x - R.y)*.5 - wob*.35, abs(p.z) - wob*(1. + lf));
    if(gBnd && length(max(bb, 0.)) - rm >= bD) return;
    if(span < 0.){ p.y = -p.y; a0 = -a0; span = -span; }
    float g = (TAU - span)*.5;
    float a = mod(atan(p.y, p.x) - a0 + g, TAU) - g;
    float s = clamp(a/span, 0., 1.);
    float an = a0 + s*span;
    float RR = mix(R.x, R.y, s) + wob*.35*sin(s*7. + ph*1.3);
    vec2 dir = vec2(cos(an), sin(an));
    vec3 q = vec3(p.xy - dir*RR, p.z - wob*(sin(s*4.5 + ph) + lf*s*s*sin(ph*sp*.4)));
    float rr = mix(r.x, r.y, s);
    float d = length(q) - rr;
    if(d >= bD) return;
    float k = TAU/N, L = span*(R.x + R.y)*.5;
    float along = abs(r.x - r.y) > 1e-3 ? L/(k*(r.x - r.y))*log(r.x/rr) : L*s/(k*r.x);
    bD = d; bM = m; bS = slot; bU = s; bW = k*rr;
    along += dot(q.xy, vec2(-dir.y, dir.x))/(k*rr);  // keeps the cells going over the end caps
    float roll = sp*(ph*.3 + s*1.2*sin(ph*sp*.55));   // slow spin + wind/unwind toward the tip (no mod(): it adds seconds to the D3D compile)
    bUV = vec2((atan(q.z, dot(q.xy, dir)) + roll)/k, along);
}

// height of the surface relief, 0..1
float bump(vec4 h, float m, vec2 uv){
    float e = h.x, c = h.y;
    if(m < .5){                                   // dome beads (clip 03)
        return .8*sqrt(max(0., 1. - c*c*5.)) + .2*smoothstep(0., .06, e);
    } else if(m < 1.5){                           // lattice with round holes (clip 04/05)
        return smoothstep(.17, .3, c) - .3*smoothstep(.06, 0., e);
    } else if(m < 2.5){                           // eye orb
        return 0.;
    } else if(m < 3.5){                           // teeth
        float t = abs(fract(uv.x) - .5);
        return (1. - smoothstep(.3, .5, t))*smoothstep(.0, .025, abs(uv.y + .69));
    }
    // suction cups (clip 02)
    return .9*sqrt(max(0., 1. - c*c*5.)) - .45*smoothstep(.2, .05, c);
}

// ---------- scenes ----------
void mapMandala(vec3 p){
    vec3 q = vec3(abs(p.x), p.yz);
    float ph = gT*.55;
    skullC(p - vec3(0, .58, -.05), .48, 0., 0.);
    vec3 b = p - vec3(0, -.48, -.12);
    float d = sdEllipsoid(b, vec3(.5, .4, .36));
    if(d < bD){ bD = d; bM = 4.; bS = 1.; bU = .3; bW = .12; bUV = vec2(atan(abs(b.x), -b.z)*1.25, b.y*1.9)*4.2; }
    tentC(q - vec3(1., .35, .15), PI, -4.4, vec2(.66, .28), vec2(.17, .05), .1, ph, 8., 4., 1.);
    tentC(q - vec3(.85, -.58, -.25), PI*.5, -4.2, vec2(.5, .22), vec2(.15, .04), .08, ph + 1.7, 8., 4., 0.);
    tentC(q - vec3(.62, 1.08, .3), -PI*.5, 3.8, vec2(.45, .2), vec2(.13, .035), .08, ph + 3.1, 7., 0., 2.);
    tentC(q - vec3(.42, -1.18, -.35), PI*.5, -3.6, vec2(.4, .18), vec2(.14, .04), .07, ph + 4.2, 8., 4., 1.);
    tentC(q - vec3(1.6, -.15, .45), PI*.8, -4.6, vec2(.62, .25), vec2(.13, .035), .1, ph + 5.3, 7., 4., 2.);
    tentC(q - vec3(.55, .3, -.15), PI*.85, -4., vec2(.32, .14), vec2(.1, .03), .05, ph + 2.4, 7., 0., 2.);
    tentC(q - vec3(.95, 1.25, .4), PI*1.1, -4.4, vec2(.38, .15), vec2(.11, .03), .06, ph + .8, 7., 4., 1.);
    tentC(p - vec3(0, .58, .6), -PI*.5, TAU, vec2(.92), vec2(.05), 0., 0., 5., 0., 2.);
}

void mapNeon(vec3 p){
    vec3 q = vec3(abs(p.x), p.yz);
    float ph = gT*.5;
    skullC(p, .62, 0., 0.);
    // hex-tube surround
    vec3 s = p - vec3(0, 0, 1.5);
    float ls = length(s), d = 7.5 - ls;
    if(d < bD){ bD = d; bM = 1.; bS = 1.; bU = .5; bW = .47; bUV = vec2(atan(abs(s.x), s.z), asin(clamp(s.y/ls, -1., 1.)))*16.; }
    // flared pillars behind the skull. Their skin rolls and wrings about the upright axis at the neon arms' pace
    float y = clamp(q.y, -2.6, 1.8);
    vec3 c = q - vec3(1.32 + .1*sin(y*1.7 + ph*1.6), y, .95 + .1*cos(y*1.3 + ph));
    float pr = .3 + .5*smoothstep(-.8, -2.6, y);
    d = length(c) - pr;
    if(d < bD){ bD = d; bM = 1.; bS = 1.; bU = .5; bW = TAU*pr/12.; bUV = vec2((atan(c.z, c.x) + ph*.4 + .45*y*sin(ph*.74))/TAU*12., q.y/(TAU*.3/12.)); }
    tentC(q - vec3(2.28, .7, .95), PI, -3.5, vec2(1., .72), vec2(.31, .1), .1, ph, 10., 0., 2.);
    tentC(q - vec3(1.35, 1.38, -.45), PI, -3., vec2(.75, .5), vec2(.22, .08), .12, ph + 1., 9., 0., 2.);
    vec3 v = q - vec3(1.32, -.8, -.9);
    tentC(v.xzy, PI*.95, 3.9, vec2(.95, .55), vec2(.25, .08), .12, ph + 2., 10., 0., 0.);
    v = q - vec3(.62, -1.1, -1.45);
    tentC(v.xzy, PI, 3.5, vec2(.75, .45), vec2(.27, .1), .1, ph + 3., 10., 0., 3.);
}

void mapWall(vec3 p){
    const vec2 C = vec2(1.8, 1.95);
    float row = floor(p.y/C.y + .5);
    p.x += mod(row, 2.)*C.x*.5;
    float col = floor(p.x/C.x + .5);
    vec3 l = vec3(p.x - col*C.x, p.y - row*C.y, p.z);
    float h = hash21(vec2(col, row));
    gBound = max(min(C.x*.5 - abs(l.x), C.y*.5 - abs(l.y)) + .1, p.z - 1.);   // neighbours sit at least .1 past the cell edge
    l.xz *= rot(.12*sin(gT*.45 + h*TAU));
    l.yz *= rot(.08*sin(gT*.37 + h*9.));
    skullC(l, .82, floor(h*4.), 1.);
}

void mapTunnel(vec3 p){
    float r = length(p.xy);
    const float SEG = TAU/6.;
    float a = atan(p.y, p.x);
    float ia = floor(a/SEG);
    a = abs(mod(a, SEG) - SEG*.5);
    vec2 l = vec2(cos(a), sin(a))*r;
    float iz = floor(p.z/3.2), zc = p.z - iz*3.2 - 1.6;
    float d = 2.9 - r;
    if(d < bD){ bD = d; bM = 1.; bS = 1.; bU = .5; bW = .38; bUV = vec2(a*2.9, p.z)/.38; }
    float ph = gT*.6 + iz*1.7;
    float sl = mod(iz + ia, 2.);
    vec3 t3 = vec3(l.x - 1.85, zc, l.y);
    t3.yz *= rot(.85);
    tentC(t3, 0., 4.4, vec2(1.0, .45), vec2(.36, .08), .12, ph, 10., 0., sl*3.);
    float iz2 = floor(p.z/3.2 + .5), zc2 = p.z - iz2*3.2;
    t3 = vec3(l.x - 1.55, zc2, l.y);
    t3.yz *= rot(-.7);
    tentC(t3, 0., -4., vec2(.95, .4), vec2(.28, .07), .12, ph + 2.5, 9., 1., 3. - sl*3.);
}

float map(vec3 p){
    bD = 1e9; gBound = 1e9;
    if(gTwist != 0.){ vec2 o = vec2(gPx, gPy); p.xy = (p.xy - o)*rot(gTwist*(p.z - gPivot)) + o; }
    gEyes = gScene != 2;
    gBnd = gScene < 2;                                     // bounds only pay off in the busy scenes
    if(gScene == 0) mapMandala(p);
    else if(gScene == 1) mapNeon(p);
    else if(gScene == 2) mapWall(p);
    else mapTunnel(p);
    gHex = hexCell(bUV);
    float lod = smoothstep(2., 6., bW/(gPix*length(p - gRo)));
    return min(bD - bW*.22*gSwell*lod*bump(gHex, bM, bUV), gBound);
}

// ---------- palettes: neon body/accent pairs pulled from the four clips ----------
const vec3 PB[6] = vec3[6](vec3(.2, 1., .35), vec3(.36, .3, 1.), vec3(.25, .85, 1.), vec3(.6, 1., .1), vec3(.85, .2, 1.), vec3(.15, .35, 1.));
const vec3 PA[6] = vec3[6](vec3(1., .12, .9), vec3(.1, 1., .85), vec3(.9, 1., .15), vec3(.7, .2, 1.), vec3(.1, .9, 1.), vec3(.3, 1., .3));

void palette(float slot, out vec3 body, out vec3 acc){
    float x = gHue + float(gScene == 0 ? 1 : gScene == 1 ? 0 : gScene == 2 ? 2 : 3);
    int i = int(mod(floor(x), 6.)), j = int(mod(floor(x) + 1., 6.));
    float f = smoothstep(0., 1., fract(x));
    body = mix(PB[i], PB[j], f);
    acc  = mix(PA[i], PA[j], f);
    if(slot > 2.5){ vec3 t = body; body = acc*.85; acc = t; }        // swapped pair
    else if(slot > 1.5){ body = hue(body, -.5); acc = hue(acc, .4); }
    else if(slot > .5) body = hue(body, .45);
}

// ---------- backgrounds ----------
float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3. - 2.*f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + 1.), f.x), f.y);
}
vec3 nebula(vec3 rd){
    vec2 p = rd.xy/rd.z*2.2 + vec2(gT*.02, 0);
    float n = 0., a = .55;
    for(int i = 0; i < 5; i++){ n += a*vnoise(p); p = p*2.03*mat2(.8, .6, -.6, .8) + 7.1; a *= .5; }
    n = smoothstep(.42, .95, n);
    vec3 c = mix(vec3(.12, .08, .5), vec3(.75, .4, 1.), n*n)*n*1.2;
    vec2 sp = rd.xy/rd.z*90.;
    float st = hash21(floor(sp));
    c += smoothstep(.985, 1., st)*(1. - smoothstep(.0, .35, length(fract(sp) - .5)))*(.6 + 2.*gHigh);
    vec3 pb, pa; palette(1., pb, pa);
    return c*normalize(pb + .3)*1.7;
}

vec3 sceneBg(vec3 rd){
    if(gScene == 0) return nebula(rd);
    return vec3(0);
}

// ---------- shading ----------
vec3 shade(vec3 p, vec3 n, vec3 rd, float ao){
    vec3 body, acc;
    palette(bS, body, acc);
    float lod = smoothstep(1.5, 5., bW/(gPix*length(p - gRo)));
    float e = mix(.2, gHex.x, lod), c = mix(.3, gHex.y, lod);
    float cid = hash21(gHex.zw);
    vec3 L = normalize(vec3(-.45, .65, -.8));
    float dif = max(dot(n, L), 0.);
    float fr = 1. - max(dot(n, -rd), 0.); fr *= fr*fr;
    float sp = max(dot(reflect(rd, n), L), 0.); sp *= sp; sp *= sp; sp *= sp; sp *= sp; sp *= sp;
    vec3 base = body, emi = vec3(0);
    float pulse = gScene == 2 ? .4 + .6*gHigh : .5*gMid + .6*spec(bU*.8);

    if(bM < .5){                                         // beads with a jewel centre
        float j = 1. - smoothstep(.1, .2, c);
        base = mix(body, acc, j*.9);
        base *= .35 + .65*smoothstep(0., .08, e);
        emi = acc*j*(.25 + 1.2*pulse);
    } else if(bM < 1.5){                                 // lattice, the hole glows
        float hole = 1. - smoothstep(.14, .26, c);
        base = mix(body, acc*.6, hole);
        emi = acc*hole*(.15 + .6*pulse)*(.6 + .4*cid);
    } else if(bM < 2.5){                                 // eyes: little mandala orbs
        float r = length(bUV);
        float ring = .5 + .5*cos(r*9. - gT*3.);
        base = mix(acc, body, ring*.6);
        emi = acc*(.8 + 2.5*gBass + 1.5*gBeat)*(1. - smoothstep(.6, 1.6, r)*.5);
    } else if(bM < 3.5){                                 // teeth
        base = mix(body, vec3(1), .25);
    } else {                                             // suction cups
        float ring = smoothstep(.2, .26, c)*(1. - smoothstep(.3, .38, c));
        float cup = 1. - smoothstep(.12, .2, c);
        base = mix(body, acc, max(ring, cup*.7));
        base *= .35 + .65*smoothstep(0., .08, e);
        emi = acc*(cup*.6 + ring*.3)*(.2 + 1.1*pulse);
    }
    if(gScene == 3 && bS == 1.) base *= .45;                // darker tunnel wall so the tentacles pop
    vec3 col = base*(.22 + .95*dif)*ao + emi;
    col += sp*mix(vec3(1), acc, .3)*(.7 + gHigh);
    col += fr*body*.55*ao;
    return col;
}

// ---------- camera + parallax ----------
vec4 parallaxWeights(){
#if PARALLAX_MODE > 0
    return vec4(equal(ivec4(1, 2, 3, 4), ivec4(PARALLAX_MODE)));
#else
    float x = iTime/PARALLAX_LEN;
    float i = mod(floor(x), 4.), f = smoothstep(.65, 1., fract(x));
    vec4 w = vec4(0);
    w[int(i)] = 1. - f;
    w[int(mod(i + 1., 4.))] += f;
    return w;
#endif
}

vec3 render(int sc, vec2 uv){
    gScene = sc;
    vec4 w = parallaxWeights();
    float pt = gT*.8;
    vec3 ro, ta; float fo;
    if(sc == 0){ ro = vec3(0, .05, -6.2); ta = vec3(0, .1, 0); fo = 2.15; }
    else if(sc == 1){ ro = vec3(0, .1, -3.9); ta = vec3(0, -.02, 0); fo = 1.9; }
    else if(sc == 2){ ta = vec3(pt*.16, pt*.05, 0); ro = ta + vec3(0, 0, -6.6); fo = 2.1; }
    else { ro = vec3(0, 0, gT*1.05); ta = ro + vec3(0, 0, 4); fo = 1.25; }

    // 1 source sway, always a little on
    ro += vec3(sin(pt*.31), sin(pt*.23)*.6, 0)*(.06 + .06*w.x);
    // 2 orbit drift: near things swing past far things
    vec3 off = ro - ta;
    float yaw = w.y*.42*sin(pt*.21), pit = w.y*.18*sin(pt*.17 + 1.);
    if(sc == 3){ ro.xy += w.y*vec2(cos(pt*.3), sin(pt*.37))*.35; }
    else { off.xz *= rot(yaw); off.yz *= rot(pit); ro = ta + off; }
    // 3 dolly breathe (vertigo): subject keeps its size, depth stretches
    float k = 1. + w.z*.42*sin(pt*.27);
    ro = ta + (ro - ta)*k; fo *= k;
    // 4 depth twist: helix through z
    gTwist = w.w*.14*sin(pt*.19);
    gPivot = sc == 3 ? ro.z : 0.; gPx = ta.x; gPy = ta.y;
    fo *= 1. + .07*gBeat;                                   // punch-in on the kick

    float roll = sc == 3 ? gRot*1.2 : .07*sin(gRot*1.7);
    vec3 fw = normalize(ta - ro), rt = normalize(cross(vec3(sin(roll), cos(roll), 0), fw)), up = cross(fw, rt);
    vec3 rd = normalize(uv.x*rt + uv.y*up + fo*fw);
    gRo = ro; gPix = 1./(fo*iResolution.y);

    // ONE map() call site for the whole pixel: phase 0 marches, 1-4 normal taps, 5-6 AO taps, 7 material lookup.
    // Same maths as separate loops, but the D3D compiler inlines the scenes once instead of four times.
    float t = .1, d = 1e9, e = 0., ao = 0.;
    vec3 p = ro, n = vec3(0), nacc = vec3(0);
    int ph = 0, mi = 0;
    bool hit = false;
    for(int i = ZERO; i < 117; i++){
        vec3 k = vec3(0), sp = p;
        if(ph == 0) sp = ro + rd*t;
        else if(ph < 5){ int j = ph - 1; k = 2.*vec3((((j + 3) >> 1) & 1), ((j >> 1) & 1), (j & 1)) - 1.; sp = p + k*e; }
        else if(ph < 7) sp = p + n*(ph == 5 ? .07 : .3);
        float dd = map(sp);
        if(ph == 0){
            d = dd;
            bool done = d < .0006*t || t > 28.;
            if(!done){ t += d*.72; done = ++mi >= 110; }
            if(done){
                if(t > 28. || d > .02*t) break;                // missed, or never converged
                hit = true; p = ro + rd*t; e = .0012*t; ph = 1;
            }
        }
        else if(ph < 5){ nacc += k*dd; if(ph == 4) n = normalize(nacc); ph++; }
        else if(ph < 7){ ao += .5*dd/(ph == 5 ? .07 : .3); ph++; }
        else break;                                             // phase 7 left the hit's material in the globals
    }
    vec3 bg = sceneBg(rd);
    if(!hit) return bg;
    ao = clamp(ao, 0., 1.);
    ao = .2 + .8*ao*ao;
    vec3 col = shade(p, n, rd, ao);
    float fog = sc == 3 ? exp(-t*.2) : sc == 1 ? exp(-max(t - 6., 0.)*.12) : exp(-max(t - 7., 0.)*.25);
    vec3 fc = sc == 3 ? vec3(0) : sc == 0 ? bg : vec3(0);
    return mix(fc, col, fog);
}

void mainImage(out vec4 O, in vec2 F){
    vec2 uv = (F - .5*iResolution.xy)/iResolution.y;

#if AUDIO_REACTIVE
    vec4 a0 = texelFetch(iChannel0, ivec2(0, 0), 0);
    vec4 a1 = texelFetch(iChannel0, ivec2(1, 0), 0);
    vec4 a2 = texelFetch(iChannel0, ivec2(2, 0), 0);
    gBass = a0.x; gMid = a0.y; gHigh = a0.z; gBeat = a0.w;
    gT = a1.x; gHue = a1.y; gRot = a1.z;
    float cur = a2.x, prv = a2.y, sw = a2.z;
#else
    gBass = .3; gMid = .3; gHigh = .2; gBeat = 0.;
    gT = iTime; gRot = iTime*.08;
  #if SCENE > 0
    float cur = float(SCENE - 1), prv = cur, sw = -99.;
  #else
    float idx = floor(iTime/SCENE_LEN);
    float cur = mod(idx, 4.), prv = mod(idx + 3., 4.), sw = idx*SCENE_LEN;
  #endif
    float hx = iTime/6.;
    gHue = floor(hx) + smoothstep(.8, 1., fract(hx));
#endif
    gSwell = 1. + .5*gBeat;

    // ring wipe from the centre, launched by the kick that switched scenes
    float pr = clamp((iTime - sw)/XFADE, 0., 1.);
    float R = pow(pr, .6)*1.25, band = .045;
    float rr = length(uv);
    float wc = pr >= 1. ? 1. : 1. - smoothstep(R - band, R + band, rr);   // weight of the new scene
    vec3 col = vec3(0);
    for(int k = ZERO; k < 2; k++){                         // one render() call site; only renders what is visible
        float wk = k == 0 ? 1. - wc : wc;
        if(wk > 0.) col += wk*render(int(k == 0 ? prv : cur), uv);
    }
    if(pr < 1.){
        vec3 b, a;
        gScene = int(cur); palette(1., b, a);
        col += (a + .4)*exp(-abs(rr - R)*28.)*(1. - pr)*1.4;
    }

    col *= 1. + .2*gBeat;
    col = 1. - exp(-col*1.25);
    col *= 1. - .35*dot(uv*.85, uv*.85);
    O = vec4(pow(col, vec3(.95)), 1);
}
