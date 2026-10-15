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

## Use

| Action | Where |
|---|---|
| Convert every door to Shaker | Toolbar: door icon |
| Convert every external drawer front to Shaker | Toolbar: drawer icon |
| Convert to any style (incl. back to Flat) | Extensions → HW Door Style → All doors / All external drawer fronts |
| Change one door | Select it (double-click into the wardrobe first), right-click → HW Door Style → Style |
| Redraw after resizing a wardrobe | Toolbar: Rebuild styles |
| Set the job's hinge type | Extensions → HW Door Style → Hinge type (this job) |
| Parts summary, CSV, PDF | Toolbar: Summary |
| Frame sizes, mid-rail, hinge rules, names | Toolbar: Settings |

Every action is a single undo (Ctrl+Z).

**Workflow:** design with flat doors, convert once the layout is settled, and press
**Rebuild styles** after any change to a wardrobe's size. The summary flags anything
that has been resized since conversion.

Internal drawer fronts (`IDRW_FRONT`) always stay flat.

## Develop

```
src/hw_door_style.rb            extension loader
src/hw_door_style/main.rb       menus, toolbar, right-click, actions
src/hw_door_style/settings.rb   settings + job hinge type
src/hw_door_style/finder.rb     finding and measuring doors/drawer fronts
src/hw_door_style/styles.rb     style registry (add new styles here)
src/hw_door_style/hardware.rb   hidden hinge / TIP-ON parts
src/hw_door_style/converter.rb  rebuilds definitions at real size
src/hw_door_style/report.rb     summary, CSV
tools/hw_inspect.rb             read-only model inspector for the Ruby Console
test/logic_test.rb              offline logic tests (ruby test/logic_test.rb)
```

Build the installer: `python3 build.py` → `dist/hw_door_style_v<version>.rbz`.

Fast iteration without reinstalling: in the Ruby Console run
`load 'C:/path/to/hw-door-style/src/hw_door_style.rb'` once, then reload individual
files with `load` after editing.
