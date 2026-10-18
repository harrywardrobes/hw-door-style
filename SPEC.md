# HW Door Style — Specification

SketchUp extension for Harry Wardrobes. Converts the fronts of our wardrobe
Dynamic Components (doors and drawer fronts) between styles (Flat, Shaker),
adds hidden hardware components for the parts list, and produces an on-screen
summary that can be exported to CSV or printed to PDF.

Target: SketchUp Pro 2026 (26.x), Windows. Users: designer and surveyor.

## 1. Which components are affected

Components are identified by their Dynamic Component name (`_name` attribute),
falling back to the component definition name with any `#n` suffix removed.
This matters because internal and external drawer fronts can share one
definition name (`DRAWER_FRONT` / `DRAWER_FRONT#2`) while their DC names differ.

| Kind | Default names | Behaviour |
|---|---|---|
| Door | `WRD_DOOR`, `LIN_DOOR`, `BRGFR_DOOR`, `WLK_DOOR`, `TPBX_DOOR`, `TPBX_DOOR_TOP` | Styled; gets hinges |
| External drawer front | `DRW_FRONT` | Styled with the slim drawer frame; no hinges |
| Internal drawer front | `INT_DRW_FRONT` | Always flat; listed in the summary only |

All three lists are editable in Settings. `LINE_TOP_DOOR_LEFT/RIGHT` are
door-swing indicator lines (tag `door_opening_dims`) and are deliberately not
in any list.

## 2. Styles

Styles are a registry (`styles.rb`) so new ones can be added without touching
the converter. v0.1 ships two.

### Flat
Plain 18 mm slab at the component's real size.

### Shaker (one-piece, bought-in door)
- Thickness 18 mm (taken from the component).
- Recess depth: 6 mm, square inner edge, no bevels (render-friendly, about 30 faces per door).
- Frame width: doors 100 mm (stiles and rails), external drawer fronts 50 mm.
- Mid-rail: doors only, when door height is over 1,500 mm. Centred 815 mm
  above the bottom edge of the door; 100 mm high. Both values are editable.
- If a panel would be smaller than 40 mm in either direction, the item stays
  flat and the summary flags it ("too small for shaker").

## 3. How the geometry is stored (wrapper contract, v0.7.0)

Doors used to be drawn by scaling: the wrapper (`WRD_DOOR`, `LIN_DOOR`, ...) had LenX/LenY/LenZ
formulas, so the DC engine stretched everything inside it. Once hinges sat behind the slab the
wrapper was 30 mm deep, and LenY = 18 mm squashed it to 0.6, leaving 10.8 mm thick doors. Hinges
and shaker frames were distorted too. Every door now follows this contract:

**Wrapper** (`WRD_DOOR`, `TPBX_DOOR_TOP`, `BRGFR_DOOR`, ...)
- No LenX/LenY/LenZ formulas; scale 1.
- Hidden attributes `DOOR_W`, `DOOR_T`, `DOOR_H` (access NONE, units MILLIMETERS, formulas in
  CENTIMETERS) carry the formulas the old Len formulas had, set on definition **and** instance.
- Hidden `ZZ_HINGE_*` / `ZZ_TIP_*` values used by the hardware formulas (no bare constants
  in any formula).

**Slab** — the visible door
- Definition and DC `_name` = `DOOR` (drawer fronts: `FRONT`). `STYLE_*` names are no longer used.
- `DOOR_STYLE` = `FLAT` or `SHAKER` (hidden text attribute).
- X/Y/Z = 0; LenX/LenY/LenZ = `parent!DOOR_W` / `parent!DOOR_T` / `parent!DOOR_H`.
- Geometry built at true size. A shaker slab is never scaled: one slab definition per
  style + size, shared between same-size doors.

**Hardware**
- Hinges are a round 35 mm euro-hinge cup, 12 mm deep; TIP-ON a 20×10×40 mm block. True size
  (scale 1), at Y = `DOOR_T` (behind the door), on the `hinges` tag.
