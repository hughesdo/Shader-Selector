// Movement in quaternionic space (v3: rolling on belts)
// After Freya Holmer's "movement in non-euclidean quaternionic space".
//
// Three belts are fixed in S^3 (the unit quaternions): the rotation paths
//   belt_a = { e^(theta a) e^(s b) },  a = i, j, k
// The ball's orientation q(t) = e^(t k) rolls along the k path through 1;
// 360 degrees takes it to -1, 720 brings it home. The i path crosses under it
// at +1 and -1 (the flat X), and the k path through i is Clifford-parallel to
// the ball's path: it never touches it and rings the ball the whole time.
// The belt the ball rides slides underneath like a conveyor, and because texture
// and colour live on S^3 itself the colours come back swapped after one full
// turn (q and -q, the double cover).
// S^3 is projected stereographically from a pole that travels with the ball
// (P = -q c), so the ball stays put and the far side of the belts swings round.

#define WR       0.12     // belt half-width in R^3 (constant, like a drawn line)
#define NCELL    80.0     // checker cells around a full belt (even, so -q looks like q)
#define DELTA    0.50     // how far the ball sits from the projection centre (radians)
#define LOOP     6.0      // seconds per 720 degree roll
#define STEPS    220
#define MAXT     40.0
#define FOV      3.0      // focal length
#define DOF      0.03     // depth-of-field strength
#define BALLK    0.42     // ball size vs. the exact rolling radius (1.0 = rolls without slipping)
#define CAXIS    vec3(0.0,0.0,-1.0)   // direction of the far side, in the ball's frame
#define CAMX    -0.5      // chase camera direction in the ball's frame (x side, y up, z along the belt)
#define CAMY     0.8
#define CAMZ     0.866
#define CAMD     30.0     // camera distance in ball radii

const float PI  = 3.14159265;
const float TAU = 6.28318531;

// ---------- quaternions (xyz = imaginary, w = real) ----------
vec4 qmul(vec4 a, vec4 b){
    return vec4(a.w*b.xyz + b.w*a.xyz + cross(a.xyz,b.xyz), a.w*b.w - dot(a.xyz,b.xyz));
}
vec4 qconj(vec4 q){ return vec4(-q.xyz, q.w); }
vec4 qexp(vec3 v){ float a = length(v); return a < 1e-6 ? vec4(v,1.) : vec4(v/a*sin(a), cos(a)); }
vec3 qrot(vec4 q, vec3 v){ return v + 2.0*cross(q.xyz, cross(q.xyz, v) + q.w*v); }

// ---------- per-frame state ----------
vec4 Q, C;             // orientation, offset c
vec3 BP;               // contact point (the ball's point on S^3, projected)
float LAMB;            // R^3 -> S^3 scale at the ball
vec3 FX, FY, FZ;       // world axes as seen at the ball (FY = up from the floor)
vec3 BC; float BR;     // ball centre and radius
vec3 AX[3]; vec3 BX[3]; vec4 RX[3];   // belt k = e^(theta a) e^(s b) r

vec4 invStereo(vec3 p){ float r2 = dot(p,p); return vec4(2.0*p, 1.0-r2)/(1.0+r2); }
vec3 stereo(vec4 z){ return z.xyz/(1.0+z.w); }
vec4 worldOf(vec4 z){ return qmul(qmul(Q, z), C); }        // x = q z c

// belt k coordinates of world point x = e^(theta a) e^(s b)
vec4 beltCoords(vec4 x, int k){
    x = qmul(x, qconj(RX[k]));
    vec3 a = AX[k], b = BX[k], c = cross(a,b);
    return vec4(x.w, dot(x.xyz,a), dot(x.xyz,b), dot(x.xyz,c));
}
vec2 beltF(vec4 x, int k, float lam){
    vec4 u = beltCoords(x,k);
    return vec2(u.x*u.w - u.y*u.z, length(u.zw) - sin(min(WR*1.5*lam, 1.3)));
}
vec4 xOf(vec3 p){ return worldOf(invStereo(p)); }

// colour field on S^3: each component of the quaternion, weighted by its square,
// picks one colour when positive and its partner when negative:
//   w: yellow / blue    i: red / green    j: green / red    k: blue / yellow
// so q and -q always show swapped colours (yellow <-> blue, red <-> green).
vec3 quatColour(vec4 x){
    const vec3 YEL = vec3(1.00,0.84,0.30);
    const vec3 RED = vec3(0.95,0.24,0.10);
    const vec3 GRN = vec3(0.48,0.95,0.22);
    const vec3 BLU = vec3(0.22,0.50,1.00);
    vec4 w = x*x;
    return w.x*(x.x >= 0.0 ? RED : GRN)
         + w.y*(x.y >= 0.0 ? GRN : RED)
         + w.z*(x.z >= 0.0 ? BLU : YEL)
         + w.w*(x.w >= 0.0 ? YEL : BLU);
}

