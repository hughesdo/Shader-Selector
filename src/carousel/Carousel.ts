import { entryKind, type IndexEntry } from '../library/schema';

/**
 * Virtualized coverflow.
 *
 * Only (2 * RADIUS + 1) card elements ever exist, whatever the library size.
 * Each frame, slot i shows entry (i mod n) at offset o = i - pos, where pos is a
 * float driven by a critically damped spring toward an integer target. Side cards
 * sit rotated ~70 degrees on Y like thin picture frames; as |o| goes 1 -> 0 the
 * card swings flat into the center, which is the "flip out" motion.
 */
export interface CarouselHooks {
  thumbUrl(e: IndexEntry): string;
  stillUrl(e: IndexEntry): string;
  /** Pos started moving away from a resting index. */
  onMove?(): void;
  /** Came to rest. The card element stays valid until the next onMove. */
  onSettle?(entry: IndexEntry, card: CardEl, index: number): void;
  /** Center index changed (fires continuously while flipping, cheap). */
  onCenter?(entry: IndexEntry, index: number): void;
}

export interface CardEl extends HTMLDivElement {
  _index: number;     // unwrapped slot index currently bound
  _entryId: string;
  _img: HTMLImageElement;
  _name: HTMLElement;
  _by: HTMLElement;
  _badges: HTMLElement;
}

const RADIUS = 7;
const STIFFNESS = 220;
const DAMPING = 2 * Math.sqrt(STIFFNESS);

export class Carousel {
  readonly el: HTMLDivElement;
  private track: HTMLDivElement;
  private cards: CardEl[] = [];
  private items: IndexEntry[] = [];
  private pos = 0;
  private vel = 0;
  private target = 0;
  private raf = 0;
  private last = 0;
  private settled = false;
  private lastCenter = -1;
  private cw = 440; // card width in px, from CSS var
  private dragging: { x0: number; t0: number; target0: number; lastX: number; lastT: number; v: number } | null = null;
  private wheelAcc = 0;
  private keyRepeat = 0;

  constructor(parent: HTMLElement, private hooks: CarouselHooks) {
    this.el = document.createElement('div');
    this.el.className = 'carousel';
    this.el.tabIndex = 0;
    this.track = document.createElement('div');
    this.track.className = 'carousel-track';
    this.el.appendChild(this.track);
    parent.appendChild(this.el);

    for (let i = 0; i < RADIUS * 2 + 1; i++) this.cards.push(this.makeCard());
    this.bindInput();
    new ResizeObserver(() => this.measure()).observe(this.el);
    this.measure();
  }

  // ------------------------------------------------------------- public API

  get count(): number {
    return this.items.length;
  }

  get index(): number {
    return this.wrap(Math.round(this.target));
  }

  get isSettled(): boolean {
    return this.settled;
  }

  get centerCard(): CardEl | undefined {
    const i = Math.round(this.pos);
    return this.cards.find((c) => c._index === i);
  }

  setItems(items: IndexEntry[], keepId?: string): void {
    this.items = items;
    const keep = keepId ? items.findIndex((e) => e.id === keepId) : -1;
    this.pos = this.target = Math.max(0, keep);
    this.vel = 0;
    this.cards.forEach((c) => ((c._index = NaN), (c._entryId = '')));
    this.lastCenter = -1;
    this.settled = false;
    this.kick();
  }

  /** Append more rows (paged index streaming in) without moving. */
  appendItems(items: IndexEntry[]): void {
    this.items = items;
    this.cards.forEach((c) => (c._index = NaN));
    this.kick();
  }

  step(n: number): void {
    if (!this.items.length) return;
    this.target = this.clampTarget(Math.round(this.target) + n);
    this.kick();
  }

  goTo(index: number, instant = false): void {
    if (!this.items.length) return;
    const cur = Math.round(this.target);
    let d = index - this.wrap(cur);
    if (this.wraps) {
      const n = this.items.length;
      if (d > n / 2) d -= n;
      if (d < -n / 2) d += n;
    }
    this.target = this.clampTarget(cur + d);
    if (instant) {
      this.pos = this.target;
      this.vel = 0;
    }
    this.kick();
  }

  goToId(id: string): void {
    const i = this.items.findIndex((e) => e.id === id);
    if (i >= 0) this.goTo(i);
  }

  // ------------------------------------------------------------- internals

  private get wraps(): boolean {
    return this.items.length > RADIUS * 2 + 1;
  }

  private wrap(i: number): number {
    const n = this.items.length || 1;
    return ((i % n) + n) % n;
  }

  private clampTarget(t: number): number {
    return this.wraps ? t : Math.max(0, Math.min(this.items.length - 1, t));
  }

  private measure(): void {
    const v = getComputedStyle(this.el).getPropertyValue('--card-w');
    this.cw = parseFloat(v) || this.el.clientWidth * 0.32;
    this.layout();
  }

