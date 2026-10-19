/* =====================================================================
   T R A N S F O R M  -  Shadertoy setup (4 tabs)
   ---------------------------------------------------------------------
   Common   : paste the COMMON section
   Buffer A : iChannel0 = Buffer A        iChannel1 = Music/SoundCloud (only for AUDIO_REACTIVE 1)
   Buffer B : iChannel0 = Buffer A        iChannel1 = Buffer B
   Image    : iChannel0 = Buffer B        iChannel1 = Buffer A
   All buffer channels: filter = linear, wrap = clamp (Shadertoy defaults).
   Flip audio on/off with  #define AUDIO_REACTIVE  at the top of Common.
   ===================================================================== */

// #####################################################################
// ##### TAB: image
// #####################################################################
// =====================================================================
//  Image : chromatic aberration, radial zoom smear, glow, grade
//  iChannel0 = Buffer B      iChannel1 = Buffer A
// =====================================================================

vec3 tapB(vec2 uv){ return texture(iChannel0, uv).rgb; }

void mainImage(out vec4 O, in vec2 fc){
    vec2  R  = iResolution.xy;
    vec2  uv = fc/R;
    vec4  S  = readState(iChannel1);
    float P  = S.x, t = iTime;

    vec2 Fuv = (focalPoint(t)*R.y + .5*R)/R;     // node in 0..1 coords
    vec2 dir = uv - Fuv;
    vec2 cdir = dir/max(length(dir), 1e-4)*min(length(dir), .3);   // capped so fringes stay thin

    // radial RGB split
    float ca = CHROMA*mix(.012, .02, P);
    vec3 col;
    col.r = tapB(uv + cdir*ca).r;
    col.g = tapB(uv).g;
    col.b = tapB(uv - cdir*ca).b;

    // zoom smear toward the node (heavy in the dark, light in the flare)
    float len = mix(.10, .035, P) + .05*S.w;
    vec3 zb = vec3(0), zh = vec3(0);
    float ws = 0.;
    for(int i = 1; i <= 14; i++){
        float k = float(i)/14.;
        vec2  q = Fuv + dir*(1. - len*k);
        vec3  c = vec3(tapB(q + cdir*ca).r, tapB(q).g, tapB(q - cdir*ca).b);
        float w = 1. - k*.7;
        zb += c*w; zh += max(c - .55, 0.)*w; ws += w;
    }
    zb /= ws; zh /= ws;
    col = mix(col, zb, mix(.32, .04, P)) + zh*mix(1.4, .6, P);

    // cheap bloom
    vec3 gl = vec3(0);
    for(int i = 0; i < 8; i++){
        float a = float(i)*TAU/8. + .4;
        vec2  o = vec2(cos(a), sin(a))*mix(.012, .02, P)*vec2(R.y/R.x, 1.);
        gl += max(tapB(uv + o) - .6, 0.) + max(tapB(uv + o*2.3) - .7, 0.);
    }
    col += gl/16.*mix(.6, 1.1, P);

    // grade: filmic shoulder, slight lift, vignette, grain
    col = col*(1. + .15*P);
    col = mix(col, col*col*1.6, .35*P);                 // punchier contrast in the flare
    col = 1. - exp(-col*1.45);
    col = pow(col, vec3(.95));
    vec2 v = uv - .5;
    col *= 1. - .35*dot(v, v)*1.6;
    col += (hash12(fc + fract(t)*137.) - .5)*.035;

    O = vec4(clamp(col, 0., 1.), 1.);
}
