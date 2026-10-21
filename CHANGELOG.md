# Changelog

## [1.60.1.26] - 2026-10-21

- The addon has its own .toc for WoW Forever (TrueshotLodge_Forever.toc), the one the WoW Forever client loads
- Options and the new **Help** have their own buttons beside the close button: the gear opens Options, the **?** opens
  Help (click either again to go back to your tab). Options is no longer a side tab
- Help: **How to Claim** (moved here from the Bounties tab), what the filters do, the slash commands, and **Tab
  Descriptions**, what each tab is for
- `/tsl options` and `/tsl help` open the window straight on Options or Help
- Debug Mode (Options, Advanced): a checkbox per area of debug messages (Collector, Data Sharing, Integrity, Beast
  Training, Stable, NPC Tooltips, Window), all off until you tick the ones you want; NPC tooltips no longer report
  every player or object you hover
- Side tabs on both sides: hold a tab and drag it across the window, and it snaps to the window's left edge (or back to
  the right). Each side keeps its own order (drag up or down), saved for each character
- **Tab Organization** (Options, Visual, was Tab Order): a checkbox per side tab to show or hide it, and Reset Tab Order
  to put them all back on the right in their usual order. The Collected Data tab still shows with Collect Mode
- With Collect Mode on, a chat message says so when you see or tame a creature that is not in TrueshotLodge yet (once
  per creature a session), so you know that one is worth uploading
- Library Dependancy Updates and Attribution  
- Data: 12 more creatures verified by a tame (145 in all), among them Dishu, Black Ravager, Longsnout, Moonstalker
  Runt, Nightsaber Stalker, Black Bear Patriarch and Wood Lurker
- Data: 8 more creatures with a known attack speed (among them the Shriekling Fledgling and Matriarch, Elder Snow
  Leopard, Famished Blackworg and Greater Tarantula); Young Fleshripper and Young Goretusk attack at 2.5, and Forest
  Spider, Mangy Wolf, Pygmy Tide Crawler and Gray Fox have a wider level range

**Still missing** (as of this release):

- 139 of 761 creatures have no known attack speed, 77 no level and 60 no zone (141 have no map points)

## [1.60.1.21] - 2026-10-19

- New on the website: the **Hall of Fame** (TrueshotLodge.com/hall-of-fame), the hunters who tamed the most, with
  their Forever, normal, elite and rare tames. Turn on Send Name (Options tab, Collection) to be on it
- Data: the unique abilities as WoW Forever has them now: **Dismember** heals 25% less for 6 sec (was 50% for 10 sec),
  15 sec cooldown; **Mine!** disarms for 3 sec, 90 sec cooldown; **Sonic Blast** slows casting by 30% for 20 sec, 60 sec
  cooldown; **Furious Howl** reaches the whole party or raid
- Data: 761 tameable creatures (3 new: Tainted Hyjal Bear, Enraged Panther and Grinning Dog); Bloodshrike is a Bird of
  Prey now, as WoW Forever has it
- Data: 70 more creatures verified by a tame (133 in all), among them Echeyakee, Sarkoth, Mystmane, Besseleth,
  Ukorsbane, Snapjaw, Matriarch Bristlefur, Bloodtalon Matriarch and the Cloud Serpents
- Data: 8 more creatures with a known attack speed, 5 more with a known zone

**Still missing** (as of this release):

- 147 of 761 creatures have no known attack speed, 77 no level and 60 no zone (141 have no map points)

## [1.60.1.19] - 2026-10-14

- New **Families** tab, as on the website: every pet family by type with its number of tameable creatures; select one
  for its unique ability, type and diet, the common and passive abilities it learns, and all its tameable creatures
  with their Map buttons (the Zone and Level filters narrow them)
- The filters are buttons now, at the top right: **Level**, **Zone**, **Pet** and, on the Trainers tab, **Faction**,
  each tab showing the ones it can use. Grey while off, red and glowing while on. They replace the Filter menu and
  the Zone Filter checkbox in the title bar