  private makeCard(): CardEl {
    const c = document.createElement('div') as CardEl;
    c.className = 'card';
    c.innerHTML = `
      <div class="card-media"><img alt="" decoding="async" draggable="false"></div>
      <div class="card-shade"></div>
      <div class="card-status"><div class="dwell-bar"></div><span class="status-text"></span></div>
      <div class="card-badges"></div>
      <div class="card-cap"><span class="card-name"></span><span class="card-by"></span></div>`;
    c._img = c.querySelector('img')!;
    c._name = c.querySelector('.card-name')!;
    c._by = c.querySelector('.card-by')!;
    c._badges = c.querySelector('.card-badges')!;
    c._index = NaN;
    c._entryId = '';
    this.track.appendChild(c);
    return c;
  }

  private bind(card: CardEl, slot: number): void {
    card._index = slot;
    const e = this.items[this.wrap(slot)];
    if (card._entryId === e.id) return;
    card._entryId = e.id;
    card.dataset.state = '';
    card.classList.remove('has-still');
    card._img.src = this.hooks.thumbUrl(e);
    card._name.textContent = e.name;
    card._by.textContent = '';
    if (e.url) {
      const a = document.createElement('a');
      a.href = e.url;
      a.target = '_blank';
      a.rel = 'noopener';
      a.draggable = false;
      a.title = e.url;
      a.textContent = `${e.user} ↗`;
      card._by.appendChild(a);
    } else {
      card._by.textContent = e.user;
    }
    const b: string[] = [];
    if (e.audio) b.push('<i title="audio reactive">♪</i>');
    if (e.needs.includes('buffer')) b.push(`<i title="${e.passes} passes">${e.passes}P</i>`);
    if (e.needs.includes('texture')) b.push('<i title="uses textures">TEX</i>');
    if (e.needs.includes('cubemap')) b.push('<i title="uses a cubemap">CUBE</i>');
    if (entryKind(e) === 'transition') b.push('<i title="transition">TRN</i>');
    card._badges.innerHTML = b.join('');
    // drop any live canvas a recycled card might still hold
    card.querySelector('.card-media canvas')?.remove();
  }

  /** Upgrades the centered card from thumb to the sharper still once it is decoded. */
  private upgradeStill(card: CardEl, e: IndexEntry): void {
    const url = this.hooks.stillUrl(e);
    const img = new Image();
    img.decoding = 'async';
    img.src = url;
    img.decode().then(
      () => {
        if (card._entryId === e.id) {
          card._img.src = url;
          card.classList.add('has-still');
        }
      },
      () => {},
    );
  }

  private prefetch(center: number, dir: number): void {
    // thumbs a little past the visible window, biased in the scroll direction
    const ahead = dir >= 0 ? 1 : -1;
    for (let k = RADIUS + 1; k <= RADIUS + 10; k++) {
      const slot = center + k * ahead;
      if (!this.wraps && (slot < 0 || slot >= this.items.length)) continue;
      const img = new Image();
      img.src = this.hooks.thumbUrl(this.items[this.wrap(slot)]);
    }
  }

  private kick(): void {
    if (this.settled && Math.abs(this.target - this.pos) > 1e-4) {
      this.settled = false;
      this.hooks.onMove?.();
    }
    if (!this.raf) {
      this.last = performance.now();
      this.raf = requestAnimationFrame(this.tick);
    }
  }

  private tick = (now: number): void => {
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    if (!this.dragging) {
      // semi-implicit Euler on a critically damped spring
      const a = -STIFFNESS * (this.pos - this.target) - DAMPING * this.vel;
      this.vel += a * dt;
      this.pos += this.vel * dt;
    }
    this.layout();

    const done = !this.dragging && Math.abs(this.target - this.pos) < 0.002 && Math.abs(this.vel) < 0.02;
    if (done) {
      this.pos = this.target;
      this.vel = 0;
      this.layout();
      this.raf = 0;
      if (!this.settled && this.items.length) {
        this.settled = true;
        const card = this.centerCard!;
        // layout() above ran while still "moving"; flip the settled-only bits now
        this.el.classList.remove('is-moving');
        card.draggable = true;
        const idx = this.wrap(this.target);
        const e = this.items[idx];
        this.upgradeStill(card, e);
        this.hooks.onSettle?.(e, card, idx);
      }
      return;
    }
    this.raf = requestAnimationFrame(this.tick);
  };

