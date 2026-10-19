// ================== SWITCHES ==================
#define AUDIO_REACTIVE 1   // 1 = music on Buffer A iChannel0 drives the visuals, 0 = pure iTime
#define SCENE 0            // 0 = auto-cycle, 1 = tentacle mandala, 2 = neon skull, 3 = skull wall, 4 = kaleido tentacles
#define PARALLAX_MODE 0    // 0 = auto-cycle, 1 = source match, 2 = orbit drift, 3 = dolly breathe, 4 = depth twist
#define SCENE_LEN 20.      // seconds per scene when SCENE 0
#define PARALLAX_LEN 9.    // seconds per parallax mode when PARALLAX_MODE 0
#define BEAT_THRESH 1.25   // onset = bass > slow bass * this. Lower it if a track won't trigger kicks
// ==============================================

#define PI 3.14159265
#define TAU 6.2831853

mat2 rot(float a){ float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x*p.y); }

float smin(float a, float b, float k){ float h = max(k - abs(a - b), 0.)/k; return min(a, b) - h*h*k*.25; }
float smax(float a, float b, float k){ return -smin(-a, -b, k); }
float sdEllipsoid(vec3 p, vec3 r){ float k0 = length(p/r), k1 = length(p/(r*r)); return k0*(k0 - 1.)/k1; }

// hue rotation around the grey axis
vec3 hue(vec3 c, float a){
    const vec3 k = vec3(.57735);
    float ca = cos(a);
    return c*ca + cross(k, c)*sin(a) + k*dot(k, c)*(1. - ca);
}

// hex lattice: x = distance to cell edge (0 edge .. .5 centre), y = distance to centre, zw = cell id
vec4 hexCell(vec2 p){
    const vec2 s = vec2(1, 1.7320508);
    vec4 hC = floor(vec4(p, p - vec2(.5, 1))/s.xyxy) + .5;
    vec4 h = vec4(p - hC.xy*s, p - (hC.zw + .5)*s);
    vec4 r = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hC.xy) : vec4(h.zw, hC.zw + .5);
    vec2 q = abs(r.xy);
    return vec4(.5 - max(dot(q, s*.5), q.x), length(r.xy), r.zw);
}