- Passive Attack Speed tab: every speed starts open, and the **Level** filter keeps the beasts you can tame now
- The right-hand pane is tighter
- New pet bounties, as on the website: **Missing Normal**, the creatures that are not rares and nobody has tamed yet,
  and **Missing Forever**, the creatures new in WoW Forever nobody has tamed yet. The Bounties tab's first heading is
  now "Wanted Tames"
- Data: 758 tameable creatures (2 new: Bloodsnout and Empyrean Galestrider), and 2 more verified by a tame (63 in
  all): Elder Ashenvale Bear and Ornery Galestrider
- Data: 4 more creatures with a known attack speed, 10 more with a known zone, and 24,435 map points (up from 23,856)

**Still missing** (as of this release):

- 152 of 758 creatures have no known attack speed, 82 no level and 62 no zone (145 have no map points)

## [1.60.1.17] - 2026-10-14

- New **Bounties** tab, with the same bounties as the website: Missing Tamed Rares, Missing Attack Speed, Missing Zone,
  and the Unique Abilities without Source with their Potential Tameable Targets, each listing its creatures with a Map
  Location button (the Zone Filter and Filter by Level narrow them), plus How to Claim, step by step. Right-click a
  heading to sort its bounties by number of creatures instead of alphabetically. It replaces the Bounties entry of the
  Collected Data tab, and shows whether Collect Mode is on or not
- With Send Name off, a one-time chat tip says how to turn it on, so your tames credit you on the website's Tamed badge
  (Send Name stays off until you turn it on)
- Collect Mode keeps only what is new: a wild sighting of a creature that the addon's data already holds completely
  (same family and classification, every level seen inside its level range, the same attack speed and zones seen on its
  maps) is no longer kept in your collected data or sent to other players, since it tells the website nothing new. It
  is kept as soon as you see that creature at another level or in another zone. Tames, trainers and Beast Training are
  always kept. When the addon loads, wild sightings that a new release's data now holds are removed from your collected
  data the same way, so your next upload carries only what is still new
- Shared sightings and tames leave out the creature's name when the addon's data has the creature, which makes them
  shorter; whoever receives one names the creature from its id, with the game's own name in their language (so a name
  in another player's language no longer ends up in your collected data)
- When other TrueshotLodge users are on a newer version, a chat message says so once a session, so you know to update
  (it needs two players reporting the same newer version)
- `/tsl debug npc <id>` (Debug Mode) shows what the game, the addon's data and your collected data say about a creature
- Data: 756 tameable creatures (2 new: Enraged Stanley and Gray Fox)
- Data: 24 more creatures verified by a tame (61 in all), among them Goretusk, Venom Web Spider, Black Widow Hatchling,
  Highland Raptor, Elder Gray Bear, Dreadmaw Crocolisk, Bloodtalon Scythemaw, Savannah Huntress, Mazzranache,
  Ghostpaw Alpha, Chakuyak and Maddened Rotclaw
- Data: 17 more creatures with a known attack speed

**Still missing** (as of this release):

- 154 of 756 creatures have no known attack speed, 85 no level and 70 no zone (161 have no map points)

## [1.60.1.15] - 2026-10-12

- A tame shared with other players now carries your credit when Send Name is on, so the website names you as the
  hunter who tamed it whoever uploads it (the name is the one the game reports for the sender)
- Fixed: "No player named ... is currently playing." could still show in chat after data sharing whispered a player
  who had gone offline (with more than one chat window, or several whispers to them); every copy is hidden now
- Data: 754 tameable creatures (5 new: Ice Claw Bear, White Lion, Frostwolf, Highland Lurker and Bloodwing Bat), and
  13 more verified by a tame (37 in all)

**Still missing** (as of this release):

- 169 of 754 creatures have no known attack speed, 87 no level and 70 no zone (159 have no map points)

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
