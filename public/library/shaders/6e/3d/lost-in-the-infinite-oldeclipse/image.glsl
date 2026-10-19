// https://www.shadertoy.com/view/7ffSRs
// Lost in the Infinite OldEclipse
// Converted to OneOffRender format with audio reactivity
// Audio reworked in the ArthurTent / ShaderAmp style: FFT bands, slow rotation
// nudged by the music, and a palette jump on bass hits.

#version 330 core

uniform float iTime;
uniform vec2 iResolution;
uniform sampler2D iChannel0; // Audio FFT (512x2: row 0 = FFT, row 1 = waveform)

out vec4 fragColor;

// ===== LOOK =====
#define EXPOSURE             6e4   // Tone-map divisor; higher = darker, less white blowout (orig 2e4)
#define SATURATION           1.35  // Pushes colour back into the bright cores

// ===== AUDIO REACTIVITY TWEAKS =====
#define ROLL_SPEED           0.06  // Slow base roll of the whole view (radians/sec)
#define ROLL_AUDIO           0.35  // Extra roll from audio energy (iAmplifiedTime idea)
#define AUDIO_ROTATION_BOOST 0.3   // How much bass speeds the lattice axis shift
#define AUDIO_SPHERE_PULSE   0.04  // How much bass pulses the sphere radius
#define AUDIO_COLOR_SHIFT    0.8   // How much mids drift the colour phase
#define HIT_LOW              0.45  // Bass level where a "hit" starts
#define HIT_HIGH             0.75  // Bass level where a hit is full strength
#define HIT_HUE_JUMP         2.6   // Palette phase jump on a bass hit
#define AUDIO_PUMP           0.45  // Brightness pump from energy, applied after tone mapping

// Audio helpers: averaged FFT bands
float getBass() {
    return (texture(iChannel0, vec2(0.01, 0.0)).x + texture(iChannel0, vec2(0.03, 0.0)).x +
            texture(iChannel0, vec2(0.05, 0.0)).x + texture(iChannel0, vec2(0.08, 0.0)).x) * 0.25;
}
float getMid() {
    return (texture(iChannel0, vec2(0.15, 0.0)).x + texture(iChannel0, vec2(0.25, 0.0)).x +
            texture(iChannel0, vec2(0.35, 0.0)).x) / 3.0;
}
float getHigh() {
    return (texture(iChannel0, vec2(0.55, 0.0)).x + texture(iChannel0, vec2(0.75, 0.0)).x) * 0.5;
}

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

void mainImage( out vec4 O, vec2 I ){
    // Audio sampling
    float bass   = getBass();
    float mid    = getMid();
    float high   = getHigh();
    float energy = bass * 0.6 + mid * 0.3 + high * 0.1;
    float hit    = smoothstep(HIT_LOW, HIT_HIGH, bass);   // beat gate

    vec3 p, a, r = normalize(vec3(I+I,0) - iResolution.xyy);
    // Slow continuous roll of the view, sped up by the music
    r.xy *= rot(iTime * ROLL_SPEED + energy * ROLL_AUDIO);

    // Palette phase: drifts with time and mids, jumps on bass hits
    float hue = iTime + mid * AUDIO_COLOR_SHIFT + hit * HIT_HUE_JUMP;

    float i, t, v;
    // Raymarching loop
    for (O*=i; i++<80.;t+=v*.2){
    p=t*r;
    // Rotation around axis — bass speeds the rotation
    float rotSpeed = iTime * (0.1 + bass * AUDIO_ROTATION_BOOST * 0.1);
    p = dot(a=normalize(sin(rotSpeed+i*.1+vec3(3,1,0))),p)*2.*a-p;
    // Move forward
    p.z+=14.;
    // Angular repetition in xz plane
    p.xz=length(p.xz)*vec2(cos(p.z=mod(atan(p.z,p.x),.4)-.2), sin(p.z));
    // Radial repetition in xz plane and repetition in y plane
    p.xy=mod(p.xy,1.)-.5;
    // Density — bass pulses the sphere radius
    float sphereR = 0.1 + bass * AUDIO_SPHERE_PULSE;
    v=abs(length(p)-sphereR)+.01;
    // Colour accumulation (no audio gain in here: it saturated everything to white)
    O += exp(sin(i*.3 + hue + vec4(0,1,3,0))) / v;
    }
    // Tone mapping
    O = tanh(O*O/EXPOSURE);

    // Pull colour back out of the bright cores
    float lum = dot(O.rgb, vec3(0.299, 0.587, 0.114));
    O.rgb = clamp(mix(vec3(lum), O.rgb, SATURATION), 0.0, 1.0);

    // Beat pump, after tone mapping so it can't blow out
    O.rgb *= 0.85 + energy * AUDIO_PUMP + hit * 0.25;
    O.a = 1.0;
}

void main() {
    vec2 fragCoord = vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y);
    mainImage(fragColor, fragCoord);
}
