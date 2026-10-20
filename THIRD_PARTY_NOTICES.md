# Third-party notices

HW Door Style is Copyright (C) Gautier Design Ltd (Harry Wardrobes) and is free software under the
GNU General Public License v3.0 (see `LICENSE`). Its full source is kept with every copy it is
distributed with. Only GPL-3.0-compatible code is included.

## OpenCutList — GPL-3.0

**OpenCutList** by **L'Air du Bois** — https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension
Copyright (C) L'Air du Bois and the OpenCutList contributors. Licensed under the GNU General Public
License v3.0. Reference copy used for the label editor port: commit `1ef3e14c` (19 October 2026).

Files in HW Door Style copied from or derived from OpenCutList (each carries a notice at the top
saying so and that it was modified by Gautier Design Ltd):

| HW Door Style file | Taken from OpenCutList |
|---|---|
| `src/hw_door_style/html/vendor/label_editor.js` | `js/plugins/components/jquery.ladb.editor-label-layout.js`, `twig/components/_editor-label-element-form.twig` — label layout editor (canvas, grid, drag / snap, nudge, add / duplicate / remove / rotate, element form). Rewritten without jQuery / Twig / i18next; fields rewired to HW's. Modified by Gautier Design Ltd, 20 October 2026. |
| `src/hw_door_style/html/parts_list.html` (labels part) | `twig/tabs/cutlist/_slide-labels.twig`, `twig/tabs/cutlist/_label-element.twig` — label page and element drawing. Modified by Gautier Design Ltd. |
| `src/hw_door_style/job/labels.rb` | `ruby/worker/cutlist/cutlist_labels_worker.rb`, `worker/common/common_eval_formula_worker.rb`, `model/formula/formula_wrapper.rb` — label entries, part order, custom formulas; reads OpenCutList's saved label layouts. Modified by Gautier Design Ltd. |
| `src/hw_door_style/job/parts_list.rb` | Cut list rules (parts, groups, edges, part order, numbering). Modified by Gautier Design Ltd. |

Left behind on purpose: OpenCutList's i18n layer, tab framework and cut list data model.

## JsBarcode — MIT

**JsBarcode** v3.11.6 by Johan Lindell — https://github.com/lindell/JsBarcode — MIT License
(GPL-compatible). `src/hw_door_style/html/vendor/JsBarcode.code128.min.js` (Code 128 build, unmodified),
licence text in `src/hw_door_style/html/vendor/JsBarcode-MIT-LICENSE.txt`.
