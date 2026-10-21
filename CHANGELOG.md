# Changelog

## 0.72.3 — 2026-10-22
- Settings > Product list: "Wardrobe internals" list added.

## 0.72.2 — 2026-10-22
- The master library file isn't told its internals have no tall unit (they sit alone there by design).

## 0.72.1 — 2026-10-22
- A settings file saved from the Settings window kept the old Pod letters (L, M) and export list; those three settings now take the shipped values (the rest of your settings are kept).

## 0.72.0 — 2026-10-22
- Pod letters are now T Tall units, W Wall / bridge units (box shelves moved here), B Base units (worktops, box ends, cabinets and the external drawer units - L is gone), F Facings. M (miscellaneous) is gone; end panels were never products.
- Wardrobe internals (int drawer, int drawer plus, shoe pull-out - Settings "product_internals") are always part of a tall unit's pod: they can't be their own product, and one that isn't inside any tall unit gets no Pod number - the Workshop checks and the Product List tab say so, with a "Put it in" list of the tall units. The Workshop pack can't be saved until they're in one.
- Add component (+): "T - Wardrobe internals" is its own group under T; the groups follow the new letters.
- The ceiling is treated like the floor: never exported from the master (Settings "export_skip"), kept in the job template.

## 0.71.1 — 2026-10-22
- Add component (+): components are grouped by their Pod number letter - T Tall units, W Wall / bridge, B Base (worktops, box ends, cabinets), L Drawer units, F Facings, M Miscellaneous - then Electrical Faceplates, then Other (bullnose, ceiling, cover). The library folders are unchanged; search still finds a component by its folder name.

## 0.71.0 — 2026-10-22
- Add component (+): a new Electrical Faceplates category - the faceplates now live in the library's own "Electrical Faceplates" folder (sockets, switches, blank covers, phone / TV / fuse plates). They're placed as they are: no job colours, scribes or door style, and they stay out of the Workshop. Unversioned files no longer show "V0"; mixed-case names are kept as written.

## 0.70.4 — 2026-10-22
- Electrical faceplates (sockets, switches, back plates) are no longer parts or hardware in the Workshop: anything loaded from the Electrical Faceplates library folder, or on the "Sockets Switches and Plugs" / "Socket Cutout Construction Lines" tags, is skipped and never flagged in the checks. Settings > Hardware > "Not furniture" lists the folders and tags.

## 0.70.3 — 2026-10-21
- Export components (template): the template's floor and ceiling are saved at the default room size - 4000 wide, 3000 long, 2400 ceiling (Settings > Export components > Template room). The room itself isn't recorded in the template, so Room setup still asks for each job with blank boxes.

## 0.70.2 — 2026-10-21
- Room setup (new job): the customer comes from a HubSpot search - pick the project, then its Room (or Design Visit) - the customer folder is found by contact ID (or a new "SURNAME First (id)" folder is made), the file name is pre-filled (SURVEY - room - customer / DESIGN VISIT - customer) to check, then the room size. The file is linked to HubSpot as it's saved. A file that already exists offers to open it instead. "select folder manually" under the customer search for a folder of your own; the "Change..." button is gone.

## 0.70.1 — 2026-10-21
- Security: custom (Ruby) label formulas are no longer run at all - a label layout can arrive inside a model file, and every HW field is a fixed field. The OpenCutList formula checker is gone with it. The Zebra fallback copy no longer goes through a shell string.
- Fixes: the shipped label names (Settings > Labels) now apply alongside your own saved ones, so renamed hardware prints as "Hanging rail 775", "Hinges 110° soft close"...; the stable panel no longer counts as needing hinges in Repair; V36 had a duplicate top rail bracket on each hanging rail after the rename - removed.

## 0.70.0 — 2026-10-21 (needs Components V36)
Library V36 and the plugin together - older job files need their units replaced from the new library.
- Library: hardware renamed (OVAL_BRACKET_TOP, HANGING_RAIL_TOP / _BTM, HINGE_SOFT_CLOSE_110..., SHELF_BRACKET for the bookcase too, WARDROBE, WRD_RAIL / WST_RAIL); the hidden derived values every unit's formulas read are named consistently (zz_topped, zz_up_to_ceiling, zz_door_double, zz_door_right, zz_depth, a04_depth_finished); pull-out closed, colours cleared; linen press top is a floor; MDF and Timber 2x1 are length materials.
- Plugin: reads the dropdowns by fixed keys (i04_top_of_unit, b01_doors); no settings migrations, no upgrade-on-open, no old tag / name / folder fallbacks. The acceptance suite knows right-hand doors.
- Parts list: Boards without length materials; Cut + Edged (Material, Thickness, Strip, Qty); Hardware one line per item (names from Settings > Labels; rails by length), no size / material columns; Timber / MDF as lengths; 22mm panels and bullnose moved to the Door / Vinyl order. Settings > Cut list > Length materials.
- Room Plan: cover without address / depth / products / doors, colours resolved (never "Default"), door style with a note for other styles; product list as pod blocks (Doors / Interior lines); installation plan footer: drawing, ceiling, top fascia, cornice, runouts written out; one panel list with the pods each part is in (Timber / MDF, Cut, Worktop, Facing, hardware, doors).
- Door / Vinyl Order: new title; 22mm and bullnose sections; worktop views (front always profiled, left / right unless against a wall or fitted between units, back only when Wall back is off; length x depth); door elevations and worktops two to a page.

## 0.68.4 — 2026-10-20
- Door order (PDF and the Doors / Vinyl tab): a **Hand** column - LH / RH for each door.
- Different hinges: only the hinge text is shaded (e.g. "** SC 155"), not the whole row.

## 0.68.3 — 2026-10-20
- Settings > Labels: **View queue** (yellow) for the Zebra and the PDF printer - opens Windows' queue window for it.

## 0.68.1 — 2026-10-20
- PDF printer: the setting is the Brother's network share name again, "BROTHER - Harry Wardrobes"; the plugin finds the printer it belongs to in Windows by its share name (or its Windows name, or \\computer\share). No guessing - a name that matches nothing lists the printers and their share names.
- Settings > Labels: **Find printers** fills a dropdown of this computer's printers (with their share names) for the PDF printer, and of the shared ones for the Zebra - pick instead of typing.

## 0.68.0 — 2026-10-20
- Workshop HubSpot tab: tick what to do - **Send to HubSpot**, **Print labels (Zebra)**, **Print PDFs** - all ticked to start; the button says what it'll do (e.g. "Print PDFs"). The summary box lists only what was done.

## 0.67.6 — 2026-10-20
- Updates: test builds in the Dev folder (beside Updates) are found too - at start-up and by Check for updates - and marked "(test build)". Settings > General > "Also offer test builds" (on). When you're ahead of the released version it says so instead of "You have the newest version".

## 0.67.5 — 2026-10-20
- PDF printing is single sided by default, whatever the Brother's own default is - Settings > Labels > PDF printer > Sides (single / double long edge / double short edge).

## 0.67.4 — 2026-10-20
- PDF printing: the printer is found in Windows by name (case / spacing forgiven) - a wrong name says which printers there are; SumatraPDF is called with Windows paths and its result is logged. Settings > Labels > PDF printer > **Test print** (one A4 page).
- Send to HubSpot + print: the prints go even if the HubSpot upload fails, and a box at the end says what was sent and printed (and what went wrong).

## 0.67.3 — 2026-10-20
- HubSpot: archived (hidden) dropdown answers are no longer offered - Survey tab, Send to HubSpot, Settings. A Room whose current answer has since been archived still shows it, marked "(archived)", so it isn't lost by accident. Hidden Room fields aren't offered under Settings > Survey questions > Add a Room field.

## 0.67.2 — 2026-10-20
- Doors / Vinyl tab and the door order PDF: when doors have different hinges, the usual type stays plain and each other type is shaded grey with a mark (* lightest, ** darker, *** darker again) and bold, with a key at the top - readable in black and white. PDF hinge column: SC = Soft Close.

