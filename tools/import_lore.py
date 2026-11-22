"""Bundle the Beast Lore lines (Specialization, Diet) seen in game into Data/Lore.lua.

Usage (from the repo root):
  python tools/import_lore.py "<WoW>/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/BeastLorePlus.lua" [...]
      Reads BeastLorePlusDB from each saved variables file, merges what it saw into
      tools/data/ingame_lore.json, and regenerates Data/Lore.lua.
  python tools/import_lore.py
      Regenerates Data/Lore.lua from tools/data/ingame_lore.json only.
  python tools/import_lore.py --check
      Fails if Data/Lore.lua is out of date with tools/data/ingame_lore.json (used by CI).

Only lines read from the game are bundled (Beast Lore casts, and the family of tamed pets), so
everything here counts as confirmed in game. Newer values replace older ones.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_PATH = os.path.join(ROOT, "tools", "data", "ingame_lore.json")
LUA_PATH = os.path.join(ROOT, "Data", "Lore.lua")

FAMILY_LINE = re.compile(r"^(specialization|diet):", re.I)
TAMEABLE_TEXT = "tameable"
NOT_TAMEABLE_TEXT = "cannot be tamed"


# --- A small reader for WoW SavedVariables (Lua table constructors) --------------------------
class LuaReader:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def ws(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n,;":
                self.i += 1
            elif s.startswith("--", self.i):
                j = s.find("\n", self.i)
                self.i = len(s) if j < 0 else j + 1
            else:
                break

    def value(self):
        self.ws()
        s, c = self.s, self.s[self.i]
        if c == "{":
            return self.table()
        if c == '"':
            return self.string()
        m = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?").match(s, self.i)
        if m and m.group(0):
            self.i = m.end()
            t = m.group(0)
            return float(t) if any(ch in t for ch in ".eE") else int(t)
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if s.startswith(word, self.i):
                self.i += len(word)
                return val
        raise ValueError("unexpected %r at %d" % (s[self.i:self.i + 20], self.i))

    def string(self):
        s = self.s
        self.i += 1
        out = []
        while s[self.i] != '"':
            c = s[self.i]
            if c == "\\":
                n = s[self.i + 1]
                if n.isdigit():
                    m = re.compile(r"\d{1,3}").match(s, self.i + 1)
                    out.append(chr(int(m.group(0))))
                    self.i = m.end()
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(n, n))
                self.i += 2
            else:
                out.append(c)
                self.i += 1
        self.i += 1
        return "".join(out)

    def table(self):
        self.i += 1
        result, n = {}, 1
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return result
            if self.s[self.i] == "[":
                self.i += 1
                key = self.value()
                self.ws()
                assert self.s[self.i] == "]"
                self.i += 1
                self.ws()
                assert self.s[self.i] == "="
                self.i += 1
                result[key] = self.value()
            else:
                m = re.compile(r"([A-Za-z_]\w*)\s*=").match(self.s, self.i)
                if m:
                    self.i = m.end()
                    result[m.group(1)] = self.value()
                else:
                    result[n] = self.value()
                    n += 1


def read_saved(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^BeastLorePlusDB\s*=\s*", text, re.M)
    if not m:
        return {}
    r = LuaReader(text)
    r.i = m.end()
    return r.value() or {}


def as_list(t):
    if isinstance(t, list):
        return t
    if isinstance(t, dict):
        return [t[k] for k in sorted(k for k in t if isinstance(k, int))]
    return []


def line_texts(lines):
    out = []
    for line in as_list(lines):
        text = as_list(line)[0] if as_list(line) else None
        if isinstance(text, str) and text.strip():
            out.append(text.strip())
    return out


# --- Merge ------------------------------------------------------------------------------------
def load_json():
    if os.path.exists(JSON_PATH):
        return json.load(open(JSON_PATH, encoding="utf-8"))
    return {"families": {}, "beasts": {}}


def merge(data, db):
    families, beasts = data.setdefault("families", {}), data.setdefault("beasts", {})
    changed = 0
    npc_family = {int(k): v for k, v in (db.get("npcFamily") or {}).items() if isinstance(v, str)}
    for tame in as_list((db.get("community") or {}).get("tames")):
        if isinstance(tame, dict) and tame.get("npcId") and isinstance(tame.get("family"), str):
            npc_family[int(tame["npcId"])] = tame["family"]
    for family, entry in (db.get("loreFamily") or {}).items():
        lines = [t for t in line_texts((entry or {}).get("lines")) if FAMILY_LINE.match(t)]
        if isinstance(family, str) and lines and families.get(family) != lines:
            families[family] = lines
            changed += 1
    for npc, entry in (db.get("lore") or {}).items():
        texts = line_texts((entry or {}).get("lines"))
        lows = [t.lower() for t in texts]
        if TAMEABLE_TEXT in lows:
            tameable = True
        elif NOT_TAMEABLE_TEXT in lows:
            tameable = False
        else:
            continue
        rec = {"tameable": tameable, "lines": [t for t in texts if FAMILY_LINE.match(t)]}
        name = (entry or {}).get("name")
        if isinstance(name, str) and name:
            rec["name"] = name
        family = npc_family.get(int(npc))
        if family:
            rec["family"] = family
        key = str(int(npc))
        old = beasts.get(key, {})
        for k in ("name", "family"):  # keep what an older import knew
            if k not in rec and k in old:
                rec[k] = old[k]
        if old != rec:
            beasts[key] = rec
            changed += 1
    for npc, family in npc_family.items():
        key = str(npc)
        if key in beasts and beasts[key].get("family") != family:
            beasts[key]["family"] = family
            changed += 1
        elif key not in beasts:
            beasts[key] = {"tameable": True, "lines": [], "family": family}
            changed += 1
    return changed


# --- Lua output ---------------------------------------------------------------------------------
def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(data):
    out = [
        "-- GENERATED by tools/import_lore.py from tools/data/ingame_lore.json.",
        "-- Beast Lore lines seen in game; do not edit by hand.",
        "",
        "local _, BLP = ...",
        "BLP.LoreData = {",
        "  -- creature family -> Specialization / Diet lines",
        "  families = {",
    ]
    for family in sorted(data.get("families", {})):
        lines = ", ".join(lua_str(t) for t in data["families"][family])
        out.append("    [%s] = { %s }," % (lua_str(family), lines))
    out.append("  },")
    out.append("  -- npcId -> { tameable, family, lines }")
    out.append("  beasts = {")
    beasts = data.get("beasts", {})
    for key in sorted(beasts, key=int):
        b = beasts[key]
        parts = ["tameable = %s" % ("true" if b.get("tameable") else "false")]
        if b.get("family"):
            parts.append("family = %s" % lua_str(b["family"]))
        if b.get("lines"):
            parts.append("lines = { %s }" % ", ".join(lua_str(t) for t in b["lines"]))
        comment = ("  -- " + b["name"]) if b.get("name") else ""
        out.append("    [%d] = { %s },%s" % (int(key), ", ".join(parts), comment))
    out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if not a.startswith("--")]
    data = load_json()
    if paths and not check:
        total = 0
        for p in paths:
            total += merge(data, read_saved(p))
        os.makedirs(os.path.dirname(JSON_PATH), exist_ok=True)
        with open(JSON_PATH, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        print("imported %d change(s): %d families, %d beasts" % (
            total, len(data.get("families", {})), len(data.get("beasts", {}))))
    lua = render(data)
    if check:
        current = open(LUA_PATH, encoding="utf-8").read() if os.path.exists(LUA_PATH) else ""
        if current != lua:
            print("Data/Lore.lua is out of date: run python tools/import_lore.py")
            return 1
        print("Data/Lore.lua is up to date")
        return 0
    with open(LUA_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
