// ============================================================
//  APOLLONIAN RELIQUARY  —  REFLECTIVE / GYROID-ORB EDITION
//  iChannel0 = Music / SoundCloud / Mic (optional)
//
//  The infinite Apollonian gasket, still lit like stained glass,
//  with a true reflection-bounce architecture and a wandering
//  gyroid orb that leads the camera through the open space,
//  catching the gasket's iridescent colors in its surface.
//
//  Color no longer washes out: saturation comes from the
//  attenuation chain and black fog, not a post-hoc luma push.
//
//  AUDIO:
//   bass  -> cusp candle glow pumps, palette jumps on hits,
//            orb swells and its halo flares,
//            a light core inside the orb glows through the gyroid
//   mids  -> orb inner light, glass tint drifts
//   highs -> orb sparkle
//   with no audio the lighting is the original look
// ============================================================
#define PI 3.14159265

// ---------------- AUDIO TWEAKS ----------------
#define AUDIO_GLOW   2.20   // cusp candle glow pump on bass
#define BEAT_HUE     0.25   // palette jump on bass hits
#define ORB_PULSE    0.15   // orb swell on bass (fraction of radius)
#define ORB_HALO     0.60   // glow around the orb, driven by the music
#define ORB_EMIT     0.90   // light from inside the gyroid shell
#define ORB_CORE     1.00   // glowing core inside the orb, driven by the music
// ----------------------------------------------------

float gBass, gMid, gHigh, gHit, gEnergy;
float fft(float u){ return texture(iChannel0, vec2(u, 0.25)).x; }
void readAudio(){
    float b = 0.0, m = 0.0, h = 0.0;
    for(int i = 0; i < 4; i++){
        float fi = float(i);
        b += fft(0.01 + fi*0.015);
        m += fft(0.12 + fi*0.060);
        h += fft(0.45 + fi*0.100);
    }
    // the FFT texture is in dB, so music sits in a narrow range: stretch each band
    float bRaw = b*0.25;
    gBass = smoothstep(0.70, 0.90, bRaw);
    gMid  = smoothstep(0.30, 0.60, m*0.25);
    gHigh = smoothstep(0.15, 0.45, h*0.25);
    gHit  = smoothstep(0.81, 0.87, bRaw);                 // beat gate: top of the bass range
    gEnergy = gBass*0.6 + gMid*0.3 + gHigh*0.1;
}

mat2 rot(float a){ float c=cos(a), s=sin(a); return mat2(c,-s,s,c); }

// iq-style cosine palette  (original look; bass hits jump the hue)
vec3 pal(float t){
    t += BEAT_HUE*gHit;
    return 0.5 + 0.5*cos(2.0*PI*(t + vec3(0.0, 0.33, 0.67)) + iTime*0.1);
}

// smooth minimum so the orb blends into the gasket rather than clipping
float smin(float a, float b, float k){
    float h = max(k - abs(a-b), 0.0);
    return min(a,b) - h*h*0.25/k;
}

// ---- globals ------------------------------------------------
float gTrap;     // orbit trap for the gasket palette
vec3  gOrbPos;   // current center of the wandering gyroid orb  (per pixel)
float gOrbR;     // current orb radius                          (per pixel)
mat3  gOrbRot;   // gyroid spin, built once per pixel           (per pixel)
float gBreathe;  // gasket breathing scale                      (per pixel)
float gMat;      // 0.0 = gyroid orb , 1.0 = gasket glass (material id)
float gDO;       // distance to the orb at the last map() call

// ---- flight path --------------------------------------------
// A closed Catmull-Rom loop through control points that were
// searched numerically for clearance: this gasket is built from
// layers around y = 0 (mod 2), so the open air is the band around
// y = 1. The path bobs through that band (y 0.70..1.32) and weaves
// in x, keeping a distance estimate >= 0.17 from every surface for
// the whole breathing range. The old loop hugged y = 0 and passed
// straight through walls.
const vec3 CTRL[6] = vec3[6](
    vec3( 0.833, 0.72,  0.049),
    vec3( 0.894, 1.28,  0.121),
    vec3( 0.886, 0.88, -0.200),
    vec3(-0.839, 1.32,  0.040),
    vec3(-0.556, 0.70,  0.200),
    vec3( 0.894, 1.12, -0.065));
