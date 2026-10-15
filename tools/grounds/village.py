"""The village beyond the estate's outer gate, and its railway station (grounds.json "village").

Placeholder names until the owner picks them (CLAUDE.md): "the village", its square,
shops by trade, "the station".

expand(cfg) runs when grounds.json is loaded. It lays out the building lots along the high
street from the seed (pinned buildings around the square and the station hall stay where
the data puts them) and appends what the grounds pipeline already knows how to handle:
terraces (the flat site, the station yard, the railway cutting), landmarks (the village
and the station: zones, tree keep-out, rule G3), paths (the road from the gatehouse, the
high street, the square, the station forecourt) and zones (every building you can walk
into is its own area: a shop, the inn, the post office, the station hall).

write(g) writes levels/grounds/village.json, which Village (gameplay/world/village.gd)
turns into merged meshes and collision at load, like the castle's exterior shell.
emit(sc, g) adds the Village node, the street lanterns and the StationArrival marker
(where new players will step off the train) to grounds.tscn.

Rules V1-V4 (validate) refuse a village whose buildings overlap the streets or each other,
whose doors open onto nothing, that stands below or in the terrain, or whose railway
does not run from the buffers into a hillside.

Frame: +X east, +Z south, y up. A building's "front" is the side with its door.
"""
import json
import math
import os
import random

OUT = "levels/grounds/village.json"
RES = "res://levels/grounds/village.json"

GROUND_STOREY = 4.4      # ground-floor walls (the shop interiors' ceiling height)
UPPER_STOREY = 3.4
FLOOR_ABOVE_SITE = 0.5   # floors stand on a stone plinth, one 0.25 m step at the door
DOOR_WIDTH = 2.0
ENTERABLE = ("shop", "inn", "post_office", "station")
RAIL_GAUGE = 1.5
PLASTERS = 6             # palette sizes in village.gd
ROOFS = 3


def _grid(v):
    return int(round(v / 4.0)) * 4


