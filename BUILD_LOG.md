# Beast Lore Plus — build log

Running record of decisions, assumptions and anything not verified. Newest phase last.
"Verified" below means seen on disk, in an installed Forever addon, or in a sibling project's
in-game probe report. "In game" means it still needs Austin to confirm (see `TESTING.md`).

## Phase 0 — Forever client investigation (2026-11-21)

### Client and Interface number

- `E:\Blizzard\World of Warcraft\.build.info`: product `wowf`, version **1.60.1.71037**.
  `_forever_\.flavor.info` says `wowf`.
- Installed Forever addons declare **`## Interface: 16001`** (Questie_Forever, Leatrix_Plus,
  LFGForever, RareScanner, WhatsTraining, Tanksign, FellowshipLedger_Forever, Plater, ...).
- The project constant is `WOW_PROJECT_CAMELOT` (Atlas, InFlight, Auctionator); TOC load
  conditions use the game type `camelot`. Packager suffix is `_Camelot.toc` (not `_Forever.toc`).
- **Decision:** a single `BeastLorePlus.toc` with `## Interface: 16001` (Forever only).

### Engine: modern, with secret values

- Forever runs on the modern (12.x) engine with Classic rules: `issecretvalue`, `C_Secrets`,
  `C_TooltipInfo`, `TooltipDataProcessor`, `Settings.*`, `C_ChatInfo.*` exist.
- Tanksign's in-game probe (`D:\Claude Code\tanksign\docs\verify-reports\forever-2026-11-06-probe1.txt`):
  in combat `UnitGUID`, `UnitName`, `UnitCreatureType` of hostile NPCs are **plain**; health is
  **secret**. GUID format `Creature-0-6825-1-57-3127-C230CEB5A4` (NPC ID = 6th field).
- **Decision:** every value read from tooltips or unit APIs is passed through an
  `issecretvalue` guard; anything secret is skipped silently.

### Beast Lore display — how it is drawn

- Austin's screenshots (`_forever_\Screenshots\WoWScrnShot_112126_1600*.jpg`): after the cast the
  display is the **GameTooltip** in its default anchor (bottom right), with the unit health bar,
  lines: name, `Level 8`, `Beast`, `Tameable` (green) / `Cannot Be Tamed` (red),
  `Specialization: Default`, `Diet: Cheese, Fungus, Fruit`. This is the retail-style Beast Lore
  (unit tooltip with extra server-provided lines), not the old Classic frame.
