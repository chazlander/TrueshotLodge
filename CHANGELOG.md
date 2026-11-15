# Changelog

## [1.60.1.45] - 2026-11-15

- A data update: the creatures, tames and attack speeds TrueshotLodge hunters have shared since the last release.
- Data since 1.60.1.44:
  - 8 new tames (354 in all)
  - 2 new creatures (787 in all)
  - 0 new sightings
  - 0 new ability tames
  - 4 new attack speeds
  - 2 new levels
  - 3 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 85 of 787 creatures have no known attack speed, 58 no level and 44 no zone (169 have no map points)

## [1.60.1.44] - 2026-11-14

- The 3D models (the Looks tab and a pet's profile) show the game's model buttons along the top when you hover them:
  zoom in and out, turn left and right (hold to keep turning) and reset, as on the stable's pet. The "Drag to turn"
  line under them is gone; dragging, right-dragging and the mouse wheel still work.
- Bounties: Uniques without Source is now Unique Ability Targets. It lists every rank of each family's unique
  ability, not only those no known creature has, each with the untamed creatures in its level range that might have
  it, and how many known creatures have it already. As on the website.
- A rank's count of creatures turns green once every one of them has been tamed, as on the website.
- A grey eye after a creature's name means a TrueshotLodge hunter has seen it in the wild and uploaded the
  sighting, but nobody has tamed it yet (a tamed creature keeps its green dot). Its profile says so too.
- Fixed: learning a pet ability rank now marks it known straight away, as 1.60.1.42 meant it to. It did not notice the
  game's "You have learned a new spell" line at all. The line links your own spell for the rank, not the pet's, and
  often shows no rank ("[Web]" was Rank 2), so the addon now knows which rank each of those spells teaches, from the
  game's own data.
- Data since 1.60.1.43:
  - 0 new tames (346 in all)
  - 0 new creatures (785 in all)
  - 0 new sightings
  - 0 new ability tames
  - 0 new attack speeds
  - 0 new levels
  - 0 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 87 of 785 creatures have no known attack speed, 58 no level and 45 no zone (167 have no map points)

## [1.60.1.43] - 2026-11-14

- **NEW FEATURE:** The addon is unaware of all the hard work a Hunter has done prior to its download. This new feature will give you the ability to mark abilities as known until it can be verified by the addon itself. Unfortately there is nothing exposed by Blizzard to allow us to read every ability you may have previously learned - only whats available in the spell book or what you actively learn while you have the addon.
- A new option, Known Ability Edit (Options, Advanced): while it is on, click an ability's icon (at the top of its
  details, on the Unique, Common and Passive tabs) to mark that rank known by hand, for one you learned before the
  addon could see it (click again to take the mark back). It is on for that session only, and off again when you log
  out. A rank your Beast Training has shown stays known for good: a rank cannot be unlearned. Help (the ? by the close
  button) has a new Known Abilities entry that explains all this.
- The abilities you have learned are never cleared any more. A hunter cannot unlearn a Beast Training rank, so once a
  rank is marked known it stays known for that character.
- Data since 1.60.1.42:
  - 14 new tames (346 in all)
  - 7 new creatures (785 in all)
  - 0 new sightings
  - 2 new ability tames
  - 11 new attack speeds
  - 10 new levels
  - 9 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 87 of 785 creatures have no known attack speed, 58 no level and 45 no zone (167 have no map points)

## [1.60.1.42] - 2026-11-14

- The Bounties tab has a new section, The Untamables: the creatures hunters have uploaded that we keep out of the
  guide. There is nothing to claim; it is there so you can see everything uploads have brought in, including what we
  left out. The same list is at TrueshotLodge.com/bounties/untamables
- Learning a pet ability rank now marks it as known right away, without opening Beast Training. Ranks you learned
  before still need one look in Beast Training, once with each pet family you own.
- The Bounties tab has a new pet bounty, Missing Model: the creatures whose look nobody knows yet, as on the website.
  Each bounty's creatures now show their family too, and a creature the game refuses to tame is no longer wanted by
  any bounty.
- A creature the game refuses to tame says "Not tameable" in red: after its name in the lists, in its tooltip (on the
  map, in the window and in the world) and on its profile.
- An ability a trainer teaches now shows the price the trainer charges for the rank. Growl says where it comes from
  ("Known by every pet" for Rank 1, a Hunter or Pet Trainer for the rest) instead of an empty list of creatures.
- On the Trainers tab the Zone filter now lists only your zone's trainers. In a zone without one it lists none; it
  used to list every trainer then, which looked as if the filter was off.
- On a pet's profile, the Map button is now at the top of the left pane, across from Back, and the model fills the
  right pane. A tamed creature's row reads "Tamed by" and the hunter's name; hover it for the date.
- Fixed: right-dragging the model on a pet's profile made the creature vanish.
- A new filter button, Rares, above Pet: wherever creatures are listed (the ability tabs, Families, Looks and
  Bounties) it shows only the rare ones, and only the ranks, families and looks that have one.
