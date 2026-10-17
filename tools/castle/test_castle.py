"""Generator tests: python3 -m unittest discover -s tools -p 'test_*.py' (from the project root)."""
import copy
import json
import os
import unittest

from castle import build, circulation, denylist, main, preview, program, rules
from castle.geometry import PlanError

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_program():
    with open(os.path.join(ROOT, main.PROGRAM)) as f:
        return json.load(f)


class CastleGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.chdir(ROOT)
        cls.data = load_program()
        cls.kit = main.load_kit()

    def plan(self, data=None):
        return main.plan_from_data(copy.deepcopy(data or self.data))

    def test_program_passes_every_rule(self):
        violations = rules.validate(self.plan())
        self.assertEqual([str(v) for v in violations], [])

    def test_build_is_deterministic(self):
        _s1, a = build.build(self.plan(), self.kit)
        _s2, b = build.build(self.plan(), self.kit)
        self.assertEqual(a, b)

    def test_overlap_is_refused(self):
        data = copy.deepcopy(self.data)
        data["rooms"].append({"id": "intruder", "rect": [-8, 8, 28, 44], "kind": "room"})
        ids = {v.rule for v in rules.validate(main.plan_from_data(data))}
        self.assertIn("C0", ids)

    def test_unreachable_is_refused(self):
        data = copy.deepcopy(self.data)
        data["rooms"].append({"id": "island", "rect": [200, 216, 200, 216], "kind": "room"})
        self.assertIn("C1", {v.rule for v in rules.validate(main.plan_from_data(data))})

    def test_doorway_onto_a_spiral_step_is_refused(self):
        old = circulation.SPIRAL_LANDING, circulation.SPIRAL_STEPS
        circulation.SPIRAL_LANDING, circulation.SPIRAL_STEPS = 0, 25
        try:
            ids = {v.rule for v in rules.validate(self.plan())}
        finally:
            circulation.SPIRAL_LANDING, circulation.SPIRAL_STEPS = old
        self.assertIn("S10", ids)

    def test_off_grid_room_is_a_plan_error(self):
        data = copy.deepcopy(self.data)
        data["rooms"].append({"id": "odd", "rect": [1, 9, 0, 8]})
        with self.assertRaises(PlanError):
            main.plan_from_data(data)

    def test_placement_outside_its_room_is_refused(self):
        p = self.plan()
        build.reset(p, self.kit)
        r = p.rooms["library"]
        with self.assertRaises(AssertionError):
            e = {"id": "x", "kind": "plaque", "at": [100, 0]}
            build.check_inside(r, e, build.placement_point(r, e)[0])

    def test_door_slot(self):
        p = self.plan()
        build.reset(p, self.kit)
        r = p.rooms["entrance_hall"]
        (x, _y, z), _yaw = build.placement_point(r, {"id": "x", "kind": "plaque", "door": "grounds", "along": 3, "inset": 1})
        self.assertAlmostEqual(z, r.z1 - 1)
        self.assertTrue(r.x0 < x < r.x1)

    def test_generated_texts_are_filled_in(self):
        # Every placeholder is substituted, and the Polish never puts a room's
        # nominative name after "sali" (it would need a declined form).
        for key, en, pl in self.plan().generated_names:
            for text in (en, pl):
                self.assertNotIn("{", text, key)
            self.assertNotIn("sali Sala", pl, key)

    def test_denylist(self):
        self.assertEqual(denylist.scan(ROOT), [])
        fake = {denylist.h("zzforbiddenzz")}
        self.assertEqual(denylist.scan_text("a ZZForbiddenZZ room", fake), {"zzforbiddenzz"})
        self.assertEqual(denylist.scan_text("zz forbidden zz", {denylist.h("forbiddenzz")}), {"forbiddenzz"})

    def test_preview_renders_every_storey(self):
        p = self.plan()
        for s in preview.storeys(p):
            self.assertIn("</svg>", preview.svg_storey(p, s))


if __name__ == "__main__":
    unittest.main()