- **Hook chosen:** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ...)`
  (used by several installed Forever addons; FellowshipLedger's verify report marks it PASS on
  Forever). In the post-call the addon reads the tooltip's lines; if one equals "Tameable" it
  appends the Pet Abilities section. "Cannot Be Tamed" and non-beasts get nothing.
  - Why: works whether the client shows the Beast Lore tooltip right after the cast or on
    mouse-over while the effect lasts, and it needs no knowledge of a private frame.
  - Fallback if `TooltipDataProcessor` is missing: `GameTooltip:HookScript("OnTooltipSetUnit")`.
  - Safety net: if "Tameable" is not in the lines at post-call time (lines added later by Lua),
    a one-frame-later re-check runs while the same unit is still shown.
- `UNIT_SPELLCAST_SUCCEEDED` for Beast Lore (spell 1462) is also watched, only to record when
  the cast happened for `/blp debug`. NPC ID comes from the tooltip data's `guid`, or
  `UnitGUID` of the tooltip unit / target.
- In game: the exact line text and line types (captured by `/blp debug`), non-English clients.

### Beast Training — learned abilities

- **Forever removed the Craft API for Beast Training.** WhatsTraining
  (`AddOns\WhatsTraining\Classes\HunterPets.lua`) says so and checks
  `C_EventUtils.IsEventValid("CRAFT_UPDATE")`. On Forever Beast Training opens the **trainer
  frame**: `C_Trainer.GetTrainerType() == Enum.TrainerType.Pet`, events `TRAINER_SHOW` /
  `TRAINER_UPDATE`, services via `GetNumTrainerServices()`, and
  `C_TooltipInfo.GetTrainerService(i).id` gives the **pet spell ID** of each listed ability.
- WhatsTraining's saved data for Austin's hunter Tarahawk lists IDs such as 17255 (Bite R2),
  24423 (Screech R1), 4187-4190 (Great Stamina), 24545/24549-24551 (Natural Armor), i.e. the
  **Classic Era spell IDs**. The trainer lists abilities the hunter knows; WhatsTraining uses
  presence only ("service status seems unreliable right after learning").
- **Decision:** `Training.lua` scans on `TRAINER_SHOW`/`TRAINER_UPDATE` when the trainer type is
  Pet; maps spell ID -> (ability, rank) via `Data/Abilities.lua`; falls back to
  `GetTrainerServiceInfo(i)` name + "Rank N" text. Known ranks are merged (max), never lowered,
  so a filtered trainer list cannot erase knowledge. The classic Craft path is kept behind the
  `CRAFT_UPDATE` feature test in case a client build brings it back.
- Also parses `CHAT_MSG_SYSTEM` "You have learned a new spell" (Forever sends a spell link) to
  pick up ranks learned in the field.
- Pet spells: `C_SpellBook.HasPetSpells()` + `C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)`,
  falling back to `HasPetSpells()` + `GetSpellBookItemName(i, "pet")`. In game: which one exists.

### Addon messages

- `C_ChatInfo.SendAddonMessage` / `RegisterAddonMessagePrefix` exist on Forever
  (FellowshipLedger verify: PASS). `Enum.SendAddonMessageResult` names (retail): Success,
  AddonMessageThrottle, InvalidChatType, NotInGuild, InvalidChannel, ChannelThrottle,
  AddOnMessageLockdown, ... — handled by name. 255 bytes is the measured whisper limit.
- Chat types used: `GUILD` and `CHANNEL` (custom channel `BeastLorePlus`). In game: that
  `CHANNEL` addon messages are allowed on Forever (they are on retail) and that the hidden channel
  join works; both are feature-detected and fail silently.
- **Decision:** no ChatThrottleLib. Messages are tiny and rare (one per tame), so a small internal
  queue (one send per 2 s, back-off on throttle results) is "an equivalent", and avoids a library
  that must hook the modern send API.

### Options, minimap, icons

- `Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory` work on Forever
  (Tanksign, FellowshipLedger, Leatrix_Plus). Used, with `InterfaceOptions_AddCategory` fallback.
- `## IconTexture:` works on Forever (Tanksign ships one). Logo converted with ffmpeg to
  `Media/logo.tga` (64×64, uncompressed 24-bit). `Media/dot.tga` (32×32 white circle with alpha)
  is generated and tinted per status, used as an inline texture (`|T...|t`).
- Dropdowns: `UIDropDownMenu` is legacy on the 12.x engine; the Finder uses
  `MenuUtil.CreateContextMenu` when present and otherwise cycles values on click.

### Packaging (researched by a subagent from packager source)

- BigWigs packager `release.sh` (master == `v2`) maps `16???` to game type **forever**, version
  string 1.60.1, CurseForge game version type 88568, name "1.60.1" (falls back to the nearest
  Forever version, never a Classic one). PR #202 "Add WoW Forever support".
- A root-level `BeastLorePlus.toc` is fine. `_Forever.toc` is not a recognised suffix
  (`_Camelot.toc` is); not needed here.
- **Decision (layout):** the addon files live at the repository root (packager standard), not in
  a `BeastLorePlus/` subfolder. `.pkgmeta` ignores `tools/`, `docs/`, the logo JPGs, etc.
  Sibling projects avoided the packager only because they kept the addon in a subfolder.
- WoWInterface upload skips Forever (packager prints a warning); not used here anyway.

## Phase 1 — Beast database (2026-11-21)

### How it was gathered

- 13 research subagents in parallel, split by ability (Bite 1-4, Bite 5-8, Claw 1-4, Claw 5-8,
  Cower/Dash/Prowl, Dive/Screech, Charge/Howl/Stomp/Shell, Lightning Breath/Scorpid Poison,
  trainer abilities + completeness, packager check, Forever family abilities, and a Forever
  cross-check of the 13 Classic abilities). Raw observations in `tools/data/raw/*.json` (one record
  per source, with URLs; format in `tools/data/RAW_SCHEMA.md`). Research notes: `raw/_findings.md`.
- Sources that worked: **Petopia** Classic and Forever sections (main beast lists, NPC IDs, pet
  level, TP), **Warcraft Tavern** (per-beast "Skills When Tamed"), **Wowhead** spell pages and the
  `nether.wowhead.com` tooltip endpoint (spell IDs, levels, elite/rare, zones), warcraft.wiki.gg
  (scraps), Ten Ton Hammer (TBC-era names/zones), mmonster.co and classicdb (rank data).