// ---------- belt shading ----------
vec4 shadeBelt(vec3 p, vec3 rd, int k, float pixW, float coc, float tHit){
    vec4 x = xOf(p);
    vec4 u = beltCoords(x,k);
    float th = atan(u.y, u.x);
    float ct = cos(th), st = sin(th);
    float s  = atan(ct*u.z + st*u.w, ct*u.x + st*u.y);

    float lam  = 2.0/(1.0+dot(p,p));
    float soft = pixW + coc;                // in R^3

    float edge = WR - abs(s)/lam;           // constant width in R^3
    float halo = WR*0.3;
    if (edge < -halo - soft) return vec4(0);
    float cover = smoothstep(-soft, soft, edge);
    float haloA = smoothstep(-halo-soft, -halo*0.1, edge) * (1.0-cover) * 0.85;

    // texture lives on S^3 (square cells there, so square here too): it slides as the ball rolls
    float cellS = TAU/NCELL;
    vec2 uv = vec2(th / cellS, s/cellS);
    float chk = mod(floor(uv.x)+floor(uv.y), 2.0);
    chk = mix(chk, 0.5, smoothstep(0.25, 0.9, soft*lam/cellS));

    vec3 base = quatColour(x) * 1.05;
    vec3 col  = base * mix(0.76, 1.0, chk);

    float rim  = smoothstep(WR*0.14 + soft, WR*0.04, edge);
    float line = smoothstep(WR*0.045 + soft, 0.0, edge);
    col = mix(col, base*0.42, rim*(1.0-line));
    col = mix(col, base*1.25 + 0.08, line*0.9);

    vec2 e = vec2(0.002,0);
    vec3 n = normalize(vec3(
        beltF(xOf(p+e.xyy),k,lam).x - beltF(xOf(p-e.xyy),k,lam).x,
        beltF(xOf(p+e.yxy),k,lam).x - beltF(xOf(p-e.yxy),k,lam).x,
        beltF(xOf(p+e.yyx),k,lam).x - beltF(xOf(p-e.yyx),k,lam).x));
    n *= -sign(dot(n,rd));
    vec3 L = normalize(FY*1.0 - FZ*0.35 + FX*0.25);
    col *= 0.82 + 0.25*max(0.0, dot(n,L));
    col += 0.10*pow(max(0.0, dot(reflect(rd,n), L)), 20.0);

    // contact shading from other belts and from the ball
    float occ = 1.0;
    for (int j=0;j<3;j++){
        if (j==k) continue;
        vec2 fb = beltF(x,j,lam);
        occ *= mix(0.55, 1.0, smoothstep(0.0, WR*0.5, max(abs(fb.x), fb.y)/lam));
    }
    float db = length(p - BC) - BR;
    occ *= mix(0.35, 1.0, smoothstep(0.0, BR*1.3, db));
    col *= occ;

    float far = smoothstep(2.4, 6.0, length(p));
    far = max(far, smoothstep(0.6, 0.1, tHit));
    vec3 ghost = mix(vec3(0.11,0.15,0.20)*mix(0.8,1.0,chk), base*0.8, line);
    col = mix(col, ghost, far);

    float a = cover * mix(mix(0.97, 0.36, far), mix(0.97, 0.85, far), line)
                    * mix(1.0, 0.7, smoothstep(0.0, 3.0*cellS, coc*lam));
    return vec4(col*a, a + haloA*(1.0-far));
}

// ---------- ball ----------
float ballHit(vec3 ro, vec3 rd){
    ro -= BC;
    float b = dot(ro,rd), c = dot(ro,ro)-BR*BR, h = b*b-c;
    return h < 0.0 ? -1.0 : -b - sqrt(h);
}
vec3 shadeBall(vec3 p, vec3 rd){
    vec3 n = normalize(p-BC);
    // display frame: rolling about world X carries the ball along the X belt
    vec3 v  = vec3(dot(n,-FZ), dot(n,FY), dot(n,FX));
    vec3 nb = qrot(qconj(Q), v);
    float oct = step(0.0, nb.x*nb.y*nb.z);
    vec3 base = mix(vec3(0.03), vec3(1.0), oct);
    vec3 L = normalize(FY*1.0 - FZ*0.35 + FX*0.25);
    float dif = 0.3 + 0.7*max(0.0, dot(n,L));
    float spec = pow(max(0.0, dot(reflect(rd,n), L)), 80.0);
    float fres = pow(1.0 - max(0.0, dot(n,-rd)), 4.0);
    vec3 floorCol = quatColour(Q);                          // the belt colour right under the ball
    vec3 col = base*dif + spec*1.3 + fres*mix(vec3(0.7), floorCol, 0.6)*0.6;
    float under = smoothstep(0.1, -0.9, dot(n,FY));
    col = mix(col, col*0.55 + floorCol*base*0.45, under);  // underside: shadow plus bounce light
    return col;
}

