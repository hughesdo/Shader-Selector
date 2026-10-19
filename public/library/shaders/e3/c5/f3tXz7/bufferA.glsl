// ==== SEIFERT GLINT  -  Buffer A (scene, linear HDR) ====
// A trefoil knot spanned by its solid-angle Seifert surface, tiled in holographic mirror tiles.
// Surface = level set  Omega(p) = SIGMA  of the solid angle the knot subtends at p.
// grad(Omega) is the Biot-Savart field of the knot -> distance estimate + normal.
//
// Setup:  Buffer A  iChannel0 = audio (Music / SoundCloud / Mic)   [only used when AUDIO_REACTIVE 1]
//         Image     iChannel0 = Buffer A, filter = mipmap, wrap = clamp

// ---------------------------------------------------------------
#define AUDIO_REACTIVE 1      // 0 = still life like the reference, 1 = react to iChannel0 audio
// ---------------------------------------------------------------
#define PI  3.14159265359
#define TAU 6.28318530718
#define NK  64                 // knot polygon segments for the surface field (48 = faster, slightly less round)

const vec3  KSC   = vec3(1.0/1.874, 1.0/0.67, 0.48/1.27); // knot space -> object space (x, height, depth)
float SIGMA = TAU;            // which surface of the solid-angle family (2pi = the "soap film")
const float NU    = 352.0;    // tiles around the knot
const float TILE  = 0.036;    // tile size (object units)
const float RIM_R = 0.0095;   // gold rim tube radius
const float LOOP   = 20.0;     // seconds per full turn about the vertical axis
const float LOOP_X = 29.0;     // seconds per full turn about the horizontal axis (out of step with LOOP, so the tumble keeps changing)

vec3  K[NK+1];
float KL[NK+1];

// exact knot curve: (2,3) torus knot on |z|^2 = 4|w|^3, stereographically projected
vec3 knot(float s){
    float t = s - 0.225*sin(2.0*s);
    vec2 z = 0.8307182*vec2(cos(3.0*t), sin(3.0*t));
    vec2 w = 0.5566931*vec2(cos(2.0*t), sin(2.0*t));
    vec3 q = vec3(z.x, z.y, w.y)/(1.0 - w.x);
    return vec3(q.x, q.z, q.y)*KSC;
}

void buildKnot(){
    float L = 0.0;
    for(int i=0;i<=NK;i++){
        K[i] = knot(TAU*float(i)/float(NK));
        if(i>0) L += length(K[i]-K[i-1]);
        KL[i] = L;
    }
}

// x = wrapped (Omega - SIGMA), grad = grad Omega, dk = dist to polygon, sk = curve param of nearest point
float field(vec3 p, out vec3 grad, out float dk, out float sk){
    float om = 0.0; grad = vec3(0); dk = 1e9; sk = 0.0;
    vec3 c = vec3(0.0,0.0,9.0) - p; float lc = length(c);
    vec3 a = K[0]-p; float la = length(a);
    for(int i=0;i<NK;i++){
        vec3 b = K[i+1]-p; float lb = length(b);
        float ab = dot(a,b);
        vec3 axb = cross(a,b);
        float den = la*lb*lc + ab*lc + dot(a,c)*lb + dot(b,c)*la;
        om += atan(dot(axb,c), den);
        float q = la*lb;
        grad += axb*(la+lb)/(q*(q+ab)+1e-12);
        vec3 ba = b-a; float h = clamp(-dot(a,ba)/dot(ba,ba),0.0,1.0);
        float d = length(a+ba*h);
        if(d<dk){ dk=d; sk = (float(i)+h)*(TAU/float(NK)); }
        a=b; la=lb;
    }
    om *= 2.0;
    return mod(om - SIGMA + TAU, 2.0*TAU) - TAU;
}

// Newton-refine nearest point on the exact curve; returns distance, updates s
float knotDist(vec3 p, inout float s, out vec3 cp){
    for(int i=0;i<3;i++){
        const float h = 0.002;
        vec3 c0 = knot(s), cpz = knot(s+h), cm = knot(s-h);
        vec3 d1 = (cpz-cm)/(2.0*h), d2 = (cpz-2.0*c0+cm)/(h*h);
        vec3 r = c0-p;
        s -= dot(r,d1)/(dot(d1,d1)+dot(r,d2));
    }
    cp = knot(s);
    return length(p-cp);
}

float arcU(float s){
    float x = fract(s/TAU)*float(NK);
    int i = int(floor(x));
    return mix(KL[i], KL[i+1], fract(x))/KL[NK];
}

