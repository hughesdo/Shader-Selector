// "Gilded Mirror Forest" : three scenes, one shader. Image tab.
// iChannel0 = Buffer A (only needed with AUDIO_REACTIVE 1)

#define XFADE 1.3             // ring-wipe duration in seconds
#define ZERO min(iFrame, 0)   // non-constant loop start: keeps the layer loops rolled up (fast compile on ANGLE/D3D)

const mat2 M2 = mat2(1.6, 1.2, -1.2, 1.6);
float fbm(vec2 p){ float s = 0., a = .5; for(int i = ZERO; i < 4; i++){ s += a*noise(p); p = M2*p; a *= .5; } return s/.9375; }
float ridge(vec2 p){ float s = 0., a = .5; for(int i = ZERO; i < 5; i++){ s += a*(1. - abs(2.*noise(p) - 1.)); p = M2*p; a *= .5; } return s/.96875; }

// ---------- frame globals ----------
float gT, gBeat, gBass, gMid, gHigh, gRot, gPx, gFlash;
vec3  gW;      // parallax weights for modes 2, 3, 4 (mode 1 = all zero)
mat3  gHM;     // accent hue rotation, hops on every kick

float spec(float x){
#if AUDIO_REACTIVE
    return texelFetch(iChannel0, ivec2(int(clamp(x, 0., 1.)*63.), 1), 0).x;
#else
    return .35 + .15*sin(x*9. - gT*2.);
#endif
}

// neon set from clip 12: magenta, violet, blue, with green and gold sparks
vec3 neonPal(float x){
    float t = abs(2.*fract(x) - 1.);
    float h = .87 - .51*t*t;                                                     // mostly magenta/violet/blue, now and then green
    return gHM*clamp(abs(mod(h*6. + vec3(0, 4, 2), 6.) - 3.) - 1., 0., 1.);
}

// ---------- shared layer camera ----------
vec2 path(float z){ return vec2(sin(z*.55)*1.1 + sin(z*.23)*.6, cos(z*.41)*.5); }
vec2 dpath(float z){ return vec2(cos(z*.55)*.605 + cos(z*.23)*.138, -sin(z*.41)*.205); }

// screen uv -> plane coords of a layer at view depth z (camera at path position c)
vec2 cam2D(vec2 uv, float z, float c, vec2 sway){
    vec2 p = uv*z + sway;                                                        // sway = camera position: near layers slide more
    if(gW.x > 0.) p += gW.x*(path(c + z) - path(c) - z*dpath(c));                // 2 curving drift: the way ahead bends
    if(gW.y > 0.) p *= rot(gW.y*z*(.5 + .25*sin(gT*.17)));                      // 3 helix twist through depth
    return p;
}

// ---------- voronoi borders: distance to the nearest cell edge, edge normal, position along it, next edge ----------
float vorEdge(vec2 x, out vec2 e, out float al, out float d2){
    vec2 n = floor(x), f = fract(x), mr = vec2(0), mg = vec2(0);
    float md = 8.;
    for(int j = ZERO - 1; j <= 1; j++) for(int i = -1; i <= 1; i++){
        vec2 g = vec2(i, j), r = g + hash22(n + g)*.8 + .1 - f;
        float d = dot(r, r);
        if(d < md){ md = d; mr = r; mg = g; }
    }
    md = 8.; d2 = 8.; e = vec2(1, 0); al = 0.;
    for(int j = ZERO - 1; j <= 1; j++) for(int i = -1; i <= 1; i++){
        if(i == 0 && j == 0) continue;                                           // that is the nearest point itself
        vec2 g = mg + vec2(i, j), r = g + hash22(n + g)*.8 + .1 - f, dr = r - mr;
        if(dot(dr, dr) > 1e-5){
            vec2 ee = normalize(dr), m = .5*(mr + r);
            float d = dot(m, ee);
            if(d < md){ d2 = md; md = d; e = ee; al = dot(m, vec2(-ee.y, ee.x)); }
            else d2 = min(d2, d);
        }
    }
    return md;
}

