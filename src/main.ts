import './styles.css';
import { Library } from './library/Library';
import type { Category, IndexEntry } from './library/schema';
import { CATEGORY_LABELS, CATEGORY_ORDER, entryCategory } from './library/schema';
import { AudioEngine, type Track } from './audio/AudioEngine';
import { CompileError, ShaderRenderer } from './render/ShaderRenderer';
import { Carousel, type CardEl } from './carousel/Carousel';
import { makePayload, setGhost, writeDrag } from './drag/drag';
import { TestTimeline } from './drag/TestTimeline';

const LIBRARY_ROOT = `${import.meta.env.BASE_URL}library`;
const TRACKS: Track[] = [
  { id: 'bass', label: 'Bass heavy', url: `${import.meta.env.BASE_URL}audio/bass.mp3` },
  { id: 'mids', label: 'Mids / drums', url: `${import.meta.env.BASE_URL}audio/mids.mp3` },
  { id: 'highs', label: 'Highs / strings', url: `${import.meta.env.BASE_URL}audio/highs.mp3` },
  { id: 'silence', label: 'Silence' },
  { id: 'mic', label: 'Microphone', url: 'mic' },
];

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

const library = new Library(LIBRARY_ROOT);
const audio = new AudioEngine();
const renderer = new ShaderRenderer(audio);
const stage = $('stage');

let all: IndexEntry[] = [];
let view: IndexEntry[] = [];
let dwellMs = 900;
let autoplay = true;
let dwellTimer = 0;
let abort: AbortController | null = null;
let liveCard: CardEl | null = null;
let settledEntry: IndexEntry | null = null;
const lastError = new Map<string, string>();
const compileMs = new Map<string, number>();
const docMeta = new Map<string, { description: string; url?: string }>();

// ------------------------------------------------------------------ carousel

const carousel = new Carousel(stage, {
  thumbUrl: (e) => library.thumbUrl(e),
  stillUrl: (e) => library.stillUrl(e),
  onMove: () => goStill(),
  onCenter: (e, i) => {
    $('counter').textContent = `${(i + 1).toLocaleString()} / ${view.length.toLocaleString()}`;
    ($('scrubber') as HTMLInputElement).value = String(i);
    renderInfo(e, 'still');
  },
  onSettle: (e, card) => {
    settledEntry = e;
    liveCard = card;
    if (!docMeta.has(e.id)) {
      library.get(e).then((rs) => {
        docMeta.set(e.id, { description: rs.doc.info.description, url: rs.doc.info.source?.url });
        if (settledEntry?.id === e.id) renderInfo(e, card.dataset.state || 'still');
      }, () => {});
    }
    if (lastError.has(e.id)) return setState(card, 'error', 'compile failed');
    if (!autoplay) return setState(card, 'still', 'Enter to go live');
    // Already compiled recently? Skip the dwell, it costs nothing.
    if (renderer.isCached(e.id)) return goLive(e, card);
    setState(card, 'dwell', '');
    card.style.setProperty('--dwell', `${dwellMs}ms`);
    dwellTimer = window.setTimeout(() => goLive(e, card), dwellMs);
  },
});

function setState(card: CardEl, state: string, text: string): void {
  card.dataset.state = state;
  card.querySelector('.status-text')!.textContent = text;
  if (settledEntry && card === liveCard) renderInfo(settledEntry, state);
}

/** Back to a plain image: cancel dwell, cancel compile, stop and park the canvas. */
function goStill(): void {
  clearTimeout(dwellTimer);
  abort?.abort();
  abort = null;
  renderer.stop();
  renderer.canvas.classList.remove('visible');
  renderer.canvas.remove();
  if (liveCard) liveCard.dataset.state = '';
  liveCard = null;
  settledEntry = null;
}

async function goLive(e: IndexEntry, card: CardEl): Promise<void> {
  clearTimeout(dwellTimer);
  if (card !== liveCard || card._entryId !== e.id) return;
  abort?.abort();
  const ctl = (abort = new AbortController());
  const cached = renderer.isCached(e.id);
  if (!cached) setState(card, 'compiling', 'compiling');
  try {
    const rs = await library.get(e);
    const inst = await renderer.prepare(rs, ctl.signal);
    if (ctl.signal.aborted || card !== liveCard) return;
    compileMs.set(e.id, inst.compileMs);
    const media = card.querySelector('.card-media')!;
    renderer.canvas.classList.remove('visible');
    media.appendChild(renderer.canvas);
    renderer.play(inst, () => {
      if (card !== liveCard) return;
      renderer.canvas.classList.add('visible');
      setState(card, 'live', 'live');
    });
  } catch (err) {
    if ((err as Error).name === 'AbortError') return;
    const log = err instanceof CompileError ? err.log : String(err);
    lastError.set(e.id, log);
    console.warn(`[shader] ${e.id} ${e.name}\n${log}`);
    if (card === liveCard) setState(card, 'error', 'compile failed');
  }
}

