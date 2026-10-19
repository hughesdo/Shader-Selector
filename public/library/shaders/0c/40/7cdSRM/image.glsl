// Infinite Sacred Corridor - raymarched, real 3D geometry + reflective marble
// v5  (SDF walls with relief, computed normals, neon lighting, floor mirror bounce)
// v6  audio: iChannel0 = Music / SoundCloud / Mic
//     ceiling medallions (and their mirror images in the floor) react ArthurTent-style:
//     bass  -> glow pump, halo swell, a ring that rides out with the bass, palette jump on hits
//     bands -> each medallion listens to its own slice of the spectrum
//     every medallion turns slowly, alternating direction; the gold catches the ceiling light
// v7  more cowbell: harder pump, faster spin; each window bay is a small VU meter
//     (glass panels light bottom-up with its band) and the sconces flicker on the highs
#define PI 3.14159265

mat2 rot(float a){ float c=cos(a),s=sin(a); return mat2(c,-s,s,c); }
float h11(float p){ return fract(sin(p*127.13)*43758.5453); }
float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    float a=hash21(i), b=hash21(i+vec2(1,0)), c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float fbm(vec2 p){ float s=0.0,a=0.5; for(int i=0;i<5;i++){ s+=a*vnoise(p); p*=2.03; a*=0.5; } return s; }

// vivid neon jewel palette (magenta / purple / blue / cyan / gold)
vec3 pal(float t){
    return 0.55 + 0.45*cos(6.2831853*(vec3(1.0,0.85,0.75)*t + vec3(0.15,0.45,0.78)));
}

// ---------------- AUDIO TWEAKS ----------------
#define AUDIO_GLOW   3.00   // medallion glow pump
#define HALO_SWELL   4.00   // soft halo around each medallion on bass
#define WAVE_AMT     2.50   // brightness of the ring that rides out with the bass
#define BEAT_HUE     0.35   // ceiling palette jump on bass hits
#define CEIL_LIGHT   1.00   // how much the ceiling pulse lights the gold
#define SPIN_SPEED   0.45   // medallion rotation (rad/s)
#define SPIN_KICK    0.90   // extra twist from the music
#define WALL_PUMP    0.80   // stained-glass VU meter strength (keep it modest)
#define SCONCE_PULSE 1.00   // wall sconces flicker on the highs
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

// sacred-geometry medallion, q in ~[-1,1]^2, returns emissive intensity
// spin turns the pattern, wave (0..1) adds a ring that rides outward
float mandala(vec2 q, float seed, float spin, float wave){
    float r = length(q);
    float a = atan(q.y,q.x) + spin;
    float N = 6.0 + 2.0*floor(h11(seed+3.0)*4.0); // 6..12
    float m = 0.0;
    m += smoothstep(0.14,0.0,r)*2.0;
    m += smoothstep(0.03,0.0,abs(r-0.30))*1.0;
    m += smoothstep(0.03,0.0,abs(r-0.55))*1.0;
    m += smoothstep(0.03,0.0,abs(r-0.80))*0.8;
    float pet = pow(0.5+0.5*cos(a*N),7.0);
    m += pet*smoothstep(0.95,0.12,r)*1.1;
    float pet2 = pow(0.5+0.5*cos(a*N + 0.5),8.0);
    m += pet2*smoothstep(0.60,0.05,abs(r-0.42))*0.8;
    float sp = pow(0.5+0.5*cos(a*N*2.0),28.0);
    m += sp*smoothstep(0.85,0.08,r)*0.6;
    m += wave*WAVE_AMT*smoothstep(0.05,0.0,abs(r-(0.18+0.62*wave)));
    m *= smoothstep(1.0,0.72,r);
    return m;
}

// ---------------- geometry ----------------
const float Pz = 2.2;   // bay period along corridor
const float wx = 1.7;   // half width
const float wy = 1.15;  // half height

float sdBox(vec3 p, vec3 b){ vec3 q=abs(p)-b; return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0); }

// returns vec2(distance, materialId)
// mat: 1 wall(stone/glass) 2 gold column 4 ceiling panel 6 floor 7 sconce(emis) 8 gold beam
vec2 mapMin(vec2 a, vec2 b){ return a.x<b.x?a:b; }

