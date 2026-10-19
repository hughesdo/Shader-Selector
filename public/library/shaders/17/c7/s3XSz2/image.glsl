// ============================================================
//  SILK AURORA
//  
//  Twisting ribbons, sweeping glints, RGB dispersion,
//  light beads riding the strands, wind gusts, flow warp,
//  nebula haze, slow camera roll
//
//  AUDIO (iChannel0 = Music / SoundCloud / Mic):
//   bass  -> ribbon glow + halo swell, palette jumps on hits,
//            gust ripples, nebula breathes, slight zoom punch
//   bands -> each strand glows with its own slice of the spectrum
//   highs -> glints, sparkles
//   with no audio it looks exactly like the original
// ============================================================
#define PI  3.14159265
#define TAU 6.28318530

// ---------------- ORIGINAL TWEAKS ----------------
#define HILITE_AMT   0.25   // white flash strength
#define HILITE_POW   14.0   // how vertical a strand must be to flash
#define IRI_SLOPE    0.70   // color spread along the bend
#define IRI_SPEED    0.03   // hue drift over time
#define SAT          1.55   // saturation pop
#define EXPOSURE     0.55   // tonemap exposure
#define BLACK_FLOOR  0.025  // haze crush before tonemap
#define GAMMA        0.72   // display gamma
#define CORE_BRIGHT  0.25   // tight bright core weight

// ---------------- NEW TWEAKS ----------------
#define TWIST_AMT    0.80   // ribbon twist pinch. 0 = flat threads
#define TWIST_FREQ   1.60   // twists per unit height
#define SHEEN_AMT    1.10   // glint where the ribbon faces you
#define DISPERSION   0.012  // RGB fringe split on steep strands
#define PULSE_AMT    1.40   // light beads traveling up strands
#define PULSE_SPEED  0.90
#define GUST_AMT     0.35   // wind gust ripple strength
#define GUST_PERIOD  9.0    // seconds between gusts
#define WARP_AMT     0.18   // flow field swirl
#define NEBULA_AMT   0.12   // background haze
#define CAM_ROLL     0.08   // camera roll amount
// ----------------------------------------------------

// ---------------- AUDIO TWEAKS ----------------
#define AUDIO_GLOW   1.60   // how hard the ribbon glow breathes with the music
#define HALO_SWELL   2.00   // soft halo width/brightness on bass
#define BEAT_HUE     0.30   // palette jump on bass hits
#define BEAT_ROLL    0.10   // extra camera roll swing driven by energy
#define BEAT_ZOOM    0.05   // zoom punch on bass hits
// ----------------------------------------------------

float gBass, gMid, gHigh, gHit, gEnergy;
float fft(float u){ return texture(iChannel0, vec2(u, 0.25)).x; }
void readAudio(){
    float b = 0.0, m = 0.0, h = 0.0;
    for(int i = 0; i < 4; i++){
        float fi = float(i);
        b += fft(0.01 + fi*0.015);
        m += fft(0.12 + fi*0.060);
        h += fft(0.45 + fi*0.100);
    }
    // the FFT texture is in dB, so music sits in a narrow range: stretch each band
    float bRaw = b*0.25;
    gBass = smoothstep(0.70, 0.90, bRaw);
    gMid  = smoothstep(0.30, 0.60, m*0.25);
    gHigh = smoothstep(0.15, 0.45, h*0.25);
    gHit  = smoothstep(0.81, 0.87, bRaw);                 // beat gate: top of the bass range
    gEnergy = gBass*0.6 + gMid*0.3 + gHigh*0.1;
}

float hash11(float n){ return fract(sin(n*127.1)*43758.5453); }
float hash21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7)))*43758.5453); }

float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3.0 - 2.0*f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p){
    float s = 0.0, a = 0.5;
    for(int i = 0; i < 4; i++){
        s += a*vnoise(p);
        p = mat2(1.6, 1.2, -1.2, 1.6)*p;
        a *= 0.5;
    }
    return s;
}

vec3 iri(float t){
    return 0.5 + 0.5*cos(TAU*t + vec3(0.0, 2.1, 4.2));
}