// ---------- scene ----------
vec3 tangentAtBall(vec3 a){
    // the i belt through the ball is e^(theta i) e^(s b); at the ball its tangents are a*conj(c) in z-space
    vec4 z0 = qconj(C);
    vec4 v  = qmul(vec4(a,0), qconj(C));
    vec3 d  = v.xyz/(1.0+z0.w) - z0.xyz*v.w/((1.0+z0.w)*(1.0+z0.w));
    return normalize(d);
}
void setupScene(float time){
    float t = time*TAU/LOOP;                        // 0..2pi  ->  720 degrees
    Q = qexp(vec3(0.0, 0.0, t));                    // roll about k: 0..720 degrees
    C = qexp(normalize(-CAXIS) * DELTA);            // far side of the sphere lies toward CAXIS
    AX[0] = vec3(0,0,1); BX[0] = vec3(1,0,0);       // k path through 1: the belt the ball rides
    AX[1] = vec3(1,0,0); BX[1] = vec3(0,0,1);       // i path through 1: crosses under the ball at +-1
    AX[2] = vec3(0,0,1); BX[2] = vec3(1,0,0);       // k path through i: Clifford-parallel to the ball's
    RX[0] = vec4(0,0,0,1); RX[1] = vec4(0,0,0,1);   // path, so it never touches it and rings the ball
    RX[2] = vec4(1,0,0,0);
    BP = stereo(qconj(C));
    LAMB = 2.0/(1.0+dot(BP,BP));
    FX = tangentAtBall(vec3(1,0,0));
    FZ = tangentAtBall(vec3(0,0,1));
    FY = normalize(cross(FZ, FX));
    BR = BALLK*0.5/LAMB;                            // 0.5/LAMB would roll without slipping
    BC = BP + FY*BR*1.02;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (2.0*fragCoord - iResolution.xy)/iResolution.y;
    setupScene(iTime);

    // chase camera in the ball's frame: in front, a little above
    vec3 cd = normalize(FZ*CAMZ + FY*CAMY + FX*CAMX);
    float D = CAMD * BR;
    vec3 ta = BC;
    vec3 ro = ta + cd*D;
    vec3 fw = normalize(ta - ro);
    vec3 rt = normalize(cross(fw, FY));
    vec3 up = cross(rt, fw);
    vec3 rd = normalize(uv.x*rt + uv.y*up + FOV*fw);
    float pixAng = 1.5/iResolution.y/FOV;

    vec3 bg = vec3(0.043,0.071,0.098);
    float tb = ballHit(ro, rd);
    bool ballPending = tb > 0.0;
    vec3 acc = vec3(0); float trans = 1.0;

    const int NB = 3;
    float t = 0.02;
    float prevF[3];
    vec4 y0 = xOf(ro + rd*t);
    float lam0 = 2.0/(1.0+dot(ro+rd*t,ro+rd*t));
    for (int k=0;k<3;k++) prevF[k] = beltF(y0,k,lam0).x;

    for (int i=0;i<STEPS;i++){
        vec3 p = ro + rd*t;
        float lam = 2.0/(1.0+dot(p,p));
        vec4 y = xOf(p);
        float dmin = 1e9;
        for (int k=0;k<NB;k++){
            vec2 fb = beltF(y,k,lam);
            dmin = min(dmin, max(abs(fb.x), fb.y));
        }
        float dt = clamp(0.8*dmin/lam, 0.003*(1.0+t*0.2), 1.0);
        float tn = t + dt;
        if (ballPending && tb < tn) tn = tb;

        vec4 yn = xOf(ro + rd*tn);
        for (int k=0;k<NB;k++){
            float fn = beltF(yn,k,lam).x;
            if (sign(fn) != sign(prevF[k])){
                float a = t, b = tn, fa = prevF[k];
                for (int j=0;j<8;j++){
                    float m = 0.5*(a+b);
                    float fm = beltF(xOf(ro+rd*m),k,lam).x;
                    if (sign(fm)==sign(fa)){ a=m; fa=fm; } else { b=m; }
                }
                float th = 0.5*(a+b);
                float coc = DOF*abs(th - D)/max(th,0.2)*th;
                vec4 c = shadeBelt(ro+rd*th, rd, k, pixAng*th, coc, th);
                acc += trans*c.rgb;
                trans *= 1.0 - clamp(c.a,0.0,1.0);
            }
            prevF[k] = fn;
        }
        if (ballPending && tn >= tb){
            acc += trans*shadeBall(ro+rd*tb, rd);
            trans = 0.0; ballPending = false;
        }
        t = tn;
        if (trans < 0.01 || t > MAXT) break;
    }
    vec3 col = acc + trans*bg;
    col *= 1.0 - 0.12*dot(uv,uv);
    fragColor = vec4(col,1.0);
}
