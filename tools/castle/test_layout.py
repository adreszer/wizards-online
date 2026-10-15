"""Layout generator tests: deterministic per seed, every rule holds, the castle is big enough."""
import copy
import json
import os
import unittest

from castle import main, rules
from castle.layout import LayoutError

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class LayoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.chdir(ROOT)
        with open(main.PROGRAM) as f:
            cls.data = json.load(f)
        cls.grounds = main.load_grounds()

    def plan(self, seed=None):
        return main.plan_from_data(copy.deepcopy(self.data), self.grounds, seed)

    def test_same_seed_same_castle(self):
        a, b = self.plan(), self.plan()
        self.assertEqual([(r.id, r.rect, r.storey, r.bands) for r in a.rooms.values()],
                         [(r.id, r.rect, r.storey, r.bands) for r in b.rooms.values()])

    def test_seeds_differ(self):
        a = self.plan(self.data["layout"]["seed"])
        b = self.plan(self.data["layout"]["seed"] + 1)
        self.assertNotEqual({(r.id, r.rect) for r in a.rooms.values()}, {(r.id, r.rect) for r in b.rooms.values()})

    def test_the_canonical_seed_passes_every_rule(self):
        self.assertEqual([str(v) for v in rules.validate(self.plan())], [])

    def test_massive_scale(self):
        p = self.plan()
        built = [r for r in p.rooms.values() if not r.get("terrain")]
        xs = [v for r in built for v in (r.x0, r.x1)]
        zs = [v for r in built for v in (r.z0, r.z1)]
        self.assertGreaterEqual(len(built) + sum(1 for r in p.rooms.values() if r.get("terrain")), 240)
        self.assertGreaterEqual(max(xs) - min(xs), 220)
        self.assertGreaterEqual(max(zs) - min(zs), 240)

    def test_the_hub_is_pinned(self):
        p = self.plan()
        for spec in self.data["rooms"]:
            self.assertEqual(p.rooms[spec["id"]].rect, tuple(spec["rect"]), spec["id"])

    def test_every_generated_room_has_a_name(self):
        p = self.plan()
        named = {k for k, _en, _pl in p.generated_names}
        pinned = {r["id"] for r in self.data["rooms"]}
        for r in p.rooms.values():
            if r.get("terrain") or r.id in pinned:
                continue
            self.assertIn(r.name_key, named, r.id)

    def test_most_seeds_pass(self):
        ok = 0
        for seed in range(100, 106):
            try:
                if not rules.validate(self.plan(seed)):
                    ok += 1
            except LayoutError:
                pass
        self.assertGreaterEqual(ok, 3)


if __name__ == "__main__":
    unittest.main()