vec3 bundle(vec2 uv, float depth, float seed, float t, float gust){
    vec3 acc = vec3(0.0);
    float drift = t*(0.15 + depth*0.35);
    // slow moving key light that makes glints sweep across the scene
    float keyLight = 0.35 + 0.65*pow(0.5 + 0.5*sin(uv.x*1.3 - uv.y*0.4 + t*0.35), 2.0);

    for(float i = 0.0; i < 14.0; i++){
        float h  = hash11(i + seed*61.0);
        float h2 = hash11(i + seed*61.0 + 29.0);
        float ph = drift*(0.6 + h*0.8) + h*PI*4.0;
        float f1 = 1.2 + h2*1.5;
        float f2 = 3.1 + h*2.0;

        // gust: a traveling ripple that rolls up the strands
        float gph = uv.y*4.0 - t*3.0 + h*6.0 + depth*2.0;

        float xc = (h - 0.5)*3.4
                 + 0.55*sin(uv.y*f1 + ph)
                 + 0.22*sin(uv.y*f2 - ph*1.7)
                 + 0.30*sin(t*0.20 + h2*9.0)
                 + GUST_AMT*gust*sin(gph);
        float dx = uv.x - xc;
        float slope = 0.55*f1*cos(uv.y*f1 + ph)
                    + 0.22*f2*cos(uv.y*f2 - ph*1.7)
                    + GUST_AMT*gust*4.0*cos(gph);

        // ribbon twist: edge-on = thin, face-on = wide + glint
        float tp   = uv.y*TWIST_FREQ*(0.7 + h2) + t*(h - 0.5)*0.8 + h*9.0;
        float face = abs(cos(tp));
        float wmul = mix(1.0, 0.12 + 0.88*face, TWIST_AMT);

        float w = (0.006 + 0.010*depth)*(1.0 + 0.6*abs(slope))*wmul;

        // per-channel offset = prismatic fringe on steep sections
        vec3 dxv  = dx + vec3(-1.0, 0.0, 1.0)*DISPERSION*clamp(slope, -3.0, 3.0);
        // each strand listens to its own slice of the spectrum
        float band = smoothstep(0.30, 0.90, fft(0.02 + h*0.45));
        float glow = 1.0 + AUDIO_GLOW*(0.6*gBass + 0.8*band);

        vec3 core = wmul*w*CORE_BRIGHT/(dxv*dxv + w*w)*glow;
        float swell = 1.0 + HALO_SWELL*gBass;
        float sheath = exp(-dx*dx/(w*w*90.0*swell))*0.30*(1.0 + HALO_SWELL*(gBass + 0.5*band));

        // thin-film hue also shifts with viewing angle of the twist; bass hits jump the palette
        vec3 tint = iri(slope*IRI_SLOPE + h*0.9 + t*IRI_SPEED + depth*0.33 + 0.18*sin(tp)
                        + BEAT_HUE*gHit + 0.10*gMid);
        tint = mix(tint, vec3(1.0, 0.97, 0.92),
                   pow(max(1.0 - abs(slope), 0.0), HILITE_POW)*HILITE_AMT);

        float glint = pow(face, 40.0)*SHEEN_AMT*keyLight*(1.0 + 2.0*gHigh);

        // beads of light racing up about half the strands
        float pulse = pow(0.5 + 0.5*sin(uv.y*(2.0 + h*2.0)
                          - t*PULSE_SPEED*(0.7 + h2) + h*TAU*3.0), 40.0)
                    * step(0.45, h2)*PULSE_AMT*(1.0 + 2.5*band);

        float fade = smoothstep(-1.6, -0.9, uv.y + h*0.6)
                   * smoothstep(1.4, 0.6, uv.y - h2*0.4);

        vec3 light = tint*(core*(1.0 + glint + pulse) + sheath*(1.0 + 0.5*pulse));
        acc += light*fade*(0.25 + 0.75*depth);
    }
    return acc;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    readAudio();
    vec2 uv0 = (2.0*fragCoord - iResolution.xy)/iResolution.y;
    float t = iTime;

    // slow camera roll, swinging wider when the music is loud
    float r = (CAM_ROLL + BEAT_ROLL*gEnergy)*sin(t*0.07);
    vec2 uv = mat2(cos(r), -sin(r), sin(r), cos(r))*uv0;
    uv *= 1.0 - BEAT_ZOOM*gHit;                            // zoom punch on bass

    // flow field warp so strands swirl instead of just swaying
    vec2 wv = vec2(sin(uv.y*1.7 + t*0.13) + 0.5*sin(uv.y*3.3 - uv.x*1.1 + t*0.21),
                   0.5*sin(uv.x*1.3 - t*0.11) + 0.3*cos(uv.x*2.9 + uv.y*1.4 + t*0.17));
    uv += WARP_AMT*0.5*wv;

    // gust envelope: a bell every GUST_PERIOD seconds, random strength
    float gi   = floor(t/GUST_PERIOD);
    float gp   = fract(t/GUST_PERIOD);
    float gust = exp(-pow((gp - 0.5)*5.0, 2.0))*(0.4 + 0.8*hash11(gi + 3.7));
    gust = max(gust, 0.8*gHit);                            // bass hits ripple the strands

    vec3 col = vec3(0.0);
    col += mix(vec3(0.004, 0.003, 0.010), vec3(0.012, 0.006, 0.022),
               smoothstep(-1.0, 1.0, uv.y));

    // nebula haze behind everything
    float neb = fbm(uv*1.2 + vec2(0.0, t*0.02) + 0.5*fbm(uv*2.0 - t*0.03));
    col += iri(neb*0.8 + t*0.01 + 0.55 + BEAT_HUE*gHit)*pow(neb, 3.0)*NEBULA_AMT*(1.0 + 3.0*gBass);

    col += bundle(uv*1.30 + vec2(0.4, 0.0), 0.25, 1.0, t, gust)*0.5;
    col += bundle(uv*1.00,                  0.60, 2.0, t, gust)*0.8;
    col += bundle(uv*0.78 - vec2(0.3, 0.0), 1.00, 3.0, t, gust);

    // drifting sparkles
    for(float i = 0.0; i < 22.0; i++){
        float h  = hash11(i*7.3);
        float h2 = hash11(i*7.3 + 5.0);
        float life = fract(t*(0.05 + h*0.06) + h2);
        vec2 sp = vec2((h - 0.5)*3.2 + 0.3*sin(life*9.0 + h*20.0) + 0.25*gust,
                       -1.1 + life*2.4);
        float d = length(uv - sp);
        float tw = pow(0.5 + 0.5*sin(t*4.0 + h*40.0), 2.0);
        col += iri(h + t*0.05 + BEAT_HUE*gHit)*0.0009/(d*d + 0.00015)*tw*sin(life*PI)*(1.0 + 3.0*gHigh);
    }

    col *= (0.88 + 0.12*sin(t*0.17))*(1.0 + 0.25*gust);
    col = max(col - BLACK_FLOOR, 0.0);
    col = 1.0 - exp(-col*EXPOSURE*(1.0 + 0.5*gEnergy));
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, SAT);
    col = max(col, 0.0);
    col = pow(col, vec3(GAMMA));
    col *= 1.0 - 0.30*dot(uv0*0.6, uv0*0.6);
    fragColor = vec4(col, 1.0);
}
