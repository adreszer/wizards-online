# Wizards Online — project instructions

Read this first in every session. It defines where the game is going, so every change should move toward this target state, not just the current MVP.

## Target state (the game we are building)

A multiplayer **open-world magical school**: one large castle (plus grounds) that players explore freely together, live in, attend lessons in, and grow as wizards in. It is a social school simulation first, an action game second.

**Design model vs. legal stance.** Internally we model the game on the Harry Potter franchise and Hogwarts: its school structure, houses, subjects, lessons, house points, secrets and atmosphere are the reference for how things should feel. Legally, the game must **not be based on that IP**: no Harry Potter names, characters, spells, places, house names, terms or artwork anywhere in the code, assets, text, scene names, translation keys or docs. Use the franchise as an unstated mental model only; every shipped element gets an original name and description. When this file mentions Hogwarts-style features it is to explain the intent, never to copy.

### 1. The castle
- One continuous, explorable castle world: great hall, towers, dungeons, corridors, staircases, library, grounds. No linear level flow; players roam.
- **Many hidden rooms, secret passages and mysteries.** Secrets are a core pillar: hidden doors, puzzles that unlock areas, clues spread across the castle, things that reward curiosity and cooperation.
- **Four houses**, named by the owner: **Drakoryn** (dragon, house 1), **Grypheon** (griffin, house 2), **Phoenara** (phoenix, house 3), **Hipporys** (hippocampus / winged horse, house 4). Never rename them; other final names (subjects, places…) still come from the owner. Each house has its own **common room** and dormitory area, accessible to members of that house.
- **A classroom for every school subject.** The curriculum mirrors the reference school's breadth (charms-style spellwork, transfiguration-style shape magic, potions, defensive magic, magical plants, astronomy, history of magic, flying, magical creatures, divination, magical mathematics, ancient runes…) but each subject gets its own original name. Each classroom is a real, distinct place in the castle.

### 2. Roles: students and professors
- Players are **students** by default.
- The owner/admin can **mark specific players as professors**. Professors run **real live lessons**: a professor stands in their classroom and teaches actual players present there.
- Lessons are **text based, not voice**. Teaching happens through in-game text (lecture text, instructions, questions to students, etc.) plus in-world demonstrations.
- Professors need tools students don't have: lesson controls, granting spells, awarding/deducting house points, classroom management.

### 3. Spells and learning
- A character **learns spells during lessons** (granted by the professor as part of the lesson), not by picking up items in the world. Spell knowledge persists on the character.
- Learned spells can then be **used freely around the school** where appropriate: on objects, puzzles, secrets, environment interactions.
- Spells must **not** be usable as free-for-all attacks on other players outside sanctioned settings.

### 4. Duels (later)
- Duels between players will exist, but **only in a specific, controlled setting** (e.g. a duelling club / arena run by a professor, or explicit consent flow). No firing at arbitrary players in corridors.
- Design systems (spell targeting, damage, PvP flags) so that duelling can be gated by location and rules later.

### 5. Houses, points and school life
- **House points**: professors award and deduct; a running per-house tally with a visible leaderboard/hourglass equivalent. House cup style competition.
- Other school-life systems will follow the same pattern: anything that exists at the reference school is a candidate (timetables, sorting, prefects, feasts, detentions, etc.). Prefer designs that keep these data-driven and server-authoritative.

### 6. Chat and communication
- **Public proximity chat**: players can text publicly and only nearby players see it (spatial/proximity based), so a classroom or common room conversation stays local.
- **Direct messages (DMs)** between players.
- Lesson teaching text flows through the same text system (professor speaking to the room).

## What this means when working on the code

- **Persistence matters.** Character identity, house membership, learned spells, roles (student/professor/admin) and house points must live on the server (Nakama), not in the client session.
- **Server authority.** Roles, spell grants, house points, duel rules and chat routing are decided server-side; the client only requests.
- **Build for an open world**, not chained rooms: the castle is one world with named areas, doors and zones; systems (chat proximity, house access, classroom context) key off those areas.
- **Keep secrets in mind**: level tooling and object composition should make hidden rooms and multi-step mysteries cheap to author.
- **Original content, always.** Structure and feel follow the reference, but every name, spell, subject, house, place, item and line of text is original. If a proposed name is recognisably from the franchise, rename it. Placeholders stay until the owner provides final names.
- Localization: Polish primary, English secondary, all text through `localization/translations.csv` (see docs/development.md).

## Where things are

- `docs/plan.md` — implementation tracker (keep it current).
- `docs/architecture.md` — code structure; `docs/development.md` — how to run and test.
- `README.md` — quick start.

## Workflow

- Commit and push after each meaningful stage (`git push origin <branch>:main`, fast-forward only).
- Verify headlessly with the test scenes under `tests/` before pushing; the owner playtests builds between pushes.
- Never add AI attribution trailers to commits.
