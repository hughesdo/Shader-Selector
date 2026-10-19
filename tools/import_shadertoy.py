"""
Import shaders from Shadertoy into the shaderlib/1 library, one ID at a time.

This is the command you run every time you find a shader worth keeping. It is
idempotent: re-running on an ID you already have replaces that entry rather than
duplicating it, so you can re-import after fixing a category or a rating.

Usage:
  python tools/import_shadertoy.py N3cXRB
  python tools/import_shadertoy.py N3cXRB --category 3d-scene --stars 4
  python tools/import_shadertoy.py -f ids.txt --stars 3
  python tools/import_shadertoy.py https://www.shadertoy.com/view/N3cXRB --dry-run

  # bulk discovery: ask Shadertoy for IDs matching a search, then import them
  python tools/import_shadertoy.py --query "audio" --sort popular --num 25 --dry-run

What it does per shader:
  * Fetches the shader JSON through the official API (uses "Shadertoy.com API").
  * Resolves buffer wiring: Shadertoy references buffers by opaque numeric ids
    matched against the producing pass's `outputs`, so it maps those to A..D.
  * Downloads referenced textures and cubemaps, stores them once by content hash
    under assets/, and rewrites the inputs to point at them.
  * Maps a `music`/`musicstream` input to our `music` type, which is the app's
    currently selected track rather than Shadertoy's fixed SoundCloud one. This
    is the substitution that makes other people's audio shaders react to your music.
  * Guesses a category from the inputs, which you override with --category.
  * Writes shader.json + one .glsl per pass, placeholder previews, then reindexes.
  * Renders real previews through the running app (default http://localhost:5180/)
    if it is up; otherwise keeps the placeholders for `libtools.py previews` later.

Requires: Pillow, curl_cffi (Cloudflare blocks plain Python by TLS fingerprint).
API key comes from --key or the SHADERTOY_KEY environment variable.

Shaders must be set to "Public + API" by their author to be reachable at all.
Note that this grants API access, not redistribution rights: check the shader's
own licence before republishing the imported code anywhere.

Per Shadertoy's terms: this tool uses the "Shadertoy.com API".
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from libtools import LIB, THUMB, STILL, placeholder, reindex, shard  # noqa: E402

try:
    from curl_cffi import requests as cffi_requests
except ImportError:
    cffi_requests = None

API_ONE = "https://www.shadertoy.com/api/v1/shaders/{sid}?key={key}"
API_QUERY = "https://www.shadertoy.com/api/v1/shaders/query/{q}"
API_ALL = "https://www.shadertoy.com/api/v1/shaders"
MEDIA_BASE = "https://www.shadertoy.com"

ID_RE = re.compile(
    r"^(?:.*shadertoy\.com/(?:view|embed)/)?([A-Za-z0-9]{6})(?:[/?#].*)?$")

BUFFER_IDS = ["A", "B", "C", "D"]
CATEGORIES = ["audio-reactive", "generative", "3d-scene", "cubemap",
              "effect", "transition"]

# Shadertoy ctype -> our InputType. Anything absent is unsupported and the
# shader is rejected rather than imported half-wired.
CTYPE_MAP = {
    "texture": "texture",
    "cubemap": "cubemap",
    "buffer": "buffer",
    "music": "music",
    "musicstream": "music",
    "mic": "mic",
    "keyboard": "keyboard",
    "volume": "volume",
    "video": "video",
    "webcam": "webcam",
}
# Types we can actually render today. Others import but get flagged.
RENDERABLE = {"texture", "cubemap", "buffer", "music", "mic"}

CUBE_FACES = ["px", "nx", "py", "ny", "pz", "nz"]


def parse_id(text: str) -> str | None:
    text = text.strip()
    if not text or text.startswith("#"):
        return None
    m = ID_RE.search(text)
    return m.group(1) if m else None


def http_get(url: str, binary: bool = False, timeout: int = 30):
    """GET through curl_cffi so Cloudflare sees a real browser fingerprint."""
    if cffi_requests is None:
        raise RuntimeError("curl_cffi is required (pip install curl_cffi)")
    r = cffi_requests.get(url, timeout=timeout, impersonate="chrome",
                          headers={"Referer": "https://www.shadertoy.com/"})
    if r.status_code != 200:
        snippet = ("" if binary else r.text[:200].replace("\n", " "))
        raise RuntimeError(f"HTTP {r.status_code} for {url} {snippet}".strip())
    return r.content if binary else r.text


def fetch_shader(sid: str, key: str) -> dict:
    data = json.loads(http_get(API_ONE.format(sid=sid, key=key)))
    if "Error" in data:
        raise RuntimeError(f"{data['Error']} (is it set to Public + API?)")
    if "Shader" not in data:
        raise RuntimeError(f"unexpected response keys: {list(data)}")
    return data["Shader"]


def fetch_query(query: str, key: str, sort: str, num: int, frm: int) -> list[str]:
    base = API_QUERY.format(q=query) if query else API_ALL
    url = f"{base}?sort={sort}&from={frm}&num={num}&key={key}"
    data = json.loads(http_get(url))
    if "Error" in data:
        raise RuntimeError(data["Error"])
    return data.get("Results", [])


def truthy(v) -> bool:
    """Shadertoy sends sampler.vflip as the STRING "true"/"false", not a bool."""
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() == "true"


def sampler_of(src: dict) -> dict:
    s = src.get("sampler", {})
    filt = s.get("filter", "linear")
    if filt not in ("nearest", "linear", "mipmap"):
        filt = "linear"
    wrap = s.get("wrap", "clamp")
    if wrap not in ("clamp", "repeat"):
        wrap = "clamp"
    return {"filter": filt, "wrap": wrap, "vflip": truthy(s.get("vflip", True))}


def ext_of(src_path: str) -> str:
    return os.path.splitext(src_path)[1].lower() or ".bin"


def store_asset(src_path: str, dry: bool) -> tuple[str, str]:
    """Download a /media/... file, store it by content hash, return (hash, rel path)."""
    url = MEDIA_BASE + src_path if src_path.startswith("/") else src_path
    if dry:
        return "dryrun", f"assets/tex/dr/dryrun{ext_of(src_path)}"
    blob = http_get(url, binary=True)
    h = hashlib.sha256(blob).hexdigest()
    rel = f"assets/tex/{h[:2]}/{h}{ext_of(src_path)}"
    dst = LIB / rel
    if not dst.exists():                      # dedupe: identical media stored once
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(blob)
    return h, rel


def store_cubemap(src_path: str, dry: bool) -> tuple[str, str]:
    """
    Cubemaps are referenced by their first face, e.g. /media/a/<hash>.png, with
    the other five at _1.._5. Store all six under one folder keyed by the hash
    of face 0.
    """
    stem, ext = os.path.splitext(src_path)
    if dry:
        return "dryrun", "assets/cube/dr/dryrun"
    face0 = http_get(MEDIA_BASE + src_path, binary=True)
    h = hashlib.sha256(face0).hexdigest()
    rel = f"assets/cube/{h[:2]}/{h}"
    folder = LIB / rel
    if (folder / f"{CUBE_FACES[0]}{ext}").exists():
        return h, rel
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{CUBE_FACES[0]}{ext}").write_bytes(face0)
    for i in range(1, 6):
        blob = http_get(f"{MEDIA_BASE}{stem}_{i}{ext}", binary=True)
        (folder / f"{CUBE_FACES[i]}{ext}").write_bytes(blob)
    return h, rel


def buffer_letters(renderpass: list[dict]) -> dict[int, str]:
    """
    Shadertoy identifies a buffer by the numeric id its producing pass declares
    in `outputs`, and consumers reference that same number in `inputs`. Walk the
    buffer passes in order and assign A, B, C, D.

    Getting this wrong is silent: the shader still compiles and renders garbage,
    so it is worth doing explicitly rather than guessing from channel order.
    """
    out: dict[int, str] = {}
    for p in renderpass:
        if p.get("type") != "buffer":
            continue
        for o in p.get("outputs", []):
            oid = o.get("id")
            if oid is not None and oid not in out:
                if len(out) >= len(BUFFER_IDS):
                    raise RuntimeError("more than 4 buffers, cannot map to A-D")
                out[oid] = BUFFER_IDS[len(out)]
    return out


def pass_sort_key(p: dict) -> tuple:
    order = {"common": 0, "buffer": 1, "cubemap": 2, "sound": 3, "image": 4}
    return (order.get(p.get("type", ""), 5), p.get("name", ""))


def convert(shader: dict, bufmap: dict[int, str], dry: bool
            ) -> tuple[list[dict], dict[str, str], set[str]]:
    """Shadertoy renderpass[] -> our RenderPass[], plus {filename: code} and input types seen."""
    passes, files, seen = [], {}, set()
    counts: dict[str, int] = {}
    for p in sorted(shader["renderpass"], key=pass_sort_key):
        ptype = p.get("type", "image")
        name = p.get("name") or ptype.title()

        inputs = []
        for src in p.get("inputs", []):
            ctype = src.get("ctype", "")
            mapped = CTYPE_MAP.get(ctype)
            if mapped is None:
                raise RuntimeError(f"unsupported input ctype {ctype!r} in pass {name!r}")
            seen.add(mapped)
            samp = sampler_of(src)
            if mapped == "buffer":
                # Shadertoy reports vflip "true" on buffer inputs but does not
                # flip them. Honouring it turns every self-feeding buffer into a
                # frame-by-frame mirror. OneOffRender forces false; match it.
                samp["vflip"] = False
            if mapped in ("music", "mic"):
                # Shadertoy reports vflip "true" for audio, but the FFT texture is
                # not actually flipped: row 0 is spectrum, row 1 is waveform, and
                # shaders sample the spectrum at y=0.25. Honouring vflip here swaps
                # those rows, so the shader still animates but reacts to the wrong
                # data, which is near-impossible to spot by eye. OneOffRender's
                # importer forces false for the same reason; match it.
                samp["vflip"] = False
            entry = {"channel": int(src.get("channel", 0)), "type": mapped,
                     "sampler": samp}
            if mapped == "buffer":
                letter = bufmap.get(src.get("id"))
                if letter is None:
                    raise RuntimeError(
                        f"pass {name!r} reads buffer id {src.get('id')} that no pass outputs")
                entry["ref"] = letter
            elif mapped == "texture":
                h, rel = store_asset(src.get("src", ""), dry)
                entry["ref"], entry["src"] = h, rel
            elif mapped == "cubemap":
                h, rel = store_cubemap(src.get("src", ""), dry)
                entry["ref"], entry["src"] = h, rel
            inputs.append(entry)
        inputs.sort(key=lambda i: i["channel"])

        rp = {"type": ptype, "name": name, "inputs": inputs}
        if ptype == "buffer":
            for o in p.get("outputs", []):
                if o.get("id") in bufmap:
                    rp["id"] = bufmap[o["id"]]
                    break

        base = {"image": "image", "common": "common", "sound": "sound",
                "cubemap": "cubemap"}.get(ptype, "buffer")
        if ptype == "buffer":
            base = f"buffer{rp.get('id', '')}" or "buffer"
        n = counts.get(base, 0)
        counts[base] = n + 1
        fname = f"{base}.glsl" if n == 0 else f"{base}{n + 1}.glsl"
        rp["codeFile"] = fname
        files[fname] = p.get("code", "")

        passes.append(rp)
    return passes, files, seen


def guess_category(seen: set[str], code: str) -> str:
    if "cubemap" in seen:
        return "cubemap"
    if "music" in seen or "mic" in seen:
        return "audio-reactive"
    # crude raymarch sniff: an SDF-ish map function plus an accumulating march loop
    sdf = re.search(r"\b(sdSphere|sdBox|sdTorus|sdCapsule|raymarch|rayMarch)\b", code)
    march = re.search(r"for\s*\([^)]*\)\s*\{[^}]*\bt\s*\+=", code, re.S)
    if sdf or march:
        return "3d-scene"
    return "generative"


def slug(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower() or "shader"


def import_one(sid: str, key: str, args) -> dict:
    shader = fetch_shader(sid, key)
    info = shader["info"]
    bufmap = buffer_letters(shader["renderpass"])
    passes, files, seen = convert(shader, bufmap, args.dry_run)

    unsupported = seen - RENDERABLE
    allcode = "\n".join(files.values())
    category = args.category or guess_category(seen, allcode)
    reactive = category == "audio-reactive" or bool(seen & {"music", "mic"})

    stars = args.stars
    if stars is None:
        likes = int(info.get("likes", 0) or 0)
        stars = 5 if likes >= 100 else 4 if likes >= 25 else 3 if likes >= 5 else 2

    doc = {
        "schema": "shaderlib/1",
        "dialect": "shadertoy",
        "kind": "standalone",
        "category": category,
        "info": {
            "id": info["id"],
            "name": info.get("name") or info["id"],
            "username": info.get("username") or "unknown",
            "description": info.get("description") or "",
            "tags": info.get("tags") or [],
            "date": int(info["date"]) if str(info.get("date", "")).isdigit() else None,
            "license": args.license,
            "source": {"kind": "shadertoy",
                       "url": f"https://www.shadertoy.com/view/{info['id']}"},
            "stars": stars,
            "audio": {"reactive": reactive},
            "preview": {"thumb": "thumb.webp", "still": "still.webp"},
        },
        "renderpass": passes,
    }
    for k in ("date", "license"):
        if doc["info"].get(k) is None:
            doc["info"].pop(k, None)

    rel = f"shaders/{shard(info['id'])}/{info['id']}"
    if args.dry_run:
        return {"id": info["id"], "name": doc["info"]["name"], "dir": rel,
                "category": category, "passes": len(passes), "stars": stars,
                "unsupported": sorted(unsupported), "written": False}

    dst = LIB / rel
    dst.mkdir(parents=True, exist_ok=True)
    # Re-import replaces code and metadata but keeps any real previews already rendered.
    for old in dst.glob("*.glsl"):
        old.unlink()
    (dst / "shader.json").write_text(json.dumps(doc, indent=1), encoding="utf-8")
    for fname, code in files.items():
        (dst / fname).write_text(code, encoding="utf-8")
    for name, size in (("thumb.webp", THUMB), ("still.webp", STILL)):
        if not (dst / name).exists():
            placeholder(dst / name, size, doc["info"]["name"])
            (dst / ".preview-pending").touch()

    return {"id": info["id"], "name": doc["info"]["name"], "dir": rel,
            "category": category, "passes": len(passes), "stars": stars,
            "unsupported": sorted(unsupported), "written": True}


def render_previews(url: str) -> None:
    """Shadertoy's own thumbnails sit behind Cloudflare, so render a real frame through the
    running app instead (same as `libtools.py previews`). Skipped with a hint if it is not up."""
    import urllib.request
    try:
        urllib.request.urlopen(url, timeout=3).close()
    except OSError:
        print(f"\npreviews: app not reachable at {url}, placeholders kept.\n"
              f"  start it with `npm run dev`, then run: py tools/libtools.py previews")
        return
    from libtools import previews
    print("\nrendering previews ...")
    try:
        previews(url, False, 3.0)
    except Exception as exc:                                      # noqa: BLE001
        print(f"previews: failed ({exc}), placeholders kept. Retry: py tools/libtools.py previews")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Import Shadertoy shaders into the library, one ID at a time.")
    ap.add_argument("ids", nargs="*", help="shader IDs or /view/ URLs")
    ap.add_argument("-f", "--file", help="file with one ID or URL per line")
    ap.add_argument("--query", help="search Shadertoy for IDs instead of naming them")
    ap.add_argument("--sort", default="popular",
                    choices=["name", "love", "popular", "newest", "hot"])
    ap.add_argument("--num", type=int, default=25, help="results per query page")
    ap.add_argument("--from", dest="frm", type=int, default=0, help="query page offset")
    ap.add_argument("--category", choices=CATEGORIES,
                    help="override the guessed category")
    ap.add_argument("--stars", type=int, choices=[1, 2, 3, 4, 5],
                    help="your rating; default is derived from likes")
    ap.add_argument("--license", help="licence string for info.license")
    ap.add_argument("--key", default=os.environ.get("SHADERTOY_KEY", ""))
    ap.add_argument("--delay", type=float, default=0.75)
    ap.add_argument("--url", default="http://localhost:5180/",
                    help="running app used to render previews after import")
    ap.add_argument("--no-previews", action="store_true",
                    help="keep placeholder previews (render later with libtools.py previews)")
    ap.add_argument("--dry-run", action="store_true",
                    help="fetch and report, write nothing")
    ap.add_argument("--keep-going", action="store_true",
                    help="continue past failures")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except AttributeError:
            pass

    if cffi_requests is None:
        print("curl_cffi is required: pip install curl_cffi", file=sys.stderr)
        return 1
    if not args.key:
        print("no API key: pass --key or set SHADERTOY_KEY", file=sys.stderr)
        return 1

    ids: list[str] = []
    for raw in args.ids:
        if (sid := parse_id(raw)):
            ids.append(sid)
    if args.file:
        for raw in Path(args.file).read_text(encoding="utf-8").splitlines():
            if (sid := parse_id(raw)):
                ids.append(sid)
    if args.query is not None:
        found = fetch_query(args.query, args.key, args.sort, args.num, args.frm)
        print(f"query {args.query!r} -> {len(found)} id(s)")
        ids.extend(found)
    if not ids:
        ap.error("no shader IDs. Pass IDs, -f a file, or --query a search.")

    seen_ids, ordered = set(), []
    for sid in ids:
        if sid not in seen_ids:
            seen_ids.add(sid)
            ordered.append(sid)

    ok, failed = [], []
    for n, sid in enumerate(ordered, 1):
        print(f"[{n}/{len(ordered)}] {sid} ... ", end="", flush=True)
        try:
            r = import_one(sid, args.key, args)
        except Exception as exc:                                  # noqa: BLE001
            print(f"FAILED: {exc}")
            failed.append((sid, str(exc)))
            if not args.keep_going and not args.query:
                break
        else:
            flag = ""
            if r["unsupported"]:
                flag = f"  [needs {', '.join(r['unsupported'])}, will not render yet]"
            print(f'ok "{r["name"]}" {r["category"]} '
                  f'{r["passes"]} pass(es) {r["stars"]}*{flag}')
            ok.append(r)
        if n < len(ordered):
            time.sleep(args.delay)

    if ok and not args.dry_run:
        reindex()
        if not args.no_previews:
            render_previews(args.url)
    print(f"\nimported {len(ok)}, failed {len(failed)}"
          + (" (dry run, nothing written)" if args.dry_run else ""))
    for sid, err in failed:
        print(f"  {sid}: {err}")
    return 0 if ok or not failed else 1


if __name__ == "__main__":
    sys.exit(main())
