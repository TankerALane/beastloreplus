<p align="center"><img src="beast_lore_plus_logo_512.jpg" alt="Beast Lore Plus" width="200"></p>

# Beast Lore Plus

**Know what a beast will teach you before you tame it.** A hunter addon for **World of Warcraft Forever**.

Cast **Beast Lore** on a tameable beast as usual. Under the game's own lines (Tameable,
Specialization, Diet) Beast Lore Plus adds a **Pet Abilities** section: every ability that beast
teaches, with its rank and a dot that says whether you need it.

## Features

- **Enhanced Beast Lore.** Every ability and rank the beast teaches, with a status dot.
  Beasts with no known abilities say "No known abilities", with a hint to tame one and help
  confirm until 2 different hunters have confirmed it teaches nothing. Nothing is added for beasts
  that cannot be tamed.
- **Learned-ability tracking per character.** Open Beast Training once and the addon remembers which
  abilities and ranks that hunter knows. It updates whenever Beast Training opens or you learn a rank.
- **Ability Finder** (`/blp` or the minimap button). Pick any pet ability and rank to see which
  beasts teach it, with level range, zone and your status. Search, sort by level/name/zone, filter
  by zone, and tick **Only upgrades for me**.
- **Community confirmation.** When you tame a beast, the abilities your new pet arrived with are
  recorded and shared with other Beast Lore Plus users (guild + a hidden channel), so the data gets
  better over time. See below.
- **Options** (Esc › Options › AddOns › Beast Lore Plus, or `/blp options`): minimap button,
  community sharing, grey "?" rows, and NPC IDs (debug).

Non-hunters can still open the Finder; it just has no status column.

## Legend

| Dot | Meaning |
|---|---|
| 🟢 Green | You already know this ability at this rank or higher |
| 🟠 Orange | You know a lower rank — taming this beast is an **upgrade** |
| 🔴 Red | You have not learned this ability at all |
| ⚪ Grey "?" | Unknown — open **Beast Training** once on this character |

Entries tagged *unverified* come from a single source, or sources disagree. They still show, so you
can check them in game.

## Commands

| Command | What it does |
|---|---|
| `/blp` or `/beastloreplus` | Open the Ability Finder |
| `/blp options` | Open the options |
| `/blp minimap` | Show or hide the minimap button |
| `/blp export` | Copy your captured tames and data conflicts, ready for a GitHub issue |
| `/blp capture` | Record the pet you have out (target a wild beast of the same kind first) |
| `/blp debug` | Show the target's NPC ID, the last Beast Lore lines and your Beast Training scan |

## Help improve the data

The bundled database was built from public sources (Petopia, Wowhead, warcraft.wiki.gg, Warcraft
Tavern and others), with every entry needing two independent sources to count as confirmed. Forever
changed hunter pets (new families, new family abilities, new beasts), so some entries are still
unverified or missing. You can help:

1. **Just tame beasts.** Your capture is shared automatically (you can turn sharing off in the
   options). A beast missing from the database is filled in for everyone once **3 different hunters**
   report the same abilities ("community: pending 1/3" until then). Community reports never
   overwrite the bundled data.
2. **Send an export.** Type `/blp export`, copy the text, and paste it into a
   [new GitHub issue](https://github.com/TankerALane/beastloreplus/issues/new). Each release folds
   confirmed reports into the bundled data.

Shared messages contain only the beast's NPC ID and name, the abilities and ranks, your client build
and the addon version.

## Support

support@decoupledlane.com · [Issues](https://github.com/TankerALane/beastloreplus/issues)

## License

MIT © Decoupled Lane Studio. See [LICENSE](LICENSE).

---

### For developers

- Data: raw research lives in `tools/data/raw/*.json`, and tames verified in game (from `/blp export`
  issues) go in `tools/data/ingame_tames.json` (source `in-game`, most trusted). `python tools/build_data.py` generates
  `Data/Abilities.lua`, `Data/Beasts.lua` and `tools/data/REVIEW.md`. Never edit the generated Lua.
- Tests: `luajit tests/run_tests.lua`. Lint: `luajit tools/lint.lua` (luacheck via its Lua API).
- Local install: `powershell -ExecutionPolicy Bypass -File tools\install_local.ps1` (add `-Junction`
  to link instead of copy).
- Releases: pushing a `v*` tag runs the BigWigs packager (CurseForge project 1822393).
