// TRANSFORM : liquid chrome / prismatic cells
// Single pass, Shadertoy. Not audio reactive.
//
// Two layers of animated Voronoi pillows -> height field -> real normals.
// Dark glassy chrome base, thin silver caustic ridges, prismatic dispersion
// patches that bloom in on a periodic "transform" kick together with a
// radial zoom pull and spectral streak blur. Sparkle dust in the dark cells.

#define TAU 6.28318530718
#define PERIOD 2.4      // seconds per transform cycle
#define SAMPLES 7       // radial blur taps

vec2 hash2(vec2 p){
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}
float hash1(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// x = distance to cell border, y = cell id hash
vec2 voronoi(vec2 x, float t){
    vec2 n = floor(x), f = fract(x);
    vec2 mg, mr; float md = 8.0;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){
        vec2 g = vec2(i,j);
        vec2 o = 0.5 + 0.42*sin(t + TAU*hash2(n+g));
        vec2 r = g + o - f;
        float d = dot(r,r);
        if(d < md){ md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for(int j=-2;j<=2;j++) for(int i=-2;i<=2;i++){
        vec2 g = mg + vec2(i,j);
        vec2 o = 0.5 + 0.42*sin(t + TAU*hash2(n+g));
        vec2 r = g + o - f;
        if(dot(mr-r,mr-r) > 1e-5)
            md = min(md, dot(0.5*(mr+r), normalize(r-mr)));
    }
    return vec2(md, hash1(n+mg));
}

// smooth-min of squared distances -> molten paraboloid domes
float smoothDome(vec2 x, float t){
    vec2 n = floor(x), f = fract(x);
    float acc = 0.0;
    for(int j=-1;j<=2;j++) for(int i=-1;i<=2;i++){
        vec2 g = vec2(i,j);
        vec2 o = 0.5 + 0.42*sin(t + TAU*hash2(n+g));
        vec2 r = g + o - f;
        acc += exp(-14.0*dot(r,r));
    }
    return log(acc + 1e-6)/14.0;     // high at seeds, soft valleys between
}

vec2 warp(vec2 p, float t){
    p += 0.42*vec2(sin(p.y*0.9 + t*0.5), cos(p.x*0.8 - t*0.45));
    p += 0.14*vec2(sin(p.y*2.1 - t*0.9), cos(p.x*1.9 + t*0.7));
    return p;
}

// rounded pillows: dome over the whole cell, crisp crease at the border
float height(vec2 p, float t, out float edge, out float id){
    vec2 q = warp(p, t);
    vec2 v1 = voronoi(q, t*0.9);
    vec2 v2 = voronoi(q*2.1 + 7.1, t*1.4);
    edge = v1.x; id = v1.y;
    float h1 = smoothDome(q, t*0.9);
    float h2 = smoothDome(q*2.1 + 7.1, t*1.4);
    // pinch a crisp crease into the border so the ridge lines read
    float crease = 1.0 - exp(-v1.x*18.0);
    return h1 + 0.2*h2 + 0.12*crease;
}

vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0/3.0, 1.0/3.0))*6.0 - 3.0) - 1.0, 0.0, 1.0); }

float envelope(float t){
    float ph = fract(t / PERIOD);
    return smoothstep(0.0, 0.10, ph) * (1.0 - smoothstep(0.12, 0.70, ph));
}

