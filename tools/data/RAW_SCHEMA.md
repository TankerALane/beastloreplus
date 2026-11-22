# Raw research file format (`tools/data/raw/<ability>.json`)

One JSON file per ability family (for example `bite.json`, `claw_r1-4.json`). Files are
**observations**, not conclusions: record what each source says, separately, with its URL.
`tools/build_data.py` merges them and decides `confirmed` / `unverified` / `conflict`.
Never write a merged opinion into these files.

```json
{
  "ability": "bite",
  "name": "Bite",
  "icon": "ability_racial_cannibalize",
  "trainerOnly": false,
  "researcher": "agent label, date",
  "ranks": [
    {
      "rank": 1,
      "observations": [
        { "source": "wowhead-classic", "url": "https://www.wowhead.com/classic/spell=17253",
          "spellIds": [17253], "petLevel": 1, "tp": 1 },
        { "source": "warcraft.wiki.gg", "url": "https://warcraft.wiki.gg/wiki/...",
          "spellIds": [17253], "petLevel": 1, "tp": 1 }
      ]
    }
  ],
  "beasts": [
    {
      "npcId": 1131,
      "observations": [
        { "source": "wowhead-classic", "url": "https://www.wowhead.com/classic/npc=1131",
          "name": "Winter Wolf", "rank": 1, "minLevel": 7, "maxLevel": 8,
          "zones": ["Dun Morogh"], "elite": false, "rare": false },
        { "source": "petopia-classic", "url": "https://...",
          "name": "Winter Wolf", "rank": 1, "minLevel": 7, "maxLevel": 8,
          "zones": ["Dun Morogh"] }
      ]
    }
  ],
  "notes": [
    "Free text: Forever-specific differences, pages that would not load, anything uncertain."
  ]
}
```

## Field rules

- `ability`: lowercase key, letters and underscores only. Use exactly these keys:
  `bite`, `claw`, `cower`, `dash`, `dive`, `charge`, `furious_howl`, `lightning_breath`,
  `scorpid_poison`, `screech`, `prowl`, `shell_shield`, `thunderstomp`, `growl`,
  `great_stamina`, `natural_armor`, `arcane_resistance`, `fire_resistance`,
  `frost_resistance`, `nature_resistance`, `shadow_resistance`. Add a new key only for an
  ability that is really missing from this list, and say so in `notes`.
- `icon`: the icon file name without path (as Wowhead shows it), or `null` if unknown.
- `trainerOnly`: true for abilities taught by the pet trainer, not learned from beasts.
- `source`: a short stable id per site. Use `wowhead-classic`, `wowhead-forever` (if Wowhead
  has Forever pages), `warcraft.wiki.gg`, `wowpedia`, `petopia-classic`, or another short site
  name. **Two observations from the same site count as one source.** Mirrors/copies of the same
  data (for example a site that just reprints Wowhead) should be marked with the site they copy in
  `notes` so the generator is not fooled.
- `rank` in a beast observation: the rank of this ability that the beast teaches.
  A beast that teaches several abilities appears in several files; that is expected.
- `npcId`: the creature ID. If a source names a beast without an ID, put the observation under the
  beast whose ID another source gave (match on name). If no source gives an ID, use `"npcId": null`
  and the generator will try to match by name, otherwise report it.
- Unknown numbers are `null`, never guessed. Levels are the level range that source shows.
- `zones`: zone names as the source shows them (English).
- `elite` / `rare`: booleans when the source says so, otherwise omit.
