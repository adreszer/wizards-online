"""Grounds generator tests (run with the castle tests: python3 -m unittest discover -s tools -p 'test_*.py')."""
import json
import os
import unittest

import numpy as np

from castle import main
from grounds import generate, rules, zones

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class GroundsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.chdir(ROOT)
        cls.plan = main.make_plan()
        cls.cfg = main.load_grounds()
        cls.g = generate.generate(cls.cfg, cls.plan)

    def test_rules_pass(self):
        self.assertEqual([str(v) for v in rules.validate(self.g, self.plan)], [])

    def test_deterministic(self):
        again = generate.generate(self.cfg, main.make_plan())
        self.assertTrue(np.array_equal(again.terrain.H, self.g.terrain.H))
        for kind in self.g.scatter:
            self.assertTrue(np.array_equal(again.scatter[kind], self.g.scatter[kind]))

    def test_castle_floors_stand_on_the_plateau(self):
        T = self.g.terrain
        h = T.height_at(0.0, 60.0)   # the forecourt
        self.assertLessEqual(float(h), 0.0)

    def test_terraces_are_flat(self):
        for t in self.cfg["terraces"]:
            x0, x1, z0, z1 = t["rect"]
            hs = self.g.terrain.height_at(np.array([x0 + 2, x1 - 2, (x0 + x1) / 2]), np.array([z0 + 2, z1 - 2, (z0 + z1) / 2]))
            self.assertTrue(np.all(np.abs(hs - t["height"]) < 0.3), hs)

    def test_outdoor_areas_are_terrain_rooms(self):
        ids = {r.id for r in self.plan.rooms.values() if r.get("terrain")}
        self.assertIn("estate", ids)
        self.assertTrue({lm["id"] for lm in self.cfg["landmarks"]} <= ids)

    def test_a_steep_path_is_refused(self):
        cfg = json.loads(json.dumps(self.cfg))
        cfg["paths"].append({"id": "goat_track", "kind": "path", "width": 3, "points": [[-160, -100], [-140, -100]], "straight": True})
        g = generate.generate(cfg, self.plan)
        self.assertIn("G2", {v.rule for v in rules.validate(g, self.plan)})


if __name__ == "__main__":
    unittest.main()
