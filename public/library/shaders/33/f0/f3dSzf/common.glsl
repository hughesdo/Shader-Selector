// ================== SWITCHES ==================
#define AUDIO_REACTIVE 1   // 1 = music on Buffer A iChannel0 drives the visuals, 0 = pure iTime
#define SCENE 0            // 0 = beat-switched auto, 1 = golden filigree, 2 = blue-gold mirror forest, 3 = neon dark mirror
#define PARALLAX_MODE 0    // 0 = auto-cycle, 1 = source match, 2 = curving drift, 3 = helix twist, 4 = accordion breathe
#define SCENE_LEN 18.      // seconds per scene when audio is off
#define PARALLAX_LEN 10.   // seconds per parallax mode in auto
#define BEAT_THRESH 1.6    // kick = bass jumps this many times its usual wobble. Lower it if a track won't trigger kicks
// ==============================================

#define PI 3.14159265
#define TAU 6.2831853

mat2 rot(float a){ float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
// integer hashes on the lattice cell (after Dave Hoskins): exact on every GPU, never go blocky as time grows
const uvec2 UI2 = uvec2(1597334673u, 3812015801u);
float hash21(vec2 p){ uvec2 q = uvec2(ivec2(p))*UI2; return float((q.x ^ q.y)*UI2.x)*2.3283064e-10; }
vec2 hash22(vec2 p){ uvec2 q = uvec2(ivec2(p))*UI2; return vec2((q.x ^ q.y)*UI2)*2.3283064e-10; }

float noise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3. - 2.*f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float sdBox(vec2 p, vec2 b){ vec2 d = abs(p) - b; return length(max(d, 0.)) + min(max(d.x, d.y), 0.); }
vec4 over(vec4 a, vec4 b){ return a + b*(1. - a.a); }    // premultiplied a over b

// hue rotation around the grey axis, as a matrix (built once per pixel)
mat3 hueMat(float a){
    const vec3 k = vec3(.57735);
    float c = cos(a), s = sin(a);
    return mat3(c) + (1. - c)*mat3(k*k.x, k*k.y, k*k.z) + s*mat3(0, k.z, -k.y, -k.z, 0, k.x, k.y, -k.x, 0);
}
