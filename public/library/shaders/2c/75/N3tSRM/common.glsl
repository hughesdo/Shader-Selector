// #####################################################################
// ##### TAB: common
// #####################################################################
// =====================================================================
//  T R A N S F O R M  -  holographic liquid-glass cell network
//  Common tab
// =====================================================================
//
//  >>> SWITCHES <<<
//
//  AUDIO_REACTIVE 0 : self-driven pulse, matches the reference video
//  AUDIO_REACTIVE 1 : the music drives the pulse (bass = glass swell +
//                     hologram flood, highs = sparkle streaks, kicks =
//                     zoom punch). Put a Music / SoundCloud input on
//                     Buffer A -> iChannel1.
#define AUDIO_REACTIVE 1

#define AUDIO_GAIN     1.0   // >1 = more sensitive to the music
#define CELL_SCALE     4.0   // bigger = more, smaller cells
#define PULSE_PERIOD   2.0   // seconds per pulse bar in auto mode
#define SPARKLES       1.0   // 0 = no warp-speed sparkle streaks
#define CHROMA         1.0   // chromatic aberration amount

#define TAU 6.28318530718

// ---------------------------------------------------------------- hash
float hash11(float p){ p = fract(p*.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y)*p3.z); }
vec2  hash22(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*vec3(.1031,.1030,.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz)*p3.zy); }

float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p); f = f*f*(3.-2.*f);
    return mix(mix(hash12(i), hash12(i+vec2(1,0)), f.x),
               mix(hash12(i+vec2(0,1)), hash12(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p){
    float a = .5, s = 0.;
    for(int i = 0; i < 4; i++){ s += a*vnoise(p); p = mat2(1.6,1.2,-1.2,1.6)*p; a *= .5; }
    return s;
}

// --------------------------------------------- the pulse (auto mode)
// Measured off the reference: two flares per 2 s bar, ~0.22 s rise,
// ~0.15 s fall, long smoky dark stretch in between.
float flare(float x){ float s = x < 0. ? .22 : .15; return exp(-x*x/(s*s)); }
float autoPulse(float t){
    float T = PULSE_PERIOD, c = floor(t/T), lt = t - c*T, p = 0.;
    for(int k = -1; k <= 1; k++){
        float b = float(k)*T, cc = c + float(k);
        p = max(p, flare(lt - (b + .36*T)) * (.80 + .20*hash11(cc*3.1)));
        p = max(p, flare(lt - (b + .96*T)) * (.85 + .15*hash11(cc*7.7 + 1.)));
    }
    return p;
}

// convergence node all the cracks radiate from; wanders around
vec2 focalPoint(float t){
    return vec2(.42*sin(t*.23) + .12*sin(t*.61), .26*cos(t*.19 + 1.) + .08*sin(t*.53));
}

// shared state lives in texel (0,0) of Buffer A
// x = pulse, y = hue drift, z = sparkle drive, w = zoom punch
vec4 readState(sampler2D A){ return texelFetch(A, ivec2(0), 0); }