// ------------------------------------------------------------------ drag

// The caption lives inside the draggable card, but only the image/live frame is a drag
// handle: a press on the name or creator link must stay a plain click.
let downOnCaption = false;
stage.addEventListener('pointerdown', (ev) => {
  downOnCaption = !!(ev.target as HTMLElement).closest('.card-cap');
}, true);
stage.addEventListener('dragstart', (ev) => {
  if (downOnCaption) {
    ev.preventDefault();
    return;
  }
  const card = (ev.target as HTMLElement).closest('.card') as CardEl | null;
  if (!card || !card.classList.contains('is-center') || !ev.dataTransfer) return;
  const e = view.find((x) => x.id === card._entryId);
  if (!e) return;
  const payload = makePayload(e, LIBRARY_ROOT);
  writeDrag(ev.dataTransfer, payload);
  const live = card.dataset.state === 'live' ? renderer.snapshot() : null;
  setGhost(ev.dataTransfer, live ?? card._img, e.name);
  card.classList.add('dragging');
});
stage.addEventListener('dragend', (ev) => {
  (ev.target as HTMLElement).closest('.card')?.classList.remove('dragging');
});

new TestTimeline($('footer'), (id) => {
  if (!view.some((e) => e.id === id)) {
    ($('search') as HTMLInputElement).value = '';
    applyFilter();
  }
  carousel.goToId(id);
});

// ------------------------------------------------------------------ info panel

function renderInfo(e: IndexEntry, state: string): void {
  const stars = '★'.repeat(Math.min(5, e.stars)) + '☆'.repeat(Math.max(0, 5 - e.stars));
  const needs = e.needs.length ? e.needs.join(' · ') : 'none';
  const ms = compileMs.get(e.id);
  const err = lastError.get(e.id);
  const meta = docMeta.get(e.id);
  $('info').innerHTML = `
    <div class="info-main">
      <h2>${esc(e.name)}</h2>
      <div class="by">by ${meta?.url
        ? `<a class="src" href="${esc(meta.url)}" target="_blank" rel="noopener" title="${esc(meta.url)}">${esc(e.user)} ↗</a>`
        : esc(e.user)} <span class="stars" title="${e.stars} stars">${stars}</span></div>
      ${meta?.description ? `<p class="desc">${esc(meta.description)}</p>` : ''}
    </div>
    <dl>
      <div><dt>id</dt><dd>${esc(e.id)}</dd></div>
      <div><dt>passes</dt><dd>${e.passes}</dd></div>
      <div><dt>inputs</dt><dd>${esc(needs)}</dd></div>
      <div><dt>state</dt><dd class="st-${esc(state || 'still')}">${esc(state || 'still')}${ms ? ` · ${Math.round(ms)} ms compile` : ''}</dd></div>
    </dl>
    ${err ? `<details class="err"><summary>compiler log</summary><pre>${esc(err)}</pre></details>` : ''}`;
}

// ------------------------------------------------------------------ search

/**
 * Builds the type dropdown. Counts come from the loaded rows, so a category with
 * nothing in it is simply not offered rather than being a dead end.
 */
function buildCategoryFilter(): void {
  const sel = $('category') as HTMLSelectElement;
  const prev = sel.value;
  const counts = new Map<Category, number>();
  for (const e of all) {
    const c = entryCategory(e);
    counts.set(c, (counts.get(c) ?? 0) + 1);
  }
  const opts = [`<option value="">All</option>`];
  for (const c of CATEGORY_ORDER) {
    const n = counts.get(c);
    if (!n) continue;
    opts.push(`<option value="${c}">${CATEGORY_LABELS[c]}</option>`);
  }
  sel.innerHTML = opts.join('');
  if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
}

function applyFilter(): void {
  const q = ($('search') as HTMLInputElement).value.trim().toLowerCase();
  const cat = ($('category') as HTMLSelectElement).value as Category | '';
  const keep = carousel.count ? view[carousel.index]?.id : undefined;
  view = all.filter((e) => {
    if (cat && entryCategory(e) !== cat) return false;
    if (!q) return true;
    return `${e.name} ${e.user} ${e.id} ${e.tags.join(' ')}`.toLowerCase().includes(q);
  });
  goStill();
  const scrub = $('scrubber') as HTMLInputElement;
  scrub.max = String(Math.max(0, view.length - 1));
  carousel.setItems(view, keep);
  if (!view.length) {
    $('counter').textContent = '0 / 0';
    $('info').innerHTML = '<div class="info-main"><h2>No matches</h2></div>';
  }
}
$('category').addEventListener('change', () => {
  applyFilter();
  carousel.el.focus();
});
let searchT = 0;
$('search').addEventListener('input', () => {
  clearTimeout(searchT);
  searchT = window.setTimeout(applyFilter, 120);
});
$('search').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === 'Escape') {
    if (e.key === 'Escape') ($('search') as HTMLInputElement).value = '';
    applyFilter();
    carousel.el.focus();
  }
});

