# Roadmap: from castle MVP to a living school of magic

This is a brainstorm and a roadmap. `docs/plan.md` stays the implementation tracker: when a roadmap item is picked up it moves there as a milestone with checkboxes. Every name below is a **placeholder** (marked *like this*) until the owner picks the final one. The franchise is the design reference only: nothing here may borrow its names, places, creatures or spell names.

Size tags: **S** a few days · **M** one to two weeks · **L** several weeks. Impact tags: ★ nice, ★★ clearly felt, ★★★ defines the game.

---

## 1. Where we are (October 2026)

Already built: one continuous castle on six storeys (54 areas, generator-driven), modular production assets (walls, floors, pillars, doorways, desks, shelves, chandeliers, torches), 11 spells as data with a hotbar, server-owned profiles (house, role, spellbook), sorting at the Choosing Stone, house-gated common rooms, live lessons v1 (open a lesson, grant spells, lecture text, house points with a ledger, lesson plans), server-authoritative world objects, data-driven mysteries (server-only online, public practice versions offline), dungeon guardians (local), inventory with a held torch, chat, PL/EN localisation, export presets with a leak check.

What a player does not feel yet:

- **Time.** There is no school day: no bells, no timetable, no meals, no night, no term. A school is a rhythm, and right now the castle is a museum.
- **A body.** The player is a placeholder capsule. No robes, no house colours, no sitting, no raising a hand.
- **People when nobody is online.** With no professor online there is no lesson; with nobody online the castle is empty. Low population will be the normal case for a long time.
- **Growth.** Spells arrive, but there are no years, grades, exams, homework or mastery: nothing that says "I was a first-year and now I am a third-year".
- **A living castle.** No residents (portraits, ghosts, caretaker, creatures), no rumours, no changes over days and seasons.

The roadmap below is ordered to fix those five, in roughly that order.

---

## 2. What makes it feel like a real school of magic

Use these pillars to judge every feature: if an item does not strengthen at least one, it waits.

1. **Rhythm.** The day has a shape (morning bell, lessons, meals, free time, curfew) and the year has a shape (arrival, term, exams, house cup, holidays).
2. **Belonging.** Your house is your family: colours on your robes, a common room that feels like home, points you earned for it, people who wear the same crest.
3. **Learning that is visible.** You sat in a class, the professor taught you something, and now you can do a thing you could not do yesterday. Grades, years, mastery and a spellbook that fills up.
4. **Wonder and secrets.** The castle hides things, changes, and rewards curiosity. There is always a rumour about a room nobody has found.
5. **Ritual and ceremony.** Sorting in front of everyone, the start-of-term feast, the cup ceremony, duels with a bow first, exams in a silent hall.
6. **Rules and mischief.** Curfew, out-of-bounds areas, detention, a caretaker on patrol. Rules exist so breaking them is exciting.

---

## 3. Offline vs online: what each mode is for

Today offline is "the castle without a server". It should become a real mode with its own purpose, while the school itself stays online.

### Principles

- **Online is the school.** Your real character, house, spellbook, grades and points live on the server and are earned only online. This keeps progression fair and keeps professors meaningful.
- **Offline is the prologue, the practice yard and the sightseeing tour.** It never writes to the online character (anything client-side can be edited). Offline rewards stay local: practice scores, an offline spellbook, photo-mode unlocks.
- **One content format for both.** Offline NPC lessons, mysteries and quizzes use the same data shapes as their online counterparts (like `content/offline_mysteries.json` already does), with public offline variants so server secrets never ship.
- **Offline is also the fallback** when the server is down or the player has no connection: the menu offers it automatically (already true) and explains what is not saved.

### Offline mode feature set

