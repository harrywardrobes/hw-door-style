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
    # Shown in Settings > General > What's new.
    z.write(root / "CHANGELOG.md", "hw_door_style/CHANGELOG.md")
print(out)

# Colour materials pack: materials/ + the plugin's colours.json and textures.
pack = root / "dist" / "HW_Colours.zip"
with zipfile.ZipFile(pack, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted((root / "materials").rglob("*")):
        if p.is_file():
            z.write(p, "HW Colours/" + p.relative_to(root / "materials").as_posix())
    z.write(src / "hw_door_style" / "colours.json", "HW Colours/colours.json")
    for p in sorted((src / "hw_door_style" / "textures").glob("*")):
        z.write(p, "HW Colours/textures/" + p.name)
print(pack)

# Copy into releases/ (committed, so the files can be downloaded from GitHub).
import shutil
rel = root / "releases"
rel.mkdir(exist_ok=True)
for old in rel.glob("hw_door_style_v*.rbz"):
    old.unlink()
shutil.copy(out, rel / out.name)
shutil.copy(pack, rel / pack.name)
