"""Dressing pass (Milestone 32, set dressing 2.0): furnishes every room by its kind, name
and house, densely enough that the castle looks lived in: carpet runners down every
corridor and hall rugs, benches, clocks, urns and plants between the portraits, a
sitting set (rug, table, chairs and what lies on the table) in ordinary rooms, house
hearths, cushions, coat racks and bookshelves in the common rooms.

Runs inside build.build() after the classroom furniture: it uses the builder's wall
spans (wall_free_intervals: clear of doorways, windows, pillars and torches) and its
keep-outs (stairs, landings). Props come from the kit's "props" roles, so a real model
replaces a placeholder everywhere at once. Rule D1 (budgets.py): no room left empty.
"""
import math

from . import build as B
from .geometry import T

SUBJECT_KITS = {
    "elixirs": ["cauldron", "cauldron", "cabinet", "barrel", "jar_shelf"], "herblore": ["plant_pot", "plant_pot", "workbench", "jar_shelf"],
    "stargazing": ["telescope", "globe", "telescope"], "farsight": ["crystal_table", "crystal_table", "candelabra"],
    "beastlore": ["cage", "crate", "cage", "log_basket"], "shapeshaping": ["pedestal", "pedestal", "cabinet", "urn"],
    "chronicles": ["bookshelf", "globe", "bookshelf", "lectern_book"], "glyphs": ["rune_stone", "rune_stone", "bookshelf", "lectern_book"],
    "numeromancy": ["abacus", "abacus", "bookshelf", "clock"], "warding": ["dummy", "dummy", "dummy", "bench"],
    "sigilcraft": ["candelabra", "pedestal", "cabinet"], "skyriding": ["staff_rack", "staff_rack", "crate"],
}
NAME_THEMES = [
    (("office", "gabinet", "records", "kancelaria", "mail"), ["cabinet", "table", "chair", "bookshelf"]),
    (("store", "cellar", "cold", "wine", "supply", "linen", "ink", "box room", "skład", "magazyn", "piwnic"), ["barrel", "crate", "crate", "barrel"]),
    (("study", "reading", "seminar", "scriptorium", "copying", "quiet", "tutoring", "archive", "catalogue", "scroll", "map"),
     ["table", "chair", "bookshelf", "candelabra"]),
    (("trophy",), ["cabinet", "cabinet", "cabinet", "statue"]),
    (("gallery", "portrait"), ["portrait", "portrait", "portrait", "statue"]),
    (("bathing", "łaźnia"), ["plant_pot", "statue", "plant_pot"]),
    (("hospital", "infirmary"), ["bed", "bed", "bed", "cabinet"]),
    (("guest", "robing", "waiting", "lounge", "lost"), ["armchair", "coat_rack", "wardrobe", "side_table"]),
    (("music", "choir"), ["harp", "bench", "side_table", "bookshelf"]),
    (("globe",), ["globe", "globe", "telescope", "bookshelf"]),
    (("cell",), ["chest", "barrel"]),
]


# A kit role may list several scenes (portraits): instances take them in turn.
_turn = {}


def prop(kind):
    path = B.KIT.get("props", {}).get(kind)
    if isinstance(path, list):
        _turn[kind] = _turn.get(kind, -1) + 1
        return path[_turn[kind] % len(path)]
    return path or f"res://objects/environment/placeholders/{kind}.tscn"


