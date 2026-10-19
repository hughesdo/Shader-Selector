
// ############################## COMMON ##############################
// ---------------- Common ----------------
#define AUDIO_REACTIVE 1     // 1 = Buffer A iChannel0 gets Music/SoundCloud/Mic
#define SPEED 1.6            // morph speed (1.6 ~ source clip pacing, lower = calmer)

float hash12(vec2 p){ vec3 p3=fract(vec3(p.xyx)*.1031); p3+=dot(p3,p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
vec2  hash22(vec2 p){ vec3 p3=fract(vec3(p.xyx)*vec3(.1031,.1030,.0973)); p3+=dot(p3,p3.yzx+33.33); return fract((p3.xx+p3.yz)*p3.zy); }
float hash13(vec3 p){ p=fract(p*.1031); p+=dot(p,p.zyx+31.32); return fract((p.x+p.y)*p.z); }
mat2 rot(float a){ float c=cos(a), s=sin(a); return mat2(c,-s,s,c); }

float noise3(vec3 p){
    vec3 i=floor(p), f=fract(p); f=f*f*f*(f*(f*6.-15.)+10.);
    return mix(mix(mix(hash13(i),hash13(i+vec3(1,0,0)),f.x),mix(hash13(i+vec3(0,1,0)),hash13(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash13(i+vec3(0,0,1)),hash13(i+vec3(1,0,1)),f.x),mix(hash13(i+vec3(0,1,1)),hash13(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p){
    float a=.5, s=0.;
    for(int i=0;i<5;i++){ s+=a*noise3(p); p=p*2.03+vec3(1.7,9.2,3.1); p.xy*=mat2(.8,-.6,.6,.8); a*=.5; }
    return s/.97;
}

// burst centre (shared by scene + radial streak post), in scene coords (y in [-1,1])
vec2 burstCenter(float t){
    return vec2(sin(t*.37)*.55 + sin(t*.13)*.3, cos(t*.29)*.35);
}

// Michel-Levy interference colour for retardation R (nm), crossed polars.
// Precomputed: the CIE 1931 fit, its normalisation, XYZ->sRGB and the white
// balance are folded into one constant per wavelength (max error ~1e-7).
const vec3 ML_K[24] = vec3[24](
    vec3(-0.0005562359,0.00001934608,0.003107131),
    vec3(0.002004709,-0.001845686,0.01461912),
    vec3(0.01177474,-0.01121372,0.07909001),
    vec3(0.02083563,-0.02769741,0.2276834),
    vec3(0.02517129,-0.03073104,0.2710665),
    vec3(0.0003711190,-0.01438466,0.2549317),
    vec3(-0.02194320,0.01199202,0.1683233),
    vec3(-0.04407929,0.04551807,0.07674652),
    vec3(-0.07026943,0.08989251,0.02842411),
    vec3(-0.09288646,0.1510180,0.0001723999),
    vec3(-0.09228622,0.2006869,-0.01678699),
    vec3(-0.04823359,0.2064459,-0.02329962),
    vec3(0.02640112,0.1833857,-0.02398898),
    vec3(0.1178009,0.1389103,-0.02116480),
    vec3(0.2042897,0.08259588,-0.01626730),
    vec3(0.2611290,0.02784043,-0.01066464),
    vec3(0.2627633,-0.008734499,-0.005928630),
    vec3(0.2065589,-0.01978283,-0.002970950),
    vec3(0.1293454,-0.01532262,-0.001476401),
    vec3(0.06493439,-0.007297854,-0.0007928187),
    vec3(0.02610847,-0.001976614,-0.0004441021),
    vec3(0.008333846,0.00006327838,-0.0002326093),
    vec3(0.002062154,0.0003839728,-0.0001057587),
    vec3(0.0003696482,0.0002347095,-0.00004066634));
vec3 michelLevy(float R){
    vec3 rgb = vec3(0);
    for(int i=0;i<24;i++){
        float s = sin(3.14159265*R/(390. + float(i)*13.9));
        rgb += ML_K[i]*s*s;
    }
    return max(rgb, 0.);
}
