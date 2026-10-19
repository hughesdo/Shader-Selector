// ============================================================
//  Image  -  Cosmic Ocean Tunnel
//  iChannel0 = Buffer A (audio state, read with texelFetch)
// ============================================================

// ---- per-frame globals -------------------------------------
float gT, gCam, gHue, gRot;
float gBass, gMid, gHigh, gBeat;
vec4  gW;          // parallax weights: curve, helix, accordion, orbit
vec2  gC, gLook;   // orbit camera offset + look
vec2  gP0, gD0;    // path(cam), path'(cam)  (hoisted)
float gTw;         // helix twist rate (hoisted)

#define MQ 3.2
#define NLAYERS 18
#define LDZ     0.62

// ---- parallax machinery ------------------------------------
vec2 path (float z){ return vec2(sin(z*.19)*1.6 + sin(z*.07)*1.2, cos(z*.15)*1.3); }
vec2 dpath(float z){ return vec2(.304*cos(z*.19) + .084*cos(z*.07), -.195*sin(z*.15)); }

// screen-space offset of the tunnel axis at camera depth dz
vec2 axisOff(float dz){
    vec2 o = vec2(0);
    if(gW.x > 0.) o += gW.x*FOCAL*((path(gCam+dz) - gP0)/dz - gD0);
    if(gW.w > 0.) o += gW.w*FOCAL*(-gC/max(dz, .45) - gLook);
    return o;
}
float twist(float dz){
    return gRot + .025*dz + gTw*dz;
}
float accordion(float dz){ return gW.z > 0. ? gW.z*.7*sin(dz*1.1 - gT*1.7)/1.1 : 0.; }

vec4 wOf(float i){
    return i < .5 ? vec4(0) : i < 1.5 ? vec4(1,0,0,0) : i < 2.5 ? vec4(0,1,0,0)
         : i < 3.5 ? vec4(0,0,1,0) : vec4(0,0,0,1);
}
vec4 modeWeights(float t){
#if PARALLAX_MODE == 0
    float m = t/MODE_SECONDS;
    float i = mod(floor(m), 5.);
    float f = smoothstep(.75, 1., fract(m));
    return mix(wOf(i), wOf(mod(i + 1., 5.)), f);
#else
    return wOf(float(PARALLAX_MODE - 1));
#endif
}

