import type { Library } from './library/Library';
import { CompileError, type ShaderRenderer } from './render/ShaderRenderer';

/**
 * Open the app with ?selftest to compile + render every shader in the library.
 * Results land on window.__selftest and in the console. tools/selftest.py drives this headless.
 */
export interface SelfTestResult {
  id: string;
  name: string;
  ok: boolean;
  ms: number;
  glError: number;
  brightness: number; // mean luma of a frame rendered with silence, 0..255
  error?: string;
}

const frames = (n: number) =>
  new Promise<void>((r) => {
    const f = () => (--n <= 0 ? r() : requestAnimationFrame(f));
    requestAnimationFrame(f);
  });

export async function run(library: Library, renderer: ShaderRenderer): Promise<void> {
  const out: { done: boolean; results: SelfTestResult[] } = { done: false, results: [] };
  (window as unknown as { __selftest: typeof out }).__selftest = out;
  while (!library.entries.length) await frames(5);
  await frames(30);

  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;left:0;top:0;width:320px;height:180px;z-index:99999';
  document.body.appendChild(host);
  const gl = renderer.gl;

  for (const e of library.entries.slice()) {
    const r: SelfTestResult = { id: e.id, name: e.name, ok: false, ms: 0, glError: 0, brightness: 0 };
    try {
      const rs = await library.get(e);
      const inst = await renderer.prepare(rs);
      r.ms = Math.round(inst.compileMs);
      host.appendChild(renderer.canvas);
      gl.getError();
      renderer.play(inst);
      await frames(4);
      r.glError = gl.getError();
      // sample a frame synchronously
      renderer.snapshot();
      const cw = renderer.canvas.width, ch = renderer.canvas.height;
      const px = new Uint8Array(cw * ch * 4);
      gl.readPixels(0, 0, cw, ch, gl.RGBA, gl.UNSIGNED_BYTE, px);
      let s = 0;
      for (let i = 0; i < px.length; i += 4) s += 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      r.brightness = Math.round(s / (cw * ch));
      renderer.stop();
      r.ok = r.glError === 0;
      if (!r.ok) r.error = `gl error 0x${r.glError.toString(16)}`;
    } catch (err) {
      r.error = err instanceof CompileError ? err.log.slice(0, 600) : String(err);
      renderer.stop();
    }
    out.results.push(r);
    console.log(`[selftest] ${r.ok ? 'ok  ' : 'FAIL'} ${r.id} ${r.ms}ms lum=${r.brightness}${r.error ? ' :: ' + r.error.split('\n')[1] : ''}`);
  }
  out.done = true;
  host.remove();
}

/**
 * ?tools mode: lets tools/render_previews.py ask the app to render a shader for a
 * few seconds and hand back a frame, so shaders without preview art get one.
 */
export function installTools(library: Library, renderer: ShaderRenderer, playTrack: (id: string) => Promise<void>): void {
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;left:0;top:0;width:960px;height:540px;z-index:99999;background:#000';
  (window as unknown as Record<string, unknown>).__tools = {
    async preview(id: string, seconds = 3, track = 'bass'): Promise<string> {
      while (!library.entries.length) await frames(5);
      const e = library.entries.find((x) => x.id === id);
      if (!e) throw new Error(`no entry ${id}`);
      await playTrack(track);
      document.body.appendChild(host);
      const inst = await renderer.prepare(await library.get(e));
      host.appendChild(renderer.canvas);
      renderer.canvas.classList.add('visible');
      renderer.play(inst);
      await new Promise((r) => setTimeout(r, seconds * 1000));
      const snap = renderer.snapshot(960)!;
      renderer.stop();
      host.remove();
      return snap.toDataURL('image/png');
    },
  };
}