// ------------------------------------------------------------------ controls

$('scrubber').addEventListener('input', (e) => carousel.goTo(+(e.target as HTMLInputElement).value, true));
$('dwell').addEventListener('input', (e) => {
  dwellMs = +(e.target as HTMLInputElement).value;
  $('dwell-out').textContent = `${(dwellMs / 1000).toFixed(1)}s`;
});
$('quality').addEventListener('change', (e) => (renderer.maxPixels = +(e.target as HTMLSelectElement).value));
$('autoplay').addEventListener('change', (e) => {
  autoplay = (e.target as HTMLInputElement).checked;
  if (!autoplay) goStill();
});

// audio
const trackSel = $('track') as HTMLSelectElement;
trackSel.innerHTML = TRACKS.map((t) => `<option value="${t.id}">${esc(t.label)}</option>`).join('');
const playBtn = $('play');
const syncPlay = () => playBtn.classList.toggle('on', audio.playing);
let unlocked = false;
const unlockOnce = async () => {
  if (unlocked) return;
  unlocked = true;
  $('unlock').hidden = true;
  try {
    await audio.select(TRACKS.find((t) => t.id === trackSel.value)!);
  } catch (err) {
    console.warn('[audio]', err);
  }
  syncPlay();
};
window.addEventListener('pointerdown', unlockOnce, { once: true, capture: true });
window.addEventListener('keydown', unlockOnce, { once: true, capture: true });
trackSel.addEventListener('change', async () => {
  unlocked = true;
  $('unlock').hidden = true;
  try {
    await audio.select(TRACKS.find((t) => t.id === trackSel.value)!);
  } catch (err) {
    console.warn('[audio]', err);
  }
  syncPlay();
  carousel.el.focus();
});
playBtn.addEventListener('click', async () => {
  await audio.toggle();
  syncPlay();
});
$('volume').addEventListener('input', (e) => audio.setVolume(+(e.target as HTMLInputElement).value));

// global keys
window.addEventListener('keydown', (e) => {
  if ((e.target as HTMLElement).matches('input[type=search], select')) return;
  if (e.key === ' ') {
    e.preventDefault();
    audio.toggle().then(syncPlay);
  } else if (e.key === 'Enter' && carousel.isSettled && liveCard && settledEntry) {
    lastError.delete(settledEntry.id);
    goLive(settledEntry, liveCard);
  } else if (e.key === '/') {
    e.preventDefault();
    $('search').focus();
  } else if (document.activeElement === document.body && /^Arrow|^Page|Home|End/.test(e.key)) {
    carousel.el.focus();
    carousel.el.dispatchEvent(new KeyboardEvent('keydown', { key: e.key, repeat: e.repeat }));
  }
});

// meters (cheap: three style writes per frame, only while music is on)
const meters = ['m-bass', 'm-mid', 'm-high'].map((id) => $(id));
(function meterLoop() {
  requestAnimationFrame(meterLoop);
  if (!audio.playing) {
    meters.forEach((m) => (m.style.transform = 'scaleY(0.04)'));
    return;
  }
  if (!renderer.playing) audio.update(); // renderer drives the analyser when a shader is live
  const l = audio.levels;
  [l.bass, l.mid, l.high].forEach((v, i) => (meters[i].style.transform = `scaleY(${Math.max(0.04, Math.min(1, v * 1.4)).toFixed(3)})`));
})();

// ------------------------------------------------------------------ boot

$('unlock').hidden = false;
library
  .load((entries) => {
    const first = !all.length;
    all = entries.slice();
    buildCategoryFilter();
    if (first) {
      view = all;
      ($('scrubber') as HTMLInputElement).max = String(view.length - 1);
      carousel.setItems(view);
    } else if (($('search') as HTMLInputElement).value || ($('category') as HTMLSelectElement).value) {
      // A filter is active, so new rows have to be filtered rather than appended raw.
      applyFilter();
    } else {
      view = all;
      ($('scrubber') as HTMLInputElement).max = String(view.length - 1);
      carousel.appendItems(view);
    }
  })
  .then(() => carousel.el.focus())
  .catch((err) => {
    $('info').innerHTML = `<div class="info-main"><h2>Library failed to load</h2><pre>${esc(String(err))}</pre></div>`;
  });

const params = new URLSearchParams(location.search);
if (params.has('selftest') || params.has('tools')) {
  autoplay = false; // headless tooling drives the renderer itself
  ($('autoplay') as HTMLInputElement).checked = false;
}
if (params.has('selftest')) import('./selftest').then((m) => m.run(library, renderer));
if (params.has('tools')) {
  import('./selftest').then((m) =>
    m.installTools(library, renderer, async (id) => {
      await audio.select(TRACKS.find((t) => t.id === id) ?? TRACKS[0]);
    }),
  );
}

// for poking around in devtools
Object.assign(window, { library, renderer, carousel, audio });
