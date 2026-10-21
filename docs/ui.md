# Production UI plan

How we take the interface from "working prototype" to a beautiful, coherent, shippable UI. It covers the art direction, the technical foundation, where every asset comes from, and the milestones (65–72) that get us there. `docs/plan.md` tracks progress; this file explains the why and the target.

## Where we are (2026-10-20)

Captured with `tools/capture_ui.tscn` (see "Verification" below). About 30 UI surfaces exist and they all work, but they look like a prototype:

- **Three unrelated visual styles.** Dark navy (satchel, sorting, inventory), brown with a gold border (journal), cream parchment (`FeaturePanel`: shop, friends, clubs, cauldron…), plus Godot's default grey buttons, tabs, dropdowns and scroll bars everywhere.
- **No theme and no font.** There is no project `Theme`. Every panel styles itself in code (55 `add_theme_*_override` calls, 16 hand-made `StyleBoxFlat`s), so changing the look means editing 30 files. Everything renders in Godot's default font.
- **The HUD is a debug readout.** Top left is a column of text lines ("Zdrowie", "Fragmenty: 0 / 27", "Czar: —", "W dłoni: —", "Sakiewka", "Dom"), always on; the hotbar has no spell icons; the notification text overlaps the chat box; the minimap is a square with a placeholder look.
- **The main menu is a dev form.** Name, language, role, server host and port fields in a grey box, a dev-build subtitle, the control list as a line of text.
- **No motion, no sound, little controller support.** Panels pop in and out; only 5 places set gamepad focus.
- **Bugs the gallery showed** (fixed in Milestone 65): the shop's title printed a raw key (`AREA_`); the notification overlapped the chat panel; the pause menu showed the HUD undimmed behind it.

What is already good and stays: the map relief shader, interface scale, reduced motion, house symbols beside colours, captions, rebindable keys (Milestone 63), and the fact that all text goes through translations.

## The target: what "production level" means here

A player should feel they are holding the school's own objects, not using a game menu. Concretely:

1. **One visual language.** Every surface belongs to one of two material families (below), uses the same fonts, the same spacing scale, the same buttons, the same close control, the same motion.
2. **Diegetic where it helps, clean where it matters.** Reading surfaces (journal, books, timetable, letters, map) are physical objects. Play surfaces (HUD, chat, prompts) are minimal and get out of the way.
3. **Every state designed.** Hover, pressed, focused (keyboard/gamepad), disabled, empty, loading, error, long Polish text, offline.
4. **Moves and sounds.** Panels open with a short ease, pages turn, seals stamp, buttons answer with a soft sound. Reduced motion turns it off.
5. **Works everywhere.** 1280×800 (Steam Deck) to 3440×1440, interface scale 0.75–1.75, mouse, keyboard and gamepad, Polish and English.
6. **Original.** Nothing that reads as the franchise: no shield split in four, no lion/eagle/badger/snake palettes, no lightning-bolt fonts. Our houses are Drakoryn, Grypheon, Phoenara, Hipporys with their own creatures and colours.

## Art direction: "Candlelit oak and parchment"

Two material families, one palette.

| Family | Used for | Materials | Feel |
|---|---|---|---|
| **Parchment** (reading) | Journal, books, timetable, notice boards, letters/DMs, quizzes, homework, map, sorting questions, shop lists | Aged paper with fibre and soft vignetting, iron-gall ink, red-brown rubrics, wax seals, ribbon bookmarks, deckled edges | Warm, quiet, tactile |
| **Oak & brass** (chrome) | HUD, hotbar, minimap ring, menus, settings, dialogs, chat, professor/admin tools | Dark stained oak or deep leather, thin aged-brass trims and corner pieces, a faint candle glow on focus | Rich, legible, never busy |

**Palette (tokens, final values set in Milestone 65):**

| Token | Role | Starting value |
|---|---|---|
| `ink` | Text on parchment | `#2B1D10` |
| `ink_soft` | Secondary text on parchment | `#5C4630` |
| `rubric` | Headings, warnings on parchment | `#8A2E1C` |
| `parchment` | Paper base | `#E9DDBF` |
| `oak` | Chrome base | `#1E1712` at 92 % opacity |
| `oak_raised` | Chrome buttons, slots | `#2C221A` |
| `brass` | Trims, focus, accents | `#C8A35A` |
| `brass_bright` | Hover, highlights | `#E8C77A` |
| `candle` | Text on chrome | `#F2E6CC` |
| `candle_soft` | Secondary text on chrome | `#B9A98C` |
| `danger` / `success` | States | `#C2523C` / `#7FA35A` |
| House colours | From `HouseSorting` | Unchanged; always paired with the house symbol |

