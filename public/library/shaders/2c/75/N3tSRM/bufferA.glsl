// #####################################################################
// ##### TAB: bufA
// #####################################################################
// =====================================================================
//  Buffer A : cell geometry + shared state
//  iChannel0 = Buffer A (itself)      iChannel1 = Music (only if AUDIO_REACTIVE 1)
//  out: x = edge distance, y = dist to cell centre, z = cell id, w = fine filament edge
//  texels (0,0),(1,0) hold the pulse state
// =====================================================================

vec2 cellPt(vec2 c, float t){
    vec2 h = hash22(c);
    return .5 + .42*sin(t*(.45 + .9*h.yx) + TAU*h);
}

// smooth voronoi: x = smooth-min of squared distance (soft pillows),
// y = F2-F1 (wall distance), z = cell id.  k = sharpness of the walls
vec3 svoro(vec2 x, float t, float k){
    vec2 n = floor(x), f = fract(x);
    float acc = 0., d1 = 8., d2 = 8., id = 0.;
    for(int j = -1; j <= 1; j++) for(int i = -1; i <= 1; i++){
        vec2 g = vec2(i, j), r = g + cellPt(n + g, t) - f;
        float d = dot(r, r);
        acc += exp2(-k*d);
        if(d < d1){ d2 = d1; d1 = d; id = hash12(n + g); }
        else if(d < d2) d2 = d;
    }
    return vec3(-log2(acc)/k, sqrt(d2) - sqrt(d1), id);
}
vec2 voro2(vec2 x, float t){
    vec2 n = floor(x), f = fract(x);
    float d1 = 8., d2 = 8.;
    for(int j = -1; j <= 1; j++) for(int i = -1; i <= 1; i++){
        vec2 g = vec2(i, j), r = g + cellPt(n + g, t) - f;
        float d = dot(r, r);
        if(d < d1){ d2 = d1; d1 = d; } else if(d < d2) d2 = d;
    }
    return vec2(sqrt(d2) - sqrt(d1), sqrt(d1));
}

float audioBand(int a, int b){
    float s = 0.;
    for(int i = a; i < b; i++) s += texelFetch(iChannel1, ivec2(i, 0), 0).x;
    return s/float(b - a);
}

void mainImage(out vec4 O, in vec2 fc){
    ivec2 ip = ivec2(fc);
    float t = iTime;

    // ------------------------------------------------ state texels
    if(ip.y == 0 && ip.x < 2){
        vec4 S  = texelFetch(iChannel0, ivec2(0, 0), 0);
        vec4 S2 = texelFetch(iChannel0, ivec2(1, 0), 0);   // audio stats
        if(iFrame == 0){ S = vec4(0); S2 = vec4(.5, .7, .3, .5); }
#if AUDIO_REACTIVE
        float bass = audioBand(1, 12)*AUDIO_GAIN;
        float high = audioBand(140, 260)*AUDIO_GAIN;
        // adaptive normalisation so any track works
        S2.x = mix(S2.x, bass, .02);                       // running mean
        S2.y = max(mix(S2.y, S2.x, .005), bass);           // decaying peak
        S2.z = mix(S2.z, high, .03);
        S2.w = max(mix(S2.w, S2.z, .005), high);
        float target = clamp((bass - S2.x - .01)/max(.06, S2.y - S2.x), 0., 1.);
        target = smoothstep(.05, .95, target);
        float p = target > S.x ? mix(S.x, target, .55) : S.x*exp(-iTimeDelta*5.);   // fast attack, ~0.2s release
        float hiT = clamp((high - S2.z)/max(.04, S2.w - S2.z), 0., 1.);
        S.y = .10*sin(t*.21) + clamp((S.x - p)*4., -.1, .1); // hue: warm on the attack, blue on the release
        S.x = p;
        S.z = mix(S.z, hiT, .3);
        S.w = max(S.w*exp(-iTimeDelta*8.), target > .75 ? 1. : 0.);       // zoom punch on hard kicks
#else
        S.x = autoPulse(t);
        S.y = .10*sin(t*.21) + clamp((autoPulse(t - .06) - S.x)*2., -.1, .1);
        S.z = .5;
        S.w = autoPulse(t + .04);
#endif
        O = ip.x == 0 ? S : S2;
        return;
    }

    vec4  S = readState(iChannel0);
    float P = S.x;

    vec2 uv = (fc - .5*iResolution.xy)/iResolution.y;
    vec2 F  = focalPoint(t);
    vec2 d  = uv - F;
    float r = length(d) + 1e-4;

    // starburst: compress radius -> cells stretch into petals that
    // converge (and get finer) toward the node
    float k = mix(.68, .95, smoothstep(.0, 1.1, r));
    vec2  p = d/r*pow(r, k);
    float a = t*.04 + .3*sin(t*.11);
    p = mat2(cos(a), -sin(a), sin(a), cos(a))*p;
    p *= CELL_SCALE*(1. + .07*sin(t*.37))*(1. - .08*S.w);

    // liquid domain warp, swells on the pulse
    vec2 w = vec2(fbm(p*.55 + vec2(0., t*.16)), fbm(p*.55 + vec2(5.2, -t*.13))) - .5;
    p += w*(1.3 + 1.0*P);
    p += .34*(vec2(vnoise(p*2.1 + t*.3), vnoise(p*2.1 + 9.1 - t*.3)) - .5);   // bend the walls

    float ks = mix(26., 6., P);                       // walls go soft & fat on the pulse
    vec3 v  = svoro(p, t*.8 + P*.5, ks);
    vec2 v2 = voro2(p*2.4 + vec2(7.3, 1.7) + w*2., t*1.2);

    O = vec4(v.x, v.y, v.z, v2.x);
}
