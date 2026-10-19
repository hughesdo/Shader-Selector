import type { IndexEntry } from '../library/schema';

/**
 * Drag contract between the selector and any drop target (your timelines later).
 * Targets should look for SHADER_MIME first and fall back to text/uri-list.
 */
export const SHADER_MIME = 'application/x-shaderlib+json';

export interface ShaderDragPayload {
  schema: 'shaderlib-drag/1';
  id: string;
  name: string;
  user: string;
  /** Absolute URLs so a target in another app/origin can fetch everything it needs. */
  shaderUrl: string;
  libraryRoot: string;
  thumbUrl: string;
  stillUrl: string;
  needs: IndexEntry['needs'];
  audio: boolean;
  passes: number;
}

export function makePayload(e: IndexEntry, libraryRoot: string): ShaderDragPayload {
  const root = new URL(libraryRoot.replace(/\/?$/, '/'), location.href).href;
  const dir = new URL(`${e.dir}/`, root).href;
  return {
    schema: 'shaderlib-drag/1',
    id: e.id,
    name: e.name,
    user: e.user,
    shaderUrl: `${dir}shader.json`,
    libraryRoot: root,
    thumbUrl: `${dir}${e.thumb}`,
    stillUrl: `${dir}${e.still}`,
    needs: e.needs,
    audio: e.audio,
    passes: e.passes,
  };
}

export function writeDrag(dt: DataTransfer, p: ShaderDragPayload): void {
  dt.effectAllowed = 'copy';
  dt.setData(SHADER_MIME, JSON.stringify(p));
  dt.setData('text/uri-list', p.shaderUrl);
  dt.setData('text/plain', `${p.name} (${p.id})`);
}

export function readDrag(dt: DataTransfer): ShaderDragPayload | null {
  const raw = dt.getData(SHADER_MIME);
  if (!raw) return null;
  try {
    const p = JSON.parse(raw) as ShaderDragPayload;
    return p.schema === 'shaderlib-drag/1' ? p : null;
  } catch {
    return null;
  }
}

/**
 * Builds the ghost image shown under the cursor: the live frame if the shader is
 * playing, otherwise the still. Must be in the DOM at dragstart, removed right after.
 */
export function setGhost(dt: DataTransfer, source: HTMLCanvasElement | HTMLImageElement, label: string): void {
  const wrap = document.createElement('div');
  wrap.className = 'drag-ghost';
  const w = 220;
  const h = Math.round(w * 9 / 16);
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const g = c.getContext('2d')!;
  try {
    g.drawImage(source, 0, 0, w, h);
  } catch {
    g.fillStyle = '#222';
    g.fillRect(0, 0, w, h);
  }
  wrap.appendChild(c);
  const s = document.createElement('span');
  s.textContent = label;
  wrap.appendChild(s);
  document.body.appendChild(wrap);
  dt.setDragImage(wrap, w / 2, h / 2);
  setTimeout(() => wrap.remove(), 0);
}
