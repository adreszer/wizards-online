# Production UI plan

How we take the interface from "working MVP" to a beautiful, coherent, shippable UI. It covers the art direction, the technical foundation, where every asset comes from, and the milestones (65–72) that get us there. `docs/plan.md` tracks progress; this file explains the why and the target.

## Where we are (2026-10-20)

Captured with `tools/capture_ui.tscn` (see "Verification" below). About 30 UI surfaces exist and they all work, but they look like a prototype:

- **Three unrelated visual styles.** Dark navy (satchel, sorting, inventory), brown with a gold border (journal), cream parchment (`FeaturePanel`: shop, friends, clubs, cauldron…), plus Godot's default grey buttons, tabs, dropdowns and scroll bars everywhere.
- **No theme and no font.** There is no project `Theme`. Every panel styles itself in code (55 `add_theme_*_override` calls, 16 hand-made `StyleBoxFlat`s), so changing the look means editing 30 files. Everything renders in Godot's default font.
- **The HUD is a debug readout.** Top left is a column of text lines ("Zdrowie", "Fragmenty: 0 / 27", "Czar: —", "W dłoni: —", "Sakiewka", "Dom"), always on; the hotbar has no spell icons; the notification text overlaps the chat box; the minimap is a square with a placeholder look.
- **The main menu is a dev form.** Name, language, role, server host and port fields in a grey box, "Pionowy wycinek MVP" as the subtitle, the control list as a line of text.
- **No motion, no sound, little controller support.** Panels pop in and out; only 5 places set gamepad focus.
- **Bugs the gallery already shows:** the shop's title prints a raw key (`AREA_`) offline; the notification overlaps the chat panel; the pause menu shows the HUD and chat undimmed behind it.

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

**Type:** three roles, all OFL fonts with full Polish diacritics (ą ć ę ł ń ó ś ź ż and capitals), loaded as MSDF so they stay crisp at any interface scale.

| Role | Candidate | Used for |
|---|---|---|
| Display | **Cormorant Garamond** (SemiBold/Bold) or **Cormorant SC** | Titles, area banners, house names, menu |
| Text | **Alegreya** (Regular/Italic/Bold) | Book and journal text, lecture text, quiz questions |
| Interface | **Alegreya Sans** (Medium/Bold) | Buttons, HUD numbers, chat, settings, tooltips, small text |

Alternatives if the owner prefers: EB Garamond for text, Marcellus or Cinzel Decorative for display (Cinzel is overused in fantasy games; avoid it as the main face). A handwriting face for the professor's board and personal notes is optional (Milestone 69), only if one with full Polish support is found.

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
| `ConfirmDialog`, `ErrorDialog` | Modal yes/no and connection errors (with retry). |
| `UiSounds` | Hover, click, open, close, page turn, tab, error, reward; from `docs/audio-list.md` (UI group). |
| `ProgressVial`, `UiSpinner` | Health/fill bar and loading indicator. |

**4. A style-guide scene** (`levels/dev/ui_gallery.tscn`): every component in every state, both families, both languages. It is the design reference, the place to tune the theme, and a capture target.

**5. Rules enforced by tests** (`tests/check_scripts.gd` or a new `tests/check_ui.gd`):
- No `add_theme_*_override`, `StyleBoxFlat.new()` or colour literals under `ui/` outside `ui/theme/` and `ui/components/` (an allowlist shrinks to zero during the migration).
- Every character used in `localization/translations.csv` exists in the three fonts.
- Every key a UI script passes to `tr()` exists (catches the `AREA_` bug class).

## Where to get the assets

Principle: **tools for volume, people for identity, CC0 for materials, code for anything that must stay consistent.** Every kept file gets a provenance line (tool, model, prompt, date) in `assets/ui/PROVENANCE.md`, as with audio, for Steam's AI content disclosure.

| Asset | How many | Recommended source | Why |
|---|---|---|---|
| **Logo** (game title wordmark) and **four house crests** | 5 | **Commission a human illustrator/designer** (ArtStation, Behance, a Polish illustrator; brief made from AI mood boards) | They are the most-seen brand art (menu, Steam capsule, store page, crests on robes and banners). Purely AI-generated images are generally not protected by copyright, so you could not stop others copying your logo or crests; a commissioned work with a written copyright transfer gives you that. Expect a few hundred to a couple of thousand euros for the set. The same artist can later do the Steam capsule. Until then we use placeholder crests built from the house symbols. |
| **Icons** (spells, items, subjects, HUD symbols, map legend, chat channels, settings tabs) | ~150 | **Recraft** (vector/SVG output with a locked style and colour palette; commercial use on a paid plan) | Godot imports SVG at any scale; one style setting keeps 150 icons consistent; single-colour vectors recolour in the theme. Placeholders until then: **game-icons.net** (SVG, CC BY 3.0, needs a credit line). |
| **Spell roundels** (painted) | 11 now, grows with spells | **Scenario** (train a style model on the first 3–5 approved roundels, then generate the rest in that style) or Midjourney with a style reference | Painted look, consistent series, cheap to extend when a spell is added. |
| **Paper, leather, oak, brass, wax textures** | ~10 | **Poly Haven / ambientCG** (CC0) first; generate a seamless parchment in an image model only if none fits | Already the project's texture source; no licence questions. |
| **Window frames, corner pieces, ribbons, tabs, seals, slot rings** (nine-slice) | ~25 | **Generated by a script**: `tools/make_ui_frames.py` (Pillow, from the CC0 textures and vector shapes), like `tools/make_tapestry.py` | Reproducible, editable by an agent, exact pixel sizes for nine-slice margins, @1x and @2x outputs. AI images are poor at exact nine-slice geometry. |
| **Fonts** | 3 families | **Google Fonts** (OFL) | Free for commercial use, full Polish support, can be embedded. |
| **Menu backdrop** | 1 | **The game itself**: a live castle at dusk with a slow camera drift (roadmap 5.7) | Always matches the real game; costs nothing; updates as the castle improves. |
| **Loading-screen lore cards** | 12–20 | Painted illustrations from **Midjourney / GPT image / Scenario** with a fixed style, or in-game captures given a painterly post-process shader | Volume asset; consistency matters more than uniqueness. |
| **Cursor** (quill, pointing hand, wand) | 3 | Recraft or hand-drawn SVG | Small, but it is on screen all the time in menus. |
| **UI sounds** | 12 | Already listed in `docs/audio-list.md` (UI group, ElevenLabs SFX) | One pipeline for all audio. |
| **Mockups / style frames** | 4–6 | Built directly in Godot in the UI gallery scene (and captured); Figma only if the owner wants to sketch | The real engine shows real fonts, scaling and Polish text; no translation step from a design tool. |

