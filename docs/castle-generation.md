# Castle and grounds generation plan

Goal: a castle and grounds on a **massive scale** that feel like the reference school in every corridor, generated from rules and data so the world can keep growing (new wings, new set pieces, new assets) without hand-placing thousands of modules. This document is the design and the milestone plan; `docs/plan.md` tracks the checkboxes (Milestones 24–32).

Legal reminder (see CLAUDE.md): we copy the **structure and the feel** of the reference school as closely as we can: the shape of its life, the kinds of rooms, the way the castle moves and hides things. We never copy its names, iconic named places, characters or artwork. Every name below is a placeholder marked *like this* until the owner picks the final one.

---

## 1. Principles

1. **Generated at build time, baked and committed.** A seed plus authored data produce `levels/castle/*.tscn`, terrain data and the server tables. Clients never generate anything at runtime; everyone loads the same committed files. `tools/check.sh` already regenerates and fails on a diff, and it keeps doing that.
2. **One canonical castle.** The owner reviews seeds, picks one, and it freezes. Later growth adds to it (new wings, the *Unfinished Wing*) without reshuffling what exists. Stable ids come from the program, never from generation order.
3. **Authored anchors, generated fill.** Anything with meaning (the entrance, the great hall, the grand staircase shaft, house towers, landmark positions) is **pinned** in data. The generator fills in everything between the anchors.
4. **Rules are code, not good intentions.** Every rule in section 3 is a validator that refuses to write the scene, the same way the overlap and reachability checks work today. A rule that can't be checked automatically doesn't count as a rule.
5. **Assets are swappable by role.** The generator places *roles* (wall, window, floor tile, roof tile, railing, stair, tree, rock…), and a kit table maps each role to a wrapper scene, with variants per area kind or house. A new asset drop is a data change; the generator is untouched.
6. **The server sees the same world.** Areas, world objects, moving-piece schedules and secret chains export to `nakama/modules/generated/*.lua`, as `world_areas.lua` and `world_objects.lua` do today.

---

## 2. Pipeline

```
content/castle/program.json   what must exist (rooms, kinds, houses, sizes, adjacency wishes, pins)
content/castle/setpieces.json authored set pieces (shifting stair shaft, jump routes, trick steps…)
content/castle/kit.json        role → wrapper scene (+ variants by kind / house / storey)
content/grounds/grounds.json   landmarks, pinned approach, biome wishes, boundary
content/placements.json        gameplay objects, positioned by slot (not raw offsets)
        │
        ▼  tools/castle/  (Python, seeded, deterministic)
 1 graph      program → room graph (hub, wings, towers, dungeons) under adjacency rules
 2 layout     graph → rectangles on the 4 m grid, storey by storey, pins respected
 3 circulate  corridors, doors, stairs (straight / switchback / spiral), shifting stairs, railings
 4 secrets    hidden rooms in voids, passages as shortcuts, lock-and-key chains
 5 validate   every rule in section 3; refuse to write on failure
 6 preview    SVG per storey + grounds overview (seconds per seed, no Godot)
 7 build      the existing builder: walls, floors, windows, doors, torches, zones, furniture
 8 exterior   roofs, spires, battlements, buttresses, bridges, far-view shell
 9 export     sector scenes, world_areas.lua, world_objects.lua, setpieces.lua
        │
        ▼  tools/grounds/ (Godot headless, like tools/export_server_content.tscn)
 heightmap → shaping masks (castle plateau, lake, cliffs, ridge) → paths (A* on slope cost)
 → biome masks → scatter (Poisson disc) → terrain regions + MultiMesh chunks + outdoor AreaZones
```

`generate_castle.py` becomes stage 7. Its hand-written plan moves into `program.json` with every room pinned, so step one changes nothing visible. The layout generator then takes over room by room as pins are removed.

---

### Grounds pipeline (as built in Milestone 26)

