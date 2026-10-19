/**
 * Feeds the shaders' "music" input.
 *
 * Texture layout matches OneOffRender exactly (512x256, single channel R8):
 *   row 0..1   : 512-bin FFT spectrum (1024-pt FFT, 0.8 smoothing)
 *   row 2..255 : 512-sample waveform
 * So texture(iChannel0, vec2(x, 0.0)) = spectrum, vec2(x, 1.0) = waveform,
 * texelFetch(iChannel0, ivec2(bin, 0), 0) = spectrum. Same behaviour as in your renderer.
 */
export interface Track {
  id: string;
  label: string;
  url?: string;      // undefined = silence; 'mic' = microphone
}

export const W = 512;
export const H = 256;

export class AudioEngine {
  private ctx?: AudioContext;
  private analyser?: AnalyserNode;
  private gain?: GainNode;
  private el = new Audio();
  private elSource?: MediaElementAudioSourceNode;
  private micSource?: MediaStreamAudioSourceNode;
  private micStream?: MediaStream;
  private freq = new Uint8Array(W);
  private wave = new Uint8Array(W * 2);
  /** Packed texture bytes, uploaded by the renderer each frame. */
  readonly pixels = new Uint8Array(W * H);
  current: Track | null = null;
  /** Rough band levels 0..1, handy for UI meters. */
  levels = { bass: 0, mid: 0, high: 0 };

  constructor() {
    this.el.loop = true;
    this.el.crossOrigin = 'anonymous';
    this.el.preload = 'auto';
  }

  get sampleRate(): number {
    return this.ctx?.sampleRate ?? 44100;
  }

  get playing(): boolean {
    return !!this.current?.url && (this.current.url === 'mic' || !this.el.paused);
  }

  /** Must be called from a user gesture the first time (browser autoplay rules). */
  async unlock(): Promise<void> {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 1024;
      this.analyser.smoothingTimeConstant = 0.8;
      this.gain = this.ctx.createGain();
      this.gain.gain.value = 0.8;
      this.elSource = this.ctx.createMediaElementSource(this.el);
      this.elSource.connect(this.analyser);
      this.analyser.connect(this.gain);
      this.gain.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') await this.ctx.resume();
  }

  setVolume(v: number): void {
    if (this.gain) this.gain.gain.value = v;
  }

  async select(track: Track): Promise<void> {
    this.current = track;
    this.stopMic();
    this.el.pause();
    if (!track.url) return;
    await this.unlock();
    if (track.url === 'mic') {
      this.micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      this.micSource = this.ctx!.createMediaStreamSource(this.micStream);
      // mic goes to the analyser only, never to the speakers (feedback)
      this.analyser!.disconnect();
      this.micSource.connect(this.analyser!);
      return;
    }
    this.analyser!.disconnect();
    this.analyser!.connect(this.gain!);
    if (!this.el.src.endsWith(track.url)) this.el.src = track.url;
    await this.el.play();
  }

  async toggle(): Promise<boolean> {
    if (!this.current?.url || this.current.url === 'mic') return this.playing;
    await this.unlock();
    if (this.el.paused) await this.el.play();
    else this.el.pause();
    return this.playing;
  }

  private stopMic(): void {
    this.micSource?.disconnect();
    this.micStream?.getTracks().forEach((t) => t.stop());
    this.micSource = undefined;
    this.micStream = undefined;
  }

  /** Call once per rendered frame. */
  update(): Uint8Array {
    const a = this.analyser;
    const active = a && this.playing;
    if (active) {
      a.getByteFrequencyData(this.freq);
      a.getByteTimeDomainData(this.wave);
    } else {
      this.freq.fill(0);
      this.wave.fill(128);
    }
    const px = this.pixels;
    px.set(this.freq, 0);
    px.set(this.freq, W);
    // waveform: first 512 of the 1024 time-domain samples
    const w = this.wave.subarray(0, W);
    for (let row = 2; row < H; row++) px.set(w, row * W);

    const band = (lo: number, hi: number) => {
      let s = 0;
      for (let i = lo; i < hi; i++) s += this.freq[i];
      return s / ((hi - lo) * 255);
    };
    this.levels.bass = band(1, 12);
    this.levels.mid = band(12, 90);
    this.levels.high = band(90, 300);
    return px;
  }
}
