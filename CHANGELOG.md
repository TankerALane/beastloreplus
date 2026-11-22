# Changelog

## Unreleased

- Ability Finder: **Level** box (defaults to your level) with **Can learn now**, **Already learned**
  and **Not yet** toggles, replacing "Only upgrades for me". Beasts above the level are dimmed.
- Ability Finder: the search box placeholder fits the box (full hint on mouse-over).

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
