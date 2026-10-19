# Working on HW Door Style

A SketchUp extension for Harry Wardrobes (Gautier Design Ltd). Windows, SketchUp 2021+.
Everything lives in the module `HarryWardrobes::DoorStyle`.

## Layout

| Folder | What's in it |
|---|---|
| `src/hw_door_style.rb` | Extension loader: name, version, SketchUp 2021+ check. Bump `VERSION` here. |
| `main.rb` | Loads every file (the `FILES` list, in order) and builds the menus once. |
| `core/` | `Settings`, `DC` (Dynamic Component values), `Finder` (finding parts), `Ops` (undo steps), `Batch` (one item per tick with a progress bar), `Drawers` (close drawers), `Log`. |
| `doors/` | `Styles` (Flat / Shaker builders), `Converter`, `Hardware` (hinges / TIP-ON), `Tagger`, `Repair`, `DrawerBox`, `Doors` (what the door menu items do). |
| `colours/` | `Colours`: the library, painting by tag group, 22mm panels. |
| `job/` | `Runouts`, `Ceiling`, `Pencil` (button state + window + observers), `Standardise` (one-off component update), `Report` (summary, door order), `Pdf`. |
| `export/` | `LibraryExport` (Export components), `OpenCutList`, `HubSpot` (API calls, key in SketchUp prefs only), `HubSpotRoom` (file <-> Room link, field mapping, send window), `HubSpotPictures` (scenes -> images -> Room file fields). |
| `ui/` | `Dialog` (opens every window), `ColoursWindow`, `SettingsWindow`, `Menus` (menu, toolbar, right-click). |
| `html/` | One page per window, plus `hw.css` / `hw.js` shared by all of them. |

One module per file, named after the file. A new file goes into `FILES` in `main.rb`
(after the files it uses).

## Rules every change follows

1. **Every model change is one undo step, through `Ops.run`.**
   `Ops.run(model, 'Apply colours') { ... }` undoes everything if the block raises.
   Message boxes go *after* `Ops.run` returns, never inside it.
   Use `Ops.throwaway` for work that must always be undone (Export components).
   Never call something that opens its own step from inside another step.
2. **Long jobs over many units use `Batch.run`**, which gives a progress window, one undo
   step and holds the pencil check until the end.
3. **Dynamic Component values are read with `DC.read` (exact key) or `DC.value` (base name)**.
   Library options carry a section prefix (`j01_runout_floor`); `DC.value(inst, 'runout_floor')`
   finds it. Write with `DC.set_value`. Lengths are inches; convert with `* 25.4`.
4. **After changing a DC, close drawers then redraw:** `Drawers.close(inst.definition.entities)`
   then `DC.redraw(inst)`. Check `_error` keys when a formula seems not to apply.
5. **Never put `ANIMATE` in a `_formula` key.** No colour / material options in components.
6. **Windows open through `Dialog.open`.** The page is `html/<name>.html`, marks `<!--HW-->`
   in its `<head>` and reads its data from `var D = /*DATA*/null;`.
7. **Console output goes through `Log`** (`Log.info`, `Log.error(where, e)`, `Log.debug`).
   Debug lines print only with `Sketchup.write_default('HW Door Style', 'debug', true)`.

## How to...

**Add a setting.** Add the key and default to `settings_default.json`, a field in the right
`<section>` of `html/settings.html` (and its `load()` / `collect()`, plus a rule in `problems()`
if it can be wrong), and read it with
`Settings.get['key']` (`Settings.mm('key')` for a length). `test/logic_test.rb` fails
if the code reads a key that isn't in the defaults. If an old saved value must change,
bump `SETTINGS_VERSION` and handle it in `Settings.migrate`.

**Add a window.** Write `html/<name>.html` (with `<!--HW-->`), then:
```ruby
dlg = Dialog.open('name', title: 'HW - Name', key: 'hw_name', width: 400, height: 300, data: {...})
dlg.add_action_callback('apply') { |_c, json| ... }   # 'cancel' is already wired
dlg.show
```

**Add a toolbar button.** Add `icons/<name>.svg`, a command in `Menus.build`
(`Menus.command(text, tip, 'name') { ... }`) and its key in `Menus::TOOLBAR`.

**Add a door style.** Write a builder lambda in `doors/styles.rb` and register it in
`STYLES`; menus pick it up.

## Settings keys

