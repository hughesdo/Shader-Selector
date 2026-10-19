import type { IndexEntry, LibraryManifest, ShaderDoc } from './schema';

/** A shader doc with every pass's code resolved (codeFile -> code). */
export interface ResolvedShader {
  entry: IndexEntry;
  doc: ShaderDoc;
  baseUrl: string;   // library root, for asset src paths
  dirUrl: string;    // this shader's folder
}

/**
 * Reads the paged index and fetches individual shaders on demand.
 * The carousel only ever touches IndexEntry rows + thumbnails; shader.json and
 * .glsl files are fetched only when a shader is about to compile.
 */
export class Library {
  readonly entries: IndexEntry[] = [];
  private docCache = new Map<string, Promise<ResolvedShader>>();
  private readonly maxDocs = 64;

  constructor(readonly root: string) {}

  url(rel: string): string {
    return `${this.root.replace(/\/$/, '')}/${rel}`;
  }

  thumbUrl(e: IndexEntry): string {
    return this.url(`${e.dir}/${e.thumb}`);
  }

  stillUrl(e: IndexEntry): string {
    return this.url(`${e.dir}/${e.still}`);
  }

  /**
   * Loads the manifest, then pages in order. `onPage` fires after each page so
   * the UI can show the first few hundred shaders while the rest stream in.
   */
  async load(onPage?: (entries: IndexEntry[]) => void): Promise<void> {
    const manifest = (await (await fetch(this.url('index/manifest.json'))).json()) as LibraryManifest;
    for (const page of manifest.pages) {
      const rows = (await (await fetch(this.url(`index/${page}`))).json()) as IndexEntry[];
      this.entries.push(...rows);
      onPage?.(this.entries);
    }
  }

  get(entry: IndexEntry): Promise<ResolvedShader> {
    const hit = this.docCache.get(entry.id);
    if (hit) {
      // refresh LRU position
      this.docCache.delete(entry.id);
      this.docCache.set(entry.id, hit);
      return hit;
    }
    const p = this.fetchShader(entry);
    p.catch(() => this.docCache.delete(entry.id));
    this.docCache.set(entry.id, p);
    while (this.docCache.size > this.maxDocs) {
      this.docCache.delete(this.docCache.keys().next().value as string);
    }
    return p;
  }

  private async fetchShader(entry: IndexEntry): Promise<ResolvedShader> {
    const dirUrl = this.url(entry.dir);
    const res = await fetch(`${dirUrl}/shader.json`);
    if (!res.ok) throw new Error(`shader.json ${res.status} for ${entry.id}`);
    const doc = (await res.json()) as ShaderDoc;
    await Promise.all(
      doc.renderpass.map(async (p) => {
        if (p.code == null && p.codeFile) {
          const r = await fetch(`${dirUrl}/${p.codeFile}`);
          if (!r.ok) throw new Error(`${p.codeFile} ${r.status} for ${entry.id}`);
          p.code = await r.text();
        }
      }),
    );
    return { entry, doc, baseUrl: this.root, dirUrl };
  }
}
