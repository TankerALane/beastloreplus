# Findings: trainer abilities, completeness check, Forever changes

Researcher: trainer-abilities research agent, 2026-11-21.
Method: Wowhead tooltip JSON (`https://nether.wowhead.com/classic/tooltip/spell/<id>` and
`https://nether.wowhead.com/forever/tooltip/spell/<id>`), Wowhead Forever search
(`https://www.wowhead.com/forever/search/suggestions-template?q=<name>`), warcraft.wiki.gg,
Blizzard's own news post, and fan guides. Petopia Classic could not be read (TLS certificate error);
the Wowhead Classic guide and calculator pages returned HTTP 403.

## Part 1: mapping the Forever pet-trainer spell IDs

Every ID is checked against Wowhead Classic and Wowhead Forever tooltips. "pet" means the pet's own spell.
"teach" means the hunter-side Beast Training learn spell (100 yd, Instant, Requires Hunter).

| IDs | Ability | Ranks | Kind |
|---|---|---|---|
| 2649 | Growl | 1 | pet (level 1) |
| 14916-14921 | Growl | 2-7 | pet (levels 10/20/30/40/50/60) |
| 4187-4194 | Great Stamina | 1-8 | pet (levels 1*/12/18/24/30/36/42/48) |
| 5041, 5042 | Great Stamina | 9, 10 | pet (levels 54, 60) |
| 24545 | Natural Armor | 1 | pet (level 1*) |
| 24549-24555 | Natural Armor | 2-8 | pet (levels 12/18/24/30/36/42/48) |
| 24629, 24630 | Natural Armor | 9, 10 | pet (levels 54, 60) |
| 23992, 24439, 24444, 24445 | Fire Resistance | 1-4 | pet (levels 20/30/40/50) |
| 24446-24449 | Frost Resistance | 1-4 | pet (levels 20/30/40/50) |
| 24493, 24497, 24500, 24501 | Arcane Resistance | 1-4 | pet |
| 24492, 24502, 24503, 24504 | Nature Resistance | 1-4 | pet |
| 24488, 24505, 24506, 24507 | Shadow Resistance | 1-4 | pet (24507 rank 4 says level **40**) |
| 24494 | Nature Resistance | 1 | **teach** (not a pet spell) |
| 24495 | Arcane Resistance | 1 | **teach** (not a pet spell) |

\* Rank 1 of Great Stamina and Natural Armor: the pet spell says level 1, but the teach spell (4195 / 24547) says level 10.

**IDs in the list that are not trainer pet spells** (assuming "24492-24507" is meant as a full range):
- **24496**: no such spell on Wowhead Classic or Forever ("Entity not found").
- **24498**: "Brilliant Light", a Paladin item effect. Not a pet spell.
- **24499**: "Energized Shield", a Shaman item effect. Not a pet spell.

Teach (Beast Training) spell IDs. These are the same on Classic and Forever; Wowhead Forever puts them in the "Beast Training Abilities" category:
- Growl: 1853 (rank 1), 14922-14927 (ranks 2-7)
- Great Stamina: 4195-4202 (ranks 1-8), 5048, 5049 (ranks 9-10)
- Natural Armor: 24547 (rank 1), 24556-24562 (ranks 2-8), 24631, 24632 (ranks 9-10)
- Fire: 24440, 24441, 24463, 24464. Frost: 24475-24478. Arcane: 24495, 24508-24510.
  Nature: 24494, 24511-24513. Shadow: 24490, 24514-24516.

Training point costs come from warcraft.wiki.gg (rank 1 only), mmonster.co (Forever beta client data, every rank)
and tentonhammer (a TBC-era page). Wowhead does not show TP on its spell pages.

| Ability | TP per rank |
|---|---|
| Growl | 0 at every rank |
| Great Stamina | 5, 10, 15, 25, 50, 75, 100, 125, 150, 185 |
| Natural Armor | 1, 5, 10, 15, 25, 50, 75, 100, 125, 150 |
| Each resistance | 5, 15, 45, 90 |

