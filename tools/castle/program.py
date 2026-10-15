"""Loads content/castle/program.json into a Plan.

The program is the authored description of the castle. Every room listed with a
"rect" is pinned: it is built exactly there. Rooms without a rect are placed by
the layout generator (layout.py) before the plan is built. Doors, secret walls,
stairs, landings and parapets are declared in order; order is kept because it
fixes node names and object ids in the generated scene.

  rooms:    {id, rect: [x0, x1, z0, z1], storey, bands, kind, house, tile, rows, ceiling,
             pillars, torches, torch_spacing, inside, name_key, no_torch_sides,
             front, no_window_sides, door_style, dressing, …}
  doors:    {a, b, at, storey, count}  or  {on: true, room, side, at, storey, count, to}
  secrets:  {a, b, at, storey, name}
  stairs:   {lo, hi, side, direction, start, run, width, rise, hole, y, kind}
  landings: {room, rect, y}            extra floors inside tall rooms
  parapets: {centre, size}             railings the rules cannot derive
  waivers:  {rule, where, until, why}  tracked exceptions (each names the milestone that removes it)
  stairs of kind "spiral": {kind: "spiral", lo: <stair turret room>}
"""
import json

from .geometry import Plan, PlanError

ROOM_KEYS = {"storey", "bands", "kind", "ceiling", "rows", "pillars", "torches", "tile", "house",
             "inside", "torch_spacing", "name_key"}


def load(path):
    with open(path) as f:
        data = json.load(f)
    return from_data(data)


def from_data(data):
    plan = Plan()
    plan.meta = {k: v for k, v in data.items() if k not in ("rooms", "doors", "secrets", "stairs", "landings", "parapets")}
    plan.start = tuple(data.get("start", plan.start))
    for spec in data["rooms"]:
        if "rect" not in spec:
            raise PlanError(f"{spec['id']}: unplaced room (run the layout generator first)")
        add_room(plan, spec)
    apply_connections(plan, data)
    return plan


def add_room(plan, spec):
    x0, x1, z0, z1 = spec["rect"]
    kw = {k: v for k, v in spec.items() if k in ROOM_KEYS}
    extra = {k: v for k, v in spec.items() if k not in ROOM_KEYS and k not in ("id", "rect", "no_torch_sides")}
    r = plan.room(spec["id"], x0, x1, z0, z1, **kw, **extra)
    r.no_torch_sides.update(spec.get("no_torch_sides", ""))
    return r


def apply_connections(plan, data):
    for d in data.get("doors", []):
        if d.get("on"):
            plan.door_on(d["room"], d["side"], d.get("at"), d.get("storey"), d.get("count", 1), d.get("to"))
        else:
            plan.door(d["a"], d["b"], d.get("at"), d.get("storey"), d.get("count", 1))
    for s in data.get("secrets", []):
        plan.secret(s["a"], s["b"], s.get("at"), s.get("storey"), s.get("name", "secret_wall"))
    for s in data.get("stairs", []):
        if s.get("kind") == "spiral":
            plan.spiral(s["lo"], **{k: v for k, v in s.items() if k not in ("lo", "kind")})
            continue
        kw = {k: v for k, v in s.items() if k not in ("lo", "hi", "side", "direction", "start")}
        plan.stair(s["lo"], s.get("hi"), s["side"], s["direction"], s["start"], **kw)
    for l in data.get("landings", []):
        plan.rooms[l["room"]].extra_floors.append((tuple(l["rect"]), l["y"]))
    for p in data.get("parapets", []):
        plan.parapets.append((tuple(p["centre"]), tuple(p["size"])))
    plan.waivers = list(data.get("waivers", []))
