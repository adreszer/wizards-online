"""Generated secrets (docs/castle-generation.md, 4.3 and Milestone 31).

  hidden rooms  small chambers (kind "secret") carved into unused space beside a public
                room, behind a SecretWall; each holds a fragment
  shortcuts     secret walls between two public rooms that share a wall but are far apart
                on foot (a tapestry, a mirror)
  chains        one mystery per secret, picked from three patterns:
                  clue      read a plaque placed in a nearby room, then strike the wall
                  torchlit  come to the wall's room holding a torch, then strike the wall
                  together  two players stand in the room, then strike the wall (online only;
                            offline the clue pattern stands in)
Outputs (written by write()): nakama/content/generated_mysteries.json and
generated_strings.json (server-only), content/castle/generated_offline_mysteries.json
(public offline versions), and plan.generated_names / plan.generated_placements for the
builder (plaques, fragments) and the translations.
"""
import json
import random

from .geometry import STOREY, overlaps

HIDDEN_NAMES = [
    ("Forgotten Study", "Zapomniany Gabinet"), ("Dusty Alcove", "Zakurzona Wnęka"), ("Whispering Closet", "Szepcząca Komórka"),
    ("Painter's Hideaway", "Kryjówka Malarza"), ("Lost Workshop", "Zaginiona Pracownia"), ("Feather Nook", "Pierzasty Kącik"),
    ("Candlemaker's Cell", "Cela Świecarza"), ("Sealed Reliquary", "Zamknięty Relikwiarz"), ("Moth Room", "Pokój Ćm"),
    ("Clockmaker's Den", "Pracownia Zegarmistrza"), ("Star Chart Cupboard", "Szafa Map Nieba"), ("Echoing Chamber", "Komnata Echa"),
    ("Herbalist's Hide", "Schowek Zielarki"), ("Glass Room", "Szklany Pokój"), ("Old Map Cupboard", "Schowek Starych Map"),
    ("Silent Chapel of Bells", "Cicha Kaplica Dzwonów"), ("Locksmith's Hole", "Nora Ślusarza"), ("Scribe's Refuge", "Schronienie Skryby"),
]
# Hand-written texts for the first three chains; the rest use the templates below.
POLISHED = [
    {"clue": ("The plaque ends mid-sentence: “...and the north stone answers only to a firm push of will.”",
              "Tablica urywa się w pół zdania: „...a północny kamień ustępuje tylko stanowczemu pchnięciu woli.”"),
     "solved": ("Stone grinds on stone and a forgotten room breathes out a century of dust.",
                "Kamień zgrzyta o kamień, a zapomniana komnata wydycha kurz całego stulecia.")},
    {"clue": ("In the torchlight a soot mark shaped like a keyhole appears on the wall, then fades.",
              "W blasku pochodni na ścianie pojawia się ślad sadzy w kształcie dziurki od klucza i znika."),
     "solved": ("The keyhole flares, the wall folds aside, and warm air smelling of old wax rolls out.",
                "Dziurka od klucza rozbłyska, ściana składa się na bok, a ze środka bucha ciepłe powietrze pachnące starym woskiem.")},
    {"clue": ("Two sets of footprints are carved into the floor here, side by side, facing the wall.",
              "W posadzce wyryto dwie pary śladów stóp, obok siebie, zwrócone ku ścianie."),
     "solved": ("Standing together was the key: the wall swings open like a door that was always there.",
                "Kluczem było stanąć razem: ściana otwiera się jak drzwi, które zawsze tu były.")},
]
TEMPLATES = {
    "clue": (("A note scratched beside the {room}'s fireplace reads: “Push where the mortar is new.”",
              "{room_pl}: notatka wydrapana obok kominka brzmi: „Pchnij tam, gdzie zaprawa jest świeża.”"),
             ("Behind the wall of the {room} something gives way.", "{room_pl}: za ścianą coś ustępuje.")),
    "torchlit": (("Your torch flickers toward one stone of the {room}, as if a draught came through it.",
                  "{room_pl}: płomień pochodni chyli się ku jednemu z kamieni, jakby wiał przez niego przeciąg."),
                 ("The draught was a doorway: the stone slides away into darkness.", "Przeciąg był przejściem: kamień odsuwa się w ciemność.")),
    "together": (("The flagstones of the {room} hum when more than one of you stands on them.",
                  "{room_pl}: płyty posadzki brzęczą, gdy stoi na nich więcej niż jedna osoba."),
                 ("Your shared weight wakes the old mechanism: the wall rolls open.", "Wspólny ciężar budzi stary mechanizm: ściana się rozsuwa.")),
}
PUBLIC_KINDS = ("hall", "corridor", "classroom", "library", "room")
HIDDEN_SIZES = [(8, 8), (8, 12), (12, 8)]


