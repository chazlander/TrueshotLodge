# Changelog

## [1.60.1.13] - 2026-10-12

- Fixed: on a client in another language than English, Collect Mode recorded no tameable creatures, NPC tooltips
  and Filter by Pet did not work, and Beast Training and pet trainers were not read. Families, creature types and
  abilities are now recognized by their game ids, which are the same in every language
- Collected data is saved in English whatever your client's language: families, abilities and ranks ("Rank 3"),
  with each family's id. Creature names stay as your client shows them; the website puts them in English by id
- Data shared by players on clients in other languages is added in English
- A pet trainer the addon does not know yet, met on a client in another language, is recorded for us to confirm
  (its title cannot be read there)
- Your collected file notes your client's language
- TODO: Add multi language support on the website.
- `/tsl debug collect check` shows each creature's family id

## [1.60.1.11] - 2026-10-12

- Data sharing's hidden channels keep out of the way of the game's own: they are moved after every other channel
  you are in, so General, Trade, LocalDefense and LookingForGroup keep their usual numbers
- The zone's sharing channel is joined as a temporary channel, so the game no longer saves it and rejoins it at
  login; the zone channels earlier versions saved are left automatically
- `/tsl debug shared` lists your channel numbers

## [1.60.1.9] - 2026-10-11

- Your collected data now records which version of the addon saved it, so after a change to the data the website
  can ask for an upload from an up-to-date addon
- README: a section on the Bounties

## [1.60.1.7] - 2026-10-11

- Fixed: the version shows as `1.60.1.<build>` (the 1.60.1.5 beta showed a commit hash)
- Fixed: your full name ("First Surname") is found even with the game's surnames display option off
- The addon list shows the TrueshotLodge logo; the .toc names the website and the CurseForge project
- Data: new verified tames, among them a source for a unique ability rank that had none

**Still missing** (as of this release; the Bounties show what to look for):

- 172 of 750 creatures have no known attack speed, 89 no level and 72 no zone (155 have no map points)
- 47 ranks of the families' unique abilities have no known tameable creature
- 80 rares have never been tamed by a TrueshotLodge hunter

Help fill them in: turn on Collect Mode, go hunting, and upload your file at
[TrueshotLodge.com](https://trueshotlodge.com/collector). The **Bounties** (in the addon's Collected Data tab and at
[TrueshotLodge.com/bounties](https://trueshotlodge.com/bounties)) list what is wanted.

## [1.60.1.5] - 2026-10-11

- **Bounties** on the Collected Data tab: what TrueshotLodge.com most needs found, with the top 5 untamed rares up to
  your level (in your zone, with the Zone Filter on)
- **Send Name** (Options, Collection; off by default): put your character's name on the beasts you tame, so the website
  credits you on their Tamed badge ("Verified Tame: date by name"). Off, your collected data is anonymous.
- The Tamed badge's tooltip says who made the tame
- WoW Forever's surnames: your full name ("First Surname") is used for the tame credit, Data Sharing and the data kept
  per character (moved over from the first name alone once)
- Versions follow the game: 1.60.1 plus a build number (`1.60.1.<build>`)

## [Alpha] - 2026-10-10

The first release of TrueshotLodge, the hunter's field guide to every tameable beast in WoW Forever.

- **Unique, Common and Passive Abilities**: every pet ability and rank, with what it does, the pet level it needs, its
  training point cost, who can learn it, and the tameable creatures that have it, each with a Map Location button
- **Passive Attack Speed**: every attack speed, with the creatures that have it
- **Trainers**: the pet trainers by zone and faction, with their location on a zone map
- **Stable**: your current and stabled pets, kept per character, with stats, abilities, a 3D model and the experience
  bar
- **Collected Data** and Collect Mode: records the beasts you tame, the tameable creatures you meet and the pet
  trainers you visit, for upload to [TrueshotLodge.com](https://trueshotlodge.com)
- **Data Sharing**: share collected finds with other TrueshotLodge users on your shard, in your zone or group
- **Options**: minimap icon, NPC tooltips, remembered selections, UI scale (50% to 150%), tab order, Data Sharing and
  Debug Mode
- NPC tooltips, the Zone Filter, movable side tabs, and the ∞ mark on what is new in WoW Forever
- Slash commands: `/tsl` opens the window, `/tsl clear` clears the map pins, and `/tsl debug` lists the
  troubleshooting commands (only while Debug Mode is on)
