// ============================================================
//  WORLD LOOM
//  Paste into Shadertoy (no channels needed)
//
//  Mix: volumetric glow-accumulation march (batch 1, #04)
//     + signal-pulse threads (batch 1, #02)
//     + slope-driven silk iridescence (batch 2, #14)
//
//  The loom, woven in world space: two perpendicular families
//  of silk threads — warp running into the depth, weft running
//  across — actually interleave (over, under, over) in 3D.
//  Light packets travel down the warp while iridescence is
//  computed from each thread's true 3D slope. The camera
//  drifts through the fabric of it: never hitting, only
//  gathering light volumetrically.
// ============================================================

#define PI 3.14159265

mat2 rot(float a){ float c=cos(a), s=sin(a); return mat2(c,-s,s,c); }
float hash11(float n){ return fract(sin(n*127.1)*43758.5453); }

vec3 iri(float t){ return 0.5 + 0.5*cos(2.0*PI*t + vec3(0.0, 2.1, 4.2)); }

// thread spacing
#define SP 1.1

// warp threads: run along z, repeated in x/y, weaving in y.
// returns (distance, slope, lane id)
vec3 warp(vec3 p){
    float lane = floor(p.x/SP);
    float lx = mod(p.x, SP) - SP*0.5;
    float h = hash11(lane*3.1);
    float ph = p.z*PI/SP + iTime*0.6 + h*6.28;
    float wy = 0.30*sin(ph)*(mod(lane, 2.0)*2.0 - 1.0)
             + 0.25*sin(p.z*0.21 + iTime*0.25 + lane*0.7);
    float ly = p.y - wy;
    float dist = length(vec2(lx, ly)) - 0.045;
    float slope = 0.30*PI/SP*cos(ph)*(mod(lane,2.0)*2.0 - 1.0);
    return vec3(dist, slope, lane);
}

// weft threads: run along x, repeated in z, weaving opposite
vec3 weft(vec3 p){
    float lane = floor(p.z/SP) + 0.5;
    float lz = mod(p.z, SP) - SP*0.5;
    float h = hash11(lane*7.7);
    float ph = p.x*PI/SP + iTime*0.45 + h*6.28;
    float wy = -0.30*sin(ph)*(mod(lane, 2.0)*2.0 - 1.0)
             + 0.20*sin(p.x*0.17 - iTime*0.2 + lane*1.3);
    float ly = p.y - wy;
    float dist = length(vec2(lz, ly)) - 0.045;
    float slope = -0.30*PI/SP*cos(ph)*(mod(lane,2.0)*2.0 - 1.0);
    return vec3(dist, slope, lane);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (2.0*fragCoord - iResolution.xy)/iResolution.y;

    float t = iTime*0.5;
    vec3 ro = vec3(t*0.7, 0.4*sin(t*0.3), t*1.1);
    vec3 fw = normalize(vec3(0.35 + 0.15*sin(t*0.2), -0.05 + 0.1*sin(t*0.13), 1.0));
    vec3 rt = normalize(cross(fw, vec3(0,1,0)));
    vec3 up = cross(rt, fw);
    vec3 rd = normalize(uv.x*rt + uv.y*up + 1.25*fw);
    rd.xy *= rot(0.15*sin(t*0.17));

    // ---- volumetric gather through the weave ---------------------
    vec3 col = vec3(0.0);
    float d = 0.08;
    for(int i = 0; i < 80; i++){
        vec3 p = ro + rd*d;

        vec3 wa = warp(p);
        vec3 we = weft(p);

        float depth = d*0.10;
        float att = exp(-depth*1.7);

        // --- warp: carries the signal pulses -----------------------
        {
            // tighter core: smaller numerator + smaller epsilon = thinner thread
            float den = 0.0016/(wa.x*wa.x + 0.0004);
            vec3 tint = iri(wa.y*0.5 + wa.z*0.13 + iTime*0.02);
            tint = mix(tint, vec3(1.0, 0.97, 0.9),
                       pow(max(1.0 - abs(wa.y)*2.0, 0.0), 6.0)*0.6);

            float pk = pow(0.5 + 0.5*sin(p.z*2.2 - iTime*(3.0 + hash11(wa.z)*2.0)
                                         + wa.z*2.7), 24.0);
            col += tint*den*att*0.014;
            col += vec3(1.0, 0.85, 0.5)*den*pk*att*0.10;
        }

        // --- weft: quieter, cooler, holds the cloth together -------
        {
            float den = 0.0014/(we.x*we.x + 0.0005);
            vec3 tint = iri(we.y*0.5 + we.z*0.21 + 0.45);
            tint = mix(tint, vec3(0.6, 0.8, 1.0), 0.35);
            float shimmer = 0.75 + 0.25*sin(p.x*3.0 + iTime*1.5 + we.z*5.0);
            col += tint*den*att*0.011*shimmer;
        }

        // --- crossing points spark where warp meets weft ------------
        float cross_ = max(0.0, 0.10 - wa.x - we.x);
        col += vec3(1.0)*cross_*cross_*att*1.4;

        float near = min(wa.x, we.x);
        d += clamp(near*0.7, 0.03, 0.45);
        if(d > 26.0) break;
    }

    // deep background: pulled way down so it reads as true black
    col += vec3(0.006, 0.003, 0.013)*(0.5 + 0.5*uv.y);

    // bloom only on the genuinely hot packets (raised threshold)
    float lum = dot(col, vec3(0.3, 0.5, 0.2));
    col += col*pow(max(lum - 0.7, 0.0), 2.0)*0.7;

    // ---- black clamp: subtract a floor so haze goes to zero ------
    col = max(col - 0.012, 0.0);

    col = 1.0 - exp(-col*1.9);

    // ---- saturation push: pull color away from gray luma ---------
    float g = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(g), col, 1.45);
    col = max(col, 0.0);

    col = pow(col, vec3(0.4545));

    // gentle contrast S-curve to deepen the blacks further
    col = smoothstep(0.0, 1.0, col);

    col *= 1.0 - 0.35*dot(uv*0.8, uv*0.8);
    fragColor = vec4(col, 1.0);
}