def is_public(r):
    return (not r.get("terrain") and r.house == 0 and r.kind in PUBLIC_KINDS and r.get("door_style") != "locked"
            and r.inside is None)


def generate(plan, spec, names_for):
    """Add hidden rooms, shortcuts and their chains to the plan. `names_for(rid)` -> (en, pl)."""
    rng = random.Random(spec.get("seed", 0) * 7919 + 13)
    plan.generated_placements = {}
    plan.chains = []
    hidden_target = spec.get("hidden_rooms", 14)
    shortcut_target = spec.get("shortcuts", 8)
    hosts = [r for r in plan.rooms.values() if is_public(r) and r.bands == 1 and -1 <= r.storey <= 4]
    rng.shuffle(hosts)
    used_hosts = set()
    made = []
    pool = list(HIDDEN_NAMES)
    rng.shuffle(pool)
    for host in hosts:
        if len(made) >= hidden_target:
            break
        if host.id in used_hosts or any(abs(host.centre()[0] - m[1].centre()[0]) + abs(host.centre()[1] - m[1].centre()[1]) < 30
                                        and m[1].storey == host.storey for m in made):
            continue
        cand = carve(plan, host, rng)
        if cand is None:
            continue
        rect, side, at = cand
        hid = f"hidden_{host.id}"
        en, pl = pool[len(made) % len(pool)]
        plan.room(hid, *rect, storey=host.storey, kind="secret", tile="ornate", name_key="AREA_" + hid.upper(), generated_secret=True)
        plan.generated_names.append(("AREA_" + hid.upper(), en, pl))
        plan.secret(host.id, hid, at=at, storey=host.storey)
        plan.generated_placements.setdefault(hid, []).append({"id": "fragment_hidden", "kind": "fragment", "slot": "centre"})
        used_hosts.add(host.id)
        made.append((hid, host))
        plan.chains.append({"wall": f"{hid}/secret_wall", "room": host.id, "hidden": hid})
    # Shortcuts: public rooms sharing a wall, no doorway, far apart on foot.
    from .rules import walking_distances
    pairs = []
    by_storey = {}
    for r in plan.rooms.values():
        if is_public(r) and r.bands == 1:
            by_storey.setdefault(r.storey, []).append(r)
    for s, rs in by_storey.items():
        for i, a in enumerate(rs):
            for b in rs[i + 1:]:
                if shares_long_wall(a, b) and not connected(plan, a.id, b.id):
                    pairs.append((a, b))
    rng.shuffle(pairs)
    shortcuts = 0
    used_pairs = set()
    dist_cache = {}
    for a, b in pairs:
        if shortcuts >= shortcut_target:
            break
        if (a.id, b.id) in used_pairs:
            continue
        if a.id not in dist_cache:
            dist_cache[a.id] = walking_distances(plan, a.id)
        d = dist_cache[a.id].get(b.id)
        if d is None or d < 40:
            continue
        at = free_module(plan, a, b)
        if at is None:
            continue
        plan.secret(a.id, b.id, at=at, storey=a.storey, name=f"secret_from_{a.id}")
        used_pairs.add((a.id, b.id))
        shortcuts += 1
        plan.chains.append({"wall": f"{b.id}/secret_from_{a.id}", "room": a.id, "hidden": None})
    # Chains: a pattern per secret, a clue plaque where the pattern needs one.
    patterns = ["clue", "torchlit", "together"]
    for k, ch in enumerate(plan.chains):
        ch["pattern"] = patterns[k % 3] if k < 3 else rng.choice(patterns)
        ch["key"] = f"GEN_{k + 1:02d}"
        if ch["pattern"] == "clue":
            clue_room = ch["room"]
            plaque_id = f"plaque_{ch['key'].lower()}"
            plan.generated_placements.setdefault(clue_room, []).append(
                {"id": plaque_id, "kind": "plaque", "text": f"PLAQUE_{ch['key']}", "wall": "auto"})
            ch["plaque"] = f"{clue_room}/{plaque_id}"
        texts = POLISHED[k] if k < 3 else None
        en_room, pl_room = names_for(ch["room"])
        if texts:
            ch["clue"], ch["solved"] = texts["clue"], texts["solved"]
        else:
            (ce, cp), (se, sp) = TEMPLATES[ch["pattern"]]
            ch["clue"] = (ce.format(room=en_room), cp.format(room_pl=pl_room))
            ch["solved"] = (se.format(room=en_room), sp.format(room_pl=pl_room))
        if ch.get("plaque"):
            plan.generated_names.append((f"PLAQUE_{ch['key']}", ch["clue"][0], ch["clue"][1]))
            plan.generated_names.append((f"OFFLINE_MYST_{ch['key']}_SOLVED", ch["solved"][0], ch["solved"][1]))
        else:
            plan.generated_names.append((f"OFFLINE_MYST_{ch['key']}_CLUE", ch["clue"][0], ch["clue"][1]))
    return plan