- Failed or thin: Wowhead full pages (403 / bot check; its "Taught by NPC" listviews could not be
  read, and Wowhead has no such lists for pet abilities anyway), Wowpedia (Cloudflare),
  warcraft.wiki.gg (no per-rank beast lists).

### Generator rules (`tools/build_data.py`, `tools/data/sources.json`)

- confirmed = 2+ different sites agree on a beast's rank; unverified = one site; conflict = sites
  disagree (highest-priority site's value ships). Beast `conf` = worst of what it teaches.
- Petopia Classic and Petopia Forever are one site; within a site the Forever page wins.
- Wowhead's beast->rank data for Dive, Screech, Scorpid Poison and Lightning Breath came from a 2019
  user comment that copies Petopia; it counts as Petopia (`beastRankCopies`).
- `"foreverComplete": true` files hold Petopia's complete Forever list for an ability; a beast only
  Classic sources list for it becomes a conflict ("not on Petopia's Forever list").
- Spell-ID sets agree when they share an ID (some sources add the "teach" spell).
- Zone suffixes "(Dungeon)/(Raid)" are stripped; names without an NPC ID are matched by name or
  reported as unresolved (2: Undead Wolf, Witherbark Broodguard; not shipped).
- **Doubt not resolved by the rules:** Warcraft Tavern agrees with Petopia almost perfectly and may
  share its origin. It is counted as an independent source, so many "confirmed" entries rest on
  Petopia + Warcraft Tavern. Austin may want to treat those as softer than Wowhead-backed ones.

### Counts (generator output)

- 32 abilities (155 ranks): 13 Classic beast-taught, 8 trainer-only, 11 Forever family abilities.
- 436 beasts: **258 confirmed, 166 unverified, 12 conflict**; beast/ability pairs 316 / 185 / 13.
- Every conflict and unverified entry is in `tools/data/REVIEW.md`.

### Forever differences found (important)

- Forever redesigned pet families (Blizzard news 24301515): Owl -> Bird of Prey, new Fox family,
  every family can learn Bite or Claw and Dive or Dash, each family has one unique ability learned
  only by taming: Sonic Blast (Bat), Swipe (Bear), Mine! (Bird of Prey), Pinch (Crab), Dismember
  (Crocolisk), Tendon Rip (Hyena), Savage Rend (Raptor), Web (Spider), Dust Cloud (Tallstrider),
  Trickster's Dance (Fox). Lava Breath (Core Hound, 2 ranks) is listed but no tameable source is
  known. Family-ability data is from Petopia Forever (beta data) + Wowhead tooltips, so beast->rank
  is mostly **unverified**; several ranks have no known teacher yet.
- Screech is "Demoralizing Screech" (Carrion Bird) on Forever; Petopia Forever still lists some
  bat/owl teachers. Shown with the client's own spell name.
- New beasts and zones (Zephras Isle, Riverglades), Thunderstomp rank 4 (Forever-only, "0 TP",
  no teacher), Furious Howl reworked, Savannah Patriarch moved from Cower 2 to Cower 4.
- Hunter-side "teach" spell IDs for family abilities are not in the data; `Training.lua` falls back
  to name + "Rank N" for those. In game: confirm the trainer service IDs (`/blp debug`).

## Phase 2-3 — Addon code and community (2026-11-21)

- Root layout as decided in Phase 0. Files: Core, Training, BeastLore, Community, Debug, Finder,
  Minimap, Options, Data/*. Globals: only the two SavedVariables and the slash command globals,
  plus the named frames `BeastLorePlusFinder` / `BeastLorePlusCopyFrame` (for Esc to close).
- Missing beasts show **"No known abilities"** plus a grey "Tame it to help confirm!" hint
  (Austin's wording, 2026-11-21) instead of the prompt's "No data yet" line.
- Status dots are `Media/dot.tga` tinted per status and `Media/unknown.tga` (grey "?"), as inline
  textures. Pet Abilities rows are sorted alphabetically (Beast Lore on Forever lists no abilities).
- Community message `B1|npcId|build|version|sig|name`, sig = sorted `key:rank` list or `-`.
  Validation: version, numeric ranges, known non-trainer ability keys, rank ranges, canonical order,
  no duplicates, <= 250 bytes; 10 messages/min/sender; caps 400 NPCs, 4 ability sets per NPC,
  10 senders per set, 200 own tames. Own tames re-shared (max 5) once a day.
- A tame whose pet has an **active spell the addon cannot map** (e.g. a Forever ability missing
  from the data) is kept for `/blp export` but not counted or shared, so incomplete lists never
  spread. Pet GUID creature ID must match the Tame Beast target (stabled/summoned pets never count).
- Sharing off = no sending and no channel; GUILD reports are still received and stored.
- Non-hunters: Beast Lore hook, training scan, capture and channel are all skipped; reports from
  others are still received so the Finder can show community-confirmed beasts.

## Phase 4 — Packaging (2026-11-21)

- `.pkgmeta`: externals LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 (canonical
  CurseForge SVN / GitHub URLs, not tried yet: the first tagged build will show if they resolve).
  No ChatThrottleLib (see Phase 0). Ignores tools, tests, docs, BUILD_LOG, TESTING, prompt, JPGs.
- TOC loads `CallbackHandler-1.0.lua` directly (no XML), so local installs that copy single files
  from other addons and the packaged layout are the same.
- `release.yml`: on `v*` tags, runs the data check and LuaJIT tests, then `BigWigsMods/packager@v2`
  with `CF_API_KEY` and `GITHUB_OAUTH`. No `-g` flag needed (16001 -> forever -> CurseForge 1.60.1).

## Phase 5 — Checks and local install (2026-11-21)

- `luajit tools/lint.lua`: luacheck through its Lua API (the luacheck CLI here lacks
  LuaFileSystem). 0 warnings on all addon files.
- `luajit tests/run_tests.lua`: GUID parsing, status logic, spell resolution, codec, junk messages,
  trust rules, caps and generated-data integrity (2054 checks pass).
- `python tools/build_data.py --check`: unknown abilities/ranks, duplicate IDs, spell IDs shared
  between abilities. Passes.
- `tools/install_local.ps1` installed the addon into the Forever AddOns folder, with libraries
  copied from Auctionator/RareScanner. Not yet loaded in game: see `TESTING.md`.

## Fixes from Austin's first in-game tests (2026-11-21)

- **Pet GUIDs do not carry the tamed beast's creature ID on Forever.** Every hunter pet GUID uses
  the generic creature ID **165189** ("Hunter Pet", as on retail). The original capture compared
  the pet's creature ID with the Tame Beast target, so every real tame was discarded as "a
  different pet". Now: the beast comes from the Tame Beast target, and the pet counts if it is
  *new* (GUID differs from the pet out before the cast). Tame Beast is detected from
  SENT/START/CHANNEL_START/SUCCEEDED by spell ID 1515 or name; INTERRUPTED/FAILED disarm (FAILED
  is ignored while a cast is still running).
- Pet spellbook includes pet commands and stances (Attack, Follow, Passive, ...): skipped
  (`Enum.SpellBookItemType.PetAction`, or subtext "Pet Command"/"Pet Stance").
- Beast Training scan **works** on Forever (Tarahawk: scanned, Bite 2, Growl 3, Great Stamina 4...).
- `/blp capture` records the pet you have out, using your current target (or the last Tame Beast
  target) for the NPC ID. Manual captures are export/local only, never shared.
- Unverified entries that a tame matched show "confirmed in game" (display only).
- Diagnostics (tame events, trainer scans with unmatched entries, learned-spell messages) are
  saved in `BeastLorePlusDB.debugLog` so they can be read from disk after /reload.
- Confirmed in game: Sunscale Screecher (3255) teaches Savage Rend 1; a Barrens hyena teaches
  Tendon Rip 1.
- Learn messages on Forever link the **hunter's** copy of a spell (Tendon Rip 1 = 1265043; the pet's is 1265038) with the name "Tendon Rip (Rank 1)". The resolver now parses "(Rank N)", matches by name when the ID is unknown, and caches the hunter-side ID. Automatic tame capture confirmed working (16:55, NPC 4127, tendon_rip:1).
- Confirmed in game (16:56): Beast Training is trainer type 3 (= Enum.TrainerType.Pet), 18 services, all matched; it lists family abilities (Tendon Rip saved as rank 1). Learn messages now update ranks without reopening Beast Training.
- **In-game source added:** `tools/data/ingame_tames.json` holds tames verified with `/blp export`; each counts as source `in-game` (highest priority, levels not used). First two: Sunscale Screecher 3255 (Savage Rend 1), Hecklefang Hyena 4127 (Tendon Rip 1), both now confirmed. Counts: 260 confirmed, 164 unverified, 12 conflict.