def expand(cfg):
    """Lays out the village and adds its terraces, landmarks, paths and zones to cfg."""
    v = cfg.get("village")
    if not v or "_layout" in v:
        return cfg
    rng = random.Random(v["seed"])
    site_h = v["height"]
    floor = site_h + FLOOR_ABOVE_SITE
    st = v["station"]
    street = v["street"]
    buildings = []

    def add(spec, rect, front):
        kind = spec.get("kind", "house")
        b = {
            "id": spec["id"], "kind": kind, "rect": list(rect), "front": front,
            "floor": floor, "enterable": kind in ENTERABLE,
            "storeys": spec.get("storeys", rng.choice((2, 2, 3)) if kind == "house" else (3 if kind == "inn" else 2)),
            "roof": spec.get("roof", rng.choice(("side", "front")) if kind != "station" else "side"),
            "plaster": rng.randrange(PLASTERS), "slate": rng.randrange(ROOFS),
            "jetty": kind != "station" and rng.random() < 0.6,
            "chimney": rng.choice((-1, 1)),
            "name_key": spec.get("name_key", "AREA_VILLAGE_" + spec["id"].upper()),
            "goods": spec.get("goods", kind),
        }
        x0, x1, z0, z1 = rect
        along = (x0, x1) if front in ("n", "s") else (z0, z1)
        width = along[1] - along[0]
        if b["enterable"] or width < 14:
            b["door"] = (along[0] + along[1]) / 2
        else:
            b["door"] = along[0] + width * rng.choice((0.3, 0.7))
        if spec.get("door") is not None:
            b["door"] = spec["door"]
        if spec.get("back_door") is not None:
            b["back_door"] = spec["back_door"]
        buildings.append(b)

    # Rows along the high street: lots in order, 4 m grid widths, terraced or with alleys.
    for row in v["rows"]:
        side = row["side"]
        front_z = row["front"]
        cursor = row["from"]
        lots = list(row["lots"])
        n_house = 0
        i = 0
        while True:
            if i < len(lots):
                spec = lots[i] if isinstance(lots[i], dict) else {"kind": lots[i]}
            elif row.get("fill", True):
                spec = {"kind": "house"}
            else:
                break
            kind = spec.get("kind", "house")
            if "id" not in spec:
                n_house += 1
                spec = dict(spec, id=f"{row['id']}_house_{n_house}")
            width = spec.get("width", 16 if kind != "house" else rng.choice((12, 12, 16)))
            depth = spec.get("depth", 16 if kind != "house" else rng.choice((12, 16)))
            if i > 0:
                cursor += rng.choice((0, 0, 4))
            if cursor + width > row["to"]:
                if i < len(lots):
                    raise ValueError(f"village row {row['id']}: lot {spec['id']} does not fit before {row['to']}")
                break
            z0, z1 = (front_z - depth, front_z) if side == "n" else (front_z, front_z + depth)
            add(spec, (cursor, cursor + width, z0, z1), "s" if side == "n" else "n")
            cursor += width
            i += 1
    for spec in v["pinned"]:
        add(spec, spec["rect"], spec["front"])

    # Lanterns along the high street (pavement on alternating sides), the square's corners,
    # the road from the gate, the forecourt and the platform.
    lamps = []
    north_kerb = street["z"] - street["width"] / 2 + 2.5
    south_kerb = street["z"] + street["width"] / 2 - 2.5
    sq = v["square"]["rect"]
    x = street["west"] + 8
    k = 0
    while x < street["east"] - 4:
        if not (sq[0] - 4 < x < sq[1] + 4):
            lamps.append([x, north_kerb if k % 2 == 0 else south_kerb])
            k += 1
        x += 22
    for cx in (sq[0] + 2, sq[1] - 2):
        for cz in (sq[2] + 2, sq[3] - 2):
            lamps.append([cx, cz])
    road = v["road"]
    for dz in (16, 44):
        lamps.append([road["x"] + road["width"] / 2 + 1.2, road["from"] + dz])
    fc = v["forecourt"]
    lamps.append([fc["rect"][0] + 1.5, fc["rect"][3] - 1.5])
    lamps.append([fc["rect"][1] - 1.5, fc["rect"][3] - 1.5])
    plat = st["platform"]
    z = plat[2] + 10
    while z < plat[3] - 4:
        lamps.append([plat[0] + 1.0, z])
        z += 18

    v["_layout"] = {"buildings": buildings, "lamps": lamps, "floor": floor}

    # Terraces: the site, then the station yard and the cutting (applied in this order).
    cfg.setdefault("terraces", [])
    cfg["terraces"] += [
        # The road from the gate climbs onto the site: its carving stays (no re-flatten, no step).
        {"id": "village_site", "rect": v["site"], "height": site_h, "blend": 30, "keep_carving": True},
        {"id": "station_yard", "rect": st["yard"], "height": st["bed"], "blend": 5},
        # The cutting runs on through the portal's 3 m headwall, so the tunnel mouth opens onto level ground.
        {"id": "railway_cutting", "rect": [st["track_x"] - 6, st["track_x"] + 6, st["yard"][3], st["portal_z"] + 3.5],
         "height": st["bed"], "blend": 3},
    ]
    cfg["landmarks"] += [
        {"id": v["id"], "kind": "village", "zone": v["zone"]},
        {"id": st["id"], "kind": "station", "zone": st["zone"]},
    ]
    sx = street["z"]
    cfg["paths"] += [
        {"id": "village_road", "kind": "road", "width": road["width"], "straight": True,
         # A waypoint just inside the site pins the road to the site's height from there on.
         "points": [[road["x"], road["from"]], [road["x"], v["site"][2] + 6], [road["x"], road["to"]]]},
        {"id": "village_square", "kind": "road", "width": v["square"]["paving"], "straight": True,
         "points": [[-6, sx], [6, sx]]},
        {"id": "high_street_west", "kind": "road", "width": street["width"], "straight": True,
         "points": [[v["square"]["fountain"][0], sx], [street["west"], sx]]},
        {"id": "high_street_east", "kind": "road", "width": street["width"], "straight": True,
         "points": [[v["square"]["fountain"][0], sx], [street["east"], sx]]},
        {"id": "station_forecourt", "kind": "road", "width": fc["width"], "straight": True,
         "points": fc["points"]},
    ]
    cfg["zones"] += [{"id": "village_square", "rect": sq, "name_key": "AREA_VILLAGE_SQUARE"}]
    y0, y1 = floor, floor + GROUND_STOREY
    for b in buildings:
        if b["enterable"]:
            cfg["zones"].append({"id": b["id"], "rect": b["rect"], "name_key": b["name_key"], "kind": b["kind"],
                                 "zone_y": (round(y0, 2), round(y1, 2))})
    return cfg


# --------------------------------------------------------------------------- geometry helpers
def door_point(b, out=1.5):
    """World (x, z) a step outside the front door (out > 0) or inside (out < 0)."""
    x0, x1, z0, z1 = b["rect"]
    return {"s": (b["door"], z1 + out), "n": (b["door"], z0 - out),
            "e": (x1 + out, b["door"]), "w": (x0 - out, b["door"])}[b["front"]]


