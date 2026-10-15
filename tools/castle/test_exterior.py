"""Exterior shell tests: every roofed room is covered, every exposed wall module is skinned."""
import os
import unittest

from castle import build, exterior, main
from castle.geometry import STOREY, rect_minus_all
from grounds import generate

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class ExteriorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.chdir(ROOT)
        cls.plan = main.make_plan()
        cfg = main.load_grounds()
        cls.g = generate.generate(cfg, cls.plan)
        build.build(cls.plan, main.load_kit())
        cls.data = exterior.generate(cls.plan, build.units, cls.g.terrain)

    def test_every_roofed_room_is_covered(self):
        roofs = [(r["rect"], r["base"]) for r in self.data["roofs"]]
        spires = [s["centre"] for s in self.data["spires"]]
        for r in self.plan.rooms.values():
            if not exterior.built(r) or exterior.open_air(r):
                continue
            above = [o.rect for o in self.plan.rooms.values() if exterior.built(o) and o.storey == r.top_storey + 1 and o.inside is None
                     and o.x0 < r.x1 and r.x0 < o.x1 and o.z0 < r.z1 and r.z0 < o.z1]
            for piece in rect_minus_all(r.rect, above):
                x0, x1, z0, z1 = piece
                cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
                covered = any(rr[0] - 0.4 <= cx <= rr[1] + 0.4 and rr[2] - 0.4 <= cz <= rr[3] + 0.4 for rr, _b in roofs) or \
                    any(abs(s[0] - cx) < 0.1 and abs(s[1] - cz) < 0.1 for s in spires)
                self.assertTrue(covered, f"{r.id}: no roof over {piece}")

    def test_exposed_wall_modules_are_skinned(self):
        quads = self.data["facade"]
        for key, u in build.units.items():
            axis, coord, off, s = key
            for sign in exterior.exposed_sides(self.plan, key):
                for row in range(u["rows"]):
                    if row == 0 and (u["door"] or u["secret"] or u["window"]):
                        continue
                    y0 = s * STOREY + row * 4
                    hit = any(q[0] == axis and q[6] == sign and abs(q[1] - (coord + sign * 0.205)) < 0.01 and q[2] <= off and q[3] >= off + 4
                              and q[4] <= y0 + 0.01 and q[5] >= y0 + 3.99 for q in quads)
                    self.assertTrue(hit, f"wall unit {key} row {row} side {sign} has no facade")

    def test_budgets_hold(self):
        from castle import budgets
        self.assertEqual([str(v) for v in budgets.check(self.plan, build.units, build.placed_nodes)], [])

    def test_far_view_has_every_roofed_room(self):
        n = sum(1 for r in self.plan.rooms.values() if exterior.built(r) and not exterior.open_air(r))
        self.assertEqual(len(self.data["hlod"]), n)


if __name__ == "__main__":
    unittest.main()