  private layout(): void {
    const n = this.items.length;
    const centerSlot = Math.round(this.pos);
    if (n && centerSlot !== this.lastCenter) {
      const dir = Math.sign(centerSlot - this.lastCenter);
      this.lastCenter = centerSlot;
      const idx = this.wrap(centerSlot);
      this.hooks.onCenter?.(this.items[idx], idx);
      this.prefetch(centerSlot, dir);
    }
    this.el.classList.toggle('is-moving', !this.settled);
    const cw = this.cw;
    const first = cw * 0.64;
    const spacing = cw * 0.19;
    const size = this.cards.length;
    for (let k = -RADIUS; k <= RADIUS; k++) {
      const slot = centerSlot + k;
      const card = this.cards[((slot % size) + size) % size];
      const visible = n > 0 && (this.wraps || (slot >= 0 && slot < n));
      if (!visible) {
        card.style.visibility = 'hidden';
        card._index = NaN;
        continue;
      }
      if (card._index !== slot) this.bind(card, slot);
      const o = slot - this.pos;
      const ao = Math.abs(o);
      const s = Math.sign(o);
      const a = Math.min(1, ao);
      const far = Math.max(0, ao - 1);
      const x = s * (a * first + far * spacing);
      const rot = -s * a * 72;
      const z = -a * cw * 0.42 - far * cw * 0.03;
      card.style.visibility = 'visible';
      card.style.transform = `translate3d(${x.toFixed(2)}px,0,${z.toFixed(2)}px) rotateY(${rot.toFixed(2)}deg)`;
      card.style.zIndex = String(1000 - Math.round(ao * 10));
      card.style.opacity = String(Math.max(0, Math.min(1, RADIUS - ao)));
      card.style.setProperty('--shade', (a * 0.55 + far * 0.04).toFixed(3));
      const isCenter = slot === centerSlot;
      card.classList.toggle('is-center', isCenter);
      card.draggable = isCenter && this.settled;
    }
  }

  // ------------------------------------------------------------- input

  private bindInput(): void {
    const el = this.el;

    el.addEventListener(
      'wheel',
      (e) => {
        e.preventDefault();
        const unit = e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? 400 : 1;
        this.wheelAcc += (Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY) * unit;
        const steps = Math.trunc(this.wheelAcc / 50);
        if (steps) {
          this.wheelAcc -= steps * 50;
          this.step(steps);
        }
      },
      { passive: false },
    );

    el.addEventListener('keydown', (e) => {
      const accel = () => {
        // holding an arrow accelerates: 1,1,...,2,...,4,...,8 steps per repeat
        this.keyRepeat = e.repeat ? this.keyRepeat + 1 : 0;
        return Math.min(8, 1 << Math.floor(this.keyRepeat / 10));
      };
      switch (e.key) {
        case 'ArrowRight':
          this.step(accel());
          break;
        case 'ArrowLeft':
          this.step(-accel());
          break;
        case 'PageDown':
          this.step(10);
          break;
        case 'PageUp':
          this.step(-10);
          break;
        case 'Home':
          this.goTo(0);
          break;
        case 'End':
          this.goTo(this.items.length - 1);
          break;
        default:
          return;
      }
      e.preventDefault();
    });

    // Swipe/scrub on the stage. Pointerdown on the settled center card is left alone
    // so native drag-and-drop can take it.
    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      const card = (e.target as HTMLElement).closest('.card') as CardEl | null;
      if (card && card.classList.contains('is-center') && this.settled) return;
      el.focus();
      this.dragging = { x0: e.clientX, t0: performance.now(), target0: this.pos, lastX: e.clientX, lastT: performance.now(), v: 0 };
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener('pointermove', (e) => {
      const d = this.dragging;
      if (!d) return;
      const now = performance.now();
      const per = this.cw * 0.3; // px of drag per card
      const vx = (e.clientX - d.lastX) / Math.max(1, now - d.lastT);
      d.v = d.v * 0.7 + vx * 0.3;
      d.lastX = e.clientX;
      d.lastT = now;
      this.pos = d.target0 - (e.clientX - d.x0) / per;
      this.target = Math.round(this.pos);
      if (this.settled && Math.abs(e.clientX - d.x0) > 4) {
        this.settled = false;
        this.hooks.onMove?.();
      }
      this.kick();
    });
    const end = (e: PointerEvent) => {
      const d = this.dragging;
      if (!d) return;
      this.dragging = null;
      const moved = Math.abs(e.clientX - d.x0);
      if (moved < 5) {
        // a click: jump to the clicked side card
        const card = (document.elementFromPoint(e.clientX, e.clientY) as HTMLElement | null)?.closest('.card') as CardEl | null;
        this.target = Math.round(this.pos);
        if (card && Number.isFinite(card._index)) this.target = this.clampTarget(card._index);
      } else {
        const per = this.cw * 0.3;
        const fling = (-d.v * 1000) / per; // cards per second
        this.target = this.clampTarget(Math.round(this.pos + fling * 0.18));
        this.vel = fling * 0.5;
      }
      this.kick();
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
  }
}