// ---- tunnel walls (one per scene) --------------------------
vec3 wallMarble(vec3 p3, float dz){
    vec3 q = vec3(p3.xy*MQ, p3.z*MQ*2.);
    q.z += gT*.05;
    float amp = .8;
    for(int i=0;i<5;i++){
        q += amp*sin(q.yzx*1.7 + vec3(0., 1.3, 2.6) + gT*.12);
        q *= 1.18; amp *= .62;
    }
    float h  = sin(q.x)*cos(q.y) + .5*sin(q.z);
    float h2 = sin(q.x + .06)*cos(q.y + .06) + .5*sin(q.z);
    float gl = (h2 - h)/.06;
    float lit = clamp(.5 + gl*.5, 0., 1.);
    float mask = smoothstep(-.6, -.2, h);
    vec3 c = mix(neon(h*.8 + dot(q, vec3(.03)) + gHue), vec3(.3, .15, 1.), .2)*(.08 + 1.2*lit*lit)*(1. + .5*gMid);
    vec3 col = c*mask + pow(lit, 8.)*vec3(1, .9, 1)*.55*mask;
    col += neon(h*.8 + .45 + gHue)*.45*exp(-abs(h + .5)*14.);
    return col;
}
vec3 wallAurora(vec3 p3, float dz){
    float f = fbm3(p3*.8 + vec3(0, 0, gT*.08), 3);
    float g = fbm3(p3*1.4 + f*2.2, 3);
    float lines = exp(-abs(sin(g*9. + f*5. - gT*.35))*5.);
    float soft  = pow(.5 + .5*sin(g*6. + f*3. + 1.), 3.);
    vec3 c1 = neon(g*2.5 + f + gHue + .1), c2 = neon(f*2. + gHue + .55);
    float m = smoothstep(.2, .6, f + g*.4);
    return vec3(.025, .01, .06) + (c1*lines*(1.1 + .5*gMid) + c2*soft*.6)*m;
}
vec3 wallRings(float a, float Z, float dz){
    const float NC = 9.;
    vec2 g  = vec2((a/TAU + .5)*NC, Z*NC/TAU);
    vec2 id = floor(g), f = fract(g);
    float d1 = 9., d2 = 9.; vec2 bid = id;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){
        vec2 o = vec2(i, j), cid = id + o; cid.x = mod(cid.x, NC);
        vec2 r = o + .2 + .6*hash22(cid) - f;
        float d = length(r*vec2(1., 1.2));
        if(d < d1){ d2 = d1; d1 = d; bid = cid; } else if(d < d2) d2 = d;
    }
    float rings = d1*9. - gT*.6;
    float rf = abs(fract(rings) - .5);
    float lw = .035 + dz*.012;
    float lod = 1. - smoothstep(4., 11., dz);
    float line = smoothstep(lw + .06, lw*.3, rf);
    vec3 c = neon(floor(rings)*.13 + hash12(bid) + gHue);
    float mask = smoothstep(0., .12, d2 - d1)*(1. - smoothstep(.55, .95, d1));
    return c*mask*(line*lod*(1. + .7*gHigh) + .22*exp(-rf*7.)) + vec3(.02, .0, .05);
}
vec3 wallSpiral(float a, float dz){
    float s = log(dz);
    float ra = a + gT*.22;
    vec3 col = vec3(.015, .005, .04);
    // faint neon threads in the dark
    float th = abs(sin(ra*3. - s*4. + 1.3*sin(s*2. + gT*.3)));
    col += neon(s*.5 + gHue + .5)*.12*exp(-th*20.);
    // ribbon set B (behind)
    float uB = ra*3./TAU + s*1.15 + .37;
    float xB = (fract(uB) - .5)/(.12 + .04*sin(s*2.3 + 1.));
    if(abs(xB) < 1.){
        float n = sqrt(1. - xB*xB);
        vec3 c = vec3(.2, .08, .7)*(.05 + .45*n*n) + neon(xB*.8 + s*.4 + gHue + .6)*pow(1. - n, 1.5)*.6 + exp(-pow((xB + .35)*4., 2.))*.3*n;
        col = mix(col, c, smoothstep(1., .85, abs(xB)));
    }
    // ribbon set A (front, 5 arms)
    float uA = ra*5./TAU + s*1.6;
    float xA = (fract(uA) - .5)/(.17 + .07*sin(s*3. + mod(floor(uA), 5.)*1.7));
    if(abs(xA) < 1.){
        float n = sqrt(1. - xA*xA);
        vec3 body = mix(vec3(.22, .1, .9), neon(s*.7 + gHue + .2*sin(ra*2.)), .45 + .35*sin(s*4. + ra));
        vec3 c = body*(.08 + .75*n*n)*(1. + .4*gMid) + neon(xA*.8 + s*.5 + gHue + .3)*pow(1. - n, 1.5)*.9;
        c += exp(-pow((xA + .35)*5., 2.))*vec3(1, .95, 1)*.7*n;
        col = mix(col, c, smoothstep(1., .85, abs(xA)));
    }
    return col;
}
vec3 wallOf(float si, float a, float Z, float dz){
    vec3 p3 = vec3(cos(a), sin(a), Z*.5);
    if(si < .5)      return wallMarble(p3, dz);
    else if(si < 1.5) return wallAurora(p3, dz);
    else if(si < 2.5) return wallRings(a, Z, dz);
    return wallSpiral(a, dz);
}
vec3 sceneWall(float a, float Z, float dz){
    float x = Z/SCENE_LEN;
    float si = mod(floor(x), 4.);
    float f = smoothstep(.82, 1., fract(x));
    vec3 c = wallOf(si, a, Z, dz);
    if(f > 0.) c = mix(c, wallOf(mod(si + 1., 4.), a, Z, dz), f);
    return c;
}