def _overlap(a, b, eps=0.01):
    return a[0] < b[1] - eps and b[0] < a[1] - eps and a[2] < b[3] - eps and b[2] < a[3] - eps


def _street_rects(v):
    s = v["street"]
    hw = s["width"] / 2
    road = v["road"]
    return {
        "high_street": (s["west"], s["east"], s["z"] - hw, s["z"] + hw),
        "village_road": (road["x"] - road["width"] / 2, road["x"] + road["width"] / 2, road["from"] + 6, road["to"]),
        "village_square": tuple(v["square"]["rect"]),
        "station_forecourt": tuple(v["forecourt"]["rect"]),
    }


def _station_rects(st):
    tx = st["track_x"]
    return {
        "platform": tuple(st["platform"]),
        "track": (tx - 2.0, tx + 2.0, st["buffer_z"] - 1.0, st["portal_z"]),
    }


# --------------------------------------------------------------------------- rules
def validate(g):
    """Rules V1-V4. Returns [(rule, where, message)]."""
    v = g.cfg.get("village")
    if not v:
        return []
    lay = v["_layout"]
    T = g.terrain
    out = []
    keep_clear = dict(_street_rects(v), **_station_rects(v["station"]))
    bs = lay["buildings"]
    # V1: buildings stand clear of each other, the streets, the platform and the track.
    for i, a in enumerate(bs):
        for b in bs[i + 1:]:
            if _overlap(a["rect"], b["rect"]):
                out.append(("V1", a["id"], f"overlaps {b['id']}"))
        for name, r in keep_clear.items():
            if _overlap(a["rect"], r):
                out.append(("V1", a["id"], f"stands on the {name.replace('_', ' ')}"))
    # V2: every door opens onto a street, the square, the forecourt or a path.
    for b in bs:
        px, pz = door_point(b, 2.0)
        on_street = any(r[0] <= px <= r[1] and r[2] <= pz <= r[3] for r in keep_clear.values())
        fz, fx = T.index(px, pz)
        iz, ix = int(round(fz)), int(round(fx))
        if not on_street and g.path_dist[iz, ix] > 1.0:
            out.append(("V2", b["id"], f"door opens onto nothing at ({px:.0f}, {pz:.0f})"))
        if b.get("back_door") is not None and b["kind"] == "station":
            x0, x1, z0, z1 = b["rect"]
            p = v["station"]["platform"]
            if not (p[0] + 1 <= b["back_door"] <= p[1] - 1 and abs(p[2] - z1) < 0.5):
                out.append(("V2", b["id"], "back door does not open onto the platform"))
    # V3: floors clear the terrain, and no building floats more than a step above it.
    import numpy as np
    for b in bs:
        x0, x1, z0, z1 = b["rect"]
        m = (T.X >= x0) & (T.X <= x1) & (T.Z >= z0) & (T.Z <= z1)
        top, low = float(T.H[m].max()), float(T.H[m].min())
        if top > b["floor"] - 0.05:
            out.append(("V3", b["id"], f"terrain at {top:.2f} reaches its floor at {b['floor']:.2f}"))
        px, pz = door_point(b, 1.0)
        step = b["floor"] - float(T.height_at(px, pz))
        if step > 0.75 or step < 0.2:
            out.append(("V3", b["id"], f"door sill {step:.2f} m above the ground outside (wants 0.25-0.75)"))
        if b["floor"] - low > 3.0:
            out.append(("V3", b["id"], f"plinth {b['floor'] - low:.1f} m tall on falling ground"))
    # V4: the railway runs level from the buffers to a portal set into rising ground.
    st = v["station"]
    tx = st["track_x"]
    zs = np.arange(st["buffer_z"], st["portal_z"] - 1, 2.0)
    hs = T.height_at(np.full(zs.shape, tx), zs)
    if float(np.abs(hs - st["bed"]).max()) > 0.15:
        out.append(("V4", st["id"], f"track bed not level (off by {float(np.abs(hs - st['bed']).max()):.2f} m)"))
    above = float(T.height_at(tx, st["portal_z"] + 8)) - st["bed"]
    if above < 9.0:
        out.append(("V4", st["id"], f"ground over the tunnel only {above:.1f} m above the rails"))
    return out


