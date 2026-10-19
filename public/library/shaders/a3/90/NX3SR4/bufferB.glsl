// ============================================================
//  BUFFER B  -  geometry precompute  (runs once per frame)
//  Holds every fragCoord-independent value the Image pass used
//  to recompute, for all 64 threads / 68 nodes / 40 motes.
//  iChannel0 = Buffer A
//
//  Layout (col = object index, row = field):
//    row 0      : thread  [polyline AABB, already padded] -> 1 fetch cull
//    row 1      : thread  [wc hue e 0]
//    row 2      : thread  [gr2 splitV.x splitV.y 0]
//    rows 3..15 : thread  point s = 0..SEGS -> [x y persp 1/|ba|^2]
//    row 16     : node/hub [q.x q.y (r+0.05)^2 r]
//    row 17     : node/hub [splitV.x splitV.y hue 0]
//    row 18     : mote     [q.x q.y (r+0.5px)^2 r]
//    row 19     : mote     [hue 0 0 0]
// ============================================================

const float PI = 3.14159265;
const float invSEGS = 1.0 / float(SEGS);

float h11(float n) { return fract(sin(n * 127.1 + SEED * 17.13) * 43758.5453); }
vec4  h41(float n) { return fract(sin(n * vec4(127.1, 311.7, 74.7, 269.5) + (SEED * 17.13)) * 43758.5453); }

float hueMap(float h)
{
    float tri = abs(fract(h * 0.5) * 2.0 - 1.0);
#if BG_MODE == 2
    return fract(0.55 + tri * 0.60);
#elif BG_MODE == 0
    return fract(0.45 + tri * 0.66);
#else
    return fract(h);
#endif
}

mat3 rotY(float a) { float c = cos(a), s = sin(a); return mat3(c, 0, -s, 0, 1, 0, s, 0, c); }
mat3 rotX(float a) { float c = cos(a), s = sin(a); return mat3(1, 0, 0, 0, c, s, 0, -s, c); }

mat3  gR;
float gZoom;
float gDrift;

vec3 project(vec3 p)
{
    vec3 q = gR * p;
    float persp = 2.0 / (3.4 + q.z);
    return vec3(q.xy * (persp * gZoom), persp);
}

vec3 nodePos(float i, vec4 h)
{
    float r = mix(0.30, 1.25, sqrt(h.x));
    float a = h.y * 2.0 * PI;
    vec3 p = vec3(cos(a) * r * 1.15, (h.z - 0.5) * 0.95, sin(a) * r);
    vec4 g = h41(i + 91.0);
    p += 0.13 * vec3(sin(gDrift * (0.6 + g.x) + g.y * 6.28),
                     0.7 * sin(gDrift * (0.5 + g.z) + g.w * 6.28),
                     cos(gDrift * (0.7 + g.y) + g.x * 6.28));
    return p;
}

vec3 hubPos(float j)
{
    vec4 h = h41(j * 7.0 + 300.0);
    vec3 p = (h.xyz - 0.5) * vec3(1.1, 0.5, 1.0);
    p += 0.09 * vec3(sin(gDrift * 0.45 + j * 2.1), cos(gDrift * 0.38 + j * 1.3), sin(gDrift * 0.33 + j * 3.7));
    return p;
}

vec2 splitVec(float fi, vec4 BIG, float px)
{
#if BASS_SPLIT == 1 && BG_MODE != 2
    if (BIG.x <= 0.001) return vec2(0.0);
    vec4 hs = h41(fi * 3.1 + BIG.y * 17.7);
    if (hs.x < SPLIT_SHARE)
        return vec2(cos(hs.y * 6.2832), sin(hs.y * 6.2832)) * (px * SPLIT_PX * (0.6 + 0.8 * hs.z) * BIG.x);
#endif
    return vec2(0.0);
}

// thread polyline point s (0..SEGS), exactly as the original evaluated it
// (kept INLINE at each use: a helper call changes ANGLE's FMA contraction and
//  shifts the antialiased thread edges by a fraction of a pixel)

vec4 S(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0); }

