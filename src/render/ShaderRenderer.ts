import type { BufferId, ParamValue, PassInput, RenderPass, ShaderDoc } from '../library/schema';
import { kindOf } from '../library/schema';
import type { ResolvedShader } from '../library/Library';
import { AudioEngine, H as AUDIO_H, W as AUDIO_W } from '../audio/AudioEngine';
import { prepareFragment, remapErrors, VERTEX_SRC } from './preprocess';
import { type ClipSources, DemoSources, loopProgress } from './DemoSources';

export class CompileError extends Error {
  constructor(message: string, readonly log: string) {
    super(message);
  }
}

type Setter = (s: FrameState) => void;

interface FrameState {
  time: number;
  dt: number;
  frame: number;
  w: number;
  h: number;
  mouse: [number, number, number, number];
  date: [number, number, number, number];
  sampleRate: number;
  /** 0..1 for a transition, held at the ends so both sources are legible. */
  progress: number;
  /** Aspect of the demo clips, for transitions that take a `ratio`. */
  ratio: number;
}

/**
 * Which source a sampler wants. Standalone shaders use `input` (iChannelN);
 * transitions bind by uniform NAME instead, since gl-transitions declares
 * `from` and `to` rather than channels.
 */
type SamplerRole = 'input' | 'from' | 'to' | 'unbound';

interface SamplerBinding {
  loc: WebGLUniformLocation;
  unit: number;
  isCube: boolean;
  input?: PassInput;
  role: SamplerRole;
}

interface CompiledPass {
  pass: RenderPass;
  program: WebGLProgram;
  setters: Setter[];
  samplers: SamplerBinding[];
}

interface PingPong {
  tex: [WebGLTexture, WebGLTexture];
  fbo: [WebGLFramebuffer, WebGLFramebuffer];
  read: 0 | 1;
}

export interface Instance {
  id: string;
  passes: CompiledPass[];
  buffers: Map<BufferId, PingPong>;
  assets: Map<string, WebGLTexture>;
  bw: number;
  bh: number;
  compileMs: number;
  /** True for gl-transitions, which drive `progress` and need the demo clips. */
  isTransition: boolean;
}

const nextFrame = () => new Promise<number>((r) => requestAnimationFrame(r));

/**
 * One WebGL2 context, shared by every shader. It lives on a single canvas that the
 * carousel parks inside whichever card is centered.
 */
export class ShaderRenderer {
  readonly canvas: HTMLCanvasElement;
  readonly gl: WebGL2RenderingContext;
  private parallel: { COMPLETION_STATUS_KHR: number } | null;
  private floatBuffers: boolean;
  private vao: WebGLVertexArrayObject;
  private audioTex: WebGLTexture;
  private black2D: WebGLTexture;
  private blackCube: WebGLTexture;
  private assetCache = new Map<string, Promise<WebGLTexture>>();
  private cache = new Map<string, Instance>();
  private readonly cacheSize = 6;
  private current: Instance | null = null;
  private demoSources: DemoSources | null = null;
  /** Where the two transition demo clips live, relative to the page. */
  demoUrls: [ClipSources, ClipSources] = [
    { webm: 'library/demo/transition_a.webm', mp4: 'library/demo/transition_a.mp4' },
    { webm: 'library/demo/transition_b.webm', mp4: 'library/demo/transition_b.mp4' },
  ];
  private raf = 0;
  private t0 = 0;
  private last = 0;
  private frame = 0;
  private mouse: [number, number, number, number] = [0, 0, 0, 0];
  private onFirstFrame: (() => void) | null = null;
  /** Max backing-store size of the live canvas, keeps big raymarchers responsive. */
  maxPixels = 1280 * 720;
  fps = 0;