def on_wall(r, side, along, kind, name="Dress", inset=0.0):
    if side in "we":
        pos = ((r.x0 + T / 2 + inset) if side == "w" else (r.x1 - T / 2 - inset), r.y, along)
    else:
        pos = (along, r.y, (r.z0 + T / 2 + inset) if side == "n" else (r.z1 - T / 2 - inset))
    yaw = {"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[side]
    B.inst(B.uname(f"{name}_{r.id}"), prop(kind) if kind != "bookshelf" else B.K("bookshelf"), pos, parent="Furniture",
           rot_y=math.radians(yaw))


def wall_slots(r, width=1.8, skip=()):
    """Free spots along the room's walls (side, coordinate along it), spread out."""
    out = []
    for side in "nsew":
        if side in skip or side in r.no_torch_sides:
            continue
        _axis, _coord, free = B.wall_free_intervals(r, side, width)
        for a, b in free:
            n = max(1, int((b - a) // (width + 2.0)))
            for i in range(n):
                out.append((side, a + (b - a) * (i + 0.5) / n))
    return out


def floor_clear(r, x, z, margin=1.6):
    if not (r.x0 + 2 < x < r.x1 - 2 and r.z0 + 2 < z < r.z1 - 2):
        return False
    return not B.kept_out(x, z, r.y, margin)


def at_floor(r, x, z, kind, yaw=0.0, name="Dress"):
    B.inst(B.uname(f"{name}_{r.id}"), prop(kind), (x, r.y, z), parent="Furniture", rot_y=math.radians(yaw))


# Corridor runners by wing (the rest are crimson); hall rugs and common rooms by house.
RUNNER_BY_WING = (("north_wing", "blue"), ("archive", "blue"), ("east_wing", "green"), ("dungeon", "green"),
                  ("lake", "green"), ("unfinished", "green"))
RUG_BY_HOUSE = {1: "green", 2: "crimson", 3: "crimson", 4: "blue"}
RUNNER_STEP = 3.6
# What stands or hangs along a corridor's walls, in turn.
CORRIDOR_WALL = ["portrait", "bench", "urn", "armour", "clock", "plant_pot", "portrait", "side_table", "bench", "tapestry"]
# Height of a table top (the table and its wrapper), for what lies on it.
TABLE_TOP = 0.81


def runner_colour(r):
    return next((c for key, c in RUNNER_BY_WING if key in r.id), "crimson")


def lay_runner(r, colour):
    """A carpet runner down the middle of a long room, in 3.6 m lengths, broken where
    a stair or landing crosses the floor."""
    cx, cz = r.centre()
    along_x = r.width >= r.depth
    length = (r.width if along_x else r.depth) - 2.0
    n = int(length // RUNNER_STEP)
    start = -(n * RUNNER_STEP) / 2 + RUNNER_STEP / 2
    for i in range(n):
        x, z = (cx + start + i * RUNNER_STEP, cz) if along_x else (cx, cz + start + i * RUNNER_STEP)
        if not B.kept_out(x, z, r.y, 0.4):
            at_floor(r, x, z, f"runner_{colour}", 90.0 if along_x else 0.0, "Runner")


# What fills the rest of an ordinary room's walls once its own kit is placed, in turn.
FILLER = ["bookshelf", "side_table", "cabinet", "clock", "urn", "plant_pot", "jar_shelf", "coat_rack", "bookshelf", "candelabra"]
RUG = (4.0, 6.0)   # the hall rug's size at scale 1


def rug_fits(r, x, z, half_w, half_d):
    """The rug's centre and corners lie on the room's floor, clear of stairs."""
    for dx, dz in ((0, 0), (-half_w, -half_d), (half_w, -half_d), (-half_w, half_d), (half_w, half_d)):
        px, pz = x + dx, z + dz
        if not (r.x0 + 1.0 < px < r.x1 - 1.0 and r.z0 + 1.0 < pz < r.z1 - 1.0) or B.kept_out(px, pz, r.y, 0.3):
            return False
    return True


def hall_rug(r, colour, x=None, z=None, margin=3.6, span=None):
    """A large rug in the middle of the floor, sized to the room (a third of its shorter
    side, at least the 4 x 6 m rug, at most twice it), when it fits clear of stairs.
    `span` caps the room size it is fitted to (a rug under one sitting set)."""
    cx, cz = r.centre()
    x = cx if x is None else x
    z = cz if z is None else z
    short = min(r.width, r.depth) if span is None else min(span, r.width, r.depth)
    if short < 8:
        return False
    scale = max(1.0, min(2.0, short / 3.0 / RUG[0]))
    along_x = r.width > r.depth
    half_w = (RUG[1] if along_x else RUG[0]) * scale / 2
    half_d = (RUG[0] if along_x else RUG[1]) * scale / 2
    while not rug_fits(r, x, z, half_w, half_d):
        if scale <= 1.0:
            return False
        scale = max(1.0, scale - 0.25)
        half_w = (RUG[1] if along_x else RUG[0]) * scale / 2
        half_d = (RUG[0] if along_x else RUG[1]) * scale / 2
    B.inst(B.uname(f"HallRug_{r.id}"), prop(f"hall_rug_{colour}"), (x, r.y, z), parent="Furniture",
           rot_y=math.radians(90.0 if along_x else 0.0), scale=scale)
    return True


def on_table(r, x, z, kind, yaw=0.0):
    B.inst(B.uname(f"Clutter_{r.id}"), prop(kind), (x, r.y + TABLE_TOP, z), parent="Furniture", rot_y=math.radians(yaw))


def sitting_set(r, x, z, clutter="writing_set", chairs=2):
    """A table with chairs round it and something lying on it (the table's wrapper stands
    on its back edge, so it is set 0.5 m back to centre it on (x, z))."""
    if not floor_clear(r, x, z, 2.0):
        return False
    at_floor(r, x, z - 0.5, "table", 0.0, "SetTable")
    for i in range(chairs):
        side = -1 if i % 2 == 0 else 1
        at_floor(r, x + side * 0.5, z + side * 1.15, "chair", 0.0 if side < 0 else 180.0, "SetChair")
    on_table(r, x + 0.35, z, clutter, 20.0)
    return True


def corner_pieces(r, kinds, inset=1.6):
    """Free-standing pieces in the room's corners (plants, urns, candelabra)."""
    corners = [(r.x0 + inset, r.z0 + inset), (r.x1 - inset, r.z0 + inset), (r.x0 + inset, r.z1 - inset), (r.x1 - inset, r.z1 - inset)]
    for (x, z), kind in zip(corners, kinds):
        if not B.kept_out(x, z, r.y, 0.8):
            at_floor(r, x, z, kind, 0.0, "Corner")


def themed(r, names):
    key = (r.name_key + " " + names.get(r.name_key, "")).lower()
    for words, kit in NAME_THEMES:
        if any(w in key for w in words):
            return kit
    return None


def dress(plan, names):
    _turn.clear()
    n = 0
    for r in plan.rooms.values():
        if r.get("terrain") or r.kind in ("outdoor", "grounds", "stair_turret") or r.inside is not None and r.kind == "outdoor":
            continue
        n += dress_room(plan, r, names)
    return n


def dress_room(plan, r, names):
    before = len(B.nodes)
    cx, cz = r.centre()
    if r.kind == "dormitory":
        side = "n" if r.width >= r.depth else "w"
        for s, along in wall_slots(r, 1.4)[:8]:
            on_wall(r, s, along, "bed", "Bed")
            on_wall(r, s, along, "trunk", "Trunk", inset=2.3)
        lay_runner(r, RUG_BY_HOUSE.get(r.house, "crimson"))
        corner_pieces(r, ["coat_rack", "side_table", "cushions", "side_table"])
    elif r.kind == "common_room":
        slots = wall_slots(r, 3.0)
        if slots:
            s, along = slots[0]
            on_wall(r, s, along, f"hearth_h{r.house}" if r.house else "hearth", "Hearth")
            on_wall(r, s, along + 2.2, "log_basket", "Logs")
        if floor_clear(r, cx, cz, 2.5):
            hall_rug(r, RUG_BY_HOUSE.get(r.house, "crimson"), margin=2.5)
            at_floor(r, cx, cz + 2.4, "sofa", 180.0)
            at_floor(r, cx - 2.2, cz, "armchair", 90.0)
            at_floor(r, cx + 2.2, cz, "armchair", -90.0)
            at_floor(r, cx - 2.3, cz + 2.3, "side_table", 0.0)
            at_floor(r, cx + 2.3, cz + 2.3, "side_table", 0.0)
            at_floor(r, cx, cz - 2.2, "cushions", 0.0)
        for s, along in wall_slots(r, 1.6)[1:4]:
            on_wall(r, s, along, f"banner_h{r.house or 1}", "Banner")
        for (s, along), kind in zip(wall_slots(r, 1.8)[4:], ["bookshelf", "coat_rack", "harp", "bookshelf", "clock"] + FILLER):
            on_wall(r, s, along, kind, "Common")
        if r.width >= 20 or r.depth >= 20:
            sitting_set(r, cx + (r.width / 4 if r.width >= r.depth else 0), cz + (r.depth / 4 if r.depth > r.width else 0), "book_stack", 4)
    elif r.kind == "classroom":
        subject = next((k for k in SUBJECT_KITS if k in r.id or k in r.name_key.lower()), None)
        kit = SUBJECT_KITS.get(subject, ["bookshelf", "cabinet"])
        front = r.get("front")
        slots = [sl for sl in wall_slots(r, 1.8) if sl[0] != front]
        for (s, along), kind in zip(slots, kit):
            on_wall(r, s, along, kind, "Kit")
    elif r.kind == "library":
        for dx in (-6.0, 6.0):
            sitting_set(r, cx + dx, cz + 4, "book_stack", 4)
        hall_rug(r, "blue", cx, cz - 2.0, 3.0)
        for (s, along), kind in zip(wall_slots(r, 2.0), ["lectern_book", "bench", "clock", "bench", "urn"]):
            on_wall(r, s, along, kind, "Library")
    elif r.kind == "hall" or r.kind == "shaft":
        slots = wall_slots(r, 2.4)
        for i, (s, along) in enumerate(slots[:8]):
            kind = ["tapestry", "portrait", "armour", "portrait"][i % 4] if r.kind == "hall" else "portrait"
            on_wall(r, s, along, kind, "Wall")
        if r.kind == "hall" and r.get("dressing") != "feast":
            for i, (s, along) in enumerate(slots[8:]):
                on_wall(r, s, along, ["bench", "urn", "plant_pot", "clock"][i % 4], "HallWall")
            if not hall_rug(r, runner_colour(r)):
                lay_runner(r, runner_colour(r))
            if r.id == "entrance_hall":
                corner_pieces(r, ["trunk_stack", "coat_rack", "urn", "plant_pot"], 2.0)
            else:
                corner_pieces(r, ["plant_pot", "urn", "urn", "plant_pot"], 2.0)
        if r.kind == "shaft":
            for k in range(1, r.bands):
                for i, (s, along) in enumerate(slots[:6]):
                    y_lift = k * 9.0
                    B.inst(B.uname(f"Portrait_{r.id}"), prop("portrait"), on_wall_pos(r, s, along, y_lift), parent="Furniture",
                           rot_y=math.radians({"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[s]))
    elif r.kind == "corridor":
        for i, (s, along) in enumerate(wall_slots(r, 2.0)):
            on_wall(r, s, along, CORRIDOR_WALL[i % len(CORRIDOR_WALL)], "Wall")
        lay_runner(r, runner_colour(r))
    elif r.kind == "secret":
        on_wall(r, wall_slots(r, 1.2)[0][0] if wall_slots(r, 1.2) else "n", cz if r.width < r.depth else cx, "chest", "Chest") if wall_slots(r, 1.2) else None
        for s, along in wall_slots(r, 1.2)[1:3]:
            on_wall(r, s, along, "candelabra", "Candles")
        if floor_clear(r, cx, cz, 1.2):
            at_floor(r, cx, cz, "book_stack", 30.0, "Secret")
    elif r.kind == "tower":
        for (s, along), kind in zip(wall_slots(r, 1.6), ["globe", "crate", "telescope", "bookshelf", "jar_shelf"]):
            on_wall(r, s, along, kind, "Tower")
        if not hall_rug(r, "crimson", margin=2.5):
            at_floor(r, cx, cz, "cushions", 0.0, "Tower") if floor_clear(r, cx, cz, 1.2) else None
    elif r.kind == "bridge":
        for s, along in wall_slots(r, 1.6)[:2]:
            on_wall(r, s, along, "banner_h2", "Banner")
    else:   # rooms: by name, else a sitting room
        kit = themed(r, names) or (["barrel", "crate"] if r.id == "kitchens" else ["table", "chair", "bookshelf"])
        if r.id == "kitchens":
            kit = ["hearth", "workbench", "barrel", "barrel"]
        slots = wall_slots(r, 1.8)
        fill = kit + kit if r.id == "kitchens" else kit + FILLER[len(r.id) % len(FILLER):] + FILLER
        for (s, along), kind in zip(slots, fill):
            on_wall(r, s, along, kind, "Room")
        # A lived-in middle: a rug with a table set on it (two in a long room), and the corners filled.
        if r.id != "kitchens":
            colour = ["crimson", "blue", "green"][sum(map(ord, r.id)) % 3]
            long_x = r.width >= r.depth
            spots = [(cx, cz)] if max(r.width, r.depth) < 20 else \
                [(cx - r.width / 4, cz), (cx + r.width / 4, cz)] if long_x else [(cx, cz - r.depth / 4), (cx, cz + r.depth / 4)]
            for i, (x, z) in enumerate(spots):
                if hall_rug(r, colour, x, z, span=min(r.width, r.depth) if len(spots) == 1 else max(r.width, r.depth) / 2):
                    sitting_set(r, x, z, ["writing_set", "book_stack"][(len(r.id) + i) % 2], 2 + 2 * (i % 2))
            corner_pieces(r, ["plant_pot", "candelabra", "urn", "broom_bucket"][: 2 + len(r.id) % 3])
        if r.house:
            for s, along in wall_slots(r, 1.6)[-2:]:
                on_wall(r, s, along, f"banner_h{r.house}", "Banner")
    if r.kind in ("room", "common_room", "library", "classroom") and r.id != "kitchens" and r.ceiling_y - r.y >= 8.0:
        high_gallery(r)
    if r.get("dressing") == "feast":
        on_wall(r, "n", cx, "high_table", "HighTable", inset=6.5)
        for i in range(4):
            x = r.x0 + r.width * (i + 0.5) / 4
            on_wall(r, "n", x, f"banner_h{i + 1}", "HouseBanner")
    if r.id == "greenhouse":
        for (s, along), kind in zip(wall_slots(r, 2.6), ["workbench", "plant_pot", "workbench", "plant_pot"]):
            on_wall(r, s, along, kind, "Green")
    return len(B.nodes) - before


# Lift of the upper row of portraits above their usual hang (tall rooms; clear of shelves).
HIGH_LIFT = 2.6


def high_gallery(r):
    """Tall rooms (9 m walls) get a second row of portraits high above the furniture, in
    the gaps between the wall slots used below, so the upper walls are not bare stone."""
    for i, (s, along) in enumerate(wall_slots(r, 2.0)):
        if i % 3:
            continue
        B.inst(B.uname(f"HighPortrait_{r.id}"), prop("portrait"), on_wall_pos(r, s, along, HIGH_LIFT), parent="Furniture",
               rot_y=math.radians({"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[s]))


def on_wall_pos(r, side, along, lift):
    if side in "we":
        return ((r.x0 + T / 2) if side == "w" else (r.x1 - T / 2), r.y + lift, along)
    return (along, r.y + lift, (r.z0 + T / 2) if side == "n" else (r.z1 - T / 2))
