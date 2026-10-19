"""
Import shaders from a OneOffRender checkout into the sharded shaderlib/1 library.

Usage:
  python tools/import_oneoffrender.py --src ../OneOffRender --out public/library --count 60
  python tools/import_oneoffrender.py --src ... --out ... --count 60 --exclude tools/compile_failures.txt
  python tools/import_oneoffrender.py --src ... --out ... --all          (import everything importable)

What it does:
  * Reads Shaders/metadata.json for stars/description/buffer/texture info.
  * Makes the per-pass channel wiring EXPLICIT (OneOffRender infers it at render time;
    here it is written into shader.json so any host can render it the same way).
  * Pulls author/date/url/license from the sibling diatribes_*.txt / .frag.meta files.
  * Writes thumb.webp (320x180) + still.webp (960x540) per shader.
  * Stores textures and cubemaps once, by content hash, under assets/.
  * Writes a paged index (index/manifest.json + index/page-NNNN.json).

Requires: Pillow.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

PAGE_SIZE = 500
THUMB = (320, 180)
STILL = (960, 540)
SAMPLER_RE = re.compile(r"^\s*uniform\s+(sampler2D|samplerCube|sampler1D|sampler3D)\s+(\w+)\s*;", re.M)
BUFFER_IDS = ["A", "B", "C", "D"]
UNSUPPORTED_SAMPLERS = {"iVideo"}
DEFAULT_SAMPLER = {"filter": "linear", "wrap": "clamp", "vflip": True}
MUSIC_SAMPLER = {"filter": "linear", "wrap": "clamp", "vflip": False}
BUFFER_SAMPLER = {"filter": "linear", "wrap": "clamp", "vflip": False}


def shard(key: str) -> str:
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()
    return f"{h[:2]}/{h[2:4]}"


def file_hash(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def slug(s: str) -> str:
    s = re.sub(r"\.(glsl)$", "", s, flags=re.I)
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower()
    return s or "shader"


def clean_name(stem: str) -> str:
    stem = re.sub(r"^[A-Z0-9]{1,3}\s*-\s*", "", stem)          # "A0 - Foo" -> "Foo"
    stem = re.sub(r"^[0-9A-Za-z]{6}_", "", stem)                # "33KSWz_Foo" -> "Foo"
    stem = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", stem)            # CamelCase -> words
    return stem.strip()


def cover_resize(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    img = img.convert("RGB")
    tw, th = size
    sw, sh = img.size
    scale = max(tw / sw, th / sh)
    nw, nh = max(tw, round(sw * scale)), max(th, round(sh * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    return img.crop((left, top, left + tw, top + th))


def samplers_in(code: str) -> list[tuple[str, str]]:
    return SAMPLER_RE.findall(code)


def channel_of(name: str) -> int | None:
    m = re.fullmatch(r"iChannel([0-3])", name)
    return int(m.group(1)) if m else None


class Importer:
    def __init__(self, src: Path, out: Path):
        self.src = src
        self.shaders_dir = src / "Shaders"
        self.out = out
        self.asset_cache: dict[str, dict] = {}
        self.txt_by_id: dict[str, Path] = {}
        for t in self.shaders_dir.glob("*.txt"):
            m = re.match(r"^([0-9A-Za-z]{6})_", t.name)
            if m:
                self.txt_by_id[m.group(1)] = t

    # ---------- attribution ----------
    def attribution(self, glsl: Path) -> dict:
        info: dict = {"username": "OneHung", "source": {"kind": "oneoffrender", "file": glsl.name}}
        m = re.match(r"^([0-9A-Za-z]{6})_", glsl.name)
        if m and m.group(1) in self.txt_by_id:
            sid = m.group(1)
            head = self.txt_by_id[sid].read_text(encoding="utf-8", errors="replace")[:400]
            for key, field in (("Name", "name"), ("User", "username"), ("Date", "date")):
                mm = re.search(rf"//\s*{key}:\s*(.+)", head)
                if mm:
                    val = mm.group(1).strip()
                    info[field] = int(val) if field == "date" and val.isdigit() else val
            info["source"] = {"kind": "shadertoy", "url": f"https://www.shadertoy.com/view/{sid}", "file": glsl.name}
            info["shadertoyId"] = sid
        meta = glsl.with_suffix(".frag.meta")
        if meta.exists():
            try:
                mj = json.loads(meta.read_text(encoding="utf-8", errors="replace"))
                if mj.get("author"):
                    info["username"] = mj["author"] + (f" (mod {mj['modifiedBy']})" if mj.get("modifiedBy") else "")
                if mj.get("shaderName"):
                    info["name"] = mj["shaderName"]
                if mj.get("license"):
                    info["license"] = mj["license"]
                if mj.get("url"):
                    info["source"] = {"kind": "shadertoy", "url": mj["url"], "file": glsl.name}
            except json.JSONDecodeError:
                pass
        return info

    # ---------- assets ----------
    def texture_asset(self, filename: str) -> dict | None:
        p = self.src / "Textures" / filename
        if not p.exists() or p.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            return None
        h = file_hash(p)
        if h in self.asset_cache:
            return self.asset_cache[h]
        ext = ".png" if p.suffix.lower() == ".png" else ".jpg"
        rel = f"assets/tex/{h[:2]}/{h}{ext}"
        dst = self.out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        img = Image.open(p)
        img.thumbnail((1024, 1024), Image.LANCZOS)
        if ext == ".png":
            img.save(dst, optimize=True)
        else:
            img.convert("RGB").save(dst, quality=88)
        self.asset_cache[h] = {"ref": h, "src": rel}
        return self.asset_cache[h]

    def cubemap_asset(self, basename: str) -> dict | None:
        faces = {}
        for f in ["px", "nx", "py", "ny", "pz", "nz"]:
            hit = next((self.src / "Cubemaps" / f"{basename}_{f}{e}" for e in (".png", ".jpg", ".jpeg")
                        if (self.src / "Cubemaps" / f"{basename}_{f}{e}").exists()), None)
            if not hit:
                return None
            faces[f] = hit
        h = hashlib.sha256(b"".join(file_hash(faces[f]).encode() for f in faces)).hexdigest()
        if h in self.asset_cache:
            return self.asset_cache[h]
        rel = f"assets/cube/{h[:2]}/{h}"
        (self.out / rel).mkdir(parents=True, exist_ok=True)
        for f, p in faces.items():
            img = Image.open(p).convert("RGB")
            img.thumbnail((512, 512), Image.LANCZOS)
            img.save(self.out / rel / f"{f}.jpg", quality=86)
        self.asset_cache[h] = {"ref": h, "src": rel}
        return self.asset_cache[h]

    # ---------- one shader ----------
    def analyze(self, meta: dict) -> dict | None:
        """Returns a plan dict, or None (with reason printed) if not importable."""
        name = meta["name"]
        glsl = self.shaders_dir / name
        prev = self.shaders_dir / (meta.get("preview_image") or "")
        if not glsl.exists():
            return None
        if not meta.get("preview_image") or not prev.exists():
            return None
        code = glsl.read_text(encoding="utf-8", errors="replace")
        if "void main" not in code:
            return None

        # buffers
        buffers: dict[str, Path] = {}
        buf = meta.get("buffer")
        stem = glsl.stem
        for bid in BUFFER_IDS:
            for cand in (f"{stem}.buffer.{bid}.glsl", f"{stem}.BUFFER.{bid}.GLSL"):
                if (self.shaders_dir / cand).exists():
                    buffers[bid] = self.shaders_dir / cand
        if isinstance(buf, str) and buf.lower().endswith(".glsl"):
            p = self.shaders_dir / buf
            bid = re.search(r"\.buffer\.([A-D])\.", buf, re.I)
            if p.exists() and bid:
                buffers[bid.group(1).upper()] = p
        if buf is True and not buffers:
            return None

        # textures
        tex = meta.get("texture")
        tex_map: dict[int, dict] = {}
        if isinstance(tex, str) and tex:
            if not tex.lower().endswith((".png", ".jpg", ".jpeg")):
                return None  # video textures: not supported in this demo
            tex = {"iChannel1": tex}
        if isinstance(tex, dict):
            for ch, cfg in tex.items():
                ci = channel_of(ch)
                if ci is None:
                    return None
                if isinstance(cfg, str):
                    if not cfg.lower().endswith((".png", ".jpg", ".jpeg")):
                        return None
                    tex_map[ci] = {"kind": "texture", "file": cfg}
                elif isinstance(cfg, dict) and cfg.get("type") == "cubemap":
                    tex_map[ci] = {"kind": "cubemap", "basename": cfg.get("basename")}
                else:
                    return None

        passes = [("image", None, glsl, code)] + [
            ("buffer", bid, p, p.read_text(encoding="utf-8", errors="replace")) for bid, p in sorted(buffers.items())
        ]
        for _, _, _, c in passes:
            for typ, uname in samplers_in(c):
                if typ in ("sampler1D", "sampler3D") or uname in UNSUPPORTED_SAMPLERS:
                    return None
        return {"meta": meta, "glsl": glsl, "preview": prev, "passes": passes, "tex_map": tex_map}

    def wire(self, kind: str, bid: str | None, code: str, buffer_ids: list[str], tex_map: dict) -> list[dict] | None:
        """Explicit version of OneOffRender's implicit channel rules."""
        declared = {u: t for t, u in samplers_in(code)}
        inputs: list[dict] = []
        used: set[int] = set()
        nxt = 0
        if kind == "buffer" and bid == "A":
            if "iChannel0" in declared:
                inputs.append({"channel": 0, "type": "buffer", "ref": "A", "sampler": BUFFER_SAMPLER})
                used.add(0)
            nxt = 1
        else:
            limit = buffer_ids if kind == "image" else [b for b in buffer_ids if b < (bid or "")]
            for b in limit:
                if f"iChannel{nxt}" in declared:
                    inputs.append({"channel": nxt, "type": "buffer", "ref": b, "sampler": BUFFER_SAMPLER})
                    used.add(nxt)
                nxt += 1
        # audio on next channel if declared and not claimed by a texture
        if f"iChannel{nxt}" in declared and nxt not in tex_map and declared[f"iChannel{nxt}"] == "sampler2D":
            inputs.append({"channel": nxt, "type": "music", "sampler": MUSIC_SAMPLER})
            used.add(nxt)
        if "iAudioData" in declared:
            inputs.append({"channel": -1, "uniform": "iAudioData", "type": "music", "sampler": MUSIC_SAMPLER})
        # custom textures override at their channels
        for ci, t in tex_map.items():
            if f"iChannel{ci}" not in declared:
                continue
            inputs = [i for i in inputs if i["channel"] != ci]
            if t["kind"] == "texture":
                a = self.texture_asset(t["file"])
                if not a:
                    return None
                inputs.append({"channel": ci, "type": "texture", **a, "sampler": {"filter": "mipmap", "wrap": "repeat", "vflip": True}})
            else:
                if declared[f"iChannel{ci}"] != "samplerCube":
                    return None
                a = self.cubemap_asset(t["basename"])
                if not a:
                    return None
                # OneOffRender flips cubemap faces vertically on upload; vflip keeps them identical
                inputs.append({"channel": ci, "type": "cubemap", **a, "sampler": {"filter": "linear", "wrap": "clamp", "vflip": True}})
            used.add(ci)
        # any remaining declared iChannel samplerCube without a cubemap: unrenderable
        for u, t in declared.items():
            ci = channel_of(u)
            if t == "samplerCube" and ci is not None and ci not in used:
                return None
        return sorted(inputs, key=lambda i: (i["channel"] < 0, i["channel"]))

    def write(self, plan: dict, sid: str) -> dict | None:
        meta, glsl = plan["meta"], plan["glsl"]
        attr = self.attribution(glsl)
        buffer_ids = [bid for k, bid, _, _ in plan["passes"] if k == "buffer"]
        rel_dir = f"shaders/{shard(sid)}/{sid}"
        d = self.out / rel_dir
        renderpass = []
        for kind, bid, path, code in plan["passes"]:
            inputs = self.wire(kind, bid, code, buffer_ids, plan["tex_map"])
            if inputs is None:
                return None
            fname = "image.glsl" if kind == "image" else f"buffer{bid}.glsl"
            renderpass.append({
                "type": kind, "name": "Image" if kind == "image" else f"Buffer {bid}",
                **({"id": bid} if bid else {}),
                "codeFile": fname, "inputs": inputs, "_code": code,
            })
        # buffers first in render order, image last
        renderpass.sort(key=lambda p: (p["type"] == "image", p.get("id", "")))
        d.mkdir(parents=True, exist_ok=True)
        for p in renderpass:
            (d / p["codeFile"]).write_text(p.pop("_code"), encoding="utf-8")
        img = Image.open(plan["preview"])
        cover_resize(img, THUMB).save(d / "thumb.webp", quality=72, method=6)
        cover_resize(img, STILL).save(d / "still.webp", quality=82, method=6)

        uses_music = any(i["type"] == "music" for p in renderpass for i in p["inputs"])
        audio_flag = bool(meta.get("audio_reactive")) or uses_music
        name = attr.get("name") or clean_name(glsl.stem)
        tags = []
        if audio_flag: tags.append("audio-reactive")
        if buffer_ids: tags.append("multipass")
        doc = {
            "schema": "shaderlib/1",
            "dialect": "glsl-full",
            "info": {
                "id": sid, "name": name, "username": attr["username"],
                "description": meta.get("description") or "", "tags": tags,
                **({"date": attr["date"]} if isinstance(attr.get("date"), int) else {}),
                **({"license": attr["license"]} if attr.get("license") else {}),
                "source": attr["source"], "stars": meta.get("stars") or 0,
                "audio": {"reactive": audio_flag},
                "preview": {"thumb": "thumb.webp", "still": "still.webp"},
            },
            "renderpass": renderpass,
        }
        (d / "shader.json").write_text(json.dumps(doc, indent=2), encoding="utf-8")
        needs = set()
        for p in renderpass:
            for i in p["inputs"]:
                needs.add({"buffer": "buffer", "texture": "texture", "cubemap": "cubemap", "music": "music"}.get(i["type"], i["type"]))
        return {
            "id": sid, "name": name, "user": attr["username"], "dir": rel_dir,
            "thumb": "thumb.webp", "still": "still.webp", "stars": meta.get("stars") or 0,
            "audio": audio_flag, "passes": len(renderpass), "needs": sorted(needs), "tags": tags,
        }