- DC position formulas, so they follow a resize from Component Options:
  hinge Z = `SMALLEST(parent!ZZ_HINGE_INSET, parent!DOOR_H/4) + ZZ_HINGE_I*(spacing) - parent!ZZ_HINGE_HALF`.
  (DC has no `MIN()`; use `SMALLEST()`.) Size is locked with Len formulas to `ZZ_HINGE_W/D/HT`.
- The **number** of hinges is set when the door is converted. If a resize changes the hinge
  rule (e.g. 1,300 mm → 2,300 mm), press **Shaker** again or run **Repair doors in model**;
  the Summary flags "Needs Repair / re-run".

**Repair doors in model** (Extensions menu) brings every door and styled drawer front up to this
contract in one undo step: it migrates Len formulas to DOOR_W/T/H, resets scale, renames slabs,
re-applies hinges, removes unused `STYLE_*` definitions and redraws the top-level components.
It reports what changed. Running it again on a correct model changes nothing.

Acceptance tests: `tools/acceptance_test.rb` (WARDROBE, WALK-IN, LINEN_PRESS, TOPBOX,
BRIDGE_FRAME × single/double × 300×400, 450×1300, 600×2300; run inside an aborted operation).

## 3a. Tags inside components

Every face and edge **inside** each recognised item is tagged, so the tag travels
with any copy of the component:
- doors → `DOOR`
- drawer fronts (external and internal) → `DRAWER_FRONT`
- hinge / TIP-ON (instance and geometry) → `hinges`
- other hardware → its own tag from Settings → **Hardware tags**, so nothing stays on `HARDWARE`:

| Tag | Components |
|---|---|
| `hinges` | soft_close_110, soft_close_155, pto_110, pto_155, tip_on |
| `shelf_brackets` | SHELF_BRACKET, BKS_SHELF_BRACKET |
| `drawer_rails` | DRW_RUNNER_410 |

**Apply tags** (menu) re-tags everything and lists anything still on `HARDWARE`. The HARDWARE
*material* is unchanged (the cutlist uses it).

This applies to all recognised items, including internal drawer fronts and items
not converted yet. It runs automatically with every convert, reset and rebuild, and
on demand from **Apply DOOR / DRAWER_FRONT tags**. Tag names are editable in Settings.

## 4. Hardware (cutlist parts)

- Hinge type is per job (stored in the model). Default: Soft Close 110.
  Options: Soft Close 110, Soft Close 155, PTO 110, PTO 155. PTO adds one TIP-ON per door.
- Hinges per door by height: <=900 mm 2, <=1,600 mm 3, <=2,000 mm 4, <=2,400 mm 5, above 6.
- Hardware sits **behind the door**, against its back face (hinge at true size, 5 mm from
  the left edge; TIP-ON 20x10x40 mm top right). They are on the **hinges** tag. Components are never hidden themselves (cutlist software
  skips hidden components).
- Faces, back faces and instance carry the material **HARDWARE** so the cutlist can split
  them out. The colour tool never repaints hardware.
- Door sizes are measured from the door body only (hardware ignored). Sizes come from the
  wrapper's DOOR_W / DOOR_T / DOOR_H attributes.
- If a definition named `soft_close_110` (etc.) already exists and wasn't made by the plugin,
  it is reused as-is.

## 4a. Handles / knobs (counted, not modelled)

- 1 per door and per drawer front.
- 2 on drawer fronts wider than 500 mm (strictly over 500).
- Internal drawer fronts are counted (setting).
- Push-to-open jobs: doors count 0 handles (setting); drawer fronts still count.
- Shown per row and as a total in the summary, CSV and PDF.

## 4b. Colours

**Colours** window (toolbar + menu) with four choices per job, each "Default (no material)"
or one of the 13 library colours:

| Choice | Tags painted |
|---|---|
| Door / Drawer Colour | DOOR, DRAWER_FRONT (hinges/TIP-ON skipped) |
| Exterior Panel / Trim Colour | FACING, END_PAN, NOSING, FILLER |
| Interior Colour | STL, SH, DIV, INT_DIV, FL, DRAWER, BACK, WALKIN, MDF |
| Worktop Colour | WORKTOP |

