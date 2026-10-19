"""
Synthesizes three placeholder loops (16s, 120 BPM, seamless) for audio-reactive testing.
Swap them for your Suno tracks later: same filenames in public/audio/.

  bass.mp3   sub kicks + wobbling sub bass      (lights up the low FFT bins)
  mids.mp3   kick/snare groove + chord stabs    (low-mids, 200 Hz..3 kHz)
  highs.mp3  arpeggios + string pad + 16th hats (upper bins, 2 kHz..12 kHz)

Requires numpy + ffmpeg on PATH.
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
BPM = 120
BEAT = 60 / BPM
BARS = 8
DUR = BARS * 4 * BEAT
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(7)


def env(n, a=0.002, d=0.2):
    x = np.arange(n) / SR
    e = np.minimum(1, x / a) * np.exp(-x / d)
    return e


def place(buf, sig, at):
    i = int(at * SR) % N
    end = i + len(sig)
    if end <= N:
        buf[i:end] += sig
    else:  # wrap so the loop is seamless
        k = N - i
        buf[i:] += sig[:k]
        buf[: len(sig) - k] += sig[k:]


def kick(length=0.45, f0=130, f1=42):
    n = int(SR * length)
    x = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-x * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(n, 0.001, 0.22)


def snare(length=0.25):
    n = int(SR * length)
    noise = rng.standard_normal(n)
    noise = np.convolve(noise, np.ones(3) / 3, mode="same") - np.convolve(noise, np.ones(40) / 40, mode="same")
    tone = np.sin(2 * np.pi * 190 * np.arange(n) / SR)
    return (noise * 0.8 + tone * 0.4) * env(n, 0.001, 0.08)


def hat(length=0.06, bright=True):
    n = int(SR * length)
    noise = rng.standard_normal(n)
    hp = noise - np.convolve(noise, np.ones(6 if bright else 12) / (6 if bright else 12), mode="same")
    return hp * env(n, 0.0005, 0.018)


def saw(freq, n, detune=0.0):
    x = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-detune, 0, detune) if detune else (0,):
        out += 2 * ((x * freq * (1 + d)) % 1) - 1
    return out / (3 if detune else 1)


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")


def note(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def bass_loop():
    b = np.zeros(N)
    for i in range(BARS * 4):
        place(b, kick(0.55, 120, 38) * 1.0, i * BEAT)
    # wobbling sub bass, root pattern per bar
    roots = [33, 33, 36, 31, 33, 33, 38, 36]
    sub = np.zeros(N)
    for bar, r in enumerate(roots):
        s, e = int(bar * 4 * BEAT * SR), int((bar + 1) * 4 * BEAT * SR)
        x = t[s:e]
        wob = 0.5 + 0.5 * np.sin(2 * np.pi * (2 if bar % 2 else 4) * x / (BEAT * 2))
        f = note(r)
        sub[s:e] = (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * 2 * f * x)) * wob
    # sidechain duck on the kick
    duck = 1 - 0.7 * np.exp(-((t % BEAT) / 0.12))
    b += sub * duck * 0.8
    for i in range(BARS * 8):
        place(b, hat(0.04, False) * 0.08, i * BEAT / 2 + BEAT / 4)
    return norm(lowpass(b, 2))


def mids_loop():
    m = np.zeros(N)
    for i in range(BARS * 4):
        place(m, kick(0.18, 170, 90) * 0.3, i * BEAT)
        if i % 2 == 1:
            place(m, snare() * 0.9, i * BEAT)
    for i in range(BARS * 8):
        place(m, hat(0.05) * 0.12, i * BEAT / 2)
    chords = [[57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65], [52, 55, 59, 62]]
    stab_n = int(SR * 0.32)
    for bar in range(BARS):
        ch = chords[bar % 4]
        for hit in (0, 1.5, 2.5, 3.5):
            sig = sum(saw(note(n), stab_n, 0.004) for n in ch) / len(ch)
            sig = lowpass(sig, 14) * env(stab_n, 0.004, 0.11)
            place(m, sig * 1.4, bar * 4 * BEAT + hit * BEAT)
    # toms fill on the last bar
    for k, f0 in enumerate((180, 150, 120, 95)):
        place(m, kick(0.25, f0 * 2.6, f0 * 2) * 0.5, (BARS - 1) * 4 * BEAT + (2 + k * 0.5) * BEAT)
    return norm(m)


def highs_loop():
    h = np.zeros(N)
    arp = [84, 88, 91, 95, 96, 95, 91, 88]
    pl_n = int(SR * 0.22)
    for i in range(BARS * 16):
        n = arp[i % len(arp)] + (12 if (i // 32) % 2 else 0)
        x = np.arange(pl_n) / SR
        f = note(n)
        pluck = (np.sin(2 * np.pi * f * x) + 0.5 * np.sin(2 * np.pi * 2 * f * x) + 0.25 * np.sin(2 * np.pi * 3 * f * x))
        place(h, pluck * env(pl_n, 0.002, 0.07) * 0.55, i * BEAT / 4)
    # string pad: detuned saws, high-passed, slow swell per bar
    pad_notes = [[88, 91, 95, 100], [84, 88, 91, 96], [86, 89, 93, 98], [83, 86, 91, 95]]
    for bar in range(BARS):
        s, e = int(bar * 4 * BEAT * SR), int((bar + 1) * 4 * BEAT * SR)
        n = e - s
        sig = sum(saw(note(p), n, 0.006) for p in pad_notes[bar % 4]) / 4
        sig = sig - lowpass(sig, 24)
        swell = np.sin(np.pi * np.arange(n) / n) ** 1.5
        h[s:e] += sig * swell * 0.5
    for i in range(BARS * 16):
        place(h, hat(0.03) * (0.4 if i % 4 == 2 else 0.25), i * BEAT / 4)
    # a soft low pulse so bass-only shaders still breathe a little
    for i in range(0, BARS * 4, 2):
        place(h, kick(0.3, 100, 50) * 0.15, i * BEAT)
    return norm(h)


def write(path: Path, x: np.ndarray):
    wav = path.with_suffix(".wav")
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-codec:a", "libmp3lame", "-b:a", "128k", str(path)], check=True)
    wav.unlink()


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "public/audio")
    out.mkdir(parents=True, exist_ok=True)
    write(out / "bass.mp3", bass_loop())
    write(out / "mids.mp3", mids_loop())
    write(out / "highs.mp3", highs_loop())
    print(f"wrote 3 loops ({DUR:.0f}s each) to {out}")


if __name__ == "__main__":
    main()