// F1, F2 cellular distances in one 3x3 pass
vec2 cell2(vec2 x){
    vec2 n = floor(x), f = fract(x);
    float d1 = 8., d2 = 8.;
    for(int j = ZERO - 1; j <= 1; j++) for(int i = -1; i <= 1; i++){
        vec2 g = vec2(i, j), r = g + hash22(n + g) - f;
        float d = dot(r, r);
        if(d < d1){ d2 = d1; d1 = d; } else d2 = min(d2, d);
    }
    return sqrt(vec2(d1, d2));
}

// =====================================================================
// SCENE 1: golden filigree lattice with a lightning heart (clip 10)
// =====================================================================
vec3 filiBg(vec2 uv, vec2 sway){
    vec2 p = uv*1.4 + sway*.15;
    p *= rot(gRot*.5);
    float w = fbm(p*1.3 + vec2(gT*.012, 0));
    float n = fbm(p*1.8 + w*1.4 - vec2(0, gT*.02));
    vec3 col = mix(vec3(.006, .014, .04), vec3(.06, .18, .42), smoothstep(.3, .8, n));
    col += vec3(.12, .3, .6)*smoothstep(.62, .9, n)*.6;                          // bright blue mist pockets
    col += vec3(.0, .12, .13)*smoothstep(.55, .85, w);                           // teal haze
    // molten drips smeared downwards under the lattice
    float dr = noise(vec2(p.x*20., p.y*1.1 + gT*.03 + w));
    dr = smoothstep(.45, .95, dr)*smoothstep(.25, -.45, uv.y)*(.4 + n);
    col += dr*mix(gHM*vec3(.6, .4, .16), vec3(.12, .45, .4), noise(vec2(p.x*3., 1.)));
    return col;
}