// ---- creatures ---------------------------------------------
vec4 jelly(vec2 q, float sd, inout vec3 glow){
    float pul = sin(gT*3.2 + sd*20.);
    q.x *= 1. + .07*pul; q.y *= 1. - .07*pul;
    float hu = sd*3.7 + gHue;
    vec3 base = neon(hu), tcol = neon(hu + .45);
    vec4 acc = vec4(0);
    vec2 e = q/vec2(1., .82);
    float r = length(e);
    float under = q.y + .18 - .22*q.x*q.x;
    float dD = max(r - 1., -under);
    if(dD < .03){
        float al = smoothstep(.03, -.02, dD)*.93;
        vec3 n = normalize(vec3(e, sqrt(max(0., 1. - r*r)) + .05));
        float dif = .35 + .65*clamp(dot(n, vec3(-.39, .58, .71)), 0., 1.);
        float fr = pow(1. - n.z, 2.);
        vec3 c = base*dif + fr*mix(base, vec3(1), .3)*.9;
        c += pow(clamp(dot(n, vec3(-.36, .54, .76)), 0., 1.), 40.)*.9;
        float spot = min(min(length(e - vec2(-.42, .42)), length(e - vec2(.1, .62))), length(e - vec2(.5, .3)));
        c = mix(c, neon(hu + .6)*1.2, smoothstep(.13, .09, spot));
        float mer = e.x/max(sqrt(max(1. - e.y*e.y, 0.)), .15);
        c *= .78 + .22*smoothstep(.04, .12, abs(fract(mer*2.2 + .5) - .5));
        c *= .5 + .5*smoothstep(-.2, .3, q.y);
        acc = vec4(c*al, al);
    }
    glow += base*.22*exp(-max(dD, 0.)*8.);
    if(acc.a < .9 && q.y < -.02 && q.y > -1.75 && abs(q.x) < 1.05){
        float yy = -q.y, sp = .26;
        float xi = clamp(floor((q.x + .78)/sp + .5), 0., 6.);
        float cx = xi*sp - .78;
        float sw = .12*sin(yy*4.5 - gT*3. + xi*1.3 + sd*9.)*smoothstep(0., .5, yy);
        float dx = q.x - cx - sw;
        float len = 1.05 + .45*hash11(xi + sd*13.);
        float w = .075*(1. - .55*yy/len);
        float m = smoothstep(w, w*.35, abs(dx))*step(yy, len);
        vec3 c = mix(tcol, neon(hu + .8), yy/len)*(.8 + .3*sin(yy*22.))*(.7 + .5*smoothstep(w, 0., abs(dx)));
        float al = m*.9*(1. - acc.a);
        acc.rgb += c*al; acc.a += al;
        float tip = exp(-length(vec2(dx, yy - len))*14.);
        glow += tcol*(.12*exp(-abs(dx)*25.)*step(yy, len) + tip*(.5 + gHigh));
    }
    return acc;
}

vec4 spore(vec2 q, float sd, inout vec3 glow){
    float r = length(q);
    vec4 acc = vec4(0);
    float hu = sd*2. + gHue;
    if(r < 1.){
        vec3 n = vec3(q, sqrt(1. - r*r));
        vec3 nr = n;
        nr.xz *= rot2(gT*.4 + sd*6.); nr.xy *= rot2(sd*3.);
        float t = dot(nr, vec3(.6, .5, .4))*1.2 + hu;
        vec3 c = neon(t);
        float th = acos(clamp(nr.y, -1., 1.)), ph = atan(nr.z, nr.x);
        const float rows = 7.;
        float ri = floor(th/PI*rows);
        float tc = (ri + .5)/rows*PI;
        float nc = max(1., floor(rows*2.*sin(tc)));
        float pc = (ph/TAU + .5)*nc;
        vec2 lc = vec2((fract(pc) - .5)*TAU/nc*sin(tc), (th/PI*rows - ri - .5)*PI/rows);
        float hd = length(lc)/(PI/rows);
        float ring = smoothstep(.08, .0, abs(hd - .3));
        float hole = smoothstep(.3, .24, hd);
        float dif = .3 + .7*clamp(dot(n, vec3(-.5, .6, .62)), 0., 1.);
        vec3 col = c*dif*(1. - hole*.75) + neon(t + .5)*ring*1.2*(.4 + .6*dif);
        col += pow(1. - n.z, 3.)*c*.8;
        col += pow(clamp(dot(n, vec3(-.4, .5, .77)), 0., 1.), 30.)*.6;
        float a = smoothstep(1., .96, r);
        acc = vec4(col*a, a);
    }
    if(acc.a < .99 && r > .85 && r < 1.5){
        const float ns = 9.;
        float sa = TAU/ns;
        float ang = atan(q.y, q.x) + gT*.3 + sd*6.;
        float ai = floor(ang/sa + .5);
        float da = (ang - ai*sa)*r;
        float hi = hash11(mod(ai, ns) + sd*7.);
        float len = 1.2 + .25*hi;
        float w = .055*(1. - .55*(r - 1.)/.5);
        float m = smoothstep(w, w*.3, abs(da))*step(r, len);
        vec3 sc = neon(hu + hi*.4 + .2)*1.1;
        float al = m*(1. - acc.a);
        acc.rgb += sc*al; acc.a += al;
        glow += sc*exp(-length(vec2(da, r - len))*16.)*(.6 + gHigh);
    }
    return acc;
}

