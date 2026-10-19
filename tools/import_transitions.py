"""
Import gl-transition shaders from a OneOffRender checkout into the library.

Usage:
  python tools/import_transitions.py --src ../OneOffRender
  python tools/import_transitions.py --src ../OneOffRender --all
  python tools/import_transitions.py --src ../OneOffRender --only Dreamy Luma
  python tools/import_transitions.py --src ../OneOffRender --dry-run

By default this takes only the ones you rated "Highly Desired" AND marked
"Fully Working" in Transitions/Transitions_Metadata.json. --all takes every
transition that is not Broken; --only takes the ones you name.

These are gl-transitions: GLSL 330, MIT (one BSD-2), each declaring

    uniform sampler2D from, to;
    uniform float progress;
    uniform vec2 resolution;
    vec4 transition(vec2 uv);

plus optional tunables. Parameter values come from Transitions_Metadata.json
where you set them, falling back to the `// = value` default in the header.

Unlike the Shadertoy importer, these ship with real licences and author
credits, so the code is redistributable. Author and licence are carried into
info.username / info.license from the file header.

Transitions land flat in library/transitions/<slug>/ since there will only
ever be ~100, but they share the single index with everything else.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from libtools import LIB, THUMB, STILL, placeholder, reindex  # noqa: E402

AUTHOR_RE = re.compile(r"^//\s*Author:\s*(.+)$", re.M | re.I)
LICENSE_RE = re.compile(r"^//\s*License:\s*(.+)$", re.M | re.I)
VERSION_RE = re.compile(r"^\s*#version\s+\d+", re.M)
# uniform <type> <name>; // = <default><, trailing note>
PARAM_RE = re.compile(
    r"^\s*uniform\s+(\w+)\s+(\w+)\s*;\s*//\s*=\s*([^\n]+)$", re.M)
RESERVED = {"from", "to", "progress", "resolution", "ratio_from", "ratio_to"}


def parse_default(gl_type: str, raw: str):
    """Turn `vec4(0.,0.,0.,.6)` or `0.075` or `false` into JSON-able values."""
    raw = raw.split(",  ")[0].strip()
    raw = re.sub(r"\s*//.*$", "", raw).strip()
    if gl_type == "bool":
        return raw.lower().startswith("true")
    m = re.match(r"^(?:vec[234]|ivec[234])\s*\((.*)\)", raw)
    if m:
        nums = []
        for part in m.group(1).split(","):
            part = part.strip()
            if not part:
                continue
            try:
                nums.append(float(part))
            except ValueError:
                return None
        return nums or None
    # strip a trailing prose note: "0.5, leaf radius"
    head = raw.split(",")[0].strip()
    try:
        return float(head)
    except ValueError:
        return None


def slug(name: str) -> str:
    name = re.sub(r"\.glsl$", "", name, flags=re.I)
    name = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower()
    return name or "transition"


def pretty(name: str) -> str:
    stem = re.sub(r"\.glsl$", "", name, flags=re.I)
    stem = stem.replace("_", " ").replace("-", " ")
    stem = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", stem)
    return " ".join(w[:1].upper() + w[1:] for w in stem.split())


def main() -> int:
    ap = argparse.ArgumentParser(description="Import gl-transitions into the library.")
    ap.add_argument("--src", type=Path, required=True,
                    help="path to a OneOffRender checkout")
    ap.add_argument("--all", action="store_true",
                    help="import everything not marked Broken")
    ap.add_argument("--only", nargs="+", help="import just these (name or stem)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    tdir = args.src / "Transitions"
    meta_path = tdir / "Transitions_Metadata.json"
    if not meta_path.exists():
        print(f"no metadata at {meta_path}", file=sys.stderr)
        return 1
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

    def wanted(fname: str) -> bool:
        m = meta.get(fname, {})
        if args.only:
            stems = {slug(o) for o in args.only}
            return slug(fname) in stems
        if m.get("status") == "Broken":
            return False
        if args.all:
            return True
        return (m.get("preference") == "Highly Desired"
                and m.get("status") == "Fully Working")

    picked = sorted(f for f in meta if wanted(f))
    if not picked:
        print("nothing matched", file=sys.stderr)
        return 1

    written = 0
    for fname in picked:
        src = tdir / fname
        if not src.exists():
            print(f"  ! {fname}: file missing, skipped")
            continue
        code = src.read_text(encoding="utf-8", errors="replace")
        m = meta[fname]

        author = (AUTHOR_RE.search(code).group(1).strip()
                  if AUTHOR_RE.search(code) else "unknown")
        licence = (LICENSE_RE.search(code).group(1).strip()
                   if LICENSE_RE.search(code) else None)

        # A few files omit #version 330. The renderer's preprocessor keys off the
        # dialect rather than the text, but keeping the source uniform means one
        # less special case downstream, so add it here where it is missing.
        if not VERSION_RE.search(code):
            code = "#version 330\n" + code
            fixed_version = True
        else:
            fixed_version = False

        # A couple of transitions (Displacement, Luma) declare a sampler beyond
        # from/to that nothing binds. In OneOffRender these silently read texture
        # unit 0, so record them and let the renderer bind deliberately instead of
        # inheriting whatever happens to be bound.
        extra_samplers = [n for _, n in
                          re.findall(r"^\s*uniform\s+(sampler2D)\s+(\w+)\s*;", code, re.M)
                          if n not in RESERVED]

        # Parameters: declared defaults, overridden by whatever you tuned.
        params: dict = {}
        for gl_type, pname, raw in PARAM_RE.findall(code):
            if pname in RESERVED:
                continue
            val = parse_default(gl_type, raw)
            if val is not None:
                params[pname] = val
        for k, v in m.items():
            if k in ("preference", "status") or k in RESERVED:
                continue
            params[k] = v

        sid = slug(fname)
        stars = {"Highly Desired": 5, "Mid": 3, "Low": 1}.get(m.get("preference"), 3)
        doc = {
            "schema": "shaderlib/1",
            "dialect": "gl-transition",
            "kind": "transition",
            "category": "transition",
            "params": params,
            "info": {
                "id": sid,
                "name": pretty(fname),
                "username": author,
                "description": f"gl-transition. Status: {m.get('status', 'unknown')}.",
                "tags": ["transition"],
                "license": licence,
                "source": {"kind": "gl-transitions", "file": f"Transitions/{fname}"},
                "stars": stars,
                "audio": {"reactive": False},
                "preview": {"thumb": "thumb.webp", "still": "still.webp"},
            },
            "renderpass": [{
                "type": "image",
                "name": "Image",
                "inputs": [],          # from/to are bound by the host, not by channel
                "codeFile": "transition.glsl",
            }],
        }
        if extra_samplers:
            doc["extraSamplers"] = extra_samplers
        if licence is None:
            del doc["info"]["license"]

        note = " (+#version)" if fixed_version else ""
        if extra_samplers:
            note += f" [needs {', '.join(extra_samplers)}]"
        print(f"  {sid:28} {author[:18]:18} {len(params)} param(s){note}")
        if args.dry_run:
            continue

        dst = LIB / "transitions" / sid
        dst.mkdir(parents=True, exist_ok=True)
        (dst / "shader.json").write_text(json.dumps(doc, indent=1), encoding="utf-8")
        (dst / "transition.glsl").write_text(code, encoding="utf-8")
        for pname, size in (("thumb.webp", THUMB), ("still.webp", STILL)):
            if not (dst / pname).exists():
                placeholder(dst / pname, size, doc["info"]["name"])
                (dst / ".preview-pending").touch()
        written += 1

    print(f"\n{len(picked)} selected, {written} written"
          + (" (dry run)" if args.dry_run else ""))
    if written:
        reindex()
    return 0


if __name__ == "__main__":
    sys.exit(main())