vec3 filigree(vec2 uv){
    float c = gT*.2, fc = fract(c), fl = floor(c);
    vec2 sway = vec2(sin(gT*.11), sin(gT*.083 + 1.))*.22;
    vec2 hub = vec2(.2*sin(gT*.07), .09*sin(gT*.05 + 2.));                      // the lightning heart (screen space)
    float hr = length(uv - hub);
    vec3 gold = gHM*vec3(.95, .62, .26), elec = mix(vec3(.6, .75, 1.), gHM*vec3(.6, .75, 1.), .5);
    vec3 fogc = vec3(.03, .08, .2);
    const vec3 L = vec3(-.48, .58, .66), H = vec3(-.26, .31, .91);              // light and half vector
    float el = gFlash*exp(-hr*6.5);
    float sp = 1. + 1.6*spec(hr*1.3)*exp(-hr*1.5);                               // spectrum rings out from the heart

    vec3 col = vec3(0);
    float T = 1.;
    for(int i = ZERO; i < 6; i++){
        float fi = float(i), zw = fl + fi + 1.;
        float z = (fi + 1. - fc)*.8;
        z += gW.z*.3*sin(zw*1.1 - gT*.9);                                       // 4 accordion breathe
        float vis = smoothstep(.06, .35, z)*smoothstep(4.8, 3.7, z);
        if(vis <= 0.) continue;
        vec2 p = cam2D(uv, z, c, sway)*rot(gRot);
        vec2 q = p*2.6 + hash22(vec2(zw, 7.))*40.;
        q += (vec2(noise(q*.45), noise(q*.45 + 17.)) - .5)*1.1;                   // organic, wobbly cells
        float pxw = max(gPx*z*2.6, 1e-4);

        float m = noise(q*.22 + zw*3.1);
        float web = smoothstep(.42, .55, m), bs = .75 + .7*smoothstep(.55, .9, m);   // fatter beads deep in a web
        float lod = smoothstep(.015, .05, pxw);                                  // far: beads fade to their average
        float a = web*.2, d = 1.;
        vec3 lc = gold*.35;
        if(lod < 1. && web > 0.){                                                // the lattice only where it can show
            vec2 e; float al, d2;
            float md = vorEdge(q, e, al, d2);
            // beads strung on wire, bigger knots where edges meet
            float bl = (fract(al/(.09*bs)) - .5)*.09*bs;
            vec2 tg = vec2(-e.y, e.x);
            float db = length(vec2(md, bl)) - .034*bs, dn = length(vec2(md, d2)) - .05*bs, dt = md - .011*bs;
            d = min(min(db, dn), dt);
            vec2 lv = (dn < min(db, dt) ? -e*md/.05 : db < dt ? (-e*md + tg*bl)/.034 : -e*md/.011)/bs;
            lv /= max(1., length(lv));
            vec3 n = vec3(lv, sqrt(max(1e-3, 1. - dot(lv, lv))));
            float df = max(dot(n, L), 0.), sh = pow(max(dot(n, H), 0.), 30.);
            vec3 sc = gold*(.1 + .9*df)*sp + vec3(1, .9, .7)*sh*1.3;
            sc = mix(sc, elec*(1.2 + 2.*sh), clamp(el*1.6, 0., 1.));            // electrified wire near the heart
            a = mix(smoothstep(pxw, -pxw, d)*web, a, lod);
            lc = mix(sc, lc, lod);
        }
        vec4 lay = vec4(lc*a, a);
        // dark solid masses behind the lace
        float fill = smoothstep(.64, .84, m)*.85;
        if(fill > 0.){                                                           // clumps of dark tarnished beads
            vec2 cb = cell2(q*4.2);
            float bb = 1. - cb.x/.75;
            vec3 fc = gold*(.025 + .22*bb*bb*bb)*smoothstep(0., .15, cb.y - cb.x)*(1. - lod*.6);
            lay = over(lay, vec4(fc*fill, fill));
        }
        // floating golden picture frames
        vec2 fq = q*.25, fid = floor(fq);
        float fh = hash21(fid + vec2(0, zw*64.));
        float fz = smoothstep(.55, 1.2, z);                                     // frames bow out before they fill the screen
        if(fh > .9 && fz > 0.){
            vec2 fo = ((fract(fq) - .5)*4. - (hash22(fid + 3.) - .5)*1.6)*rot((fh - .89)*2.5);
            float fb = sdBox(fo, vec2(.2, .28)), fr = abs(fb + .02) - .03;
            float fa = smoothstep(pxw, -pxw, fr)*fz, fin = smoothstep(pxw, -pxw, fb + .05)*.92*fz;
            float bev = clamp(1. - abs(fb + .02)/.03, 0., 1.);
            vec3 fcol = gold*(.25 + .9*bev) + vec3(1, .9, .7)*pow(bev, 8.)*.8;
            vec3 inner = vec3(.02, .04, .1) + elec*exp(-length(fo)*8.)*(.4 + gFlash)*1.5;
            lay = over(over(vec4(fcol*fa, fa), vec4(inner*fin, fin)), lay);
        }
        lay.rgb = mix(lay.rgb, fogc*lay.a, smoothstep(1.2, 4.4, z)*.75);
        lay *= vis;
        col += T*(lay.rgb + elec*el*exp(-max(d, 0.)*35.)*.35*web*vis*(1. - lod));
        T *= 1. - lay.a;
        if(T < .02) break;
    }
    if(T > .02) col += T*filiBg(uv, sway);

    // lightning bolts and the white-hot heart
    float bolt = 0.;
    if(hr < .42){
        vec2 dv = uv - hub;
        float ang = atan(dv.y, dv.x), tq = floor(gT*7.);
        float jag = noise(vec2(hr*9., tq)) - .5 + (noise(vec2(hr*25., tq + 5.)) - .5)*.45;
        bolt = exp(-abs(sin(ang*3. + jag*2.6 + tq))*hr*95.)*smoothstep(.42, .02, hr);
    }
    col += elec*(bolt*.9 + exp(-hr*13.)*1.2 + .02/(hr*hr*40. + .08))*gFlash;

    // tiny neon sparks (later in the clip), ride the highs
    vec2 sg = uv*48. + vec2(0, gT*.4);
    float sh = hash21(floor(sg) + floor(gT*2.));
    if(sh > .985) col += neonPal(sh*13.)*exp(-length(fract(sg) - .5)*9.)*(.25 + 2.*gHigh);
    return col;
}