| Feature | Description | Size | Impact |
|---|---|---|---|
| **Prologue: *The Night Before Term*** | A guided first hour: arrival sequence at dusk, an NPC prefect leads you through the entrance hall, you are sorted (locally), an NPC professor teaches you your first spell, you find your first secret, you reach your common room. Ends with "Your first term begins online". Doubles as the tutorial for movement, interaction, casting, hotbar and chat. | L | ★★★ |
| **NPC lessons** | Scripted lessons run by an NPC professor from the same lesson-plan format human professors use (lines + "demonstrate" + "practise" + "quiz" steps). Teaches spells to the *offline* spellbook. | M | ★★★ |
| **Practice yard** | Spell drills (targets, timed sequences, moving targets), a duelling dummy that blocks and counters, obstacle courses for movement and flying. Score boards stored locally. | M | ★★ |
| **Trial rooms** | Short self-contained puzzle chambers (the existing `levels/mvp` chain is the seed). Each has a par time and a hidden extra. | M | ★★ |
| **Castle tour mode** | A free-roam "visitor" mode with all public areas open, area descriptions and lore plaques. Great for showing friends, streamers and the store page trailer. | S | ★ |
| **Photo mode** | Free camera, depth of field, filters, hide HUD, poses. Works offline and online. | S | ★★ |
| **Offline save slots** | Local save of offline spellbook, discoveries, practice scores. Clearly labelled "practice save". | S | ★ |
| **Solo campaign (later)** | A story-driven offline school year with NPC classmates, an original mystery plot across the castle, exams and an ending. Only once the online core is solid; it reuses every system built for online. | L+ | ★★★ |

### Online mode feature set

| Feature | Description | Size | Impact |
|---|---|---|---|
| **Live lessons 2.0** | Board writing, quizzes, practice tasks, attendance, grades (section 4, Term B). | M–L | ★★★ |
| **Self-study lessons** | When no professor is online, an automated lesson runs from an approved lesson plan at scheduled times. It can teach only spells marked "self-study" by the owner, so human-led lessons keep the best spells. *Owner decision needed.* | M | ★★★ |
| **Server timetable and bells** | Real-time schedule (e.g. weekly lessons at fixed hours, Polish time) shown on notice boards and in the journal; bells and announcements before each lesson. | M | ★★★ |
| **Feasts and ceremonies** | Scheduled great hall events: start-of-term feast, sorting ceremony with an audience, house cup ceremony. Admin speaks to the whole hall. | M | ★★★ |
| **Community mysteries** | Server-wide puzzles that need many players or all four houses (each house holds a piece). Weekly rotating mystery. | M | ★★ |
| **Duelling club** | Consent-based duels in a duelling hall run by a professor (Term F). | L | ★★★ |
| **Clubs and societies** | Player-run groups with a meeting room booking, notice board posts and a badge. | M | ★★ |
| **Messages, friends, DMs** | DMs delivered as in-world *paper birds* that fly to the recipient; friend list; "where is my friend" (area only, if they allow it). | M | ★★ |
| **Private schools** | Self-hosted or rented servers for roleplay communities and friend groups, with their own professors and house cup. Possibly the strongest long-term growth channel for this genre. | L | ★★★ |
| **Moderation** | Must exist before any public launch (section 7). | M | required |

---

## 4. Roadmap by terms

Each "term" is a batch of milestones with one theme, ordered by what the player feels most. Terms can overlap; the order inside a term is the suggested build order.

### Term A: "The school has a heartbeat" (rhythm + a body)

Goal: an hour online feels like a day at school, even with three players.

1. **Day/night cycle and the school clock** (M ★★★). *Done (Milestone 34), torches lit at dusk included; night-only content still open.* One in-game day per N real minutes for atmosphere (sky, sun/moon, window light, torches lit at dusk), separate from the real-time timetable. Server owns the clock; clients interpolate. Night unlocks things (stargazing tower, night creatures, curfew).
2. **Bells and the timetable** (M ★★★). *Done (Milestone 35): real-time timetable from `nakama/content/timetable.json`, bells, notice boards, week panel, HUD line; attendance records and admin editing still open.* `TimetableDefinition` as data (subject, classroom, weekday, hour, professor or self-study). Notice boards in the entrance hall and common rooms render it. Bells ring castle-wide; a HUD toast "Herb Lore begins in 5 minutes in the greenhouse".
3. **Player character v1** (L ★★★). Real model replacing the capsule (Meshy + Mixamo pipeline already proven on the guardian). Base robe that takes house colours and crest after sorting; a few faces, hairstyles and skin tones; a simple character creator on first join (server stores the choices).
4. ~~**Social animations and seats**~~ (built: Milestone 40, procedural gestures, seats on every bench/chair/sofa, raised-hands queue). (M ★★★). Sit on benches and chairs (interaction), raise hand, wave, bow, clap, point, shrug, take notes. Professors see a "raised hands" queue in their lesson panel. Cheap and it instantly reads as a classroom.
5. ~~**Chat bubbles and proximity rings**~~ (built: Milestone 39, server-routed say / whisper / shout, DMs with an offline mailbox, speech bubbles). (S ★★). Speech bubbles over heads for proximity chat, faded by distance; "whisper" (very short range) and "shout" (larger range, rate limited). Lecture text shows as a bigger bubble on the professor plus the board.
6. **Meals in the great hall** (S–M ★★). Food appears on the feast tables at mealtimes (VFX), players can sit and eat (animation, no stats). The hall fills, which is the point.
7. **Ambient audio pass** (M ★★). Area ambiences (hall chatter, wind in towers, dripping dungeons), footsteps per surface, reverb per area (`AreaZone` already knows the area), bells, music that changes with time of day.

