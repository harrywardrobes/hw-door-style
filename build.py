#!/usr/bin/env python3
"""Build the plugin.

  python3 build.py               tests, then dist/hw_door_style_v<version>.rbz + HW_Colours.zip
  python3 build.py --no-test     build without running the tests
  python3 build.py --bump minor  0.15.0 -> 0.16.0 (also: patch, major), adds a CHANGELOG
                                 heading for it, and stops - write the notes, then build.
"""
import argparse, datetime, pathlib, re, subprocess, sys, zipfile

root = pathlib.Path(__file__).parent
src = root / "src"
loader = src / "hw_door_style.rb"
changelog = root / "CHANGELOG.md"
VERSION_RE = re.compile(r"(VERSION\s*=\s*')([^']+)(')")

ap = argparse.ArgumentParser(description="Build HW Door Style")
ap.add_argument("--bump", choices=["patch", "minor", "major"])
ap.add_argument("--no-test", action="store_true")
args = ap.parse_args()

version = VERSION_RE.search(loader.read_text()).group(2)

if args.bump:
    major, minor, patch = (int(x) for x in version.split("."))
    major, minor, patch = {"major": (major + 1, 0, 0), "minor": (major, minor + 1, 0), "patch": (major, minor, patch + 1)}[args.bump]
    new = f"{major}.{minor}.{patch}"
    loader.write_text(VERSION_RE.sub(lambda m: m.group(1) + new + m.group(3), loader.read_text(), count=1))
    text = changelog.read_text(encoding="utf-8")
    if f"## {new} " not in text:
        text = text.replace("# Changelog\n\n", f"# Changelog\n\n## {new} \u2014 {datetime.date.today()}\n- \n\n", 1)
        changelog.write_text(text, encoding="utf-8")
    print(f"Version {version} -> {new}. Write the CHANGELOG notes, then: python3 build.py")
    sys.exit(0)

top = re.search(r"^## (\S+)", changelog.read_text(encoding="utf-8"), re.M)
if not top or top.group(1) != version:
    print(f"WARNING: CHANGELOG.md has no entry for {version} at the top (Settings > General shows it).")

if not args.no_test:
    if subprocess.run(["ruby", str(root / "test" / "logic_test.rb")], stdout=subprocess.DEVNULL).returncode != 0:
        sys.exit("Tests failed - not building. Run: ruby test/logic_test.rb")
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
