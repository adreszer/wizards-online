"""Castle generator entry point: program -> plan -> rules -> scene + server data.

  python3 tools/generate_castle.py              build levels/castle/castle.tscn
  python3 tools/generate_castle.py --preview    also write SVG plans to .godot/castle_preview/
  python3 tools/generate_castle.py --check      validate only, write nothing
"""
import argparse
import json
import sys

from . import build, export, program, rules
from .geometry import PlanError

PROGRAM = "content/castle/program.json"
KIT = "content/castle/kit.json"
OUT = "levels/castle/castle.tscn"
AREA_MAP = "nakama/modules/world_areas.lua"


def load_kit(path=KIT):
    with open(path) as f:
        return json.load(f)


def make_plan(path=PROGRAM):
    return program.load(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--program", default=PROGRAM)
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--preview", action="store_true", help="write SVG previews")
    args = ap.parse_args(argv)
    try:
        plan = make_plan(args.program)
    except PlanError as e:
        sys.exit(f"program error: {e}")
    violations = rules.validate(plan)
    if violations:
        for v in violations:
            print(v, file=sys.stderr)
        sys.exit(f"{len(violations)} rule violation(s); nothing written")
    if args.preview:
        from . import preview
        print("preview:", preview.write_all(plan))
    if args.check:
        print("rules: ok")
        return
    stats, text = build.build(plan, load_kit())
    with open(OUT, "w") as f:
        f.write(text)
    export.area_map(plan, AREA_MAP)
    print("name keys:", " ".join(sorted({r.name_key for r in plan.rooms.values()})))
    print("  ".join(f"{k.replace('_', ' ')}: {v}" for k, v in stats.items()))
