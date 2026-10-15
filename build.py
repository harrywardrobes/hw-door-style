#!/usr/bin/env python3
"""Build dist/hw_door_style_v<version>.rbz from src/ (python3 build.py)."""
import pathlib, re, zipfile

root = pathlib.Path(__file__).parent
src = root / "src"
version = re.search(r"VERSION\s*=\s*'([^']+)'", (src / "hw_door_style.rb").read_text()).group(1)
out = root / "dist" / f"hw_door_style_v{version}.rbz"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(src.rglob("*")):
        if p.is_file() and p.name != "settings.json":
            z.write(p, p.relative_to(src).as_posix())
print(out)