# --------------------------------------------------------------------------- export
def layout_json(g):
    v = g.cfg["village"]
    lay = v["_layout"]
    T = g.terrain
    st = v["station"]
    tx = st["track_x"]
    buildings = []
    for b in lay["buildings"]:
        x0, x1, z0, z1 = b["rect"]
        attached = []
        for o in lay["buildings"]:
            if o is b:
                continue
            ox0, ox1, oz0, oz1 = o["rect"]
            zs_overlap = min(z1, oz1) - max(z0, oz0) > 0.5
            xs_overlap = min(x1, ox1) - max(x0, ox0) > 0.5
            if zs_overlap and abs(x1 - ox0) < 0.01: attached.append("e")
            if zs_overlap and abs(x0 - ox1) < 0.01: attached.append("w")
            if xs_overlap and abs(z1 - oz0) < 0.01: attached.append("s")
            if xs_overlap and abs(z0 - oz1) < 0.01: attached.append("n")
        m = (T.X >= x0 - 1) & (T.X <= x1 + 1) & (T.Z >= z0 - 1) & (T.Z <= z1 + 1)
        e = dict(b)
        e["attached"] = sorted(set(attached))
        e["ground"] = round(float(T.H[m].min()), 3)
        px, pz = door_point(b, 1.0)
        e["sill"] = round(float(T.height_at(px, pz)), 3)
        buildings.append(e)
    # The portal's headwall rises to the ground behind it.
    xs = [tx + d for d in range(-8, 9, 2)]
    head = min(max(float(T.height_at(x, st["portal_z"] + 8)) for x in xs), st["bed"] + 12.2)
    train = []
    z = st["buffer_z"] + 1.2
    for kind, length in [("engine", 13.0), ("tender", 7.0)] + [("carriage", 17.0)] * st.get("carriages", 3):
        train.append({"kind": kind, "z": [round(z, 2), round(z + length, 2)]})
        z += length + 0.8
    plat = st["platform"]
    signs = [
        {"key": "AREA_STATION", "at": [plat[0] + 1.2, lay["floor"], plat[2] + 26], "yaw": 90},
        {"key": "AREA_STATION", "at": [plat[0] + 1.2, lay["floor"], plat[3] - 20], "yaw": 90},
    ]
    sq = v["square"]
    data = {
        "_doc": "GENERATED by tools/generate_castle.py from content/grounds/grounds.json (village); built by gameplay/world/village.gd.",
        "site_height": v["height"],
        "floor": lay["floor"],
        "ground_storey": GROUND_STOREY,
        "upper_storey": UPPER_STOREY,
        "door_width": DOOR_WIDTH,
        "buildings": buildings,
        "fountain": {"at": sq["fountain"], "y": v["height"], "radius": sq.get("fountain_radius", 3.6)},
        "benches": [[sq["fountain"][0] + dx, sq["fountain"][1] + dz, yaw] for dx, dz, yaw in
                    ((-8, 0, 90), (8, 0, -90), (0, -8, 0), (0, 8, 180))],
        "station": {
            "track_x": tx, "gauge": RAIL_GAUGE, "bed": st["bed"], "buffer_z": st["buffer_z"],
            "portal_z": st["portal_z"], "portal_top": round(head + 0.8, 2),
            "platform": plat, "platform_top": lay["floor"],
            "canopy": [plat[0], plat[1], plat[2], plat[2] + st.get("canopy_length", 48)],
            "train": train, "signs": signs,
            "benches": [[plat[0] + 3.0, zz, 90] for zz in (plat[2] + 18, plat[2] + 44, plat[2] + 70)],
        },
        "arrival": st["arrival"],
    }
    return data


def write(g, out=OUT):
    if not g.cfg.get("village"):
        return None
    data = layout_json(g)
    with open(out, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    return data


def emit(sc, g, kit):
    """Village node, lanterns and the arrival marker in grounds.tscn."""
    v = g.cfg.get("village")
    if not v:
        return
    script = sc.ext_id("Script", "res://gameplay/world/village.gd")
    sc.nodes.append(f'[node name="Village" type="Node3D" parent="."]\nscript = ExtResource("{script}")\ndata_path = "{RES}"\n')
    sc.node("Lanterns", "Node3D", parent="Village")
    T = g.terrain
    lay = v["_layout"]
    plat = v["station"]["platform"]
    for x, z in lay["lamps"]:
        on_platform = plat[0] <= x <= plat[1] and plat[2] <= z <= plat[3]
        y = lay["floor"] if on_platform else float(T.height_at(x, z))
        sc.inst("Lantern", kit["lantern_post"], (x, y, z), parent="Village/Lanterns")
    a = v["station"]["arrival"]
    sc.node("StationArrival", "Marker3D", parent="Village", pos=(a[0], lay["floor"] + 0.1, a[1]), yaw=math.radians(a[2]),
            groups=["station_arrival"])
    fx, fz = v["square"]["fountain"]
    sc.node("VillageArrival", "Marker3D", parent="Village", pos=(fx, v["height"] + 0.1, fz + 12), groups=["village_arrival"])
