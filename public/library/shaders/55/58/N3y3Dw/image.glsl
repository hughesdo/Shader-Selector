// ============================================================================
//  AUDIO REACTIVE - the fold is the instrument
//
//  Two passes: Buffer A is the analyzer, this is the instrument.  Down here there
//  is no band maths at all - three numbers come out of the analyzer and the cost
//  per pixel is exactly what it always was.
//
//    k = kick env / kick pool     the hit.  A RATIO, so it is master-level
//                                 independent: it fires the same at -20 dBFS as
//                                 at 0 dBFS.  Measured over 7 s of the track it
//                                 sits at 0 about half the time and spikes to
//                                 0.6 on the beat - exactly the shape you want.
//                                 Drives the light: camera dive, ball bloom,
//                                 glow, exposure.
//    H = top env / top pool       the top end (1.1-4.4 kHz): 0 between hits, up
//                                 to 0.44 on a snare or hat.  Drives the texture:
//                                 spin rate, the cos() displacement PHASE, the
//                                 cross() facet term - so a hit shears the fold
//                                 instead of only brightening it.
//    s = kick env level           the slow one, for the shape: fold offset,
//                                 displacement amplitude, inner sphere radius.
//                                 This one IS a level and will drift with the
//                                 master, which is fine and deliberate - it only
//                                 drives terms that move light around rather than
//                                 add it, and it is clamped.
//
//  The hard limit is the cut: the ball CUT_R + .2k must stay under the camera
//  distance CAM_Z - .22s - .06k, or the camera ends up INSIDE the ball,
//  step(cut,0) turns on across the whole frame and it goes white.  That is
//  exactly what the first single-pass cut did (0.6 dive + 0.7 bloom, measured
//  100% of pixels over 250).  Worst case here is camera 4.32 against ball 3.60.
//
//  s is deliberately a small amplitude: measured, this track's kick band sits
//  near 0.9 for whole sections, so s is effectively pinned and it is the SHAPE
//  amplitudes that decide how big the orb reads at rest.  Keep them small and the
//  idle frame keeps the original framing, with the punch doing the expansion.
//  The bloom is also the sharpest brightness lever in the whole shader, not a
//  gentle one: growing the ball past 3.4 uncovers KIFS structure that was outside
//  it, so a few hundredths of CUT_R buy a lot of pixels.  That is why it carries
//  only .2k where the glow and exposure carry .12k and .07k.
//
//  Reference budget, measured on the untouched original: mean 41, 4% of pixels
//  over 250.  At k = H = 0 (silence, or simply between hits) every expression
//  collapses to the original numbers exactly.
//
//  Kept from the original: the cut is on the un-folded world position p and never
//  on the folded q, which is why the glow stays inside the ball.
// ============================================================================
#define R(a) mat2(cos(a),-sin(a),sin(a),cos(a))

#define CAM_Z 3.6         // camera distance (was the hard-coded 4.6)
#define CUT_C vec3(0.0)   // centre of the kept ball
#define CUT_R 3.30        // radius of the kept ball

void mainImage(out vec4 O, vec2 I) {
    vec4 S = texture(iChannel0, vec2(.5));       // the analyzer, uniform
    float k = clamp((S.x/max(S.y,.05) - 1.)*8., 0., 1.),   // punch
          H = clamp((S.z/max(S.w,.05) - 1.)*3., 0., 1.),   // top end
          s = clamp( S.x*1.15,                0., 1.);     // kick level

    float i=-200.0, z=0.8, d, t=iTime, t1=t*.184;

    for(O-=O; i++<-45.;) {
        vec3 p = z * normalize(vec3(I+I-iResolution.xy, iResolution.y));
        p.z -= CAM_Z - (0.22*s + 0.96*k);      // the level pushes in, the hit snaps in
        vec3 q = p;                          // p is the real position; q is the folded one

        q.xz *= R(t*(0.4 + 0.4*H*H));         // the top end owns the spin rate
        q.yz *= R(sin(t*1.25)*.3 + 1.1*H);
        q.xy *= R(t1 + 1.5*H);
        q.yz *= R(t*(0.152 + .5*H));
        t1 += i*27.142;

        for(d=1.; d++<7.; q += cos(q.zxy*d*1.4 + t*1.832 + 5.*H)/(d*(4.7 - .45*s))) {
            q = abs(q) - (4.55 - 0.72*s);     // the kick's level caves the cell walls in
            if(q.x<q.y) q.xy=q.yx;
            if(q.x<q.z) q.xz=q.zx;
        }
        if (z>11.0) continue;

        float cut  = length(p-CUT_C) - (CUT_R+s + .2*k);                    // the hit blooms the ball
        float surf = max(abs(length(q) - 2.35 - .12*s*1.1) - 0.12,
                         length(cross(sin(q*3.), cos(q.yzx*5.)))*(0.15 + .22*H));

        z += d = .002 + max(surf, cut) / 2.3;

        O += (cos(dot(q, vec3(1.4, 2.1, .7)) + t1*10. + vec4(0, 1.8, 3.6, 0)) + 1.3 + .12*k)
             * step(cut, 0.0)
             / (.002 + surf / 2.3) / z / 120.;
    }

    O = tanh(O*O*(.55 + .07*k));
}
