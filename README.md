# Shader Selector

You can try it right now in your browser at the
[live demo](https://hughesdo.github.io/Shader-Selector/). Click anywhere on the
page to start the demo audio for the audio-reactive shaders.

Shader Selector is the shader picker I use inside the other applications I'm
building: one place to browse, preview, rate and pull in a growing library of
GLSL shaders and transitions. It's public because I'd like it to be a starting
point for others. Fork it, point the importer at the Shadertoy work you love,
add your own pieces, and grow a personal collection over time, with an app for
selecting those assets already built. If it nudges you to write your own
shaders and share them back on Shadertoy, even better.

The shaders in `public/library` belong to their original authors. Each
`shader.json` credits the creator and links back to the original on Shadertoy
wherever that was possible. If you see a missing or incorrect credit, or you'd
like your work handled differently, reach out to me on X at
[@oneHung](https://x.com/oneHung) and I'll fix it.

## What changed in v2

- **Type filter** next to search: All, Audio Reactive, Generative, 3D Scene, CubeMaps, Effects, Transitions. Only categories that actually have shaders are offered.
- **Transitions**, 15 of them, imported from OneOffRender. A transition card renders the live morph between two demo clips rather than showing a still.
- **`tools/import_shadertoy.py`**, the repeatable one-ID-at-a-time importer.
- **`tools/import_transitions.py`**, for pulling gl-transitions out of a OneOffRender checkout.
- Schema gained `kind`, `category` and `params`. All three are optional with
  derivation rules, so shader.json files written before v2 load unchanged.

### Importing a Shadertoy shader

The importer reads your Shadertoy API key from the `SHADERTOY_KEY` environment
variable (or `--key`). Get a key at https://www.shadertoy.com/myapps. Keep it out
of the repo: set it in your environment rather than in any file.

On Windows, save it permanently for your user (open a new terminal afterwards):

```
setx SHADERTOY_KEY "yourkey"
```

Or set it for the current terminal only:

```
set SHADERTOY_KEY=yourkey              (cmd)
$env:SHADERTOY_KEY = "yourkey"         (PowerShell)
```

```
pip install curl_cffi pillow

python tools/import_shadertoy.py N3cXRB
python tools/import_shadertoy.py N3cXRB --category 3d-scene --stars 4
python tools/import_shadertoy.py --query audio --sort popular --num 25 --dry-run
```

Re-running on an ID you already have replaces that entry instead of duplicating
it, so you can re-import after changing your mind about a category or rating.
The category is guessed from the shader's own inputs; `--category` overrides.
Stars default to a band derived from likes; `--stars` overrides.

`curl_cffi` is not optional. Shadertoy is behind Cloudflare, which blocks
Python's HTTP client on its TLS fingerprint before the API key is even looked at.

Only shaders their author set to **Public + API** are reachable. That grants API
access, not redistribution rights, so check a shader's own licence before
republishing its code. The gl-transitions are different: those carry real MIT
licences and author credits, which is why they ship in the repo.

### After importing

```
npm run dev                                   # in another terminal
python tools/libtools.py previews             # render art for anything pending
python tools/selftest.py --url http://localhost:5180/
```

### Known rough edges

- `Displacement` and `Luma` declare a sampler (`displacementMap`, `luma`) that
  nothing provides. They are bound to the `from` clip, which is what OneOffRender
  ends up doing by accident. They work, but they are not doing what their authors
  intended.
- The two demo clips ship as WebM **and** MP4. The WebM is load-bearing:
  Chromium without proprietary codecs, which includes the build Playwright
  drives, cannot decode H.264, so an MP4-only clip makes every transition render
  a flat grey frame during headless preview generation.


A reusable coverflow picker for GLSL shaders. Flip through stills fast, let one sit for a beat and it turns into the live, audio-reactive shader, then drag it onto a timeline.

Built as a standalone piece so it can be debugged in isolation and dropped into bigger apps later.

## Run it

```
run.bat                (Windows: installs deps the first time, then opens the dev server)
```
or
```
npm install
npm run dev            -> http://localhost:5180
npm run build          -> dist/  (static, works from any folder or web host)
```

Needs Node 18+ and a WebGL2 browser (any current Chrome, Edge, Firefox, Safari).

## Controls

| Input | Does |
|---|---|
| ← → / mouse wheel / swipe | flip |
| hold ← → | accelerates (1, 2, 4, 8 cards per repeat) |
| PgUp / PgDn, Home / End | ±10, first, last |
| click a side card | jump to it |
| scrubber | jump anywhere in the library |
| Enter | go live now (skip the dwell) |
| Space | play / pause music |
| / | search |
| drag the center card | drop payload (still or live) |

**Dwell** slider sets how long a card has to sit before its shader compiles (default 0.9s). Flip again before it fires and nothing is compiled. Recently compiled shaders (last 6) skip the dwell entirely since they cost nothing to show again.

**Music** dropdown: Bass heavy, Mids/drums, Highs/strings, Silence, Microphone. The three loops in `public/audio/` are synthesized placeholders. Drop your Suno tracks in with the same file names (or add entries to `TRACKS` in `src/main.ts`).

## How it fits together

```
src/
  library/schema.ts        the data format (shaderlib/1), read this first
  library/Library.ts       paged index loader + on-demand shader.json/.glsl fetch (LRU)
  carousel/Carousel.ts     virtualized coverflow: 15 DOM cards no matter the library size
  render/ShaderRenderer.ts one shared WebGL2 context, multipass, textures, cubemaps, LRU of compiled shaders
  render/preprocess.ts     dialect handling: Shadertoy mainImage() and full GLSL 330 -> GLSL ES 3.00
  audio/AudioEngine.ts     Web Audio -> 512x256 FFT/waveform texture (same layout as OneOffRender)
  drag/drag.ts             the drag contract (MIME + payload), what your timelines consume
  drag/TestTimeline.ts     throwaway drop target that proves it works
  main.ts                  wiring: dwell timer, still -> compiling -> live states, controls
  selftest.ts              ?selftest and ?tools modes used by the Python tools
```

The sequence when a card lands in the center:

1. still image shows, its sharper 960px version swaps in once decoded
2. dwell timer runs (thin bar along the card bottom)
3. timer fires: shader.json + .glsl fetched, compiled (in the background if the browser supports `KHR_parallel_shader_compile`), textures loaded
4. the single live canvas is parked inside the card and crossfades in only after its first frame is drawn, so no black flash
5. flip away at any point: dwell cancelled, compile abandoned (or kept in cache if it already finished), canvas detached

## Library format

Modeled on Shadertoy's export JSON, see `src/library/schema.ts` for every field.

```
public/library/
  index/manifest.json            count, page size, page list
  index/page-0000.json           500 lightweight rows per page (what the carousel reads)
  shaders/ab/cd/<id>/            ab/cd = first 4 hex chars of sha1(id)
    shader.json                  info + renderpass[] (Image, Buffer A..D, Common) with explicit inputs
    image.glsl, bufferA.glsl...  pass code as real files
    thumb.webp  (320x180)        for flipping
    still.webp  (960x540)        for the centered card
  assets/tex/ab/<sha256>.jpg     textures, stored once, shared by hash
  assets/cube/ab/<sha256>/       cubemaps: px nx py ny pz nz
```

Why it holds up at tens of thousands: no folder ever holds more than a handful of entries (65,536 shard buckets), assets are deduplicated by content hash, and the carousel never touches anything but index rows and thumbnails until a shader is actually wanted.

Each pass declares its inputs explicitly (`music`, `buffer` with ref A..D, `texture`, `cubemap`, plus `keyboard`/`webcam`/`video` reserved), with Shadertoy-style sampler settings (filter, wrap, vflip). OneOffRender figures out channel wiring at render time; here it's written down once by the importer, so any host renders a shader the same way.

Two dialects in one library:
- `glsl-full`: complete programs with their own `#version`, uniforms and `main()` (your OneOffRender files)
- `shadertoy`: `mainImage()` code, host injects the standard uniforms. Raw Shadertoy exports fit this, inline `code` is accepted as well as `codeFile`.

`tools/originals/selector-demo-orbits/` is a reference shader in the Shadertoy dialect using Common + a self-feeding Buffer A + music.

## Drag contract

```ts
import { readDrag, SHADER_MIME } from './drag/drag';
el.addEventListener('dragover', e => { if (e.dataTransfer.types.includes(SHADER_MIME)) e.preventDefault(); });
el.addEventListener('drop', e => { const p = readDrag(e.dataTransfer); /* p.id, p.shaderUrl, p.thumbUrl ... */ });
```

MIME `application/x-shaderlib+json`, schema `shaderlib-drag/1`. URLs are absolute so a target in a different app can fetch the shader. `text/uri-list` (shader.json URL) and `text/plain` are set as fallbacks.

## Tools (Python, need Pillow; playwright for the browser ones)

```
python tools/import_oneoffrender.py --src <OneOffRender> --out public/library --count 60 ^
    --exclude tools/compile_failures.txt --prefer tools/prefer.txt
python tools/import_oneoffrender.py --src <OneOffRender> --out public/library --all
python tools/libtools.py add tools/originals/selector-demo-orbits   (re-add after an import, imports wipe shaders/)
python tools/libtools.py reindex
python tools/libtools.py previews [--all]     render real previews for shaders with no art, using the app
python tools/selftest.py                      compile + render every shader headless, writes compile_failures.txt
python tools/make_audio.py                    regenerate the placeholder loops
```

Status from the last full run against OneOffRender: 449 shaders in metadata, 369 importable (the rest need video inputs or have no preview image), 344 of 351 tested compile and render in WebGL2. The 7 failures are genuine GLSL ES strictness errors (int times float, an undeclared `iTimeDelta`, a missing Common tab), listed with line numbers in `tools/selftest_results.json`.

## Knobs worth knowing

- `Carousel.ts`: `RADIUS` (cards each side), `STIFFNESS` (flip snappiness), the 72 degree side angle and spacing in `layout()`
- `ShaderRenderer.ts`: `cacheSize` (compiled shaders kept warm), `maxPixels` (the Quality dropdown)
- `styles.css`: `--card-w` on `.carousel` sets card size
- Feedback buffers are RGBA16F when the GPU allows it, RGBA8 otherwise

## Not done yet (on purpose)

- keyboard / webcam / video inputs are in the schema but render black
- sound passes and cubemap-output passes are skipped
- no persistence of last position, favourites or ratings
- the music texture is live analyser data (Shadertoy style); OneOffRender normalizes over the whole track, so absolute brightness can differ a bit from your renders