`tools/grounds/` runs inside the castle generator (one command builds both): `terrain.py` layers the heightmap (hills that grow with distance from the castle's summit, the lake basin, the island, the plateau under every castle room, cliffs, hills, valleys with rivers, mountains at the border, flats under landmarks, terraces), `paths.py` routes roads with A* between pinned waypoints and carves them at 9 degrees at most (rule G2 allows 10), bridges keep their span, `scatter.py` places trees, bushes and rocks from forest masks with the G4 clearances, `zones.py` turns grounds zones and landmark zones into terrain rooms of kind `grounds` (no geometry, but an `AreaZone`, a line in the server's area map and a place in the reachability graph, linked to the estate), `rules.py` checks G1-G6 and `export.py` writes `levels/grounds/` (`terrain.json`, `height.bin`, `holes.bin`, `splat.png`, `scatter.bin`, `grounds.tscn` with greybox landmarks and bridges). The terrain has holes wherever a castle room has its own floor at or below the ground floor, and wherever it would dip into an underground room. Outdoor objects sit on render layer 11, the only layer the moon lights; a node on the terrain carries players out of deep water back to the last dry ground and lowers their kill height below the lake floor.

## 3. Rules

Each rule has an id. The validator reports violations by id and room, and each rule has a test. A rule can be **waived** for one place only by a `waivers` entry in the program naming the rule, the place, the milestone that lifts it and why; the generator tests list them, so they cannot pile up silently.

### 3.1 Anchors (never move)

- **A1 Fixed entrance.** The main gate stays at world (0, 0, 48), facing south, double doorway, with the entrance hall behind it at (−12…12, 24…48), two storeys tall. `StartPoint` stays on the approach in front of the gate. Every seed and every growth step keeps these coordinates. They're the world origin of the castle, and tests, spawn and server data depend on them.
- **A2 Fixed approach.** The ceremonial approach (*arrival causeway*) runs straight south from the gate, at least 12 m wide, rising at most 8° to the gate plateau, and nothing (trees, rocks, buildings) may stand on it. The secondary arrival (*first-year crossing*: a landing stage on the lake, then a path up the cliff to a lower gate) is pinned too.
- **A3 Hub order.** The entrance hall connects directly to the great hall, the grand staircase shaft and the courtyard. Those four are pinned and form the hub. Every other wing attaches to the hub.
- **A4 House territories.** Each house's common room and dormitories are pinned to a quarter of the castle: two in towers (high), one in the dungeons (low, by the lake), one by the kitchens (warm, low). A house's territory is reachable only through its own gate (rule C6).
- **A5 Landmarks.** Grounds landmarks have pinned positions in `grounds.json`: lake, boathouse, greenhouses, beast paddock, groundskeeper's cottage, sport pitch, stone circle, forest edge, clock courtyard, the bridge. Paths are generated between them; the landmarks themselves never move.

### 3.2 Stairs

The current stairs break rule S1: tower flights start 0.2 m from the south wall, and the grand staircase's first flight starts at the hall's south wall.

- **S1 Approach landing.** Before the bottom step there must be a clear rectangle the width of the flight and at least **4 m long** (one module), in the same room, on a floor or landing. No wall, door-leaf swing, pillar or other flight may be in it (a flight passing overhead with full headroom is fine). A flight never starts against a wall.
- **S2 Arrival landing.** After the top step there must be a clear rectangle at least 4 m long before any wall, rail or doorway. The player keeps walking straight off the flight without walking into something.
- **S3 Headroom.** Clearance of at least 2.6 m above every tread, measured against ceilings, ceiling holes, flights above and landings.
- **S4 Tread comfort.** Riser at most 0.36 m (PlayerMovement step height 0.42) and tread at least 0.45 m. With the 9 m storey, a straight flight runs about 11.5–14 m. A flight that doesn't fit with S1+S2 must become a **switchback** (two half flights and a mid landing) or a **spiral** (towers). The generator chooses; it never shortens the landings.
- **S5 Towers get spirals.** Any room smaller than 20 × 20 m that needs a stair gets a spiral staircase (new `SpiralStaircase` @tool module) around a central column, or a newel stair in a corner turret. 16 m tower rooms can't hold a straight flight that also has two landings.
- **S6 Wall the flight hugs.** No doorway or secret wall on the wall section behind a flight where its underside comes down into the opening (3.5 m). Torches and windows are kept off a flight's wall by the builder; landings may have doors beside them.
- **S7 Fall protection.** Every walkable edge with a drop over 1.2 m gets a railing or parapet. The only exceptions are volumes tagged `jump_route` or `drop_ok` (set pieces, section 4). Open sides of flights get balustrades.
- **S8 Where stairs may be.** Flights only in stair halls, corridors, towers, halls and house landings. Never in classrooms, the library reading floor, the great hall floor or dormitories.
- **S9 Two ways up.** Every public storey is reachable from the entrance by at least **two independent stair routes**, so one closed or shifting stair never cuts off part of the school.