vec4 bubble(vec2 q, float sd){
    float d = abs(length(q) - .75);
    float m = smoothstep(.2, .06, d);
    vec3 c = neon(sd*5. + gHue + .3)*(1. + gHigh);
    return vec4(c*m*.9, m*.85);
}

// composite helper (premultiplied, b goes under a)
void under(inout vec4 acc, vec4 b){ acc.rgb += (1. - acc.a)*b.rgb; acc.a += (1. - acc.a)*b.a; }

// one depth layer of creatures. p = world cross-section coords, k = layer id
// type 1 = jellyfish + bubbles, 2 = spores
vec4 creatureLayer(vec2 p, float pang, float k, float type, inout vec3 glow){
    vec4 acc = vec4(0);
    float NS = type < 1.5 ? 4. : 5.;
    float sa = TAU/NS;
    float lr = hash11(k*7.13)*TAU;
    float ang = pang + lr;
    float fs = ang/sa;
    float s0 = floor(fs);
    float ff = fract(fs);
    float s1 = s0 + (ff > .5 ? 1. : -1.);
    // neighbour sector can only reach us if we are within its max extent of the shared edge
    float ext = type < 1.5 ? .425 : .32;
    int nc = length(p)*sin(min(ff, 1. - ff)*sa) > ext ? 1 : 2;
    for(int c=0;c<2;c++){
        if(c >= nc) break;
        float sj = c == 0 ? s0 : s1;
        float sid = mod(sj, NS);
        vec2 kk = vec2(k, sid);
        if(hash12(kk) > .78) continue;
        float ca = (sj + .2 + .6*hash12(kk*1.37 + 3.1))*sa - lr;
        float rr = .22 + .62*hash12(kk*.71 + 9.7);
        vec2 cen = rr*vec2(cos(ca), sin(ca));
        float sd = hash12(kk + 17.3);
        if(type < 1.5){
            float S = .13 + .1*hash12(kk*1.9 + 1.);
            vec2 q = (p - cen)/S;
            if(dot(q, q) > 3.4) continue;
            q *= rot2((sd - .5)*1.8 + .25*sin(gT*.9 + sd*30.));
            under(acc, jelly(q, sd, glow));
        } else {
            float S = .11 + .1*hash12(kk*1.9 + 1.);
            vec2 q = (p - cen)/S;
            if(dot(q, q) > 2.3) continue;
            under(acc, spore(q, sd, glow));
        }
    }
    if(type < 1.5 && acc.a < .95){
        const float NB = 11.;
        float sb = TAU/NB;
        float ab = pang + lr*2.3;
        float bj = floor(ab/sb);
        vec2 kb = vec2(k, mod(bj, NB));
        float ca = (bj + .5 + .5*(hash12(kb + 5.) - .5))*sb - lr*2.3;
        float rr = .15 + .8*hash12(kb + 2.2);
        float S = .02 + .025*hash12(kb + 8.);
        vec2 q = (p - rr*vec2(cos(ca), sin(ca)))/S;
        if(dot(q, q) < 1.2) under(acc, bubble(q, hash12(kb)));
    }
    return acc;
}

float sceneTypeAt(float Z){
    float x = Z/SCENE_LEN;
    float si = mod(floor(x), 4.);
    float f = smoothstep(.82, 1., fract(x));
    float nx = mod(si + 1., 4.);
    return hash11(Z*3.7) < f ? nx : si;
}