Never changed: HARDWARE, hanging rail, Untagged, room tags, *_dims tags.

- "Default" means different things per row: on Door / Drawer it is no material; on
  Exterior, Interior and Worktop it means **same as the door colour** and shows as e.g.
  "Default (Cashmere)". Each can still be set to its own colour. Rows left on Default keep
  following the door if the door colour changes later.
- A part's group comes from its own tag, or, if the part is Untagged, the tag on most of
  the faces inside it. The material is set on the component instance; if the instance has a
  DC "material" attribute it is updated too, so a DC redraw doesn't revert it.
- Choices are stored in the model. **Save as default** stores them in the plugin; defaults
  start as Default (no material) and are pre-selected on jobs with nothing chosen yet.
- **Doors can't be edited until a Door / Drawer colour is chosen** for the job (convert,
  reset, rebuild and right-click styles open the Colours window instead). Converted doors
  are repainted with the job's colours automatically.
- Library (`colours.json`): Alby Blue, Cashmere, Dust Grey, Frost White, Graphite, Indigo
  Blue, Light Grey, Lissa Oak, Mussel, Opera Walnut, Reed Green, Sage Green, Stone Grey.
  Plain colours are solid colour (no texture, so no tile borders), sampled from the swatches
  on harrywardrobes.co.uk/door-colour-options. Lissa Oak and Opera Walnut use the site's
  grain photos, mirror-tiled so they repeat without seams (600 mm tile, grain vertical).
- If the model already has a material with exactly the same name, that one is used.
- **Export colour library (.skm)** writes all 13 as .skm files to a chosen folder.

### 22mm Panels
Colours window row **22mm Panels**, default **White** (RGB 248,248,246; only offered on this row).
Any component whose thinnest real side is 22 mm (±0.3 mm, setting `panel_22_mm`) and whose other
sides are at least 50 mm takes this colour instead of its tag group: today the bookcase shelves,
dividers and end panels (BKS_THICKNESS = 22). Hardware, doors, drawer fronts and drawer boxes are
never matched. "Default" follows the door colour, like the other rows.

## 4c. Drawer box finish

**Drawer Box** row in the Colours window (default **Windsor Oak**). Only the drawer box parts
are painted (Settings > Materials > Drawer box parts: `DRW_BOX`, `DRW_BOX_SIDE`,
`DRW_BOX_END`, `DRW_BOX_BASE`); runners, hooks and other hardware are never touched, and
box parts are excluded from the Interior colour even though they are on the DRAWER tag.

| Finish | Board | Thickness | SketchUp material |
|---|---|---|---|
| Windsor Oak (default) | Kronospan 1929 SU | 15mm (Interfit page also says 18mm - confirm) | Interfit-Box-Windsor-Oak (texture, 700 x 583 mm tile) |
| Light Grey | Egger U708 ST9 | 16mm | Interfit-Box-Light-Grey (plain colour) |
| Graphite Grey | Kronospan 0162 PE | 16mm | Interfit-Box-Graphite-Grey (plain colour) |

A job saved with an older finish falls back to Windsor Oak.

**Thickness follows the finish** (setting, on by default): each drawer unit whose own
`DRWR_BOX_THICKNESS` formula is a plain number gets 1.5 or 1.6 (cm), set on both instance and
definition dictionaries. Changed units are then redrawn by the Dynamic Components engine,
checked for size changes and `subformula-error`, and repainted. Units with an open drawer
(onClick ANIMATE moved) are skipped and listed so they can be closed and re-applied.

.skm files: `materials/interfit_box/make_interfit_box_skm.rb` (run in SketchUp), or
Extensions > HW Door Style > Export colour library (.skm), which includes all three box finishes.

## 5. User interface

- **Toolbar** (5 buttons): Colours · Shaker · Reset to Flat · Summary · Settings.
  - **Shaker** converts every door **and** external drawer front in one step. Pressing it
    again redraws everything at its current size, so there is no separate Rebuild button.
  - Export door order lives in the Summary window (and the menu).
- **Extensions menu → HW Door Style**: All doors → (each style), All external
  drawers → (each style), Reset all to Flat, Rebuild styles, Apply tags,
  Hinge type (this job) → (4 types), Summary, Export door order, Settings.