### Term B: "I am learning magic" (lessons 2.0 + progression)

Goal: attending a lesson is fun, and progress over weeks is visible.

1. **Writing on the board** (S ★★★). The professor's lecture lines and a "board" text field render onto the classroom's slate or wall board (the props already exist). Everyone in the room sees it; it persists for the lesson.
2. **Quizzes** (M ★★★). The professor asks a question (open or multiple choice, from the lesson plan or typed live); students answer in a small panel; the professor sees answers live and can award points per answer. Server collects and stores results. Already listed in `plan.md` as "questions to students".
3. **Practice tasks** (M ★★★). The professor starts a practical: "levitate the feather into the bowl", "light the three candles in order", "mend the cracked vase". Tasks are world objects with success rules (reuse the mystery step engine). Completion is required before the spell is granted, so learning means doing.
4. **Spell mastery** (M ★★). Each known spell has a mastery level that grows with successful use in lessons, practice tasks and puzzles. Mastery adds visible polish (bigger effect, shorter cooldown, a cleaner casting gesture), never raw PvP power before duels exist.
5. **Casting gestures** (M ★★). Optional: hold cast and trace a simple rune shape with the mouse or stick; a clean shape gives a stronger cast or is required for some spells. Makes casting a skill and lessons something to practise. Keep a simple click mode for accessibility.
6. **Years and the school journal** (M ★★★). Characters belong to a year (*First Circle* … *Seventh Circle*, placeholder). The *journal* (in-game book UI) shows timetable, spellbook with mastery, grades per subject, discoveries, house points earned, current homework.
7. **Homework** (M ★★). The professor sets a task at the end of a lesson: a short written answer (text, submitted to the professor), "find the plaque in the library that names…", "bring three glowcaps from the greenhouse". Professors grade from a panel; grades go into the journal.
8. **Grades and end-of-term exams** (L ★★★). Per-subject grade from attendance, quizzes, practicals and homework. An exam week: written quiz in the great hall (desks rearranged, silence rule: proximity chat off), practical exam in each classroom. Passing all core subjects advances the year. Exams can run as self-study events so they happen even without professors.
9. **Library and lore books** (M ★★). Readable books on shelves (original lore, written per subject); some answer quiz and homework questions, some contain clues to mysteries. A *sealed stacks* section opens only with a permission slip a professor grants (an item, server-side).

### Term C: "My house is my family" (belonging)

1. **House crests and banners** (S–M ★★★). Crests for Drakoryn, Grypheon, Phoenara, Hipporys on doors, banners, robes, common rooms and the menu. Already in `plan.md`.
2. **Common rooms that feel like home** (M ★★★). Each one with its own style, fireplace, armchairs, notice board, trophy shelf. Unique entry rituals (a riddle of the week on the door, a gesture, a spell) instead of a plain door.
3. **Dormitories and personal space** (M ★★). A bed and trunk per player in the house dormitory; decorate it with earned items (pennants, trophies from mysteries, plants grown in Herb Lore). Visiting a friend's bed corner is a social activity.
4. ~~**The house tally monument**~~ (built: *House Columns*, `HouseTally`). An original in-world equivalent of the points display in the great hall: four crystal columns that fill with light in house colours, updated live from the ledger, with a small burst when points change.
5. **House cup and term ceremony** (M ★★★). At term end the great hall changes decor to the winning house's colours, the cup is awarded on stage, the winning house gets a cosmetic for next term.
6. **Prefects and heads of house** (M ★★). New roles between student and professor: prefects can deduct small amounts of points, lead first-years, patrol at night, and open their house's door for guests; a head of house (professor) sees house-wide stats and posts to the house board.
7. **House quests** (M ★★). Weekly house goals ("our house solves 3 mysteries", "100 practical tasks completed") with a house-wide reward. Gives low-population houses something to do together.