| Key | Used for |
|---|---|
| `door_names`, `ext_drawer_names`, `int_drawer_names` | Component names treated as doors / drawer fronts |
| `top_door_height_mm` | TOPBOX top doors and the bridge (Components section) |
| `door_frame_mm`, `drawer_stile_mm`, `drawer_frame_mm`, `recess_mm`, `min_panel_mm` | Shaker frame sizes |
| `midrail_min_door_height_mm`, `midrail_centre_mm`, `midrail_width_mm` | Shaker mid-rail |
| `default_hinge_type`, `hinge_rules`, `hinge_end_inset_mm` | Hinges (job type stored on the model) |
| `handle_double_min_width_mm`, `handles_on_internal_drawers`, `handles_on_pto_doors` | Handle counts in the summary |
| `door_tag`, `drawer_tag`, `hinge_tag`, `hardware_material`, `hardware_tags` | Tags |
| `colour_groups`, `default_colours`, `colour_library`, `panel_22_mm`, `panels_22_default` | Colours |
| `drawer_box_parts`, `box_thickness_follows_finish` | Drawer boxes |
| `runout_values_mm`, `runout_defaults_mm` | Pencil dropdowns and defaults |
| `export_old_folder`, `export_aliases`, `export_skip` | Export components |
| `ocl_thicknesses_mm`, `ocl_sheet_sizes`, `ocl_doors_bought_in`, `ocl_bought_in_tag` | Set up OpenCutList (Cut list) |
| `hubspot_pictures`, `hubspot_picture_size`, `hubspot_picture_format`, `hubspot_picture_folder`, `hubspot_picture_mode`, `hubspot_files_folder` | Pictures to HubSpot |
| `hubspot_required` | Fields each Room stage needs (`{ stage id => [field names] }`) |
| `settings_version` | Migration marker (see `Settings.migrate`) |

Window-only data the Settings window receives starts with `_` (`_job`, `_version`, `_colour_rows`...)
and is never saved; `_debug` is stored as a SketchUp preference (`Log.debug?`).

Job values stored **on the model** (attribute dictionary `hw_door_style`): `hinge_type`,
`scribe_on`, `scribe_values`, `ceiling_mm`, `facing_btm_mm`, colour choices, export versions,
the HubSpot link (`hs_room_id`, `hs_project_id`, `hs_contact_id`, `hs_room_name`, `hs_customer`, `hs_address`, `hs_info`, `hs_sent_at`).

**HubSpot field mapping** lives in `export/hubspot_room.rb` (`fields`). Never add a HubSpot field without
Harry's OK; the fields the plugin made are in the Room group "Survey (SketchUp)".

## Testing

- `ruby test/logic_test.rb`: offline, no SketchUp needed. Also runs on GitHub for every push
  (`.github/workflows/test.yml`, which attaches the built `.rbz` to the run).
- In SketchUp, on the component library: turn on **Settings > General > Developer mode**,
  restart SketchUp, then **Extensions > HW Door Style > Developer > Run tests**. Suites:
  doors (size / slab / hinge contract), runouts (25 mm on, back exactly), ceiling (heights, top
  doors, bridge alignment), colours, cut list (OpenCutList set-up), export (read-only). Each runs in an `Ops.throwaway` step,
  so the model is never changed; `Ops.run` inside one raises `Ops::NestedStep` instead of committing.
  Add a check by writing a `suite_<name>` method in `dev/acceptance.rb` and listing it in `SUITES`.
- Developer menu also has **Inspect selected component** (DC options and formulas to the Ruby
  Console) and **Reload plugin code** (after editing files in the installed plugin folder).
- Try changes on a copy of a job or inside a step that is undone. `model.save_copy` first
  before editing the component library.

## Releasing

1. `python3 build.py --bump minor` (or `patch` / `major`): sets `VERSION` and adds a
   `CHANGELOG.md` heading. Write the notes under it (they show in Settings > General).
2. `python3 build.py`: runs the tests, then writes `dist/` and `releases/`.
3. Commit, push, and copy `dist/hw_door_style_v<version>.rbz` + `dist/hw_door_style_latest.json` into
   the updates folder (`Harry Wardrobes\_HW Door Style\Updates` on Google Drive). Every computer
   running the plugin offers the update at its next start-up (or Settings > General > Check for updates).

Shared Drive folders (`Harry Wardrobes\_HW Door Style`): `Updates` (releases), `Colours` (colour pack),
`Team settings` (the file for Load team settings), `Dev` (test files).
