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

# In-game tames are complete lists
beasts = {7: {"name": "Wolf", "minLevel": 9, "maxLevel": 10, "zones": [], "elite": False, "rare": False, "conf": "unverified",
              "teaches": [{"ability": "bite", "rank": 2, "conf": "confirmed", "ingame": True},
                          {"ability": "furious_howl", "rank": 1, "conf": "unverified", "ingame": False}]},
          8: {"name": "Hyena", "minLevel": 22, "maxLevel": 23, "zones": [], "elite": False, "rare": False, "conf": "confirmed",
              "teaches": [{"ability": "tendon_rip", "rank": 1, "conf": "confirmed", "ingame": False}]}}
ingame = {7: {"abilities": {"bite": 2}, "name": "Wolf"}, 8: {"abilities": {}, "name": "Hyena"},
          9: {"abilities": {}, "name": "Lizard", "level": 12, "zone": "The Barrens"}}
review = bd.apply_ingame_complete(beasts, ingame)
check([t["ability"] for t in beasts[7]["teaches"]] == ["bite"] and beasts[7]["conf"] == "confirmed",
      "ability the tame did not show is removed; beast confirmed")
check(beasts[8]["teaches"] == [] and 8 in beasts, "tamed with nothing: kept, teaches nothing")
check(beasts[9]["teaches"] == [] and beasts[9]["zones"] == ["The Barrens"], "new beast tamed with nothing is added")
check(any("furious_howl" in r[1] for r in review), "removal listed for REVIEW.md")
bd.drop_out_of_order(beasts, {"bite": {"name": "Bite", "ranks": {2: {}}}})
check(8 in beasts and 9 in beasts, "teaches-nothing beasts survive the level-order pass")

# import_lore: read saved variables and merge Beast Lore lines
import import_lore as il  # noqa: E402

SAVED = '''
BeastLorePlusDB = {
["npcFamily"] = {
[3249] = "Wind Serpent",
},
["loreFamily"] = {
["Wind Serpent"] = {
["lines"] = {
{
"Specialization: Default", -- [1]
1, -- [2]
},
{
"Diet: Fish, Cheese, Bread",
},
},
["npcId"] = 3249,
},
},
["lore"] = {
[3249] = {
["tameable"] = true,
["name"] = "Greater \\"Thunder\\" hawk",
["lines"] = {
{
"Tameable",
0.09, 1, 0.09,
},
{
"Specialization: Default",
},
},
},
[3239] = {
["tameable"] = false,
["lines"] = {
{
"Cannot Be Tamed",
},
},
},
},
}
'''
r = il.LuaReader(SAVED)
r.i = SAVED.index("{")
db = r.value()
data = {"families": {}, "beasts": {}}
il.merge(data, db)
check(data["families"].get("Wind Serpent") == ["Specialization: Default", "Diet: Fish, Cheese, Bread"], "family lines imported")
check(data["beasts"]["3249"] == {"tameable": True, "lines": ["Specialization: Default"], "family": "Wind Serpent",
                                 "name": 'Greater "Thunder" hawk'}, "beast imported with family and name")
check(data["beasts"]["3239"]["tameable"] is False, "untameable beast imported")
check(il.merge(data, db) == 0, "importing again changes nothing")
check('[3249] = { tameable = true, family = "Wind Serpent"' in il.render(data), "Lua output")

print("build_data tests: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
sys.exit(1 if failures else 0)
