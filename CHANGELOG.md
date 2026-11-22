# Changelog

## Unreleased

- Fix: with "Show Beast Lore details without casting Beast Lore" on, the tooltip no longer flickers or
  jumps on mouseover; the lines are added at once instead of a frame later.
- Specialization / Diet added on mouseover: label in yellow, value in white.

## 1.0.2 (2026-11-21)

- Data: in-game tames are now the complete ability list for that beast. Prairie Wolf Alpha teaches only
  Bite 2 (no Furious Howl); Hecklefang Stalker and Sunscale Lashtail teach nothing; Fleeting
  Plainstrider (Cower 1, Dust Cloud 1), Washte Pawne (Lightning Breath 3), Silithid Creeper, Ornery
  Plainstrider and Greater Thunderhawk confirmed in game. Beasts that teach nothing say "No known
  abilities" without the "Tame it to help confirm!" hint.
- Bundled Specialization / Diet for Carrion Bird, Cat, Tallstrider, Wind Serpent and Wolf.
- Ranks are tracked one by one: learning a higher rank does not teach the lower ones. A lower rank you
  don't have shows a new **yellow** dot ("you have a higher rank, but not this one"). Beast Training only
  lists the current pet family's abilities, so this applies once Beast Training has listed that ability;
  until then lower ranks stay green. Green now means "you know this rank".
- Option **Show Beast Lore details without casting Beast Lore** (off by default). When on, hovering a
  beast shows the Beast Lore lines seen the last time you cast Beast Lore on it (Tameable,
  Specialization, Diet), or "Tameable" for beasts in the database, followed by Pet Abilities.
  Specialization and Diet are remembered per creature family, so a beast you never lored shows those
  of its family once you have cast Beast Lore on any beast of that family.
- Specialization and Diet come from three places: your own Beast Lore casts, the bundled
  `Data/Lore.lua` (lines seen in game, added each release), and other Beast Lore Plus users, who share
  what their Beast Lore casts show (used once 2 different hunters agree). Shown in Blizzard's default
  tooltip yellow. Beasts known to be untameable say "Cannot Be Tamed".
- `/blp export` lists the Specialization and Diet seen for each family and each beast.
- Fix: when the game's "You have learned a new spell" message has no rank (Forever sends
  "[Lightning Breath]" for Rank 2), the rank now comes from your pet instead of assuming Rank 1, so the
  dot no longer shows orange until you open Beast Training.

## 1.0.1 (2026-11-21)

- Data: entries where a beast would teach a higher rank than its level allows (below every teacher
  of the rank before) are removed, e.g. Savannah Patriarch as Cower (Rank 4).
- Ability Finder: **Level** box (defaults to your level) with **Can learn now** (hide beasts above the
  level) and **Already learned** (show ranks you know), replacing "Only upgrades for me". Beasts above
  the level are dimmed when shown.
- Ability Finder: click a beast to set a map pin where it spawns, plus a TomTom arrow when TomTom is
  installed. Spawn points come from Questie's database when Questie is installed, otherwise from where
  you last targeted that beast; with neither, the world map opens on its zone.
- Ability Finder: the list no longer looks empty after a filter shortens it while scrolled down.
- Ability Finder: the search box placeholder fits the box (full hint on mouse-over).
- Ability Finder: results are grouped under a header per ability and rank (icon, pet level, TP,
  beast count), with a gap between groups; click a header to show only that rank.
- Ability Finder: rank buttons you already know are greyed out.
- Ability Finder: rank buttons only appear for ranks with beasts under the current filters (e.g.
  "Can learn now" at level 27 hides Claw 5), and abilities with nothing to show are dimmed.
- Ability Finder: sorts **nearest first** by default (Zone column; click again for farthest), the zone
  menu lists zones nearest first, the active sort column shows an arrow, and the sort is remembered.
- Ability Finder: typing a search shrinks the ability list to matching abilities; level, toggles and
  zone only grey abilities out.

## 1.0.0 (2026-11-21)

First release for WoW Forever (1.60.1).

- Beast Lore shows a **Pet Abilities** section: each ability and rank the beast teaches, with a
  green / orange / red / grey status dot for this hunter. Abilities that an in-game tame confirmed
  are tagged "confirmed in game". Beasts with no known abilities say so, with a hint to tame one
  until two hunters have confirmed it.
- Per-character learned-ability tracking from Beast Training (Forever's pet trainer window, including
  the new family abilities) and from "You have learned a new spell" messages, so Beast Training only
  needs opening once per character.
- **Ability Finder** window: search, rank filter, zone filter, sort, "Only upgrades for me".
- Minimap button (LibDBIcon) and options panel.
- **Community confirmation:** fresh tames are recorded and shared (guild + hidden channel); gaps are
  filled after 3 different hunters agree; disagreements with bundled data are kept as conflicts.
- `/blp export` (tames, conflicts, gap reports and confirmations, ready for a GitHub issue),
  `/blp capture` (record the pet you have out), `/blp debug`.
- Bundled database: 32 pet abilities (including Forever's family abilities such as Savage Rend,
  Tendon Rip, Pinch and Web) and 436 beasts, with confirmed / unverified tags.