  constructor(private audio: AudioEngine) {
    this.canvas = document.createElement('canvas');
    this.canvas.className = 'live-canvas';
    const gl = this.canvas.getContext('webgl2', {
      alpha: false,
      antialias: false,
      depth: false,
      stencil: false,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
      powerPreference: 'high-performance',
    });
    if (!gl) throw new Error('WebGL2 not available');
    this.gl = gl;
    this.parallel = gl.getExtension('KHR_parallel_shader_compile');
    this.floatBuffers = !!gl.getExtension('EXT_color_buffer_float');
    this.vao = gl.createVertexArray()!;
    this.audioTex = this.makeTex2D(AUDIO_W, AUDIO_H, gl.R8, gl.RED, gl.UNSIGNED_BYTE, gl.LINEAR, gl.CLAMP_TO_EDGE);
    this.black2D = this.makeTex2D(1, 1, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, gl.NEAREST, gl.CLAMP_TO_EDGE);
    this.blackCube = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, this.blackCube);
    for (let f = 0; f < 6; f++) {
      gl.texImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
    }
    this.canvas.addEventListener('pointermove', (e) => this.pointer(e, false));
    this.canvas.addEventListener('pointerdown', (e) => this.pointer(e, true));
    this.canvas.addEventListener('pointerup', () => {
      this.mouse[2] = -Math.abs(this.mouse[2]);
      this.mouse[3] = -Math.abs(this.mouse[3]);
    });
  }

  get supportsParallelCompile(): boolean {
    return !!this.parallel;
  }

  isCached(id: string): boolean {
    return this.cache.has(id);
  }

  // ------------------------------------------------------------------ compile

  /**
   * Compiles every pass. With KHR_parallel_shader_compile the driver works in the
   * background and we poll once per frame, so the carousel never hitches.
   * Resolves to a cached instance when the same shader was compiled recently.
   */
  async prepare(rs: ResolvedShader, signal?: AbortSignal): Promise<Instance> {
    const cached = this.cache.get(rs.entry.id);
    if (cached) {
      this.cache.delete(rs.entry.id);
      this.cache.set(rs.entry.id, cached);
      return cached;
    }
    const gl = this.gl;
    const t = performance.now();
    const { doc } = rs;
    const common = doc.renderpass.filter((p) => p.type === 'common').map((p) => p.code ?? '').join('\n');
    const runnable = doc.renderpass.filter((p) => p.type === 'image' || p.type === 'buffer');
    if (!runnable.some((p) => p.type === 'image')) throw new CompileError('no image pass', '');

    // Give the UI a frame to paint its "compiling" state before any blocking work.
    await nextFrame();
    if (signal?.aborted) throw new DOMException('aborted', 'AbortError');

    const pending = runnable.map((pass) => {
      const prep = prepareFragment(doc.dialect, pass.code ?? '', {
        common,
        inputs: pass.inputs,
        isImage: pass.type === 'image',
      });
      const vs = gl.createShader(gl.VERTEX_SHADER)!;
      gl.shaderSource(vs, VERTEX_SRC);
      gl.compileShader(vs);
      const fs = gl.createShader(gl.FRAGMENT_SHADER)!;
      gl.shaderSource(fs, prep.source);
      gl.compileShader(fs);
      const program = gl.createProgram()!;
      gl.attachShader(program, vs);
      gl.attachShader(program, fs);
      gl.linkProgram(program);
      return { pass, program, vs, fs, lineOffset: prep.lineOffset };
    });

    if (this.parallel) {
      const done = (p: WebGLProgram) => gl.getProgramParameter(p, this.parallel!.COMPLETION_STATUS_KHR);
      while (!pending.every((p) => done(p.program))) {
        await nextFrame();
        if (signal?.aborted) {
          // Let the driver finish, then throw the work away.
          pending.forEach((p) => this.dropProgram(p.program, p.vs, p.fs));
          throw new DOMException('aborted', 'AbortError');
        }
      }
    }

    const failures: string[] = [];
    for (const p of pending) {
      if (!gl.getProgramParameter(p.program, gl.LINK_STATUS)) {
        const flog = gl.getShaderInfoLog(p.fs) || '';
        const plog = gl.getProgramInfoLog(p.program) || '';
        failures.push(`[${p.pass.name}]\n${remapErrors(flog || plog, p.lineOffset)}`);
      }
    }
    if (failures.length) {
      pending.forEach((p) => this.dropProgram(p.program, p.vs, p.fs));
      throw new CompileError(`compile failed: ${rs.entry.id}`, failures.join('\n'));
    }
    pending.forEach((p) => {
      gl.detachShader(p.program, p.vs);
      gl.detachShader(p.program, p.fs);
      gl.deleteShader(p.vs);
      gl.deleteShader(p.fs);
    });

    const isTransition = kindOf(doc) === 'transition';
    const inst: Instance = {
      id: rs.entry.id,
      passes: pending.map((p) => this.introspect(p.pass, p.program, doc)),
      buffers: new Map(),
      assets: new Map(),
      bw: 0,
      bh: 0,
      compileMs: 0,
      isTransition,
    };
    if (isTransition) await this.demo().init();

    // textures / cubemaps, shared across shaders by content hash
    const assetInputs = runnable.flatMap((p) => p.inputs).filter((i) => i.type === 'texture' || i.type === 'cubemap');
    await Promise.all(
      assetInputs.map(async (i) => {
        if (!i.ref || !i.src) return;
        try {
          inst.assets.set(i.ref, await this.loadAsset(i, rs.baseUrl));
        } catch (err) {
          console.warn(`[asset] ${i.src}`, err);
        }
      }),
    );
    if (signal?.aborted) {
      // compiled fine, just not wanted right now: keep it for when the user comes back
      this.remember(inst);
      throw new DOMException('aborted', 'AbortError');
    }
    inst.compileMs = performance.now() - t;
    this.remember(inst);
    return inst;
  }

  /** Created on first use: most sessions never show a transition at all. */
  private demo(): DemoSources {
    if (!this.demoSources) this.demoSources = new DemoSources(this.gl, this.demoUrls);
    return this.demoSources;
  }

  private remember(inst: Instance): void {
    this.cache.set(inst.id, inst);
    while (this.cache.size > this.cacheSize) {
      const [oldId, old] = this.cache.entries().next().value as [string, Instance];
      if (old === this.current) {
        this.cache.delete(oldId);
        this.cache.set(oldId, old);
        continue;
      }
      this.cache.delete(oldId);
      this.destroy(old);
    }
  }

  private dropProgram(p: WebGLProgram, vs: WebGLShader, fs: WebGLShader): void {
    this.gl.deleteProgram(p);
    this.gl.deleteShader(vs);
    this.gl.deleteShader(fs);
  }

  private destroy(inst: Instance): void {
    const gl = this.gl;
    inst.passes.forEach((p) => gl.deleteProgram(p.program));
    this.freeBuffers(inst);
  }

  private introspect(pass: RenderPass, program: WebGLProgram, doc?: ShaderDoc): CompiledPass {
    const gl = this.gl;
    const setters: Setter[] = [];
    const samplers: SamplerBinding[] = [];
    const n = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS) as number;
    const params = doc?.params ?? {};
    let unit = 0;
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(program, i);
      if (!info) continue;
      const name = info.name.replace(/\[0\]$/, '');
      const loc = gl.getUniformLocation(program, info.name);
      if (!loc) continue;
      const T = info.type;
      if (T === gl.SAMPLER_2D || T === gl.SAMPLER_CUBE) {
        const ch = /^iChannel([0-3])$/.exec(name);
        const input = pass.inputs.find((inp) => (inp.uniform ? inp.uniform === name : ch && inp.channel === +ch[1]));
        let role: SamplerRole = input ? 'input' : 'unbound';
        if (name === 'from') role = 'from';
        else if (name === 'to') role = 'to';
        // A transition's extra samplers (displacementMap, luma) have nothing to
        // bind, so they read the `from` clip rather than whatever unit 0 holds.
        // That matches what OneOffRender ends up doing, but on purpose.
        else if (!input && doc && kindOf(doc) === 'transition') role = 'from';
        samplers.push({ loc, unit: unit++, isCube: T === gl.SAMPLER_CUBE, input, role });
        continue;
      }
      // A transition's tunables are constants for the life of the instance.
      if (Object.prototype.hasOwnProperty.call(params, name)) {
        const s = this.paramSetter(name, params[name], T, loc);
        if (s) { setters.push(s); continue; }
      }
      const s = this.uniformSetter(name, T, loc, info.size);
      if (s) setters.push(s);
    }
    return { pass, program, setters, samplers };
  }

  /** Binds a stored parameter value, coping with number / bool / vecN. */
  private paramSetter(_name: string, v: ParamValue, T: number, loc: WebGLUniformLocation): Setter | null {
    const gl = this.gl;
    const nums = Array.isArray(v) ? v : [typeof v === 'boolean' ? (v ? 1 : 0) : v];
    switch (T) {
      case gl.FLOAT: return () => gl.uniform1f(loc, nums[0]);
      case gl.FLOAT_VEC2: return () => gl.uniform2f(loc, nums[0], nums[1] ?? 0);
      case gl.FLOAT_VEC3: return () => gl.uniform3f(loc, nums[0], nums[1] ?? 0, nums[2] ?? 0);
      case gl.FLOAT_VEC4: return () => gl.uniform4f(loc, nums[0], nums[1] ?? 0, nums[2] ?? 0, nums[3] ?? 0);
      case gl.INT: return () => gl.uniform1i(loc, nums[0] | 0);
      case gl.BOOL: return () => gl.uniform1i(loc, nums[0] ? 1 : 0);
      default: return null;
    }
  }

  /** Type-aware: OneOffRender shaders declare iMouse as vec2 or vec4, iFrame as int or float, etc. */
  private uniformSetter(name: string, T: number, loc: WebGLUniformLocation, size: number): Setter | null {
    const gl = this.gl;
    const vec = (v: number[]) => {
      if (T === gl.FLOAT) gl.uniform1f(loc, v[0]);
      else if (T === gl.FLOAT_VEC2) gl.uniform2f(loc, v[0], v[1]);
      else if (T === gl.FLOAT_VEC3) gl.uniform3f(loc, v[0], v[1], v[2] ?? 1);
      else if (T === gl.FLOAT_VEC4) gl.uniform4f(loc, v[0], v[1], v[2] ?? 0, v[3] ?? 0);
      else if (T === gl.INT) gl.uniform1i(loc, v[0] | 0);
    };
    switch (name) {
      case 'iTime':
      case 'time':
      case 'iGlobalTime':
        return (s) => vec([s.time]);
      case 'iTimeDelta':
        return (s) => vec([s.dt]);
      case 'iFrameRate':
        return (s) => vec([s.dt > 0 ? 1 / s.dt : 60]);
      case 'iFrame':
        return (s) => vec([s.frame]);
      case 'iResolution':
      case 'resolution':
      case 'v2Resolution':
        return (s) => vec([s.w, s.h, 1]);
      case 'iMouse':
      case 'mouse':
        return (s) => vec(s.mouse);
      case 'iDate':
      case 'date':
        return (s) => vec(s.date);
      case 'iSampleRate':
        return (s) => vec([s.sampleRate]);
      case 'progress':
        return (s) => vec([s.progress]);
      case 'ratio':
        return (s) => vec([s.ratio]);
      case 'iChannelTime':
        return (s) => gl.uniform1fv(loc, new Float32Array(size).fill(s.time));
      case 'iChannelResolution':
        return (s) => {
          const a = new Float32Array(size * 3);
          for (let k = 0; k < size; k++) a.set([s.w, s.h, 1], k * 3);
          gl.uniform3fv(loc, a);
        };
      default:
        return null; // unknown uniform keeps its GLSL default (0)
    }
  }

  // ------------------------------------------------------------------ assets

  private loadAsset(input: PassInput, baseUrl: string): Promise<WebGLTexture> {
    const key = `${input.type}:${input.ref}:${input.sampler.filter}:${input.sampler.wrap}:${input.sampler.vflip}`;
    let p = this.assetCache.get(key);
    if (!p) {
      p = input.type === 'cubemap' ? this.loadCube(input, baseUrl) : this.loadTexture(input, baseUrl);
      p.catch(() => this.assetCache.delete(key));
      this.assetCache.set(key, p);
    }
    return p;
  }

  private async bitmap(url: string, flip: boolean): Promise<ImageBitmap> {
    const blob = await (await fetch(url)).blob();
    return createImageBitmap(blob, { imageOrientation: flip ? 'flipY' : 'from-image' });
  }

  private async loadTexture(input: PassInput, baseUrl: string): Promise<WebGLTexture> {
    const gl = this.gl;
    const bmp = await this.bitmap(`${baseUrl}/${input.src}`, input.sampler.vflip);
    const tex = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, bmp);
    bmp.close();
    const wrap = input.sampler.wrap === 'repeat' ? gl.REPEAT : gl.CLAMP_TO_EDGE;
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
    if (input.sampler.filter === 'mipmap') {
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    } else {
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, input.sampler.filter === 'nearest' ? gl.NEAREST : gl.LINEAR);
    }
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, input.sampler.filter === 'nearest' ? gl.NEAREST : gl.LINEAR);
    return tex;
  }

  private async loadCube(input: PassInput, baseUrl: string): Promise<WebGLTexture> {
    const gl = this.gl;
    const faces = ['px', 'nx', 'py', 'ny', 'pz', 'nz'];
    const bmps = await Promise.all(faces.map((f) => this.bitmap(`${baseUrl}/${input.src}/${f}.jpg`, input.sampler.vflip)));
    const tex = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, tex);
    bmps.forEach((b, i) => {
      gl.texImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, b);
      b.close();
    });
    gl.generateMipmap(gl.TEXTURE_CUBE_MAP);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    return tex;
  }

  private makeTex2D(w: number, h: number, ifmt: number, fmt: number, type: number, filter: number, wrap: number): WebGLTexture {
    const gl = this.gl;
    const tex = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, ifmt, w, h, 0, fmt, type, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
    return tex;
  }

  // ------------------------------------------------------------------ buffers

  private ensureBuffers(inst: Instance, w: number, h: number): void {
    if (inst.bw === w && inst.bh === h && inst.buffers.size) return;
    this.freeBuffers(inst);
    const gl = this.gl;
    const ifmt = this.floatBuffers ? gl.RGBA16F : gl.RGBA8;
    const type = this.floatBuffers ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE;
    for (const cp of inst.passes) {
      if (cp.pass.type !== 'buffer' || !cp.pass.id) continue;
      const mk = () => {
        const tex = this.makeTex2D(w, h, ifmt, gl.RGBA, type, gl.LINEAR, gl.CLAMP_TO_EDGE);
        const fbo = gl.createFramebuffer()!;
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        return { tex, fbo };
      };
      const a = mk();
      const b = mk();
      inst.buffers.set(cp.pass.id, { tex: [a.tex, b.tex], fbo: [a.fbo, b.fbo], read: 0 });
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    inst.bw = w;
    inst.bh = h;
  }

  private freeBuffers(inst: Instance): void {
    const gl = this.gl;
    inst.buffers.forEach((pp) => {
      pp.tex.forEach((t) => gl.deleteTexture(t));
      pp.fbo.forEach((f) => gl.deleteFramebuffer(f));
    });
    inst.buffers.clear();
    inst.bw = inst.bh = 0;
  }

  // ------------------------------------------------------------------ playback

  play(inst: Instance, onFirstFrame?: () => void): void {
    this.stop();
    this.current = inst;
    this.freeBuffers(inst); // every showing starts from clean feedback buffers
    this.frame = 0;
    this.t0 = this.last = performance.now();
    this.mouse = [0, 0, 0, 0];
    this.onFirstFrame = onFirstFrame ?? null;
    // Clips only roll while a transition is on screen; leaving two videos
    // decoding behind every other card is wasted battery.
    if (inst.isTransition) this.demoSources?.play();
    else this.demoSources?.pause();
    const loop = (now: number) => {
      this.raf = requestAnimationFrame(loop);
      this.render(now);
    };
    this.raf = requestAnimationFrame(loop);
  }

  stop(): void {
    cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.current = null;
    this.onFirstFrame = null;
    this.demoSources?.pause();
  }

  get playing(): boolean {
    return !!this.current;
  }

  /** Copies the current frame (for drag ghosts). Renders synchronously so the buffer is valid. */
  snapshot(maxW = 240): HTMLCanvasElement | null {
    if (!this.current) return null;
    this.render(performance.now());
    const c = document.createElement('canvas');
    const r = this.canvas.height / this.canvas.width;
    c.width = maxW;
    c.height = Math.round(maxW * r);
    c.getContext('2d')!.drawImage(this.canvas, 0, 0, c.width, c.height);
    return c;
  }

  private pointer(e: PointerEvent, down: boolean): void {
    const r = this.canvas.getBoundingClientRect();
    const x = ((e.clientX - r.left) / r.width) * this.canvas.width;
    const y = (1 - (e.clientY - r.top) / r.height) * this.canvas.height;
    if (down) this.mouse = [x, y, x, y];
    else if (e.buttons & 1) {
      this.mouse[0] = x;
      this.mouse[1] = y;
    }
  }

  private resize(): [number, number] {
    const c = this.canvas;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let w = Math.max(1, Math.round(c.clientWidth * dpr));
    let h = Math.max(1, Math.round(c.clientHeight * dpr));
    const k = Math.sqrt(this.maxPixels / (w * h));
    if (k < 1) {
      w = Math.round(w * k);
      h = Math.round(h * k);
    }
    if (c.width !== w || c.height !== h) {
      c.width = w;
      c.height = h;
    }
    return [w, h];
  }

  private render(now: number): void {
    const inst = this.current;
    if (!inst) return;
    const gl = this.gl;
    const [w, h] = this.resize();
    this.ensureBuffers(inst, w, h);

    gl.bindTexture(gl.TEXTURE_2D, this.audioTex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, AUDIO_W, AUDIO_H, gl.RED, gl.UNSIGNED_BYTE, this.audio.update());

    const d = new Date();
    const dt = Math.min(0.1, (now - this.last) / 1000);
    this.fps = this.fps * 0.9 + (dt > 0 ? 1 / dt : 0) * 0.1;
    this.last = now;
    const state: FrameState = {
      time: (now - this.t0) / 1000,
      dt,
      frame: this.frame,
      w,
      h,
      mouse: this.mouse,
      date: [d.getFullYear(), d.getMonth(), d.getDate(), d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + d.getMilliseconds() / 1000],
      sampleRate: this.audio.sampleRate,
      progress: 0,
      ratio: 16 / 9,
    };

    if (inst.isTransition && this.demoSources) {
      this.demoSources.update();
      state.progress = loopProgress(state.time);
      state.ratio = this.demoSources.aspect();
    }

    gl.bindVertexArray(this.vao);
    for (const cp of inst.passes) {
      const isBuffer = cp.pass.type === 'buffer' && cp.pass.id;
      const pp = isBuffer ? inst.buffers.get(cp.pass.id!) : undefined;
      gl.bindFramebuffer(gl.FRAMEBUFFER, pp ? pp.fbo[1 - pp.read] : null);
      gl.viewport(0, 0, w, h);
      gl.useProgram(cp.program);
      for (const s of cp.setters) s(state);
      for (const sb of cp.samplers) {
        gl.activeTexture(gl.TEXTURE0 + sb.unit);
        const target = sb.isCube ? gl.TEXTURE_CUBE_MAP : gl.TEXTURE_2D;
        gl.bindTexture(target, this.textureFor(sb, inst));
        gl.uniform1i(sb.loc, sb.unit);
      }
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (pp) pp.read = (1 - pp.read) as 0 | 1;
    }
    gl.activeTexture(gl.TEXTURE0);
    this.frame++;
    if (this.onFirstFrame) {
      const cb = this.onFirstFrame;
      this.onFirstFrame = null;
      cb();
    }
  }

  private textureFor(sb: SamplerBinding, inst: Instance): WebGLTexture {
    const i = sb.input;
    const fallback = sb.isCube ? this.blackCube : this.black2D;
    if (sb.role === 'from' || sb.role === 'to') {
      const t = this.demoSources?.texture(sb.role === 'from' ? 0 : 1);
      return t ?? fallback;
    }
    if (!i) return fallback;
    switch (i.type) {
      case 'music':
      case 'mic':
        return sb.isCube ? fallback : this.audioTex;
      case 'buffer': {
        const pp = inst.buffers.get(i.ref as BufferId);
        return pp && !sb.isCube ? pp.tex[pp.read] : fallback;
      }
      case 'texture':
      case 'cubemap':
        return (i.ref && inst.assets.get(i.ref)) || fallback;
      default:
        return fallback;
    }
  }
}
