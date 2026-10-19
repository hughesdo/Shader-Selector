// ============================================================
//  "Neural Bloom"  -  audio-reactive thread web
//  Image: iChannel1 = Buffer A (audio state)
//         iChannel2 = Buffer B (precomputed geometry, once/frame)
//
//  Buffer B holds, per thread, the padded screen-space AABB of
//  its polyline plus the 13 projected polyline points and the
//  per-segment reciprocal length. So each thread is rejected
//  with ONE fetch + four compares, and the inner loop has no
//  hashes, no trig, no projections and no divisions.
// ============================================================



const float PI = 3.14159265;

vec3 hsv(float h, float s, float v)
{
    vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), k, s);
}

vec4 S(int i) { return texelFetch(iChannel1, ivec2(i, 0), 0); }
vec4 GB(int i, int r) { return texelFetch(iChannel2, ivec2(i, r), 0); }

mat2 rot2(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

void ink(inout vec3 col, vec3 a, float hue, float sat, float dark)
{
#if BG_MODE == 0
    vec3 c = hsv(hue, sat, 0.95 - dark);
    c = pow(c, vec3(1.0 + dark * 0.9));
    col *= 1.0 - a * (1.0 - c);
#elif BG_MODE == 1
    vec3 c = hsv(hue, sat * 0.85, 1.0) * (0.75 + dark);
    col += a * c;
#else
    vec3 c = hsv(hue, min(sat + 0.1, 1.0), 0.95 - dark * 0.6);
    col = mix(col, c, a);
#endif
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Full screen native coordinates
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.0 / iResolution.y;

    vec4 PH   = S(4);
    vec4 MISC = S(5);
    if (PH.x == 0.0 && PH.z == 0.0)
    {
        PH = vec4(iTime * 0.5, iTime * 0.012, iTime * 0.06, 0.0);
        MISC = vec4(0.0, iTime * 0.15, 0.0, 0.0);
    }
    vec4 HIT = S(3);
    float kick   = PH.w;
    float energy = MISC.z;

    float ra = PH.z * ROT_SPEED;
    uv = rot2(0.08 * sin(ra * 0.27)) * uv;

#if ABERRATION == 1 && BG_MODE != 2
    vec2 ab = normalize(uv + 1e-4) * (px * (1.6 * kick + 1.2 * HIT.w * HIT.w));
#else
    vec2 ab = vec2(0.0);
#endif

#if BG_MODE == 0
    vec3 col = vec3(0.985, 0.982, 0.975);
#elif BG_MODE == 1
    vec3 col = vec3(0.0);
#else
    vec3 col = vec3(0.0, 1.0, 0.0);
#endif

    float glow = 0.0;
    vec3  glowCol = vec3(0.0);

    const float invSEGS = 1.0 / float(SEGS);

    // ---- threads: node -> hub ----
    for (int n = 0; n < NODES; n++)
    {
        // One fetch: padded screen-space AABB of this thread's polyline.
        vec4 bb = GB(n, 0);
        if (uv.x < bb.x || uv.x > bb.z || uv.y < bb.y || uv.y > bb.w) continue;

        vec4 c1 = GB(n, 1);   // wc, hue, e
        vec4 c2 = GB(n, 2);   // gr2, splitV.xy
        vec4 q0 = GB(n, ROW_PT0);   // point 0: x, y, persp

        float gr2 = c2.x;
        vec2  splitV = c2.yz;
        float wc = c1.x, hue = c1.y, e = c1.z;

        vec2 abT = ab + splitV;
        bool hasSplit = dot(abT, abT) > 1e-8;
        vec2 tR = uv + abT, tB = uv - abT;

        vec3 dmin2 = vec3(1e8);
        float tAt = 0.0, pAt = 1.0;
        vec2 prev = q0.xy;
        float prevZ = q0.z;

        for (int s = 1; s <= SEGS; s++)
        {
            vec4 pt = GB(n, ROW_PT0 + s);      // x, y, persp, 1/|ba|^2
            vec2 ba = pt.xy - prev;
            float invL2 = pt.w;

            vec2 paG = uv - prev;
            float tt = clamp(dot(paG, ba) * invL2, 0.0, 1.0);
            vec2 dvecG = paG - ba * tt;
            float dG2 = dot(dvecG, dvecG);

            float dR2 = dG2, dB2 = dG2;

            if (hasSplit && dG2 < 0.003)
            {
                vec2 paR = tR - prev;
                float ttR = clamp(dot(paR, ba) * invL2, 0.0, 1.0);
                vec2 dvecR = paR - ba * ttR;
                dR2 = dot(dvecR, dvecR);

                vec2 paB = tB - prev;
                float ttB = clamp(dot(paB, ba) * invL2, 0.0, 1.0);
                vec2 dvecB = paB - ba * ttB;
                dB2 = dot(dvecB, dvecB);
            }

            if (dG2 < dmin2.y) {
                tAt = (float(s) - 1.0 + tt) * invSEGS;
                pAt = mix(prevZ, pt.z, tt);
            }

            dmin2 = min(dmin2, vec3(dR2, dG2, dB2));
            prev = pt.xy;
            prevZ = pt.z;
        }

        vec3 dmin = sqrt(dmin2); // Only 1 sqrt per thread

        float w = wc * pAt * mix(0.55, 1.2, tAt);
        float depthFade = clamp((pAt - 0.40) * (1.0 / 0.30), 0.3, 1.0);
        float opacity = clamp(w / (0.75 * px), 0.6, 1.0) * mix(0.55, 1.0, depthFade);
        float wd = max(w, 0.5 * px);
#if BG_MODE == 2
        opacity = 1.0; wd = max(w, 0.7 * px);
#endif
        vec3 a = clamp((wd - dmin) / px + 0.5, 0.0, 1.0) * opacity;

        if (any(greaterThan(a, vec3(0.0)))) {
            ink(col, a, hue, 0.85 + 0.15 * e, 0.04 + 0.22 * e);
        }

        if (dmin2.y < 9.0 * gr2) {
            float gl = exp(-dmin2.y / gr2) * (0.15 + e) * w * 120.0;
            glow += gl;
            glowCol += gl * hsv(hue, 0.8, 1.0);
        }
    }

    // ---- nodes + hubs ----
    for (int n = 0; n < NODES + HUBS; n++)
    {
        vec4 c8 = GB(n, ROW_NODE);   // q.xy, (r+0.05)^2, r
        vec2 dp = uv - c8.xy;
        float d2 = dot(dp, dp);
        if (d2 > c8.z) continue;

        vec4 c9 = GB(n, ROW_NODE + 1);   // splitV.xy, hue
        float r = c8.w;
        float hue = c9.z;

        float dCenter = sqrt(d2);
        vec2 abN = ab + c9.xy;
        vec3 d = vec3(length(dp + abN), dCenter, length(dp - abN));

        vec3 a = clamp((r - d) / px + 0.5, 0.0, 1.0);

        if (any(greaterThan(a, vec3(0.0)))) {
            ink(col, a, hue, 0.95, 0.32);
        }

        float rGlow2 = r * r * 9.0;
        if (d2 < 9.0 * rGlow2) {
            float gl = exp(-d2 / rGlow2) * r * 60.0 * (0.4 + kick);
            glow += gl;
            glowCol += gl * hsv(hue, 0.8, 1.0);
        }
    }

    // ---- free-floating specks (space dust) ----
    for (int m = 0; m < MOTES; m++)
    {
        vec4 c = GB(m, ROW_MOTE);   // q.xy, (r+0.5px)^2, r
        vec2 dp = uv - c.xy;
        float d2 = dot(dp, dp);
        if (d2 >= c.z) continue;

        float r = c.w;
        float hue = GB(m, ROW_MOTE + 1).x;

        float d = sqrt(d2);
        float a = clamp((r - d) / px + 0.5, 0.0, 1.0) * 0.85;
        ink(col, vec3(a), hue, 0.7, 0.25);
    }

    // ---- halo composite ----
    glow = min(glow, 3.0);
    vec3 gc = glowCol / max(glow, 1e-4);
#if BG_MODE == 0
    col *= 1.0 - clamp(glow * 0.06, 0.0, 0.35) * (1.0 - gc * 0.55);
#elif BG_MODE == 1
    col += gc * glow * 0.10;
    col = 1.0 - exp(-col * 1.25);
    col = pow(col, vec3(0.92));
#endif

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
