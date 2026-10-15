"""Layout generator: grows the castle's wings around the pinned hub.

The program's "layout" block lists wings in order. Each wing is a template attached to
a port (a wall of a room already placed); the seed varies everything the template
leaves open: corridor length, room depths, which side and storey each room lands on,
where along the port it sits, which end its stair turrets take. A wing is placed when
it overlaps nothing, stays inside the buildable area and clear of keep-clear areas;
otherwise the next candidate is tried. The whole castle is then validated by the
rules; a seed that breaks one is skipped (main.py tries the next).

Templates
  corridor   a corridor stack (one room per storey) growing out of the port, rooms on
             one or both sides (slots of `slot` metres), stair turrets at the root and/or
             the far end, optional basement (storey -1); a side room may span several
             slots and storeys (halls, the turning-stairs shaft)
  tower      a square stack of rooms with a stair turret, joined to the port at one storey
  bridge     a covered sky bridge between two towers' facing walls at one storey

Room ids: corridors <wing>_c<storey> (cm1 for the basement), turrets <wing>_stair_<a|b>,
filler rooms <wing>_r<n>; named rooms keep the id the program gives them. Generated
names go to localization/castle_generated.csv (see names()).
"""
import random

from .geometry import Plan, PlanError, overlaps, door_offsets, shared_edge, STOREY

SIDES = {"n": (0, -1), "s": (0, 1), "e": (1, 0), "w": (-1, 0)}
LEFT = {"n": "w", "s": "e", "e": "n", "w": "s"}      # left-hand side when walking outward
RIGHT = {"n": "e", "s": "w", "e": "s", "w": "n"}
STOREY_NAMES = {-1: ("cellar level", "poziom piwnic"), 0: ("ground floor", "parter"), 1: ("first floor", "pierwsze piętro"),
                2: ("second floor", "drugie piętro"), 3: ("third floor", "trzecie piętro"), 4: ("fourth floor", "czwarte piętro"),
                5: ("fifth floor", "piąte piętro"), 6: ("sixth floor", "szóste piętro")}


class LayoutError(Exception):
    pass


def sid(s):
    return f"m{-s}" if s < 0 else str(s)


class Rect:
    """Axis-aligned plan rect with helpers for building along a direction."""
    def __init__(self, x0, x1, z0, z1):
        self.x0, self.x1, self.z0, self.z1 = x0, x1, z0, z1

    def t(self):
        return (self.x0, self.x1, self.z0, self.z1)


def strip(origin_axis_coord, along_lo, along_hi, out_from, out_to, direction):
    """A rect spanning [along_lo, along_hi] across the growth direction and [out_from, out_to]
    metres outward from the port line `origin_axis_coord`."""
    dx, dz = SIDES[direction]
    c = origin_axis_coord
    if dx:   # growing east or west: 'along' is z
        xa, xb = c + dx * out_from, c + dx * out_to
        return (min(xa, xb), max(xa, xb), along_lo, along_hi)
    za, zb = c + dz * out_from, c + dz * out_to
    return (along_lo, along_hi, min(za, zb), max(za, zb))


