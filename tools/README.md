# tools/

Ruby Console helpers. None of these are part of the plugin `.rbz`.

## Everyday

| File | What it does |
|---|---|
| `acceptance_test.rb` | Old Ruby Console command for the acceptance tests; they now live in the plugin (`dev/acceptance.rb`) and run from **Developer > Run tests** (doors, runouts, ceiling + bridge, colours, export). Each suite runs inside a step that is undone. |
| `hw_inspect.rb` | Read-only inspector: prints a component's DC options, formulas and children. |

## One-off library migrations (already applied)

These changed the component library once. They are kept so the change can be repeated on
an older library file, or read to see what was done. Each one **does not open its own
undo step**: call it inside yours (or inside one you abort, to try it).

| File | Applied to | What it changed |
|---|---|---|
| `standardise_runouts.rb` | Components V19 | SCRIBE_L/R → RUNOUT_L/R, every runout dropdown 0/25/50/75/100/150, TOPPED naming. (The plugin's `Standardise` module does the key/dropdown part automatically on old job files.) |
| `reorder_options.rb` | Components V19 → V20 | Section prefixes (`a01_` … `j05_`) so Component Options lists sections in order; formulas and `NAME!X` references rewritten. |
| `div_runouts.rb` | Components V20 | Dividers / end panels take the floor and ceiling runouts as well as back. |
| `ceiling_switch.rb` | Components V20 | `i05_up_to_ceiling` on every unit with a height; `a03_height_below` on BRIDGE_FRAME (removed again in V21). |
| `hide_facing_bottom.rb` | Components V22 | The bottom facing option ("bottom", d01_facing_btm) hidden in Component Options on every component, plus FACING section headers left empty (BOX_SHELF, BXEND, EXT_DRAWER). Set in the pencil window from 0.19. |
| `bridge_door_height.rb` | Components V21 | BRIDGE_FRAME built from "Top door height" (b02, 460): height = door + facing top + gaps, top at "Ceiling height" (a02) by a Z formula; "Height below bridge" removed. BRIDGE_SKELETON gets the same options and sits under the frame. |

Before running any of them on a library: `model.save_copy` first.