// tile coords: x = arclength of nearest knot point, y = distance from rim
vec2 surfCoords(vec3 p){
    float d1 = 1e9, s1 = 0.0;
    vec3 a = K[0]-p;
    for(int i=0;i<NK;i++){
        vec3 b = K[i+1]-p; vec3 ba = b-a;
        float h = clamp(-dot(a,ba)/dot(ba,ba),0.0,1.0);
        float dd = length(a+ba*h);
        if(dd<d1){ d1=dd; s1=(float(i)+h)*(TAU/float(NK)); }
        a = b;
    }
    vec3 cp; float ss = s1;
    float dex = knotDist(p, ss, cp);
    return vec2(arcU(ss)*NU, (dex - RIM_R)/TILE);
}

// ---- audio ----
float A_BASS = 0.0, A_MID = 0.0, A_HIGH = 0.0;
#if AUDIO_REACTIVE
float fft(float x){ return texture(iChannel0, vec2(x, 0.25)).x; }
void readAudio(){
    float b=0.0, m=0.0, h=0.0;
    for(int i=0;i<8;i++){
        float k = (float(i)+0.5)/8.0;
        b += fft(0.005 + 0.045*k);
        m += fft(0.08  + 0.20*k);
        h += fft(0.35  + 0.40*k);
    }
    A_BASS = smoothstep(0.25, 0.95, b/8.0);
    A_MID  = smoothstep(0.15, 0.80, m/8.0);
    A_HIGH = smoothstep(0.08, 0.60, h/8.0);
}
#else
float fft(float x){ return 0.0; }
void readAudio(){}
#endif

mat3 rotX(float a){float c=cos(a),s=sin(a);return mat3(1,0,0,0,c,s,0,-s,c);}
mat3 rotY(float a){float c=cos(a),s=sin(a);return mat3(c,0,-s,0,1,0,s,0,c);}
mat3 rotZ(float a){float c=cos(a),s=sin(a);return mat3(c,s,0,-s,c,0,0,0,1);}

mat3 objRot(float t){
    float a = t*TAU/LOOP, b = t*TAU/LOOP_X;
    return rotX(b)*rotY(a)*rotZ(0.08*sin(2.0*a));   // spins and tumbles end over end
}

vec3 hash32(vec2 p){ vec3 p3=fract(vec3(p.xyx)*vec3(.1031,.1030,.0973)); p3+=dot(p3,p3.yxz+33.33); return fract((p3.xxy+p3.yzz)*p3.zyx); }

// holographic foil palette: gold-heavy, through lime, cyan, violet, magenta, orange
vec3 holo(float x){
    x = fract(x);
    const vec3 c0=vec3(1.00,0.66,0.08), c1=vec3(0.48,0.80,0.06), c2=vec3(0.05,0.78,0.45),
               c3=vec3(0.12,0.30,1.00), c4=vec3(0.92,0.08,0.80), c5=vec3(0.95,0.22,0.10);
    float y = x*6.0; float f = smoothstep(0.0,1.0,fract(y)); int i = int(y);
    vec3 a = i==0?c0: i==1?c1: i==2?c2: i==3?c3: i==4?c4: c5;
    vec3 b = i==0?c1: i==1?c2: i==2?c3: i==3?c4: i==4?c5: c0;
    return mix(a,b,f);
}

// studio reflection: dim room, broad soft boxes, small hot lights (glints)
vec3 lightDir(int i){
    return i==0 ? normalize(vec3(-0.55,0.55,0.62)) :
           i==1 ? normalize(vec3( 0.35,0.75,0.55)) :
                  normalize(vec3( 0.80,-0.25,0.55));
}
float envLum(vec3 r){
    float l = 0.12 + 0.06*r.y;
    l += 0.55*pow(0.5+0.5*sin(5.0*r.x+3.5*r.y+2.0*r.z), 3.0);               // banded studio walls
    l += 0.45*pow(0.5+0.5*sin(-4.0*r.y+6.0*r.z+1.3*r.x+1.0), 4.0);
    l += 1.00*smoothstep(0.2,0.95,dot(r,normalize(vec3(-0.2,0.6,0.8))));     // big softbox
    l += 0.60*smoothstep(0.5,0.98,dot(r,normalize(vec3(0.9,0.1,0.3))));     // side strip
    l += 0.40*smoothstep(0.5,1.0,dot(r,normalize(vec3(-0.8,-0.3,0.4))));
    return l;
}
vec3 glints(vec3 r){
    vec3 g = vec3(0);
    g += vec3(4.0,0.7,3.4)*pow(max(dot(r,lightDir(0)),0.0),70.0);
    g += vec3(3.6,3.4,3.2)*pow(max(dot(r,lightDir(1)),0.0),110.0);
    g += vec3(0.4,3.0,2.8)*pow(max(dot(r,lightDir(2)),0.0),80.0);
    return g;
}

