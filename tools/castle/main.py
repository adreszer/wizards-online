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


def plan_from_data(data, grounds_cfg=None):
    from grounds import zones
    plan = program.from_data(data)
    zones.add_terrain_rooms(plan, grounds_cfg or load_grounds())
    return circulation.derive(plan)


def make_plan(path=PROGRAM, grounds_path=GROUNDS):
    with open(path) as f:
        data = json.load(f)
    return plan_from_data(data, load_grounds(grounds_path))


def main(argv=None):
    from grounds import export as gexport, generate as ggenerate, rules as grules, zones
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--program", default=PROGRAM)
    ap.add_argument("--grounds", default=GROUNDS)
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--preview", action="store_true", help="write SVG previews")
    args = ap.parse_args(argv)
    try:
        plan = make_plan(args.program, args.grounds)
    except PlanError as e:
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
    with open(OUT, "w") as f:
        f.write(text)
    from . import exterior
    shell = exterior.write(exterior.generate(plan, build.units, g.terrain))
    export.area_map(plan, AREA_MAP)
    print("name keys:", " ".join(sorted({r.name_key for r in plan.rooms.values()})))
    print("  ".join(f"{k.replace('_', ' ')}: {v}" for k, v in stats.items()))
    print("exterior:", "  ".join(f"{k}: {v}" for k, v in shell.items()))
    print("grounds:", "  ".join(f"{k}: {len(v)}" for k, v in sorted(g.scatter.items())),
          " paths:", len(g.paths), " bridges:", len(g.bridges))