### 3.3 Circulation and rooms

- **C1 Reachable.** Every room is reachable from the gate (as today). Every *public* room is reachable **without** secrets, house gates, locked doors or jump routes.
- **C2 Walking budget.** From the great hall, any classroom is at most 180 m of walking (path length through doors and stairs, not straight-line distance), and any common room is at most 220 m. This keeps lesson changes and meals practical on a massive map. The preview prints the worst offenders.
- **C3 Corridor widths.** Main corridors are 8 m (two modules). Service corridors and passages are 4 m. Galleries and cloisters are 8–12 m. A dead-end longer than 3 modules must end in something: a window seat, a statue, a secret, a stair.
- **C4 Room proportions.** Aspect ratio at most 3:1 except corridors, halls, galleries and shafts. Minimum sizes per kind: classroom 16 × 16, common room 16 × 16, dormitory 16 × 16, library 24 × 40, great hall 32 × 40 (the pinned hub keeps today's great hall).
- **C5 Classroom layout.** The door is in the back or side wall, never the front (teaching) wall, so students enter behind the desks. The front wall has no window over the boards. At least 12 desk seats for the wing rooms.
- **C6 House gates.** Every doorway between a house room and a non-house room is a house gate. Each house territory has exactly one gate from public space (plus secret exits, if the owner wants them).
- **C7 Doors.** A doorway with leaves stays at least one module from a room corner (walls of 12 m or more). Door swing clear of furniture and stair landings (S1/S2). No two doorways on the same wall closer than 4 m (except double doors).
- **C8 Windows.** Only on walls facing the outside or an open-air area. None in dungeons or secret rooms (a secret room with a window would show from outside). Hidden-room voids get blind wall on the exterior shell.
- **C9 Structure.** A room on storey s > 0 stands over rooms below. A room marked `support: corbel` may instead hang off a neighbour on the same storey, reaching out at most 8 m (exterior corbels are drawn in Milestone 27). Tall rooms (bands > 1) block the storeys they span. Towers rise continuously from the ground.
- **C11 Doorways land somewhere.** Every doorway opens, on both sides, onto a floor, landing or stair turn at its storey (reachability is computed per level: a tall room with landings is several walkable levels joined only by its flights).
- **C10 Naming and ids.** Area ids come from the program. Generated rooms (corridor segments, passages, voids) get ids from their wing and index along it, so regenerating one wing never renames another.

### 3.4 Moving pieces

- **M1 Reachable in every state.** The reachability (C1) and two-routes (S9) checks run for **every** state combination of shifting stairs, rotating rooms and doors on schedules.
- **M2 Worst-case detour.** In the worst state, the walking path from the great hall to any classroom is at most 2× the best-state path.
- **M3 Clean ends.** In every state, both ends of a shifting stair sit exactly on a landing edge (within 2 cm height, 5 cm plan), or on a closed rail.
- **M4 Clear sweep.** The volume a moving piece sweeps between states is empty of static geometry. Players in the sweep are pushed (AnimatableBody), never crushed into walls.
- **M5 Rails close.** A landing's rail gate closes while its stair is away, so nobody walks off into the shaft by accident.
- **M6 Server time.** Moving pieces follow a schedule computed from **server time**, the same on every client. They never simulate independently per client.

### 3.5 Grounds

- **G1 Plateau.** Terrain inside the castle footprint plus a 6 m margin is flattened under the plinth. Terrain never pokes through a floor, and no gap opens between the plinth and the ground.
- **G2 Slopes.** Paths at most 10°. Walkable ground at most 35°. Steeper ground is cliff: rock material, collision, no scatter, and it can't be climbed.
- **G3 Landmarks connected.** Every landmark is reachable from the gate along a path. Paths avoid water, cliffs and the sport pitch.
- **G4 Scatter clearance.** No tree within 4 m of a path, 8 m of a building or 15 m of a castle window wall. No rock on paths. Lake shores keep a 3 m clear rim.
- **G5 Soft boundary.** The walkable world is bounded by deep water, cliffs, a dense forest band and backdrop mountains. Invisible walls only as a last resort, behind those. A kill-and-respawn volume below the lowest cliff.
- **G6 Outdoor zones.** Grounds are split into AreaZones (lake shore, forest edge, pitch, paddock, greenhouses, stone circle…) so proximity chat, curfew and flying rules work outdoors.

### 3.6 Budgets and content

- **B1 Per-sector budgets.** Per sector, module instances, omni lights, shadowed lights and triangles each have a cap (numbers set in Milestone 28 from profiling). The generator reports per-sector totals, and any sector over its cap is an error.
- **B2 Lights.** At most 8 lights affecting any one room. Shadowed lights only where needed (flames are already shadowless).
- **B3 No franchise names.** Every generated id, name key and translation is checked against a **hashed** denylist (SHA-256 of normalised words, kept in `tools/castle/denylist.sha256`) so the forbidden words never appear in the repo in plain text.

---

## 4. Set pieces: making it feel like the reference school

These are authored in `setpieces.json`, placed by the generator into slots the layout reserves for them, and validated by the M rules. Together they deliver the feel; the rest of the castle is the stage they sit on.

### 4.1 The shifting staircase shaft (*Hall of Turning Stairs*)
- A square shaft at least 40 × 40 m that rises the full height of the castle (dungeon level to storey 6, ~65 m), lined with landings on every storey. The walls are covered in portraits (the slots later host talking portraits, roadmap Term D).
- **Shifting flights**: straight flights hinged at one end. Each has 2–3 target landings and swings between them on a server-time schedule (about every 90 s, staggered), with a grinding sound and dust.
- Some flights only shift when someone steps on them (`trigger: ride`). One flight changes on the school clock (day/night), so some routes exist only at night.
- **Trick step**: one tread in some flights gives way. The player sinks to the knee and is held for 2 s unless they jump. Purely comic, never lethal.
- Gameplay: the fastest route between storeys, and an unreliable one; the fixed stair halls (S9) are the slow, safe alternative.

### 4.2 Jump routes (*Clockwork Loft*, *Floating Stair of the Library*, *Broken Bridge*)
- A clock tower interior: rotating gear platforms, swinging pendulum platforms and pistons that rise and fall, climbing to the clock face (a secret and a view).
- In the library's tall reading hall, floating book-stack stones circle slowly and lead to the restricted upper gallery.
- A partly collapsed covered bridge to an outer tower: floating slabs drift between the broken ends and settle into a full bridge only when someone casts Uplift on the keystone.
- All are `jump_route` volumes (S7 exception), with a respawn point at the bottom and a fall that is never lethal (soft landing area). They're never on a required route (C1).

### 4.3 Living castle details
- **Rotating corridor** (*Turnabout Passage*): a corridor segment that rotates 90° on a schedule and connects different doors.
- **Doors that aren't doors**: painted doors, doors that open only when asked politely (interact twice), doors that move one module along the wall at night.
- **Portrait and statue gates**: each house gate gets its own original mechanism (a riddling knocker, a statue that needs a gesture, a painting that needs the house phrase). Server-checked like `HouseDoor`.
- **Moving suits of armour and statues** along gallery walls (schedule-driven, cosmetic, M4 sweeps).
- **Vanishing corridor** (*Seldom Room*, placeholder): a wall that becomes a door only when a player walks past it three times. A room that changes its contents for the group inside (authored variants).
- **Secret passages behind tapestries and mirrors**, generated (section 2, stage 4) as shortcuts between rooms that are far apart in the graph but close in space.

### 4.4 Grounds set pieces
- A great lake with an island, a boathouse and the first-year crossing (A2). A covered wooden bridge over a ravine to the outer grounds. A stone viaduct carrying the arrival causeway. A sport pitch with tall ring goals and stands in house colours. Greenhouses in glass. A groundskeeper's cottage with a vegetable patch at the forest edge. A forbidding forest (night-gated, roadmap Term D). A stone circle. A clock courtyard. The roost tower. A hostile animated tree guarding a tunnel into the castle (a secret entrance). The backdrop: mountains, cliffs below the castle, distant waterfalls.

### 4.5 Multiplayer mechanics
- New client `ServerClock` (NetworkManager): the match includes its tick time in the join snapshot and in periodic pings. The client keeps a smoothed offset using half the round-trip time. Offline it uses the local clock.
- `ScheduledMover` component (builds on `MovingPlatform`): its pose is a pure function of `(schedule, server_time)`, so late joiners and every client agree without any per-tick sync. Triggered moves (`ride`, `spell`) go through `OP_WORLD_EVENT`, and the server answers with a start time.
- Riders are carried by `sync_to_physics` like on today's moving platform. Remote players stay interpolated from their own synced transforms, so nothing changes in `NetworkSynchronizer`.

---

## 5. Scale and performance

Target (owner to confirm, section 7):
- **Castle**: about 320 × 260 m footprint, dungeon level plus 6 storeys, towers to storey 10 (~90 m), 250–350 named areas (today: ~128 × 160 m, 54 areas, ~6,000 module instances).
- **Grounds**: about 2 × 2 km walkable, plus backdrop terrain out to 8 km rendered as low-detail meshes.

What that needs:
- **Sectors.** The castle is split into sector scenes (a wing, a tower, the hub, the dungeons), each a separate generated `.tscn`. A `SectorStreamer` keeps the player's sector plus everything within N doorways (the room graph *is* the portal graph) and the exterior shell loaded, and loads and unloads others in the background. Today's single 6,000-instance scene would become ~40,000 instances in one file, which is not workable.
- **Batching.** Repeated modules (wall faces, floor tiles, pillars, roof tiles) are drawn as one `MultiMeshInstance3D` per module type per sector instead of one node each. Collision is merged into per-sector static bodies. The occluders on wall runs and floors stay.
- **Far view (HLOD).** A merged low-detail mesh of the whole exterior with lit-window emissive cards, shown beyond about 150 m. The detailed exterior of a sector is shown near it.
- **Terrain (decided in Milestone 26: our own, no GDExtension).** `gameplay/world/terrain.gd` builds 64 m chunks from the generated heightmap: a coarse mesh for every chunk, full resolution within 240 m of the player, skirts against cracks, collision (`HeightMapShape3D`, triangle collision where the castle cuts holes) and tree trunks only within 120 m of a local player. Flora is one MultiMesh per kind per 128 m cell with visibility ranges. The Python generator samples the same heights, which Terrain3D would not have given us.
- **Lights.** About 350 omni lights today, roughly 2,000 at target scale. They're loaded per sector and capped per room (B2). Baked or SDFGI lighting is decided in the lighting overhaul (roadmap 5.1).

---

## 6. Milestones

Each milestone ships green (`tools/check.sh`), is pushed, and leaves the game playable. The owner playtests between them.

### Milestone 24 — Generator foundation (no visible change)
- Split `tools/generate_castle.py` into `tools/castle/` (program loader, rules, layout, builder, preview, export). The current plan moves into `content/castle/program.json` with every room pinned. The output scene is identical node for node (diff check).
- Rules engine with ids; port the existing overlap and reachability checks to it.
- `content/castle/kit.json` (role → scene), and the builder reads every scene path from it.
- `tools/castle/preview.py`: SVG per storey (rooms coloured by kind and house, doors, stairs with landings, secrets, zones).
- Placements by **slot** (`wall`, `corner`, `beside_lectern` already exist; add `centre`, `door_side`, `window_bay`, `stair_foot`), and raw `at` offsets are validated against the room's size.
- Hashed denylist check (B3).
- **Done when:** the castle scene regenerates byte-identical and the preview renders all storeys.

### Milestone 25 — Stairs and circulation rules (fixes the castle as it is)
- Rules S1–S9, C1–C10 and A1/A3 implemented, and the current castle **fixed** to pass them:
  - Grand staircase: the first flight starts 4 m clear of the south wall (run 11.5 m, tread 0.46 m) with the landings re-cut.
  - Towers: the new `SpiralStaircase` module replaces the straight flights.
  - Doors and windows are moved off walls behind flights.
  - Balustrades on open flight sides, railings on every unprotected edge (S7).
- Test: for every flight, a capsule walks from the approach landing to the arrival landing without touching a wall, in both directions.
- **Done when:** the validator passes on the real castle and a player can walk every stair without bumping into anything.

### Milestone 26 — Grounds v1
- `tools/grounds/` headless generator: heightmap from layered noise, shaping masks (castle plateau G1, lake basin, ravine, cliffs below the castle, ridge), A* paths between pinned landmarks (A5, G2, G3), biome masks, scatter (G4), soft boundary (G5), outdoor AreaZones (G6).
- Terrain3D integrated (or the fallback), lake water surface, and placeholder buildings at the landmark slots (greybox until assets arrive).
- The arrival causeway and the first-year crossing (A2).
- **Done when:** a player can walk from the lake landing stage up to the gate and to every landmark with no invisible walls, and grounds tests (slopes, clearance, reachability) pass.

### Milestone 27 — Exterior shell
- Roof generation from the room plan: pitched roofs per wing, conical or spired caps on towers, battlements on open roofs, buttresses on tall halls, chimneys over hearth rooms, corbelled turrets, flying bridges between towers.
- Plinth and foundations meeting the terrain (G1), cliff-face retaining walls.
- Far-view HLOD mesh with lit windows.
- **Done when:** the castle silhouette reads from the lake shore, and there's no see-through gap anywhere from outside.

### Milestone 28 — Scale infrastructure
- Sector split, `SectorStreamer`, MultiMesh batching, merged collision, per-sector budgets (B1) measured and set.
- Stress fixture: the current castle duplicated into a 5× grid, which must hold the frame-time target on the owner's machine.
- **Done when:** the stress fixture plays at target frame time and sectors stream without hitches.

### Milestone 29 — Layout generator and the big castle
- Program → graph → embedding with pins (A1–A4) for the new wings. The program grows to the full curriculum (a classroom per subject, plus duelling hall, trophy room, staff offices, infirmary, kitchens, a bathing hall, clock tower, roost, observatory, music room, *Unfinished Wing* shell).
- C2 walking budget and C9 structure enforced. The owner picks a seed from previews.
- Every existing area id is kept (the old castle becomes the pinned hub). Server data and placements migrate through the area-id map.
- **Done when:** the target-scale castle passes every rule, existing mysteries and lessons still work, and the multiplayer tests are green.

### Milestone 30 — The living castle (set pieces)
- `ServerClock`, `ScheduledMover`, server schedule export (`generated/setpieces.lua`).
- The Hall of Turning Stairs (4.1) with shifting flights, rail gates and trick steps. Rules M1–M6.
- One jump route (clock tower, 4.2) and the rotating corridor (4.3).
- Two-client test: both clients see the same stair in the same state at the same server time, and a late joiner matches.
- **Done when:** the owner can ride a shifting stair with a second player and both arrive at the same landing.

### Milestone 31 — Secrets generator
- Hidden rooms in layout voids, passages behind tapestries and mirrors as shortcuts, generated lock-and-key chains written as `mysteries.lua` content (stub text keys for the owner to fill).
- Rules: no secret on a required route, every chain solvable with lesson-granted spells, no windows on hidden rooms (C8).
- **Done when:** 20+ secrets are generated and validated, and three hand-polished chains ship with text.

### Milestone 32 — Dressing pass
- Per-kind furnishing rules (dormitory beds and trunks, common-room hearths and armchairs, library stacks, great hall house tables and a high table, kitchens, greenhouse benches, trophy cabinets), house banners and colours per territory, portrait and tapestry slots, clutter kits per subject (roadmap 5.2).
- The kit table makes every placeholder swappable as assets arrive (asset-drop workflow).
- **Done when:** no room in the castle is empty, and swapping one kit entry restyles every instance.

Order: 24 → 25 is the immediate fix. 26 and 27 can run in parallel with 28. 29 needs 25 and 28. 30 and 31 need 29's layout (30 can prototype in the current stair hall earlier). 32 follows the assets.

---

## 7. Decisions for the owner

- **Scale.** Confirm the target (~320 × 260 m castle, 250–350 areas, 2 × 2 km grounds) or set another.
- **Canonical vs. regenerated.** One frozen castle that grows (recommended), or a new layout per school year.
- **Arrival.** Keep both arrivals (causeway plus the first-year lake crossing)?
- **Shifting stairs.** Schedule period, and whether some flights only move at night.
- **Final names** for every *placeholder* in this document.
