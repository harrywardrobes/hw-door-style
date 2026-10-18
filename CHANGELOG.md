# Changelog

## 0.11.4 — 2026-10-18
- **Ceiling height** for the whole job: on the pencil window (required, starts at 0) and on a new
  **Ceiling height** button (floor / ceiling / arrows icon) that works any time. Every unit with
  "Up to ceiling" = TRUE is built to it; runouts add on top; scribes off never changes it.
  Heights that come from stretching are stretched (bottom fixed, corrected to the exact height);
  BRIDGE_FRAME = ceiling - "Height below bridge".
- Summary flags units whose height differs from the ceiling.
- Library (V20): "Up to ceiling" (default TRUE) on the 4 wardrobes, BOOKCASE, facing blocks, END_PAN,
  BULLNOSE, BXEND, BRIDGE_FRAME; BRIDGE_FRAME "Height below bridge (mm)"; THICKNESS hidden everywhere;
  dividers take floor + ceiling runouts.

## 0.11.3 — 2026-10-18
- Works with the re-ordered library: attributes are found with or without their section prefix
  (j01_runout_floor, i04_topped, a01_frame_width ...), so old job files still work too.
- Library (tools/reorder_options.rb, applied to Components V19): Component Options in the same order on
  every unit - Size, Doors, Depths, Facing, Div / End panel, Shelves, Rails, Drawers, Wall / Topped,
  Runout. Labels unchanged; all formulas rewritten; verified identical geometry and no new errors on
  all 17 units.

## 0.11.2 — 2026-10-18
- Settings window in tabs: Doors & hinges, Tags, Colours & materials, Scribe / runout, Export
  (remembers the last tab); smaller window.
- Includes the 0.11.1 redraw fix for the pencil.

