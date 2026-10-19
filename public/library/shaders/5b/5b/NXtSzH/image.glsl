// =====================================================================
//  BIREFRINGENT BLOOM  -  Shadertoy, 3 tabs: Common / Buffer A / Image
// =====================================================================
//  Setup:
//   1. Paste the COMMON section into the Common tab (+ next to Image).
//   2. Add Buffer A, paste the BUFFER A section.
//   3. Image tab: paste the IMAGE section, set iChannel0 = Buffer A
//      (filter linear, wrap clamp; those are the defaults).
//   4. Audio (optional): set AUDIO_REACTIVE 1 in Common, then in Buffer A
//      set iChannel0 = Music / SoundCloud / Microphone.
//        bass  -> clouds swell, bands glow hotter
//        mids  -> interference colours shift up the Michel-Levy scale
//        highs -> brighter film emission
//  SPEED in Common: 1.6 matches the source's frantic morph; 0.6 is dreamy.
//
//  How it works: one height field (warped fbm + metaball puffs + voronoi
//  pebbles). Film thickness follows the height, and its colour is the real
//  Michel-Levy interference sequence integrated over the spectrum (CIE 1931
//  fit), so the bands come out black > white > yellow > orange > red >
//  purple > blue in the right order. Image pass adds depth of field,
//  radial streaks with dispersion, two-radius bloom and film grain.
// =====================================================================

// ############################## IMAGE ###############################
// ---------------- Image : lens / film post ----------------
// iChannel0 = Buffer A  (filter: linear, wrap: clamp)

vec3 tapRGB(vec2 uv, vec2 c, float ca){
    vec2 d = uv - c;
    return vec3(texture(iChannel0, c + d*(1.+ca)).r,
                texture(iChannel0, uv).g,
                texture(iChannel0, c + d*(1.-ca)).b);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord/iResolution.xy;
    float t = iTime;
    vec2 bc = burstCenter(t);
    vec2 c = vec2(bc.x*iResolution.y/iResolution.x, bc.y)*.5 + .5;
    vec2 asp = vec2(iResolution.y/iResolution.x, 1.);

    // depth of field: clouds (high) drift out of focus
    float H = texture(iChannel0, uv).a;
    float coc = mix(1., 4., smoothstep(.55, .9, H)) / 450.;
    vec3 sharp = vec3(0);
    for(int i=0;i<12;i++){
        float fi = float(i)+.5;
        vec2 o = vec2(cos(fi*2.39996), sin(fi*2.39996))*sqrt(fi/12.)*coc*asp*1.0;
        sharp += tapRGB(uv+o, c, .005);
    }
    sharp /= 12.;

    // radial streak blur with growing dispersion
    vec3 acc = vec3(0); float ws = 0.;
    for(int i=0;i<14;i++){
        float k = float(i)/14.;
        vec2 s = mix(uv, c, k*.14);
        float w = 1.-k;
        acc += tapRGB(s, c, .005 + k*.012)*w; ws += w;
    }
    vec3 col = mix(sharp, acc/ws, .5);

    // bloom, two radii
    vec3 b1 = vec3(0), b2 = vec3(0);
    for(int i=0;i<24;i++){
        float fi = float(i)+.5;
        vec2 dir = vec2(cos(fi*2.39996), sin(fi*2.39996))*sqrt(fi/24.)*asp;
        b1 += max(texture(iChannel0, uv + dir*.03).rgb - .95, 0.);
        b2 += max(texture(iChannel0, uv + dir*.09).rgb - .9, 0.);
    }
    col += b1/24.*1. + b2/24.*.6;

    col *= .93;
    // soft knee: keep mids, roll highlights
    vec3 kn = .72 + .28*(1. - exp(-(col-.72)/.28));
    col = mix(col, kn, step(.72, col));
    col = pow(col, vec3(1.12));
    float g = hash12(fragCoord + fract(t*13.7)*517.) - .5;
    col += g*.035;
    fragColor = vec4(clamp(col,0.,1.),1.);
}