- **Reset all to Flat**: every door and external drawer front to the Flat style in one
  step; hinges and TIP-ONs are kept.
- **Right-click** on a selected door/drawer (or a wardrobe containing them):
  HW Door Style → each style, Rebuild.
- Each action is a single undo step.

## 6. Summary

On-screen table, one row per physical item (counts multiply through repeated
parent components): unit, item, kind, width, height, style, mid-rail, hinge
type, hinge qty, TIP-ON qty, notes. Totals: items by style, hinges by type,
TIP-ONs. Buttons: Refresh, Export door order.

### Export door order
One button saves **both** files, with the same version number, next to the .skp
(no dialog):

    DOOR_ORDER_v1_<file name>.csv
    DOOR_ORDER_v1_<file name>.pdf

Each export adds one to the version. The next number is the highest of: any
`DOOR_ORDER_v<N>_<file name>` already in the folder, or the last version recorded
in the model. The model must be saved first. The PDF is written by the plugin
itself (A4 landscape, totals at the top, table repeats its header on each page).

Style does **not** affect price (cost sheet to be integrated later).

## 7. Settings

**Download backup** saves every setting (including default colours) to a dated
`HW_Door_Style_settings_YYYY-MM-DD.json`. **Upload backup** reads one back into the window
(unknown keys ignored, file must be an HW Door Style backup); nothing changes until Save.
Useful for copying settings to the designer's and surveyor's computers.

Compact two-column window. **Tags** and **Materials** are separate sections (Materials holds
the hinge material and the tag lists for each colour group).

Stored inside the plugin folder:
`settings_default.json` ships with the plugin; `settings.json` holds local
overrides and survives plugin updates. The job hinge type lives in the model.

## 7a. Export components (library file)

Only in a saved file with "Components" in its name. Rocket button opens a window:

| Column | |
|---|---|
| Tick | Pre-ticked unless the component is unchanged since its last export |
| Component | Top-level component (one row per definition) |
| Folder | Remembered choice, else the folder its current file is in, else a guess (WARDROBES, DRAWERS, BRIDGE, BOOKCASE, SHELVING, MAIN COMPONENTS) |
| Status | new / not exported yet / changed / unchanged (fingerprint of every nested definition + DC values) |
| Current file | Moves to `_old` on export (also files with older names from Settings, e.g. WRD for WARDROBE) |
| New file | `<NAME>_V<n>.skp`, n = highest version anywhere (folder, main folder, `_old`) + 1; no suffix counts as V1 |

Each file is exported from the component definition inside an undone operation: colours Default
(the drawer box finish and HARDWARE material stay), drawers closed, DC values as drawn, SketchUp
2026. A clash in `_old` gets a `_moved_<date>_<time>` suffix: nothing is overwritten.
**Clean model** does the same cleaning on the library itself (one undo step), plus an optional purge
of unused components (materials are never purged), so it can be checked first. Optionally the library is saved as
the next `Components V<n>` and older `Components V*.skp/.skb` move to `_old`. A progress bar runs
during export; Explorer opens on the folder at the end.

## 7b. Scribe / runout (pencil)

Every unit (outermost component carrying runout attributes) has five runouts:
`RUNOUT_FLOOR`, `RUNOUT_CEILING`, `RUNOUT_L`, `RUNOUT_R`, `RUNOUT_BACK_WALL` (DC string values in inches,
dropdown 0 / 25 / 50 / 75 / 100 / 150 mm from Settings). The plugin only sets values; each component's
switches decide what is used: `WALL_LEFT` / `WALL_RIGHT` / `WALL_BACK`, topped off (no ceiling runout);
floor always applies.

- **Pencil pressed (scribes on)** - every unit has the job values (Settings defaults 25 mm, then the last
  values used on the job, stored in the model).
