/**
 * Shader library schema ("shaderlib/1").
 *
 * Modeled on Shadertoy's export JSON (info + renderpass[] with inputs/outputs),
 * with two deliberate differences:
 *   1. Pass code lives in sibling .glsl files (codeFile) so it diffs and edits cleanly.
 *      Inline `code` is still accepted, so a raw Shadertoy export can be dropped in.
 *   2. `dialect` says how the code is written, so one library can hold both
 *      Shadertoy-style mainImage() code and full standalone GLSL programs (OneOffRender style).
 *
 * On-disk layout (see tools/import_oneoffrender.py, tools/import_shadertoy.py):
 *   library/index/manifest.json        -> LibraryManifest
 *   library/index/page-0000.json       -> IndexEntry[]  (pageSize entries per page)
 *   library/shaders/ab/cd/<id>/        -> shader.json, *.glsl, thumb.webp, still.webp
 *   library/transitions/<name>/        -> same files, flat: only ~100 of them ever
 *   library/demo/                      -> the two clips every transition card morphs between
 *   library/assets/tex/ab/<hash>.<ext> -> textures, stored once, referenced by hash
 *   library/assets/cube/ab/<hash>/     -> px,nx,py,ny,pz,nz faces
 * "ab/cd" is the first 4 hex chars of sha1(id), so no folder ever gets fat,
 * even at hundreds of thousands of shaders.
 *
 * Transitions live in their own folder but share ONE index with everything else,
 * so the carousel, search and filters need no second code path. `kind` separates them.
 *
 * v2 added `kind`, `category` and `params`. All three are optional and have
 * derivation rules (kindOf / categoryOf), so documents written before v2 load unchanged.
 */

export type Dialect =
  /** Shadertoy style: body defines mainImage(out vec4, in vec2). Host injects uniforms + main(). */
  | 'shadertoy'
  /** Complete fragment program with its own #version, uniforms, out var and main(). */
  | 'glsl-full'
  /**
   * gl-transitions style: declares `uniform sampler2D from, to; uniform float progress;
   * uniform vec2 resolution;` plus optional parameters, and defines
   * `vec4 transition(vec2 uv)`. Usually ships its own #version 330 and main(),
   * but a few omit the #version line, so the host supplies one when missing.
   */
  | 'gl-transition';

/**
 * What the shader IS, structurally. This decides how a host can use it, so it is
 * separate from `category`, which is only how the user browses.
 *
 *  standalone - draws a full frame from nothing. The default.
 *  transition - blends two sources over `progress`. Needs from/to bound.
 *  effect     - modifies one incoming frame. Needs a source bound.
 *
 * A host that cannot bind the required sources must not offer the shader.
 */
export type ShaderKind = 'standalone' | 'transition' | 'effect';

/**
 * How the shader is filed for browsing. One value per shader, picked at import.
 * `audio-reactive`, `cubemap`, `effect` and `transition` are derivable from the
 * data, `generative` is the fallback and `3d-scene` is a human judgement call.
 */
export type Category =
  | 'audio-reactive'
  | 'generative'
  | '3d-scene'
  | 'cubemap'
  | 'effect'
  | 'transition';

export const CATEGORY_LABELS: Record<Category, string> = {
  'audio-reactive': 'Audio Reactive',
  'generative': 'Generative',
  '3d-scene': '3D Scene',
  'cubemap': 'CubeMaps',
  'effect': 'Effects',
  'transition': 'Transitions',
};

/** Dropdown order, with All handled separately by the UI. */
export const CATEGORY_ORDER: Category[] = [
  'audio-reactive', 'generative', '3d-scene', 'cubemap', 'effect', 'transition',
];

export type PassType = 'image' | 'buffer' | 'common' | 'cubemap' | 'sound';
export type BufferId = 'A' | 'B' | 'C' | 'D';

/** Same ctype vocabulary Shadertoy uses. */
export type InputType =
  | 'music'      // the app's currently selected audio track (512x256 FFT+wave texture)
  | 'mic'
  | 'buffer'     // ref = 'A'..'D'
  | 'texture'    // ref = asset hash, src = asset path
  | 'cubemap'    // ref = asset hash, src = folder holding 6 faces
  | 'keyboard'
  | 'video'
  | 'webcam'
  | 'volume';