def carve(plan, host, rng):
    """A free rect beside one of the host's walls (same storey), with a wall module for the
    secret wall away from corners, doorways and other secrets. (rect, side, at) or None."""
    sides = list("wens")
    rng.shuffle(sides)
    for side in sides:
        axis, coord, lo, hi = host.wall_line(side)
        if hi - lo < 12:
            continue
        for w, d in HIDDEN_SIZES:
            for off in range(int(lo) + 4, int(hi) - w - 3, 4):
                if side == "n": rect = (off, off + w, coord - d, coord)
                elif side == "s": rect = (off, off + w, coord, coord + d)
                elif side == "w": rect = (coord - d, coord, off, off + w)
                else: rect = (coord, coord + d, off, off + w)
                if not free(plan, rect, host.storey):
                    continue
                at = off + w / 2
                mod = int((at - 2) // 4) * 4
                if mod in (lo, hi - 4) or busy(plan, axis, coord, mod, host.storey):
                    continue
                return rect, side, mod + 2
    return None


def free(plan, rect, s):
    x0, x1, z0, z1 = rect
    lay = plan.meta.get("layout", {})
    bx = lay.get("buildable")
    if bx and (x0 < bx[0] or x1 > bx[1] or z0 < bx[2] or z1 > bx[3]):
        return False
    for k in lay.get("keep_clear", []):
        if x0 < k[1] and k[0] < x1 and z0 < k[3] and k[2] < z1:
            return False
    for r in plan.rooms.values():
        if r.get("terrain"):
            continue
        if r.storey <= s <= r.top_storey and x0 < r.x1 and r.x0 < x1 and z0 < r.z1 and r.z0 < z1:
            return False
        # Nothing may stand on a hidden room above the ground (it would float).
    if s > 0:
        below = [r for r in plan.rooms.values() if not r.get("terrain") and r.top_storey == s - 1]
        for i in range(int((x1 - x0) // 4)):
            for j in range(int((z1 - z0) // 4)):
                px, pz = x0 + 4 * i + 2, z0 + 4 * j + 2
                if not any(r.x0 < px < r.x1 and r.z0 < pz < r.z1 for r in below):
                    return False
    return True


def busy(plan, axis, coord, mod, s):
    """A doorway, secret wall or stair hole within 8 m of this wall module."""
    for (a, c, off, st), _v in plan.door_rooms.items():
        if a == axis and c == coord and st == s and abs(off - mod) < 8:
            return True
    for sec in plan.secrets:
        if sec[2] == axis and sec[3] == coord and sec[5] == s and abs(sec[4] - mod) < 8:
            return True
    for st in plan.stairs:
        if st.get("kind") == "spiral" or st["lo"] not in plan.rooms:
            continue
        L = plan.rooms[st["lo"]]
        if L.storey <= s <= L.top_storey and L.side_of(axis, coord) == st.get("side"):
            return True
    return False


def shares_long_wall(a, b):
    if a.x1 == b.x0 or b.x1 == a.x0:
        return min(a.z1, b.z1) - max(a.z0, b.z0) >= 12
    if a.z1 == b.z0 or b.z1 == a.z0:
        return min(a.x1, b.x1) - max(a.x0, b.x0) >= 12
    return False


def connected(plan, a, b):
    return any({a, b} == set(v[:2]) for v in plan.door_rooms.values()) or any({a, b} == {s[0], s[1]} for s in plan.secrets)


def free_module(plan, a, b):
    from .geometry import shared_edge
    axis, coord, lo, hi = shared_edge(a, b)
    mods = list(range(int(lo) + 4, int(hi) - 7, 4))
    for m in mods:
        if not busy(plan, axis, coord, m, a.storey):
            return m + 2
    return None


def write(plan):
    """Server mysteries + strings (server-only) and the public offline versions."""
    mysteries, strings, offline = [], {}, []
    for ch in plan.chains:
        key = ch["key"]
        clue_key, solved_key = f"MYST_{key}_CLUE", f"MYST_{key}_SOLVED"
        strings[clue_key] = {"en": ch["clue"][0], "pl": ch["clue"][1]}
        strings[solved_key] = {"en": ch["solved"][0], "pl": ch["solved"][1]}
        if ch["pattern"] == "clue":
            first = {"event": "interact", "object": ch["plaque"], "text": clue_key}
        elif ch["pattern"] == "torchlit":
            first = {"event": "enter", "area": ch["room"], "holding": "torch", "text": clue_key}
        else:
            first = {"event": "together", "area": ch["room"], "players": 2, "text": clue_key}
        mysteries.append({"id": f"gen_{key.lower()}", "scope": "world",
                          "steps": [first, {"event": "spell", "object": ch["wall"], "effect_type": "force", "within_seconds": 180}],
                          "on_solved": {"set_state": {ch["wall"]: "revealed"}, "text": solved_key,
                                        "discovery": f"gen_{key.lower()}", "house_points": 5},
                          "reset_after_minutes": 30})
        # Offline: a clue the player reads (or a torchlit approach), then the wall.
        if ch["pattern"] == "clue":
            ofirst = {"event": "interact", "object": ch["plaque"], "text": f"OFFLINE_MYST_{key}_SOLVED"}
        else:
            ofirst = {"event": "enter", "area": ch["room"], "text": f"OFFLINE_MYST_{key}_CLUE"}
        offline.append({"id": f"offline_gen_{key.lower()}", "steps": [ofirst, {"event": "spell", "object": ch["wall"], "effect_type": "force"}],
                        "on_solved": {"set_state": {ch["wall"]: "revealed"}}})
    with open("nakama/content/generated_mysteries.json", "w") as f:
        json.dump({"mysteries": mysteries}, f, indent=1, ensure_ascii=False)
        f.write("\n")
    with open("nakama/content/generated_strings.json", "w") as f:
        json.dump(strings, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    with open("content/castle/generated_offline_mysteries.json", "w") as f:
        json.dump({"mysteries": offline}, f, indent=1, ensure_ascii=False)
        f.write("\n")
    return len(mysteries)
