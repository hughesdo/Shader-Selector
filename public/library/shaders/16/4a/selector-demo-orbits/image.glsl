// Image: tone-map Buffer A and draw a thin live spectrum along the bottom.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec3 col = texture(iChannel0, uv).rgb;
    col = 1.0 - exp(-col * 1.4);

    float s = fft(iChannel1, uv.x * 0.5);
    float bar = smoothstep(0.004, 0.0, uv.y - s * 0.12);
    col += bar * palette(uv.x + iTime * 0.1) * 0.35;

    // vignette
    col *= 1.0 - 0.35 * dot(uv - 0.5, uv - 0.5) * 2.0;
    fragColor = vec4(pow(col, vec3(0.92)), 1.0);
}