## 0.67.1 — 2026-10-20
- Workshop "Before you start": doors drawn with hinges that aren't the ones they should have now (their own, the stable wardrobe big door's 155, or the job's) are listed and redrawn in one click (style kept). Save Workshop Pack waits until they're right.

## 0.67.0 — 2026-10-20
- Hinge type per door: right-click doors > HW Door Style > Hinge > Soft Close 110 / 155, PTO 110 / 155, or "the job's". Kept on those doors (like a right-click style) - changing the job's hinge type in the Door style window leaves them as they are. The door order, Room Plan, hinge totals and HubSpot counts follow each door's own hinges; handles follow PTO per door.
- Stable wardrobe: the big door (WST_DOOR) gets Soft Close 155 hinges by default (settings "hinge_defaults").

## 0.66.1 — 2026-10-20
- HubSpot: dropdown, yes / no and checkbox fields are sent as HubSpot's internal option values ("pending"), not the labels ("Needs Ordering") - every send to the Room (Workshop, Send to HubSpot, pictures, Survey) goes through the same check. Fixes "Needs Ordering was not one of the allowed options".
- Workshop HubSpot tab: order statuses are read and compared by label ("Ordered" stays locked), and dropdown fields show their labels.

## 0.66.0 — 2026-10-20
- Workshop **Survey** tab (left of Check): the Room's survey questions, read from HubSpot each time and saved back with **Save to HubSpot** (only what you changed). Dropdowns, checkboxes, yes / no, numbers, dates and text as in HubSpot. **Reload from HubSpot** and **Open in HubSpot** buttons. Not linked / design visit: a Link / Connect button.
- Settings > HubSpot > Survey questions: the list (Room field names, in order); **Add a Room field...** picks any existing Room field; **New question in HubSpot** makes a new Room field (text, paragraph, number, dropdown, checkboxes, yes / no, date - you confirm first) and adds it.
- HubSpot tab: **Open in HubSpot** next to Send to HubSpot + print.

## 0.65.1 — 2026-10-20
- Workshop, HubSpot tab: a file that isn't linked (or a design visit with no Room yet) gets a **Link to HubSpot... / Connect to a Room...** button - the customer's project, then its Room (or Design Visit). The Workshop opens again once it's linked.
- The "Before you start" box also offers linking when the file has no HubSpot customer (done last, in its own window).

## 0.65.0 — 2026-10-20
- PDFs (door order, parts list, Room Plan): Customer as "WILLIAMS, Rebecca" (the HubSpot contact), Room (the Workshop room name), Drawing X<Room ID> and Account HW<HubSpot contact ID> on every one; the date is gone from the top. Door order / parts list: one "Customer | Room | Drawing | Account" line under the title.
- Save Workshop Pack needs the file linked to its HubSpot customer (a Room or a design visit).

## 0.64.3 — 2026-10-20
- Parts list: hardware-tagged items with no colour (cable outlets, hinges...) count as hardware (the HARDWARE material), and things outside every colour group - switches, sockets, room items - aren't parts at all, so neither is reported as "no colour".

## 0.64.2 — 2026-10-20
- Parts list: a part with no colour of its own now takes the job colour of its colour group - its own tag, else the nearest tagged unit above it (e.g. an untagged shelf inside a BOOKCASE) - resolved as the Colours window does (Default exterior / interior / worktop = the door colour). So with the door colour Mussel and the rest Default, those parts count as Mussel instead of being left out.
- Checks box: names the parts that still have no colour, and shows "Default (Mussel)" so it's clear what Default means.

## 0.64.1 — 2026-10-20
- Workshop: the title and the line under it are gone - the tabs start at the top of the window.