**Prompt rules for every image tool** (append to every prompt): *original fantasy school, engraved woodcut line icon* (or *painted roundel*), *no text, no letters, no logos*; never name the franchise, its houses, characters, places or artists. Reject anything that looks like a known crest or symbol.

## Milestones

Each milestone ends with a captured gallery the owner can look at and a playable build. The order is chosen so the whole game looks better after the first one, before any new art arrives.

### Milestone 65 — Foundation: tokens, fonts, one theme, the router
- [ ] `tools/capture_ui.tscn`: the before/after gallery of every main surface (done in this planning step; extend it with resolutions, languages and interface scales)
- [ ] `UiTokens`, the three fonts (MSDF), `tools/build_ui_theme.gd` → `ui/theme/arcanum_theme.tres` as the project theme; flat-colour styles from the palette for every control type and state
- [ ] `UiRouter`: panel stack, Esc, input capture, mouse mode, modal dim, HUD fade, focus on open; migrate every panel to it
- [ ] `FeaturePanel` → `UiWindow` (still flat-styled); remove per-panel style overrides (allowlist test, shrinking)
- [ ] Font coverage test and missing-key test; fix `AREA_`, the notification/chat overlap, the undimmed pause backdrop
- **Result:** the whole game in one consistent style and real fonts, with no new art yet.

### Milestone 66 — Art kit v1 and the UI gallery
- [ ] CC0 textures chosen; `tools/make_ui_frames.py` makes parchment and oak frames, corners, ribbons, tabs, wax-seal close button, slot rings, separators (@1x/@2x)
- [ ] Theme switches from flat styles to textured nine-slice styles
- [ ] Components: `KeyChip`, `ToastStack`, `AreaBanner`, `SpellSlot`, `ItemSlot`, `HouseBadge` (placeholder crests), `UiTooltip`, dialogs, `ProgressVial`, `UiSpinner`
- [ ] Placeholder icon set (game-icons.net) wired through an `UiIcons` registry, so swapping in the final Recraft set is a file replacement
- [ ] `levels/dev/ui_gallery.tscn`; owner reviews the style frames here and signs off the direction
- **Owner checkpoint:** approve the look before the screens are rebuilt.

### Milestone 67 — The HUD
- [ ] Remove the text column. Top left: house badge, name, year. Health appears only when below full or in a duel (vial). Fragments, coins and "in hand" show as toasts or in the satchel, not permanently
- [ ] Hotbar: spell roundels, key chips, radial cooldown, mastery pips, selected glow; held item slot beside it
- [ ] Interaction prompt near the crosshair as a key chip + verb ("[E] Otwórz drzwi")
- [ ] Top right: sun/moon dial with the time and the next lesson line; a compact four-crystal house tally
- [ ] Minimap: round brass ring with a compass rose, area name below
- [ ] `ToastStack` for every notification; `AreaBanner` on entering a named area; lesson start and bell banners
- [ ] HUD hides cleanly in photo mode and while windows are open

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

**Parallel track (owner):** brief and commission the logo and four crests during Milestones 65–66, so they arrive by 72. Buy one Recraft month for the icon set during Milestone 71–72.

## Owner decisions

| Decision | Recommendation |
|---|---|
| Art direction | "Candlelit oak and parchment" as above. Confirm before Milestone 66. |
| Fonts | Cormorant Garamond / Alegreya / Alegreya Sans. Confirm in the UI gallery. |
| Logo and crests | Commission a human artist (copyright ownership); AI only for the brief. |
| Icon tool | Recraft for the final set; game-icons.net placeholders now. |
| Gamepad / Steam Deck for 1.0 | Yes: Steam players expect it and the Deck is a good fit for this game. Budgeted in Milestone 72. |

## Verification

```
godot --path . tools/capture_ui.tscn -- --out=/absolute/output/dir
```

Saves a PNG of the main menu, HUD, satchel, journal, map, chat, timetable, sorting, character creator, settings, friends, clubs, profile, shop, cauldron, decor and pause (needs a window, not `--headless`). Every UI milestone ends by capturing the gallery and comparing it with the previous one; the headless tests (`tests/run_tests.tscn`) and the UI lint stay green.