def pick(plans: list[dict], count: int, prefer: set[str] = frozenset()) -> list[dict]:
    """Variety first: preferred, every multipass, a couple of cubemaps, a few textures, a few static, then best-rated."""
    def has(plan, kind): return any(t["kind"] == kind for t in plan["tex_map"].values())
    multi = [p for p in plans if len(p["passes"]) > 1]
    cube = [p for p in plans if has(p, "cubemap")][:3]
    tex = [p for p in plans if has(p, "texture")][:5]
    rest = sorted(plans, key=lambda p: (-(p["meta"].get("stars") or 0), not p["meta"].get("audio_reactive")))
    still_static = [p for p in rest if not p["meta"].get("audio_reactive")][:6]
    preferred = [p for p in plans if p["meta"]["name"] in prefer]
    chosen: list[dict] = []
    for group in (preferred, multi, cube, tex, still_static, rest):
        for p in group:
            if len(chosen) >= count:
                break
            if p not in chosen:
                chosen.append(p)
    return chosen


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--count", type=int, default=60)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--exclude", type=Path, help="file with one source .glsl name or id per line")
    ap.add_argument("--prefer", type=Path, help="file with source .glsl names to always include")
    ap.add_argument("--keep", action="store_true", help="don't wipe existing shaders/ (merge mode)")
    a = ap.parse_args()

    meta_list = json.loads((a.src / "Shaders" / "metadata.json").read_text(encoding="utf-8"))
    excluded = set()
    if a.exclude and a.exclude.exists():
        excluded = {l.strip() for l in a.exclude.read_text().splitlines() if l.strip() and not l.startswith("#")}

    imp = Importer(a.src, a.out)
    plans = []
    for m in meta_list:
        if m.get("name") in excluded:
            continue
        p = imp.analyze(m)
        if p:
            plans.append(p)
    print(f"importable: {len(plans)} of {len(meta_list)}")
    prefer = set()
    if a.prefer and a.prefer.exists():
        prefer = {l.strip() for l in a.prefer.read_text().splitlines() if l.strip()}
    chosen = plans if a.all else pick(plans, a.count, prefer)

    if not a.keep:
        for sub in ("shaders", "index", "assets"):
            shutil.rmtree(a.out / sub, ignore_errors=True)

    entries, seen = [], set()
    for p in chosen:
        attr = imp.attribution(p["glsl"])
        sid = attr.get("shadertoyId") or slug(p["glsl"].stem)
        base, n = sid, 2
        while sid in seen:
            sid, n = f"{base}-{n}", n + 1
        if sid in excluded:
            continue
        e = imp.write(p, sid)
        if e:
            seen.add(sid)
            entries.append(e)

    # browse order: best-rated first, then name
    entries.sort(key=lambda e: (-e["stars"], e["name"].lower()))
    idx = a.out / "index"
    idx.mkdir(parents=True, exist_ok=True)
    pages = []
    for i in range(0, len(entries), PAGE_SIZE):
        pn = f"page-{i // PAGE_SIZE:04d}.json"
        (idx / pn).write_text(json.dumps(entries[i:i + PAGE_SIZE], separators=(",", ":")), encoding="utf-8")
        pages.append(pn)
    (idx / "manifest.json").write_text(json.dumps({
        "schema": "shaderlib-index/1", "count": len(entries), "pageSize": PAGE_SIZE,
        "pages": pages, "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }, indent=2), encoding="utf-8")
    print(f"wrote {len(entries)} shaders, {len(imp.asset_cache)} assets, {len(pages)} index page(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
