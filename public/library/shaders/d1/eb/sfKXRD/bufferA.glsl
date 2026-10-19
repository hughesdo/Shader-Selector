// ── Zoom & pan state ────────────────────────────────────────────
// Three state texels on row 0, each split R coarse / G fine
// (~16 bits total) because Shadertoy buffers are 8-bit:
//   (0,0) dive progress v : 0 = loaded view, 1 = deepest
//   (1,0) pan x, WORLD units -- bounded by the screen, so it
//   (2,0) pan y             can never saturate however deep you dive
//
// Hold LMB   : dive toward the cursor, fast then slower and slower
// Hold SPACE : reverse -- climb back out AND drift back to center
//              with the same easing. Space wins if both are held.

#define ZSTART   10.0   // \ keep in sync
#define ZMIN     0.01   // / with Image tab
#define ZOOM_RATE .015  // fraction of remaining distance per frame
#define CSCALE   48.0   // pan storage span: world units in [-24, 24]
#define FRAME    1.0    // view scale (same as Image tab)

void mainImage(out vec4 O, vec2 U){
    ivec2 pix = ivec2(U);
    if (pix.y != 0 || pix.x > 2){ O = vec4(0.); return; }

    float rev = min(texelFetch(iChannel1, ivec2(32, 0), 0).x, 1.); // SPACE held
    float fwd = float(iMouse.z > 0.) * (1. - rev);                 // LMB held

    // state -- frame 0 seeds neutral values, because the untouched
    // buffer texture is all-zeros, and zeros biased-decode to
    // pan = -CSCALE/2, which shoves the flower into a corner on load
    float v = 0.;
    vec2 c = vec2(0.);
    if (iFrame > 0){
        vec2 t0 = texelFetch(iChannel0, ivec2(0, 0), 0).xy;
        v = min(t0.x + t0.y / 255., 1.);
        vec2 t1 = texelFetch(iChannel0, ivec2(1, 0), 0).xy;
        vec2 t2 = texelFetch(iChannel0, ivec2(2, 0), 0).xy;
        c = (vec2(t1.x + t1.y / 255., t2.x + t2.y / 255.) - .5) * CSCALE;
    }

    // dive progress -> zoom ratio this frame
    float z0 = ZSTART + (ZMIN - ZSTART) * v;
    v = clamp(v + ZOOM_RATE * (fwd * (1. - v) - rev * v), 0., 1.);
    float z1 = ZSTART + (ZMIN - ZSTART) * v;

    vec2 sig = (iMouse.xy - .5 * iResolution.xy) / iResolution.y * FRAME;
    if (fwd > 0.){
        // forward: pin the world point under the cursor across z0 -> z1
        vec2 wpt = sig * z0 * FRAME + c;
        c = wpt - sig * z1 * FRAME;
    } else if (rev > 0.){
        // reverse: unwind the pan home, same fractional curve as the
        // zoom climb, so view and center arrive back together
        c *= 1. - ZOOM_RATE;
    }

    float e = pix.x == 0 ? v
            : clamp((pix.x == 1 ? c.x : c.y) / CSCALE + .5, 0., 1.);
    O = vec4(floor(e * 255.) / 255., e * 255. - floor(e * 255.), 0., 1.);
}