export interface Sampler {
  filter: 'nearest' | 'linear' | 'mipmap';
  wrap: 'clamp' | 'repeat';
  vflip: boolean;
}

export interface PassInput {
  /** iChannel index 0..3. */
  channel: number;
  /** Optional explicit uniform name for non-iChannel samplers (e.g. "iAudioData"). */
  uniform?: string;
  type: InputType;
  ref?: string;
  /** Path relative to library root, for textures/cubemaps. */
  src?: string;
  sampler: Sampler;
}

export interface RenderPass {
  type: PassType;
  name: string;               // "Image", "Buffer A", "Common"...
  id?: BufferId;              // buffers only
  codeFile?: string;          // relative to the shader folder
  code?: string;              // inline alternative (Shadertoy export style)
  inputs: PassInput[];
}

/**
 * A tunable a gl-transition declares, e.g. `uniform float strength; // = 0.4`.
 * Values come from OneOffRender's Transitions_Metadata.json where available,
 * otherwise from the default in the header comment.
 */
export type ParamValue = number | boolean | number[];

export interface ShaderInfo {
  id: string;
  name: string;
  username: string;
  description: string;
  tags: string[];
  date?: number;
  license?: string;
  source?: {
    kind: 'shadertoy' | 'oneoffrender' | 'gl-transitions' | 'original';
    url?: string;
    file?: string;
  };
  stars?: number;
  audio: { reactive: boolean };
  preview: { thumb: string; still: string };
}

export interface ShaderDoc {
  schema: 'shaderlib/1';
  dialect: Dialect;
  /** Defaults to 'standalone' when absent, so shaderlib/1 docs written before v2 still load. */
  kind?: ShaderKind;
  /** Defaults to audio-reactive or generative when absent, derived from info.audio. */
  category?: Category;
  /** Uniform values for a transition or effect. Ignored for standalone shaders. */
  params?: Record<string, ParamValue>;
  info: ShaderInfo;
  renderpass: RenderPass[];
}

/** Fallbacks for docs written before kind/category existed. */
export function kindOf(doc: ShaderDoc): ShaderKind {
  return doc.kind ?? 'standalone';
}

export function categoryOf(doc: ShaderDoc): Category {
  if (doc.category) return doc.category;
  const k = kindOf(doc);
  if (k === 'transition') return 'transition';
  if (k === 'effect') return 'effect';
  return doc.info.audio.reactive ? 'audio-reactive' : 'generative';
}

/** Lightweight row in the paged index. Everything the carousel needs, nothing more. */
export interface IndexEntry {
  id: string;
  name: string;
  user: string;
  /** Where the shader came from (info.source.url), when known. */
  url?: string;
  /** Shader folder, relative to library root. */
  dir: string;
  thumb: string;   // relative to dir
  still: string;   // relative to dir
  stars: number;
  audio: boolean;
  passes: number;
  /** Absent means 'standalone' (rows written before v2). */
  kind?: ShaderKind;
  /** Absent means derive from audio, same rule as categoryOf. */
  category?: Category;
  /** Requirement flags so a UI can filter/badge without opening shader.json. */
  needs: Array<'buffer' | 'texture' | 'cubemap' | 'common' | 'music'>;
  tags: string[];
}

/** Same fallbacks as kindOf/categoryOf, for the lightweight index rows. */
export function entryKind(e: IndexEntry): ShaderKind {
  return e.kind ?? 'standalone';
}

export function entryCategory(e: IndexEntry): Category {
  if (e.category) return e.category;
  const k = entryKind(e);
  if (k === 'transition') return 'transition';
  if (k === 'effect') return 'effect';
  return e.audio ? 'audio-reactive' : 'generative';
}

export interface LibraryManifest {
  schema: 'shaderlib-index/1';
  count: number;
  pageSize: number;
  pages: string[];   // relative to index/
  generated: string;
}