- The search box now searches creatures, not the names on the left. Type part of a creature's name on the ability
  tabs, Families, Looks or Bounties: the left side keeps only the ranks, families, looks and bounties that have a
  creature matching it (opened, with their number of matches), and the right side lists just those creatures. On the
  tabs without creatures (Passive, Trainers, Options, Help, Collected Data) it searches the list as before.
- With the Zone filter on, the ability tabs' list now follows it too: only the ranks (and attack speeds) that a
  creature in your zone has are listed, each with its number of creatures there. Ranks a trainer teaches stay.
  The Families tab does the same with the Zone and Level filters: a family with no creature left is not listed.
- The addon and the website now use the same colors for the same things: creature names are the website's light blue,
  and hints are one grey everywhere.
- Your collected data file now carries a random id, so when you upload it again after more hunting, we can tell it is a
  newer copy of the same file. The id says nothing about you or your characters.
- Data since 1.60.1.41:
  - 54 new tames (332 in all)
  - 1 new creature (778 in all)
  - 0 new sightings
  - 12 new ability tames
  - 2 new attack speeds
  - 1 new level
  - 1 new zone
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 91 of 778 creatures have no known attack speed, 61 no level and 47 no zone (160 have no map points)

## [1.60.1.41] - 2026-11-11

- Data since 1.60.1.40:
  - 44 new tames (278 in all)
  - 9 new creatures (777 in all)
  - 0 new sightings
  - 8 new ability tames
  - 27 new attack speeds
  - 16 new levels
  - 13 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 92 of 777 creatures have no known attack speed, 61 no level and 47 no zone (159 have no map points)

## [1.60.1.40] - 2026-11-11

- Right-click any Map button to clear the pins from the world map
- TrueshotLodge is now listed in the game's addon menu by the minimap, under the calendar. Left-click opens or closes
  the window and right-click clears the map pins, and it stays there if you hide the minimap icon
- Creature and map pin tooltips now color each ability: yellow if you know it, green if your level has reached it, and
  grey if it hasn't yet
- An ability now counts as known once it is in your Beast Training window, not as soon as you tame a beast that has it.
  Open Beast Training once with each kind of pet to mark what you have already learned
- The Collected Data tab now shows each creature's family, and a sighting's classification (Normal, Elite, Rare...).
  Both are highlighted when they differ from the addon's data, and a Beast Training entry highlights its new spell or
  its different rank, so you can see why each entry was kept
- Data since 1.60.1.39:
  - 55 new tames (234 in all)
  - 3 new creatures (768 in all)
  - 0 new sightings
  - 6 new ability tames
  - 15 new attack speeds
  - 7 new levels
  - 6 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 110 of 768 creatures have no known attack speed, 68 no level and 51 no zone (150 have no map points)

## [1.60.1.39] - 2026-11-08