void mainImage(out vec4 o, in vec2 fc)
{
    ivec2 p = ivec2(fc);
    if (p.y >= ROW_END || p.x >= BUF_W) { o = vec4(0.0); return; }

    vec4 HIT  = S(3);
    vec4 PH   = S(4);
    vec4 MISC = S(5);
    vec4 BIG  = S(6);
    if (PH.x == 0.0 && PH.z == 0.0)
    {
        PH = vec4(iTime * 0.5, iTime * 0.012, iTime * 0.06, 0.0);
        MISC = vec4(0.0, iTime * 0.15, 0.0, 0.0);
    }
    float kick   = PH.w;
    float energy = MISC.z;
    float flash  = MISC.w;
    gDrift = MISC.y;

    float ra = PH.z * ROT_SPEED;
    gR = rotX(0.32 + 0.12 * sin(ra * 0.41)) * rotY(ra);
    gZoom = 1.0 + 0.035 * kick + 0.02 * energy;

    float huePal = PH.y + 0.10 * flash;
    float px = 1.0 / iResolution.y;

    vec3 gHubs[HUBS];
    vec3 gHubProj[HUBS];
    for (int j = 0; j < HUBS; j++) { gHubs[j] = hubPos(float(j)); gHubProj[j] = project(gHubs[j]); }

    // ---- threads (rows 0..15) ----
    if (p.y < ROW_NODE)
    {
        float fi = float(p.x);
        vec4 h  = h41(fi + 1.0);
        vec4 h2 = h41(fi + 51.0);
        int hubIdx = int(floor(pow(h2.x, 1.6) * float(HUBS)));
        vec3 A  = nodePos(fi, h);
        vec3 B  = gHubs[hubIdx];
        vec3 pa = project(A);
        vec3 pb = gHubProj[hubIdx];
        float L = length(B - A);
        float bow1 = (h.z - 0.5) * 0.5, bow2 = (h.w - 0.5) * 0.4;
        int bin = int(6.0 * pow(58.0, h2.y));
        float raw = texelFetch(iChannel0, ivec2(bin, 1), 0).x;
        int g = bin < 30 ? 1 : (bin < 110 ? 2 : 3);
        float bh = g == 1 ? HIT.y : (g == 2 ? HIT.z : HIT.w);
        float lv = clamp((raw - (0.63 - 0.30 * h2.y) + LEVEL_BOOST) * (1.0 / 0.24), 0.0, 1.0);
        float e  = clamp(0.4 * bh * (0.35 + 0.9 * h2.z) + 0.8 * lv * (0.5 + 0.7 * h.x) + 0.2 * kick * h2.w, 0.0, 1.0);
        float amp = 0.03 + 0.07 * e + 0.035 * kick;
        float maxDeflect = length(vec2(bow1, bow2)) + amp;
        float margin = L * maxDeflect * max(pa.z, pb.z) * gZoom + 0.015;

        float gr = 0.012 + 0.03 * e;
        float gr2 = gr * gr;
        float wc = (0.0008 + 0.0055 * e * e * e + 0.0022 * energy * h.x * h.x);
        float hue = hueMap(huePal + h.y * 1.7 + float(hubIdx) * 0.23);
        vec2 splitV = splitVec(fi, BIG, px);

        if (p.y == 0)
        {
            // conservative reach of this thread's ink + glow, then its padded AABB.
            // margin is still required by later consumers, so keep the same math.
            vec3 dir = B - A;
            vec3 e1 = normalize(cross(dir, vec3(0.0, 1.0, 0.3)));
            vec3 e2 = normalize(cross(dir, e1));
            float freq = 2.2 + 3.8 * h2.w;
            float wph  = PH.x * (0.6 + 0.8 * h.x) + fi * 1.7;
            vec3 eBow  = L * (e1 * bow1 + e2 * bow2);
            vec3 eAmp1 = (L * amp) * e1;
            vec3 eAmp2 = (L * amp) * e2;
            vec2 bmin = vec2(1e9), bmax = vec2(-1e9);
            float maxP = 0.0;
            for (int s = 0; s <= SEGS; s++)
            {
                vec3 pt;
                if (s == 0)        pt = pa;
                else if (s == SEGS) pt = pb;
                else
                {
                    float t = float(s) * invSEGS;
                    float env = 4.0 * t * (1.0 - t);
                    pt = project(A + dir * t + env * (eBow + eAmp1 * sin(t * freq + wph)
                                                         + eAmp2 * cos(t * freq * 0.8 - wph * 0.9 + h.y * 6.0)));
                }
                bmin = min(bmin, pt.xy);
                bmax = max(bmax, pt.xy);
                maxP = max(maxP, pt.z);
            }
            // w = wc * pAt * mix(0.55,1.2,tAt);  pAt = perspective depth, which can exceed 1,
            // so bound it with the largest persp of this thread's own points.
            float inkReach  = max(wc * maxP * 1.2, 0.7 * px) + 0.5 * px;
            float glowReach = 3.0 * gr;                       // dmin2.y < 9*gr2  ->  dmin < 3*gr
            float shiftMax  = px * (1.6 * kick + 1.2 * HIT.w * HIT.w) + length(splitV);
            float reach = max(inkReach, glowReach) + shiftMax + 0.004;
            o = vec4(bmin - reach, bmax + reach); return;
        }
        if (p.y == 1) { o = vec4(wc, hue, e, margin); return; }
        if (p.y == 2) { o = vec4(gr2, splitV.x, splitV.y, 0.0); return; }

        vec3 dir = B - A;
        vec3 e1 = normalize(cross(dir, vec3(0.0, 1.0, 0.3)));
        vec3 e2 = normalize(cross(dir, e1));
        float freq = 2.2 + 3.8 * h2.w;
        float wph  = PH.x * (0.6 + 0.8 * h.x) + fi * 1.7;
        vec3 eBow  = L * (e1 * bow1 + e2 * bow2);
        vec3 eAmp1 = (L * amp) * e1;
        vec3 eAmp2 = (L * amp) * e2;

        int s = p.y - ROW_PT0;
        vec3 pt;
        if (s == 0)        pt = pa;
        else if (s == SEGS) pt = pb;
        else
        {
            float t = float(s) * invSEGS;
            float env = 4.0 * t * (1.0 - t);
            pt = project(A + dir * t + env * (eBow + eAmp1 * sin(t * freq + wph)
                                                 + eAmp2 * cos(t * freq * 0.8 - wph * 0.9 + h.y * 6.0)));
        }
        float il2 = 0.0;
        if (s >= 1)
        {
            vec3 qp;
            if (s == 1) qp = pa;
            else
            {
                float tp = float(s - 1) * invSEGS;
                float envp = 4.0 * tp * (1.0 - tp);
                qp = project(A + dir * tp + envp * (eBow + eAmp1 * sin(tp * freq + wph)
                                                     + eAmp2 * cos(tp * freq * 0.8 - wph * 0.9 + h.y * 6.0)));
            }
            vec2 ba = pt.xy - qp.xy;
            il2 = 1.0 / max(dot(ba, ba), 1e-8);
        }
        o = vec4(pt.xy, pt.z, il2);
        return;
    }

    // ---- nodes + hubs (rows 16..17) ----
    if (p.y < ROW_MOTE)
    {
        float fi = float(p.x);
        bool isHub = p.x >= NODES;
        int hubIdx = isHub ? (p.x - NODES) : 0;
        vec4 h  = h41(fi + 1.0);
        vec4 h2 = h41(fi + 51.0);
        vec3 P  = isHub ? gHubs[hubIdx] : nodePos(fi, h);
        vec3 q  = isHub ? gHubProj[hubIdx] : project(P);
        float big = step(h.w, 0.13);
        float r = isHub ? 0.0065 : mix(0.0038 + 0.0042 * h.x, 0.0145, big);
        float bh = h2.y < 0.33 ? HIT.y : (h2.y < 0.66 ? HIT.z : HIT.w);
        r *= q.z * (1.0 + 0.55 * HIT.x * h2.z + 0.45 * kick * big + 0.3 * bh);
        float hub = isHub ? float(hubIdx) : floor(pow(h2.x, 1.6) * float(HUBS));
        float hue = hueMap(huePal + h.y * 1.7 + hub * 0.23);
        vec2 splitV = isHub ? vec2(0.0) : splitVec(fi, BIG, px);
        float maxR = r + 0.05;
        if (p.y == ROW_NODE) o = vec4(q.xy, maxR * maxR, r);
        else           o = vec4(splitV, hue, 0.0);
        return;
    }

    // ---- motes (rows 18..19) ----
    {
        float fi = float(p.x) + 500.0;
        vec4 h = h41(fi);
        vec3 P = (h.xyz - 0.5) * vec3(3.0, 1.3, 2.6);
        P += 0.2 * vec3(sin(gDrift * 0.3 + h.w * 6.3), sin(gDrift * 0.23 + h.x * 6.3), cos(gDrift * 0.27 + h.y * 6.3));
        vec3 q = project(P);
        float r = (0.0022 + 0.003 * h.w) * q.z * (1.0 + 0.6 * HIT.w);
        float hue = hueMap(huePal + h.z * 1.7);
        float maxR = r + 0.5 * px;
        if (p.y == ROW_MOTE) o = vec4(q.xy, maxR * maxR, r);
        else           o = vec4(hue, 0.0, 0.0, 0.0);
    }
}