vec2 map(vec3 p){
    float X  = abs(p.x);
    float zc = mod(p.z, Pz) - 0.5*Pz;         // window bay centre
    float ze = mod(p.z - 0.5*Pz, Pz) - 0.5*Pz;// column centre

    // tunnel shell (planar half-spaces)
    vec2 res = vec2(p.y + wy, 6.0);           // floor
    res = mapMin(res, vec2(wy - p.y, 4.0));   // ceiling
    res = mapMin(res, vec2(wx - X, 1.0));     // side walls

    // gold pilaster columns protruding inward from side walls
    float cd = 0.24, cw = 0.30;
    float dcol = sdBox(vec3(X-(wx-0.5*cd), p.y, ze), vec3(0.5*cd, wy-0.02, cw)) - 0.04;
    res = mapMin(res, vec2(dcol, 2.0));
    // capital + base (fatter blocks)
    float dcap  = sdBox(vec3(X-(wx-0.17), p.y-(wy-0.15), ze), vec3(0.17,0.15,cw+0.10)) - 0.03;
    float dbase = sdBox(vec3(X-(wx-0.17), p.y+(wy-0.17), ze), vec3(0.17,0.17,cw+0.10)) - 0.03;
    res = mapMin(res, vec2(min(dcap,dbase), 2.0));

    // cornice rail (top of wall) + base rail (bottom) — long boxes in z
    float dcorn = sdBox(vec3(X-(wx-0.08), p.y-(wy-0.13), 0.0), vec3(0.08,0.05,1e3)) - 0.03;
    float dbrl  = sdBox(vec3(X-(wx-0.08), p.y+(wy-0.16), 0.0), vec3(0.08,0.07,1e3)) - 0.03;
    res = mapMin(res, vec2(min(dcorn,dbrl), 8.0));

    // wall sconce (small emissive block) between windows, upper wall
    float dsc = sdBox(vec3(X-(wx-0.20), p.y-0.38, ze), vec3(0.05,0.13,0.05)) - 0.02;
    res = mapMin(res, vec2(dsc, 7.0));

    // coffered-ceiling beams: transverse beams at column lines + two longitudinal rails
    float beamZ = sdBox(vec3(p.x, p.y-(wy-0.05), ze), vec3(1e3,0.05,0.11)) - 0.03;
    float beamX = sdBox(vec3(X-(wx-0.55), p.y-(wy-0.05), 0.0), vec3(0.055,0.05,1e3)) - 0.03;
    res = mapMin(res, vec2(min(beamZ,beamX), 8.0));

    return res;
}

vec3 calcNormal(vec3 p){
    const vec2 k = vec2(1.0,-1.0);
    const float e = 0.0018;
    return normalize(k.xyy*map(p+k.xyy*e).x + k.yyx*map(p+k.yyx*e).x
                   + k.yxy*map(p+k.yxy*e).x + k.xxx*map(p+k.xxx*e).x);
}

// ---------------- ceiling medallion (shared) ----------------
// Used by the ceiling itself AND by its mirror image in the floor,
// so the reflection always pulses in step with the real thing.
// k = brightness of the caller (3.0 on the ceiling, 2.6 in the mirror)
vec3 ceilingMedallion(vec2 q, float cell, float k){
    float band = smoothstep(0.30, 0.90, fft(0.02 + fract(cell*0.137)*0.40));
    float dir  = mod(cell, 2.0) < 0.5 ? 1.0 : -1.0;     // neighbours counter-rotate
    float m    = mandala(q, cell, dir*(iTime*SPIN_SPEED + SPIN_KICK*gEnergy), gBass);
    vec3 mc    = pal(cell*0.16 + 0.05 + BEAT_HUE*gHit);
    float pump = 1.0 + AUDIO_GLOW*(0.5*gBass + band);
    return mc*m*k*pump
         + mc*smoothstep(1.4,0.2,length(q))*0.12*(1.0 + HALO_SWELL*gBass);
}