const int   NUM_CTRL   = 6;
const float SEG_Z      = 2.0;    // z-advance per control point
#define CAM_SPEED   0.12         // segments per second
#define LOOK_AHEAD  0.35         // how far down the path the camera looks (segments)
#define ORB_LEAD    0.75         // how far ahead the orb flies (segments)

// the four points around segment 'seg', z re-based so the path never snaps back
void segPoints(float seg, out vec3 p0, out vec3 p1, out vec3 p2, out vec3 p3){
    int w = ((int(seg) % NUM_CTRL) + NUM_CTRL) % NUM_CTRL;
    p0 = CTRL[(w + NUM_CTRL - 1) % NUM_CTRL];
    p1 = CTRL[w];
    p2 = CTRL[(w + 1) % NUM_CTRL];
    p3 = CTRL[(w + 2) % NUM_CTRL];
    float zb = seg*SEG_Z;
    p0.z += zb - SEG_Z; p1.z += zb; p2.z += zb + SEG_Z; p3.z += zb + 2.0*SEG_Z;
}
vec3 pathPos(float prog){
    vec3 p0, p1, p2, p3; float seg = floor(prog), t = prog - seg;
    segPoints(seg, p0, p1, p2, p3);
    float t2 = t*t, t3 = t2*t;
    return 0.5*((2.0*p1) + (-p0 + p2)*t + (2.0*p0 - 5.0*p1 + 4.0*p2 - p3)*t2
                + (-p0 + 3.0*p1 - 3.0*p2 + p3)*t3);
}
// analytic tangent: continuous across segment joints (the old
// "sample a hair ahead, clamped at 1.0" tangent snapped there)
vec3 pathTan(float prog){
    vec3 p0, p1, p2, p3; float seg = floor(prog), t = prog - seg;
    segPoints(seg, p0, p1, p2, p3);
    return 0.5*((-p0 + p2) + 2.0*(2.0*p0 - 5.0*p1 + 4.0*p2 - p3)*t
                + 3.0*(-p0 + 3.0*p1 - 3.0*p2 + p3)*t*t);
}

void camera(out vec3 ro, out vec3 fw, out vec3 rt, out vec3 up){
    float prog = iTime*CAM_SPEED;
    ro = pathPos(prog);
    // blend the tangent with a look-ahead target: turns are eased in
    // before they happen instead of being followed mechanically
    vec3 la = normalize(pathPos(prog + LOOK_AHEAD) - ro);
    fw = normalize(normalize(pathTan(prog)) + la);
    rt = normalize(cross(fw, vec3(0,1,0)));
    up = cross(rt, fw);
}

// ---- the Apollonian gasket distance (original) --------------
float gasket(vec3 p){
    float s = 1.0;
    gTrap = 1e9;
    for(int i=0; i<8; i++){
        p = mod(p - 1.0, 2.0) - 1.0;
        float r2 = dot(p,p);
        gTrap = min(gTrap, r2);
        float k = gBreathe / r2;
        p *= k;
        s *= k;
    }
    return 0.25*abs(p.y)/s;
}

// ---- a gyroid-shelled orb -----------------------------------
float gyroidOrb(vec3 p){
    vec3 q = p - gOrbPos;
    float sphere = length(q) - gOrbR;
    // the carved shell is never closer than its bounding sphere, so
    // away from the orb the sphere alone is a safe (cheaper) distance
    if(sphere > 0.08) return sphere;
    q = gOrbRot*q*14.0;                  // gyroid frequency + spin
    float gyr = (abs(dot(sin(q), cos(q.yzx))) - 0.22) / 14.0;
    return max(sphere, gyr);             // carve the gyroid into the shell
}

