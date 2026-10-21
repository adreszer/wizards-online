# Audio list

Every sound and music track the game needs, with the prompt to generate it. Built from the roadmap (item 7 and section 5.8) and what exists in the code today: 11 spells, the puzzle and set-piece objects, school systems (bells, sorting, house points, timetable), brooms, the crystal guardian, the HUD, and the castle and grounds areas.

## How to use this list

**Source column**
- **Gen**: generate with ElevenLabs (Sound Effects or Music). It's for sounds that don't exist in the real world.
- **Lib**: take from a library first: the free yearly Sonniss GDC bundle or CC0 clips on Freesound. Real recordings loop and vary better. The prompt is a fallback.

**Settings (ElevenLabs Sound Effects)**
- Set the duration to the **Len** value; leave it on auto for anything under 1 s.
- For rows marked **Loop**, use the loop option if your model offers it. Otherwise generate a little longer and crossfade the ends in Audacity.
- Prompt influence: high (about 0.7) for spells and UI, so they stay on brief; lower (about 0.4) for ambiences, so they vary naturally.
- **Takes** is how many generations to budget. Keep every good take of a frequent sound and play them through an `AudioStreamRandomizer`, so repeats don't sound identical.

**Style rules for every prompt**
- Generation works best when you describe the sound physically: what material, what action, what room. Mood words help less.
- Paste this suffix onto every sound effect prompt: `, no voices, no music, clean recording, no background noise` (ambiences: drop "no background noise").
- The palette: old stone and oak, iron fittings, crystal and glass for magic, warm rather than sci-fi. Never "laser", "electronic" or "synth" for spells.
- Original content: never mention franchise names, characters, places, spells or composers in a prompt ("in the style of …"). Describe the sound itself.

**Files**
- Short sounds go in `assets/audio/<group>/<id>.wav`; music and ambience loops go in `assets/audio/<group>/<id>.mp3` (Godot plays MP3 natively), loudness-matched to −18 LUFS, with the untouched download kept in `source/` next to them (WAV downloads stored there as lossless FLAC) (a `.gdignore` keeps Godot out of it).
- Spells are wired through `cast_sound`, `travel_sound` (looped on the projectile) and `impact_sound` on each `resources/spells/*.tres`; the spoken words through `incantation` and `assets/audio/voice/<voice>/<spell>.wav`.
- The castle bell is synthesised in code today (`SchoolBells.bell_stream()`); `school_bell_stroke` replaces it.

