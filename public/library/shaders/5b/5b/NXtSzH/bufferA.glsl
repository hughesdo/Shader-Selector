

// ############################## BUFFER A ############################
// ---------------- Buffer A : scene ----------------
// iChannel0 = Music/SoundCloud/Mic (only if AUDIO_REACTIVE 1)
float gBass, gMid, gHigh;
void readAudio(){
#if AUDIO_REACTIVE
    float b=0., m=0., h=0.;
    for(int i=0;i<8;i++){
        float fi=float(i);
        b += texture(iChannel0, vec2((2.+fi*2.)/512., .25)).x;
        m += texture(iChannel0, vec2((50.+fi*14.)/512., .25)).x;
        h += texture(iChannel0, vec2((220.+fi*28.)/512., .25)).x;
    }
    gBass = smoothstep(.35,.95,b/8.); gMid = m/8.; gHigh = smoothstep(.1,.6,h/8.);
#else
    gBass = 0.; gMid = 0.; gHigh = 0.;
#endif
}

vec2 gW; float gId; float gPit; float gS; float gZone; float gEdge;
#define H0 .52

// returns shading height; sets gS (smooth structure), gPit, gZone, gId
float heightF(vec2 p, float t){
    float tt = t*SPEED;
    vec2 bc = burstCenter(t);
    vec2 d = p - bc; float r = length(d); float a = atan(d.y, d.x);
    vec3 q = vec3(p*1.5, tt*.8);
    vec2 w = vec2(fbm(q), fbm(q + vec3(5.2,1.3,2.8))) - .5;
    gW = w;
    float b = fbm(vec3(p*1.5 + w*1.4, tt*.65) + vec3(3.,7.,0.));
    // puffs: soft metaball domes on a coarse jittered grid -> rounded cotton-ball clouds
    vec2 cp = p*1.9 + w*1.1;
    vec2 ci = floor(cp), cf = fract(cp);
    float puff = 0.;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){
        vec2 g = vec2(i,j);
        vec2 h = hash22(ci+g+3.7);
        vec2 o = .5 + .42*sin(tt*.9 + 6.2831*h);
        float dd = length(g + o - cf);
        float rr = .45 + .35*hash12(ci+g+9.1);
        puff += exp(-dd*dd/(rr*rr)*2.2) * step(.3, hash12(ci+g+5.5));
    }
    b = mix(b, .28 + .42*puff, .5);
    // petals radiating from the burst centre
    float pet = sin(a*9. + sin(a*4.+tt)*1.2 - log(r+.08)*2. + tt*1.5);
    float S = b + pet*.035*smoothstep(.9,.15,r)*smoothstep(.05,.3,r);
    gS = S;
    float bill = fbm(vec3(p*3.2 + w*1.5, tt*.9)+9.);
    // pebbles: anisotropic voronoi, stretched along the burst rays
    vec2 dir = d/max(r,1e-3), perp = vec2(-dir.y, dir.x);
    float st = mix(1., mix(.45, .95, smoothstep(.0, .9, r)), smoothstep(.0,.2,r));
    vec2 pp = p*3.6 + w*2.;
    vec2 ip = floor(pp), fp = fract(pp);
    float pit = 0.; gId = 0.;
    float f1 = 9., f2 = 9.;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){
        vec2 g = vec2(i,j);
        vec2 h = hash22(ip+g);
        vec2 o = .5 + .38*sin(tt*1.6 + 6.2831*h);
        vec2 dd = g + o - fp;
        vec2 dl = vec2(dot(dd,dir), dot(dd,perp));
        float dist = length(dl*vec2(st, 1.));
        if(dist<f1){ f2=f1; f1=dist; } else if(dist<f2) f2=dist;
        float hr = hash12(ip+g+17.3);
        float rad = (.26 + .3*hr) * step(.2, hash12(ip+g+41.7));
        float dome = clamp(1.-dist/max(rad,.01), 0., 1.);
        if (dome > pit){ pit = dome; gId = hr; }
    }
    float wob = (fbm(vec3(pp*.7, tt*1.2)) - .5);
    pit = clamp(pit + wob*.3, 0., 1.);
    float zone = smoothstep(.2, .34, S) * (1.-smoothstep(.48, .56, S));
    gPit = pit; gZone = zone; gEdge = f2-f1 + wob*.12;
    float pm = 1. - smoothstep(H0-.05, H0+.0, S);           // crevice side
    gZone = pm;
    // cauliflower puffs on the cloud surface (shading only)
    vec2 kp = p*7. + w*3.;
    vec2 ki = floor(kp), kf = fract(kp);
    float cauli = 0.;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){
        vec2 g = vec2(i,j);
        vec2 o = .5 + .4*sin(tt*.8 + 6.2831*hash22(ki+g+7.));
        float dd = length(g+o-kf);
        cauli = max(cauli, sqrt(max(1.-dd*dd/.55, 0.)));
    }
    float cs = smoothstep(H0-.02, H0+.18, S);
    float H = S + (bill-.5)*.12*cs + cauli*.11*cs;
    H += sqrt(pit)*.1*pm;                                    // glossy lump domes
    return H;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    readAudio();
    vec2 p = (2.*fragCoord - iResolution.xy)/iResolution.y;
    float t = iTime;
    float e = 4.5/max(iResolution.y, 450.);

    float H  = heightF(p, t);
    vec2 w = gW; float id = gId; float S = gS; float pit = gPit; float zone = gZone;
    float Hx = heightF(p+vec2(e,0), t);
    float Hy = heightF(p+vec2(0,e), t);
    vec3 n = normalize(vec3(-(Hx-H)/e, -(Hy-H)/e, .65));

    float h0 = H0 - gBass*.03;
    float bw = .075;
    // x: 0 = crevice floor .. 1 = cloud ; film thickness sweeps black->white fast, then
    // spreads yellow / orange / red / purple / blue wide before melting into cloud
    float x = smoothstep(h0-bw, h0+bw, S);
    float R = 390.*smoothstep(.0, .09, x) + 150.*smoothstep(.08, .55, x) + 120.*smoothstep(.52, .78, x);
    // lightning lines between the lumps in the crevices
    float crev = 1.-smoothstep(.0, .35, x);
    float rimD = (pit-.13)/.08;
    float line = exp(-rimD*rimD) * (1.-smoothstep(.3,.6,x));
    R = max(R, 430.*line);
    float pe = smoothstep(.06, .4, pit);
    float lumpMask = 1. - smoothstep(.3, .6, x);
    R *= 1. - pe*lumpMask;
    x *= 1. - pe*lumpMask;
    vec3 film = pow(michelLevy(R + gMid*70.), vec3(1./2.2));
    film = mix(film, vec3(dot(film, vec3(.3,.55,.15))), .18) * vec3(1.04,.97,.95);

    vec3 L = normalize(vec3(-.45,.55,.7));
    float dif = dot(n,L);
    vec3 rf = reflect(vec3(0,0,-1), n);

    // clouds: bright cream, lavender-grey where they roll down to the edge
    float fluff = fbm(vec3(p*5. + w*3., t*SPEED*.8));
    float top = smoothstep(h0+bw*.8, h0+bw+.14, S + (H-S)*.6);
    vec3 cloudCol = mix(vec3(.7,.62,.72), vec3(1.15,1.07,1.02), clamp(.2 + top*.25 + .75*dif,0.,1.));
    cloudCol *= .97 + (fluff-.5)*.16;
    cloudCol = mix(cloudCol, cloudCol*vec3(1.06,.93,.9), smoothstep(.5,.8,fluff));

    // crevice + lumps: wet glossy slate
    vec3 base = mix(vec3(.32,.37,.45), vec3(.46,.36,.3), smoothstep(.55,.95,id));
    float spec = pow(max(dot(rf,L),0.), 12.);
    float env = smoothstep(.35,.95, rf.y*.5+.5 + .3*sin(rf.x*6.+id*9.));
    vec3 creCol = base*(.75+.55*max(dif,0.)) + vec3(.55,.68,.82)*env*.35 + spec*1.1;
    creCol += vec3(.02,.08,.14)*(1.-pe);
    creCol *= mix(.62, 1.05, pe);

    float wFilm = smoothstep(50., 200., R);
    float wCloud = smoothstep(.55, .9, x);
    vec3 col = mix(creCol, film*(1.4+.9*gHigh), wFilm);
    col = mix(col, cloudCol, wCloud);
    // HDR glow carried by the film band (feeds the bloom)
    float bandE = smoothstep(.02,.15,x)*(1.-smoothstep(.6,.9,x));
    col += film*film*bandE*(.4+gBass*1.);
    fragColor = vec4(col, H);
}

