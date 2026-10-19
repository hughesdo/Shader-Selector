// ============================================================
//  Buffer A  -  audio analyser (ArthurTent / ShaderAmp style)
//  iChannel0 = Music / SoundCloud     iChannel1 = Buffer A (itself)
// ============================================================
float fft(float x){ return texture(iChannel0, vec2(x, .25)).x; }

float band(float a, float b){
    float s = 0.;
    for(int i=0;i<8;i++) s += fft(mix(a, b, (float(i)+.5)/8.));
    return s/8.;
}

void mainImage(out vec4 O, in vec2 F){
    ivec2 p = ivec2(F);
    O = vec4(0);
    if(p.x >= 64 || p.y >= 2) return;           // only a tiny corner does work
    bool init = iFrame < 2;
    vec4 prev = init ? vec4(0) : texelFetch(iChannel1, p, 0);
    float dt = clamp(iTimeDelta, 0., .1);

    if(p.y == 1){                                 // 64-bin spectrum, fast attack, slow fall
        float v = fft((float(p.x)+.5)/64.*.75);
        float s = v > prev.x ? mix(prev.x, v, .7) : mix(prev.x, v, .12);
        O = vec4(s, 0, 0, 1);
        return;
    }

    vec4 s0 = init ? vec4(0) : texelFetch(iChannel1, ivec2(0,0), 0);
    vec4 s1 = init ? vec4(0) : texelFetch(iChannel1, ivec2(1,0), 0);

    float bass = band(.0, .06);
    float mid  = band(.12, .4);
    float high = band(.5, .9);

    if(p.x == 0){
        float sb = mix(s0.x, bass, .45), sm = mix(s0.y, mid, .25), sh = mix(s0.z, high, .35);
        float onset = smoothstep(BEAT_THRESH, BEAT_THRESH*2.5, bass - s1.w);
        float beat  = max(s0.w*exp(-dt*6.), onset);
        O = vec4(sb, sm, sh, beat);
    } else if(p.x == 1){
        float onset  = (bass - s1.w) > BEAT_THRESH ? 1. : 0.;
        bool  newHit = onset > .5 && s0.w < .6;     // rising edge of a kick
        float energy = (s0.x + s0.y + s0.z)/3.;
        float at  = s1.x + dt*(.7 + 1.1*energy*energy + .9*s0.w);
        float hue = s1.y + (newHit ? HUE_JUMP : 0.) + dt*.01;
        float rt  = s1.z + dt*(.03 + .25*energy);
        float slow = mix(s1.w, bass, .04);
        if(init){ at = iTime; hue = 0.; rt = 0.; slow = bass; }
        O = vec4(at, mod(hue, 64.), rt, slow);
    }
}
