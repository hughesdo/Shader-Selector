// Buffer A: audio analyser + beat-driven scene director
// iChannel0 = Music (SoundCloud / mp3), iChannel1 = Buffer A (itself)
//
// (0,0) bass, mid, high, beat envelope
// (1,0) amplified time, smoothed hue, rotation accumulator, slow bass average
// (2,0) current scene, previous scene, switch time, hue target
// (3,0) kick count, last palette step time, bass wobble (mean abs deviation), -
// (4,0) last time each scene was on screen
// row 1: 64-bin smoothed spectrum

#define MIN_SCENE 9.     // a kick can only switch scenes after this many seconds
#define MAX_SCENE 24.    // switch anyway if no kick lands (quiet intros, ambient tracks)

float fft(float x){ return texture(iChannel0, vec2(x, .25)).x; }
vec4 ld(int x, int y){ return texelFetch(iChannel1, ivec2(x, y), 0); }

void mainImage(out vec4 O, in vec2 F){
    ivec2 I = ivec2(F);
    O = vec4(0);
    if(I.y > 1 || I.x > 63) return;
    bool init = iFrame < 2;
    float dt = clamp(iTimeDelta, 1./240., .25);

    if(I.y == 1){                                   // smoothed spectrum, fast attack slow fall
        float v = fft(pow((float(I.x) + .5)/64., 1.4)*.75);
        float o = ld(I.x, 1).x;
        O = vec4(init ? v : (v > o ? mix(o, v, .6) : mix(o, v, min(1., dt*5.))));
        return;
    }
    if(I.x > 4) return;

    vec4 s0 = ld(0, 0), s1 = ld(1, 0), s2 = ld(2, 0), s3 = ld(3, 0), ls = ld(4, 0);
    float rb = (fft(.004) + fft(.008) + fft(.012) + fft(.018))*.25;          // ~40-200 Hz: where kicks live
    float rm = (fft(.12) + fft(.2) + fft(.3))/3.;
    float rh = (fft(.48) + fft(.6) + fft(.72))/3.;
    if(init){ s0 = vec4(rb, rm, rh, 0); s1 = vec4(0, 0, 0, rb); s2 = vec4(0, 0, iTime, 0); s3 = vec4(0); ls = vec4(0, -1, -1, 0)*1e3; }

    // bands: fast attack, slower release
    vec3 b = s0.xyz, r = vec3(rb, rm, rh);
    b = mix(b, r, mix(vec3(min(1., dt*4.)), vec3(.7), step(b, r)));
    // onset = bass jumps BEAT_THRESH times its usual wobble above its slow average.
    // Adaptive, so it still fires on mixes whose bass bins sit near the top of the FFT range.
    float wob = mix(s3.z, abs(rb - s1.w), min(1., dt*1.5));
    bool onset = rb - s1.w > max(BEAT_THRESH*wob, .025) && rb > .15 && s0.w < .45;
    float beat = max(s0.w*exp(-dt*5.5), onset ? 1. : 0.);
    float slowB = mix(s1.w, rb, min(1., dt*1.2));

    float kicks = s3.x + (onset ? 1. : 0.);
    // THE colour change on bass hits: accents hop round the colour wheel (at most ~once a second so it pops, not strobes)
    bool palStep = onset && iTime - s3.y > .9;
    float hueT = s2.w + (palStep ? 1. : 0.);
    float lastStep = palStep ? iTime : min(s3.y, iTime);
    float en = .6*b.x + .4*b.y;
    float at = s1.x + dt*(.55 + en*en*1.8 + beat*.9);                              // iAmplifiedTime
    float hu = mix(s1.y, hueT, min(1., dt*10.));                                    // quick glide, reads as a pop
    float ro = s1.z + dt*(.05 + en*.25);

    // scene director: next kick after MIN_SCENE swaps to another scene
    float cur = s2.x, prev = s2.y, sw = s2.z;
    if(iTime < sw) sw = iTime;                                                      // rewind / reset
#if SCENE > 0
    cur = prev = float(SCENE - 1);
#else
    float age = iTime - sw;
    if((onset && age > MIN_SCENE) || age > MAX_SCENE){
        ls[int(cur)] = iTime;
        // the two other scenes: usually the one we have not seen for longest
        float a = mod(cur + 1., 3.), c = mod(cur + 2., 3.);
        float j1 = ls[int(a)] <= ls[int(c)] ? a : c, j2 = j1 == a ? c : a;
        prev = cur;
        cur = fract(sin(kicks*12.9898 + iTime*7.1)*43758.5) < .75 ? j1 : j2;
        sw = iTime;
    }
#endif

    if(I.x == 0) O = vec4(b, beat);
    else if(I.x == 1) O = vec4(at, hu, ro, slowB);
    else if(I.x == 2) O = vec4(cur, prev, sw, hueT);
    else if(I.x == 3) O = vec4(kicks, lastStep, wob, 0);
    else O = ls;
}
