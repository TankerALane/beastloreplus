# Beast Lore Plus — Claude Code Build Prompt

You are building **Beast Lore Plus**, a World of Warcraft **Forever** addon for hunters, from scratch in this folder. Work straight through all phases without stopping for approval, except where this prompt says to ask (publishing a release). Keep a running `BUILD_LOG.md` of decisions, assumptions and anything you could not verify.

## Project facts

| Item | Value |
|---|---|
| Addon name | Beast Lore Plus (folder/TOC name `BeastLorePlus`) |
| Author | Decoupled Lane Studio |
| Support contact | support@decoupledlane.com |
| License | MIT |
| Local project folder | `D:\Claude Code\beast_lore_plus` (logo JPGs already here) |
| GitHub repo | https://github.com/TankerALane/beastloreplus (public, already created) |
| CurseForge project ID | 1822393 (`CF_API_KEY` repo secret already set) |
| Game client | WoW Forever only. AddOns folder: `E:\Blizzard\World of Warcraft\_forever_\Interface\AddOns` |
| Slash commands | `/beastloreplus` and `/blp` |
| Look | WoW-native (standard Blizzard frame/tooltip styling) with small gold/brown accents from the logo |

## What the addon does

1. **Enhanced Beast Lore.** The hunter still has to cast Beast Lore. The game's Beast Lore display already shows name, level, "Beast", Tameable / Cannot Be Tamed, `Specialization:` and `Diet:`. After those lines, Beast Lore Plus adds a **Pet Abilities** section listing every ability that beast teaches, each with its rank and a status dot:
   - **Green**: this hunter already knows this ability at this rank or higher
   - **Orange**: this hunter knows a lower rank (taming this beast is an upgrade)
   - **Red**: this hunter has not learned this ability at all
   - **Grey "?"**: learned status unknown because this hunter hasn't opened Beast Training yet, plus a one-line hint to open it
   - Beasts that teach nothing show "Teaches no pet abilities". Beasts missing from the database show "No data yet — tame it to help confirm!"
   - Don't add anything for "Cannot Be Tamed" beasts or non-beasts.
2. **Learned-ability tracking per hunter.** Each hunter learns abilities themselves, so status is saved separately for each character.
3. **Ability Finder window.** Search or pick any pet ability and rank to see which beasts teach it, with level range, zone(s) and this hunter's status for that rank. Sort by level and filter by zone, plus a "show only upgrades for me" toggle. Opens from `/blp` and a minimap button.
4. **Community confirmation.** When a hunter tames a beast, record the abilities the new pet arrived with and share them with other Beast Lore Plus users so the data improves over time (rules below).
5. **Options panel** (Interface Options / Settings): show or hide the minimap button, turn community sharing on or off, show or hide the grey unknown rows, and show the beast's NPC ID (debug).

The addon does nothing for non-hunter characters except load quietly. The Finder can still open, but with no status column.

## Phase 0: Investigate the Forever client first

Forever is a Blizzard ruleset, and its API may mix Classic-era and newer features (the Beast Lore display shows "Specialization", which Classic Era never had). Do not assume. Before writing addon code:

1. Find the correct `## Interface:` number. Read the client's build info and the `.toc` files of addons already installed in the Forever AddOns folder. Record the number in `BUILD_LOG.md`.
2. Work out **how the Beast Lore display is drawn**: a GameTooltip shown after the cast, a separate frame, or tooltip data. Check how comparable installed addons hook it, and which events fire around the Beast Lore cast (`UNIT_SPELLCAST_SUCCEEDED`, tooltip post-calls, `TooltipDataProcessor` if it exists). Write down the hook you chose and why.
3. Work out **how Beast Training exposes learned abilities** on Forever: the classic Craft API (`GetNumCrafts`, `GetCraftInfo`, `GetCraftDisplaySkillLine` == "Beast Training", events `CRAFT_SHOW` / `CRAFT_UPDATE`) or something newer. Also check how a pet's own spells and ranks can be read (`GetSpellBookItemName(i, "pet")` or equivalent).
4. Confirm the addon message API (`C_ChatInfo.SendAddonMessage` / `RegisterAddonMessagePrefix`) and which chat types are allowed.

Write a short debug helper (`/blp debug`) that dumps the target's NPC ID, the current Beast Lore frame's lines, and the parsed Beast Training list. Austin can then confirm your findings in game. Where something can only be confirmed in game, write the code defensively (feature-detect, fail silently) and add it to the in-game test checklist.

## Phase 1: Build the beast database with research agents

Use parallel research subagents to gather the data from public sources: Wowhead (Classic/Forever pages if they exist), warcraft.wiki.gg / Wowpedia, and other well-known hunter pet resources. Split the work by ability family (Bite, Claw, Cower, Dash, Dive, Charge, Furious Howl, Lightning Breath, Scorpid Poison, Screech, Prowl, Shell Shield, Thunderstomp, resistances, etc. — build the full list from the sources) so agents don't overlap.

For each ability and rank, collect: the spell ID(s), required pet level, training point cost, and the beasts that teach it (NPC ID, name, level range, zone(s), elite/rare flag).

Rules:
- **Two-source minimum.** An entry is `confirmed` only if two independent sources agree. Single-source entries are `unverified`, and disagreements are `conflict`. Keep every entry, with its confidence and its source URLs.
- Note anything that looks Forever-specific or differs from Classic Era.
- Raw research goes in `tools/data/raw/*.json` (with source URLs). A generator script (`tools/build_data.py`, standard library only) merges it and writes the shipped Lua tables. **Never hand-edit the generated Lua.**
- The generator also writes `tools/data/REVIEW.md`, listing every conflict and unverified entry so Austin can check them.

