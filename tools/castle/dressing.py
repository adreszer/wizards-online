"""Dressing pass (Milestone 32): furnishes every room by its kind, name and house.

Runs inside build.build() after the classroom furniture: it uses the builder's wall
spans (wall_free_intervals: clear of doorways, windows, pillars and torches) and its
keep-outs (stairs, landings). Props come from the kit's "props" roles, so a real model
replaces a placeholder everywhere at once. Rule D1 (budgets.py): no room left empty.
"""
import math

from . import build as B
from .geometry import T

SUBJECT_KITS = {
    "elixirs": ["cauldron", "cauldron", "cabinet", "barrel"], "herblore": ["plant_pot", "plant_pot", "workbench"],
    "stargazing": ["telescope", "globe", "telescope"], "farsight": ["crystal_table", "crystal_table", "candelabra"],
    "beastlore": ["cage", "crate", "cage"], "shapeshaping": ["pedestal", "pedestal", "cabinet"],
    "chronicles": ["bookshelf", "globe", "bookshelf"], "glyphs": ["rune_stone", "rune_stone", "bookshelf"],
    "numeromancy": ["abacus", "abacus", "bookshelf"], "warding": ["dummy", "dummy", "dummy"],
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
    (("guest", "robing", "waiting", "lounge", "lost"), ["armchair", "table", "wardrobe", "rug"]),
    (("globe",), ["globe", "globe", "telescope", "bookshelf"]),
    (("cell",), ["chest", "barrel"]),
]


def prop(kind):
    return B.KIT.get("props", {}).get(kind) or f"res://objects/environment/placeholders/{kind}.tscn"


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


def themed(r, names):
    key = (r.name_key + " " + names.get(r.name_key, "")).lower()
    for words, kit in NAME_THEMES:
        if any(w in key for w in words):
            return kit
    return None


def dress(plan, names):
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
        if floor_clear(r, cx, cz):
            at_floor(r, cx - 1.5, cz - 1.0, "rug")
    elif r.kind == "common_room":
        slots = wall_slots(r, 3.0)
        if slots:
            s, along = slots[0]
            on_wall(r, s, along, "hearth", "Hearth")
        if floor_clear(r, cx, cz, 2.5):
            at_floor(r, cx - 1.5, cz - 1.0, "rug")
            at_floor(r, cx, cz + 2.4, "sofa", 180.0)
            at_floor(r, cx - 2.2, cz, "armchair", 90.0)
            at_floor(r, cx + 2.2, cz, "armchair", -90.0)
        for s, along in wall_slots(r, 1.6)[1:4]:
            on_wall(r, s, along, f"banner_h{r.house or 1}", "Banner")
    elif r.kind == "classroom":
        subject = next((k for k in SUBJECT_KITS if k in r.id or k in r.name_key.lower()), None)
        kit = SUBJECT_KITS.get(subject, ["bookshelf", "cabinet"])
        front = r.get("front")
        slots = [sl for sl in wall_slots(r, 1.8) if sl[0] != front]
        for (s, along), kind in zip(slots, kit):
            on_wall(r, s, along, kind, "Kit")
    elif r.kind == "library":
        for dx in (-6.0, 6.0):
            if floor_clear(r, cx + dx, cz + 4):
                at_floor(r, cx + dx - 1.0, cz + 3.5, "table")
    elif r.kind == "hall" or r.kind == "shaft":
        slots = wall_slots(r, 2.4)
        for i, (s, along) in enumerate(slots[:8]):
            kind = ["tapestry", "portrait", "armour", "portrait"][i % 4] if r.kind == "hall" else "portrait"
            on_wall(r, s, along, kind, "Wall")
        if r.kind == "shaft":
            for k in range(1, r.bands):
                for i, (s, along) in enumerate(slots[:6]):
                    y_lift = k * 9.0
                    B.inst(B.uname(f"Portrait_{r.id}"), prop("portrait"), on_wall_pos(r, s, along, y_lift), parent="Furniture",
                           rot_y=math.radians({"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[s]))
    elif r.kind == "corridor":
        for i, (s, along) in enumerate(wall_slots(r, 1.6)[::3][:6]):
            on_wall(r, s, along, "portrait" if i % 2 == 0 else "armour", "Wall")
    elif r.kind == "secret":
        on_wall(r, wall_slots(r, 1.2)[0][0] if wall_slots(r, 1.2) else "n", cz if r.width < r.depth else cx, "chest", "Chest") if wall_slots(r, 1.2) else None
        for s, along in wall_slots(r, 1.2)[1:3]:
            on_wall(r, s, along, "candelabra", "Candles")
    elif r.kind == "tower":
        for (s, along), kind in zip(wall_slots(r, 1.6), ["globe", "crate", "telescope"]):
            on_wall(r, s, along, kind, "Tower")
    elif r.kind == "bridge":
        for s, along in wall_slots(r, 1.6)[:2]:
            on_wall(r, s, along, "banner_h2", "Banner")
    else:   # rooms: by name, else a sitting room
        kit = themed(r, names) or (["barrel", "crate"] if r.id == "kitchens" else ["table", "chair", "bookshelf"])
        if r.id == "kitchens":
            kit = ["hearth", "workbench", "barrel", "barrel"]
        for (s, along), kind in zip(wall_slots(r, 1.8), kit + kit):
            on_wall(r, s, along, kind, "Room")
        if r.house:
            for s, along in wall_slots(r, 1.6)[-2:]:
                on_wall(r, s, along, f"banner_h{r.house}", "Banner")
    if r.get("dressing") == "feast":
        on_wall(r, "n", cx, "high_table", "HighTable", inset=6.5)
        for i in range(4):
            x = r.x0 + r.width * (i + 0.5) / 4
            on_wall(r, "n", x, f"banner_h{i + 1}", "HouseBanner")
    if r.id == "greenhouse":
        for (s, along), kind in zip(wall_slots(r, 2.6), ["workbench", "plant_pot", "workbench", "plant_pot"]):
            on_wall(r, s, along, kind, "Green")
    return len(B.nodes) - before


def on_wall_pos(r, side, along, lift):
    if side in "we":
        return ((r.x0 + T / 2) if side == "w" else (r.x1 - T / 2), r.y + lift, along)
    return (along, r.y + lift, (r.z0 + T / 2) if side == "n" else (r.z1 - T / 2))
