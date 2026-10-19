// ============================================================================   
//  SPECTRUM VORTEX (audio reactive)            -- BUFFER A tab --
//  iChannel0 = music, iChannel1 = Buffer A (itself)
//  Smooths the audio, runs the audio clock and kick spring, and stores a
//  frozen spectrum snapshot for every ring as it is born.
// ============================================================================

vec4 prev(int x, int y){ return texelFetch(iChannel1, ivec2(x, y), 0); }
float fft(float x){ return texture(iChannel0, vec2(x, 0.25)).x*AUDIO_GAIN; }
float wav(float x){ return texture(iChannel0, vec2(x, 0.75)).x; }

struct State { vec4 fast; vec4 slow; vec4 clk; vec4 kick; vec4 ons; };

State stepState(float dt){
    State s;
    vec4 pf = prev(0,0), ps = prev(1,0), pc = prev(2,0), pk = prev(3,0);

    // raw bands
    float bass = 0.0, mid = 0.0, high = 0.0;
    for (int i = 0; i < 4; i++){
        float f = float(i)/3.0;
        bass += fft(mix(0.004, 0.018, f));
        mid  += fft(mix(0.03, 0.15, f));
        high += fft(mix(0.20, 0.50, f))*(1.0 + SPEC_TILT*0.5);
    }
    bass *= 0.25; mid *= 0.25; high = clamp(high*0.25, 0.0, 1.0);
    float loud = clamp(0.5*bass + 0.3*mid + 0.2*high, 0.0, 1.0);

    // fast bands (light smoothing, keeps punch)
    s.fast.x = smoothAR(pf.x, bass, 0.02, 0.12, dt);
    s.fast.y = smoothAR(pf.y, mid,  0.03, 0.15, dt);
    s.fast.z = smoothAR(pf.z, high, HIGH_ATTACK, HIGH_RELEASE, dt);
    s.fast.w = smoothAR(pf.w, loud, 0.03, 0.15, dt);

    // long averages warm up quickly after a restart so nothing surges at t=0
    float wu = 0.3 + iTime;
    float drive = s.fast.x + 0.35*pc.y;          // bass level + kick density
    s.slow.x = smoothAR(ps.x, drive, min(SPEED_AVG, wu), min(SPEED_AVG, wu), dt);   // drive average
    s.slow.y = smoothAR(ps.y, s.fast.w, min(TWIST_SMOOTH, wu), min(TWIST_SMOOTH, wu), dt); // loudness (twist)
    s.slow.z = smoothAR(ps.z, s.fast.w, min(TWIST_AVG, wu), min(TWIST_AVG, wu), dt);       // loudness average
    s.slow.w = smoothAR(ps.w, drive - s.slow.x, SPEED_SMOOTH, SPEED_SMOOTH, dt);            // speed drive

    // audio clock: integrates speed, so speed changes never jump position
    float speed = 1.0;
#if ENABLE_SPEED
    speed = clamp(1.0 + SPEED_AMT*s.slow.w*2.5, SPEED_MIN, SPEED_MAX);
#endif
    s.clk.x = pc.x + dt*speed;

    // kick onset = raw bass jumping above its short average
    s.clk.z = smoothAR(pc.z, bass, 0.12, 0.12, dt);
    float onset = max(bass - pc.z - 0.025/KICK_SENS, 0.0)*12.0;
    float po = prev(4,0).x;
    s.ons = vec4(smoothAR(po, min(onset, 1.5), KICK_SMOOTH, KICK_SMOOTH*2.0 + 0.02, dt), 0.0, 0.0, 0.0);
    s.clk.y = smoothAR(pc.y, clamp(onset, 0.0, 1.0), PULSE_ATTACK, PULSE_RELEASE, dt);
    s.clk.w = s.fast.z;

    // kick spring: onset pushes the center, spring + damping pull it home
    vec2 pos = pk.xy, vel = pk.zw;
#if ENABLE_CENTER_KICK
    float ang = s.clk.x*1.7 + 0.8*sin(s.clk.x*0.37);
    vec2 force = vec2(cos(ang), sin(ang))*s.ons.x*9.0*KICK_STRENGTH;
    vec2 acc = force - KICK_SPRING*pos - KICK_DAMP*vel;
    vel += acc*dt;
    pos += vel*dt;
    pos = clamp(pos, vec2(-0.25), vec2(0.25));
#else
    pos = vec2(0.0); vel = vec2(0.0);
#endif
    s.kick = vec4(pos, vel);
    return s;
}

void mainImage(out vec4 o, in vec2 fragCoord){
    ivec2 ip = ivec2(fragCoord);
    float dt = clamp(iTimeDelta, 0.0, 0.1);

    if (iFrame < 2){
        o = vec4(0.0);
        if (ip.y >= 2 && ip.x == NBINS) o = vec4(-99999.0, 0.0, 0.0, 0.0);
        return;
    }
    if (ip.y > 1 + NSLOT || ip.x > NBINS + 1){ o = vec4(0.0); return; }

    State s = stepState(dt);

    // ---- row 0: state
    if (ip.y == 0){
        if      (ip.x == 0) o = s.fast;
        else if (ip.x == 1) o = s.slow;
        else if (ip.x == 2) o = s.clk;
        else if (ip.x == 3) o = s.kick;
        else if (ip.x == 4) o = s.ons;
        else o = vec4(0.0);
        return;
    }

    // ---- row 1: smoothed spectrum + waveform per bin
    if (ip.y == 1){
        if (ip.x >= NBINS){ o = vec4(0.0); return; }
        float b = (float(ip.x) + 0.5)/float(NBINS);
        float x = binToFFT(b);
        float raw = fft(x)*(1.0 + SPEC_TILT*b);
        raw = clamp(raw, 0.0, 1.2);
        vec4 p = prev(ip.x, 1);
        float sp = smoothAR(p.x, raw, SPEC_ATTACK, SPEC_RELEASE, dt);
        float w = mix(p.y, wav(b), 1.0 - exp(-dt/0.02));
        o = vec4(sp, w, 0.0, 0.0);
        return;
    }

    // ---- rows 2..: ring snapshots, written once when that ring is born
    int slot = ip.y - 2;
    float curId = floor(s.clk.x*RATE);
    float wantId = curId - posMod(curId - float(slot), float(NSLOT));
    float haveId = prev(NBINS, ip.y).x;
    if (haveId == idKey(wantId)){ o = prev(ip.x, ip.y); return; }

    if (ip.x < NBINS)       o = vec4(prev(ip.x, 1).xy, 0.0, 0.0);
    else if (ip.x == NBINS) o = vec4(idKey(wantId), s.kick.xy, s.clk.y);
    else                    o = vec4(s.fast.z, s.fast.w, 0.0, 0.0);
}