- Collect Mode clears old tames too: each time you log in or reload, a tame that tells TrueshotLodge nothing new any more
  (the creature's tame, attack speed and abilities are all already known) is dropped from your collected data, as old
  sightings already were, so your next upload holds only what's new. Tames other hunters share with you are checked
  the same way as they arrive
- Pet trainers and Beast Training are now collected only when they add something: a trainer TrueshotLodge doesn't
  list, or an ability whose rank or price differs from what it has (your reputation discount is allowed for). The
  rest are no longer recorded, shared or uploaded, and are cleared from your collected data when you log in or reload
- A new pet's abilities are now the ones it came with: an ability you teach it right after taming (Growl, say) is no
  longer recorded as one the creature comes with
- Collect Mode only records a creature's zone when it is close to you (within about 28 yards). A creature across a
  zone border, such as a Durotar raptor seen from the Barrens side of the river, is no longer credited to the zone you
  stand in
- A wild creature's attack speed now only counts when TrueshotLodge has none for it yet. A creature often swings
  slower than its pet will (in a fight it can be slowed), so only a tame changes a speed we already have
- Collected Data highlights more of what a tame brings: a Verified Tame line when it would be the creature's first
  tame, name the hunter of an anonymous one or be an earlier one, and its attack speed when no tame has confirmed it yet
- Data since 1.60.1.38:
  - 11 new tames (180 in all)
  - 0 new creatures (765 in all)
  - 0 new sightings
  - 3 new ability tames
  - 8 new attack speeds
  - 1 new level
  - 3 new zones
  - 0 new looks (164 in all)

**Still missing** (as of this release):

- 122 of 765 creatures have no known attack speed, 72 no level and 54 no zone (147 have no map points)

## [1.60.1.38] - 2026-11-07

- Collect Mode and Collected Data:
  - Each creature's model (the look the game draws for it) is noted when you see it, so a creature new to
    TrueshotLodge gets its 3D model and picture on the website and in the addon as soon as you upload, without
    waiting for anyone else to list it. Shared sightings carry it too
  - Collected Data shows what's new: in a sighting or tame of a creature TrueshotLodge already knows, each line that
    differs from what the addon has (a level, attack speed, zone, model or ability rank) is in green, with what the
    addon has beside it
  - Far fewer sightings that tell the website nothing new are kept. A wild creature's attack speed no longer counts
    once a tamed pet has confirmed it (a tamed pet attacks at its own speed), a dungeon (where the game only reports
    the continent) is no longer a new zone, and creatures we've hidden are left alone. Sightings like these already
    saved are cleared when you log in
- Data since 1.60.1.36:
  - 12 new tames (169 in all)
  - 0 new creatures (765 in all)
  - 0 new sightings
  - 4 new ability tames
  - 2 new attack speeds
  - 0 new levels
  - 0 new zones
  - 9 new looks (164 in all)

**Still missing** (as of this release):

- 130 of 765 creatures have no known attack speed, 73 no level and 56 no zone (147 have no map points)

## [1.60.1.36] - 2026-11-05

- First off, thank you! The number of people downloading, using, taming and uploading has been phenomenal! The hunter community is strong! I'm going to try and push daily updates with all the valuable data everyone's been helping collect! Happy taming and safe leveling! - TSL
- **Pet Profile**: click a creature's name anywhere in the window (the creature lists, Collected Data, and the Stable
  tab's new Tamed From) to open its profile: its 3D model, family, level, attack speed, zone, verified tame, the
  abilities it teaches and its looks, with its Map button. Click its family, an ability or a look to see it on its
  own tab, and **Back** returns to where you were  
- Data since 1.60.1.34:
  - 9 new tames (157 in all)
  - 10 new creatures (765 in all)
  - 0 new sightings
  - 2 new ability tames
  - 2 new attack speeds
  - 0 new levels
  - 0 new zones

**Still missing** (as of this release):

- 132 of 765 creatures have no known attack speed, 73 no level and 56 no zone (147 have no map points)

## [1.60.1.34] - 2026-11-04

- Looks: the tab now sits below Trainers (unless you have put your tabs in an order of your own), and the Stand, Walk,
  Run and Attack buttons under the model are gone for now. Right-drag the model to move it around its frame.
  The model now sits at the top of the details, with its hint under it
- Unique Abilities: a rank nobody has found on a tameable beast yet says so, with a button to its pet bounty (the
  likeliest beasts to have it). The Bounties tab's "Missing Normal" is now "Missing Normals", and the creature lists
  are headed "Tameable beasts"
- Reminder: you can put the side tabs in any order you like. Hold a tab for a moment, then drag it up or down the
  column (saved for each character; Options can reset it)
- Data: no changes since 1.60.1.30 (755 creatures, 148 verified by a tame)

**Still missing** (as of this release):

- 134 of 755 creatures have no known attack speed, 73 no level and 56 no zone (137 have no map points)

## [1.60.1.32] - 2026-11-01

- Looks: clearer names for the looks borrowed from other creatures (Vuldren, Shriekling, Shrieker, Prideclaw,
  Galestrider, Frost, Dark Diamond), and a family's own unnamed look is named after the family ("Bat")
- Collect Mode notes what Tame Beast tells you: a creature TrueshotLodge does not list yet is recorded as tameable as
  soon as the channel starts (even if you cancel it), and one it lists is recorded when the game answers "Creature not
  tameable". Either one prints a message and is listed under **Tame Beast Checks** on the Collected Data tab; upload
  your file and we check it. A creature the website has marked Not tameable is known to the addon too
- Data: no changes since 1.60.1.30 (755 creatures, 148 verified by a tame)

**Still missing** (as of this release):

- 134 of 755 creatures have no known attack speed, 73 no level and 56 no zone (137 have no map points)

## [1.60.1.30] - 2026-10-31

- **Looks**: a new tab with every look each pet family comes in (the beasts that look alike: the same model and skin, whatever their size), as on TrueshotLodge.com/looks. Select a look to see it in 3D (drag to turn it, scroll to zoom, and its Stand, Walk, Run and Attack animations where the game client can play them) with every creature that has it and their Map buttons. A look in gold has only one creature. The Zone and Level filters and the search work here too
- Look names no longer carry the numbers from the game's file names ("Brown", not "Brown01")
- Data: 3 more creatures verified by a tame (148 in all): Plainstrider, Elder Plainstrider and Prairie Stalker;
  Ghostfang's attack speed is known; 6 entries that are not tameable beasts were removed (among them Cooking Bear,
  Skinning Bear and Cooking Wolf)

**Still missing** (as of this release):

- 134 of 755 creatures have no known attack speed, 73 no level and 56 no zone (137 have no map points)

## [1.60.1.28] - 2026-10-22

- **Final Release before Live!!!**
- **Pet Ability Tooltips**: a pet ability's own tooltip (in the spellbook, on the pet bar, in Beast Training, in chat
  links) shows the pet level it needs and its training point cost
- Options: a new **Tooltips** group with Pet Tooltips (was NPC Tooltips, under General) and Pet Ability Tooltips, each
  on by default
- Unique, Common and Passive Abilities: **Learnable By** is a row of every family's icon at the top of the
  ability's details, the families that cannot learn it greyed out (hover one for its name)

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
- Library Dependency Updates and Attribution  
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
- TODO: Add multi-language support on the website.
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