// =====================================================================
// SCENES 2 + 3: mirror forest. st 0 = blue-gold (clip 11), st 1 = neon dark (clip 12)
// =====================================================================
vec3 forestBack(vec2 uv, float st, vec3 gold){
    float c = gT*.1;
    vec2 p = uv*(1.5 - .12*sin(gT*.045)) + vec2(0, .03*sin(gT*.07));           // slow breathing zoom like the source
    if(gW.x > 0.) p += gW.x*.25*(path(c + 6.) - path(c) - 6.*dpath(c));
    if(gW.y > 0.) p *= rot(gW.y*.35*sin(gT*.17));
    p.x = abs(p.x);
    float bar = 1.;
    if(st > .5){                                                                 // extra mirror panels with dark seams
        float P = .46, fx = mod(p.x, 2.*P);
        p.x = P - abs(fx - P);
        bar = smoothstep(0., .1, P - p.x);
    }
    float ts = gT*(1. + 2.*st);                                                  // the neon world shimmers faster
    vec2 w = vec2(fbm(p*1.7 + vec2(0, ts*.02)), fbm(p*1.7 + 5.2 - vec2(ts*.015, 0)));
    float rn = ridge(p*2.4 + w*1.3);                                             // big crystalline forms
    // crystal bubbles (clip 11) whose cell walls double as neon lace (clip 12)
    float bub = 0., wall = 1., cbx = 0.;
    for(int o = ZERO; o < 2; o++){                                               // two octaves, one cell2() call site
        float fo = float(o);
        vec2 cb = cell2(p*(10. + 17.*fo) + w*(2.5 + 2.*fo) + fo*7.3);
        bub += (1. - cb.x)*(.6 - .2*fo);
        wall = min(wall, (cb.y - cb.x)*(1. + fo));
        cbx = cb.x;
    }
    bub /= .8;
    float rf = rn*(.45 + .8*bub);
    float fib = noise(vec2(p.x*60., p.y*6.));
    // meandering veins: iso-lines of a second field
    float vf = fbm(p*3.1 + w*.8 - 3.7);
    float lf = exp(-length((p - vec2(0, .12))*vec2(1.4, 1.))*1.7);              // light pouring from behind the column
    float hl = pow(rf, 4.);
    vec3 col;
    if(st < .5){
        vec3 base = mix(vec3(.004, .012, .04), vec3(.05, .17, .44), smoothstep(.25, .85, rf))*(.35 + .65*smoothstep(0., .15, wall));
        col = base*(.5 + 1.8*lf) + vec3(.55, .82, 1.)*hl*bub*(.7 + 3.4*lf);
        float vein = smoothstep(.012, .003, abs(vf - .5))*smoothstep(.35, .6, w.y);
        col += vec3(.75, .88, 1.)*vein*(.2 + .7*lf);                            // pale glowing roots
        float gc = smoothstep(.54, .72, w.x)*smoothstep(.45, -.2, p.y);           // golden coral, lower half
        col = mix(col, gold*(.04 + 1.5*bub*bub*bub*(.3 + rn))*smoothstep(0., .1, wall), gc*.92);
    } else {
        float clump = smoothstep(.54, .8, w.y + rn*.25);
        float lace = smoothstep(.08, .015, wall)*clump*(.3 + .7*smoothstep(.3, .7, noise(p*7. + gT*1.3)));
        col = vec3(.002, .003, .01) + vec3(.04, .09, .42)*pow(rf, 3.)*bub*bub*(.4 + 2.2*lf)
            + neonPal(w.x*2. + p.y*.25 + cbx*.3)*lace*(.35 + 1.2*gMid);
        col += neonPal(vf*3.)*smoothstep(.01, .002, abs(vf - .5))*.5*(1. - clump);   // stray neon threads
        col *= bar;
    }
    // dark canopy hub up top where the trunks meet
    col *= 1. - .85*smoothstep(1., .55, length((p - vec2(0, .62))/vec2(.32, .22)) + (rn - .5)*.5);
    // central light column, a vertical spectrum display
    float stack = noise(vec2(p.x*16., p.y*5. - gT*.25))*.5 + bub*.5;
    float seg = spec(clamp((p.y + .6)*.8, 0., 1.));
    float colm = exp(-p.x*(st > .5 ? 40. : 12.))*smoothstep(-.7, -.1, p.y)*smoothstep(.75, .3, p.y)*(.3 + .7*stack);
    col += (st > .5 ? neonPal(p.y*.6 + .1)*.6 : gHM*vec3(.55, .8, 1.))*colm*(.5 + seg + gBass*.8)*(1. + gBeat);
    // fans of curved strands sweeping out from the base
    vec2 fp = p - vec2(0, -.38);
    float fa = atan(fp.x, fp.y), fr = length(fp);
    float ca = fa*26. + sin(fr*4. - fa*2.)*1.6 + gRot*3.;
    float strand = noise(vec2(ca, fr*3. - gT*.05))*.6 + fib*.4;
    strand = pow(strand, 5.)*6.;
    float fm = smoothstep(.12, .32, fr)*smoothstep(1.25, .5, fr)*smoothstep(.7, 1.5, fa)*smoothstep(3.1, 2.4, fa);
    col += (st > .5 ? mix(vec3(.15, .3, 1.), neonPal(fa*.4 + .6), .4) : mix(gold, vec3(.7, .88, 1.), smoothstep(.4, .7, w.x)))*strand*fm*.45*bar;
    // mossy mound at the bottom
    float ee = length((p - vec2(0, -.75))/vec2(.5, .26)) + (w.x - .5)*.45 + (rf - .5)*.15;
    float mm = smoothstep(1., .85, ee);
    if(mm > 0.){
        vec2 cm = cell2(p*34. + w*4.);
        float bmp = (1. - cm.x)*smoothstep(0., .12, cm.y - cm.x);
        vec3 mc = st > .5 ? neonPal(bmp + rn)*smoothstep(.06, .01, cm.y - cm.x)*.5 + vec3(.02, .04, .14)*bmp*bmp*rn : gold*(.02 + .9*bmp*bmp*(.4 + rn));
        col = mix(col, mc, mm);
    }
    // sparks on the highs
    vec2 sg = p*40.;
    float sh = hash21(floor(sg) + floor(gT*3.));
    if(sh > (st > .5 ? .955 : .975)) col += (st > .5 ? neonPal(sh*17.) : vec3(.7, .85, 1.))*exp(-length(fract(sg) - .5)*9.)*(.15 + 1.5*gHigh)*bar;
    return col;
}

