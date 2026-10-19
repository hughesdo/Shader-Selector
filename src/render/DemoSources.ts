/**
 * The two looping clips every transition card morphs between.
 *
 * A transition shader is not standalone: it needs a `from` and a `to` to blend.
 * In Sizzle those will be the real neighbouring clips on the timeline. Here in the
 * selector they are two fixed demo clips, because the card's job is only to show
 * what the transition LOOKS like, not to preview a specific edit.
 *
 * One pair is shared by every transition card, so this is created once, lazily,
 * the first time a transition is shown, and then kept for the session.
 */
/**
 * Each clip ships as WebM/VP9 first and MP4/H.264 second.
 *
 * This is not just belt and braces. Chromium builds without proprietary codecs,
 * which includes the one Playwright drives, cannot decode H.264 at all, so an
 * mp4-only clip silently never loads and every transition renders a flat frame.
 * That is exactly how the preview-rendering tool runs, so WebM has to come first.
 * MP4 stays for Safari, which does not take VP9 in every version.
 */
export interface ClipSources {
  webm: string;
  mp4: string;
}

export class DemoSources {
  private videos: HTMLVideoElement[] = [];
  private textures: WebGLTexture[] = [];
  private ready = false;

  constructor(private gl: WebGL2RenderingContext, private urls: [ClipSources, ClipSources]) {}

  /**
   * Starts both clips and uploads a first frame. Resolves once they are playing,
   * or after a timeout, so a card never hangs on a missing or blocked video.
   */
  async init(): Promise<void> {
    if (this.ready) return;
    const gl = this.gl;
    this.videos = this.urls.map((srcs) => {
      const v = document.createElement('video');
      v.loop = true;
      v.muted = true;              // required for autoplay without a user gesture
      v.playsInline = true;
      v.preload = 'auto';
      v.crossOrigin = 'anonymous';
      // <source> elements rather than .src so the browser picks a codec it has.
      for (const [url, type] of [[srcs.webm, 'video/webm'], [srcs.mp4, 'video/mp4']]) {
        const s = document.createElement('source');
        s.src = url;
        s.type = type;
        v.appendChild(s);
      }
      v.load();
      return v;
    });
    this.textures = this.videos.map(() => {
      const t = gl.createTexture()!;
      gl.bindTexture(gl.TEXTURE_2D, t);
      // 1x1 mid grey until the first frame lands, so nothing flashes black
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE,
        new Uint8Array([128, 128, 128, 255]));
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      return t;
    });

    await Promise.all(this.videos.map((v) => new Promise<void>((resolve) => {
      let settled = false;
      const done = () => { if (!settled) { settled = true; resolve(); } };
      v.addEventListener('canplay', () => { v.play().catch(() => {}); done(); }, { once: true });
      v.addEventListener('error', done, { once: true });
      // Never let a card wait on a clip that will not load.
      setTimeout(done, 4000);
    })));
    this.ready = true;
  }

  /** Re-uploads any frame that advanced. Called once per rendered frame. */
  update(): void {
    const gl = this.gl;
    for (let i = 0; i < this.videos.length; i++) {
      const v = this.videos[i];
      if (v.readyState < 2 || v.videoWidth === 0) continue;
      gl.bindTexture(gl.TEXTURE_2D, this.textures[i]);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, v);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    }
  }

  /** 0 = from, 1 = to. Returns null before init so callers fall back to black. */
  texture(which: 0 | 1): WebGLTexture | null {
    return this.textures[which] ?? null;
  }

  /** Both clips are the same size; used for the `ratio` uniform some transitions take. */
  aspect(): number {
    const v = this.videos[0];
    return v && v.videoWidth ? v.videoWidth / v.videoHeight : 16 / 9;
  }

  play(): void {
    this.videos.forEach((v) => v.play().catch(() => {}));
  }

  pause(): void {
    this.videos.forEach((v) => v.pause());
  }

  dispose(): void {
    this.videos.forEach((v) => { v.pause(); v.removeAttribute('src'); v.load(); });
    this.textures.forEach((t) => this.gl.deleteTexture(t));
    this.videos = [];
    this.textures = [];
    this.ready = false;
  }
}

/**
 * Progress for a looping transition preview.
 *
 * A bare 0->1 sawtooth reads badly: the morph is over before your eye catches it
 * and you never see the endpoints cleanly. So hold on A, run the real 1.6s morph,
 * hold on B, then snap back.
 */
export const TRANSITION_SECONDS = 1.6;
const HOLD_SECONDS = 0.7;

export function loopProgress(time: number): number {
  const cycle = HOLD_SECONDS + TRANSITION_SECONDS + HOLD_SECONDS;
  const t = time % cycle;
  if (t < HOLD_SECONDS) return 0;
  if (t < HOLD_SECONDS + TRANSITION_SECONDS) {
    return (t - HOLD_SECONDS) / TRANSITION_SECONDS;
  }
  return 1;
}
