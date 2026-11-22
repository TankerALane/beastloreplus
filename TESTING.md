# In-game test checklist (WoW Forever)

Some facts could only be worked out from files and other addons, not in game. These are marked
**[confirms Phase 0]** below. If a step fails, run `/blp debug`, click **Select all**, copy it, and
send it along with what you saw.

## Setup

1. In PowerShell from the repo folder:
   `powershell -ExecutionPolicy Bypass -File tools\install_local.ps1`
   (fills `Libs\` from libraries already installed in other addons, then copies the addon into
   `_forever_\Interface\AddOns\BeastLorePlus`). Use `-Junction` to link instead of copy.
2. Start Forever, check **Beast Lore Plus** is enabled in the AddOns list (logo icon shows), log in
   on a hunter. No Lua errors should appear (`/console scriptErrors 1` to see them).

## 1. Beast Lore before opening Beast Training (grey)

Use a hunter that has **never opened Beast Training** since installing (or a fresh character).

- [ ] Cast Beast Lore on a **tameable** beast that is in the database. The tooltip shows the game's
      lines, then a gold **Pet Abilities** header, then each ability with a grey "?" texture and
      "Open Beast Training to see which of these you know." **[confirms Phase 0: the Unit tooltip
      hook sees the Beast Lore lines]**
- [ ] `/blp debug` → "Last Beast Lore display seen" lists the tooltip lines; note the line types.
- [ ] Options › untick "Show grey ? rows" → the grey rows disappear, the hint stays. Tick it again.
- [ ] Default: hovering a beast without casting Beast Lore shows no Pet Abilities.
- [ ] Options › tick "Show Beast Lore details without casting Beast Lore" → hovering the beast you just
      lored shows Tameable / Specialization / Diet and Pet Abilities; a database beast you never lored
      shows "Tameable" and Pet Abilities, plus Specialization / Diet if you have lored another beast of
      its family; humanoids show nothing extra. `/blp export` lists "Beast Lore by family". Untick it again.

## 2. Beast Training scan, then green / orange / red

- [ ] Open **Beast Training** (spellbook). `/blp debug` → "Beast Training" shows `scanned=true` and
      the abilities/ranks you know, each matched (no "UNMATCHED"). **[confirms Phase 0: Pet trainer
      type + C_TooltipInfo.GetTrainerService ids]**
- [ ] Beast Lore on a beast that teaches a rank you **know** (or lower) → **green** dot.
- [ ] Beast Lore on a beast that teaches a **higher** rank of something you know → **orange** dot.
- [ ] A rank **below** your highest that you never learned: **green** until Beast Training has listed that
      ability (open it with a pet of a family that uses it), then **yellow**. `/blp debug` shows
      "has 1,3, checked in Beast Training" per ability; the "trainer:" log line lists every rank read.
- [ ] Beast Lore on a beast that teaches an ability you **don't have** → **red** dot.
- [ ] Learn a new rank from a pet in the field; the "You have learned..." message updates the
      status without reopening Beast Training.

## 3. Cannot Be Tamed, missing beast, non-beasts

- [ ] Beast Lore on a **Cannot Be Tamed** beast (e.g. Kodo Calf in Mulgore) → nothing added.
- [ ] Beast Lore on a tameable beast **missing from the database** (turn on "Show NPC ID" in options;
      check the ID is not in the Finder) → "No known abilities" and a grey "Tame it to help confirm!".
- [ ] Tame such a beast that arrives with **no** pet abilities → the hint stays (1 hunter). After a
      second hunter reports the same → only "No known abilities" remains.
- [ ] Mouse over ordinary mobs, players and NPCs without Beast Lore → tooltips unchanged.
- [ ] Beast Lore in combat → no errors (secret values are skipped silently).

## 4. Ability Finder

- [ ] `/blp` opens the Finder; the minimap button left-click opens it too; Esc closes it.
- [ ] Pick an ability (e.g. Bite) and a rank → the list shows beasts with level range and zone,
      and the header shows pet level, training points and your status for that rank.
- [ ] Click the **Level** and **Beast** headers → sorting changes; click again → reverses.
- [ ] Default sort is nearest first (arrow on **Zone**): in the Crossroads, Bite (Rank 3) starts with The
      Barrens / Wailing Caverns, Eastern Kingdoms beasts last. Click **Zone** again → farthest first.
      The zone menu also lists zones nearest first. Close and reopen → the sort is remembered.
- [ ] Type "raptor" in search → the ability list shrinks to matching abilities; clear it → all back.
      Changing the Level box only greys abilities.
- [ ] "All abilities" (or "All" ranks) → a gold header per ability and rank with a blank row between
      groups; clicking a header shows only that rank.
- [ ] Pick an ability you know (e.g. Bite rank 2) → rank buttons 1 and 2 are grey; hovering says you
      already know it.
- [ ] **Zone** button → menu of zones (and "Current zone"); picking one filters; right-click clears.
      **[confirms Phase 0: MenuUtil exists; otherwise it cycles zones on click]**
- [ ] Type in the search box (a beast name, an ability or a zone) → the list filters.
- [ ] **Level** box shows your level. Tick **Can learn now** and untick **Already learned** → only beasts
      you can tame now with ranks you don't know remain (level 27: Claw shows ranks 1-4, not 5). Type
      another level (e.g. 40) → the list changes; clear it → back to your level. With **Can learn now**
      unticked, rows above the level are dimmed with a red level.
- [ ] Scroll down, then tick **Can learn now** → the list stays visible (no empty view).
- [ ] Click a beast row → chat names the zone and coordinates, a map pin appears (and a TomTom arrow if
      TomTom is installed). With Questie installed the spot is a real spawn point.
- [ ] Hover a row → tooltip with all abilities that beast teaches and your status.

## 5. Minimap button and options

- [ ] Minimap button shows the logo; drag it around the minimap; right-click opens options.
- [ ] Options › untick "Show the minimap button" → it hides; `/blp minimap` shows it again.
- [ ] Esc › Options › AddOns › Beast Lore Plus shows the panel with logo, 5 checkboxes and legend.

## 6. Capture a fresh tame, then export

- [ ] Tame a beast (Tame Beast channel completes). Within a few seconds chat says the tame was
      recorded if it is new or differs from the database (nothing is said if it matches).
      `/blp debug` → "last capture" shows the beast's NPC ID and abilities, and the diagnostic log
      shows the Tame Beast events. **[confirms the pet spellbook API]**
- [ ] `/blp capture` with a pet out while targeting a wild beast of the same kind → recorded as a
      manual capture (shown in `/blp export`, never shared).
- [ ] Dismiss and call a **stabled** pet (no Tame Beast cast) → **no** capture is recorded.
- [ ] Interrupt a Tame Beast cast → no capture.
- [ ] `/blp export` → a copyable window with the tame in a Markdown table; Ctrl+C works.

## 7. Sharing between two characters or accounts

Two hunters with the addon, sharing on, either in the same guild or both online (hidden channel).

- [ ] `/blp debug` → "channel id" is a number (the hidden **BeastLorePlus** channel was joined) and
      the channel does **not** appear in any chat tab. **[confirms Phase 0: JoinTemporaryChannel /
      ChatFrame_RemoveChannel on Forever]**
- [ ] Hunter A tames a beast; on hunter B, `/blp debug` → "stored NPC reports" goes up.
      **[confirms Phase 0: CHANNEL/GUILD addon messages allowed]**
- [ ] If that beast is missing from the database, hunter B's Beast Lore shows
      "community: pending (1/3)" next to the abilities.
- [ ] Options › untick sharing → the channel is left; no messages are sent.

## 8. Non-hunter character

- [ ] Log in on a non-hunter: no errors, no channel joined, nothing added to tooltips.
- [ ] `/blp` still opens the Finder, without the status column; "Already learned" is disabled.

## Data review

Unverified and conflicting entries are listed in `tools/data/REVIEW.md`. Any you can check in game
(Beast Lore on the beast, or a tame) can be fixed in `tools/data/raw/*.json`, then run
`python tools/build_data.py`.
