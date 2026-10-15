"""Castle rules as validators (ids from docs/castle-generation.md, section 3).

Each rule is a function plan -> list of messages. validate() runs them all and
returns Violations; the generator refuses to write anything while one remains.
"""
from collections import deque

from .geometry import overlaps

RULES = []


class Violation:
    def __init__(self, rule, where, message):
        self.rule = rule; self.where = where; self.message = message

    def __str__(self):
        return f"[{self.rule}] {self.where}: {self.message}"


def rule(rule_id, title):
    def deco(fn):
        RULES.append((rule_id, title, fn))
        return fn
    return deco


def validate(plan, only=None):
    out = []
    for rule_id, _title, fn in RULES:
        if only and rule_id not in only:
            continue
        for where, message in fn(plan):
            out.append(Violation(rule_id, where, message))
    return out


def reachable(plan, root, allow=("door", "secret", "stair"), blocked=()):
    adj = plan.adjacency(allow)
    seen = {root}; queue = deque([root])
    while queue:
        n = queue.popleft()
        for m in adj.get(n, ()):
            if m not in seen and m not in blocked:
                seen.add(m); queue.append(m)
    return seen


@rule("C0", "rooms on the same storey never overlap")
def no_overlap(plan):
    ids = list(plan.rooms)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            A, B = plan.rooms[a], plan.rooms[b]
            if A.inside == b or B.inside == a:
                continue
            if set(A.storeys()) & set(B.storeys()) and overlaps(A, B):
                yield a, f"overlaps {b}"


@rule("C1", "every room is reachable from the grounds")
def all_reachable(plan):
    seen = reachable(plan, "grounds")
    for r in plan.rooms:
        if r not in seen:
            yield r, "unreachable"