**Provenance (for Steam's AI content disclosure)**
- For every file you keep, record the file, tool and model, prompt, date and take number.
- For library files, record the pack name and licence.
- Keep these in `assets/audio/SOURCES.csv`.

## Credit budget (ElevenLabs Creator, 121,000 credits)

The pricing page lists 200 credits per sound effect generation and 900 credits per minute of music. Totals count only **Gen** rows.

| Group | Gen sounds | Takes | Credits |
|---|---|---|---|
| Spells | 36 | 120 | 24,000 |
| Spell effects on the world | 11 | 33 | 6,600 |
| Puzzles, secrets and set pieces | 21 | 67 | 13,400 |
| Doors and furniture | 9 | 22 | 4,400 |
| School life and classrooms | 21 | 64 | 12,800 |
| Brooms and flying | 7 | 19 | 3,800 |
| Player | 8 | 24 | 4,800 |
| Crystal guardian | 5 | 15 | 3,000 |
| UI | 12 | 30 | 6,000 |
| Ambiences (Gen only) | 8 | 16 | 3,200 |
| **Sound effects total** | **138** | **410** | **82,000** |
| Music: 11 pieces, 42.5 min of takes | | | 38,250 |
| **Total** | | | **120,250** |

That uses almost all of one month of Creator, so there's little margin. Two habits keep it inside:
- **Sketch music first.** Generate each track at 30 s to check the direction before paying for the full length.
- **Stop early on easy sounds.** When take 1 or 2 is already good, skip the rest; most UI and furniture sounds won't need every take.

If you run short anyway, cut music takes first.

---

## 1. Spells

Each spell has three sounds: **cast** (at the hand), **travel** (a loop on the projectile, `spell_projectile.tscn`) and **impact** (where it lands). They share a core so they sound like one school of magic: a short wooden flick and a glassy shimmer, coloured by the element.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| spell_arcane_pulse_cast | Gen | 1 s | | 4 | A short magical force pulse released from a wooden wand: a tight low thump with a bright glassy shimmer on top, crisp attack, quick tail |
| spell_arcane_pulse_travel | Gen | 2 s | Loop | 3 | A small orb of magical energy flying through the air: a steady soft pulsing hum with a faint glassy shimmer, even and seamless |
| spell_arcane_pulse_impact | Gen | 1.5 s | | 4 | A burst of magical force hitting a stone wall: a deep punchy thud, a short ringing shimmer, a little dust and grit scattering |
| spell_uplift_cast | Gen | 1 s | | 3 | A gentle rising magical swell from a wand: soft airy upward whoosh with a delicate glass chime climbing in pitch |
| spell_uplift_travel | Gen | 2 s | Loop | 3 | A light floating magical hum drifting through the air, airy and buoyant, soft shimmer, seamless |
| spell_uplift_impact | Gen | 1.5 s | | 3 | A magical lift taking hold of a wooden crate: a soft whoomp, a creak of wood leaving a stone floor, a rising airy shimmer |
| spell_galewind_cast | Gen | 1 s | | 4 | A hard gust of conjured wind bursting out of a wand: a sharp, powerful whoosh with cloth snapping, tight and short |
| spell_galewind_travel | Gen | 2 s | Loop | 3 | A small tunnel of rushing wind flying past, swirling gusty roar, steady and seamless |
| spell_galewind_impact | Gen | 1.5 s | | 4 | A blast of wind slamming into a stone room: a heavy gust burst, cloth and banners flapping hard, loose papers and grit scattering |
| spell_emberkindle_cast | Gen | 1 s | | 4 | A spark of living flame leaping from a wand: a flint-like strike and a small hungry fire whoosh, crisp |
| spell_emberkindle_travel | Gen | 2 s | Loop | 3 | A small fireball flying through the air: steady crackling flame roar with tiny sparks popping, seamless |
| spell_emberkindle_impact | Gen | 1.5 s | | 4 | A small fire burst splashing onto stone: a soft whump of flame, crackling embers, a short sizzle as it dies down |
| spell_wellspring_cast | Gen | 1 s | | 3 | Water summoned from nothing: a quick bubbling gurgle rising into a bright splash, clean and fresh |
| spell_wellspring_travel | Gen | 2 s | Loop | 3 | A flowing ribbon of water flying through the air: a steady watery whoosh with light bubbling, seamless |
| spell_wellspring_impact | Gen | 1.5 s | | 4 | A large splash of water hitting a stone floor, droplets pattering all around, a short trickle at the end |
| spell_frostbind_cast | Gen | 1 s | | 4 | An ice spell cast from a wand: sharp crystalline crackle, a cold breathy hiss and a high glassy ting |
| spell_frostbind_travel | Gen | 2 s | Loop | 3 | A spinning shard of ice whistling through the air with a faint frosty crackle, seamless |
| spell_frostbind_impact | Gen | 1.5 s | | 4 | An ice shard shattering against stone: a crisp crystalline smash, frost spreading with a crackling creak, tinkling ice fragments |
| spell_glowmote_cast | Gen | 1 s | | 3 | A tiny mote of light conjured from a wand: a soft warm twinkle like a small glass bell, a gentle breath of air |
| spell_glowmote_travel | Gen | 2 s | Loop | 3 | A small glowing light drifting slowly through the air: a delicate sparkling hum, warm and calm, seamless |
| spell_glowmote_impact | Gen | 1.5 s | | 3 | A soft bloom of light settling in place: a warm swelling glassy chime that blossoms and holds gently |
| spell_duskveil_cast | Gen | 1 s | | 4 | A shadow spell cast from a wand: a hushed, breathy low whoosh, muffled and velvety, like a heavy curtain swept through the air |
| spell_duskveil_travel | Gen | 2 s | Loop | 3 | A drifting cloud of shadow: a low smoky rumble with a soft airy hiss, muffled, seamless |
| spell_duskveil_impact | Gen | 1.5 s | | 4 | A veil of shadow smothering a flame: a soft muffled thump, a short hiss and the flame dying into silence |
| spell_unbolt_cast | Gen | 1 s | | 3 | A quick precise magical flick: a small metallic click and a bright brassy shimmer |
| spell_unbolt_travel | Gen | 2 s | Loop | 2 | A small spell flying through the air with a faint tinkling metallic hum, like tiny keys, seamless |
| spell_unbolt_impact | Gen | 1.5 s | | 4 | A heavy iron bolt sliding back by itself: a scrape of iron, a solid lock clunk, a faint sparkle |
| spell_mendweave_cast | Gen | 1 s | | 3 | A warm, soft magical swell from a wand, gentle and soothing, a light glassy shimmer |
| spell_mendweave_travel | Gen | 2 s | Loop | 2 | A gentle threaded whir travelling through the air, like fine thread pulled quickly, soft shimmer, seamless |
| spell_mendweave_impact | Gen | 2 s | | 4 | Broken pottery knitting itself back together: shards clinking into place in quick succession, ending with a soft clear ceramic ring |
| spell_quicksprout_cast | Gen | 1 s | | 3 | A nature spell cast from a wand: an organic rustle of leaves and a soft earthy shimmer |
| spell_quicksprout_travel | Gen | 2 s | Loop | 2 | Fluttering leaves and seeds swirling through the air, soft rustling whoosh, seamless |
| spell_quicksprout_impact | Gen | 2 s | | 4 | A plant bursting into sudden growth: creaking stems stretching, leaves unfurling and rustling, a soft earthy pop |
| spell_fizzle | Gen | 1 s | | 3 | A spell failing in a wand: a weak sputtering crackle and a deflating puff, like a damp match |
| spell_warded | Gen | 1.5 s | | 3 | A spell bouncing off an invisible magical ward: a deep resonant glassy thrum and a dull shimmering rebound |
| spell_learned | Gen | 3 s | | 4 | A new spell settling into memory: a rising shimmer of glass chimes, a warm swell of air, a final soft bell-like ring (replaces `learn.wav`) |

### Incantations (built)

Every spell has original Latin words (`SpellDefinition.incantation`, translation keys `SPELL_*_INCANTATION`, the same in Polish and English), spoken by the caster on every cast in their body's voice. Two voices designed with ElevenLabs Voice Design (young adult apprentices; the designer refuses voices described as under 18), lines from Text to Speech `eleven_v3` with a delivery tag. Never reuse or echo franchise incantations.

| Spell | Words | Meaning | Delivery tag |
|---|---|---|---|
| arcane_pulse | Arcana Pulsa | push, hidden powers | shouts commandingly |
| uplift | Surge Sublimis | rise, aloft | firmly, rising |
| galewind | Procella Ruat | let the storm rush | shouts forcefully |
| emberkindle | Accende Favillam | kindle the ember | sharply, commanding |
| wellspring | Fons Erumpe | spring, burst forth | clearly, commanding |
| frostbind | Gelu Liga | frost, bind | sharp and cold |
| glowmote | Scintilla Mane | spark, stay | softly, with wonder |
| duskveil | Vela Crepusculo | veil with twilight | in a low, hushed voice |
| unbolt | Pessulum Solve | loosen the bolt | crisp and precise |
| mendweave | Texe Integrum | weave it whole | warmly, steady |
| quicksprout | Germina Cito | sprout quickly | brightly, encouraging |

## 2. Spell effects on the world

What objects do when a spell reaches them. Positional, played by `spell_receiver.gd`.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| torch_ignite | Gen | 1.5 s | | 3 | A wall torch catching fire: a soft whoomph as oily cloth ignites, then a crackling flame settling in |
| torch_snuff | Gen | 1 s | | 3 | A torch flame snuffed out in an instant: a short muffled puff and a faint smoky hiss |
| fire_doused | Lib | 2 s | | 3 | Water poured on burning wood: a loud steamy hiss, a sputter of dying flames, a sizzle fading out |
| torch_loop | Lib | 10 s | Loop | 2 | A wall torch burning steadily: gentle crackling flame with small pops, close, seamless |
| brazier_loop | Lib | 10 s | Loop | 2 | A large iron fire brazier burning outdoors: deep steady flame roar with crackling logs, seamless |
| water_freeze | Gen | 2.5 s | | 3 | A pool of water freezing solid in seconds: creaking, crackling ice spreading across the surface, ending in a sharp crystalline snap |
| basin_fill | Gen | 2.5 s | | 3 | A stone basin filling up with water from a magical stream: splashing, then rising gurgling water reaching the brim |
| object_hover_loop | Gen | 4 s | Loop | 3 | A heavy object floating in the air by magic: a low soft resonant hum with a gentle wavering shimmer, seamless |
| object_drop_wood | Gen | 1 s | | 3 | A wooden crate dropped from a short height onto a stone floor: a solid thud and a rattle |
| glowmote_loop | Gen | 4 s | Loop | 3 | A small hovering light: a very soft warm twinkling hum, delicate and calm, seamless |
| glowmote_fade | Gen | 1.5 s | | 3 | A small magical light fading away: a gentle descending glassy twinkle dissolving into air |
| plant_grow_large | Gen | 3 s | | 3 | A climbing vine growing fast up a stone wall: creaking stems, leaves rustling and unfurling, roots gripping stone |
| object_mended | Gen | 1.5 s | | 3 | A torn page or broken object made whole by magic: a soft papery rustle and a gentle clear chime |
| lock_unlocked | Gen | 1 s | | 3 | An old iron lock springing open by itself: a crisp clack of iron and a tiny magical glint |

Built (2026-10-21): all but `water_freeze`, `basin_fill` and `object_mended`, which wait for objects to play on. `brazier_loop` became `hearth_loop` (the village hearths), `basin_fill` gave way to `garden_water` (the greenhouse beds); `torch_loop` and `hearth_loop` are played by `FireAmbience` at the nearest fires only.

## 3. Puzzles, secrets and set pieces

`objects/puzzles/*` and `objects/setpieces/*`, plus the mystery system. Secrets are a core pillar, so these are hero sounds; budget extra takes.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| secret_wall_open | Gen | 4 s | | 4 | A hidden passage opening in a castle wall: heavy stone blocks grinding and sliding apart, a deep rumble, dust trickling, ending with a heavy settle (replaces `door.wav` on the secret wall) |
| secret_wall_close | Gen | 3 s | | 3 | A secret stone wall sliding shut: heavy grinding stone and a final deep boom as it seals |
| secret_revealed | Gen | 3 s | | 4 | The discovery of a hidden place: a soft breath of air, a low mysterious shimmering swell and a single deep resonant chime |
| magic_door_open | Gen | 3 s | | 4 | An ancient enchanted stone door unsealing: a low magical hum rising, runes chiming, then heavy stone swinging open |
| magic_door_close | Gen | 2.5 s | | 3 | An enchanted stone door swinging shut: heavy stone thud and the magical hum fading out |
| magic_door_refuse | Gen | 1.5 s | | 3 | A warded door refusing to open: a dull resonant thrum, a low buzzing hum and a heavy unmoving thunk |
| lever_pull | Gen | 1.5 s | | 3 | A heavy iron lever pulled down: grinding iron pivot, a hard clunk, a chain rattling inside the wall (replaces `switch.wav` on the lever) |
| magic_switch_on | Gen | 1.5 s | | 3 | A crystal switch activated by a spell: a bright crystalline chime and a short rising energy hum |
| magic_switch_off | Gen | 1 s | | 2 | A crystal switch going dark: a soft falling glassy tone and the hum dying away |
| pressure_plate_down | Gen | 1 s | | 3 | A stone pressure plate sinking into the floor: a heavy stone click, a thunk and a faint mechanism inside |
| pressure_plate_up | Gen | 1 s | | 2 | A stone pressure plate rising back into place: a soft stone scrape and a click |
| block_push_loop | Lib | 3 s | Loop | 3 | A heavy stone block pushed slowly across a stone floor: rough grinding scrape, steady, seamless |
| statue_rotate | Gen | 2 s | | 3 | A heavy stone statue turned on its base: grinding stone rotation and a solid click into place |
| statue_puzzle_solved | Gen | 3 s | | 4 | An old stone mechanism unlocking after a puzzle is solved: a deep clunk, a cascade of clicks and a warm low chime |
| gear_loop | Gen | 5 s | Loop | 3 | Large wooden and iron clockwork gears turning slowly inside a castle wall: rhythmic creaking teeth and heavy ticks, seamless |
| shifting_stair_move | Gen | 6 s | | 4 | A huge stone staircase swinging to a new position: a deep grinding rumble, creaking stone and a heavy echo in a tall stairwell |
| shifting_stair_settle | Gen | 2 s | | 3 | A massive stone staircase locking into place: a deep boom echoing in a tall hall, a little dust falling |
| trick_step_drop | Gen | 1.5 s | | 3 | A stair step suddenly giving way: a loose stone clack, a hollow sinking thunk |
| trick_step_reset | Gen | 1.5 s | | 2 | A stone stair step sliding back up into place with a soft grind and a click |
| rail_gate_move | Lib | 4 s | | 3 | A heavy iron portcullis gate rising: rattling chains, iron grating clanking, a winch creaking |
| platform_move_loop | Gen | 4 s | Loop | 3 | A floating stone platform drifting through the air by magic: a low stone rumble mixed with a soft steady magical hum, seamless |
| clue_found | Gen | 2 s | | 4 | Finding a clue: a soft intriguing shimmer and two gentle chimes, curious and quiet |
| mystery_solved | Gen | 4 s | | 4 | A great secret solved: a rising swell of shimmering chimes, a deep warm resonant boom and a long glowing ring-out |

Built (2026-10-21): all of them. `shifting_stair_move` is a loop (`shifting_stair_move_loop`) that runs for the whole 7 s swing; `clue_found` and `mystery_solved` live with the UI sounds (`ui_clue_found`, `ui_mystery_solved`); `magic_door_refuse` is heard at a house door turning someone away.

## 4. Doors and furniture

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| door_wood_open | Lib | 2 s | | 3 | A heavy old oak door opening: long iron hinge creak, wood groan (replaces `door.wav` on `castle_door`) |
| door_wood_close | Lib | 1.5 s | | 3 | A heavy oak door closing: a solid deep thud and an iron latch clicking |
| door_ceremonial_open | Gen | 4 s | | 3 | Enormous double castle doors swinging open into a great hall: deep groaning wood, huge iron hinges, a booming echo |
| door_ceremonial_close | Gen | 3 s | | 2 | Enormous double castle doors closing: a huge booming thud echoing through a stone hall |
| house_door_open | Gen | 2.5 s | | 3 | An enchanted door recognising its house member: a soft welcoming chime, then a heavy wooden door swinging open |
| house_door_refuse | Gen | 1.5 s | | 3 | An enchanted door refusing a stranger: a dull wooden knock-back, a low disapproving hum |
| chest_open | Gen | 1.5 s | | 3 | An old wooden chest with iron bands opening: a latch flip, a creaky hinge, a soft wooden thump against the back |
| chest_close | Gen | 1 s | | 2 | An old wooden chest lid closing with a heavy wooden thud and a latch click |
| wardrobe_open | Gen | 1.5 s | | 2 | A tall old wooden wardrobe door opening: a long creak and a gentle wooden knock |
| curtain_draw | Gen | 1.5 s | | 2 | Heavy velvet bed curtains drawn along an iron rail: a soft swish and rings sliding |
| window_shutter | Gen | 1.5 s | | 2 | Wooden window shutters swinging open in a stone castle: a creak and a wooden clap |

Built (2026-10-21): every door but `house_door_refuse` (a house door refusing plays `magic_door_refuse`). Not made: chests, wardrobe, curtains, shutters (furniture has no interaction yet).

## 5. School life and classrooms

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| school_bell_stroke | Gen | 6 s | | 4 | A single stroke of a large bronze bell in a castle tower, heard from inside: a deep rich strike with a long shimmering decay (replaces the synthesised bell in `SchoolBells`) |
| sorting_stone_wake | Gen | 3 s | | 4 | An ancient standing stone awakening: a deep low hum building, a grinding stone rumble and a rising glow-like shimmer |
| sorting_reveal_drakoryn | Gen | 3 s | | 4 | A great dragon's deep rumbling growl that swells into a burst of roaring flame and a heavy resonant gong |
| sorting_reveal_grypheon | Gen | 3 s | | 4 | A fierce eagle cry, powerful wings beating twice and a bright gust of high mountain wind |
| sorting_reveal_phoenara | Gen | 3 s | | 4 | A bright, soaring bird trill rising into a bloom of warm crackling fire and shimmering golden chimes |
| sorting_reveal_hipporys | Gen | 3 s | | 4 | A spirited horse whinny blended with a crashing ocean wave and a single great wingbeat |
| house_points_gain | Gen | 2 s | | 4 | Points awarded to a house: a quick rising cascade of crystal chimes and a soft swell of light-like shimmer |
| house_points_loss | Gen | 1.5 s | | 3 | Points taken from a house: a short falling sequence of glassy tones, dim and disappointed |
| house_column_loop | Gen | 5 s | Loop | 2 | Four tall crystal columns full of glowing light: a very soft deep resonant hum with a faint sparkle, seamless |
| feast_appears | Gen | 3 s | | 3 | A grand feast appearing on long tables by magic: a soft whoosh, then a wave of plates, goblets and cutlery settling with clinks |
| notice_pinned | Gen | 1 s | | 2 | A parchment notice pinned to a wooden board: a paper rustle and a tack pushed into wood |
| book_page_turn | Lib | 1 s | | 2 | Turning a thick old parchment page in a heavy book |
| book_open_heavy | Gen | 1.5 s | | 3 | A huge old leather-bound book opened on a lectern: a creak of the spine and a soft thump of pages, played as the spell tome opens |
| quill_writing | Lib | 3 s | Loop | 2 | A quill scratching on parchment, steady writing, close, seamless |
| chalk_writing | Lib | 3 s | Loop | 2 | Chalk writing on a slate board, steady, seamless |
| cauldron_bubble_loop | Gen | 6 s | Loop | 3 | A thick potion bubbling in an iron cauldron over a fire: slow gloopy bubbles, soft pops, gentle simmer, seamless |
| potion_pour | Gen | 1.5 s | | 3 | Pouring a thick potion from a glass vial into a cauldron: a viscous glug and a fizzing hiss |
| potion_brew_success | Gen | 2 s | | 3 | A potion finished correctly: a bright fizzing bubble burst and a clear glass chime |
| potion_brew_fail | Gen | 2 s | | 3 | A potion going wrong: a thick gloopy burp, a puff of smoke and a dull sputter |
| telescope_adjust | Gen | 1.5 s | | 2 | A brass telescope adjusted on its mount: smooth metal sliding, a gear click and a lens ring turning |
| crystal_ball_loop | Gen | 5 s | Loop | 2 | A crystal ball glowing on a table: a soft swirling airy hum, misty and mysterious, seamless |
| abacus_clack | Gen | 1.5 s | | 2 | Wooden beads on a large old abacus slid quickly: several crisp clacks |
| rune_stone_glow | Gen | 2 s | | 3 | Ancient carved runes lighting up on a standing stone: a low stony hum and a rising warm shimmer |
| globe_spin | Gen | 2 s | | 2 | A large old wooden globe spun on its brass stand: a smooth whirring spin slowing with soft ticks |
| creature_paddock_loop | Lib | 10 s | Loop | 2 | Animals in a wooden paddock: soft snorts, hooves shifting on straw, an occasional wing flutter, seamless |

Built (2026-10-21): bell, sorting stone and reveals, house points and columns, feast, notice, page turn, heavy book, chalk (a short one-shot), cauldron and potions, paddock (with the ambiences, `assets/audio/ambience/`). Not made: quill, telescope, crystal ball, abacus, rune stone, globe (decorations only).

## 6. Brooms and flying

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| broom_take | Gen | 1 s | | 2 | A wooden broom lifted off a wooden rack: a light wooden clack and a bristle rustle (replaces `pickup.wav` on `broom_rack`) |
| broom_return | Gen | 1 s | | 2 | A wooden broom hung back on a wooden rack: a soft wooden knock |
| broom_takeoff | Gen | 1.5 s | | 3 | Kicking off the ground on a flying broom: a quick rising whoosh of air and robes flapping |
| broom_flight_slow_loop | Gen | 6 s | Loop | 3 | Flying slowly through open air: gentle wind rushing past, robes fluttering softly, seamless |
| broom_flight_fast_loop | Gen | 6 s | Loop | 3 | Flying very fast through the sky: strong wind roaring past the ears, robes flapping hard, seamless |
| broom_land | Gen | 1 s | | 3 | Landing from flight: feet hitting the ground with a soft thump and the wind dying down |
| goal_ring_pass | Gen | 1.5 s | | 3 | Flying through a floating hoop: a bright quick whoosh and a clear rising chime |

Built (2026-10-21): all but `broom_return` (brooms are never handed back). The flight loops blend by speed; `goal_ring_pass` is a Lantern Chase goal.

## 7. Player

No vocal grunts: characters are customisable, so a voice would clash with many of them.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| footstep_stone | Lib | 0.4 s | | | Shoes walking on stone flagstones in a castle corridor, single step (8 variations) |
| footstep_wood | Lib | 0.4 s | | | Shoes on old creaky wooden floorboards, single step (8 variations) |
| footstep_carpet | Lib | 0.4 s | | | Shoes on thick carpet or rug, soft single step (8 variations) |
| footstep_grass | Lib | 0.4 s | | | Shoes on grass, single step (8 variations) |
| footstep_gravel | Lib | 0.4 s | | | Shoes on a gravel path, single step (8 variations) |
| footstep_water | Lib | 0.4 s | | | Shoes splashing in shallow water, single step (8 variations) |
| footstep_metal | Lib | 0.4 s | | | Shoes on an iron grate or metal walkway, single step (8 variations) |
| jump | Gen | 0.6 s | | 3 | A person jumping in long robes: a quick cloth whoosh and a light push-off scuff |
| land_soft | Gen | 0.6 s | | 3 | Landing on a stone floor from a small jump: a soft thump and a cloth rustle |
| land_hard | Gen | 0.8 s | | 3 | Landing heavily on stone from a big fall: a solid thud and a robe flap |
| hurt | Gen | 0.6 s | | 3 | A magical hit landing on a person: a dull thump with a short crackle of sparks, no voice (replaces the unused `hurt.wav`) |
| respawn | Gen | 2.5 s | | 3 | A person reforming from swirling light at a magical waypoint: a soft whoosh pulling inward, a bright shimmer, a gentle thump |
| checkpoint_activate | Gen | 2 s | | 3 | A magical waystone attuning to a traveller: a low stone hum and a warm rising chime |
| fragment_collect | Gen | 1 s | | 3 | Collecting a small glowing magical crystal fragment: a bright sparkling chime and a tiny whoosh (replaces `pickup.wav` on `arcane_fragment`) |
| item_pickup | Gen | 0.8 s | | 3 | Picking up a small object and putting it in a leather satchel: a quick rustle and a soft thud |
| torch_held_loop | Lib | 6 s | Loop | 2 | A hand-held torch burning while carried: crackling flame with a slight swishing movement, seamless |

## 8. Crystal guardian

The current enemy, `characters/enemies/crystal_guardian.tscn`.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| guardian_idle_loop | Gen | 5 s | Loop | 3 | A large living crystal construct standing still: a low resonant glassy hum with slow faint grinding, seamless |
| guardian_alert | Gen | 1.5 s | | 3 | A crystal construct noticing an intruder: a sharp rising crystalline ring and a grinding shift of heavy crystal |
| guardian_attack | Gen | 1.5 s | | 3 | A crystal construct charging and releasing a blast: a rising glassy whine and a sharp crystalline crack |
| guardian_hit | Gen | 0.8 s | | 3 | A spell striking a large crystal body: a hard glassy clank and a ringing chip of crystal |
| guardian_shatter | Gen | 2.5 s | | 3 | A large crystal construct shattering: a deep crack, a cascade of breaking glass and crystal shards scattering on stone |

Built (2026-10-21): all five, through `Enemy`'s sound exports on `crystal_guardian.tscn`.

## 9. UI

Soft, short and quiet; parchment, wood and glass, matching the world.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| ui_hover | Gen | 0.2 s | | 2 | A very soft short wooden tick, subtle interface hover sound |
| ui_click | Gen | 0.3 s | | 3 | A soft crisp click of a small wooden button, gentle interface confirm sound |
| ui_back | Gen | 0.3 s | | 2 | A soft muted wooden tap, lower in pitch, gentle interface cancel sound |
| ui_panel_open | Gen | 0.6 s | | 3 | A parchment sheet unrolled quickly: a short paper swish and rustle |
| ui_panel_close | Gen | 0.5 s | | 2 | A parchment sheet rolled up quickly: a short paper swish |
| ui_map_open | Gen | 1 s | | 3 | A large folded parchment map opened out: crinkling paper unfolding, a soft flap |
| ui_inventory_open | Gen | 0.6 s | | 2 | A leather satchel flap opened: a soft leather creak and buckle jingle |
| ui_chat_message | Gen | 0.3 s | | 3 | A very soft short glass tap, subtle notification for a new chat message |
| ui_dm_received | Gen | 0.8 s | | 3 | A gentle two-note glass chime, warm and personal, a private message arriving |
| ui_notification | Gen | 0.8 s | | 3 | A soft single bell-like chime, gentle notification |
| ui_error | Gen | 0.4 s | | 2 | A soft dull wooden knock, low pitched, gentle error sound |
| ui_spell_select | Gen | 0.4 s | | 2 | A tiny glassy shimmer with a soft click, choosing a spell |

## 10. Ambiences

Loops per area, keyed by `AreaZone`. Most are best from a library: real rooms and nature loop cleanly. The **Gen** ones are the magical rooms a library won't have. For each **Lib** row, record two or three 30 s variants if you can, so the loop doesn't get recognisable.

| ID | Source | Len | Loop | Takes | Prompt |
|---|---|---|---|---|---|
| amb_great_hall_busy | Lib | 30 s | Loop | | A large stone dining hall full of students: crowd murmur with no clear words, cutlery and plates clinking, benches scraping, big reverb |
| amb_great_hall_empty | Lib | 30 s | Loop | | A huge empty stone hall at night: deep quiet room tone, a distant draught, faint creaks, long reverb |
| amb_corridor | Lib | 30 s | Loop | | An old stone castle corridor: quiet airy room tone, a soft draught, very distant footsteps and a far-off door |
| amb_library | Lib | 30 s | Loop | | A quiet old library: hushed room tone, an occasional page turn, a creaking shelf, a soft cough far away |
| amb_dungeon | Lib | 30 s | Loop | | A damp stone dungeon: slow water drips echoing, low cold air rumble, an occasional distant iron creak |
| amb_cellars | Lib | 30 s | Loop | | Old vaulted cellars under a castle: low muffled room tone, slow drips, wooden barrels creaking |
| amb_tower_wind | Lib | 30 s | Loop | | Inside a tall stone tower: wind howling softly around the walls and through narrow windows |
| amb_battlements | Lib | 30 s | Loop | | Up on open castle battlements: strong steady wind, flags flapping, distant birds far below |
| amb_common_room | Lib | 30 s | Loop | | A cosy common room: a crackling fireplace, soft distant chatter with no clear words, an armchair creaking |
| amb_dormitory_night | Lib | 30 s | Loop | | A quiet dormitory at night: embers in a fireplace, a slow clock ticking, wind against the window |
| amb_kitchens | Lib | 30 s | Loop | | A busy old castle kitchen: pots clanking, sizzling pans, a bubbling stew, a roaring hearth, no voices |
| amb_greenhouse | Lib | 30 s | Loop | | A warm humid greenhouse: dripping water, soft insects buzzing, leaves rustling, rain gently on the glass roof |
| amb_bathing_hall | Lib | 30 s | Loop | | A large stone bathing hall: water gently flowing into a pool, drips and splashes, wet echo |
| amb_roost | Lib | 30 s | Loop | | A high stone roost full of birds: wings fluttering, soft cooing and rustling feathers, wind at the openings |
| amb_classroom_elixirs | Gen | 30 s | Loop | 2 | A dim stone classroom full of cauldrons: several potions bubbling and simmering at once, glass vials clinking softly, low fire under the cauldrons |
| amb_clock_tower | Gen | 30 s | Loop | 2 | Inside a giant clock tower: huge gears turning slowly, a deep heavy tick and tock, chains and pendulum creaking, wind outside |
| amb_star_tower_night | Gen | 30 s | Loop | 2 | The top of an open astronomy tower at night: soft cold wind, a very faint high shimmering hum like starlight, brass instruments creaking |
| amb_divination_room | Gen | 30 s | Loop | 2 | A stuffy round attic classroom: soft swirling airy hum of crystal balls, a crackling fire, curtains rustling, mysterious and warm |
| amb_duelling_hall | Gen | 30 s | Loop | 2 | A large empty duelling hall: deep stone room tone, a faint lingering magical hum in the air, long reverb |
| amb_hidden_room | Gen | 30 s | Loop | 2 | A forgotten secret chamber: still dusty air, a very low resonant hum, faint distant drips, ancient and mysterious |
| amb_stone_circle | Gen | 30 s | Loop | 2 | An ancient stone circle on a windy hill: steady wind through tall grass and a very low otherworldly hum from the stones |
| amb_restricted_stacks | Gen | 30 s | Loop | 2 | A locked section of an ancient library: deep silence, old books creaking on their shelves, a faint uneasy low hum |
| amb_grounds_day | Lib | 30 s | Loop | | Open countryside meadow by a castle in daytime: birdsong, a gentle breeze in the grass, distant sheep |
| amb_grounds_night | Lib | 30 s | Loop | | A countryside meadow at night: crickets, a gentle breeze, an owl hooting far away |
| amb_forest | Lib | 30 s | Loop | | A deep old forest: wind in tall trees, creaking branches, distant birds, leaves rustling |
| amb_forest_night | Lib | 30 s | Loop | | A dark forest at night: wind in trees, crickets, twigs snapping far off, an owl |
| amb_lake_shore | Lib | 30 s | Loop | | The shore of a large lake: small waves lapping on stones, wind over water, birds |
| amb_river | Lib | 30 s | Loop | | A fast mountain river and stream: rushing water over rocks |
| amb_boathouse | Lib | 30 s | Loop | | An old wooden boathouse: water lapping under the boards, boats knocking gently, ropes creaking |
| amb_rain_outdoor | Lib | 30 s | Loop | | Steady rain falling on grass and stone |
| amb_rain_window | Lib | 30 s | Loop | | Rain heard from inside a stone room, pattering on a leaded window |
| thunder | Lib | 6 s | | | Distant rolling thunder over hills (4 variations) |

Built (2026-10-21) with the MCP's 5 s limit: each loop is three 5 s takes spliced into a ~12 s seamless loop, stored as MP3 with its first 2 s repeated so `AmbienceDirector` crossfades it into itself; thunder is four 5 s rolls. Not made: `amb_divination_room`, `amb_river` (no such places).

## 11. Music

All tracks: **instrumental, no vocals**. One musical identity across them, chosen by the owner after the first sketches (2026-10-16): a **magical symphony orchestra** with a **celesta** as the signature voice, shimmering strings, harp, woodwind runs and warm horns, often in a lilting 3/4 and in minor keys with chromatic, mysterious turns. Folk-style instrumentation was tried and rejected.

**Never name a film, game, theme or composer in a prompt, and throw away any take that sounds recognisably like an existing theme.** We want that feeling, with melodies of our own.

**Status:** ✅ in game: generated and playing · ✅ prompt approved · 🎧 sketching · ⬜ not started.

| ID | Status | Length | Takes | Loop | Prompt |
|---|---|---|---|---|---|
| music_castle_day | ✅ in game | 2:00 | 2 | Loop | Enchanted, sparkling orchestral music for exploring a magical castle, instrumental, no vocals. Full symphony orchestra. A glittering celesta melody leads in a lilting 3/4 waltz, in a minor key with chromatic, mysterious turns, over shimmering high strings and soft harp arpeggios. Woodwinds answer with playful runs, warm French horns and gentle swells of the full orchestra underneath. Wondrous, whimsical and a little mysterious, like candlelight in old stone towers. Moderate tempo, about 90 BPM. Background exploration music: even energy, no big climax, loops cleanly. |
| music_castle_night | ✅ in game | 2:00 | 2 | Loop | Dark, hushed, sneaking orchestral music for creeping through a magical castle at night, instrumental, no vocals. Symphony orchestra played very quietly: soft pizzicato low strings tiptoeing in a slow 3/4, a muted celesta playing a sparse, chromatic minor melody, a low bass clarinet and bassoon answering in the shadows, distant muted horns, high string harmonics like moonlight. Secretive, calm and a little mischievous, never scary or dramatic. Slow tempo, about 68 BPM. Background music: even, low energy throughout, no climax, loops cleanly. |
| music_main_theme | ✅ in game | 2:00 | 3 | | Original magical main theme for a wizarding school, instrumental, no vocals. Full symphony orchestra. Opens with a solo celesta melody in a lilting 3/4 waltz, in a minor key with chromatic, mysterious turns, over soft harp and shimmering strings. The melody passes to flutes and then to the whole orchestra with warm French horns and a sweeping string climax, then fades back to the lone celesta. Wondrous, mysterious and hopeful. About 92 BPM. |
| music_lesson | ✅ in game | 2:00 | 2 | Loop | Gentle, focused orchestral music for a lesson in a magical classroom, instrumental, no vocals. Light symphony orchestra, mostly soft strings, harp and a quiet celesta, with an occasional warm clarinet line. Calm, studious and a little wondrous, unobtrusive so text can be read over it. Slow, about 72 BPM, very even energy, loops cleanly. |
| music_grounds | ✅ in game | 2:00 | 2 | Loop | Open, airy orchestral music for walking the green hills, lake and forest around a magical castle, instrumental, no vocals. Symphony orchestra: a soaring flute and oboe melody over broad sustained strings, rippling harp and celesta sparkles, warm horns underneath. Free, bright and wondrous, with a hint of mystery. About 90 BPM, steady energy, no big climax, loops cleanly. |
| music_feast | ✅ ready (needs its event) | 2:00 | 2 | Loop | Warm, festive orchestral music for a grand candlelit feast in a castle hall, instrumental, no vocals. Symphony orchestra in a bouncy 3/4: bright strings, cheerful woodwind runs, glockenspiel and celesta sparkles, warm horns, light timpani. Joyful and bustling but not loud, magical rather than medieval. About 112 BPM, steady energy, loops cleanly. |
| music_flying | ✅ in game | 2:00 | 2 | Loop | Soaring, exhilarating orchestral music for flying on a broom over a magical castle and lake, instrumental, no vocals. Full symphony orchestra: rushing string runs, a bold French horn melody, sweeping harp glissandi, celesta and glockenspiel sparkles, driving timpani. Adventurous and joyful, a sense of height and wind. About 126 BPM, steady energy, loops cleanly. |
| music_mystery | ✅ ready (needs its event) | 2:00 | 2 | Loop | Tense, curious orchestral music for discovering secret passages in a magical castle, instrumental, no vocals. Symphony orchestra: a low pulsing string ostinato, plucked harp, ticking woodblock, sparse chromatic celesta notes, a creeping bass clarinet, muted horns. Quiet suspense, a puzzle about to open. About 80 BPM, even energy, loops cleanly. |
| music_duel | ✅ ready (needs its event) | 2:00 | 2 | Loop | Energetic, competitive orchestral music for a wizards' duel in a grand stone hall, instrumental, no vocals. Full symphony orchestra: driving staccato strings, bold brass stabs, rolling timpani and snare, fast woodwind flourishes, flashes of celesta. Exciting and sporting rather than dark. About 140 BPM, steady energy, loops cleanly. |
| music_sorting | ✅ ready (needs its event) | 1:30 | 2 | | Solemn, magical ceremony music for new students joining their houses, instrumental, with soft wordless choir. Symphony orchestra: opens hushed with sustained strings and a lone celesta in 3/4, swells with harp, woodwinds and warm horns into a proud, glowing climax, then resolves gently. Slow, about 70 BPM. |
| music_house_cup | ✅ ready (needs its event) | 0:30 | 3 | | A short triumphant orchestral fanfare for winning the school house cup, instrumental, no vocals. Full symphony orchestra: bright brass fanfare, rolling timpani, sweeping strings, glittering celesta and glockenspiel, ending on a big satisfying final chord. |