### Term D: "The castle is alive" (secrets and residents)

1. **Moving and shifting castle** (M ★★★). Some staircases rotate on a schedule, some corridors swap at night, a door that only appears on certain days. Server-owned state, so everyone sees the same castle. The generator's stair and door data make this cheap to author.
2. **Talking portraits** (M ★★★). Painted NPCs on walls who greet you by name, comment on your house, hint at mysteries, gossip about other players' achievements ("a Phoenara student found the loft yesterday…"), and act as messengers between portraits.
3. **The *Echoes*** (M ★★). Translucent memories of former students and staff, each tied to a part of the castle, with a short questline and lore. Original replacement for the classic ghost residents.
4. **Curfew and the night warden** (M ★★★). After curfew students outside their common room risk being caught by an NPC warden with a lantern familiar that patrols corridors (stealth: light, noise, line of sight). Caught → small point loss and a detention task. Some mysteries can only be done after curfew, which creates the best kind of risk.
5. **Detention tasks** (S–M ★★). Minigames assigned by professors, prefects or the warden: polish trophies, re-shelve the library, sort ingredients, scrub cauldrons. Sometimes detention leads to a secret (the trophy room has a hidden switch).
6. **A self-filling map** (M ★★). An enchanted map item (*Wayfinder's Chart*, placeholder) that draws the castle as you explore, marks discoveries, and can show house-mates' locations if they share. Hidden rooms stay hidden on it until found. *Started (plan M33): a castle map and minimap read from the generated level; hidden rooms already stay off it until found. Still open: the chart as an item, drawing only what you explored, house-mates.*
7. **Mystery chains per year** (L ★★★). Each school year has a story mystery spread across the castle, solved over a term (clues in books, portraits, Echoes, lessons). First-years cannot reach some parts; later years can. This is the long-term content engine; the mystery step engine already supports it.
8. **The *Unfinished Wing*** (L ★★★). A sealed part of the castle that the whole server opens room by room through community goals (points earned, mysteries solved). New content gets released as "the next room has opened", and every player shares the moment.
9. **Seasons and holidays** (M ★★). The grounds change over the year (autumn leaves, snow, spring blossom); holiday decorations in the great hall; a winter ball event; end-of-year farewell.
10. **Rumour board** (S ★). A notice board where anonymous rumours appear (authored by the owner or generated from server events): "Someone heard knocking behind the third bookshelf." Directs players toward secrets without spoiling them.

### Term E: "My people are here" (social)

1. **Friends, DMs as paper birds, offline mail** (M ★★). DMs fly to the recipient as a folded paper bird in the world (and land in the journal's inbox when they are offline).
2. **Emotes wheel and expressions** (S ★★). Ties to Term A animations.
3. **Clubs and societies** (M ★★). Player-created clubs with a board, a badge and a bookable room (astronomy club on the tower at night, a gardening society in the greenhouse, a chess-like game club).
4. **Board and parlour games** (M ★★). An original wizard board game playable at common-room tables; animated cards; a game with enchanted pieces. Great low-population content: two players are enough.
5. **Events calendar** (S ★★). In the journal: lessons, feasts, club meetings, duels, community mysteries, with reminders.
6. **Player profiles** (S ★). Click a nameplate: house, year, titles, favourite spell, discoveries count, club badges.

### Term F: "Sanctioned combat and sport" (duels, flying)

1. **Duelling club** (L ★★★). A duelling hall with a stage and an audience. A professor (or a prefect, later) runs a duel: both players accept, bow, a countdown, then spells hit each other only inside the arena volume. Server validates targets and damage; health is a separate duel meter so nothing persists. Rules sets: first to three hits, disarm only, shields allowed. Spectators cheer with emotes; house points stay professor-awarded, never wagered.
2. **Duel ladder** (M ★★). Ranked duels during scheduled club hours; season rewards are cosmetic.
3. **Flying lessons for real** (L ★★★). The broom and the flight mode exist (Milestone 13b: racks and a dev cheat hand them out, flying is outdoors only). Next: the Flying professor grants brooms in lessons instead of open racks, flight rules per area checked server-side, a modelled broom (the riding pose is procedural for now).
4. **An original flying sport** (L ★★★). Design proposal, *Lantern Chase* (placeholder): two teams of four fly around the grounds; one lit lantern per team must be carried through the opponents' rings; defenders try to snuff it with Galewind or Wellspring, carriers relight with Emberkindle. Uses existing spells, rewards teamwork, and is clearly our own. Inter-house matches feed the house cup.
5. **Shared enemies** (L ★★). Already planned (Milestone 17): server-authoritative guardians in the dungeons, co-op for groups, curfew-only spawns.

### Term G: "Beyond the walls" (grounds and the wider world)

1. **The grounds properly** (L ★★★). A lake with a water shader, a forest edge (forbidden at night, original name), the greenhouse in glass, the beast paddock with creatures, a stone circle, a boathouse, a clock tower. The castle silhouette visible from outside with lit windows. Planned as generated grounds in `docs/castle-generation.md` (Milestones 26–27).
2. **Herbology gardening** (M ★★). Plant, water, grow and harvest magical plants in the greenhouse (Quicksprout helps). Plants are ingredients for Potions.
3. **Potion brewing** (M ★★★). A cauldron minigame (order, stirring, heat, timing). Brewed potions are consumables (glow-in-dark, featherfall, voice-change, colour-change robes for an hour). Professors can grade the results.
4. **Care of Magical Creatures and familiars** (L ★★★). Original creatures to care for in lessons; later a personal familiar that follows you, sits on your shoulder, sleeps on your dorm bed. Huge for attachment.
5. **The village weekend** (L ★★). An original nearby village reachable on scheduled weekends: shops for cosmetics, a tea house to meet, a post office for paper birds. Needs an economy (below). The village itself is built (Milestone 36: high street, square, nine shops, an inn, a tea house, the post office, all walk-in areas with stable ids) together with the railway station where new players will arrive; next come the shop logic, the weekend schedule and the arrival flow.
6. **Economy (careful)** (M ★). A small currency earned by attendance, homework and events, spent on cosmetics and decoration. No buying spells or points. The currency exists (Milestone 37: server wallet with a ledger, paid for attending lessons and first mystery solves, daily cap, admin grants); next: something to buy in the village shops, homework and event rewards.

---

## 5. Visual roadmap

Ordered by "biggest change on screen per day of work".

### 5.1 Lighting (the single biggest win)

- **Bake the static castle.** `LightmapGI` for walls, floors and furniture lit by the fixed torches and chandeliers, then turn most of the 353 omni lights into baked-only or very short-range dynamic lights with distance fade. Keep dynamic light for the held torch, spells and a few hero lights. Better quality and far better performance. Alternative to evaluate first: SDFGI or VoxelGI per wing (no bake step, works with the generator, cost on GPU). Recommendation: spike both on two rooms, pick by look and frame time. (M ★★★)
- **Finish the lighting overhaul** already in `plan.md`: dim ambient so darkness is real, carried light matters, and night in the dungeons is scary. (S ★★★)
- **Windows and light shafts.** Real window modules with stained glass; volumetric fog with light shafts from windows by day and moonlight at night; colour cast from the glass on the floor. (M ★★★)
- **Per-area atmosphere.** `AreaZone` blends a WorldEnvironment profile per area: warm and hazy great hall, cold blue dungeons, green greenhouse, starry tower. Fog density, exposure, colour grading LUT. (S–M ★★)
- **Light flicker and life.** Candle and torch flicker already exists; add wind gusts that dim torches in corridors, magical floating candles in the great hall, glowing runes in the Ancient Runes classroom. (S ★★)

### 5.2 Materials and set dressing

- **Break repetition.** Two or three variants per wall module, random 180° flips, vertex colour or decal grime near floors, moss in the dungeons, scorch marks near the Potions room. (M ★★★)
- **Decals.** Rugs, cracks, stains, wax drips, chalk circles, house sigils painted on floors. Godot `Decal` nodes placed by the generator. (S ★★)
- **Clutter kits per subject.** Each classroom gets 10–20 props that say what it is: cauldrons and shelves of jars, telescopes and star charts, potted plants and trowels, cages and feeding buckets, crystal balls, abacus-like instruments, rune stones. Common rooms get armchairs, fireplaces, rugs, banners. This is the asset list to generate next. (L ★★★)
- **Trim sheets and hero materials.** Carved wood, worn stone stairs, iron fittings, gold leaf for the great hall. (M ★★)
- **Paintings and portraits** as props first (Term D makes them talk). (S ★★)

### 5.3 Exterior and sky

- Night sky with moon phases and real constellations (Astronomy lessons can use it), clouds, sunrise/sunset tied to the clock. (M ★★★)
- Terrain, trees, the lake (water shader with reflections), weather (rain on windows, snow on the grounds, fog in the morning). (L ★★★)
- A castle silhouette with towers, battlements and lit windows: the shot for the store page and the menu. (L ★★★)

### 5.4 Characters and animation

- Real player model, robes with house trim, hair and faces (Term A). Robe cloth: start with animated bones on the robe skirt; cloth sim only if cheap. (L ★★★)
- Casting animations per spell family (a flick, a sweep, a push, a two-handed lift), not one generic cast. (M ★★)
- Social animations (sit, raise hand, wave, bow, take notes). (M ★★★)
- NPC models: professors, portraits, the warden, Echoes, creatures. (L ★★)

### 5.5 Magic VFX

- One distinct look per spell: a casting circle at the hand, a trail with its own shape, an impact with its own sound and remains (frost crystals, scorch, water splash, sprouting vines). (M ★★★)
- Magical ambience: floating dust motes in sunbeams, glowing runes, sparks when a secret is near (subtle "warm" hint for curious players). (S ★★)

### 5.6 Post-processing and rendering

- Tonemapper (AgX or ACES), SSAO, SSIL, glow tuned for candles, subtle chromatic aberration and vignette off by default, depth of field in photo mode and dialogues. (S ★★)
- **Graphics settings menu** with presets (low/medium/high/ultra), render scale, FSR, shadows, GI, fog, VSync and FPS cap. Needed before anyone with a laptop plays. (M ★★★)
- LODs on generated props, HLOD per wing, occlusion already in place; a perf budget per area (e.g. 60 fps on a mid laptop at medium). (M ★★)

### 5.7 UI art direction

- A coherent look: parchment panels, ink-style headings, wax seals for house crests, a dedicated UI font with full Polish diacritics (already a `plan.md` item). (M ★★★)
- The journal as a real book with pages and tabs (timetable, spellbook, grades, map, inbox). (M ★★★)
- Spell icons for the hotbar, radial spell wheel for gamepad (already planned). (S–M ★★)
- Main menu with a live castle backdrop at dusk and a slow camera drift; loading screens with lore cards. (S–M ★★)

### 5.8 Audio (paired with visuals)

- Ambience per area, footsteps per surface, reverb zones, spell sounds per spell, a bell system, a small music set (day, night, feast, lesson, duel, mystery found). (M ★★★)
- The full sound and music list, with generation prompts, sources and a credit budget, is in `docs/audio-list.md`.

---

## 6. Professor and admin tooling

Professors are the scarcest resource; every minute a professor spends fighting the UI is a lesson that does not happen.

- **In-game lesson panel 2.0** (M ★★★): roster with raised hands, attendance, quick point buttons with reasons, board text, quiz launcher, practical task launcher, spell grant to "everyone who completed the task".
- **Lesson plan editor in game** (M ★★): write and reorder lines, quizzes and tasks; share a plan with other professors; mark a plan as approved for self-study.
- **Classroom controls** (S ★★): mute room chat except the professor, seat students, lock the door during exams, summon latecomers' attention (a bell).
- **Professor demonstrations** (S ★★): cast a spell with a larger, slower, highlighted effect for teaching.
- **In-game admin UI** (M ★★★): set roles and houses, reset mysteries, schedule events, edit timetable, broadcast to the castle, see who is online and where. Replaces `tools/set_role.sh` for day-to-day use (already in `plan.md`).
- **Event scheduler** (M ★★): feasts, exams, community mysteries, duelling hours as data with start times; server runs them.

---

## 7. Platform, safety and live operations

Required before opening to the public:

- **Moderation** (M, required): word filter (PL + EN), report player, mute/kick/ban for admins and professors, chat logs retained for a limited time, block list for DMs, age-appropriate defaults. Young players are the natural audience of this genre, so this is not optional.
- **Account and identity** (M): device auth today; add Steam auth when GodotSteam lands, account recovery, display-name rules.
- **Persistence of world state** across restarts (already in `plan.md`) and backups of Nakama storage.
- **Server-side position sanity** for area reports (already in `plan.md`) so lesson and house logic cannot be spoofed.
- **CI** running `tools/check.sh` and `tools/check_build.sh` on every push.
- **Analytics (privacy-respecting)**: which areas people visit, where they get lost, which mysteries stall, lesson attendance. Guides content work.
- **Steam**: store page, achievements tied to discoveries and ceremonies (not grind), rich presence ("In the Potions classroom"), PL + EN.
- **Accessibility**: rebindable keys, subtitles for all audio cues, colour-blind safe house colours (crests and patterns, not colour alone), text size, motion reduction (camera bob, fog), click-casting alternative to gestures.

---

## 8. Idea bank (unordered, for later picking)

School life
- First-day *welcome letter* in the journal written to your character by name.
- House-mate *buddy* system: a later-year student is assigned to each new first-year, both get a small reward when the first-year completes their first term.
- School newspaper written by players (club), pinned on boards and readable in the journal.
- Class photos: at the end of a lesson the professor triggers a group photo, saved to everyone's journal.
- Yearbook at the end of each school year.
- Lost property office: dropped items return here; a source of small quests.
- School choir or bell-ringing club that plays the castle bells.
- Professors' office hours: a scheduled slot where a professor sits in their office for questions.
- Graduation ceremony when a character finishes the final year, with a permanent title.

Magic
- Combination spells: two players cast together for a bigger effect (needed for some mysteries; the loft already uses "together").
- Spell research: late-year students combine known spells in a research lab to discover an unlisted variant (owner-authored, so it stays controlled).
- Wandless-style quiet charms for social use (colour your robes, conjure a small light, make flowers bloom) that are harmless and fun to show off.
- Personal magical focus chosen at an original ceremony (e.g. *attuning a focus crystal*) that changes your spell colours slightly.

Secrets
- Hidden house history: each house has a secret only its members can uncover, behind their common room.
- Puzzles that need one player from each house.
- Secrets that only open at a specific in-game time (midnight, full moon, during the winter feast).
- Easter-egg collectibles across the castle (the arcane fragments already exist; give them a story and a reward).
- Developer-run live mysteries: the owner changes something in the castle overnight and lets players notice.

Social and cosmetics
- Robe accessories earned, not bought: scarves from the house cup, a pin from each mystery, a badge for perfect attendance.
- Dorm decoration, common-room trophies with player names engraved.
- Sitting together at meals by house tables, with optional cross-house tables at feasts.

World
- Weather that matters a little: rain makes Emberkindle weaker outdoors, frost on the lake allows walking on it in winter.
- Creatures in the castle: cats, crows, enchanted suits of armour that shuffle at night, brooms that sweep by themselves.
- A clock tower with a working mechanism that is also a puzzle.

---

## 9. Recommended next steps (the next ~6 milestones)

1. **Lighting overhaul + GI spike** (5.1). Biggest visual jump, unblocks performance, and every later screenshot depends on it.
2. **School clock, day/night and bells** (Term A 1–2). Gives the castle a rhythm with almost no new art.
3. **Writing on the board + quizzes + raised hands + sitting** (Term B 1–2, Term A 4). Makes the live lessons that already work feel like real lessons; mostly code and UI, props exist.
4. **Player character v1 with house robes** (Term A 3). Replaces the capsule; ties identity to the house.
5. **Self-study lessons and the server timetable** (section 3, Term A 2). Solves "nothing happens when no professor is online". Needs the owner's decision on which spells can be self-studied.
6. **Offline prologue *The Night Before Term*** (section 3). Turns offline into an onboarding experience and a store-page demo, reusing the NPC lesson format from step 5.

In parallel, asset generation can target the **clutter kits per subject** (5.2) and the **window/stained-glass modules** (5.1), since both are needed by steps 1 and 3.

---

## 10. Decisions for the owner

- Can spells be learned in self-study lessons without a human professor, and which ones?
- Real-time timetable (fixed weekly hours) vs. an in-game clock that cycles faster than real time, or both (recommended: both; lessons on real time, atmosphere on game time).
- How many school years, and does a character advance by passing exams or by time served?
- Does offline progress ever carry over to online? (Recommended: no, except settings and cosmetics that cannot affect play.)
- Flying: the owner chose brooms (a generic folklore broom; no franchise broom models or names). Open: final name for the school broom model, and whether other mounts follow.
- Prefects: appointed by the admin, by professors, or elected by the house?
- Private servers for communities: in scope for launch or later?
- Final names for everything marked as a placeholder (subjects are named; the year system, the map, the Echoes, the flying sport, the village, the warden).