// backdrop: a dim foil haze behind the knot + out-of-focus holo bokeh from the studio lights.
// The bokeh drifts with the turn (sideways with the spin, up/down with the tumble; near layers faster),
// twinkles on the highs, and the haze breathes on the bass. Only runs where the ray misses the knot.
vec3 backdrop(vec2 uv, float t){
    float a = t*TAU/LOOP, b = t*TAU/LOOP_X;
    vec3 col = pow(holo(0.6 + 0.2*uv.x - 0.12*uv.y + 0.06*sin(0.07*t)), vec3(2.0))
             * 0.012*exp(-3.0*dot(uv,uv))*(1.0 + 1.2*A_BASS);
    for(int l=0;l<3;l++){
        float fl = float(l);
        vec2 q = uv*(4.0 + 2.5*fl) - vec2(a, b)*(0.55 - 0.15*fl) + 7.31*fl;
        vec2 id = floor(q), f = fract(q) - 0.5;
        vec3 hs = hash32(id + 13.0*fl);
        float rad = 0.12 + 0.12*fract(hs.x*7.7);                  // centre offset <= 0.25, so the disc stays in its cell
        float d = length(f - (hs.xy - 0.5)*0.5);
        float disc = (1.0 - smoothstep(rad - 0.03, rad, d))*(0.55 + 0.45*smoothstep(0.4*rad, rad, d));   // brighter rim, like lens bokeh
        float tw = 0.5 + 0.5*sin(t*(0.6 + hs.y) + TAU*hs.x);
        col += pow(holo(0.8*hs.y + 0.1*fl), vec3(2.0))*disc*step(hs.z, 0.22)
             * (0.016 + 0.05*tw*(0.35 + A_HIGH))/(1.0 + 0.6*fl);
    }
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (fragCoord - 0.5*iResolution.xy)/iResolution.y;
    float t = iTime;
    readAudio();
    SIGMA = TAU + 0.55*A_BASS;     // bass: the film breathes through its own family of Seifert surfaces
    buildKnot();
    vec3 ro = vec3(0,0,12.0);                 // long lens, like the reference
    vec3 rd = normalize(vec3(uv, -3.75));
#ifdef STATIC_VIEW
    mat3 R = STATIC_VIEW;
#else
    mat3 R = objRot(t);
#endif
    vec3 o = R*ro, d = R*rd;           // ray in object space

    vec3 col = vec3(0.0);
    float alpha = 0.0;

    float BR = 1.4;
    float b = dot(o,d), c = dot(o,o)-BR*BR, h = b*b-c;
    if(h>0.0){
        float tt = max(-b-sqrt(h),0.0), tmax = -b+sqrt(h);
        bool hit=false; bool rim=false;
        vec3 g; float dk, sk, x;
        for(int i=0;i<128;i++){
            vec3 p = o+d*tt;
            x = field(p,g,dk,sk);
            float ds = 0.75*abs(x)/(length(g)+1e-6);
            float dr = dk - RIM_R - 0.004;          // polygon vs exact curve slack
            if(dr < 0.02){                          // near the rim: exact tube distance
                vec3 cp; float ss = sk;
                dr = knotDist(p, ss, cp) - RIM_R;
                if(dr < 0.0002*tt){ hit=true; rim=true; sk=ss; break; }
            }
            float eps = 0.0002*tt;
            if(ds<eps){ hit=true; break; }
            tt += min(min(ds,max(dr,0.0005)), 0.25);
            if(tt>tmax) break;
        }
        if(hit){
            vec3 p = o+d*tt;
            if(!rim){
                x = field(p,g,dk,sk);
                vec3 N = normalize(g); if(dot(N,d)>0.0) N=-N;
                float NV = max(dot(N,-d),0.0);
                vec2 tc = surfCoords(p);
                // wavy rows/columns like the hand-laid reference mosaic
                tc.y += 0.45*sin(0.09*tc.x + 0.9*sin(0.21*tc.y));
                tc.x += 0.35*sin(0.23*tc.y + 0.8*sin(0.05*tc.x));
                // gentle ripples in the sheet itself (makes the reflections streak)
                N = normalize(N + 0.07*vec3(sin(9.0*p.y+4.0*p.z), sin(8.0*p.z-5.0*p.x), sin(7.0*p.x+6.0*p.y)));
                if(dot(N,d)>0.0) N=-N;
                vec2 id = floor(tc), f = fract(tc);
                vec3 hs = hash32(vec2(mod(id.x,NU), id.y)+17.0);
                // tile edge mask + bevel (derivatives taken around the atan branch cut)
                float u2 = tc.x<0.0 ? tc.x+NU : tc.x;
                vec2 fw = min(vec2(min(fwidth(tc.x),fwidth(u2)), fwidth(tc.y)), vec2(0.4));
                vec2 e2 = min(f,1.0-f);
                float edge = min(e2.x, e2.y);
                float gap  = 0.012 + 0.2*max(fw.x,fw.y);
                float tileM = smoothstep(gap, gap+max(max(fw.x,fw.y),0.015), edge);
                float bevel = 1.0-smoothstep(gap, gap+0.07, edge);
                // flat mirror per tile: jittered normal
                vec3 Nt = normalize(N + (0.16 + 0.10*A_HIGH)*(hs-0.5)*2.0);
                vec3 r = reflect(d, Nt);
                // thin-film like hue: view angle + slow spatial drift + per tile
                float hue = 1.3*(1.0-NV) + 0.32*sin(3.1*p.x+4.0*p.y-2.0*p.z) + 0.24*cos(4.4*p.y+2.7*p.z-1.2*p.x)
                          + 0.45*dot(r, vec3(0.5,0.45,-0.35)) + 0.09*(hs.x-0.5) + 0.18*A_MID;
                vec3 film = holo(hue);
                film = mix(film, vec3(0.85,0.70,0.10), 0.32*(0.6+0.4*sin(TAU*hue*0.5+1.3)));  // gold foil base
                film = pow(film, vec3(2.0))*1.25;             // deeper, foil-like saturation
                float L = envLum(r);
                vec3 tileCol = film*L*(0.55+0.75*hs.y*hs.y)*1.45;
                float spark = step(0.975 - 0.06*A_HIGH, hs.z);
                tileCol *= 1.0 + (3.0 + 4.0*A_HIGH)*spark*smoothstep(0.3,0.8,L);   // occasional hot sparkle tile
                tileCol += glints(r)*film*1.5 + glints(r)*0.25;
                // bevel: edges catch shifted hues (the red/blue seams in the reference)
                vec3 edgeCol = holo(hue+0.45)*(0.25+0.9*L)*0.8;
                tileCol = mix(tileCol, edgeCol, bevel*0.45);
#if AUDIO_REACTIVE
                // spectrum wrapped twice around the knot: equalizer bars of lit tiles grow in from the rim
                float cx = mod(id.x, NU)/NU;
                float m  = abs(fract(cx*2.0)*2.0-1.0);           // 1 at highs, 0 at bass, mirrored
                float amp = fft(0.01 + 0.6*m*m);
                float bar = amp*amp*14.0 - id.y;
                float lit = step(0.0, bar);
                float tip = lit*(1.0 - smoothstep(0.0, 1.5, bar));    // the top tile of each bar runs hot
                vec3 barCol = pow(holo(0.05 + 0.75*m), vec3(1.5));      // gold bass -> magenta -> cyan highs
                tileCol = mix(tileCol, barCol*(1.8 + 2.5*A_BASS) + tip*vec3(2.0), lit*0.6);
                tileCol *= 1.0 + 0.25*A_BASS;
#endif
                vec3 grout = mix(tileCol*0.22, holo(hue+0.5)*0.05, 0.5);
                col = mix(grout, tileCol, tileM);
            } else {
                vec3 cp; float ss = sk;
                knotDist(p, ss, cp);
                vec3 n = normalize(p-cp);
                vec3 r = reflect(d,n);
                float L = envLum(r);
                float fr = pow(1.0-max(dot(n,-d),0.0),4.0);
                vec3 gold = vec3(1.0,0.74,0.42);
                col = gold*gold*(0.04+0.7*L) + gold*glints(r)*0.5 + 0.15*fr*gold;
                col += gold*1.6*A_BASS*A_BASS;                   // rim pulses on the kick
            }
            alpha = 1.0;
        }
    }
    if(alpha == 0.0) col = backdrop(uv, t);
    fragColor = vec4(col, alpha);
}