- **Click** -> scribes off: every runout 0 so units line up and move easily (one undo step, progress bar).
- **Click again** -> window with floor / ceiling / left / right / back dropdowns -> applied to every unit.
- **Right-click a unit -> HW Door Style -> Runouts...** changes just that unit (or the selected units).
- **Summary** flags scribes off, and every unit whose runouts differ from the job values.
- **Export door order** warns when scribes are off.
- **Export components** saves every library file with runouts at 0.
- **Ceiling height** (pencil window, required; or the Ceiling height button any time): every unit with
  `I05_UP_TO_CEILING` = TRUE gets its height option set to it (stretched where the height comes from
  CURRENT("LenZ")). BRIDGE_FRAME: ceiling - `A03_HEIGHT_BELOW` (skipped while 0). Scribes off keeps it.
- One-off **standardise** (asked the first time the pencil is used): `SCRIBE_L/R` renamed `RUNOUT_L/R` in keys
  and every formula (`parent!SCRIBE_L` too; hidden `ZZ_SCRIBE_*` untouched); every runout dropdown gets the
  Settings list. Open drawers are closed before each redraw.

### Component standard (library, from V19)

| Runout | Applies when | Effective value used by parts |
|---|---|---|
| Floor | always | `RUNOUT_FLOOR` |
| Ceiling | `TOPPED` = To ceiling (0) | `ZZ_RUNOUT_CEILING = IF(TOPPED, 0, RUNOUT_CEILING)` |
| Left / Right | `WALL_LEFT` / `WALL_RIGHT` = TRUE | `ZZ_RUNOUT_L/R`, `ZZ_EXT_L/R` (wardrobes) |
| Back | `WALL_BACK` = TRUE (default) | `ZZ_RUNOUT_BACK = IF(WALL_BACK="TRUE", RUNOUT_BACK_WALL, 0)` |

- `TOPPED` everywhere (was FRAME_TOPPED in wardrobes); added to END_PAN, BXEND, BULLNOSE, BOOKCASE.
- `WALL_BACK` added to WARDROBE, WALK-IN, LINEN_PRESS, TOPBOX, END_PAN, BXEND, BOOKCASE.
- Wardrobe facings: top facing + ceiling runout (when not topped), bottom facing down by the floor runout.
- BOOKCASE sides and facings go down by the floor runout.
- Dividers / end panels (WRD/WLK/LIN/TPBX_DIV, _R, BKS_DIV) take floor, ceiling (when not topped) and back.
- Shelf groups pass `ZZ_RUNOUT_BACK` through to their shelves.
- INT_DRAWER, INT_DRAWER_PLUS, SHOE_PULL_OUT carry no runouts.
- Applied once with `tools/standardise_runouts.rb`.

### Component Options order (library, from V19)

Component Options lists attributes alphabetically by attribute name, so every visible option has a
section prefix (labels unchanged). Same order on every unit; each unit only shows its sections:

| Prefix | Section |
|---|---|
| `a..` | SIZE / FRAMEWORK / CABINET |
| `b..` | DOORS |
| `c..` | DEPTHS |
| `d..` | FACING (and fillers) |
| `e..` | DIV + END PANEL / COMPARTMENTS |
| `f..` | SHELVES |
| `g..` | RAILS / HANGING RAIL |
| `h..` | DRAWERS / RUNNERS / FITTING |
| `i..` | WALL / TOPPED |
| `j..` | RUNOUT (floor, ceiling, left, right, back) |

e.g. `j01_runout_floor`, `i04_topped`, `a01_frame_width`. Formulas (own, `parent!` and named
references like `INT_DRAWER!...`) were rewritten; shelf groups that pass values through got aliases.
The plugin finds attributes with or without the prefix (`DC.key`), so old job files still work.
Applied once with `tools/reorder_options.rb`.

## 8. Not in v0.1 (future)

- Hinge side (L/R), and `DOOR L` / `DOOR R` naming.
- Supplier profiles (Integral, HPP) with different frame sizes.
- More styles: double mid-rail, glazed/mirror panels, slim shaker.
- Grain direction for oak/walnut textures (vertical on doors, horizontal on drawers).
- Pricing from the cost sheet.
- Hinge positions that avoid the mid-rail / shelf lines; real hardware models.
- Automatic rebuild when a DC is redrawn.
