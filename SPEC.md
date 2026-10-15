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
| External drawer front | `XDRW_FRONT`, `LIN_DRAWER_FRONT` | Styled with the slim drawer frame; no hinges |
| Internal drawer front | `IDRW_FRONT` | Always flat; listed in the summary only |

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

## 3. How the geometry is stored

Our components are Dynamic Components that are **scaled** to size (e.g.
`WRD_DOOR` is drawn 1,942.5 mm tall and stretched to 2,024 mm). A shaker
frame inside a scaled component would stretch with it, so on conversion:

1. Doors are grouped by original definition + style + real size. Each group
   gets one definition (made unique only where needed). Same-name, same-size
   doors keep sharing one definition. Different sizes get `#n` definitions
   (SketchUp naming; instance names are left alone).
2. The instance's scale is reset to 1 and the geometry is rebuilt at real size
   in the same position. DC values (LenX/LenY/LenZ) stay consistent.
3. Inside the door definition:
   - `STYLE_SHAKER` / `STYLE_FLAT` — nested component holding the visible
     geometry. The door instance's own tag is untouched.
   - Hinge components (e.g. 4 × `soft_close_110`) and, for PTO, one `tip_on`,
     on tag `HARDWARE`, **hidden** so they never appear in renders.
4. Settings used are written to the `hw_door_style` attribute dictionary.

**Known trade-off:** if a wardrobe is resized afterwards, the DC engine
stretches the door again. **Rebuild styles** redraws every styled item at its
new size. Recommended workflow: design flat, convert when the layout is settled,
press Rebuild after any resize.

## 3a. Tags inside components

Every face and edge **inside** each recognised item is tagged, so the tag travels
with any copy of the component:
- doors → `DOOR`
- drawer fronts (external and internal) → `DRAWER_FRONT`
- hinge / TIP-ON geometry → `HARDWARE`

This applies to all recognised items, including internal drawer fronts and items
not converted yet. It runs automatically with every convert, reset and rebuild, and
on demand from **Apply DOOR / DRAWER_FRONT tags**. Tag names are editable in Settings.

## 4. Hardware (cutlist parts)

- Hinge type is per job (stored in the model). Default: Soft Close 110.
  Options: Soft Close 110, Soft Close 155, PTO 110, PTO 155. PTO adds one TIP-ON per door.
- Hinges per door by height: <=900 mm 2, <=1,600 mm 3, <=2,000 mm 4, <=2,400 mm 5, above 6.
- Hardware sits **behind the door**, against its back face (hinge 35x10x35 mm, 5 mm from
  the left edge; TIP-ON 20x10x40 mm top right). It is on the **DOOR** tag, so hiding DOOR
  hides the hinges with the doors. Components are never hidden themselves (cutlist software
  skips hidden components).
- Faces, back faces and instance carry the material **HARDWARE** so the cutlist can split
  them out. The colour tool never repaints hardware.
- Door sizes are measured from the door body only (hardware ignored). Thickness prefers the
  DC LenY, so if a Dynamic Component ever squashes a door to fit the hinges, Rebuild corrects it.
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

## 8. Not in v0.1 (future)

- Hinge side (L/R), and `DOOR L` / `DOOR R` naming.
- Supplier profiles (Integral, HPP) with different frame sizes.
- More styles: double mid-rail, glazed/mirror panels, slim shaker.
- Grain direction for oak/walnut textures (vertical on doors, horizontal on drawers).
- Pricing from the cost sheet.
- Hinge positions that avoid the mid-rail / shelf lines; real hardware models.
- Automatic rebuild when a DC is redrawn.