// stained glass: each bay is a little VU meter for its own band.
// Shared by the windows and their mirror images in the floor.
float windowGain(float cell, float panel){
    float band = smoothstep(0.30, 0.90, fft(0.05 + fract(cell*0.291)*0.35));
    float lit  = step(panel, band*4.0);          // the 4 panels light bottom-up with the level
    return 1.0 + WALL_PUMP*band*(0.35 + 0.65*lit);
}

// ---------------- material albedo / emission ----------------
// returns albedo in .rgb, emissive strength packed via out; metalness out
void material(vec3 pos, float mat, out vec3 albedo, out vec3 emis, out float metal, out float rough){
    float X  = abs(pos.x);
    float zc = mod(pos.z, Pz) - 0.5*Pz;
    float cell = floor(pos.z/Pz);
    albedo = vec3(0.05); emis = vec3(0.0); metal = 0.0; rough = 0.6;

    if(mat < 1.5){
        // ===== SIDE WALL: stone + arched stained glass window =====
        float lv = pos.y/wy;
        float zw = 0.62;
        float wext   = 1.0 - smoothstep(zw-0.06, zw, abs(zc));
        float archTop= 0.52 + 0.34*sqrt(max(0.0,1.0-pow(zc/zw,2.0)));
        float inWin  = wext*step(-0.70,lv)*step(lv,archTop);
        // coherent stacked jewel panels (a few colour bands up the window, per bay)
        float panel = floor((lv+0.72)*2.2);
        vec3 glass = pal(cell*0.37 + panel*0.14 + 0.30);
        float lead   = (0.5+0.5*sin(lv*22.0))*(0.5+0.5*sin(zc*40.0));
        float diamond= 0.5+0.5*sin((lv+zc*1.6)*20.0)*sin((lv-zc*1.6)*20.0);
        emis   = glass*inWin*(0.55+0.7*lead+0.4*diamond)*1.7*windowGain(cell, panel);
        // dark carved stone around the window
        vec3 stone = vec3(0.06,0.05,0.055)*(0.7+0.5*fbm(vec2(zc*6.0,lv*6.0)));
        albedo = mix(stone, vec3(0.02), inWin);
        // gold arch + sill outline
        float outline = smoothstep(0.03,0.0,abs(lv-archTop))*wext
                      + smoothstep(0.025,0.0,abs(lv+0.70))*wext;
        albedo = mix(albedo, vec3(1.0,0.72,0.30), clamp(outline,0.0,1.0));
        metal  = clamp(outline,0.0,1.0)*0.9;
        rough  = mix(0.7, 0.25, metal);
    } else if(mat < 2.5 || (mat>7.5)){
        // ===== GOLD (columns, caps, beams, cornices) =====
        albedo = vec3(1.0,0.74,0.32);
        // subtle vertical fluting grooves (low amplitude, no harsh banding)
        float ze2 = mod(pos.z - 0.5*Pz, Pz) - 0.5*Pz;
        float fl = 0.5+0.5*sin(ze2*70.0);
        albedo *= 0.88+0.12*fl;
        metal = 1.0; rough = 0.20;
    } else if(mat < 4.5){
        // ===== CEILING PANEL: dark + glowing mandala medallion =====
        float lu = pos.x/wx;
        vec3 base = vec3(0.02,0.015,0.03);
        vec2 q = vec2(lu*1.05, zc*2.0)*1.18;
        emis = ceilingMedallion(q, cell, 3.0);
        albedo = base;
        rough = 0.8;
    } else if(mat < 6.5){
        // ===== FLOOR: handled specially in shade (marble+tiles+runway) =====
        albedo = vec3(0.015);
        metal = 0.0; rough = 0.05;
    } else {
        // ===== SCONCE emissive =====
        emis = vec3(1.0,0.85,0.6)*3.0*(1.0 + SCONCE_PULSE*gHigh);
        albedo = vec3(1.0,0.8,0.5);
        metal = 0.6; rough = 0.3;
    }
}