Shipped data (generated):
- `Data/Abilities.lua`: `BLP.Abilities[abilityKey] = { name, icon, ranks = { [rank] = { spellIds = {...}, petLevel, tp } } }`
- `Data/Beasts.lua`: `BLP.Beasts[npcId] = { name, minLevel, maxLevel, zones = {...}, teaches = { {ability=key, rank=n}, ... }, conf = "confirmed"|"unverified"|"conflict" }`
- Unverified and conflict entries still display, marked with a small "unverified" tag in the Beast Lore section and the Finder.

## Phase 2: Addon code

Suggested layout (adjust if Phase 0 findings call for it):

```
BeastLorePlus/
  BeastLorePlus.toc
  Core.lua            -- init, events, SavedVariables, slash commands, options
  BeastLore.lua       -- detect the Beast Lore cast/display and append the Pet Abilities section
  Training.lua        -- read Beast Training, keep per-character learned ranks
  Finder.lua          -- Ability Finder window
  Community.lua       -- tame capture, addon-message sharing, report storage
  Minimap.lua         -- LibDataBroker + LibDBIcon launcher
  Data/Abilities.lua
  Data/Beasts.lua
  Libs/               -- pulled by the packager via .pkgmeta externals, not committed
  Media/logo.tga      -- converted from beast_lore_plus_logo_512.jpg if the client supports TOC icons
```

- **NPC ID** comes from `UnitGUID("target")`, which must be a creature GUID.
- **Status logic:** known rank ≥ taught rank → green; 0 < known rank < taught rank → orange; none → red; never scanned → grey "?".
- **Saved variables:** `BeastLorePlusDB` (account-wide: options and community reports) and `BeastLorePlusCharDB` (per character: learned ranks, a scanned flag and a last-scan time). Re-scan whenever Beast Training is opened or updated.
- Dots should be small textures or atlas circles, not emoji or font glyphs.
- Show the Pet Abilities section in the order the game lists abilities, or alphabetically if no order is available.

## Phase 3: Community confirmation

- **Capture:** remember the target's NPC ID when the Tame Beast cast starts. On a successful tame, once the new pet exists, read the pet's spells and ranks and record `{npcId, abilities with ranks, client build, addon version}`. Do this only for a fresh tame, never for a stabled or summoned pet.
- **Share:** use an addon-message prefix `BLPlus` (keep it ≤16 characters) and a versioned compact message format. Send to GUILD, and also to a single hidden custom channel (e.g. `BeastLorePlus`) that the addon joins quietly and hides from all chat frames. Throttle with ChatThrottleLib or an equivalent. Sharing respects the options toggle and is on by default.
- **Trust rules:**
  - Bundled data always wins. Community reports never overwrite it.
  - A report fills a gap (a beast missing from the database) only after **3 different senders** agree. Until then it shows as "community: pending (n/3)".
  - A report that disagrees with bundled data is stored as a conflict. It never changes the display.
  - Validate every incoming message (types, sizes, known ability keys, rank ranges), cap stored reports, and drop junk silently.
- **Export:** `/blp export` opens a copyable text box with locally captured tames and conflicts, formatted for a GitHub issue. Austin uses this to fix the bundled data in the next release.

## Phase 4: Packaging and release automation

- TOC: `## Title: Beast Lore Plus`, `## Notes`, `## Author: Decoupled Lane Studio`, `## Version: @project-version@`, `## X-Curse-Project-ID: 1822393`, `## X-License: MIT`, the SavedVariables lines, and the Interface number from Phase 0.
- `.pkgmeta` with externals for LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 and ChatThrottleLib (if used). Ignore `tools/`, `BUILD_LOG.md` and the logo JPGs.
- `.github/workflows/release.yml` using `BigWigsMods/packager@v2`, triggered on `v*` tags, with `CF_API_KEY: ${{ secrets.CF_API_KEY }}` and `GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}`. Check that the packager's game-version flag/TOC handling works for Forever, and record what you found.
- `README.md` with the logo, feature list, the green/orange/red legend, a "help improve the data" section, and the MIT license. Also add `LICENSE` (MIT, Decoupled Lane Studio), `CHANGELOG.md` and `.gitignore`.
- **Git:** initialize the repo in this folder, set `origin` to the GitHub URL, and commit at the end of each phase with clear messages. Pushing commits to `main` is fine. **Ask Austin before creating any `v*` tag**, because a tag publishes to CurseForge.

## Phase 5: Local install and test checklist

- Add `tools/install_local.ps1`, which copies (or junctions) `BeastLorePlus` into the Forever AddOns folder.
- Run `luac -p` or luacheck on every Lua file if available, and run the data generator's own checks: every beast references known abilities and ranks, and there are no duplicate NPC IDs.
- Write `TESTING.md` as an in-game checklist for Austin, covering:
  - Beast Lore on a tameable beast with known, upgrade and unlearned abilities (green, orange and red)
  - Beast Lore before ever opening Beast Training (grey)
  - Cannot Be Tamed beast, and a beast missing from the database
  - Finder search, filters and the upgrades-only toggle
  - Minimap button and options panel
  - A fresh tame captured, then `/blp export`
  - Two accounts or characters to see sharing work
  - A non-hunter character (nothing breaks)

## Finish

When done, give Austin a short summary covering:
- what was built
- the Phase 0 findings (Interface number, Beast Lore hook, Beast Training API)
- the data counts (confirmed, unverified and conflict)
- where `REVIEW.md` and `TESTING.md` are
- a reminder that the release is waiting for his go-ahead to tag `v1.0.0`
