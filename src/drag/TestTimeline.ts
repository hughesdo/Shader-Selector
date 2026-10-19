import { readDrag, SHADER_MIME, type ShaderDragPayload } from './drag';

/**
 * Throwaway drop target that proves the drag contract works.
 * Your real timelines replace this; they only need readDrag().
 */
export class TestTimeline {
  readonly el: HTMLElement;
  private lane: HTMLElement;
  private log: HTMLElement;
  private clips: ShaderDragPayload[] = [];

  constructor(parent: HTMLElement, private onPick: (id: string) => void) {
    this.el = document.createElement('section');
    this.el.className = 'timeline';
    this.el.innerHTML = `
      <header><b>Test timeline</b><span class="hint">drag the center card here</span>
        <button class="ghost-btn" data-act="clear">clear</button></header>
      <div class="lane"><span class="lane-empty">drop zone</span></div>
      <pre class="drop-log"></pre>`;
    this.lane = this.el.querySelector('.lane')!;
    this.log = this.el.querySelector('.drop-log')!;
    parent.appendChild(this.el);

    this.el.querySelector('[data-act=clear]')!.addEventListener('click', () => {
      this.clips = [];
      this.render();
      this.log.textContent = '';
    });

    const accepts = (e: DragEvent) => !!e.dataTransfer && Array.from(e.dataTransfer.types).includes(SHADER_MIME);
    this.lane.addEventListener('dragenter', (e) => {
      if (accepts(e)) {
        e.preventDefault();
        this.lane.classList.add('over');
      }
    });
    this.lane.addEventListener('dragover', (e) => {
      if (accepts(e)) {
        e.preventDefault();
        e.dataTransfer!.dropEffect = 'copy';
      }
    });
    this.lane.addEventListener('dragleave', (e) => {
      if (!this.lane.contains(e.relatedTarget as Node)) this.lane.classList.remove('over');
    });
    this.lane.addEventListener('drop', (e) => {
      e.preventDefault();
      this.lane.classList.remove('over');
      const p = e.dataTransfer && readDrag(e.dataTransfer);
      if (!p) return;
      this.clips.push(p);
      this.render();
      this.log.textContent = `received ${new Date().toLocaleTimeString()}\n${JSON.stringify(p, null, 2)}`;
    });
  }

  private render(): void {
    if (!this.clips.length) {
      this.lane.innerHTML = '<span class="lane-empty">drop zone</span>';
      return;
    }
    this.lane.innerHTML = '';
    this.clips.forEach((c) => {
      const d = document.createElement('button');
      d.className = 'clip';
      d.title = `${c.name} by ${c.user}\nclick to find it in the selector`;
      const img = document.createElement('img');
      img.src = c.thumbUrl;
      img.alt = '';
      const label = document.createElement('span');
      label.textContent = c.name;
      d.append(img, label);
      d.addEventListener('click', () => this.onPick(c.id));
      this.lane.appendChild(d);
    });
    this.lane.scrollLeft = this.lane.scrollWidth;
  }
}