// neon light contribution on a lit (non-emissive) surface
vec3 neonLight(vec3 pos, vec3 nor, vec3 rd, vec3 albedo, float metal, float rough){
    float cell = floor(pos.z/Pz);
    vec3 cCeil = pal(cell*0.16+0.05 + BEAT_HUE*gHit)*(1.0 + CEIL_LIGHT*gBass);
    vec3 cWin  = pal(cell*0.23+0.35);
    vec3 cFloor= pal(cell*0.16+0.55);

    vec3 amb = vec3(0.10,0.09,0.12);
    vec3 col = albedo*amb;

    // three area-ish lights: ceiling (above), floor tiles (below), windows (sides)
    // plus warm forward light from the vanishing point
    vec3 ldirs[4];
    vec3 lcols[4];
    ldirs[0]=normalize(vec3( 0.15, 1.0, 0.2)); lcols[0]=cCeil*1.1;
    ldirs[1]=normalize(vec3( 0.10,-1.0, 0.2)); lcols[1]=cFloor*0.9;
    ldirs[2]=normalize(vec3(-sign(pos.x)*1.0, 0.15, 0.15)); lcols[2]=cWin*1.0;
    ldirs[3]=normalize(vec3( 0.0, 0.0, 1.0));  lcols[3]=vec3(1.0,0.9,0.72)*0.9;

    for(int i=0;i<4;i++){
        float df = max(dot(nor, ldirs[i]), 0.0);
        vec3 h = normalize(ldirs[i]-rd);
        float sp = pow(max(dot(nor,h),0.0), mix(16.0,180.0,1.0-rough));
        col += albedo*lcols[i]*df*0.55;
        col += lcols[i]*sp*mix(0.3,1.6,metal);
    }
    // metallic environment tint (colored neon reflected in gold)
    if(metal>0.1){
        vec3 r = reflect(rd,nor);
        vec3 env = mix(cFloor, cCeil, r.y*0.5+0.5)*0.45 + cWin*0.15 + vec3(0.9,0.72,0.4)*0.25;
        float fres = pow(1.0-max(dot(-rd,nor),0.0),3.0);
        col += env*metal*(0.25+0.75*fres);
    }
    return col;
}

// full shade of a surface hit (allowReflect adds a floor mirror bounce)
vec3 shade(vec3 pos, vec3 nor, vec3 rd, float mat);

vec3 shadeNoRefl(vec3 pos, vec3 nor, vec3 rd, float mat){
    vec3 albedo, emis; float metal, rough;
    material(pos, mat, albedo, emis, metal, rough);
    vec3 col = emis + neonLight(pos, nor, rd, albedo, metal, rough);
    return col;
}