// ---- the full scene -----------------------------------------
float map(vec3 p){
    float dG = gasket(p);
    float dO = gyroidOrb(p);
    gDO = dO;

    float d = smin(dG, dO, 0.06);        // the orb no longer touches the walls
    gMat = smoothstep(0.02, 0.18, dO - dG);  // ~0 near orb, ~1 on gasket
    return d;
}

vec3 normal(vec3 p, float d){
    // 4-tap tetrahedron normal; the step grows with distance so far
    // surfaces stop sparkling from sub-pixel fractal detail
    vec2 e = vec2(1.0, -1.0) * 0.0007*(1.0 + d*0.5);
    return normalize(
        e.xyy * map(p + e.xyy) +
        e.yyx * map(p + e.yyx) +
        e.yxy * map(p + e.yxy) +
        e.xxx * map(p + e.xxx));
}

// ---- one marching pass: returns lit color, updates ray state -
// rp : ray position (advanced to hit)
// rd : ray direction (replaced with reflection on exit)
// ra : reflection attenuation (multiplied down each bounce)
// hit: did we hit anything this pass
vec3 march(inout vec3 rp, inout vec3 rd, inout vec3 ra, inout bool hit){
    float d = 0.0, glow = 0.0, orbGlow = 0.0, trap = 0.0, matId = 1.0;
    hit = false;
    vec3 p = rp;
    for(int i=0; i<96; i++){
        p = rp + rd*d;
        float h = map(p);
        glow += 0.008/(0.01 + h*h*60.0);         // cusp candle glow
        orbGlow += 0.002/(0.004 + gDO*gDO*40.0); // halo around the orb
        if(h < 0.0004*d + 0.0002){
            hit = true;
            trap = gTrap;
            matId = gMat;
            break;
        }
        d += h*0.85;
        if(d > 22.0) break;
    }

    vec3 col = vec3(0.0);
    vec3 halo = pal(0.5 + 0.1*gMid) * orbGlow * ORB_HALO * (0.4*gEnergy + 0.6*gHit);

    // glowing core inside the orb: a gaussian light integrated
    // analytically along the ray up to the hit, so the shell occludes
    // it naturally and it only shows through the gyroid holes
    float coreAmt = ORB_CORE*(0.5*gBass + 0.3*gMid + 0.5*gHit);
    vec3  coreCol = mix(pal(0.5 + 0.1*gMid), vec3(1.0, 0.85, 0.6), 0.45);
    vec3  co = gOrbPos - rp;
    float t0 = dot(co, rd);
    float s  = 0.38*gOrbR;
    float b2 = max(dot(co, co) - t0*t0, 0.0);
    vec2  ex = vec2(d - t0, -t0)/s;
    vec2  ef = sign(ex)*sqrt(1.0 - exp(-ex*ex*1.2732));   // erf approx
    float core = exp(-b2/(s*s)) * s*0.8862 * (ef.x - ef.y) * 12.0;
    vec3  coreGlow = coreCol * core * coreAmt;

    if(hit){
        rp = p;                              // advance origin to the hit
        vec3 n  = normal(p, d);
        vec3 lp = rp + vec3(0.0, 0.4, 1.5);  // headlamp slightly above
        vec3 ld = normalize(lp - p);
        float dif = max(dot(n, ld), 0.0);
        float spe = pow(max(dot(reflect(-ld,n), -rd), 0.0), 28.0);
        float fre = pow(1.0 - max(dot(n,-rd),0.0), 3.0);

        // gasket = stained glass from orbit trap+depth
        vec3 glassCol = pal(trap*3.0 + d*0.12 + 0.08*gMid);
        // orb = brighter, more metallic, picks up palette by depth
        vec3 orbCol   = pal(d*0.18 + 0.5);

        // blend body color by material id
        vec3 body = mix(orbCol, glassCol, matId);

        col  = body*(0.15 + 0.85*dif);
        col += spe*vec3(1.0, 0.95, 0.8);
        col += fre*pal(trap*5.0 + 0.4)*0.8;  // iridescent rim
        // light from inside the gyroid shell, on mids and highs
        col += (1.0 - matId)*orbCol*ORB_EMIT*(0.6*gMid + 0.8*gHigh);
        // the core lights the inward-facing faces of the shell
        vec3  tc = gOrbPos - p;
        float lc = max(dot(n, normalize(tc)), 0.0) / (1.0 + dot(tc,tc)*40.0);
        col += (1.0 - matId)*coreCol*coreAmt*lc*1.5;

        // BLACK fog: pull toward black, never toward a bright color,
        // so saturation survives instead of bleaching to violet
        float fog = exp(-0.05*d*d);
        col = mix(vec3(0.0), col, fog);

        // attenuate the bounce. Gasket glass reflects less than the
        // metallic orb, and fresnel boosts grazing reflections.
        float reflAmt = mix(0.55, 0.18, matId) + 0.45*fre;
        col *= ra;                           // current path weight
        ra  *= body * reflAmt * fog;         // weight for next bounce

        // candle glow in the cusps — weighted by THIS path's
        // attenuation so reflection bounces barely add to it, and
        // tamed so it can't flood the frame to white. Bass pumps it.
        col += ra * glow * pal(d*0.2 + 0.6) * 0.12 * (1.0 + AUDIO_GLOW*gBass);
        col += ra * halo * fog;
        col += ra * coreGlow;

        // set up the reflected ray for the next march() call
        rp += 0.01*n;                        // nudge off the surface
        rd  = reflect(rd, n);
    } else {
        // missed: deep violet void, weighted by current attenuation.
        // Only the (music-driven) orb halo may paint it.
        col = ra * (vec3(0.012, 0.008, 0.02) + halo + coreGlow);
        ra *= 0.0;                           // nothing more to reflect
    }

    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    readAudio();
    vec2 uv = (2.0*fragCoord - iResolution.xy)/iResolution.y;

    // ---- per-pixel constants, hoisted out of the march -------
    gBreathe = 1.08 + 0.06*sin(iTime*0.25);
    vec3 ro, fw, rt, up;
    camera(ro, fw, rt, up);
    // the orb rides the same cleared path, a little ahead, with a
    // small weave that stays well inside the clearance
    gOrbPos = pathPos(iTime*CAM_SPEED + ORB_LEAD)
            + vec3(sin(iTime*0.37), cos(iTime*0.29), 0.0)*0.03;
    gOrbR = 0.22*(1.0 + ORB_PULSE*gBass);
    // slower, smoother gyroid spin (the old 1.3 / 1.7 rad/s flickered)
    float a = iTime*0.45, b = iTime*0.6;
    mat3 rz = mat3(cos(a), sin(a), 0.0,  -sin(a), cos(a), 0.0,  0.0, 0.0, 1.0);
    mat3 rx = mat3(1.0, 0.0, 0.0,  0.0, cos(b), sin(b),  0.0, -sin(b), cos(b));
    gOrbRot = rx*rz;

    vec3 rd = normalize(uv.x*rt + uv.y*up + 1.3*fw);
    rd.xy *= rot(0.1*sin(iTime*0.07));        // lazy roll (not audio-driven: no shake)

    // ---- reflective bounce loop ----------------------------
    vec3 col = vec3(0.0);
    vec3 ra  = vec3(1.0);                     // reflection attenuation
    bool hit = false;

    col += march(ro, rd, ra, hit);            // primary
    // only spend a bounce if it can still contribute something visible
    if(hit && max(max(ra.r,ra.g),ra.b) > 0.02)
        col += march(ro, rd, ra, hit);        // 1st reflection
    if(hit && max(max(ra.r,ra.g),ra.b) > 0.02)
        col += march(ro, rd, ra, hit);        // 2nd reflection

    // tone map: compress highlights so glow can't nuke to white
    col = 1.0 - exp(-col * 1.6 * (1.0 + 0.4*gEnergy));

    // gentle saturation lift
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, 1.12);

    // soft vignette, never crosses zero, no ring
    col *= 1.0 / (1.0 + 0.18*dot(uv,uv));

    col = pow(col, vec3(0.4545));
    fragColor = vec4(col, 1.0);
}
