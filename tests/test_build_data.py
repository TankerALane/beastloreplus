"""Tests for tools/build_data.py rules. Run from the repo root:  python tests/test_build_data.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import build_data as bd  # noqa: E402

ABILITIES = {"cower": {"name": "Cower", "ranks": {1: {}, 2: {}, 3: {}, 4: {}}}}


def beast(name, lvl, rank, conf="unverified", ingame=False):
    return {"name": name, "minLevel": lvl, "maxLevel": lvl, "zones": [], "conf": conf,
            "teaches": [{"ability": "cower", "rank": rank, "conf": conf, "ingame": ingame}]}


def run(ingame):
    beasts = {
        1: beast("Low", 5, 1, "confirmed"),
        2: beast("Mid", 15, 2, "confirmed"),
        3: beast("High", 25, 3, "confirmed"),
        4: beast("Odd", 16, 4, "conflict", ingame=ingame),  # below every rank 3 teacher
        5: beast("Top", 35, 4, "confirmed"),
    }
    review = bd.drop_out_of_order(beasts, ABILITIES)
    return beasts, review


failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", label)


beasts, review = run(ingame=False)
check(4 not in beasts, "out-of-order beast from websites is dropped")
check(any("Odd" in r[1] for r in review), "drop is listed for REVIEW.md")
check(5 in beasts and 3 in beasts, "in-order beasts are kept")

beasts, review = run(ingame=True)
check(4 in beasts, "out-of-order beast confirmed in game is kept")
check(not any("Odd" in r[1] for r in review), "in-game beast is not reported as dropped")

print("build_data tests: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
sys.exit(1 if failures else 0)
