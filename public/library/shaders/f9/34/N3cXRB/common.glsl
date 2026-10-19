// ============================================================
//  COSMIC OCEAN TUNNEL  -  Common tab
//  Neon fractal fly-through: chrome marble, jellyfish,
//  spore balls + contour rings, chrome spiral ribbons.
// ============================================================

// ---- SWITCHES ---------------------------------------------
#define AUDIO_REACTIVE 1     // 1 = music drives it (Buffer A), 0 = pure iTime
#define PARALLAX_MODE  0     // 0 auto-cycle | 1 source match | 2 curving path
                             // 3 helix twist | 4 accordion | 5 orbit look-around
#define SPEED        1.15    // fly speed (depth units / sec)
#define SCENE_LEN    9.0     // depth units per scene (4 scenes loop)
#define FOCAL        0.55    // lens focal length (bigger = narrower FOV)
#define HUE_JUMP     0.11    // palette jump per detected kick
#define BEAT_THRESH  0.055   // onset threshold: bass above its slow average
#define MODE_SECONDS 14.0    // seconds per parallax mode when PARALLAX_MODE 0

#define PI  3.14159265
#define TAU 6.28318531

// ---- hashing / noise --------------------------------------
float hash11(float p){ p = fract(p*.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y)*p3.z); }
vec2  hash22(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*vec3(.1031,.1030,.0973)); p3 += dot(p3, p3.yzx+33.33); return fract((p3.xx+p3.yz)*p3.zy); }
float hash13(vec3 p3){ p3 = fract(p3*.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y)*p3.z); }

float noise3(vec3 x){
    vec3 i = floor(x), f = fract(x);
    f = f*f*(3.-2.*f);
    float a = hash13(i),            b = hash13(i+vec3(1,0,0));
    float c = hash13(i+vec3(0,1,0)), d = hash13(i+vec3(1,1,0));
    float e = hash13(i+vec3(0,0,1)), g = hash13(i+vec3(1,0,1));
    float h = hash13(i+vec3(0,1,1)), k = hash13(i+vec3(1,1,1));
    return mix(mix(mix(a,b,f.x),mix(c,d,f.x),f.y), mix(mix(e,g,f.x),mix(h,k,f.x),f.y), f.z);
}
float fbm3(vec3 p, int oct){
    float s = 0., a = .5;
    for(int i=0;i<4;i++){
        if(i>=oct) break;
        s += a*noise3(p); p = p*2.03 + vec3(1.7,9.2,3.1); a *= .5;
    }
    return s;
}

// ---- palette: rainbow thin-film leaning violet ------------
vec3 iri(float t){ return .5 + .5*cos(TAU*(t + vec3(0.,.33,.67))); }
vec3 neon(float t){ vec3 c = iri(t); c = c*c*1.35; return mix(c, vec3(.5,.2,1.1), .14); }

mat2 rot2(float a){ float c = cos(a), s = sin(a); return mat2(c,-s,s,c); }

// ---- Buffer A layout (shared by both passes) --------------
// texel (0,0): bass, mid, high, beat
// texel (1,0): amplified time, hue accumulator, rotation accumulator, slow bass
// row 1, x 0..63: smoothed spectrum
