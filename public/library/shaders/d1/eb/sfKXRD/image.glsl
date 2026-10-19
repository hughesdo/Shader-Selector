// ── Fractal Flower ──────────────────────────────────────────────
// Exact Descartes packing: outer unit circle + 3 mutually tangent
// inner circles, folded per-pixel by inversion in the seeds.
// Circle inversion = Mobius map = meromorphic automorphism of the
// Riemann sphere. Fold count drives the hue.
//
// Zoom + pan state live in Buffer A.
//   Hold LMB:   dive toward the cursor, fast then slower and slower
//   Hold SPACE: reverse, climb back out with the same easing

#define FOLDS 20      // fold depth = detail level
#define FRAME 1.0     // view scale fine-tune
#define SPIN  .07     // rotation speed of the inner trio
#define EDGE  1300.   // line thinness (higher = finer)
#define PAL   0.0     // palette base shift
#define HUESTEP 0.118 // hue advance per fold

#define AA 4          // AA x AA sub-pixel samples (1 = off, 2 = 4x cost)
#define ZSTART 10.3   // zoom at load  \ keep these three
#define ZMIN   0.01   // deepest zoom  / in sync with Buffer A
#define CSCALE 48.0   // pan storage span /

vec2 rot(vec2 p, float a){ float c = cos(a), s = sin(a); return mat2(c, -s, s, c) * p; }

vec3 flower(vec2 fragU, vec2 r, float zoom, vec2 c){
    vec2 p = (fragU - .5 * r) / r.y * FRAME * zoom + c;
    float t = iTime;

    float ri = 1.0 / (1. + 2.25 / sqrt(4.0));   // inner radius: exact 4-way tangency
    vec2 cd = vec2(1. - ri, 0.);

    float sc2 = 1.00 ;                         // cumulative inverse scale
    float dm = abs(length(p) - 1.0);           // distance to outer rim
    float fc = 5. + iTime * 1.3;              // fold count

    for (int f = 0; f < FOLDS; f++){
        bool hit = false;
        for (int k = 0; k < 3; k++){
            vec2 cc = rot(cd, 2.0943951 * float(k) + SPIN * t);
            vec2 u = p - cc;
            float d2 = dot(u, u);
            if (d2 < ri * ri){                // inside seed k: fold through it
                dm = min(dm, sc2 * abs(sqrt(d2) - ri));
                sc2 *= d2 / (ri * ri);
                p = cc + u * (ri * ri / max(d2, 0.000001));
                fc += 1.2;
                hit = true;
                break;
            }
        }
        if (!hit){
            float l2 = dot(p, p);
            if (l2 > 1.00){                   // escaped the outer circle: fold back
                dm = min(dm, sc2 * (sqrt(l2) - 1.00)); // was originaly - 1.0
                sc2 /= l2 * 0.7;
                p /= l2 * 0.76;
            } else break;                     // resting in a gap: done
        }
    }

    float line = exp(-EDGE * dm);
    float hue  = fract(fc * HUESTEP + PAL);

    vec3 pal = .5 + 0.5 * cos(6.28318 * (hue + vec3(0.0, 0.33, .66)));
    pal = pow(pal, vec3(1.25, 1., .8)) * (1. + 0.10 * min(fc, 6.));

    vec2 q = fragU / r;
    vec3 bg = vec3(0.008, .010, .017) * (1.3 - length(q - .5));
    return bg + line * pal * 1.15 + line * line * pal * pal * 0.55;
}

void mainImage(out vec4 O, vec2 U){
    vec2 r = iResolution.xy;

    // state from Buffer A: (0,0) dive progress, (1,0)/(2,0) pan x/y
    vec2 tv = texelFetch(iChannel0, ivec2(0, 0), 0).xy;
    vec2 tx = texelFetch(iChannel0, ivec2(1, 0), 0).xy;
    vec2 ty = texelFetch(iChannel0, ivec2(2, 0), 0).xy;
    float zoom = ZSTART + (ZMIN - ZSTART) * min(tv.x + tv.y / 255., 1.);
    vec2  c    = (vec2(tx.x + tx.y / 255., ty.x + ty.y / 255.) - .5) * CSCALE;

    vec3 col = vec3(0.);
    for (int m = 0; m < AA; m++)
    for (int n = 0; n < AA; n++){
        vec2 o = (vec2(float(m), float(n)) + .5) / float(AA) - .5;  // sub-pixel grid
        col += flower(U + o, r, zoom, c);
    }
    col /= float(AA * AA);

    col = 1. - exp(-col * 2.);
    col += (fract(sin(dot(U, vec2(127.1, 311.7))) * 43758.5453) - 0.5) / 255.;
    O = vec4(col, 1.);
}