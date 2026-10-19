# HW Door Style

SketchUp extension for Harry Wardrobes. It converts the doors and drawer fronts in
our wardrobe components between **Flat** and **Shaker**, adds hidden hinge / TIP-ON
parts for the parts list, and shows a summary that exports to CSV or PDF.

See [SPEC.md](SPEC.md) for the full behaviour and design decisions.

## Install

1. Download `hw_door_style_v<version>.rbz`.
2. SketchUp → **Extensions → Extension Manager → Install Extension** → pick the `.rbz`.
3. If the toolbar doesn't appear: **View → Toolbars → HW Door Style**.

To update, install the newer `.rbz` over the old one. Your settings are kept (they live in
`%APPDATA%\HW Door Style\settings.json`, outside the plugin folder).

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
| 22mm panels (bookcase etc.), White by default | Toolbar: Colours → 22mm Panels |
| Make every door **and** external drawer front Shaker | Toolbar: Shaker (door icon) |
| Redraw after resizing a wardrobe | Toolbar: press Shaker again |
| Everything back to Flat (hinges kept) | Toolbar: Reset to Flat |
| Summary, plus Export door order (CSV + PDF) | Toolbar: Summary |
| Frame sizes, mid-rail, hinge rules, names, tags, materials | Toolbar: Settings (gear) |
| Back up / copy settings to another computer | Settings → Download backup / Upload backup |
| Change one door | Select it (double-click into the wardrobe first), right-click → HW Door Style → Style |
| Redraw but keep individual doors' styles | Extensions → HW Door Style → Rebuild styles, or right-click → Rebuild selected |
| Fix thin / stretched doors, old STYLE_* doors, hinges | Extensions → HW Door Style → Repair doors in model |
| Export library components to their folders (old versions to `_old`) | Toolbar: Export components (rocket), library file only |
| Scribes on/off (all runouts 0 for moving units; click again for floor/ceiling/left/right/back) | Toolbar: Scribe (pencil) |
| Change one unit's runouts | Right-click → HW Door Style → Runouts... |
| Set the job's hinge type | Extensions → HW Door Style → Hinge type (this job) |
| Re-tag doors, drawer fronts and all hardware (hinges, shelf_brackets, drawer_rails) | Extensions → HW Door Style → Apply tags |
| Save the 13 colours as .skm files | Extensions → HW Door Style → Export colour library (.skm) |

Every action is a single undo (Ctrl+Z).

**Workflow:** design with flat doors, press **Shaker** once the layout is settled, and press
it again when a resize changes the number of hinges. Sizes, slab and hinge positions follow
Component Options on their own; the Summary flags anything that needs a re-run.

Drawer fronts are named `DRW_FRONT` (external) and `INT_DRW_FRONT` (internal). Internal drawer fronts always stay flat.

## Develop

See **CONTRIBUTING.md** for how the code is laid out, the rules every change follows
(undo steps, Dynamic Component values, windows) and how to add a setting, a window,
a toolbar button or a door style.

```
src/hw_door_style.rb        extension loader (version, SketchUp 2021+ check)
src/hw_door_style/main.rb   loads every file below, builds the menus once
  core/      settings, DC attributes, finding parts, undo steps (Ops), batches, logging, drawers
  doors/     styles, converter, hinges / TIP-ON, tags, repair, drawer boxes, menu actions
  colours/   colour library + painting by tag group
  job/       runouts (pencil), ceiling height, one-off standardise, door summary, PDF
  export/    component library export, OpenCutList
  ui/        windows (Dialog helper, Colours, Settings), menus and toolbar
  html/      window pages + shared hw.css / hw.js
  icons/     toolbar icons (SVG)
  settings_default.json  shipped defaults (your changes: %APPDATA%\HW Door Style\settings.json)
  colours.json, textures/  the built-in colour library
tools/      Ruby Console helpers and one-off library migrations (tools/README.md)
materials/  colour pack: make_skm.rb, swatches, RGB values
test/logic_test.rb  offline tests (ruby test/logic_test.rb)
```

Acceptance tests (in SketchUp): `load 'tools/acceptance_test.rb'; puts HWDoorAcceptance.run_report`.

Build: `python3 build.py` → `dist/hw_door_style_v<version>.rbz` and `dist/HW_Colours.zip`.