class Layout:
    def __init__(self, plan, spec, rng):
        self.plan = plan
        self.spec = spec
        self.rng = rng
        self.buildable = spec.get("buildable")
        self.keep_clear = [tuple(r) for r in spec.get("keep_clear", [])]
        self.generated = []        # (room id, en, pl) for the generated translations
        self.placed_wings = {}

    # -- checks ---------------------------------------------------------------------------
    def fits(self, rect, s0, s1, ignore=()):
        x0, x1, z0, z1 = rect
        if self.buildable:
            bx0, bx1, bz0, bz1 = self.buildable
            if x0 < bx0 or x1 > bx1 or z0 < bz0 or z1 > bz1:
                return False
        for k in self.keep_clear:
            if x0 < k[1] and k[0] < x1 and z0 < k[3] and k[2] < z1:
                return False
        for r in self.plan.rooms.values():
            if r.get("terrain") or r.id in ignore:
                continue
            if r.kind == "outdoor" and r.inside is None and r.storey == 0 and r.bands == 1 and r.id == "grounds":
                pass
            if r.storey <= s1 and s0 <= r.top_storey and x0 < r.x1 and r.x0 < x1 and z0 < r.z1 and r.z0 < z1:
                return False
        return True

    def port(self, room_id, side):
        r = self.plan.rooms[room_id]
        axis, coord, lo, hi = r.wall_line(side)
        return r, axis, coord, lo, hi

    def name(self, rid, en, pl):
        self.generated.append(("AREA_" + rid.upper(), en, pl))

    # -- templates ------------------------------------------------------------------------
    def place(self, w):
        side = w.get("attach", {}).get("side")
        if side == "auto":
            sides = list("wens")
            self.rng.shuffle(sides)
            last = None
            for s in sides:
                try:
                    return self.place(dict(w, attach=dict(w["attach"], side=s)))
                except LayoutError as e:
                    last = e
            raise last
        t = w["template"]
        if t == "corridor":
            return self.corridor(w)
        if t == "tower":
            return self.tower(w)
        if t == "bridge":
            return self.bridge(w)
        if t == "tower_pair":
            return self.tower_pair(w)
        raise LayoutError(f"{w['id']}: unknown template {t}")

    def corridor(self, w):
        att = w["attach"]
        port_room, axis, coord, lo, hi = self.port(att["room"], att["side"])
        d = att["side"]
        s0, s1 = w["storeys"][0], w["storeys"][-1]
        basement = w.get("basement", False)
        b0 = -1 if basement else s0
        slot = w.get("slot", 16)
        width = w.get("width", 8)
        lengths = list(range(w["length"][0], w["length"][1] + 1, slot))
        depths = w.get("depth", [24])
        turret_size = 8
        candidates = []
        for L in lengths:
            for dl in depths:
                for dr in depths:
                    for off in range(int(lo) + 4, int(hi) - width - 3, 4):
                        candidates.append((L, dl, dr, off))
        self.rng.shuffle(candidates)
        candidates.sort(key=lambda c: -c[0] if w.get("prefer") == "long" else 0)
        for L, dl, dr, off in candidates[:4000]:
            built = self.try_corridor(w, port_room, axis, coord, d, off, width, L, dl, dr, slot, s0, s1, b0, turret_size)
            if built:
                return built
        raise LayoutError(f"{w['id']}: no room for the wing at {att}")

    def try_corridor(self, w, port_room, axis, coord, d, off, width, L, dl, dr, slot, s0, s1, b0, turret_size):
        sides = w.get("sides", "both")
        corr = strip(coord, off, off + width, 0, L, d)
        rooms = []                      # (id, rect, storey, bands, kw)
        if not self.fits(corr, b0, s1):
            return None
        rooms.append(("__corr", corr, b0, s1 - b0 + 1, {}))
        nslots = L // slot
        side_specs = []
        if sides in ("both", "left"):
            side_specs.append(("L", LEFT[d], dl))
        if sides in ("both", "right"):
            side_specs.append(("R", RIGHT[d], dr))
        slot_rects = {}                 # (side tag, slot index) -> rect
        for tag, side, depth in side_specs:
            for k in range(nslots):
                a0 = k * slot
                if tag == "L":
                    rect = self.side_rect(corr, d, side, a0, a0 + slot, depth)
                else:
                    rect = self.side_rect(corr, d, side, a0, a0 + slot, depth)
                slot_rects[(tag, k)] = rect
        # Turrets: at the far end on the corridor axis, and/or at the root beside the corridor.
        turrets = []
        tw = turret_size
        want = w.get("turrets", "end")
        if want in ("end", "both"):
            t = strip(coord, off, off + width, L, L + tw, d)
            turrets.append(("a", t, "end"))
        if want in ("root", "both"):
            # The root turret takes the first slot on one side (seeded), set against the corridor.
            tag = self.rng.choice([s[0] for s in side_specs])
            side = LEFT[d] if tag == "L" else RIGHT[d]
            t = self.side_rect(corr, d, side, 4, 4 + tw, tw)
            turrets.append(("b", t, ("root", tag)))
        for _n, t, where in turrets:
            if not self.fits(t, b0, s1):
                return None
        blocked_slots = {(where[1], 0) for _n, _t, where in turrets if isinstance(where, tuple)}
        # Slots that collide with what is already built stay empty on every storey (nothing
        # may stand on an empty slot), so a wing can grow past an obstacle.
        for (tag, k), rect in slot_rects.items():
            if not self.fits(rect, b0, s1):
                blocked_slots.add((tag, k))
        # Assign rooms to (storey, side, slot); spans take consecutive slots and storeys.
        free = {(s, tag, k) for s in range(s0, s1 + 1) for tag, _sd, _dp in side_specs for k in range(nslots)
                if (tag, k) not in blocked_slots}
        if b0 < s0:
            free |= {(b0, tag, k) for tag, _sd, _dp in side_specs for k in range(nslots) if (tag, k) not in blocked_slots}
        assigned = []
        specs = list(w.get("rooms", []))
        order = list(range(len(specs)))
        self.rng.shuffle(order)
        order.sort(key=lambda i: -(specs[i].get("span", 1) * len(specs[i].get("storeys", [0]))))
        for i in order:
            rs = specs[i]
            span = rs.get("span", 1)
            want_storeys = rs.get("storeys")
            options = []
            for (s, tag, k) in sorted(free):
                if want_storeys and s != want_storeys[0]:
                    continue
                if rs.get("side") and rs["side"] != tag:
                    continue
                cells = [(s2, tag, k2) for s2 in (want_storeys or [s]) for k2 in range(k, k + span)]
                if all(c in free for c in cells):
                    options.append((s, tag, k, cells))
            if not options:
                return None
            self.rng.shuffle(options)
            if rs.get("near_root"):
                options.sort(key=lambda o: o[2])
            s, tag, k, cells = options[0]
            for c in cells:
                free.discard(c)
            assigned.append((rs, s, tag, k, span, cells))
        # Build rects for assigned rooms; deeper rooms (e.g. a shaft) take their own depth.
        out = []
        for rs, s, tag, k, span, cells in assigned:
            side = LEFT[d] if tag == "L" else RIGHT[d]
            depth = rs.get("depth", dl if tag == "L" else dr)
            rect = self.side_rect(corr, d, side, k * slot, (k + span) * slot, depth)
            storeys = sorted({c[0] for c in cells})
            if not self.fits(rect, storeys[0], storeys[-1]):
                return None
            out.append((rs, rect, storeys[0], len(storeys), tag, k, span))
        fill = w.get("fill", "room")
        fillers = []
        if fill:
            for (s, tag, k) in sorted(free):
                rect = slot_rects[(tag, k)]
                if self.fits(rect, s, s):
                    fillers.append((rect, s, tag, k))
        # Everything fits: commit to the plan.
        wid = w["id"]
        P = self.plan
        en, pl = w["name"]
        corridor_ids = {}
        for s in range(b0, s1 + 1):
            cid = f"{wid}_c{sid(s)}"
            P.room(cid, *map(int, corr), storey=s, kind="corridor", wing=wid, **self.style(w))
            sn = STOREY_NAMES[s]
            self.name(cid, f"{en}, {sn[0]} corridor", f"{pl}, korytarz ({sn[1]})")
            corridor_ids[s] = cid
        turret_ids = []
        for n, t, where in turrets:
            tid = f"{wid}_stair_{n}"
            P.room(tid, *map(int, t), storey=b0, bands=s1 - b0 + 1, kind="stair_turret", pillars=False, torches=False,
                   wing=wid, house=w.get("house", 0), **self.style(w))
            self.name(tid, f"{en}, stair turret", f"{pl}, wieżyczka schodowa")
            P.spiral(tid)
            turret_ids.append((tid, where))
        side_rooms = []
        for rs, rect, st, bands, tag, k, span in out:
            kw = {key: v for key, v in rs.items() if key not in ("id", "kind", "span", "storeys", "side", "depth", "near_root", "en", "pl", "door")}
            kind = rs.get("kind", "room")
            if kind == "classroom" and "front" not in kw:
                kw["front"] = d_away(corr, rect)
            P.room(rs["id"], *map(int, rect), storey=st, bands=bands, kind=kind, wing=wid, **kw)
            if rs.get("en"):
                self.name(rs["id"], rs["en"], rs["pl"])
            side_rooms.append((rs["id"], st, bands, rs.get("door", "middle")))
        pool = list(w.get("names", []))
        self.rng.shuffle(pool)
        n = 0
        for rect, s, tag, k in fillers:
            n += 1
            rid = f"{wid}_r{n}"
            kind = w.get("fill_kind", "room")
            P.room(rid, *map(int, rect), storey=s, kind=kind, wing=wid, house=w.get("house", 0), **self.style(w))
            if pool:
                nen, npl = pool[(n - 1) % len(pool)]
                rnd = (n - 1) // len(pool)
                suffix_en = "" if rnd == 0 else f" {['', 'II', 'III', 'IV', 'V', 'VI'][min(rnd, 5)]}"
                self.name(rid, nen + suffix_en, npl + suffix_en)
            else:
                self.name(rid, f"{en}, room {n}", f"{pl}, sala {n}")
            side_rooms.append((rid, s, 1, "middle"))
        # Doors: corridor root to the port room where it has a floor; corridor to each side room;
        # corridor to the turrets.
        from .rules import room_levels
        port_levels = room_levels(P, port_room)
        root_storeys = w.get("root_storeys") or [s for s in range(b0, s1 + 1) if s in port_levels]
        if not root_storeys and not turret_ids:
            raise LayoutError(f"{wid}: the wing would be unreachable")
        for s in root_storeys:
            if s in port_levels and port_room.storey <= s <= port_room.top_storey:
                P.door(corridor_ids[s], port_room.id, storey=s)
        for rid, st, bands, where in side_rooms:
            levels = room_levels(P, P.rooms[rid])
            for s in range(st, st + bands):
                if s in levels and s in corridor_ids:
                    P.door(corridor_ids[s], rid, at=self.door_at(P, corridor_ids[s], rid, where), storey=s)
        for tid, where in turret_ids:
            for s in range(b0, s1 + 1):
                P.door(corridor_ids[s], tid, storey=s)
        self.placed_wings[wid] = {"corridor": corr, "storeys": (b0, s1), "dir": d, "turrets": turret_ids}
        return True

    @staticmethod
    def style(w):
        """Wing-wide room attributes (a sealed wing: door_style "locked")."""
        return {"door_style": w["door_style"]} if w.get("door_style") else {}

    def side_rect(self, corr, d, side, a0, a1, depth):
        """A room on `side` of the corridor rect, from a0 to a1 metres along the growth direction."""
        x0, x1, z0, z1 = corr
        dx, dz = SIDES[d]
        if dx:      # corridor runs along x; sides are n/s
            along_lo = x0 + a0 if dx > 0 else x1 - a1
            along_hi = x0 + a1 if dx > 0 else x1 - a0
            if side == "n":
                return (along_lo, along_hi, z0 - depth, z0)
            return (along_lo, along_hi, z1, z1 + depth)
        along_lo = z0 + a0 if dz > 0 else z1 - a1
        along_hi = z0 + a1 if dz > 0 else z1 - a0
        if side == "w":
            return (x0 - depth, x0, along_lo, along_hi)
        return (x1, x1 + depth, along_lo, along_hi)

    def door_at(self, P, a, b, where):
        """Doorway offset on the shared wall: the middle, or a non-corner module chosen by the seed."""
        axis, coord, lo, hi = shared_edge(P.rooms[a], P.rooms[b])
        n = int((hi - lo) // 4)
        if n <= 2:
            return None
        mods = list(range(1, n - 1))
        if where == "middle":
            k = mods[len(mods) // 2]
        else:
            k = self.rng.choice(mods)
        return lo + 4 * k + 2

    def tower(self, w):
        att = w["attach"]
        port_room, axis, coord, lo, hi = self.port(att["room"], att["side"])
        d = att["side"]
        size = w.get("size", 16)
        s0, s1 = w["storeys"][0], w["storeys"][-1]
        offs = list(range(int(lo) - size + 8, int(hi) - 7, 4))
        self.rng.shuffle(offs)
        for off in offs:
            rect = strip(coord, off, off + size, 0, size, d)
            if not self.fits(rect, s0, s1):
                continue
            # Its turret on a free side (not the port side), seeded.
            tsides = [s for s in "wens" if s != {"n": "s", "s": "n", "e": "w", "w": "e"}[d]]
            self.rng.shuffle(tsides)
            if w.get("turret_side"):
                tsides = [w["turret_side"]]
            if not self.door_off_corner(port_room, rect):
                continue
            for ts in tsides:
                t = self.turret_beside(rect, ts)
                if self.fits(t, s0, s1):
                    if not self.shares_door_wall(port_room, rect, w.get("door_storey", s0)):
                        continue
                    return self.commit_tower(w, rect, t, port_room, s0, s1)
        raise LayoutError(f"{w['id']}: no room for the tower at {att}")

    def door_off_corner(self, port_room, rect):
        """Would the doorway between the port room and a tower at `rect` stay out of both
        rooms' corner modules (rule C7)?"""
        from .geometry import Room
        probe = Room("__probe", *map(int, rect))
        try:
            axis, coord, lo, hi = shared_edge(port_room, probe)
            off = door_offsets(lo, hi, None, 1)[0]
        except PlanError:
            return False
        for r in (port_room, probe):
            a2, c2, rlo, rhi = r.wall_line(r.side_of(axis, coord))
            if rhi - rlo >= 12 and (off == rlo or off + 4 == rhi):
                return False
        return True

    def shares_door_wall(self, port_room, rect, s):
        x0, x1, z0, z1 = rect
        if not (port_room.storey <= s <= port_room.top_storey):
            return False
        if port_room.x1 == x0 or port_room.x0 == x1:
            return min(port_room.z1, z1) - max(port_room.z0, z0) >= 8
        if port_room.z1 == z0 or port_room.z0 == z1:
            return min(port_room.x1, x1) - max(port_room.x0, x0) >= 8
        return False

    def turret_beside(self, rect, side):
        x0, x1, z0, z1 = rect
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        if side == "e": return (x1, x1 + 8, cz - 4, cz + 4)
        if side == "w": return (x0 - 8, x0, cz - 4, cz + 4)
        if side == "n": return (cx - 4, cx + 4, z0 - 8, z0)
        return (cx - 4, cx + 4, z1, z1 + 8)

    def commit_tower(self, w, rect, trect, port_room, s0, s1):
        P = self.plan
        wid = w["id"]
        en, pl = w["name"]
        kinds = w.get("kinds", {})
        ids = []
        for s in range(s0, s1 + 1):
            rid = f"{wid}_{sid(s)}"
            kind, house = kinds.get(str(s), ("tower", w.get("house", 0)))
            top = s == s1 and w.get("open_top")
            P.room(rid, *map(int, rect), storey=s, kind="outdoor" if top else kind, house=house, tower=wid, wing=wid,
                   ceiling=not top, rows=1 if top else 2, pillars=not top, torches=not top,
                   tile="ornate" if kind in ("common_room", "classroom") else "plain",
                   **({"battlements": True} if top else {}))
            sn = STOREY_NAMES[s]
            label = w.get("labels", {}).get(str(s))
            if label:
                self.name(rid, label[0], label[1])
            else:
                self.name(rid, f"{en}, {sn[0]}", f"{pl}, {sn[1]}")
            ids.append(rid)
        tid = f"{wid}_stair"
        P.room(tid, *map(int, trect), storey=s0, bands=s1 - s0 + 1, kind="stair_turret", pillars=False, torches=False,
               tower=wid, wing=wid, house=w.get("house", 0))
        self.name(tid, f"{en}, stair turret", f"{pl}, wieżyczka schodowa")
        P.spiral(tid)
        for s, rid in zip(range(s0, s1 + 1), ids):
            P.door(rid, tid, storey=s)
        ds = w.get("door_storey", s0)
        if port_room is not None and ds is not None:
            P.door(f"{wid}_{sid(ds)}", port_room.id, storey=ds)
        self.placed_wings[wid] = {"rect": rect, "storeys": (s0, s1)}
        return True

    def tower_pair(self, w):
        """Two towers side by side on one port wall, a sky bridge between them at `bridge_storey`."""
        att = w["attach"]
        port_room, axis, coord, lo, hi = self.port(att["room"], att["side"])
        d = att["side"]
        size = w.get("size", 16)
        s0, s1 = w["storeys"][0], w["storeys"][-1]
        gaps = list(w.get("gaps", [12, 16]))
        offs = list(range(int(lo) - size + 8, int(hi) - 7, 4))
        self.rng.shuffle(offs)
        self.rng.shuffle(gaps)
        a_spec = dict(w, id=w["towers"][0]["id"], name=w["towers"][0]["name"], kinds=w["towers"][0].get("kinds", {}),
                      labels=w["towers"][0].get("labels", {}))
        b_spec = dict(w, id=w["towers"][1]["id"], name=w["towers"][1]["name"], kinds=w["towers"][1].get("kinds", {}),
                      labels=w["towers"][1].get("labels", {}))
        for off in offs:
            for gap in gaps:
                ra = strip(coord, off, off + size, 0, size, d)
                rb = strip(coord, off + size + gap, off + 2 * size + gap, 0, size, d)
                gap_rect = strip(coord, off + size, off + size + gap, 0, size, d)
                if not (self.fits(ra, s0, s1) and self.fits(rb, s0, s1) and self.fits(gap_rect, w["bridge_storey"], w["bridge_storey"])):
                    continue
                if not self.shares_door_wall(port_room, ra, w.get("door_storey", s0)) or not self.door_off_corner(port_room, ra):
                    continue
                ta = self.turret_beside(ra, {"n": "s", "s": "n", "e": "w", "w": "e"}[d] if False else self.outer_side(d))
                tb = self.turret_beside(rb, self.outer_side(d))
                if not (self.fits(ta, s0, s1) and self.fits(tb, s0, s1)):
                    continue
                self.commit_tower(a_spec, ra, ta, port_room, s0, s1)
                self.commit_tower(dict(b_spec, door_storey=None), rb, tb, None, s0, s1)
                return self.bridge({"id": w["bridge"]["id"], "name": w["bridge"]["name"],
                                    "between": [a_spec["id"], b_spec["id"]], "storey": w["bridge_storey"]})
        raise LayoutError(f"{w['id']}: no room for the tower pair at {att}")

    def outer_side(self, d):
        """The side of a tower facing away from its port (where its turret goes in a pair)."""
        return d

    def bridge(self, w):
        a, b = w["between"]
        s = w["storey"]
        A, B = self.plan.rooms[f"{a}_{sid(s)}"], self.plan.rooms[f"{b}_{sid(s)}"]
        width = w.get("width", 8)
        # Facing walls along x or z with an overlap wide enough for the bridge.
        if A.x1 <= B.x0 or B.x1 <= A.x0:
            lo, hi = max(A.z0, B.z0), min(A.z1, B.z1)
            if hi - lo < width:
                raise LayoutError(f"{w['id']}: towers do not face each other")
            mid = (lo + hi) / 2
            z0 = int(round((mid - width / 2) / 4) * 4)
            x0, x1 = (A.x1, B.x0) if A.x1 <= B.x0 else (B.x1, A.x0)
            rect = (x0, x1, z0, z0 + width)
        elif A.z1 <= B.z0 or B.z1 <= A.z0:
            lo, hi = max(A.x0, B.x0), min(A.x1, B.x1)
            if hi - lo < width:
                raise LayoutError(f"{w['id']}: towers do not face each other")
            mid = (lo + hi) / 2
            x0 = int(round((mid - width / 2) / 4) * 4)
            z0, z1 = (A.z1, B.z0) if A.z1 <= B.z0 else (B.z1, A.z0)
            rect = (x0, x0 + width, z0, z1)
        else:
            raise LayoutError(f"{w['id']}: towers overlap")
        if rect[1] - rect[0] < 4 or rect[3] - rect[2] < 4 or not self.fits(rect, s, s):
            raise LayoutError(f"{w['id']}: the bridge's way is blocked")
        en, pl = w["name"]
        self.plan.room(w["id"], *map(int, rect), storey=s, kind="bridge", support="bridge", wing=w["id"], pillars=False,
                       torches=True)
        self.name(w["id"], en, pl)
        self.plan.door(w["id"], A.id, storey=s)
        self.plan.door(w["id"], B.id, storey=s)
        return True


def d_away(corr, rect):
    """The wall of `rect` facing away from the corridor (a classroom's teaching wall)."""
    x0, x1, z0, z1 = rect
    if x1 == corr[0]: return "w"
    if x0 == corr[1]: return "e"
    if z1 == corr[2]: return "n"
    return "s"


def generate(plan, spec, seed):
    rng = random.Random(seed)
    lay = Layout(plan, spec, rng)
    for w in spec.get("wings", []):
        lay.place(w)
    for r in list(plan.rooms.values()):
        if r.kind == "shaft":
            shaft(plan, r, rng)
    return lay


def shaft(plan, R, rng):
    """The turning-stairs hall: a landing ring at every storey above the bottom, switchback
    flights against three walls (never the wall the corridors come in through), each ring
    cut open where the flight below arrives. Milestone 30 adds the shifting flights that
    cross the open middle."""
    from .geometry import rect_minus_all, T
    ring = R.get("ring", 8)
    s0, s1 = R.storey, R.top_storey
    door_sides = set()
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        if R.id in (a, b):
            door_sides.add(R.side_of(axis, coord))
    walls = [s for s in "nesw" if s not in door_sides]
    if len(walls) < 1:
        raise LayoutError(f"{R.id}: a shaft needs a wall without doorways for its flights")
    climb = {"n": "e", "e": "s", "s": "w", "w": "n"}      # each flight climbs clockwise along its wall
    holes = {}
    run = 12.0
    for k, s in enumerate(range(s0, s1)):
        side = walls[k % len(walls)]
        axis, coord, lo, hi = R.wall_line(side)
        d = climb[side]
        # The flight starts a ring's width plus the approach landing in from the wall's start.
        forward = d in ("e", "s")
        start = (lo + ring + 4.4) if forward else (hi - ring - 4.4)
        st = plan.stair(R.id, None, side, d, start, run=run, y=s * STOREY, hole=False)
        st["shaft"] = True
        # The ring above is open over the flight's upper part (headroom), like a stair hole.
        from .circulation import flight_rect, HOLE_FROM_HEIGHT
        hx0, hx1, hz0, hz1 = flight_rect(st, run * HOLE_FROM_HEIGHT / STOREY - 0.6, run, -st["width"] / 2 - 0.1, st["width"] / 2 + 0.1)
        holes[s + 1] = (hx0, hx1, hz0, hz1)
    x0, x1, z0, z1 = R.rect
    strips = [(x0, x1, z0, z0 + ring), (x0, x1, z1 - ring, z1), (x0, x0 + ring, z0 + ring, z1 - ring), (x1 - ring, x1, z0 + ring, z1 - ring)]
    for s in range(s0 + 1, s1 + 1):
        cut = [holes[s]] if s in holes else []
        for st_rect in strips:
            for piece in rect_minus_all(st_rect, cut):
                if piece[1] - piece[0] >= 0.5 and piece[3] - piece[2] >= 0.5:
                    R.extra_floors.append((tuple(round(v, 3) for v in piece), s * STOREY))


def write_names(entries, path="localization/castle_generated.csv"):
    with open(path, "w") as f:
        f.write("keys,en,pl\n")
        for key, en, pl in sorted(set(entries)):
            q = lambda s: '"' + s.replace('"', '""') + '"' if ("," in s or '"' in s) else s
            f.write(f"{key},{q(en)},{q(pl)}\n")
