# Part labels — the pipeline as it was before the labels work (0.59.0)

Read-only survey, written before changing anything (step 1 of the labels plan).

## Where it lives

| Piece | File | What it does |
|---|---|---|
| Parts list | `job/parts_list.rb` — `generate`, `collect`, `finish` | OpenCutList-style list: a part = one definition at one size; groups = material + standard thickness. `finish` sorts each group by the OCL part order strategy and numbers the parts **A, B, C…** (`first_number` → `'A'`, `.succ`), restarting at A in every group (`part_number_sequence_by_group`, read from OpenCutList's cutlist presets) and again for hardware. Every piece is kept in the part's `instances` (`instance_info`: layer, entity name, named path, and the top-level entity id `top`). Nothing is stored on the model — numbers are worked out fresh each time. |
| Label data | `job/labels.rb` — `Labels.options`, `Labels.entries`, `Labels.sort` | Port of OpenCutList's `CutlistLabelsWorker`: one entry per piece (sheet parts then hardware), sorted by the layout's part order strategy, custom formulas evaluated with OCL's formula checker (`core/formula_parser.rb`). |
| Label layouts | `Labels.options` | **Not edited in HW.** Reads the layouts saved in OpenCutList: the model's own (`ladb_opencutlist` › `core.presets` › `cutlist_labels_options`), then OCL's global presets, else OCL's built-in default (A4, 2 × 4). Page size, margins, columns / rows, offset, cutting marks and the element list (`formula`, `x`, `y` as a fraction of the label, `size`, `anchor`, `rotation`, `color`). |
| Drawing | `html/parts_list.html` — `labels()`, `labelEntries`, `paginate`, `pageSvg`, `element` | Port of OCL's `_slide-labels.twig` / `_label-element.twig`: each page is an SVG in mm; preview in the Labels tab (first 60 pages). |
| Printing | `printLabels()` in `html/parts_list.html` | Sets `@page { size: W H; margin: 0 }`, copies the pages into `#printArea` (the only thing visible under `@media print`) and calls `window.print()` 50 ms later → **SketchUp's HtmlDialog (Chromium) → Windows print dialog**. No raw printing. |
| Callback | `PartsList.show` → `labels` action | Builds entries for all / hardware only / one group (`lWhich`) with the chosen preset and sends them to the page. |
| Settings | `core/settings.rb` (`settings.json` in `%APPDATA%\HW Door Style`) | Nothing label-specific yet; layouts are OpenCutList's. |
| T number | `job/products.rb` — `Products.list(model)` → `[rows, tops]` | `tops` maps the **entity id of each top-level product (host and members)** to its reference (`T1`, `W2`, `L1`…). `instance_info['top']` is that id, so a piece's T number is `tops[instance['top']]` (the Room Plan pod sheet already does this). Numbers are kept on the products (`product_t` / `product_ref`); the library master is never numbered. |

## Confirmed

It is **HTML in the dialog → browser print**: the labels are SVG drawn by the dialog's JavaScript and printed with `window.print()` through the Windows print dialog. That is the path the Zebra "first label blank" problem goes through (Chromium keeps the last printer's page size for the first job).

## Notes for the work

- The plugin's attribute dictionary is `hw_door_style` (`DICT`) — used for the per-instance `part_no` / `barcode` and the model's customer / room fields, instead of a new `HW` dictionary, so everything the plugin stores stays in one place.
- The HubSpot link already stores the Room ID, room name and customer on the model (`HubSpotRoom.link`: `hs_room_id`, `hs_room_name`, `hs_first_name`, `hs_last_name`); the new customer / room fields take those when the file is linked, and the path-based bootstrap otherwise.
- Part numbers today restart in every group, so they are not unique in a room — the new integers run across the whole file so the barcode `HW-{ROOM_ID}-{PART_NO}` is unique.