vec3 scene(vec2 uv, float t, float e){
    float zoom = 4.6 - 0.9*e;                     // cells swell on the kick
    vec2 p = uv*zoom + vec2(0.0, t*0.10);

    float edge, id, tmp;
    float eps = 0.01;
    float h  = height(p, t, edge, id);
    float hx = height(p + vec2(eps,0.0), t, tmp, tmp);
    float hy = height(p + vec2(0.0,eps), t, tmp, tmp);
    vec2 grad = vec2(hx-h, hy-h)/eps;
    vec3 N = normalize(vec3(-grad*0.55, 1.0));
    float slope = clamp(1.0 - N.z, 0.0, 1.0);
    float rim = smoothstep(0.0, 0.25, slope);

    // base: dark smoky glass, slightly lighter on the domes' shoulders
    vec3 base = vec3(0.06, 0.062, 0.07) + vec3(0.09)*rim*rim;
    // per-cell smoky tint (warm brown or cold blue), like the original
    vec3 tint = mix(vec3(0.16,0.10,0.06), vec3(0.06,0.08,0.16), step(0.5, fract(id*13.7)));
    base = mix(base, tint, 0.5);

    // chrome reflection: a slow-rotating key light catching the rims
    vec2 L = vec2(cos(t*0.3), sin(t*0.3));
    float spec = pow(max(dot(normalize(grad + 1e-4), L), 0.0), 10.0) * rim * rim;
    vec3 col = base + vec3(0.85,0.87,0.92) * spec * 0.6;

    // prismatic dispersion: hue follows the surface direction, broad patches
    float ang = atan(grad.y, grad.x)/TAU;
    vec3 prism = hue(ang*1.0 + id*0.5 + t*0.15 + h*0.35);
    prism.r *= 1.0 - 0.55*smoothstep(0.25, 0.9, min(prism.r, prism.b));   // tame magenta
    prism = mix(prism, prism*prism, 0.4);       // deepen
    float pm = smoothstep(0.08, 0.45, slope) * smoothstep(0.015, 0.12, edge);
    // a few hero cells stay lit off-peak
    float hero = smoothstep(0.86, 1.0, fract(id*7.31 + floor(t/PERIOD)*0.37));
    float amt = pm * (0.10 + 1.6*e + 0.8*hero);
    col = mix(col, prism*(0.9 + 0.8*spec), clamp(amt, 0.0, 0.92));
    // a hot white core where the color is brightest
    col += vec3(1.0) * pow(pm*e, 4.0) * 0.25;

    // dark cell centers
    float center = 1.0 - smoothstep(0.08, 0.40, edge);
    col *= mix(0.45, 1.0, center + 0.4*e);

    // caustic ridge network: thin silver lines, soft halo
    float ridge = exp(-edge*110.0) + 0.22*exp(-edge*28.0);
    float shimmer = 0.45 + 0.55*sin(p.x*3.1 + p.y*2.3 + t*2.2 + id*6.0);
    col += vec3(0.82, 0.85, 0.92) * ridge * (0.45 + 0.45*e) * (0.55 + 0.6*shimmer*shimmer);

    // sparkle dust
    vec2 sp = uv*240.0;
    float sh = hash1(floor(sp));
    float tw = 0.5 + 0.5*sin(t*8.0 + sh*80.0);
    float star = step(0.982, sh) * tw * smoothstep(0.4, 0.0, length(fract(sp)-0.5));
    col += vec3(0.85,0.88,1.0) * star * (1.0-center) * 0.8;

    return col;
}

vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 res = iResolution.xy;
    vec2 uv = (fragCoord - 0.5*res) / res.y;
    float t = iTime;
    float e = envelope(t);

    // radial transform pull with spectral streaks
    float blur = 0.008 + 0.09*e;
    vec2 center = 0.05*vec2(sin(t*0.37), cos(t*0.29));
    vec2 d = uv - center;

    vec3 col = vec3(0.0), wsum = vec3(0.0);
    float jit = hash1(fragCoord + fract(t*7.0)*31.0);
    for(int i=0;i<SAMPLES;i++){
        float s = (float(i) + jit)/float(SAMPLES);
        vec3 w = 0.55 + 0.45*cos(TAU*(s*0.85 + vec3(0.0, 0.33, 0.67)));
        w *= 1.0 - 0.55*s;
        col += scene(center + d*(1.0 - blur*s), t, e) * w;
        wsum += w;
    }
    col /= wsum;

    col *= 1.0 - 0.4*dot(uv, uv);                 // vignette
    col = aces(col*1.2);
    col += (hash1(fragCoord + fract(t)*97.0) - 0.5) * 0.03;   // grain
    fragColor = vec4(col, 1.0);
}