## 0.64.0 — 2026-10-20
- **Pod numbers**: "T numbers" are called Pod numbers everywhere (Workshop, Settings, labels, Room Plan, label editor). The plan tag is now Pod_numbers (the old T_numbers tag is renamed when it's next used). The codes themselves (T1, W1, B1...) are unchanged.
- Workshop checks box: parts with no colour can be fixed too - pick the job colours (door, exterior, interior, worktop) and they're applied as in the Colours window, then the Workshop reopens. Not offered on the library master (it has no colours on purpose).
- **Save Workshop Pack is blocked** until the lists are complete: scribes off, parts left out (no colour / colour not set up), full sheets not entered, parts bigger than the sheet, or a board with no sheet size. The button is greyed with the reasons; a thickness outside the standard list is still only a warning.

## 0.63.0 — 2026-10-20
- Workshop opens with a **Before you start** box when something can be put right straight away: scribes off (turned on for every unit with the job's runouts) and colours not set up as a sheet good or hardware (pick Sheet good / Hardware / Leave out for each - known board colours are pre-set). **Fix and reopen** does them in one go and opens the Workshop again; parts with no colour at all are listed to paint. "Not now" carries on.
- Floor plan: hardware is left off the plan picture (Floor Plan tab and the Room Plan PDF) - Settings > Floor plan > Hidden on the plan (hinges, shelf brackets, drawer runners, cable outlets, hanging rails by default). Scenes aren't changed.

## 0.62.0 — 2026-10-20
- HubSpot **Design Visit**: a project with no Rooms can be linked as a design visit (customer only) - "DESIGN VISIT - <customer>.skp". Opening it again checks the project: once a Room exists it asks which one ("Not now" asks again next time) and saves the file as that room's SURVEY file, linked to it (the design visit file is left as it was). If HubSpot can't be reached it says so - try again. Labels / Room Plan take the customer from HubSpot (Room ID made up until there's a Room).
- All PDFs (door order, parts list, Room Plan) are A4 portrait; table columns fit the page (door order: Mid / Hng / TIP / Hdl, explained in the header).
- Check tab: labels on the left third, the PDFs (list on top, viewer below) across the other two thirds; labels aren't previewed again. The first PDF opens after Save Workshop Pack.
- Label: the part's outline (its own shape, larger) top right; the part number (same size) bottom right, right-aligned to the left of the barcode, both right-aligned. Barcodes use Code 128 automatic code sets (digit runs packed), so long HubSpot Room IDs keep 2-dot bars.

## 0.61.0 — 2026-10-20
Workshop:
- Labels tab renamed **Check**: labels stacked down the left, a preview in the middle (click a label or a PDF), and this model's latest PDFs (door order, parts list, Room Plan) on the right.
- **Save Workshop Pack** is only on the Check tab. It makes the PDFs and the labels (saved next to them as LABELS_vN_....zpl - exactly what prints). The HubSpot tab stays greyed out until the pack is saved (and again after the model is re-read).
- HubSpot tab: one **Send to HubSpot + print** button - uploads the pack and updates the Room, prints the labels on the Zebra and the PDFs on "BROTHER - Harry Wardrobes" (no dialog; needs SumatraPDF, free). A printer that can't be reached doesn't stop the rest - it's reported. The Save buttons are gone from the other tabs.
- Labels only ever go to the Zebra (A4 label layout removed; the Brother prints the PDFs only). Settings > Labels: PDF printer name and SumatraPDF path.
- Customer and Room ID come from the HubSpot link and can't be edited (not linked: from the customer folder, as before). The room name is asked for when the Workshop opens and the file hasn't got one, and can be changed on the Check tab.
- New label layout: T number and "1 of 2" small top left, part number big top right, part name, length x width, material / thickness, OpenCutList's outline picture (edged sides thick) with customer / room beside it, barcode along the bottom with no text under it. Grouped labels: name, H number, Qty, timber lengths, T numbers.

## 0.60.1 — 2026-10-20
- Labels: long values (grouped labels' names such as "Bookcase shelf pegs") shrink to fit the label width, on screen and on the Zebra, instead of running off the edge / printing over themselves.

## 0.60.0 — 2026-10-20
Labels (Workshop > Labels):
- Part numbers 1, 2, 3... across the whole room file (identical parts share one), kept on the parts so they stay the same when the list is made again; new parts get the next number. "Renumber parts" starts again from 1.
- T number printed left of the part number ("T3  12"); labels print in T number then part number order.
- Customer and room on every label: SURNAME INITIALS, Room ID, room name - from the HubSpot link, else the customer folder / file name (the Room ID is then made up once, {SUR}{YYMMDD}{NN}, and kept). Editable in the Labels tab.
- Grouped labels: hardware, timber and the names in Settings > Labels (L_BRACKET, HINGE*...) get one label per name with the total and the T numbers it's for; any part can be switched for the job. 2x1 timber: one "2x1 Timber" label with the number of 2100 / 2400 stock lengths (first fit) and the cut lengths. Timber (dimensional) now in the parts list (Hardware tab, parts PDF).
- Code 128 barcode on every label: HW-{ROOM_ID}-{PART_NO} (grouped: H1, H2...), kept on the parts. JsBarcode bundled - no internet needed.
- Zebra GK420D: layouts set to the Zebra print straight to it as ZPL (shared as ZEBRA in Windows) - no print dialog, so no blank first label after the Brother. Settings > Labels > Test print.
- Label layout editor (Edit layout), ported from OpenCutList: drag fields on a grid, sizes, anchors, rotation, barcode, free text, lines; page size, margins, columns / rows and printer; named layouts kept in the settings; live preview of the first 3 labels. Starter layouts: Zebra 102 x 76 and A4 sheet (Brother).
- Print: all, grouped only, one T number or chosen part numbers.

## 0.59.0 — 2026-10-20
- Part types, like the front types: a part's Workshop section is kept on its component - Worktop, Bullnose / cornice (vinyl), 22mm white back or Sheet goods - and wins over the name / thickness rules, so the linen press and drawer unit worktops (18mm / 25mm) go in the Worktops tab. Right-click a part > HW Door Style > Part type (or Automatic).
- Library V32: WRKTP, LIN_WORKTOP and EXT_DRW_WORKTOP marked Worktop; WRKTP_FACING marked Sheet goods (it matched "WRKTP" before).

## 0.59.0 — 2026-10-20
- 

## 0.58.0 — 2026-10-20
- Front types: what a door, drawer front, internal drawer front or fixed panel is now kept on the component itself (hidden data on its definition), so it travels with every copy, export and job file whatever the component is called. The plugin reads it first and only falls back to the names in Settings > Doors for components without one (older job files keep working). Tags stay for showing / hiding.
- Right-click a component > HW Door Style > Front type: Door, Drawer front, Internal drawer front, Fixed panel (no hinges / handles), Not a front, or By name. New components no longer need adding to Settings.
- Library V32: every door (15), drawer front (8), internal drawer front (2) and the stable panel (fixed) marked.

## 0.58.0 — 2026-10-20
- 

## 0.57.0 — 2026-10-20
- Key for the reference letters (T Tall units, W Wall / bridge units, B Base units, L Drawer units, F Facings, M Miscellaneous) at the top of the Product List and along the bottom of every Room Plan and door order page - only the letters used in the job. Wording in Settings > Product list > Letter key.

## 0.57.0 — 2026-10-20
- 

## 0.56.0 — 2026-10-20
- Product List: facing blocks are listed as products, F1, F2, F3... (no longer skipped), and external drawer units are L1, L2, L3... (were B). Settings > Product list > Reference letters; saved settings are brought up to date.
- Product names match components with more after a space or bracket too ("EXT_DRAWER (Fitted)" is a Drawer unit).

## 0.56.0 — 2026-10-20
- 

## 0.55.0 — 2026-10-20
- Fix: a door or drawer front that was already styled kept its old drawing when its unit changed size (wider drawer unit, new height, runouts, ceiling, depth) - the drawing was stretched to fit, so Shaker frames and mid-rails came out wrong, and applying the Door style window didn't redraw it because the style hadn't changed. Now any styled front whose size has changed is drawn again: by the Door style window, and straight after the pencil / Scribe window, the ceiling height and Depth resize a unit (colours put back too).

## 0.55.0 — 2026-10-20
- 

## 0.54.0 — 2026-10-20
- Plan tags in the "dimensions / labels" tag folder: plan dimensions on room_dims, plan notes on plan_notes, T numbers on T_numbers, the doors view on door_elevation (Settings > Floor plan / Product list; folder in Settings > Floor plan). The old "Plan notes", "Plan dimensions", "T numbers" and "Door elevation" tags are renamed, or their items moved onto the tag that's already there, the next time they're used.
- Only tags the plugin made are switched to show in the plan / doors scenes only - room_dims, which has your own room dimensions too, keeps your scene settings.

## 0.54.0 — 2026-10-20
- 

## 0.53.0 — 2026-10-20
- Doors view clearer: no overall height at the ends; each front's height is written in it (in the top panel of a door with a mid-rail, so the rail stays clear); widths under the bottom row and over every other front (the linen press doors above the drawers, top box doors); the mid-rail centre reads "815 (mid-rail)"; each product's T number under its doors.
- Linen press drawer fronts are framed like the doors above them (the door frame all round, e.g. 100) - Settings > Doors > Drawers framed like doors (LINEN_PRESS). Shown that way in the doors view too.
- Fix for library V30: the top box's lower door subtracted the shelf depth instead of the top door height, so the top doors ran 80mm into the top facing (fixed in the component; lower door 1558, top 460).

## 0.53.0 — 2026-10-20
- 

## 0.52.0 — 2026-10-20
- **Doors view** (Workshop > Floor Plan > Doors view): the doors and drawer fronts on each wall drawn flat, front on, with their sizes - widths along the bottom (and along the top for doors above drawers), the overall height at each end, the height of any door that isn't full height, each drawer front's height, the mid-rail width on each door and the mid-rail centre (from the bottom of the door) on the first. A drawing per wall on the "Door elevation" tag, below the floor, and a front-on flat scene for each ("Doors", or "Doors - back wall" / "- left wall"... for more than one wall) - the tag shows only in those scenes. Made again each time, like the T numbers.
- The door elevation is also a page per wall in the Room Plan (after the Installation Plan) and on the door order PDF.

## 0.52.0 — 2026-10-20
- 

## 0.51.0 — 2026-10-20
- Stable panel and linen press drawers line up with the door style's mid-rail: stable panel = mid-rail centre - half its width - margin (Shaker 815 / 100: 763), and the linen press drawer fronts share the same height between them ((763 - gaps) / 3 = 253). The door above starts level with the bottom of the mid-rail on the doors beside it. Needs Components V30+ (Mid-rail centre / width in Component Options; "Stable panel height" still overrides, 0 = auto).
- The mid-rail centre and width are copied from Settings > Door styles (the job's door style, or Shaker when the doors are flat) when a unit is placed from the + window and when the Door style window is applied; units that change are redrawn and their doors / fronts restyled at the new size.

## 0.51.0 — 2026-10-20
- 

## 0.50.0 — 2026-10-20
- The stable panel (fixed panels) is always flat, whatever style the job's doors are.
- No mid-rail on the door above the stable panel (WST_DOOR_UPPER), however tall. Settings > Doors > No mid-rail lists the doors that never get one.
- Clean model (Export library) also sets every door and drawer front back to Flat, and export stays locked while any aren't flat.

## 0.50.0 — 2026-10-20
- 

## 0.49.0 — 2026-10-20
- **Stable wardrobe** (WARDROBE_STABLE, Components V29+): a double wardrobe with a fixed stable panel below one door. Its doors are WST_DOOR (full height) and WST_DOOR_UPPER (above the panel, lined up like the linen press door), and the panel is WST_STABLE_PANEL. Each door hinges on its outer edge, whichever side the panel is on.
- Fixed panels (Settings > Doors > Fixed panels, default WST_STABLE_PANEL) are styled, coloured and on the door order like a door ("Stable Panel"), with no hinges, TIP-ON or handles. The Room Plan lists them as "stable panel W x H (fixed)".
- Settings brought up to date: the stable wardrobe's door names and "Stable wardrobe" product type are added to saved settings.

## 0.49.0 — 2026-10-20
- 

## 0.48.0 — 2026-10-20
- **Room Plan**: one PDF, ROOM_PLAN_v<N>_<file>.pdf, in place of the separate installation plan - Cover / Specification (customer, address, colours, door style, hinges, handles, ceiling, top fascia, depths, scribes, cornice), Product List (loose items first, then each ref as "1000 Wardrobe (580 deep / 598 overall)", its doors with LH / RH and 155 hinges flagged, and an interior summary), Installation Plan (plan scene with the footer: client, account, drawing, main ceiling, scribe set L / R / F / C / back, cornice), Pod Sheet (the parts, hardware and doors in each ref) and Panel list (MDF / Timber / Cut / Worktop / Facing, with the refs each panel goes in).
- Every page has the header: customer, room, drawing X<Room ID>, account HW<customer ID>, fit week (the Room's new "Fit week" field in HubSpot) and date, and "Page n of N".
- Saved with the workshop pack and sent to the Room's Floor Plan (replacing the last one). The Floor Plan tab button is now "Save room plan (PDF)".
- References by letter: T tall, W wall / bridge, B base (drawer units, worktops, box ends), M misc - each numbered on its own (T1, T2, W1, B1...). Settings > Product list > Reference letters.

## 0.48.0 — 2026-10-20
- 

## 0.47.0 — 2026-10-20
- **Floor Plan** tab in the Workshop (next to the Product List): the plan scene (e.g. "S top") with its notes, dimensions and T numbers; buttons for T numbers on the plan, Dimension the plan (the room and each product's width along the wall - made again each time) and Save installation plan (PDF). Notes are listed to edit or delete.
- Plan notes: right-click a part > HW Door Style > Plan note > a standard message ("81mm FILLER", "CABLE PORT", "BOOKCASE SHELVING 300mm DEEP"...) or Other text. A SketchUp text with an arrow to the part, on the "Plan notes" tag, shown only in the plan scene(s). {size} {width} {depth} {height} fill in from the part. Messages are edited in Settings > Floor plan (new section, with the plan scenes, tags and distances).
- INSTALLATION_PLAN_v<N>_<file>.pdf: "Installation Plan" with the ceiling height and top fascia and the plan picture. Saved with the workshop pack, and Save + send to HubSpot adds it to the Room's Floor Plan (replacing the last plan, keeping the survey pictures).

## 0.46.0 — 2026-10-20
- **Depth** on every unit: back wall to the back of the facing (finished depth adds the facing / door, e.g. 580 / 598). Standard 580, bridge units / worktops / box ends 500 (Settings > Components, with own depths for box shelves and the bookcase). New units from the + window get it; the Scribe / runout window has the job's depths (standard and bridge / worktop) and sets every unit; right-click > HW Door Style > Depth changes any unit (standard, bridge / worktop, job depth for each, or a number).
- Library components (from Components V29): Depth in Component Options in place of the old depth boxes - a wardrobe's floor / divider and shelf depth follow it (shelves keep their setback, the linen press worktop its gap), the bridge / box shelf / box end / end panel / bookcase / worktop depth follows it (less the back runout). Axis at the back-left corner on the floor, so units go straight against the wall and changing Depth moves the front only. Units already in job files keep their old axis.
- Product List depth / finished depth reads the new Depth option.

## 0.45.0 — 2026-10-19
- **Product List** - new first tab in the Workshop: every product in the job (wardrobes, bridge units, worktops, drawer units, box shelf sections, bookcases...) with a T number (T1, T2...), its name (type + width, e.g. "Wardrobe 824"), size W x D x H, and depth / finished depth from the component (e.g. 570/588 - back wall to the back of the facing / to the front of the door). Facings, bullnose, end panels, floor and ceiling aren't products.
- Parts that belong to a product join it automatically: internal drawers / shoe pull-outs in a wardrobe, a box end under a worktop, the bridge frame on its skeleton; box shelves / box ends next to each other make one section. Units side by side stay separate. Any part can be moved to another product or split off as its own in the Product List (kept with the file).
- T numbers are given left to right the first time and kept on each product after that - a new unit gets the next number; "Renumber left to right" gives them out again. Click a T number to select the product in the model. The library file is never numbered.
- "Show T numbers on the plan": T1 (570/588) over each product on its own "T numbers" tag, shown only in the plan scenes (e.g. "S top").
- Doors / Vinyl tab and the door order PDF: the Unit column is now the product's T number (hover for the component path).
- New Settings > Product list: component -> product name, parts that join another product, never-products, depth options, front thickness, number prefix, plan label tag and scenes.

## 0.44.4 — 2026-10-19
- Workshop window: Refresh and Open folder on the left of the bottom bar, the two save buttons on the right; no Close button (close the window itself).

## 0.44.2 — 2026-10-19
- Workshop: 22mm panels (e.g. Frost White 22 mm) are on the Doors / Vinyl tab under "22mm (White Back)" - ordered with the doors, so they're out of Sheet goods and the MFC sheet count. Same in the parts list PDF.
- Default 1000 x 2800 cut + edged colours: Cashmere, Dust Grey, Frost White, Light Grey, Lissa Oak, Opera Walnut.

## 0.44.1 — 2026-10-19
- Door order and parts list are saved as PDF only by default (Export door order, Workshop window, and the files sent to HubSpot). Settings > Export > "Also save CSV files" turns the CSVs back on.

## 0.44.0 — 2026-10-19
- Product pictures are kept on this computer (AppData\HW Door Style\product_images): the Door style window and Settings > Products show them straight away and offline - nothing is loaded from the internet when a window opens. Missing (or changed) pictures are copied down once in the background, after the products are read from HubSpot or when a window that shows them opens.
- Door style window: **Browse** next to each handle (or click its picture) opens a picture gallery to look through with the customer - one card per family (e.g. Bergamo Knob, not every finish and size), with search. Pick a family to see it large with its finishes (each with its own picture) and sizes, then "Use this ..." fills in the handle. N/A is there too.

## 0.43.0 — 2026-10-19
- Door summary: a door with a mid-rail is a "Wardrobe Door", and Mid-rail says where it is - "Yes - 815mm" (the mid-rail's centre above the bottom of the door, from the style).
- Workshop tabs: Doors / Vinyl (was Door order) also lists bullnose and cornice; new Worktops tab (22 / 25 mm worktops, with their own sheet count, not counted in the MFC sheets sent to HubSpot); Sheet goods; Drawer Boxes (in place of Edging - the drawer boxes come off the Hardware tab); Hardware; Labels; HubSpot. Edging is at the bottom of Sheet goods.
- Drawer Boxes tab: #, Parent (the drawer unit, e.g. EXT_DRAWER#1), Material, Internal cabinet width (box width + the box clearance each side), Height (a warning under 100 mm), Runners (e.g. "410mm Hook/Peg Drawer Runners" - one pair per box; the type is Settings > Components "Drawer runner type") and Quantity. Pull-outs with runners but no box get a row too. The runners come off the Hardware tab.
- Parts list PDF follows the same split: worktops, bullnose / cornice and drawer boxes in their own tables.
- HubSpot worktop order status: needs ordering when the parts list has a worktop (a part named WRKTP / WORKTOP at 22 or 25 mm).

## 0.42.2 — 2026-10-19
- Cable outlets go to HubSpot: the Room card's "Cable Outlet Quantity" (and the Workshop window's HubSpot tab) is filled from the cable outlets showing in the model - a WORKTOP's outlets that are switched off in its options don't count.
- Parts list: a hardware component made of sub-parts (like a cable outlet with its rim and lid) is listed as the one piece of hardware, not its parts. (CABLE_OUTLET_80 in the library is now one part anyway, so OpenCutList lists it as one too.)

## 0.42.1 — 2026-10-19
- New Settings > Components "Worktop height (mm)" (default 771, the height of the half units): the bottom of every WORKTOP board. The pencil (and the + window) sets it on each worktop, like the top door height.
- Settings: cable_outlets hardware tag (CABLE_OUTLET_80) in the defaults.

## 0.42.0 — 2026-10-19
- New **Add component (+)** button (first on the HW measure once toolbar): picture cards of the latest version of every library component, grouped and colour coded by category (Wardrobes, Drawers, Bridge, Bookcase, Shelving, Main Components), with search (Enter places the first match; search looks in every category). Click a category to show only that one (All, or the same one again, shows everything). Click a card and the window closes so you can click straight into the model to place it - like File > Import without the file browser; the result shows in SketchUp's status bar. Opening the window checks the library at most every 10 minutes (Check library always checks).
- Works from a copy on this computer (AppData\HW Door Style\library), so the window opens straight away and works offline; each time it opens it checks the library folder and copies any newer versions in the background (old copies replaced, removed components dropped). Library folder: Settings > Export > Add component.
- A placed unit is set up to the job in one quick step, merged with the place (one Undo removes both): runouts and bottom facing as the pencil has them (0 when scribes are off), the ceiling height for Scribed To Ceiling units, the job's door style and hinges on its doors and drawer fronts (once a Door colour is chosen) and the job's colours. Only the new unit is touched, so it stays quick on older computers. Untick "Set up to this job" to place it as it comes from the library.
- Top of unit on every component: the old "Topped off?" and "Up to ceiling" switches were still showing on every component except the wardrobe, because each placed copy kept its own "show this option" setting, which wins over the component's. Those are now hidden too, so every unit shows only the Top of unit dropdown. A unit with only one of the two switches gets the two options that apply to it. Half components (BULLNOSE_HALF, END_PAN_HALF) whose old switches had lost the link to the dropdown are relinked, with the dropdown set to how the unit is drawn.
- Fix: BXEND (and BXEND_HALF) went to the ceiling height with the pencil / ceiling. Its height option has no units, which DC keeps in cm, and it was read as inches - so a 945 mm BXEND looked like 2400 mm and was skipped as already at the ceiling.
- **Job template** for Welcome to SketchUp, saved with Export components (tick "Template"): the library file with no components in it - only the floor (and the ceiling once there is one; Settings > Export > Template keeps) - keeping its units, tags, scenes, styles and materials, with no job settings or export records. Versioned in the library's _TEMPLATES folder (Harry Wardrobes Template V1, V2...; older ones to _old), and only saved again when it changed. It is copied into SketchUp's own Templates folder so it shows in Welcome to SketchUp, and every computer with the plugin picks up the latest version when SketchUp starts.
- Template: "as the default" tick (on by default) next to it in Export components - File > New and SketchUp's start-up file then use the Harry Wardrobes template. Other computers pick it up as their default too when SketchUp starts (unless someone has chosen a different default there).
- **Room setup**: a file without a room asks for it when it is opened (Not now / Don't ask for this file). A new, unsaved job is saved first: customers folder (remembered, starts at 1_CUSTOMERS), customer folder (pick an existing one - newest first - or type a new name) and file name. Then the room width (left-right, red), length (into the room, green) and ceiling height: the floor and ceiling are stretched to the room and the ceiling's underside moved to the ceiling height, and that height becomes the job's ceiling height for units.
- Scribe / runout window: Room size (width x length) next to the ceiling height - Apply resizes the floor and ceiling and moves the ceiling to the ceiling height, even before any units are in the file. The Ceiling height window and a ceiling height taken from HubSpot move the ceiling too.
- New room from HubSpot uses the open file when it is just the template's floor and ceiling (it used to open another new file).
- Add component: the window always closes before the component is put in your cursor, and the model window gets the focus, so you can click straight into the model.
- Settings > updates: a test build newer than the released version now says so, instead of "Up to date (newest in the folder: 0.41.0)".

## 0.41.0 — 2026-10-19
- **Shortening a wardrobe no longer breaks the shelf and rails** (double hanging especially):
  - the top shelf now stops under the top frame rail - before, it ran into the rail once the wardrobe was
    shorter than about 2.1m;
  - the lower hanging rail keeps its drop (950mm) while it fits; on a shorter wardrobe it sits halfway
    between the floor and the shelf, so both hanging sections stay usable instead of the lower rail
    sliding down towards the floor.
  Standard heights are unchanged. Applied to old files when they're opened (only where the original
  formula is still there) and takes effect the next time the unit is redrawn; Export components carries
  it into the library.

## 0.41.0 — 2026-10-19
- 

## 0.40.0 — 2026-10-19
- **"Top of unit"** replaces the two switches "Topped off?" and "Up to ceiling" in the units' Component
  Options (they sounded alike but did different things). One dropdown:
  - **Scribed To Ceiling** - built to the job's ceiling height, top facing scribed to the ceiling;
  - **Custom Scribe Height (Lower Section)** - its own height, top facing still scribed (bulkheads,
    lower sections);
  - **No Upper Facing** - its own height, no top facing and no ceiling runout.
  The old two are kept inside the component (its formulas use them) but hidden and set from the dropdown.
  Units are upgraded when a file is opened, keeping what they were set to, so older job files and the
  library pick it up; Export components carries it into the library files. "height (ceiling)" is now
  "Height (mm)".
- **Scribe / runout window**: units with their own height are listed with a height you can type in
  (no need to stretch them), and the runouts have their own heading.
- Fixed: the Scribe window sent the ceiling height and the ceiling runout under the same name, so the
  height could be replaced by the runout value (e.g. 25) when you pressed Apply.

## 0.40.0 — 2026-10-19
- 

## 0.39.1 — 2026-10-19
- Fixed: the Scribe / runout window cut off the Apply button once ceiling height and bottom facing were
  shown (fixed 400px, no scrolling). It opens taller, can be resized, the fields scroll and Cancel / Apply
  always stay at the bottom. Enter applies.

## 0.39.1 — 2026-10-19
- 

## 0.39.0 — 2026-10-19
- **18mm boards come from cut and edged strips, not full sheets.** Each part uses the next width up
  (a 460mm shelf -> 500, a 60mm filler -> 90), packed end to end along the strip (2800). Widths, length and
  which colours can also be ordered as **1000 x 2800 edged on the long sides** are in Settings > Cut list.
- Parts wider than the widest strip for their colour (or longer than a strip) are listed on the Sheet goods
  tab and you **enter the full sheets needed**; Save + send to HubSpot waits until you have. Counts for
  other thicknesses (22mm panels, 25mm worktops) start from the area estimate and can be changed too.
  Anything you enter is kept with the file.
- New HubSpot field **1000mm Cut and Edged** (cut_and_edged_1000mm_quantity).
- Fixed: the parts list waste % in Settings > Cut list wasn't saved.

## 0.39.0 — 2026-10-19
- 

## 0.38.0 — 2026-10-19
- **Workshop window** replaces the Door summary and Parts list buttons (toolbar: Colours, Door style |
  Scribe / runout, Workshop, Send to HubSpot). Tabs: Door order, Sheet goods, Edging, Hardware, Labels,
  HubSpot. Door summary is still in the menu. OpenCutList stays for cutting diagrams - both read the same
  OpenCutList settings, so letters and counts agree.
- **Save workshop pack**: door order (DOOR_ORDER_v<N>) and parts list (PARTS_LIST_v<N>), PDF + CSV, next
  to the .skp.
- **Save + send to HubSpot**: the four files go in the Room's Order / Parts List, plus (each one shown
  first, untick to leave out):
  - quantities: hinges, TIP-ON, drawers, handles (name, SKU, supplier, quantity);
  - **MFC Sheets - <colour>** (new fields, one per colour + MDF) and MFC (Full Sheet) Quantity (total);
  - **Cut and edged** 90 / 160 / 300 / 500 / 570 / 610mm: parts exactly that wide, packed end to end into
    strips of that colour's stock length (2800 if none) - not counted in the full sheets;
  - **order statuses**: Needs Ordering when the model has it, Not Applicable when it doesn't (doors / vinyl,
    drawers, sheets, hardware, 25mm worktop). Statuses already Ordered / Received / Partially Received are
    never changed - they're flagged so you can check the order still matches.
  - the stage only moves if you tick "Also move the Room to", and only once that stage's required fields
    are filled.
- Strips are on the Sheet goods tab, the parts list PDF and the CSV.

## 0.38.0 — 2026-10-19
- 

## 0.37.0 — 2026-10-19
- **Parts list** (new toolbar button, after Door summary), built on OpenCutList's rules:
  - **Sheet goods** per colour and thickness: every part with its letter, length, width, quantity and the
    edge material on each edge (L1 / L2 along the length, W1 / W2 the ends). Uses OpenCutList's own cut list
    settings saved in the model (letters from A in each group, mirrored parts separate, its sort order), so
    letters and counts match OpenCutList exactly. Doors and drawer fronts (bought-in tag) are left for the
    door summary.
  - **Board count** per colour: part area + a waste allowance (Settings > Cut list, default 20%) over the
    colour's largest stock size; warns about parts bigger than the sheet and non-standard thicknesses.
  - **Edging**: metres of each edge tape.
  - **Hardware** counted from the model (hinges, runners, rails, brackets, drawer boxes...), plus the
    handles from the Door style window with SKU, supplier and quantity.
  - **Labels**: one per piece, drawn from the label layouts saved in OpenCutList (this model's, then your
    saved presets) - number, name, size, material, custom formulas such as @layer / @filename / @batch, and
    the thumbnail with its edges - and printed one label per page at the label size.
  - **Save CSV + PDF** next to the .skp (PARTS_LIST_v<N>_...), and **Save + attach to HubSpot Room**: both
    files go in the Room's new **Order / Parts List** file field (made the first time).
- **Licence:** the parts list and labels adapt OpenCutList by L'Air du Bois (GPL-3.0), so HW Door Style is
  now GPL-3.0 (LICENSE and NOTICE.md in the plugin; credited in the window and Settings > General).

## 0.37.0 — 2026-10-19
- 

## 0.36.0 — 2026-10-19
- **Toolbar tidied:** the Ceiling height button is gone from "HW measure once" (the Scribe / runouts window
  already asks for the ceiling height). Scribe / runouts now sits to the left of Door summary:
  Colours, Door style | Scribe / runouts, Door summary, Send to HubSpot. Ceiling height is still in the
  Extensions > HW Door Style menu.

## 0.36.0 — 2026-10-19
- 

## 0.35.0 — 2026-10-19
- **Export components now requires a clean model.** The window checks the library file when it opens, after
  Clean model, and again when you press Export. Export all / Export selected stay locked while any part
  still has a colour or any drawer is open, and the window says how many (and which drawers). Purging
  unused components stays optional.

## 0.35.0 — 2026-10-19
- 

## 0.34.0 — 2026-10-19
- **Fixed: pictures from Import from supplier didn't show** in Settings > Products or HubSpot. The download
  treated pictures as text and damaged them on the way in. Pictures are now copied byte for byte, saved
  with their real type (JPG / PNG / WebP), and anything that isn't a picture is turned away. JPG or PNG is
  asked for first, so they also work in HubSpot quotes.
- The 74 products already imported had their pictures copied again from each product's page.

## 0.34.0 — 2026-10-19
- 

## 0.33.0 — 2026-10-19
- **Delete products** in Settings > Products:
  - One at a time: open a product and press Delete (then click again to confirm).
  - Several at once: Select to delete, click the cards (or Pick all shown after filtering), Delete N, click
    again to confirm.
  - They go to HubSpot's recycle bin, where they can be restored for 90 days. Jobs that already use a deleted
    handle keep its name, SKU and supplier.
- Product cards show the finish on one line again.

## 0.33.0 — 2026-10-19
- 

## 0.32.0 — 2026-10-19
- **Handles can be N/A** on the Door style window (Robe, Drawer and Interior handle). N/A sends "n/a" as the
  handle name and SKU, N/A as the supplier, and 0 as the quantity to the HubSpot Room; the door summary
  counts no handles for it either.
- **Handle pickers go Handle / knob, then Finish, then Size** - only the finishes (and sizes) that product
  actually comes in are offered. Size only shows when a finish comes in more than one size. Apply won't
  run until the finish/size is chosen.
- Handles4u added to the product Supplier list; Handles4u and N/A added to the Room handle-supplier fields.

## 0.31.0 — 2026-10-19
- **Products are grouped by range: Range - Finish - Size** (e.g. "Venice Handle - Aged Brass - 128mm").
  - Import from supplier works out the range, finish and size of every item (HPP from its tables; others from
    the name) and shows them under a heading per range, each card showing the finish and size, with a
    "Tick range" button. Products are added to HubSpot with that name.
  - Settings > Products now looks the same: picture cards grouped by range, filter by text or category,
    click a card to edit it.
  - The Door style handle dropdowns are grouped by range too.
- **Paste a page address** in Import from supplier (any supplier: a category or a product page) and choose
  its supplier. HPP, Interfit and Handles4u addresses use their own readers; other sites are read from the
  page's product data (name, SKU, picture, price).

## 0.30.0 — 2026-10-19
- **Import from supplier** (Settings > Products): reads HPP, Interfit and Handles4u's handle and knob sections from
  this computer - following every sub-category and numbered page - and lists each item with its picture,
  name, SKU, supplier link and website price. Filter by group or text, click the ones to keep, tick their
  categories (e.g. Robe handle + Drawer handle), then Add to HubSpot: each becomes a Non-inventory product
  with the supplier set, the link copied and the picture copied into HubSpot. Items already in HubSpot are
  marked. Optional: fill Cost with the website price (usually retail - check it).
  - HPP: each code from the family pages (e.g. H200.032.CH) with the picture for its finish.
  - Interfit: the exact SKU is read from the product page when it's added.
  - Handles4u: needs "Handles4u" in HubSpot's Supplier list for the supplier to be set.

## 0.29.0 — 2026-10-19
- **Renamed scenes stay in step with Settings.** Rename a scene in the Scenes panel and every setting that
  names it is renamed too - for now Settings > HubSpot > Pictures to HubSpot (the scenes ticked to start).
  If the Settings window is open its fields change as well. Scenes are followed by their id, so a rename
  is never taken for a new scene.
- HubSpot Products are connected (e-commerce permission): the Supplier and Category product fields and the
  Robe / Drawer / Interior Handle Supplier Room fields are in HubSpot.

## 0.28.0 — 2026-10-19
- **Settings > Products**, kept in HubSpot's Products: name, SKU, category (Robe / Drawer / Interior handle,
  Hinge, TIP-ON, Drawer box, Drawer runner, Mirror, Cable outlet, Other hardware - tick as many as fit),
  supplier, product type, price, cost, supplier link and a picture. Save to HubSpot creates or updates the
  product straight away. Read from HubSpot brings in products (and suppliers) added or changed there.
- New HubSpot fields (made the first time you press Read from HubSpot): product Supplier (Integral, HPP,
  Interfit - add more in HubSpot), product Category, and Robe / Drawer / Interior Handle Supplier on the Room.
- **Door style window: handles are dropdowns** of the products in each category; the SKU and supplier fill in
  and can't be edited. Handle names entered before stay until you pick a product.
- Send to HubSpot sends each handle's supplier to the Room, next to its SKU, so whoever orders knows where from.
- Needs the HubSpot key's e-commerce (Products) permission - Settings > HubSpot > Test connection shows it.

## 0.27.0 — 2026-10-19
- **Hinges on the correct side.** Double doors: the left door is hinged on its left edge, the right door on its
  right. Single door: new unit option "Hinge side (single door)" (Left / Right), added next to Double / Single
  the first time the unit's doors are drawn. TIP-ON goes on the opposite edge. These are component formulas,
  so changing Double / Single or the side in Component Options moves the hinges when the unit redraws.
  Existing jobs: press Apply in the Door style window (or Rebuild styles) once to redraw the hinges.
- **Tags:** every door is on the DOOR tag (two were on Layer0), hinges stay on "hinges", and scenes that hide
  DOOR (D internal, S front internal...) now hide "hinges" too - so D internal no longer shows hinges.
  Scenes named HARDWARE / HINGE are left alone.
- **Updating shows a progress window** (installing, then loading each file) instead of looking frozen.
  It appears from the next update after this one.

## 0.26.0 — 2026-10-19
- **Two toolbars.** "HW measure once": Colours, Door style, Scribe / runout, Ceiling height | Door summary,
  Send to HubSpot. "HW dev": Settings, Export components. (The old "HW Door Style" toolbar is gone.)
- **Door style window** (replaces the Shaker and Reset buttons), laid out like Colours:
  - A style for Doors, Drawer fronts and Internal drawers (internal drawers can now be styled; Flat by default).
  - Hinge type for the job (moved here from the menu).
  - Handles for the job: on push-to-open doors, on internal drawers, two handles above a width, and the
    robe / drawer / interior handle names and SKUs (sent to and taken from HubSpot).
  - Apply redraws only what changed, with a progress bar, as one undo step. Items styled by right-click keep
    their style (the window counts them; tick to put them back). Right-click > Follow the Door style window too.
- **Door styles in Settings > Doors.** Flat, Shaker and the HubSpot range (Ascot, Esquire, Halstead, Juliette,
  Keswick, Sutton, Vienna, Cairo Traditional, Caraway) plus Avienda. Each style has its own frame, recess
  and mid-rail sizes (Shaker 815 mm, Ascot 820 mm) and a Handleless tick. A style can only be chosen once the
  plugin can draw it and all its sizes are filled in - for now Flat and Shaker. Add, rename and reorder here.
- Handleless styles count no handles. Handle rules in Settings are the defaults for new jobs.
- Your Shaker sizes moved onto the Shaker style automatically (settings version 4).

## 0.25.1 — 2026-10-19
- Fixed: "Can't reach HubSpot (ECONNRESET)". About 1 in 4 new connections from this computer were being
  cut off straight away (by the network or security software). The plugin now keeps one connection
  open and reuses it, and if one drops it reconnects and tries again (up to 5 times).

## 0.25.0 — 2026-10-19
- **Progress bars instead of "Not Responding".** Slow jobs in the HubSpot windows now run one step at a
  time with a bar along the bottom of the window saying what is happening (and "3 of 7"):
  - Pictures: making each picture, uploading each file, putting them on the Room.
  - Send to HubSpot: the window opens straight away, then reads the fields, measures the model and
    reads the Room; Send shows each step, and if a step fails the window stays open to try again.
  - New room / Link: searching and reading the rooms.
  - Settings > HubSpot: Test connection, Show Room fields, Load stages and fields.
  Buttons wait while the bar shows.

## 0.24.2 — 2026-10-19
- Picture files are named "<room> - view 1, <SURNAME> <First names>", e.g.
  "Master Bedroom - view 3, HASPREY Kenny.jpg". Views count up across every picture made and carry
  on from the highest number already in the folder, so earlier pictures are never overwritten.
- The customer's first and last names are kept on the link (files linked before use the last word
  of the customer's name as the surname).

## 0.24.1 — 2026-10-19
- Fixed: Upload to HubSpot stopped with "Invalid JSON for options input". Pictures are now uploaded
  as private files (only people signed in to HubSpot can open them).

## 0.24.0 — 2026-10-19
- **Pictures to HubSpot** (HubSpot menu, or Pictures... in the Send window):
  - Tick the scenes for Renders, Survey Floor Plan and Survey Door Dimensions, then Make pictures.
  - Each scene is saved as an image next to the .skp (SURVEY RENDERS folder) and shown in the window.
  - Untick any you don't want, choose Replace or Add for each field, then Upload - they go onto the Room.
- **Required fields per stage.** Settings > HubSpot > Required to move on: tick the fields each Room
  stage needs. The Send window shows the Room's stage, which stage you're getting ready for, marks the
  required fields * and won't send until they're filled in (pictures included).
- Settings > HubSpot > Pictures to HubSpot: scenes ticked to start, picture size, JPG / PNG, folder,
  replace or add, and the HubSpot files folder.

## 0.23.0 — 2026-10-19
- **Send to HubSpot is now the whole Room card**, in the same sections as HubSpot (Survey Questions,
  Colours + Style, Hardware, Blum Hinges, Drawer Boxes, Order List, Installation, Delivery, Object
  Dimensions, plus Survey (SketchUp)). Every field is shown, including 0 and empty ones, and can be edited.
  - Values worked out from the model are marked SketchUp; Use HubSpot's / Use SketchUp's swaps them.
  - Green = changes HubSpot, blue = changes this file. Review changes lists old -> new before Send.
  - Fields HubSpot fills from the Project are shown but not edited here.
- Room width / depth now measure the FLOOR as drawn, including any scaling.
- Exterior, interior and worktop colours are sent too (a Default row sends the door colour, as painted).
- Open Room and Open Project buttons (and menu items).
- Your own toolbar icon: put hubspot.svg or hubspot.png in %APPDATA%\HW Door Style\icons.
- Settings > HubSpot > Test connection also checks Users (for Installer / Surveyor names).

## 0.22.0 — 2026-10-19
- **One SketchUp file = one HubSpot Room.** New menu Extensions > HW Door Style > HubSpot (and a toolbar button):
  - New room from HubSpot: search by customer, address or room name, pick the Room - the survey file
    is saved in the customer's folder in 1_CUSTOMERS (found by the contact number) as
    "SURVEY - room - customer.skp" and linked to the Room.
  - Link this file to a HubSpot room: the same for a survey file that already exists.
  - Send to HubSpot: this file's values next to HubSpot's, nothing written until you press Send.
    Each line can be sent, taken from HubSpot (ceiling, bottom facing, runouts, colours) or left.
  - Sent: room width and depth (FLOOR), ceiling, bottom facing, runouts and units set differently,
    door / exterior / interior / worktop colours, hinges by type, TIP-ON, drawers, handle counts.
  - Shown from HubSpot: door style, handles and their SKUs.
  - Open this room in HubSpot.
- New Room fields in HubSpot (group "Survey (SketchUp)"): Room Width, Room Depth, Bottom Facing,
  five runouts and Runout Exceptions.

## 0.21.0 — 2026-10-19
- **HubSpot connection** (Settings > HubSpot), read-only for now:
  - Paste the private app key (the one Measure Once used); it is kept on this computer only,
    never in settings backups or team settings, and only its first and last characters are shown.
  - Test connection shows the HubSpot account and whether the key can read Contacts, Rooms
    (Listings), Projects, Notes and Files - anything missing says so.
  - Show Room fields lists your own Room fields, ready for matching to the survey data.
- Retries when HubSpot is busy, with plain-English messages for a wrong key or a missing permission.

## 0.20.0 — 2026-10-19
- The plugin's Google Drive folders are now together in Harry Wardrobes\_HW Door Style:
  - Updates (was _plugin_updates) - the updates folder setting moves there on its own.
  - Colours (was HW Colours) - the colour pack.
  - Team settings - Load team settings opens here the first time.
  - Dev - test files.
- Export components skips every folder starting with _ (no special case for HW Colours).

## 0.19.0 — 2026-10-19
- **Bottom facing (plinth) is a job value**, like the ceiling height: set it in the pencil
  window for every unit (default 79 mm, Settings > Scribe & ceiling).
  - One unit different: right-click it > HW Door Style > Runouts / bottom facing.
  - Works on every component with the option, including internal drawers and the shoe pull-out.
  - The door summary flags a unit whose bottom facing differs from the job.
- Component library (Components V22): the "bottom" option is hidden in Component Options on
  every component (the value stays, so formulas keep working).
- New test suite: bottom facing (every unit takes 120 mm and goes back exactly).
- First version delivered through the updates folder.

## 0.18.0 — 2026-10-19
- **Updates without uninstalling or restarting**: Settings > General > Updates.
  - New versions are saved to the updates folder on Google Drive
    (Harry Wardrobes\_plugin_updates); SketchUp offers a newer one a few seconds after it
    starts (once per version), or press Check for updates.
  - Update now installs over the old version and loads the new code straight away.
  - Install from a file... does the same for an .rbz you downloaded.
  - New toolbar buttons or menu items from an update appear after the next restart.
- Developer > Reload plugin code uses the same reload.

## 0.17.0 — 2026-10-19
- **Set up OpenCutList** (Settings > Cut list): one button, one undo step, on the open model.
  - Board colours: sheet good, 18 / 25 mm (the 22mm Panels colour also 22 mm), stock 2800 x 2070
    sheets plus your pre-cut strips (90 / 160 / 300 / 500 / 570 / 610 / 1000), woodgrains marked
    grained - the same as you had set up by hand in Components V22.
  - Interfit drawer box finishes and HARDWARE (hinges, TIP-ON): hardware - counted, not cut.
  - Door and drawer front parts tagged "bought-in" so they can be filtered off the cutting
    diagrams (new Shaker parts are tagged as they are made).
  - Only fills in what's missing; tick "Also replace" to overwrite settings that differ.
- Cut list section shows each material's state (already set / not set / set differently) and
  warnings: scribes off, no colours chosen, untagged doors, materials not set up.
- Board thicknesses, stock sizes and the bought-in tag are settings.
- Grain: OpenCutList runs it along each part's longest side and never rotates a grained part,
  so tall doors and panels come out vertical and wide drawer fronts horizontal.
- New test suite: cut list (set-up, tags, second run changes nothing).

## 0.16.0 — 2026-10-19
- **Developer menu** (Settings > General > Developer mode, then restart SketchUp): Run tests,
  Inspect selected component, Reload plugin code, Ruby Console.
- **Tests inside SketchUp**, with a results window: doors, runouts (every unit takes 25 mm and goes
  back exactly), ceiling (heights, top doors, bridge lined up with TOPBOX), colours and export.
  121 checks on Components V22; the model is never changed.
- Safety net: a step that would open inside a test or an export copy is refused instead of
  quietly committing.
- Build: runs the tests first, warns if the changelog has no entry, `--bump` sets the next version.
  Tests and build also run on GitHub for every push.

## 0.15.0 — 2026-10-19
- **New Settings window**: sections listed down the left - Doors, Hinges & handles, Components,
  Colours, Tags, Scribe & ceiling, Export, Cut list, General.
- Checks before saving: wrong values are marked in red with a note, the section gets a dot, and
  Save explains what needs fixing (e.g. a runout default that isn't in the dropdown list).
- Shows "Unsaved changes"; Cancel or closing the window asks before throwing changes away.
- **Default hinge type** for new jobs (Hinges & handles).
- **Default colours** for new jobs, and what "Default" means on the 22mm Panels row, are now set in
  Settings > Colours (the Colours window's "Save as default" button is gone).
- Scribe & ceiling shows this job's state (scribes on / off, ceiling, units).
- **General**: version, what's new, where settings are kept (Open settings folder), backups and team
  settings, Reset (asks whether to reset your colour library too), and a Developer section:
  detailed Ruby Console log switch and Copy diagnostics.

## 0.14.0 — 2026-10-19
- **Top door height** (new Settings > **Components** tab, default 460 mm): the top doors on TOPBOX
  and the doors on BRIDGE_FRAME, so they line up along the run. Applied with the ceiling height
  (pencil window or ceiling button) to every unit set "Up to ceiling"; both windows show it.
- **Bridge built from its door** (component library, Components V21): BRIDGE_FRAME height = top door +
  top facing + gaps, and it places itself so its top is at the ceiling; BRIDGE_SKELETON sits under
  it. "Height below bridge" is gone. Both have "Ceiling height", "Top door height" and "Topped off?"
  in Component Options, so they also work without the plugin. Keep "Topped off?" the same on a
  skeleton and the frames on it.
- Door summary flags a unit whose top door differs from the setting.
- Settings window: tabs and bottom buttons no longer wrap onto two lines.
- Older job files with the previous bridge ("Height below bridge") still work as before.

## 0.13.0 — 2026-10-19
Behind-the-scenes tidy-up; nothing you use should look or work differently.
- Code split into folders (core / doors / colours / job / export / ui), one module per file.
  The old 550-line scribe.rb is now Runouts, Ceiling, Pencil and Standardise; main.rb is now
  Doors (actions), ColoursWindow, SettingsWindow and Menus.
- Every change to the model goes through one undo-step helper: a failure is always undone in
  full, and a later error can no longer undo work that had already finished (fixed in Apply
  colours, Apply tags, Export colour library, Settings save and Standardise runouts).
- One way to read component values (DC.read / DC.value), one way to open windows (Dialog),
  shared window styling (html/hw.css, hw.js), one progress runner (Batch).
- Export components saves in SketchUp's own version (removed a 2026-only lookup).
- Developer notes: CONTRIBUTING.md (rules, how to add a setting / window / button, settings
  keys) and tools/README.md (what each one-off library script did).

## 0.12.0 — 2026-10-19
- **Settings now kept in `%APPDATA%\HW Door Style\settings.json`**, so installing an update no longer
  wipes them. A settings.json left in the plugin folder by an older version is copied across once.
- **Load team settings** (Settings window, bottom bar): pick a settings backup kept on Google Drive;
  it loads into the window (press Save to keep it) and the file is remembered for next time.
  Make the team file with Download backup.
- Needs SketchUp 2021 or newer; older versions show a message instead of half-loading.
- Pencil check about 40x faster on big models (0.6 s -> 0.016 s on Components V20), and held while
  Scribes / Ceiling / Export components are running, then checked once at the end. Pressing the
  pencil while a job is running is ignored.
- Observers start once when the plugin loads (and see the file SketchUp opens at start-up).
- Extension description updated (Extension Manager).

## 0.11.8 — 2026-10-19
- The pencil now shows the state of the open model, like SketchUp's own toggles (X-ray, Hidden
  Geometry): pressed when any unit has a runout above 0, released when every runout is 0. Worked out
  from the model itself (not a stored flag), refreshed when a file is opened or switched and after
  every change / undo / redo. Opening a file never marks it as modified.

## 0.11.7 — 2026-10-19
- Shaker drawer fronts: stiles (vertical) 100 mm, the same as the doors, so the panels line up with the
  door panels; rails (top / bottom) stay 50 mm. Settings -> Doors & hinges has both values.
  Press Shaker again to redraw existing drawer fronts.

## 0.11.6 — 2026-10-19
- Settings -> Colours & materials: **Colour library** editor, laid out like SketchUp's Materials
  browser - swatch grid; edit name, colour, texture image and size; New / Duplicate / Delete /
  Reset to built-in. Saved in your settings (and backups); textures kept in %APPDATA%\HW Door Style\textures
  so updates don't remove them. Saving updates materials of the same name in the open model.
- New **Cut list** tab (information only): OpenCutList installed / version, what the plugin could set
  for OpenCutList (material types, thickness, grain) and ideas for connecting the two.

## 0.11.5 — 2026-10-19
- 22mm Panels row: default is now "Default (Frost White)" (Settings: panels_22_default). The separate
  plain White colour is gone; saved defaults of White become Default. Export / Clean model still strip it.

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
