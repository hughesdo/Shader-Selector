// ============================================================================
//  SPECTRUM VORTEX (audio reactive)            -- COMMON tab --
//
//  Shadertoy setup:
//    Buffer A : iChannel0 = music (SoundCloud / Music / Mic)
//               iChannel1 = Buffer A   (feedback)
//    Image    : iChannel0 = Buffer A
//
//  Everything audio is ADDED on top of the original look. With silence (or
//  every ENABLE_ set to 0) you get the original non-reactive shader back.
//  Every reaction runs through a smoother so nothing snaps or jerks.
//  Smoothing values are time constants in seconds: bigger = smoother/slower.
// ============================================================================

// ---------------------------------------------------------------- base look
#define NR        17.0    // rings alive at once
#define RATE      3.4     // rings born per second (at normal speed)
#define NBARS     150.0   // bars per ring
#define TWIST     1.3     // spiral strength near center
#define WANDER    0.035   // radius of the center's circular wander

// ------------------------------------------------------------ audio input
#define AUDIO_GAIN     1.0    // overall input level, raise for quiet tracks
#define SPEC_TILT      2.5    // lifts the high end so treble bars show up

// ---------------------------------- 1. bass kick shoves the center
// Rings remember where the center was when they were born, so every kick
// ripples outward through the tunnel.
#define ENABLE_CENTER_KICK   1
#define KICK_STRENGTH        1.0    // how far a kick shoves the center
#define KICK_SENS            1.0    // onset sensitivity
#define KICK_SMOOTH          0.04   // rise time of the shove (s): 0 = punchy, 0.1 = floaty
#define KICK_SPRING          16.0   // pull back to rest (higher = snappier return)
#define KICK_DAMP            6.0    // damping (higher = less bounce/overshoot)
#define KICK_MAX             0.07   // soft limit on how far the center can travel

// ---------------------------------- 2. rings freeze the spectrum at birth
#define ENABLE_SPECTRUM_RINGS 1
#define BASE_BARS            0.55   // share of the original procedural bars
#define AUDIO_BARS           0.75   // share of the real spectrum (added on top)
#define SPEC_FLOOR           0.40   // spectrum level treated as "nothing" (raise if bars stay long)
#define SPEC_CEIL            0.95   // spectrum level treated as full
#define SPEC_ATTACK          0.03   // spectrum rise smoothing (s)
#define SPEC_RELEASE         0.20   // spectrum fall smoothing (s)
#define RING_BEAT_GLOW       0.9    // rings born on a kick glow brighter

// ---------------------------------- 3. bass drives tunnel speed
// Speed follows bass RELATIVE to the song's recent average, so on average
// the tunnel runs at the original speed: drops surge, breakdowns drift.
#define ENABLE_SPEED         1
#define SPEED_AMT            2.2    // how much bass changes speed
#define SPEED_SMOOTH         0.45   // speed smoothing (s)
#define SPEED_AVG            5.0    // window for the "recent average" (s)
#define SPEED_MIN            0.35   // never slower than this x normal
#define SPEED_MAX            2.6    // never faster than this x normal

// ---------------------------------- 4. loudness winds the spiral
#define ENABLE_TWIST         1
#define TWIST_AMT            1.2    // how much the spiral tightens when loud
#define TWIST_SMOOTH         1.2    // twist smoothing (s)
#define TWIST_AVG            8.0    // window for the "recent average" (s)

// ---------------------------------- 5. highs drive the warp streaks
#define ENABLE_STREAKS       1
#define STREAK_AMT           1.0    // extra density/brightness from highs
#define HIGH_FLOOR           0.30   // highs level treated as "nothing"
#define HIGH_ATTACK          0.03
#define HIGH_RELEASE         0.35

// ---------------------------------- 6. ring color from the sound at birth
// bass-heavy moments -> orange/magenta rings, bright moments -> green/blue
#define ENABLE_RING_COLOR    0

// ---------------------------------- 7. ring outline follows the waveform
#define ENABLE_WAVE_OUTLINE  0
#define WAVE_AMT             0.18   // how far the waveform bends the ring

// ---------------------------------- 8. core pulse on kicks
#define ENABLE_CORE_PULSE    1
#define PULSE_AMT            0.7    // glow swell
#define PULSE_PUPIL          0.35   // black dot swell
#define PULSE_ATTACK         0.04   // pulse rise (s)
#define PULSE_RELEASE        0.30   // pulse decay (s)

// ============================================================================
//  internals (no need to touch)
// ============================================================================
#define NSLOT 32          // ring history slots (must be > NR)
#define NBINS 64          // spectrum bins stored per ring
// Buffer A layout
//   row 0: x0 fast bands (bass, mid, high, loud)   x4 (smoothed onset)
//          x1 slow stats (bassAvg, loudMed, loudAvg, speedSm)
//          x2 (clock, kickEnv, bassSlow, highSm)
//          x3 kick spring (pos.xy, vel.xy)
//   row 1: smoothed spectrum per bin (r), waveform (g)
//   row 2+slot: ring snapshot: x<NBINS (spec, wave)
//               x=NBINS   (ringId mod 8192, kickPos.x, kickPos.y, kickAtBirth)
//               x=NBINS+1 (highAtBirth, loudAtBirth, 0, 0)

const float TAU = 6.28318530718;

float h11(float p){ p = fract(p*0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p){ vec3 q = fract(vec3(p.xyx)*0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y)*q.z); }

vec3 palIdx(float k){
    if (k < 0.5) return vec3(0.15, 1.00, 0.20); // green
    if (k < 1.5) return vec3(1.00, 0.55, 0.05); // orange
    if (k < 2.5) return vec3(0.10, 0.25, 1.00); // blue
    return vec3(1.00, 0.08, 0.50);              // magenta
}
vec3 palette(float k){ return palIdx(floor(k*4.0)); }

// center wanders in a small circle (with a slower secondary wobble)
vec2 wander(float t){
    return WANDER*vec2(cos(t*0.9), sin(t*0.9)) + 0.012*vec2(sin(t*2.3), cos(t*1.7));
}

// global swirl: big near the center, gone further out so bars become lines
float swirl(float r, float tw){ return -tw*log(r + 0.015)*exp(-(r*r)/0.045); }

// frame-rate independent smoother with separate rise/fall times
float smoothAR(float prev, float x, float att, float rel, float dt){
    float tau = (x > prev) ? att : rel;
    return mix(prev, x, 1.0 - exp(-dt/max(tau, 1e-4)));
}

// log-ish frequency mapping for bin b in [0,1]
float binToFFT(float b){ return 0.003 + pow(b, 1.7)*0.5; }

float posMod(float a, float m){ return a - m*floor(a/m); }
float idKey(float id){ return posMod(id, 8192.0); }   // keeps ids exact in the buffer

// soft limit (no hard edge, so big hits never clip or snap)
vec2 kickSat(vec2 p){ float l = length(p); return l < 1e-5 ? p : p*(KICK_MAX*tanh(l/KICK_MAX)/l); }