// ---- main ---------------------------------------------------
void mainImage(out vec4 O, in vec2 F){
    vec2 uv = (F - .5*iResolution.xy)/iResolution.y;

#if AUDIO_REACTIVE
    vec4 A0 = texelFetch(iChannel0, ivec2(0, 0), 0);
    vec4 A1 = texelFetch(iChannel0, ivec2(1, 0), 0);
    gBass = A0.x; gMid = A0.y; gHigh = A0.z; gBeat = A0.w;
    gT = A1.x; gHue = A1.y; gRot = A1.z;
#else
    gBass = 0.; gMid = 0.; gHigh = 0.; gBeat = 0.;
    gT = iTime; gHue = iTime*.012; gRot = iTime*.03;
#endif
    gCam  = gT*SPEED;
    gW    = modeWeights(iTime);
    gC    = .22*vec2(cos(iTime*.31), sin(iTime*.23));
    gLook = -.5*gC;
    gP0 = path(gCam); gD0 = dpath(gCam);
    gTw = gW.y*.24*sin(iTime*.17 + 1.);

    uv *= 1. - .05*gBeat;                 // punch-in on kicks

    // --- wall depth (fixed point solve when the axis bends) ---
    float dz = FOCAL/max(length(uv), 1e-3);
    vec2 q = uv;
    if(gW.x + gW.w > 0.){
        for(int i=0;i<4;i++){
            q = uv - axisOff(dz);
            dz = mix(dz, FOCAL/max(length(q), 1e-3), .75);
        }
        q = uv - axisOff(dz);
    }
    dz = min(dz, 60.);

    // --- creatures, front to back ---
    vec4 acc = vec4(0);
    vec3 glow = vec3(0);
    float k0 = floor(gCam/LDZ) + 1.;
    bool  bent = gW.x + gW.w > 0.;
    float ang0 = atan(uv.y, uv.x);
    for(int i=0;i<NLAYERS;i++){
        float k  = k0 + float(i);
        float Zk = k*LDZ;
        float ld = Zk - gCam;
        float dr = ld - accordion(ld);
        if(dr > dz) break;
        float type = sceneTypeAt(Zk);
        if(type < .5 || type > 2.5) continue;
        vec2 p = (uv - axisOff(dr))*dr/FOCAL;
        float spin = gW.y*.15*iTime*(mod(k, 2.) < .5 ? 1. : -1.);
        float th = twist(dr) + spin;
        p = rot2(th)*p;
        float pang = bent ? atan(p.y, p.x) : ang0 - th;
        vec3 g = vec3(0);
        vec4 c = creatureLayer(p, pang, k, type, g);
        float fade = smoothstep(.06, .4, dr)*(1. - smoothstep(8., 11.5, dr));
        float fog = smoothstep(2., 11., dr);
        c.rgb = mix(c.rgb, vec3(.3, .15, .6)*c.a, fog*.6);
        acc.rgb += (1. - acc.a)*(c.rgb + g*(1. - fog))*fade;
        acc.a   += (1. - acc.a)*c.a*fade;
        if(acc.a > .98) break;
    }

    // --- background: wall + core orb ---
    vec3 bg = vec3(.18, .08, .35);
    if(acc.a < .98){
        float fogW = smoothstep(3., 15., dz);
        if(fogW < 1.){
            float a = atan(q.y, q.x) - twist(dz);
            float Z = gCam + dz + accordion(dz);
            bg = mix(sceneWall(a, Z, dz), bg, fogW);
        }
        vec2 d = uv - axisOff(40.);
        float r = length(d);
        float R0 = .12 + .02*gBass;
        float an = atan(d.y, d.x);
        bg *= 1. + .25*smoothstep(R0, R0*.5, r);
        bg += neon(an/TAU + gHue + r*3.)*(exp(-abs(r - R0)*90.)*.6 + exp(-abs(r - R0)*22.)*.12);
        bg += vec3(.6, .35, 1.)*(.022/(r + .02))*(1. + .8*gBass);
        bg += vec3(1, .85, 1)*exp(-r*30.)*(1.3 + .8*gBeat);
#if AUDIO_REACTIVE
        float r1 = R0 + .012;
        if(r > r1 && r < r1 + .09){
            float a01 = abs(an)/PI;
            float bin = floor(a01*63.);
            float sv = texelFetch(iChannel0, ivec2(int(bin), 1), 0).x;
            float bar = step(r, r1 + sv*.09)*step(fract(a01*63.), .6);
            bg += neon(bin/64. + gHue)*bar*.8;
        }
#endif
    }
    vec3 col = acc.rgb + (1. - acc.a)*bg;

    col += neon(gHue)*gBeat*.05;
    col = 1. - exp(-col*1.5);
    vec2 v = F/iResolution.xy;
    col *= .55 + .45*pow(16.*v.x*v.y*(1. - v.x)*(1. - v.y), .2);
    O = vec4(col, 1);
}