vec3 forest(vec2 uv, float st){
    float c = gT*.1, fc = fract(c), fl = floor(c);
    vec2 sway = vec2(0, .05*sin(gT*.07));                                        // vertical only: keeps the mirror honest
    vec3 gold = gHM*vec3(.9, .66, .3);
    vec3 fogc = st > .5 ? vec3(.003, .003, .01) : vec3(.03, .08, .18);
    vec3 col = vec3(0);
    float T = 1.;
    for(int i = ZERO; i < 4; i++){
        float fi = float(i), zw = fl + fi + 1.;
        float z = (fi + 1. - fc)*1.2;
        z += gW.z*.4*sin(zw*1.1 - gT*.8);
        float vis = smoothstep(.2, .65, z)*smoothstep(4.8, 3.8, z);
        if(vis <= 0.) continue;
        vec2 p = cam2D(uv, z, c, sway);
        p.x = abs(p.x);                                                          // mirror axis fixed in the world, so parallax shows
        float pxw = gPx*z;
        // gnarly trunks, some hanging from the canopy and ending mid-air
        const float W = .7;
        float k = floor(p.x/W), h = hash21(vec2(k, zw)), h2 = fract(h*17.31);
        float lx = p.x - k*W;
        float yEnd = h2 < .4 ? -9. : -.7 + h2*.8;                              // 40% run floor to canopy
        float xc = W*(.3 + .4*h) + .07*sin(p.y*2.1 + h*20.) + .05*(noise(vec2(p.y*3.5, h*40.)) - .5);
        if(k < .5) xc -= .18*smoothstep(-.1, .6, p.y - yEnd*.3)*(1. - h);       // innermost trunks lean in and arch over the column
        float r = (.022 + .028*h2)*(.7 + .7*noise(vec2(p.y*9., h*13.)) + .3*abs(sin(p.y*23. + h*9.)));   // knobbly
        r *= sqrt(clamp((p.y - yEnd)/.12, 0., 1.));                              // rounded end, not a spike
        float d = abs(lx - xc) - r;
        float a = smoothstep(pxw, -pxw, d)*step(.22, h)*vis;
        float nx = clamp((lx - xc)/max(r, 1e-3), -1., 1.);
        float lit = pow(max(0., -nx), st > .5 ? 10. : 3.);                                     // rim lit from the central column
        float bark = noise(vec2(nx*2. + h*7., p.y*14.));
        vec3 tc = st > .5 ? neonPal(h + p.y*.15)*lit*(.2 + gMid)*.35 + vec3(.002)
                          : vec3(.035, .026, .016)*(.6 + bark) + gold*lit*.55*bark + vec3(.2, .4, .7)*lit*.15;
        tc = mix(tc, fogc, smoothstep(.6, 4.4, z)*.75);
        // thin hanging vines (glow only)
        float vx = p.x*3.1 + h*5., vh = hash21(vec2(floor(vx), zw + 9.));
        float vd = abs(fract(vx + .04*sin(p.y*5. + vh*9.)) - .5)/3.1;
        float vine = exp(-vd/(pxw*1.5 + .002))*step(.6, vh)*smoothstep(-.4 + vh*.4, .3, p.y)*vis*(1. - smoothstep(.6, 4., z));
        col += T*(a*tc + (st > .5 ? neonPal(vh*7.)*.4 : gold*.8)*vine*.35);
        T *= 1. - a;
        if(T < .02) break;
    }
    if(T > .02) col += T*forestBack(uv, st, gold);
    return col;
}

