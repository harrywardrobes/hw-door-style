# HW Door Style

SketchUp extension for Harry Wardrobes. It converts the doors and drawer fronts in
our wardrobe components between **Flat** and **Shaker**, adds hidden hinge / TIP-ON
parts for the parts list, and shows a summary that exports to CSV or PDF.

See [SPEC.md](SPEC.md) for the full behaviour and design decisions.

## Install

1. Download `hw_door_style_v<version>.rbz`.
2. SketchUp → **Extensions → Extension Manager → Install Extension** → pick the `.rbz`.
3. If the toolbar doesn't appear: **View → Toolbars → HW Door Style**.

To update, install the newer `.rbz` over the old one. Your settings (`settings.json`) are kept.

## Downloads

In the [`releases`](releases/) folder (click a file, then **Download raw file**):
- `hw_door_style_v<version>.rbz` - the plugin installer (latest version)
- `HW_Colours.zip` - the 13 colour materials (textures, swatches, RGB values and a script
  that makes the `.skm` files - see `materials/README.txt`)

Every version is a separate commit (see [CHANGELOG.md](CHANGELOG.md) and the commit history), so any earlier build can be checked out and rebuilt with `python3 build.py`.

## Use

| Action | Where |
|---|---|
| Choose colours for the job (needed before editing doors) | Toolbar: Colours (palette) |
| Drawer box finish (and matching 15/16mm box thickness) | Toolbar: Colours → Drawer Box |
| Make every door **and** external drawer front Shaker | Toolbar: Shaker (door icon) |
| Redraw after resizing a wardrobe | Toolbar: press Shaker again |
| Everything back to Flat (hinges kept) | Toolbar: Reset to Flat |
| Summary, plus Export door order (CSV + PDF) | Toolbar: Summary |
| Frame sizes, mid-rail, hinge rules, names, tags, materials | Toolbar: Settings (gear) |
| Change one door | Select it (double-click into the wardrobe first), right-click → HW Door Style → Style |
| Redraw but keep individual doors' styles | Extensions → HW Door Style → Rebuild styles, or right-click → Rebuild selected |
| Set the job's hinge type | Extensions → HW Door Style → Hinge type (this job) |
| Re-tag faces/edges inside doors and drawer fronts | Extensions → HW Door Style → Apply DOOR / DRAWER_FRONT tags |
| Save the 13 colours as .skm files | Extensions → HW Door Style → Export colour library (.skm) |

Every action is a single undo (Ctrl+Z).

**Workflow:** design with flat doors, press **Shaker** once the layout is settled, and press
it again after any change to a wardrobe's size. The summary flags anything
that has been resized since conversion.

Internal drawer fronts (`IDRW_FRONT`) always stay flat.

## Develop

```
src/hw_door_style.rb            extension loader
src/hw_door_style/main.rb       menus, toolbar, right-click, actions
src/hw_door_style/settings.rb   settings + job hinge type
src/hw_door_style/finder.rb     finding and measuring doors/drawer fronts
src/hw_door_style/styles.rb     style registry (add new styles here)
src/hw_door_style/hardware.rb   hinge / TIP-ON cutlist parts
src/hw_door_style/converter.rb  rebuilds definitions at real size
src/hw_door_style/report.rb     summary, CSV, export naming/versioning
src/hw_door_style/pdf.rb        built-in PDF writer
src/hw_door_style/tagger.rb     DOOR / DRAWER_FRONT tagging
src/hw_door_style/colours.rb    colour library + painting by tag group
src/hw_door_style/drawer_box.rb drawer box finish + thickness
src/hw_door_style/colours.json  the 13 colours
src/hw_door_style/textures/     woodgrain textures
tools/hw_inspect.rb             read-only model inspector for the Ruby Console
materials/                      colour pack: make_skm.rb, swatches, RGB values
test/logic_test.rb              offline logic tests (ruby test/logic_test.rb)
```

Build: `python3 build.py` → `dist/hw_door_style_v<version>.rbz` and `dist/HW_Colours.zip`.

Fast iteration without reinstalling: in the Ruby Console run
`load 'C:/path/to/hw-door-style/src/hw_door_style.rb'` once, then reload individual
files with `load` after editing.
