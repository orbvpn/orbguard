#!/usr/bin/env python3
"""Assemble the OrbGuard flagship artifact from src/ parts.

usage: build.py <icon_dir> <fragment_out>
Writes the artifact fragment (no doctype/html/head/body) and out/index.html,
a full local preview document that mimics the publish skeleton.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src"
ICON_DIR = pathlib.Path(sys.argv[1])
FRAGMENT = pathlib.Path(sys.argv[2])
PREVIEW = ROOT / "out" / "index.html"

FONTS = (
    # one link per family, so a refused family cannot take the others down with it.
    # Archivo is requested with both of its axes: the app bundles the same variable file.
    "https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,100..900&display=swap",
    "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&display=swap",
    "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap",
)


def cat(folder, ext):
    parts = []
    for p in sorted((SRC / folder).glob("*." + ext)):
        parts.append(p.read_text())
    return "\n".join(parts)


def sprite(names):
    out, missing = [], []
    paint = re.compile(r'(stroke|fill)="(?!none|white|url)[^"]+"')
    for n in names:
        f = ICON_DIR / (n + ".svg")
        if not f.exists():
            missing.append(n)
            continue
        svg = f.read_text()
        vb = re.search(r'viewBox="([^"]+)"', svg)
        inner = re.sub(r"^.*?<svg[^>]*>", "", svg, count=1, flags=re.S)
        inner = re.sub(r"</svg>\s*$", "", inner.strip(), flags=re.S)
        inner = paint.sub(lambda m: m.group(1) + '="currentColor"', inner)
        inner = re.sub(r"\s*\n\s*", "", inner)
        out.append(
            '<symbol id="i-%s" viewBox="%s" fill="none">%s</symbol>'
            % (n, vb.group(1) if vb else "0 0 24 24", inner)
        )
    return "\n".join(out), missing


css = cat("css", "css")
js = cat("js", "js")
body = (SRC / "body.html").read_text()
names = sorted(set((SRC / "icons.txt").read_text().split()))
symbols, missing = sprite(names)

# every icon referenced from markup or script must be in the sprite
used = set(re.findall(r"#i-([a-z0-9_]+)", body + js))
used |= set(re.findall(r"\bic\('([a-z0-9_]+)'", js))
used |= set(re.findall(r"\bicon:\s*'([a-z0-9_]+)'", js))
undefined = sorted(u for u in used if u not in names or u in missing)

head = (
    '<meta name="claude:viewport-fit-sides" content="cover">\n'
    "<title>OrbGuard Flagship</title>\n"
    + "".join('<link rel="stylesheet" href="%s">\n' % u for u in FONTS)
    + "<style>\n%s\n</style>\n" % css
)
sprite_block = (
    '<svg aria-hidden="true" focusable="false" '
    'style="position:absolute;width:0;height:0;overflow:hidden">\n%s\n</svg>\n' % symbols
)
fragment = head + sprite_block + body + "\n<script>\n" + js + "\n</script>\n"

bad = [c for c in ("—", "–") if c in fragment]
FRAGMENT.write_text(fragment)
PREVIEW.parent.mkdir(exist_ok=True)
PREVIEW.write_text(
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
    "<style>:root{color-scheme:light;padding:env(safe-area-inset-top,0px) 0 "
    "env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui}"
    "img{max-width:100%}[hidden]{display:none!important}</style>"
    "<script>var q=new URLSearchParams(location.search).get('theme');"
    "if(q)document.documentElement.setAttribute('data-theme',q);</script>"
    "</head><body>" + fragment + "</body></html>"
)

print("fragment bytes:", len(fragment.encode()))
print("icons in sprite:", len(names) - len(missing), "| used:", len(used))
print("missing icon files:", missing or "none")
print("undefined icon refs:", undefined or "none")
print("dash characters:", "FOUND " + repr(bad) if bad else "none")
unused = sorted(n for n in names if n not in used and n not in missing)
print("unused in sprite:", len(unused))
if "--list-unused" in sys.argv:
    print(" ".join(unused))
