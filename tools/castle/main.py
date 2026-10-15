"""Castle and grounds generator: program -> plan -> rules -> scenes + server data.

  python3 tools/generate_castle.py              build levels/castle/castle.tscn and levels/grounds/*
  python3 tools/generate_castle.py --preview    also write SVG plans to .godot/castle_preview/
  python3 tools/generate_castle.py --check      validate only, write nothing
"""
import argparse
import json
import sys

from . import build, circulation, export, program, rules
from .geometry import PlanError

PROGRAM = "content/castle/program.json"
GROUNDS = "content/grounds/grounds.json"
KIT = "content/castle/kit.json"
OUT = "levels/castle/castle.tscn"
AREA_MAP = "nakama/modules/world_areas.lua"


def load_kit(path=KIT):
    with open(path) as f:
        return json.load(f)


def load_grounds(path=GROUNDS):
    with open(path) as f:
        return json.load(f)


def plan_from_data(data, grounds_cfg=None, seed=None):
    from grounds import zones
    from . import layout
    plan = program.from_data(data)
    plan.generated_names = []
    if data.get("layout"):
        spec = data["layout"]
        lay = layout.generate(plan, spec, spec.get("seed", 0) if seed is None else seed)
        plan.generated_names = lay.generated
    from . import setpieces, secrets
    setpieces.prepare(plan)
    if data.get("layout"):
        secrets.generate(plan, data["layout"], names_lookup(plan))
    zones.add_terrain_rooms(plan, grounds_cfg or load_grounds())
    return circulation.derive(plan)


def names_lookup(plan):
    """room id -> (en, pl) display names (generated names first, then translations.csv)."""
    import csv
    names = {k: (en, pl) for k, en, pl in plan.generated_names}
    with open("localization/translations.csv", newline="") as f:
        for row in csv.reader(f):
            if len(row) >= 3 and row[0].startswith("AREA_"):
                names.setdefault(row[0], (row[1], row[2]))
    return lambda rid: names.get(plan.rooms[rid].name_key, (rid.replace("_", " "), rid.replace("_", " ")))


def make_plan(path=PROGRAM, grounds_path=GROUNDS, seed=None):
    with open(path) as f:
        data = json.load(f)
    return plan_from_data(data, load_grounds(grounds_path), seed)


def search(path, grounds_path, first, count):
    """Try layout seeds first..first+count-1; print which pass every castle rule."""
    from .layout import LayoutError
    ok = []
    for seed in range(first, first + count):
        try:
            plan = make_plan(path, grounds_path, seed)
        except (LayoutError, PlanError) as e:
            print(f"seed {seed}: layout failed ({e})")
            continue
        v = rules.validate(plan)
        rooms = sum(1 for r in plan.rooms.values() if not r.get("terrain"))
        print(f"seed {seed}: {len(v)} violation(s), {rooms} rooms" + (f"  first: {v[0]}" if v else ""))
        if not v:
            ok.append(seed)
    print("passing seeds:", ok)


def main(argv=None):
    from grounds import export as gexport, generate as ggenerate, rules as grules, zones
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--program", default=PROGRAM)
    ap.add_argument("--grounds", default=GROUNDS)
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--preview", action="store_true", help="write SVG previews")
    ap.add_argument("--seed", type=int, help="layout seed (default: the program's)")
    ap.add_argument("--search", type=int, metavar="N", help="try N layout seeds from --seed and list the ones that pass")
    args = ap.parse_args(argv)
    if args.search:
        search(args.program, args.grounds, args.seed or 0, args.search)
        return
    from .layout import LayoutError
    try:
        plan = make_plan(args.program, args.grounds, args.seed)
    except (PlanError, LayoutError) as e:
        sys.exit(f"program error: {e}")
    cfg = load_grounds(args.grounds)
    violations = rules.validate(plan)
    g = ggenerate.generate(cfg, plan)
    violations += grules.validate(g, plan)
    if violations:
        for v in violations:
            print(v, file=sys.stderr)
        sys.exit(f"{len(violations)} rule violation(s); nothing written")
    if args.preview:
        from . import preview
        print("preview:", preview.write_all(plan, g))
    if args.check:
        print("rules: ok")
        return
    zones.set_zone_heights(plan, g)
    kit = load_kit()
    gexport.write_data(g)
    gexport.write_scene(g, kit)
    stats, text = build.build(plan, kit)
    from . import budgets
    over = budgets.check(plan, build.units, build.placed_nodes)
    if over:
        for v in over:
            print(v, file=sys.stderr)
        sys.exit(f"{len(over)} budget violation(s); nothing written")
    with open(OUT, "w") as f:
        f.write(text)
    from . import exterior
    shell = exterior.write(exterior.generate(plan, build.units, g.terrain))
    export.area_map(plan, AREA_MAP)
    from . import layout, secrets
    layout.write_names(plan.generated_names)
    print("secrets:", secrets.write(plan), "chains")
    print("name keys:", " ".join(sorted({r.name_key for r in plan.rooms.values()})))
    print("  ".join(f"{k.replace('_', ' ')}: {v}" for k, v in stats.items()))
    print("exterior:", "  ".join(f"{k}: {v}" for k, v in shell.items()))
    print("grounds:", "  ".join(f"{k}: {len(v)}" for k, v in sorted(g.scatter.items())),
          " paths:", len(g.paths), " bridges:", len(g.bridges))
