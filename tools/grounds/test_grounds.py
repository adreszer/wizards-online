"""Grounds generator tests (run with the castle tests: python3 -m unittest discover -s tools -p 'test_*.py')."""
import json
import os
import unittest

import numpy as np

from castle import main
from grounds import generate, rules, village, zones

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

    def test_village_lots_are_stable(self):
        lay = self.cfg["village"]["_layout"]
        ids = [b["id"] for b in lay["buildings"]]
        self.assertEqual(len(ids), len(set(ids)))
        for shop in ("sweet_shop", "stationer", "apothecary", "bookshop", "instrument_maker", "joke_shop", "tailor",
                     "general_store", "broom_workshop", "inn", "tea_house", "post_office", "station_hall"):
            self.assertIn(shop, ids)
        again = main.load_grounds()["village"]["_layout"]["buildings"]
        self.assertEqual([b["rect"] for b in again], [b["rect"] for b in lay["buildings"]])

    def test_village_rooms_are_areas(self):
        rooms = {r.id: r for r in self.plan.rooms.values() if r.get("terrain")}
        for b in self.cfg["village"]["_layout"]["buildings"]:
            if b["enterable"]:
                self.assertIn(b["id"], rooms)
                self.assertEqual(rooms[b["id"]].kind, b["kind"])
                lo, hi = rooms[b["id"]].get("zone_y")
                self.assertEqual(lo, b["floor"])   # like the castle: an area starts at its floor
                self.assertGreater(hi, b["floor"] + 3.0)
        for need in ("village", "village_square", "station"):
            self.assertIn(need, rooms)

    def test_a_house_on_the_street_or_facing_nowhere_is_refused(self):
        cfg = json.loads(json.dumps(self.cfg, default=list))
        lay = cfg["village"]["_layout"]
        first = lay["buildings"][0]
        lay["buildings"].append(dict(first, id="squatter", rect=[-60, -48, 744, 756]))
        first["front"] = "n" if first["front"] == "s" else "s"
        g = generate.generate(cfg, self.plan)
        found = {(r, w) for r, w, _m in village.validate(g)}
        self.assertIn(("V1", "squatter"), found)
        self.assertIn(("V2", first["id"]), found)


if __name__ == "__main__":
    unittest.main()