// cheap ANALYTIC environment reflection for the mirror floor.
// (ray-plane intersection with the tunnel shell — O(1), no second raymarch)
vec3 traceReflect(vec3 ro, vec3 rd){
    float big=1e9;
    float tC = rd.y >  1e-4 ? ( wy-ro.y)/rd.y : big; // ceiling
    float tR = rd.x >  1e-4 ? ( wx-ro.x)/rd.x : big; // right wall
    float tL = rd.x < -1e-4 ? (-wx-ro.x)/rd.x : big; // left wall
    float tm = min(tC, min(tR,tL));
    vec3 hp = ro + rd*max(tm,0.0);
    float cell = floor(hp.z/Pz);
    float zc   = mod(hp.z,Pz)-0.5*Pz;
    vec3 c;
    if(tm==tC){
        // reflected glowing ceiling medallion
        float lu = hp.x/wx;
        vec2 q = vec2(lu*1.05, zc*2.0)*1.18;
        c = ceilingMedallion(q, cell, 2.6) + vec3(0.02,0.015,0.03);
    } else {
        // reflected stained-glass window
        float lv = clamp(hp.y/wy,-1.0,1.0);
        float zw = 0.62;
        float panel = floor((lv+0.72)*2.2);
        vec3 glass = pal(cell*0.37 + panel*0.14 + 0.30);
        float inWin = (1.0-smoothstep(zw-0.06,zw,abs(zc)))*step(-0.70,lv);
        c = glass*inWin*1.5*windowGain(cell, panel) + vec3(0.05,0.04,0.035);
    }
    // fade the reflection into warm haze with distance
    return mix(c, vec3(1.0,0.9,0.78)*0.8, smoothstep(6.0,22.0,tm));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    readAudio();
    vec2 p = (fragCoord - 0.5*iResolution.xy)/iResolution.y;
    float t = iTime;
    float speed = 2.3;

    // camera
    vec3 ro = vec3(0.0, 0.02, t*speed);
    vec3 rd = normalize(vec3(p, 1.35));
    rd.yz *= rot(0.05);                    // slight downward pitch
    rd.xy *= rot(0.02*sin(t*0.3));         // gentle sway

    // primary raymarch (distance-relaxed epsilon for fast grazing convergence)
    float tt=0.0; vec2 h=vec2(1e9,0.0); bool hit=false;
    for(int i=0;i<72;i++){
        vec3 pos=ro+rd*tt;
        h=map(pos);
        if(h.x < 0.0012*tt+0.0007){ hit=true; break; }
        tt+=h.x*0.92;
        if(tt>38.0) break;
    }

    vec3 col;
    if(hit){
        vec3 pos=ro+rd*tt;
        vec3 nor=calcNormal(pos);
        float mat=h.y;

        if(mat>5.5 && mat<6.5){
            // ===== FLOOR: polished black marble + inset glowing tiles + reflection =====
            float lu = pos.x/wx;
            float cell = floor(pos.z/Pz);
            float zc = mod(pos.z,Pz)-0.5*Pz;
            float band = abs(lu);

            // marble veining perturbs normal + darkens
            float mv = fbm(vec2(pos.x*3.0, pos.z*1.4));
            float vein = smoothstep(0.45,0.5,abs(fbm(vec2(pos.x*2.2+mv, pos.z*1.1))-0.5)*2.0);
            vec3 base = vec3(0.008,0.008,0.011)*(1.0+0.7*vein) + vec3(0.015,0.014,0.022)*mv*0.25;
            nor = normalize(nor + vec3((fbm(vec2(pos.x*7.0,pos.z*4.0))-0.5)*0.035, 0.0,
                                       (fbm(vec2(pos.z*7.0,pos.x*4.0))-0.5)*0.035));

            // emissive inset colored glass tiles along the sides
            vec3 tileCol = pal(cell*0.31 + 0.30);
            // rectangular backlit tiles along the sides (bright, per-bay colour)
            float tileZ = 1.0 - smoothstep(0.62, 0.78, abs(zc)/(0.5*Pz));
            float tile  = smoothstep(0.40,0.45,band)*(1.0-smoothstep(0.80,0.90,band))*tileZ;
            vec3 tiles = tileCol*tile*2.1;

            // central mandala runway (glowing circles down the centre)
            vec2 q = vec2(lu*1.4, zc*2.0)*1.35;
            float rm = mandala(q, cell+13.0, 0.0, 0.0);
            vec3 runway = pal(cell*0.16+0.55)*rm*1.4;

            // mirror reflection bounce
            vec3 r = reflect(rd, nor);
            vec3 refc = traceReflect(pos + nor*0.01, r);
            float fres = pow(1.0-max(dot(-rd,nor),0.0), 4.0);
            float gloss = 0.62 + 0.35*fres;

            col = base + tiles + runway;
            col = mix(col, refc, gloss);
            // wet central specular streak toward vanishing point
            col += vec3(1.0,0.94,0.82)*exp(-lu*lu*10.0)*0.18;
        } else {
            col = shadeNoRefl(pos, nor, rd, mat);
        }

        // depth fog toward warm vanishing point
        float fog = 1.0-exp(-tt*0.048);
        col = mix(col, vec3(0.95,0.85,0.72)*0.95, smoothstep(0.0,1.0,fog)*0.5);
    } else {
        col = vec3(0.95,0.86,0.74)*0.9; // vanishing end (not pure white)
    }

    // compact additive glow at the vanishing point
    float centg = exp(-dot(p*vec2(1.0,1.2),p*vec2(1.0,1.2))*30.0);
    col += vec3(1.0,0.9,0.78)*centg*0.35;

    // fake bloom on bright neon
    float lum = dot(col, vec3(0.299,0.587,0.114));
    col += col*smoothstep(0.8,1.9,lum)*0.4;

    // grade — richer saturation to match reference vibrancy
    col = mix(vec3(lum), col, 1.34);
    col = pow(max(col,0.0), vec3(0.90));
    col = col/(1.0+col*0.30);
    col = clamp(col,0.0,1.0);

    fragColor = vec4(col,1.0);
}
