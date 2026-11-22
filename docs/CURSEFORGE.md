<!-- The CurseForge project fields and description, kept here so they can be reviewed and updated
     with each release. Paste the description (everything below the line) into the editor on
     curseforge.com in Markdown mode. -->

## Project fields

- **Name:** Beast Lore Plus
- **Summary:** Beast Lore shows which pet abilities a beast teaches and whether you need them, plus a searchable finder for every beast in WoW Forever.
- **Main category:** Hunter (under Class)
- **Additional category:** Map & Minimap
- **License:** MIT License
- **Game version:** WoW Forever 1.60.1
- **Source:** https://github.com/TankerALane/beastloreplus
- **Issues:** https://github.com/TankerALane/beastloreplus/issues
- **Avatar:** `beast_lore_plus_logo_512.jpg`

---

# Beast Lore Plus

*Know what a beast will teach you before you tame it.*

A hunter addon for **World of Warcraft Forever**.

Cast **Beast Lore** on a tameable beast as usual. Under the game's own lines (Tameable, Specialization, Diet), Beast Lore Plus adds a **Pet Abilities** section listing every ability and rank that beast teaches, each with a coloured dot showing whether you need it:

- **Green**: you already know this rank
- **Yellow**: you have a higher rank, but not this one (a higher rank doesn't teach the lower ones)
- **Orange**: you know a lower rank, so taming this beast is an **upgrade**
- **Red**: you haven't learned this ability yet
- **Grey ?**: open **Beast Training** once on this character so the addon knows what you have

Beast Training only shows the abilities your current pet's family can use, so skipped ranks turn yellow once you've opened Beast Training with a pet of that family.

Beasts with no known abilities say so. Nothing is added for beasts that can't be tamed.

Prefer not to cast every time? Turn on **Show Beast Lore details without casting Beast Lore** in the options and simply hover a beast to see Tameable, Specialization, Diet and Pet Abilities. Specialization and Diet come built in for beasts already seen in game, are shared by other Beast Lore Plus users, and are learned per family from your own casts (cast Beast Lore once on any wolf and every wolf shows them). It's off by default.

## Ability Finder

Type **/blp** or click the minimap button to search every pet ability and the beasts that teach it.

- **Search** by beast, ability or zone.
- **Pick an ability and rank.** Ranks you already know are greyed out.
- **Results are grouped** by ability and rank, showing pet level, training points and beast count.
- **Nearest first:** beasts in your zone come first, then nearby zones.
- **Level box** (your level by default):
  - **Can learn now** hides beasts you can't tame yet.
  - Untick **Already learned** to see only what you still need.
- **Click a beast** to drop a **map pin** where it spawns, plus a **TomTom** arrow if you use TomTom. Exact spawn points need **Questie** installed; without it, the pin uses where you last targeted that beast.

## Includes Forever's new pet abilities

Forever redesigned hunter pets, and the database covers the new family abilities: Savage Rend, Tendon Rip, Pinch, Web, Swipe, Sonic Blast, Dismember, Dust Cloud, Mine! and Trickster's Dance. It also covers the Classic abilities (Bite, Claw, Dash, Dive, Cower and more).

It has **435 beasts across 32 abilities**. Each entry is tagged **confirmed** (two independent sources agree, or a hunter confirmed it in game) or **unverified**.

## Your training, tracked per character

Open Beast Training once on each hunter. After that, Beast Lore Plus keeps track by itself: when the game says "You have learned a new spell…", the dot turns green straight away.

## Help improve the data

Forever changed a lot about pets, so some entries are still unverified. You can help just by playing:

- **Tame beasts.** When you tame a beast, the abilities your new pet arrived with are recorded and shared with other Beast Lore Plus users in your guild and on a hidden channel. A beast missing from the data is filled in once **3 different hunters** report the same abilities. Community reports never overwrite the bundled data.
- **Send an export.** Type **/blp export**, copy the text, and paste it into a [GitHub issue](https://github.com/TankerALane/beastloreplus/issues). Each release folds confirmed tames into the bundled data.

Casting **Beast Lore** shares that beast's Specialization and Diet the same way, so everyone can see them on mouseover.

Shared messages contain only the beast's ID, name and family, its abilities and ranks, its Specialization and Diet, your game build and the addon version. You can turn sharing off in the options.

## Commands

- **/blp**: open the Ability Finder
- **/blp options**: settings (minimap button, sharing, details without casting, grey rows, NPC IDs)
- **/blp export**: copy your tames and data reports for a GitHub issue
- **/blp capture**: record the pet you have out (target a wild beast of the same kind first)
- **/blp debug**: troubleshooting information

## Support

support@decoupledlane.com · [Report an issue](https://github.com/TankerALane/beastloreplus/issues)

Made by Decoupled Lane Studio. MIT licensed.
