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