Growl ranks 1-2: warcraft.wiki.gg Beast_Training says Beast Training "comes with only Growl (ranks 1 and 2) by default"
(https://warcraft.wiki.gg/wiki/Beast_Training).

## Part 2: completeness check (Classic Era)

Source A is warcraft.wiki.gg Beast_Training (https://warcraft.wiki.gg/wiki/Beast_Training):
- Tamed beasts teach: Bite, Charge, Claw, Cower, Dash, Dive, Furious Howl, Lightning Breath, Prowl, Scorpid Poison, Screech, Shell Shield, Thunderstomp.
- Pet trainers teach: Great Stamina, Natural Armor, and the Arcane, Fire, Frost, Nature and Shadow Resistances.
- Growl ranks 1-2 come by default; trainers teach the other ranks.

Source B is Warcraft Tavern. Its Classic guide (https://www.warcrafttavern.com/wow-classic/guides/hunter-pets/) and
its abilities guide (https://warcrafttavern.com/wow-classic/guides/hunter-pet-abilities) list the same 13 beast-taught
and 8 trainer-taught abilities.
- The two Warcraft Tavern pages disagree on max ranks: resistances R4 vs R5, and Lightning Breath R5 vs R6. Wowhead shows only 4 resistance ranks.

**Result for Classic Era: the 13 beast-taught abilities plus 8 trainer abilities are the complete list. No beast-taught ability is missing.**

Cobra Reflexes (25077, "Increases attack speed by 30%, but decreases damage") is an innate family passive
(raptor and others), not a trainable ability.

### On Forever the list is NOT complete

The Wowhead Forever database and Blizzard's class deep dive show family-unique abilities that are new on Forever.
The pet spell IDs below come from Wowhead Forever search results:

| Ability | Family | Ranks | Pet spell IDs (Wowhead Forever) | Notes |
|---|---|---|---|---|
| Sonic Blast | Bat | 5 | 1264478-1264482 | Nature damage, spells cast 30% slower for 20 s |
| Swipe | Bear | 5 | 1264494, 1264497, 1264498, 1264501, 1264502 | hits 3 targets |
| Mine! | Bird of Prey (was Owl) | at least 5 seen | 1265054 (R1), 1265058 (R5) | damage plus 3 s disarm |
| Pinch | Crab | 5 | 1264735, 1264736, 1264739, 1264741, 1264742 | teach IDs 1264745, 1264749-1264752 |
| Dismember | Crocolisk | 5 | 1264758, 1264927, 1264929, 1264930, 1264933 | healing reduction 25% |
| Tendon Rip | Hyena | 5 | 1265038-1265042 | teach IDs 1265043, 1265045, 1265047, 1265048 (partial) |
| Savage Rend | Raptor | 5 | 1265065-1265069 | teach IDs 1265831, 1265833-1265836 |
| Web | Spider | 5 | 1265843, 1265878, 1265880, 1265881, 1265883 | teach ID 1265887 (R1) |
| Dust Cloud | Tallstrider | 5 | 1265899, 1265901-1265904 | armor reduction |
| Trickster's Dance | Fox (new family) | 1 | 1310612 | teach ID 1310617 |
| Demoralizing Screech | Carrion Bird | 4 | **24423**, 24577, 24578, 24579 | **same IDs as Classic "Screech"** |

More Forever-only pet passives appear on Wowhead Forever as "Generic Pet Abilities": Faster Attack I-VII
(1263099-1263110) and Slower Attack II/III (1263113, 1263114). Fan sites say these set the pet's attack speed,
and that unlearning all abilities removed them during beta. A November 2 hotfix reportedly changed that.

Wowhead Forever also lists "Lava Breath" (444678/444681) as a Hunter pet ability. Those IDs are in the Season of
Discovery range, so this is probably a leftover. It is not confirmed as obtainable on Forever.

**Impact on the addon:** spell 24423 (verified on Forever) is named "Demoralizing Screech" there, with icon
ability_hunter_pet_vulture and Carrion Bird only. ForeverChanges says the Bat and Owl Screech was removed.
Bite, Claw, Dive and Dash are also reported to be spread across more families on Forever.

## Part 3: Forever-specific changes (with URLs)

Official sources:
- Blizzard's deep dive (posted September 30): https://worldofwarcraft.blizzard.com/news/24301515 (mirror: https://news.blizzard.com/en-us/article/24301515/world-of-warcraft-forever-class-deep-dives-hunter-and-druid)
  - Foxes are a new family with Trickster's Dance. Owl is renamed Bird of Prey.
  - Every family can now learn Bite or Claw, sometimes both, and every family can learn Dive or Dash.
  - Each family has one unique ability (the list above).
  - Pets scale from the hunter's gear and no longer take stat buffs from players.
  - Endurance Training now gives pet Health and Armor. Other pet talents also changed.
  - Pets can tank in solo and small-group play.
  - The post says nothing about the trainer, training points or Beast Lore.
- Wowhead news summary of the same post: https://www.wowhead.com/forever/news/druid-and-hunter-class-deep-dives-in-world-of-warcraft-forever-383190
  - It says family abilities "can not [be learned] from the Pet Trainer", only by taming a pet that knows the ability at that rank.

Wowhead Forever database (tooltip JSON as above):
- **Great Stamina** pet spells now read "Health increased by 30 ... 400" instead of Classic's "Stamina increased by 3 ... 40".
  Spell IDs and levels are unchanged. The teach spells still say "Stamina increased by 30 ... 400".
- Natural Armor, Growl and all resistance spells match Classic (same IDs, levels and values).
- Some unclassed Classic "100 yd" variants (24442, 24548, 24636) do not exist on Forever.
- The Shadow Resistance rank 4 oddity (pet spell level 40, teach spell level 50) is present on both versions.

warcraft.wiki.gg:
- Beast Training and Training point "remain in Classic and Forever": https://warcraft.wiki.gg/wiki/Beast_Training, https://warcraft.wiki.gg/wiki/Training_point
- New Forever-exclusive APIs in the "Exclusive API/forever" category (https://warcraft.wiki.gg/wiki/Category:Exclusive_API/forever):
  - `C_PetInfo.GetPetTrainingPoints()` returns totalPoints, usedPoints (https://warcraft.wiki.gg/wiki/API:C_PetInfo.GetPetTrainingPoints)
  - `C_PetInfo.GetPetLoyalty`, `C_PetInfo.GetPetHappiness`, `C_PetInfo.GetPetFoodTypes`, `C_PetInfo.CanPetEatItem`, `C_PetInfo.GetPetUIModelSceneID`
  - `GetPetHitChanceModifier`, `GetPetSpellHitChanceModifier`, event `PET_STATS_UPDATE`
  - `C_StableInfo.*` (stable slots)
  - These are relevant for the addon (the training point API differs from Classic's `GetPetTrainingPoints`).

Fan or secondary sites (unofficial, may be partly AI-written; use with care):
- ForeverChanges: https://foreverchanges.pro/hunter-pets
  - Says it compares Forever 1.60.1.71037 client data with Classic Era 1.15.9.69722.
  - Changes: new Fox family; Owl renamed Bird of Prey; Bat and Bird of Prey Screech removed; Raptor Cobra Reflexes removed.
  - Dash added to 8 more families. Charge, Demoralizing Screech, Thunderstomp, Scorpid Poison, Shell Shield, Lightning Breath and Furious Howl changed.
  - Pets default to 2.0 s swings, set by Faster/Slower Attack passives. Focus regenerates about 2x faster.
  - Taming is limited to beasts at or below your level.
  - "Training still works as in Classic." Beast Lore is learned at level 24 and shows what a beast knows. No pet specializations are mentioned.
- conquestcapped hotfix timeline: https://conquestcapped.com/guides/wow-forever/wow-forever-hunter-pet-changes/
  - Oct 1: Aggressive mode restored; fixed beasts whose ability ranks were too high.
  - Oct 16: Dismember, Sonic Blast and Mine! nerfed.
  - Nov 2: pets keep their attack-speed passive when untrained.
  - Nov 9: Vulgara and the Shrieklings moved to their correct families.
  - Nov 10: pet health fixed from 150% to 115%.
- mmonster.co: https://mmonster.co/wow-forever/guides/hunter-pets/abilities
  - Full trainer TP tables (client data read in beta) and the full Forever ability list (36 entries).
- Warcraft Tavern Forever guide: https://www.warcrafttavern.com/forever/guides/hunter-pet-abilities/
  - Beast Training is spell 5149, pets hold at most 4 active abilities, and loyalty has 6 ranks (300 TP at 60).
  - A beta note says untraining removes the attack-speed passive.
  - A reader reported Bite vanishing after training (a bug).
- Other fan guides seen but not used for numbers: https://classicwow.gg/forever/guides/hunter, https://wow4ever.quest/en/articles/habilidades-mascotas-cazador-wow-forever, https://overgear.com/guides/wow-forever/hunter-pets/

Pet specializations shown by Beast Lore: **no source found** mentions pet specializations (Ferocity, Tenacity,
Cunning or similar) on Forever. Blizzard only talks about pets as tanks. No Beast Lore change was found, and no
Beast Training UI change beyond the new APIs. One fan site reports Beast Training missing for some players with
controller support enabled.
