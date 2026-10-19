"""
Library maintenance.

  python tools/libtools.py add tools/originals/selector-demo-orbits [more dirs...]
      Copies a hand-made shader folder (shader.json + *.glsl [+ thumb/still]) into the
      sharded store and (re)builds the paged index. Missing previews get a placeholder
      and a `.preview-pending` marker.

  python tools/libtools.py reindex
      Rebuilds index/ from every shaders/**/shader.json (the source of truth).

  python tools/libtools.py previews [--url http://localhost:5180/] [--all]
      Renders a real frame for every shader marked .preview-pending (or --all) using the
      app itself in headless Chromium, and writes thumb.webp + still.webp.
      This is also how the ~46 OneOffRender shaders without preview art can get one.

Requires: Pillow (+ playwright for `previews`).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "public" / "library"
PAGE_SIZE = 500
THUMB, STILL = (320, 180), (960, 540)


def shard(key: str) -> str:
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()
    return f"{h[:2]}/{h[2:4]}"


def kind_of(doc: dict) -> str:
    """Mirror of kindOf() in schema.ts."""
    return doc.get("kind") or "standalone"


def category_of(doc: dict) -> str:
    """Mirror of categoryOf() in schema.ts. Keep the two in step."""
    if doc.get("category"):
        return doc["category"]
    k = kind_of(doc)
    if k in ("transition", "effect"):
        return k
    return "audio-reactive" if doc["info"]["audio"]["reactive"] else "generative"


def entry_for(doc: dict, rel_dir: str) -> dict:
    needs = set()
    for p in doc["renderpass"]:
        if p["type"] == "common":
            needs.add("common")
        for i in p.get("inputs", []):
            if i["type"] in ("buffer", "texture", "cubemap", "music"):
                needs.add(i["type"])
    info = doc["info"]
    url = (info.get("source") or {}).get("url")
    return {
        "id": info["id"], "name": info["name"], "user": info["username"], "dir": rel_dir,
        **({"url": url} if url else {}),
        "thumb": info["preview"]["thumb"], "still": info["preview"]["still"],
        "stars": info.get("stars", 0), "audio": bool(info["audio"]["reactive"]),
        "passes": sum(1 for p in doc["renderpass"] if p["type"] in ("image", "buffer")),
        "kind": kind_of(doc), "category": category_of(doc),
        "needs": sorted(needs), "tags": info.get("tags", []),
    }


def shader_docs():
    """Every shader.json in the library: sharded standalone ones, flat transitions."""
    yield from sorted(LIB.glob("shaders/*/*/*/shader.json"))
    yield from sorted(LIB.glob("transitions/*/shader.json"))


def reindex() -> int:
    entries = []
    seen = {}
    for f in shader_docs():
        doc = json.loads(f.read_text(encoding="utf-8"))
        e = entry_for(doc, f.parent.relative_to(LIB).as_posix())
        if e["id"] in seen:
            print(f"  ! duplicate id {e['id']}: {seen[e['id']]} and {e['dir']}, keeping the first")
            continue
        seen[e["id"]] = e["dir"]
        entries.append(e)
    entries.sort(key=lambda e: (-e["stars"], e["name"].lower()))
    idx = LIB / "index"
    shutil.rmtree(idx, ignore_errors=True)
    idx.mkdir(parents=True)
    pages = []
    for i in range(0, len(entries), PAGE_SIZE):
        pn = f"page-{i // PAGE_SIZE:04d}.json"
        (idx / pn).write_text(json.dumps(entries[i:i + PAGE_SIZE], separators=(",", ":")), encoding="utf-8")
        pages.append(pn)
    (idx / "manifest.json").write_text(json.dumps({
        "schema": "shaderlib-index/1", "count": len(entries), "pageSize": PAGE_SIZE, "pages": pages,
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }, indent=2), encoding="utf-8")
    print(f"index: {len(entries)} shaders, {len(pages)} page(s)")
    return len(entries)


def placeholder(dst: Path, size, label: str) -> None:
    img = Image.new("RGB", size, (14, 18, 22))
    d = ImageDraw.Draw(img)
    d.text((12, size[1] - 24), label[:40], fill=(120, 135, 150))
    img.save(dst, quality=80)


def add(dirs: list[Path]) -> None:
    for src in dirs:
        doc = json.loads((src / "shader.json").read_text(encoding="utf-8"))
        sid = doc["info"]["id"]
        rel = f"shaders/{shard(sid)}/{sid}"
        dst = LIB / rel
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        for name, size in (("thumb.webp", THUMB), ("still.webp", STILL)):
            if not (dst / name).exists():
                placeholder(dst / name, size, doc["info"]["name"])
                (dst / ".preview-pending").touch()
        print(f"added {sid} -> {rel}")
    reindex()


def previews(url: str, all_: bool, seconds: float) -> None:
    from playwright.sync_api import sync_playwright

    targets = []
    for f in shader_docs():
        if all_ or (f.parent / ".preview-pending").exists():
            targets.append(json.loads(f.read_text(encoding="utf-8"))["info"]["id"])
    if not targets:
        print("nothing to render")
        return
    common = ["--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"]
    with sync_playwright() as p:
        # Hardware GPU first: heavy raymarchers can't finish a single frame on SwiftShader
        # (the tab just crashes after minutes). SwiftShader only when there is no GPU.
        b = p.chromium.launch(args=["--use-gl=angle", "--use-angle=default", *common])

        def open_page():
            pg = b.new_page(viewport={"width": 1280, "height": 900})
            pg.goto(url.rstrip("/") + "/?tools")
            pg.wait_for_function("() => window.__tools")
            return pg

        page = open_page()
        gpu = page.evaluate("""() => { const g = document.createElement('canvas').getContext('webgl2');
            const e = g && g.getExtension('WEBGL_debug_renderer_info');
            return g ? (e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'webgl2') : '' }""")
        if not gpu or "SwiftShader" in gpu:
            b.close()
            b = p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader",
                                        "--enable-unsafe-swiftshader", *common])
            page = open_page()
            gpu = "SwiftShader (software, slow)"
        print(f"  gpu: {gpu}")
        for sid in targets:
            try:
                data = page.evaluate("([id, s]) => window.__tools.preview(id, s)", [sid, seconds])
            except Exception as e:  # noqa: BLE001
                print(f"  FAIL {sid}: {e}")
                if page.is_closed() or "crash" in str(e).lower():
                    page.close()
                    page = open_page()
                continue
            img = Image.open(io.BytesIO(base64.b64decode(data.split(",", 1)[1]))).convert("RGB")
            d = next(f.parent for f in shader_docs()
                     if json.loads(f.read_text(encoding="utf-8"))["info"]["id"] == sid)
            img.resize(STILL, Image.LANCZOS).save(d / "still.webp", quality=82, method=6)
            img.resize(THUMB, Image.LANCZOS).save(d / "thumb.webp", quality=72, method=6)
            (d / ".preview-pending").unlink(missing_ok=True)
            print(f"  rendered {sid}")
        b.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a_add = sub.add_parser("add")
    a_add.add_argument("dirs", nargs="+", type=Path)
    sub.add_parser("reindex")
    a_prev = sub.add_parser("previews")
    a_prev.add_argument("--url", default="http://localhost:5180/")
    a_prev.add_argument("--all", action="store_true")
    a_prev.add_argument("--seconds", type=float, default=3.0)
    a = ap.parse_args()
    if a.cmd == "add":
        add(a.dirs)
    elif a.cmd == "reindex":
        reindex()
    else:
        previews(a.url, a.all, a.seconds)
    return 0


if __name__ == "__main__":
    sys.exit(main())
