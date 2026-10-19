// =====================================================================
//  LUMINOUS LOTUS GATES  ::  COMMON tab  (shared by Buffer A + Image)
// =====================================================================

// ---------------- MASTER SWITCHES ------------------------------------
#define AUDIO_REACTIVE 1   // 1 = music drives it (needs Buffer A + music on its iChannel0)
                           // 0 = pure video-match mode, runs on iTime only
#define PARALLAX_MODE  0   // 0 = auto-cycle all modes (crossfades every 14 s)
                           // 1 = classic straight tunnel (closest to the source video)
                           // 2 = helix twist   (rotation grows with depth)
                           // 3 = curving drift (camera rides a bending path, far end swings)
                           // 4 = accordion     (depth spacing breathes in a travelling wave)
                           // 5 = counter-spin  (alternate gates rotate opposite ways)
#define GATES 9            // gates in flight (visible depth). 7 = faster, 11 = deeper
// ----------------------------------------------------------------------

#define PI  3.14159265
#define TAU 6.28318531

mat2 rot2(float a){ float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

float hash11(float p){ p = fract(p * .1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p){ vec3 q = fract(p.xyx * .1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }

// thin-film iridescence, skewed toward the source's magenta / violet / cyan / lime
vec3 iri(float t){
    vec3 c = .5 + .5 * cos(TAU * (t + vec3(0., .33, .67)));
    c *= c;
    c.b = max(c.b, c.r * (1. - c.g) * .85);          // push reds toward magenta
    return c * vec3(1.15, 1., 1.4) + vec3(.03, 0., .06);
}
