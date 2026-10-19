// ============================================================================
//  Buffer A - the analyzer
//
//  Two bands, each kept as a fast envelope and a slow pool, copied into every
//  texel so the Image pass can pick them up with one plain texture() at a fixed
//  uv (no texelFetch, no resolution maths).
//
//    x = kick env : instant attack, .92 release (~140 ms at 60 fps).  The hit.
//                   It jumps on the kick and bleeds off even while the bass note
//                   underneath keeps ringing - which is the whole reason this
//                   pass exists.  A raw band mean is a LEVEL, and a level cannot
//                   tell a hit from a loud bar: that is why the first single-pass
//                   cut of this shader measured 100% of pixels over 250 through
//                   the loud half of the track and looked fine in the quiet half.
//                   Measured, this track's bass band swings 0.27..0.95 between
//                   sections, so no fixed divisor can ever work.
//    y = kick pool: .006 attack (~3 s).   x/y is the punch.
//    z = top env  : 1.1 k - 4.4 kHz, .90 release.  Hats, snare crack, presence.
//    w = top pool : .0015 attack (~11 s), deliberately slower than the kick pool
//                   so z/w is correlated with the beat as little as possible.
//
//  43-220 Hz, not 0-430 Hz: the wide band drags in the DC bin and sits pinned
//  near 0.85 for the entire track (measured), which is useless as a hit detector.
//  The kick's own octave swings 0.59..0.95 and pulses cleanly with the beat.
//
//  The Image pass only ever sees the RATIOS env/pool.  A band against its own
//  recent average is master-level independent, so the shader reacts the same at
//  -20 dBFS and at 0 dBFS and does not drift as the track gets louder - which is
//  the failure mode none of the single-pass versions could escape.
// ============================================================================
float band(float lo, float hi){ float s = 0.;
    for(float i=0.; i<12.; i++) s += texture(iChannel0, vec2(mix(lo,hi,i/11.), .25)).x;
    return s/12.; }

void mainImage(out vec4 O, vec2 U) {
    vec4 s = texture(iChannel1, vec2(.5));            // last frame's state
    float lo = band(.002,.010),                       // 43  -  220 Hz  kick
          hi = band(.050,.200);                       // 1.1 k - 4.4 kHz top

    O = vec4(max(lo, s.x*.92),                        // kick: hit jumps, tail bleeds
             mix(s.y, lo, .006),                      // kick: ~3 s pool
             max(hi, s.z*.90),                        // top:  hit jumps, tail bleeds
             mix(s.w, hi, .0015));                    // top:  ~11 s pool

    // Seed on frame 0, and also whenever the pool reads empty.  Fullscreen
    // recreates the buffer at the new resolution, which clears it while iFrame
    // keeps counting - without this the pools stay at 0 and the shader sits on
    // its silent look (k = H = s = 0) for the 3 s / 11 s the pools take to grow
    // back.  One line, and a resolution change becomes invisible.
    if (iFrame == 0 || s.y <= 0.) O = vec4(lo, lo, hi, hi);
}
