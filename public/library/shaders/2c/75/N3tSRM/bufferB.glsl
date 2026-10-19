// #####################################################################
// ##### TAB: bufB
// #####################################################################
// =====================================================================
//  Buffer B : liquid glass shading + holographic thin film + sparkles
//  iChannel0 = Buffer A      iChannel1 = Buffer B (itself, smoky echo)
// =====================================================================

vec4 geo(ivec2 q){
    q = clamp(q, ivec2(0), ivec2(iResolution.xy) - 1);
    if(q.y == 0 && q.x < 2) q.x = 2;          // skip the state texels
    return texelFetch(iChannel0, q, 0);
}

float H(vec4 g, float Ww, float TA){ return -g.x + TA*exp(-g.y*g.y/(Ww*Ww)); }

// saturated holo spectrum: 0 red, .17 yellow, .33 green, .5 cyan, .66 blue
vec3 spectrum(float x){
    vec3 c = clamp(abs(fract(x + vec3(0., 2./3., 1./3.))*6. - 3.) - 1., 0., 1.);
    return c*c*(3. - 2.*c);
}

// holo-foil ramp: lingers on red/orange and electric blue, rushes through yellow-green-cyan
vec3 foil(float x){
    x = clamp(x, 0., 1.);
    float h = x < .38 ? mix(-.02, .085, x/.38)
            : x < .55 ? mix(.085, .50, smoothstep(.38, .55, x))
            :           mix(.50, .635, smoothstep(.55, .8, x));
    return spectrum(h);
}

float sparkles(vec2 uv, vec2 F, float t){
    vec2  d = uv - F;
    float r = length(d), a = atan(d.y, d.x)/TAU + .5, s = 0.;
    for(int L = 0; L < 3; L++){
        float fl = float(L);
        float N  = 300. + 170.*fl;
        float ca = a*N, id = floor(ca), fa = fract(ca) - .5;
        float h  = hash11(id + fl*91.7);
        float h2 = hash11(id*1.31 + fl*13.1);
        float z  = fract(h2 + t*(.22 + .35*h));
        float rp = .02 + 1.7*z*z;
        float len = .006 + .06*z*z;
        float along  = smoothstep(1., 0., abs(r - rp)/len);
        float across = smoothstep(1.2, 0., abs(fa)*TAU*r/N*iResolution.y);
        s += step(h, .45)*along*across*(.35 + .65*h2)*smoothstep(0., .08, z);
    }
    return s;
}

void mainImage(out vec4 O, in vec2 fc){
    vec4  S  = readState(iChannel0);
    float P  = S.x, t = iTime;
    ivec2 ip = ivec2(fc);
    vec2  R  = iResolution.xy;

    // pillow surface: height = -smooth F1
    vec4  g  = geo(ip);
    float Ww = mix(.035, .19, P);
    float TA = mix(.012, .05, P);                          // glass tube riding the walls
    float hx = H(geo(ip + ivec2(1, 0)), Ww, TA) - H(geo(ip - ivec2(1, 0)), Ww, TA);
    float hy = H(geo(ip + ivec2(0, 1)), Ww, TA) - H(geo(ip - ivec2(0, 1)), Ww, TA);
    float K  = R.y*.17;
    vec3  n  = normalize(vec3(-hx*K, -hy*K, 1.));
    float sl = 1. - n.z;                                   // 0 flat top .. 1 steep

    vec2  uv    = (fc - .5*R)/R.y;
    vec2  F     = focalPoint(t);
    float smoke = fbm(uv*2.6 + vec2(t*.07, -t*.05) + g.z*.5);
    float blob  = fbm(uv*1.2 + vec2(-t*.05, t*.04) + 3.7);

    // fake environment: dark overhead, bright horizon, a key light
    vec3  rd  = reflect(vec3(0, 0, -1), n);
    float env = pow(clamp(1. - rd.z, 0., 1.), .9);
    float key = pow(max(dot(rd, normalize(vec3(-.45, .55, .7))), 0.), 40.);
    float dif = clamp(dot(n, normalize(vec3(-.4, .5, .75))), 0., 1.);

    // the walls between the pillows
    float wall = exp(-g.y*g.y/(Ww*Ww));
    float hair = exp(-g.w*g.w/(.0006))*(1. - P);           // faint finer network

    float hue  = .02 + 1.9*sl + 1.0*(blob - .5) + .3*(g.z - .5) + S.y;
    vec3  film = foil(hue);

    // ---------------------------------------------- smoky silver state
    vec3 dark = vec3(.068, .066, .068)*(.35 + 1.2*smoke)*(.45 + .9*dif);
    dark += vec3(.52, .52, .54)*env*.22*(.35 + smoke);
    dark += vec3(.66, .68, .74)*(pow(wall, 3.)*.62 + hair*.14)*(.25 + 1.3*smoke);
    dark += vec3(.04, .025, .015)*g.z;
    dark += foil(clamp(hue, .62, .9))*sl*.16*smoothstep(.55, .78, blob + .3*(g.z - .5));   // ghost of the hologram
    dark += key*.25;

    // ---------------------------------------------- hologram state
    film = mix(vec3(dot(film, vec3(.3, .5, .2))), film, .74);
    float val  = smoothstep(.02, .22, sl + .25*wall)*(1. - .55*smoothstep(.45, .75, sl)*(1. - wall));        // flat tops stay dark
    vec3  pit  = vec3(.14, .05, .025)*(.35 + smoke);
    vec3  holo = mix(pit, film*(.36 + .56*env + .2*dif), val);
    vec3  glass = vec3(.46, .49, .54)*(.45 + .6*env + .25*dif);
    holo = mix(holo, glass, smoothstep(.22, .8, wall));
    holo += key*1.8;

    vec3 col = mix(dark, holo, smoothstep(.06, .8, P));

    // bright core of the walls
    col += vec3(.95, .97, 1.)*pow(wall, mix(10., 20., P))*mix(.30, .9, P);

    // warp-speed sparkle streaks + glitter dust (strongest in the dark)
    float sp = sparkles(uv, F, t)*SPARKLES*(.8 - .6*P)*(.6 + .8*S.z);
    float dust = step(.997, hash12(floor(fc*.7) + floor(t*14.)*13.1))*(1. - P)*SPARKLES;
    col += vec3(.9, .93, 1.)*(sp*1.4 + dust*.8);

    // smoky echo: last frame pulled slightly toward the node (zoom trails)
    vec2  Fp   = F*R.y + .5*R;
    float fr   = clamp(iTimeDelta*25., .2, 3.);              // tuned at 25 fps, same feel at 60
    vec2  src  = Fp + (fc - Fp)*(1. - mix(.02, .006, P)*fr);
    vec3  prev = texture(iChannel1, src/R).rgb;
    float echo = iFrame < 2 ? 0. : mix(.55, .04, P);
    float keep = 1. - pow(1. - echo*.5, fr);
    col = mix(col, prev, keep) + max(prev - col, 0.)*keep*.6;

    O = vec4(col, 1.);
}