**Type (owner's choice, 2026-10-20):** three roles, all OFL fonts from Google Fonts with full Polish diacritics, in `assets/fonts/` with their licences. Godot re-rasterises dynamic fonts at the scaled size, so they stay crisp at any interface scale; MSDF is only worth it later for 3D text (`Label3D`).

| Role | Font | Used for | In the theme |
|---|---|---|---|
| Display | **Cormorant SC** (SemiBold, Bold) | Titles, area banners, house and spell names, menu | `TitleLabel` (30), `BannerLabel` (64) |
| Text | **EB Garamond** (variable: 400, italic, 700) | Book and journal text, lecture text, quiz and sorting questions | `BookLabel` (19), `BookRichText` |
| Interface | **Fira Sans** (Regular, Italic, Medium, Bold) | Everything else: buttons, HUD, chat, settings, tooltips; the project's default font | default font, 16 |
| Symbols | **Noto Sans Symbols 2** + **Noto Sans Symbols**, trimmed | Fallback for ✓ ● ▲ ★ ✉ and other symbols none of the faces have, so they look the same on every platform | fallback on every face |

Godot measures a line's height over the whole fallback chain, and the Noto symbol fonts are much taller than Fira Sans (they spread a 24 px label to 50 px per line). `tools/make_symbol_fonts.py` (fontTools) keeps only the symbol blocks from the originals in `assets/fonts/noto_symbols/source/` and gives them Fira's vertical metrics, writing `UiSymbols2.ttf` and `UiSymbols.ttf`.

Code asks `UiFonts` for a role, never for a file; `tools/build_ui_theme.gd` writes the font resources and the theme. `tests/check_ui.tscn` fails if any character in the translations, the server's strings or a script literal is missing from the interface font, or any translated letter from the display and text fonts. The comparison page used to choose them: https://claude.ai/artifact/VoXgMfscSZxw1bFxAmGBFx. A handwriting face for the professor's board and personal notes is optional (Milestone 69), only if one with full Polish support is found.

**Iconography:** one icon style for ~150 icons: engraved/woodcut line art, single colour, drawn on a 64 px grid, recoloured in the engine (brass on chrome, ink on parchment). Spell icons are the exception: small painted roundels in the spell's colour, framed by a brass ring in the hotbar.

## Technical foundation

The look must live in one place so we can iterate on it in hours, not weeks.

**1. Tokens** (`ui/theme/ui_tokens.gd`, `class_name UiTokens`): colours, the spacing scale (4, 8, 12, 16, 24, 32, 48), corner radii, font sizes (12, 14, 16, 18, 22, 28, 40, 64), motion durations and easings, z-layers. Code that needs a colour asks `UiTokens`, never a literal.

**2. One Theme** (`ui/theme/arcanum_theme.tres`, set as `gui/theme/custom` with the interface font as `gui/theme/custom_font`). Built by `tools/build_ui_theme.gd` from the tokens and the frame textures, so it is reviewable in diffs and an agent can change it headlessly; the generated `.tres` is committed. Every control type gets real styles for all states (Button, LineEdit, TextEdit, OptionButton + its popup, CheckBox, CheckButton, HSlider, ProgressBar, TabContainer/TabBar, ItemList, Tree, ScrollBar, PopupMenu, TooltipPanel, RichTextLabel). Theme **type variations** carry the two families: `ParchmentPanel`, `ParchmentLabel`, `ParchmentButton`, `ChromePanel`, `ChromeButton`, `TitleLabel`, `RubricLabel`, `KeyChip`, `HotbarSlot`, `Toast`.

**3. Components** (`ui/components/`), small scenes with scripts, used by every screen:

| Component | Replaces / adds |
|---|---|
| `UiWindow` | The card in `FeaturePanel`: framed window (parchment or chrome), title ribbon, wax-seal close button, optional tabs, footer hint row, open/close animation. `FeaturePanel` becomes a thin subclass, so all its panels change look at once. |
| `UiRouter` (autoload) | One stack of open panels: Esc closes the top one, input capture and mouse mode handled centrally (today every panel sets `GameSession.ui_input_captured` itself), backdrop dim/blur behind modal windows, HUD fade while a window is open, gamepad focus on open. |
| `KeyChip` | Shows the bound key (or gamepad glyph when a pad was last used) for an action, read from the InputMap, so rebinding updates every hint. |
| `ToastStack` | Stacked notifications (top centre), types: info, reward (coins, points), learned spell, discovery, warning. Replaces the single notification label. |
| `AreaBanner` | Big display-font title when entering a new area ("Wielka Sala", small floor line), fades after 2.5 s. |
| `SpellSlot`, `ItemSlot` | Icon, key chip, radial cooldown sweep (shader), mastery pips, count, tooltip. |
| `HouseBadge` | Crest + symbol + colour, sizes S/M/L; the only way a house is shown. |
| `UiTooltip` | Rich tooltip: title, body, key hint. |
| `UiDialog` | Modal yes/no (`confirm()`) and connection errors with retry (`error()`). |
| `UiSounds` | Hover, click, open, close, page turn, tab, error, reward; from `docs/audio-list.md` (UI group). |
| `ProgressVial`, `UiSpinner` | Health/fill bar and loading indicator. |

**4. A style-guide scene** (`levels/dev/ui_gallery.tscn`): every component in every state, both families, both languages. It is the design reference, the place to tune the theme, and a capture target.

**5. Rules enforced by tests** (`tests/check_scripts.gd` or a new `tests/check_ui.gd`):
- No `add_theme_*_override`, `StyleBoxFlat.new()` or colour literals under `ui/` outside `ui/theme/` and `ui/components/` (an allowlist shrinks to zero during the migration).
- Every character used in `localization/translations.csv` exists in the three fonts.
- Every key a UI script passes to `tr()` exists (catches the `AREA_` bug class).

## Where to get the assets

Principle: **tools for volume, CC0 for materials, code for anything that must stay consistent.** The owner chose AI for the logo and crests too (no commissioned art); tool and prompts are in `docs/brand-prompts.md`. Every kept file gets a provenance line (tool, model, prompt, date) in `assets/ui/PROVENANCE.md`, as with audio, for Steam's AI content disclosure.

| Asset | How many | Recommended source | Why |
|---|---|---|---|
| **Logo** (game title wordmark) and **four house crests** | 5 | **AI, by the owner's decision.** Crests done (2026-10-20, ChatGPT): `assets/ui/brand/`, made game-ready by `tools/prep_crests.py`, loaded with `CharacterProfile.crest()`. School emblem and its small mark done too (main menu, boot splash, app icon); the wordmark too (owner, ChatGPT: main menu, and under the emblem on the boot splash) | They are the most-seen brand art (menu, Steam capsule, store page, crests on robes and banners). Purely AI-generated images are generally not protected by copyright, so edit them by hand and register the logo as a trademark. |
| **Icons** (spells, items, subjects, HUD symbols, map legend, chat channels, settings tabs) | ~150 | **Recraft** (vector/SVG output with a locked style and colour palette; commercial use on a paid plan) | Godot imports SVG at any scale; one style setting keeps 150 icons consistent; single-colour vectors recolour in the theme. Placeholders until then: **game-icons.net** (SVG, CC BY 3.0, needs a credit line). |
| **Spell roundels** (painted) | 11 now, grows with spells | **Scenario** (train a style model on the first 3–5 approved roundels, then generate the rest in that style) or Midjourney with a style reference | Painted look, consistent series, cheap to extend when a spell is added. |
| **Paper, leather, oak, brass, wax textures** | ~10 | **Poly Haven / ambientCG** (CC0) first; generate a seamless parchment in an image model only if none fits | Already the project's texture source; no licence questions. |
| **Window frames, corner pieces, ribbons, tabs, seals, slot rings** (nine-slice) | ~25 | **Generated by a script**: `tools/make_ui_frames.py` (Pillow, from the CC0 textures and vector shapes), like `tools/make_tapestry.py` | Reproducible, editable by an agent, exact pixel sizes for nine-slice margins, @1x and @2x outputs. AI images are poor at exact nine-slice geometry. |
| **Fonts** | 3 families + symbols | **Google Fonts** (OFL): Cormorant SC, EB Garamond, Fira Sans, Noto Sans Symbols | Free for commercial use, full Polish support, can be embedded. Done. |
| **Menu backdrop** | 1 | **The game itself**: a live castle at dusk with a slow camera drift (roadmap 5.7) | Always matches the real game; costs nothing; updates as the castle improves. |
| **Loading-screen lore cards** | 12–20 | Painted illustrations from **Midjourney / GPT image / Scenario** with a fixed style, or in-game captures given a painterly post-process shader | Volume asset; consistency matters more than uniqueness. |
| **Cursor** (quill, pointing hand, wand) | 3 | Recraft or hand-drawn SVG | Small, but it is on screen all the time in menus. |
| **UI sounds** | 12 | Already listed in `docs/audio-list.md` (UI group, ElevenLabs SFX) | One pipeline for all audio. |
| **Mockups / style frames** | 4–6 | Built directly in Godot in the UI gallery scene (and captured); Figma only if the owner wants to sketch | The real engine shows real fonts, scaling and Polish text; no translation step from a design tool. |

**Prompt rules for every image tool** (append to every prompt): *original fantasy school, engraved woodcut line icon* (or *painted roundel*), *no text, no letters, no logos*; never name the franchise, its houses, characters, places or artists. Reject anything that looks like a known crest or symbol.

## Milestones

Each milestone ends with a captured gallery the owner can look at and a playable build. The order is chosen so the whole game looks better after the first one, before any new art arrives.

### Milestone 65 — Foundation: tokens, fonts, one theme, the router
- [x] `tools/capture_ui.tscn`: the before/after gallery of every main surface, with `--size`, `--lang` and `--scale` for one run; `tools/capture_ui_matrix.sh` captures every size × language × scale the ship check reviews
- [x] The three fonts (`UiFonts`, `assets/fonts/`, symbol fallbacks), `tools/build_ui_theme.gd` → `ui/theme/arcanum_theme.tres` as the project theme (`gui/theme/custom`) with `TitleLabel`, `BannerLabel`, `BookLabel`, `BookRichText`; window titles, menu titles and book, quiz and sorting text use them
- [x] Font coverage test (`tests/check_ui.tscn`); chat escapes BBCode with `[lb]`/`[rb]` instead of full-width brackets
- [x] `UiTokens` (palette, spacing, radii, sizes, motion); the oak theme styles every control type in every state (buttons, option/menu buttons, check boxes, fields, popups, tooltips, tabs, lists, trees, scroll bars, sliders, progress bars, separators, focus rings); `ui/theme/parchment_theme.tres` turns everything inside a paper surface into ink (FeaturePanel cards and books use it)
- [x] Fixed: wrapping labels in a row shrank to one letter per line (settings, cauldron)
- [x] `UiRouter` (autoload, `ui/components/ui_router.gd`): panel stack, Esc to the top panel (its `ui_back()` or `close()`), input capture, freeing the cursor, the dim behind the top modal panel, HUD fade, gamepad focus on open; every panel (feature panels, chat, gesture wheel, map, satchel, book, timetable, lesson tools, quiz, character creator, journal, sorting) reports to it and no longer sets `GameSession.ui_input_captured` or handles Esc itself. The pause menu stays outside the stack (it pauses the tree)
- [~] `FeaturePanel` → `UiWindow` (still flat-styled): done, `ui/components/ui_window.gd` (parchment and chrome families from the theme's `ParchmentWindow`/`ChromeWindow` and `Window*` variations, title row, close control, status line, footer hints, open fade); every FeaturePanel uses it. Per-panel style overrides: `tests/check_ui.gd` fails on hand styling under `ui/` outside `ui/theme/` and `ui/components/` beyond a per-file allowlist that only shrinks; the remaining screens (HUD, journal, map, sorting, timetable, professor, quiz, satchel, chat, menus) move onto `UiWindow` and off the list
- [x] Missing-key test (`tests/check_ui.gd`: every key-shaped literal in a script or scene is in a table under `localization/`; `tests/run_tests.gd`: keys built at run time, and the settings window and gesture wheel show no raw key); `AREA_` fixed (`Localization.area_name()`: castle and grounds `AREA_<ID>`, village buildings `AREA_VILLAGE_<ID>`, else readable words; every shop window had shown a raw key); notifications above the chat box at any size; the pause menu on the `UiRouter` stack (dim, HUD fade, Esc resumes)
- **Result:** the whole game in one consistent style and real fonts, with no new art yet.

### Milestone 66 — Art kit v1 and the UI gallery
- [x] CC0 textures chosen (ambientCG Paper001 fibre and Paper003 mottling for the paper, Poly Haven black_oak_veneer for the grain, all tinted to the palette); `tools/make_ui_frames.py` draws 38 pieces at 4x and saves them at 1x and 2x into `assets/ui/frames/` with `frames.json` (nine-slice margins, the shadow outside the control, tiling): deckled parchment window with a ruled frame, oak window with a brass band and corner brackets, paper and oak panels, buttons (normal, hover, pressed, disabled), fields, tabs, a cloth ribbon, ink and brass rules, the wax-seal close control, key cap, toast, tooltip, slot rings and item slots. Every texture and noise repeats with the piece's period, so frames of any size have no seams
- [x] Theme switches from flat styles to textured nine-slice styles (`tools/build_ui_theme.gd` reads `frames.json`); small parts (scroll bars, sliders, focus rings) stay flat. `UiFrames` swaps the 2x pieces in, shown at 1x size, when the interface is drawn larger than 1:1 (interface scale times the window's stretch), so frames stay sharp at 1.5 and on 1440p
- [x] Components (`ui/components/`): `KeyChip` (bound key from the InputMap, pad button after pad input, follows rebinding), `ToastStack` (info, reward, learned, discovery, warning; newest four), `AreaBanner`, `SpellSlot` (ring, roundel in the spell's colour, key chip, cooldown sweep, mastery pips, selected and disabled), `ItemSlot`, `HouseBadge` (crest + name in house colour with its symbol, S/M/L; the emblem for the unsorted), `UiTooltip` (title, body, key hint), `UiDialog` (`confirm()` and `error()` with Retry, on the router stack), `ProgressVial`, `UiSpinner`; `UiWindow.add_key_hint()`; `UiRouter.device_changed`
- [x] Placeholder icon set: 54 game-icons.net icons (HUD, toasts, chat channels, the twelve subjects) as DPITextures (sharp at any size) behind `UiIcons.icon(id, px)`; `tools/make_ui_icons.py` writes them and `assets/ui/icons/CREDITS.md`. The final set replaces the files under the same ids
- [x] `levels/dev/ui_gallery.tscn`: four pages (windows and controls in both families, play surfaces, icons and houses, dialogs); `tools/capture_ui.gd` captures them first
- [x] Owner reviews the style frames and signs off the direction (approved 2026-10-22)
- **Owner checkpoint:** approve the look before the screens are rebuilt.

### Milestone 67 — The HUD
- [x] Remove the text column. Top left: `PlayerPlate` (crest, name, house in its colour and the year; staff see their title) and the lesson-tools key chip for staff. Health is a `ProgressVial` only while hurt (and a moment after healing) or in a duel. Fragments and coins are toasts; the purse moved to the satchel
- [x] Hotbar: ten `SpellSlot` roundels with the slot key chips (the `spell_slot_N` bindings), the effect's icon (`spell_<effect>`, 11 new placeholder icons), radial cooldown, mastery pips, a halo on the selected spell; the spell's name and incantation above; the held item in an `ItemSlot` beside it
- [x] Interaction prompt under the crosshair as a key chip + verb ("[E] Usiądź"); `HudCrosshair` is drawn, with a halo
- [x] Top right: `DayDial` (a window of sky that follows the day, the sun or the moon over a horizon, in a brass ring) with the time and the lesson now/next (else the part of the day); `HouseCrystals`, four crystals filled by each house's share of the leader's points (online)
- [x] Minimap: a round window in a brass ring with ticks and the north pointer (`minimap_ring` in the frame kit), the place and floor below
- [x] `ToastStack` for every notification (`GameEvents.notify(text, seconds, kind, icon)` gives it its kind; plain `notification_requested` stays an info toast), on its own layer above windows; `AreaBanner` on entering a named area (not again for the same area within 30 s); the lesson-start bell shows the subject and the room as a banner
- [x] The HUD and the minimap fade out behind windows; `toggle_hud` (F2, rebindable) hides the whole interface for screenshots. The HUD and the minimap no longer style anything by hand (`UiBox` gives code-built screens their spacing)

### Milestone 68 — Front door: main menu, loading, pause, settings
- [ ] Main menu: logo (placeholder wordmark until the commission), live castle backdrop at dusk with a slow drift, music; Play online, Practise offline, Settings, Credits, Quit. Server host/port move under "Advanced"; name and character choice move into the first-run flow
- [ ] Loading screen with lore cards and tips; connection, reconnect and error dialogs with retry
- [ ] Pause menu over a blurred, dimmed world
- [ ] Settings as a full window with tabs (Graphics, Audio, Controls, Interface, Accessibility, Language), styled sliders and toggles, a proper rebinding screen with key chips
- [ ] Credits screen (fonts, CC BY icons, music, tools)

### Milestone 69 — Reading surfaces: journal, books, satchel, map
- [ ] Journal as an open book: two-page spread, ribbon tabs on the edge, page-turn animation and sound; spellbook pages with roundels and mastery; grades in ink; calendar and post pages
- [ ] Books (`BookPanel`) on the same spread
- [ ] Satchel: leather bag window with an item grid, icons, tooltips, hold/put-away action
- [ ] Map: parchment frame, compass rose, legend with icons, floor tabs; timetable as a parchment sheet
- [ ] Optional handwriting face for notes and the professor's board

### Milestone 70 — School life screens
- [ ] Sorting as a ceremony: stone-dark vignette, question cards, the house reveal with the crest, a seal stamp and a sound
- [ ] Character creator full screen: character turntable on the left, options and swatches on the right
- [ ] Quizzes, homework, riddle doors, shop, cauldron, decor, duel HUD, Lantern Chase HUD on the new components
- [ ] Professor and admin panels in a compact "staff ledger" chrome style: denser, keyboard-friendly, still on the theme

### Milestone 71 — Social: chat, bubbles, nameplates, profiles
- [ ] Chat: channel tabs (say, whisper, shout, house, DM), names in house colour with symbols, timestamps, fades when idle, unread counts
- [ ] Speech bubbles, nameplates, notice boards and classroom boards (3D text) use the theme fonts and colours
- [ ] Profile card, friends, clubs, DMs, game panel on `UiWindow`

### Milestone 72 — Polish and ship check
- [ ] Final icon set (Recraft) and spell roundels replace placeholders; commissioned logo and crests (if delivered)
- [ ] Motion pass (one set of durations/easings from the tokens) and UI sounds on every component; reduced motion respected
- [ ] Full gamepad navigation and glyphs, a radial spell wheel, Steam Deck pass at 1280×800
- [ ] Accessibility: contrast check on both families, interface scale 0.75–1.75 without clipping, colour never the only signal
- [ ] Gallery at 1280×800, 1600×900, 2560×1440, 3440×1440 × PL/EN × scale 0.75/1/1.5, reviewed; native-speaker pass over the Polish copy
- [ ] Owner playtest sign-off

**Parallel track (owner):** none open; the crests, emblem and mark are done (`docs/brand-prompts.md`). Buy one Recraft month for the icon set during Milestone 71–72.

## Owner decisions

| Decision | Recommendation |
|---|---|
| Art direction | Decided (owner, 2026-10-21): "candlelit oak and parchment" as above. |
| Fonts | Decided: Cormorant SC / EB Garamond / Fira Sans. |
| Logo and crests | Decided: generated with AI, prompts and rules in `docs/brand-prompts.md`; crests made with ChatGPT and in the game; edit by hand and register the logo as a trademark. |
| Icon tool | Recraft for the final set; game-icons.net placeholders now. |
| Gamepad / Steam Deck for 1.0 | Yes: Steam players expect it and the Deck is a good fit for this game. Budgeted in Milestone 72. |

## Verification

```
godot --path . tools/capture_ui.tscn -- --out=/absolute/output/dir
# one size, language and interface scale: add --size=1280x800 --lang=en --scale=1.5
# every combination the ship check reviews (24 runs, about a minute each):
tools/capture_ui_matrix.sh /absolute/output/dir
```

Saves a PNG of the main menu, HUD, satchel, journal, map, chat, timetable, sorting, character creator, settings, friends, clubs, profile, shop, cauldron, decor and pause (needs a window, not `--headless`). Every UI milestone ends by capturing the gallery and comparing it with the previous one; the headless tests (`tests/run_tests.tscn`) and the UI lint stay green.