## 0.11.1 — 2026-10-18
- Fix: pencil "can't convert NilClass into an exact number" on every unit. Redraws now run without
  the DC progress bar (which isn't initialised on a fresh SketchUp) and fall back to the other DC
  redraw entry points; any failure is logged to the Ruby Console with its source line.

## 0.11.0 — 2026-10-16
- **Scribe / runout** (pencil, right of the rocket). Pressed = every unit has the job runouts;
  click = all runouts 0 (easier to move units); click again = window with floor / ceiling / left /
  right / back dropdowns, applied to every unit. Progress bar, one undo step, drawers closed first.
- Right-click a unit -> **Runouts...** to change just that unit; the Summary flags hand-changed units
  and scribes off. Door order export warns when scribes are off.
- Export components saves library files with every runout at 0.
- One-off standardise (asked on first use): SCRIBE_L/R -> RUNOUT_L/R in keys and formulas, every
  runout dropdown 0 / 25 / 50 / 75 / 100 / 150 mm (Settings). Verified on all 17 V19 units: same
  geometry before/after, at current values and at 100 mm with every wall switch on.
- Settings: runout dropdown values and defaults (25 mm each side).
- Library standard (tools/standardise_runouts.rb, applied to Components V19): TOPPED everywhere,
  WALL_BACK on wardrobes / END_PAN / BXEND / BOOKCASE, wardrobe facings take floor + ceiling,
  BOOKCASE takes floor, internal drawers + shoe pull-out carry no runouts. All 17 units verified.

## 0.10.1 — 2026-10-16
- Clean model: purge removes unused components only; materials are never purged.

## 0.10.0 — 2026-10-16
- **Export components** (rocket button). Library files only ("Components" in the name).
  Window lists every top-level component with folder, status (new / changed / unchanged),
  current file and the new file; Select all / Deselect all / Export all / Export selected.
- Each export: cleaned (colours Default, drawers closed), as drawn, SketchUp 2026, saved as
  `<FOLDER>/<NAME>_V<n>.skp` (n = highest version found, incl. `_old` and older file names, + 1).
  The previous file(s) move to `_old` (never overwritten).
- **Clean model** button: colours to Default, close drawers, optional purge of unused components (listed
  first; materials are never purged). One undo step, so you can check before exporting.
- Optional: save the library as the next `Components V<n>` and move older ones to `_old`.
- Progress bar; Explorer opens on the folder when done. Folder per component is remembered.
- Settings: old versions folder, older file names (e.g. `WARDROBE: WRD`), never-export list (FLOOR).
- Change detection compares content (geometry, positions, materials, tags, DC values), not SketchUp ids.
- Library: BXSH → BOX_SHELF, BRGSK → BRIDGE_SKELETON, FACNG_BLOCK_L → FACING_BLOCK_L.

## 0.9.0 — 2026-10-16
- Colours window: new **22mm Panels** row, default **White** (a plain white offered only on this row).
  Matches any flat panel 22 mm thick by size, not tag (today: bookcase shelves, dividers and end
  panels), and overrides its tag group. Hardware, doors, drawer fronts and drawer boxes are never matched.
- Settings → Materials: panel thickness for that row (default 22 mm).
- Saved default colours missing a row now fall back to the shipped default.

## 0.8.0 — 2026-10-16
- Hinges are now round 35 mm euro-hinge cups (12 mm deep). Repair / Shaker rebuilds old square ones.
- Hinges on the **hinges** tag (was DOOR). New Settings → **Hardware tags**: shelf brackets →
  `shelf_brackets`, drawer runners → `drawer_rails`. Nothing is left on HARDWARE; **Apply tags**
  lists anything that is.
- Simpler drawer front names: `DRW_FRONT` (external) and `INT_DRW_FRONT` (internal) replace
  BEDSIDE_/LINEN_PRESS_/INT_DRAWER_/INT_DRAWER_PLUS_DRW_FRONT.
- Saved settings are updated once automatically (drawer names, hinge tag, hardware tags,
  EXT_SH and BOOKCASE in Exterior / Trim); your own extra tags are kept.

## 0.7.0 — 2026-10-16
- **Fix: doors drawn 10.8 mm thick.** Wrappers no longer scale: Len formulas moved to hidden
  DOOR_W / DOOR_T / DOOR_H; wrapper and hardware scale is always 1.
- Slab renamed `DOOR` (drawer fronts `FRONT`) with `DOOR_STYLE` = FLAT / SHAKER; sized by
  `parent!DOOR_W/T/H`. Shaker is built at true size, never stretched. `STYLE_*` retired.
- Hinges / TIP-ON follow resizes through DC position formulas. A change in hinge count still
  needs Shaker or Repair (flagged in the Summary).
- New **Repair doors in model** menu command: one undo step, idempotent, reports what it fixed.
- Default names add BEDSIDE_DRW_FRONT, LINEN_PRESS_DRW_FRONT (external) and
  INT_DRAWER_DRW_FRONT, INT_DRAWER_PLUS_DRW_FRONT (internal).
- `tools/acceptance_test.rb`: all 56 checks pass on Components V16.

## 0.6.2 — 2026-10-15
- New default settings: Exterior tags add EXT_SH and BOOKCASE; Interior tags drop MDF; drawer box parts = DRW_BOX.
- Settings: **Download backup** / **Upload backup** (.json). An uploaded backup fills the window; press Save to keep it.

## 0.6.1 — 2026-10-15
- Drawer box finishes: **Windsor Oak** (default, 15mm, textured), **Light Grey** and **Graphite Grey** (16mm).
- Materials named `Interfit-Box-Windsor-Oak` / `-Light-Grey` / `-Graphite-Grey`; seamless Windsor Oak texture.
- Export colour library (.skm) includes the box finishes; `materials/interfit_box/` script makes the two .skm files.

## 0.6.0 — 2026-10-15
- **Drawer Box** finish in the Colours window: Lissa Oak (default) plus Interfit's melamine range
  (Graphite Grey, Light Grey, White, Lugano Oak, Windsor Oak). Paints only DRW_BOX parts.
- Box side thickness follows the finish (15mm woodgrains, 16mm plain): sets DRWR_BOX_THICKNESS on each
  drawer unit, redraws, checks sizes and formula errors. Skips units with open drawers.
- Drawer boxes no longer take the Interior colour.
- Settings: drawer box parts list, thickness-follows-finish switch.

## 0.5.0 — 2026-10-15
- Toolbar trimmed to 5 buttons: Colours, Shaker, Reset to Flat, Summary, Settings.
- Shaker now converts doors and external drawer fronts together; press again to redraw after resizing.
- Rebuild styles and Export door order removed from the toolbar (still in the menu; export also in Summary).
- Settings icon is now a gear.

## 0.4.1 — 2026-10-15
- Colours: Exterior / Interior / Worktop "Default" now follows the door colour, shown as
  "Default (<door colour>)"; each can still be set separately.

## 0.4.0 — 2026-10-15
- Hinges / TIP-ONs moved behind the door, on the DOOR tag, material HARDWARE.
- Door sizes measured from the door body only, so hardware behind the door doesn't change them.
- **Colours** window: Door / Drawer, Exterior Panel / Trim, Interior and Worktop colours from a
  13-colour library; Save as default; doors locked until a door colour is chosen.
- Colour library bundled (plain colours + seamless Lissa Oak / Opera Walnut textures);
  **Export colour library (.skm)**.
- Settings window made compact; Tags and Materials split into separate sections.

## 0.3.0 — 2026-10-15
- Hinges and TIP-ONs are no longer hidden: they sit fully inside the door thickness
  (invisible, but found by cutlist software) and carry the material `HARDWARE`.
- Handle / knob count: 1 per door and drawer front, 2 on drawer fronts over 500 mm wide,
  none on push-to-open doors (configurable). In summary, CSV and PDF.
- Settings: hardware material, handle rules.

## 0.2.0 — 2026-10-15
- **Reset all to Flat** (toolbar + menu): all doors and external drawer fronts to Flat, hinges kept.
- **Export door order**: one button saves `DOOR_ORDER_v<N>_<file name>.csv` and `.pdf` next to the
  .skp; version goes up by one on every export. PDF generated by the plugin (no print dialog).
- Faces and edges inside every recognised item are tagged `DOOR` / `DRAWER_FRONT` (hardware `HARDWARE`),
  so tags carry across copies. Runs on every convert/reset/rebuild, or via **Apply DOOR / DRAWER_FRONT tags**.
- Tag names added to Settings.

## 0.1.0 — 2026-10-15
First test build.
- Flat and Shaker styles (one-piece, 6 mm square recess). Doors 100 mm frame, external drawer fronts 50 mm.
- Mid-rail on doors over 1,500 mm, centred 815 mm above the door bottom.
- Detects items by Dynamic Component name; internal drawer fronts stay flat.
- Rebuilds stretched DC doors at real size; same-name, same-size doors share one definition.
- Hidden hinge components (per-job type, count by height) and TIP-ON for PTO, on tag HARDWARE.
- Toolbar, Extensions menu, right-click menu, Rebuild styles.
- Summary dialog with totals, CSV export and print-to-PDF.
- Settings dialog; settings stored in the plugin folder.
