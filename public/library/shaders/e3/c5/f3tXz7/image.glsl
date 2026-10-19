// ==== SEIFERT GLINT  -  Image (bloom + tonemap) ====
// iChannel0 = Buffer A   (filter: mipmap, wrap: clamp)

vec3 lodTap(vec2 uv, float l){
    vec2 px = exp2(l)/iResolution.xy;
    return 0.25*(textureLod(iChannel0, uv+px*vec2( 0.5, 0.5), l).rgb +
                 textureLod(iChannel0, uv+px*vec2(-0.5, 0.5), l).rgb +
                 textureLod(iChannel0, uv+px*vec2( 0.5,-0.5), l).rgb +
                 textureLod(iChannel0, uv+px*vec2(-0.5,-0.5), l).rgb);
}

vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord/iResolution.xy;
    vec3 c = texture(iChannel0, uv).rgb;
    // bloom: only the hot parts glow (glints, rim highlights)
    vec3 bl = vec3(0);
    bl += max(lodTap(uv,1.0)-1.2,0.0)*0.20;
    bl += max(lodTap(uv,2.0)-0.9,0.0)*0.20;
    bl += max(lodTap(uv,3.0)-0.6,0.0)*0.20;
    bl += max(lodTap(uv,4.0)-0.35,0.0)*0.18;
    bl += max(lodTap(uv,5.0)-0.2,0.0)*0.15;
    bl += lodTap(uv,6.0)*0.02;
    vec3 col = c + bl;
    col = aces(col*1.05);
    col = pow(col, vec3(1.0/2.2));
    col = col + (1.0-col)*(10.0/255.0);            // the reference's lifted black
    col += (fract(sin(dot(fragCoord,vec2(12.9898,78.233)))*43758.5453)-0.5)/255.0;
    fragColor = vec4(col,1.0);
}
