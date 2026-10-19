// Buffer A: feedback trails. iChannel0 = Buffer A (previous frame), iChannel1 = music.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    float bass = band(iChannel1, 0.0, 0.04);
    float high = band(iChannel1, 0.25, 0.6);

    // previous frame, slightly zoomed and swirled so trails spiral inward
    vec2 q = (uv - 0.5) * (0.985 - bass * 0.01);
    q *= rot(0.004 + high * 0.02);
    vec3 prev = texture(iChannel0, q + 0.5).rgb * 0.965;

    vec3 col = vec3(0.0);
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float t = iTime * (0.35 + fi * 0.07);
        float r = 0.12 + fi * 0.045 + bass * 0.08;
        vec2 c = r * vec2(cos(t + fi), sin(t * 1.3 + fi * 2.0));
        float d = length(p - c);
        col += palette(fi / 7.0 + iTime * 0.05) * (0.0016 + high * 0.002) / (d * d + 0.0004);
    }
    fragColor = vec4(prev + col * 0.06, 1.0);
}