vec3 render(int s, vec2 uv){
    if(s == 0) return filigree(uv);
    return forest(uv, float(s - 1));
}

vec4 onehot(float i){ return vec4(equal(vec4(i), vec4(0, 1, 2, 3))); }

void mainImage(out vec4 O, in vec2 F){
    vec2 uv = (F - .5*iResolution.xy)/iResolution.y;
    gPx = 1./iResolution.y;
    float hueSteps;

#if AUDIO_REACTIVE
    vec4 a0 = texelFetch(iChannel0, ivec2(0, 0), 0);
    vec4 a1 = texelFetch(iChannel0, ivec2(1, 0), 0);
    vec4 a2 = texelFetch(iChannel0, ivec2(2, 0), 0);
    gBass = a0.x; gMid = a0.y; gHigh = a0.z; gBeat = a0.w;
    gT = a1.x; hueSteps = a1.y; gRot = a1.z;
    float cur = a2.x, prv = a2.y, sw = a2.z;
    gFlash = .3 + 1.3*gBeat + .5*gBass;
#else
    gBass = .3; gMid = .35; gHigh = .2; gBeat = 0.;
    gT = iTime; gRot = iTime*.03;
  #if SCENE > 0
    float cur = float(SCENE - 1), prv = cur, sw = -99.;
  #else
    float idx = floor(iTime/SCENE_LEN);
    float cur = mod(idx, 3.), prv = mod(idx + 2., 3.), sw = idx*SCENE_LEN;
  #endif
    hueSteps = .35*sin(iTime*.05);                                               // gentle drift; the hops are a music thing
    gFlash = .35 + 1.1*pow(.5 + .5*sin(iTime*2.3)*sin(iTime*.71), 6.);
#endif
    gHM = hueMat(hueSteps*1.0472);                                               // 60 degrees per kick

#if PARALLAX_MODE == 0
    float px = iTime/PARALLAX_LEN;
    vec4 w4 = mix(onehot(mod(floor(px), 4.)), onehot(mod(floor(px) + 1., 4.)), smoothstep(.75, 1., fract(px)));
#else
    vec4 w4 = onehot(float(PARALLAX_MODE - 1));
#endif
    gW = w4.yzw;

    uv *= 1. - .06*gBeat;                                                        // punch-in on the kick

    // ring wipe from the centre, launched by the kick that switched scenes
    float pr = clamp((iTime - sw)/XFADE, 0., 1.);
    float R = pow(pr, .6)*1.25, band = .045, rr = length(uv);
    float wc = pr >= 1. ? 1. : 1. - smoothstep(R - band, R + band, rr);          // weight of the new scene
    vec3 col = vec3(0);
    for(int k = ZERO; k < 2; k++){                                               // one render() call site; only renders what is visible
        float wk = k == 0 ? 1. - wc : wc;
        if(wk > 0.) col += wk*render(int(k == 0 ? prv : cur), uv);
    }
    if(pr < 1.) col += gHM*vec3(.9, .75, .5)*exp(-abs(rr - R)*28.)*(1. - pr)*1.4;

    col *= 1. + .18*gBeat;
    col = 1. - exp(-col*1.3);
    col *= 1. - .35*dot(uv*.85, uv*.85);
    O = vec4(pow(col, vec3(.95)), 1);
}
