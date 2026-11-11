local _, Addon = ...
local Collector = Addon:GetModule("Collector")
local DB = Addon:GetModule("DB")

-- Collects data about creatures seen around the player into
-- `DB.collected.creatures` (SavedVariables), keyed by npc id. Enable with
-- the Collect Mode option. Upload the saved file (WTF/Account/<account>/
-- SavedVariables/TrueshotLodge.lua) on the website's collector page to compare it
-- with the database.

local SAMPLE_PRECISION = 100 -- Round positions to 1/100th of a percent.

local frame = CreateFrame("Frame")

local function round(n)
  return math.floor(n * SAMPLE_PRECISION + 0.5) / SAMPLE_PRECISION
end

-- Player position, used as an approximation of where the creature is.
local function getObserverPosition()
  local mapId = C_Map.GetBestMapForUnit("player")
  if not mapId then return end
  local pos = C_Map.GetPlayerMapPosition(mapId, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return mapId, round(x * 100), round(y * 100)
end

-- The zone's uiMapID for the player (the same ids as `ui_map_id` in the npc
-- data, e.g. 1413 for The Barrens). Sub-maps such as caves and micro maps are
-- walked up to their parent zone.
local function getZoneMapId()
  local mapId = C_Map.GetBestMapForUnit("player")
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
  local info = mapId and C_Map.GetMapInfo(mapId)
  while info and zoneType and info.mapType > zoneType and info.parentMapID
      and info.parentMapID > 0 do
    mapId = info.parentMapID
    info = C_Map.GetMapInfo(mapId)
  end
  return mapId
end

-- Whether a creature is close enough for the zone you are in to be its zone too: within about 28 yards (the game's
-- Follow range). Nameplates show creatures up to about 40 yards away, so one across a zone border (Durotar's raptors
-- seen from the Barrens bank of the Southfury, say) would otherwise be credited to the zone you stand in. When the
-- game will not say (it can refuse in combat), it is not near: a later sighting closer by records the zone.
local function nearYou(unit)
  local ok, near = pcall(CheckInteractDistance, unit, 4)
  near = ok and Addon:Plain(near)
  return near ~= nil and near ~= false
end

-- The player's position on the zone's map (getZoneMapId: the map the website's creature map points are on), not on a
-- cave's or a city district's own map. For a tame: Tame Beast's short range puts the hunter next to the beast, so it
-- is close to where the beast was.
local function getZonePosition()
  local zoneId = getZoneMapId()
  if not zoneId then return end
  local pos = C_Map.GetPlayerMapPosition(zoneId, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return zoneId, round(x * 100), round(y * 100)
end

-- Called when something new was recorded (the window's Collected Data tab refreshes on it).
Collector.version = 0 -- Counts every change to the collected data; the window's tab polls it.

local function changed()
  Collector.version = Collector.version + 1
  if Collector.onChange then Collector.onChange() end
end

-- For entries other TrueshotLodge users shared (src/share.lua adds them to the collected data).
function Collector:NotifyChanged()
  changed()
end

-- Shares an entry with other TrueshotLodge users (src/share.lua; only while collecting).
local function share(kind, entry)
  local Share = Addon:GetModule("Share")
  if Share.Send then Share:Send(kind, entry) end
end

-- A creature's model (its display id), read off the unit: the game draws it in a model frame of ours, too small to see,
-- and says which display it drew. nil when this client cannot tell (or not yet: the model can still be loading, and a
-- later sighting tries again). The website adds it to the creature's looks, so a new creature gets its 3D model and
-- picture without waiting for Wowhead.
local displayReader
local function UnitDisplayId(unit)
  if not displayReader then
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    if not (ok and model and model.GetDisplayInfo) then
      displayReader = false
      return nil
    end
    model:SetSize(1, 1)
    model:SetAlpha(0)
    model:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- (off the screen's corner)
    displayReader = model
  end
  if displayReader == false then return nil end
  local ok = pcall(displayReader.SetUnit, displayReader, unit)
  local readOk, display = pcall(displayReader.GetDisplayInfo, displayReader)
  pcall(displayReader.ClearModel, displayReader)
  display = ok and readOk and Addon:Plain(display) or nil
  return (type(display) == "number" and display > 0) and display or nil
end

-- The creatures that have a look in the addon's data (data/Looks.lua): a model read off one of the others is news.
local withLook
local function HasLook(id)
  if not withLook then
    withLook = {}
    for _, looks in pairs(Addon.TameableLooks or {}) do
      for _, look in ipairs(looks) do
        for _, npcId in ipairs(look.npcs or {}) do withLook[npcId] = true end
      end
    end
  end
  return withLook[tonumber(id) or 0] == true
end

-- UnitClassification() => the data's classification text (nil: a plain creature), as in the website's pets table.
local CLASSIFICATIONS = { elite = "Elite", rare = "Rare", rareelite = "Rare Elite", worldboss = "Boss" }
-- (the Collected Data tab shows a sighting's classification next to the data's)
Collector.Classification = function(classification) return CLASSIFICATIONS[classification] end

-- Whether a world map the creature was seen on is a zone the data does not link it to yet. Only a map that is a zone
-- of its own counts (data/NPCs.lua's TameableZoneMaps): a continent (as in a dungeon, which shows the continent's map)
-- or a map the website has no zone for links nothing on an upload, so it is no news.
local function newZone(npc, mapId)
  local zoneId = Addon.TameableZoneMaps and Addon.TameableZoneMaps[tonumber(mapId) or 0]
  if not zoneId then return false end
  for _, linked in ipairs(npc.zones or {}) do
    if linked == zoneId then return false end
  end
  return true
end
Collector.NewZone = newZone

-- Whether a wild attack speed is news: only when the data has no speed at all. A creature's own swing is often not its
-- pet's (read about a fifth slower when it is slowed in a fight, and unrelated for Forever's new creatures), so the
-- website lets a wild sighting fill an empty speed but never change one; only a tame does.
local function newSpeed(npc, speed)
  return speed ~= nil and not npc.speed
end
Collector.NewSpeed = newSpeed

-- Whether the addon's data (data/NPCs.lua, from the website's database) already holds everything a sighting says,
-- compared as the website's upload page does (an upload's Commit changes only what this finds): the creature is in it
-- (or we hid it), with the same family and classification, every level seen inside its level range, the same attack
-- speed, and each zone seen linked. Such a sighting tells the website nothing new, so it is neither kept nor sent to
-- other players (Collector:Record). A sighting with anything the data lacks or has differently is kept and sent.
local function inData(c)
  if Addon.TameableHidden and Addon.TameableHidden[tonumber(c.id) or 0] then return true end
  local npc = Addon.TameableNPCs and Addon.TameableNPCs[c.id]
  if not npc then return false end
  if npc.family ~= c.family then return false end
  if npc.class ~= CLASSIFICATIONS[c.classification] then return false end
  -- Levels: the data must have them (a level the data lacks is news), and the sightings lie inside its range.
  if c.level_min or c.level_max then
    local low, high = npc.min, npc.max or npc.min
    if not (low and high) then return false end
    if (c.level_min and c.level_min < low) or (c.level_max and c.level_max > high) then return false end
  end
  -- Attack speed, to a tenth as the website compares it (a speed hidden in combat is not compared).
  if newSpeed(npc, c.mainhand_speed) then return false end
  for mapId in pairs(c.zones or {}) do
    if newZone(npc, mapId) then return false end
  end
  -- Its model: news for a creature with no look in the data yet.
  if c.display_id and not HasLook(c.id) then return false end
  return true
end

-- Shares a creature sighting unless the data already holds all of it (see inData).
local function shareCreature(c)
  if inData(c) then
    return Addon:Debug("collector: not sharing", c.name, "(" .. c.id .. "): the data already has it")
  end
  share("creature", c)
end
Collector.InData = inData -- (data sharing leaves out received sightings the data already holds, too)
Collector.HasLook = HasLook -- (the Collected Data tab marks a model read off a creature without a look)

-- Shared trainers collected before they were named from their id (their name and title were in the sender's
-- language): named again, in yours, as a shared trainer is now. Returns how many changed.
function Collector:RenameSharedTrainers()
  local renamed = 0
  for id, r in pairs(DB.collected.trainers or {}) do
    if type(r) == "table" and r.shared_by then
      local name, title = Addon:TrainerNameAndTitle(r.id or id)
      if (name and name ~= r.name) or (title and title ~= r.title) then
        r.name, r.title = name or r.name, title or r.title
        renamed = renamed + 1
      end
    end
  end
  if renamed > 0 then
    Addon:Debug("collector:", renamed, "shared trainers named in your language")
    changed()
  end
  return renamed
end

-- Tame Beast's verdicts (tame checks, below). A verdict is news when the data says otherwise: a creature the data does
-- not list that can be tamed, or one it lists that cannot. ("Lists" means shown as tameable: a creature the website has
-- marked Not tameable (its data's not_tameable) counts as not listed.)
local TAMEABLE, NOT_TAMEABLE = "tameable", "not_tameable"

local function tameCheckIsNews(id, result)
  local npc = Addon:GetNPC(id)
  local listed = npc ~= nil and not npc.not_tameable
  return listed ~= (result == TAMEABLE)
end

-- Whether a tame still tells the website something (as its upload page compares a tame): the creature is not in the
-- data, or is listed as not tameable, or has no tame recorded yet; the tame would name the hunter of an anonymous one,
-- or is from an earlier day than the one recorded; its attack speed is not yet confirmed by a tame, or differs; or its
-- pet came with an ability rank the data does not list for the creature. When in doubt, it is kept.
local function tameIsNews(t)
  local npc = Addon:GetNPC(t.npc_id)
  if not npc or npc.not_tameable or not npc.tamed then return true end
  if t.tamed_by and not npc.tamed_by then return true end
  if type(t.tamed) == "number" and date("%Y-%m-%d", t.tamed) < npc.tamed then return true end
  if t.attack_speed and (not npc.speed_tamed or not npc.speed or math.abs(t.attack_speed - npc.speed) > 0.05) then
    return true
  end
  for _, spell in ipairs(t.spells or {}) do
    if not spell.passive and spell.spell_id then
      local listed = false
      for _, entry in ipairs(npc.taught or {}) do
        local rank = entry.ability.ranks[entry.rankIndex]
        if rank and rank.spell_id == spell.spell_id then listed = true end
      end
      if not listed then return true end
    end
  end
  return false
end
Collector.TameIsNews = tameIsNews -- (data sharing leaves out received tames that tell the data nothing new, too)

-- The discount on a trainer's prices by your standing with the trainer (UnitReaction: 4 Neutral ... 8 Exalted), in
-- percent: the same table the website uses (CollectorCommit::REPUTATION_DISCOUNTS).
local DISCOUNTS = { [4] = 0, [5] = 5, [6] = 10, [7] = 15, [8] = 20 }

-- Whether a price paid is the data's full price less the discount of your standing (any standing's when it is not
-- known, as for a shared trainer), to a copper of rounding. A price the data does not have never matches.
local function priceMatches(paid, full, reaction)
  if not full then return false end
  local discounts = DISCOUNTS[reaction or 0] and { DISCOUNTS[reaction] } or { 0, 5, 10, 15, 20 }
  for _, discount in ipairs(discounts) do
    if math.abs(math.floor(full * (100 - discount) / 100 + 0.5) - paid) <= 1 then return true end
  end
  return false
end

-- The number in a rank's text ("Rank 3" -> 3), or nil.
local function rankNumber(text)
  return tonumber(tostring(text or ""):match("%d+"))
end

-- Whether a trainer window entry (a pet trainer's, or Beast Training's) tells the data something: a spell it does not
-- have, another rank, or (a pet trainer's, `price`) a price that is not the data's. An entry without a spell id can be
-- committed to nothing.
local function serviceIsNews(service, price, reaction)
  if not service.spell_id then return false end
  local ability = Addon:AbilityOfSpell(service.spell_id)
  if not ability then return true end
  local rank = rankNumber(service.rank)
  if rank and ability.rank and rank ~= ability.rank then return true end
  return price and service.cost ~= nil and not priceMatches(service.cost, ability.trainer_cost, reaction) or false
end

-- Whether a recorded pet trainer tells the website something: a trainer the data does not have, or one of its pet
-- abilities differing (serviceIsNews), as the website's upload page compares them. (Every trainer in the data and every
-- one recorded is titled "Pet Trainer", so the title never differs.)
local function trainerIsNews(trainer)
  local known = Addon.TameableTrainers and Addon.TameableTrainers[tonumber(trainer.id) or 0]
  if not known then return true end
  for _, service in ipairs(trainer.services or {}) do
    if service.pet_ability and serviceIsNews(service, true, trainer.reaction) then return true end
  end
  return false
end

-- Whether a Beast Training entry tells the website something (its number is not compared: at a stable master it is
-- training points).
local function trainingIsNews(entry)
  return serviceIsNews(entry, false)
end
Collector.TrainingIsNews = trainingIsNews -- (data sharing leaves out received entries the data already has, too)

-- At load (each login and /reload): drops the records the addon's data now holds, which would only be uploaded and
-- reviewed again for nothing (a new release brings in what players found): the wild sightings it holds completely
-- (inData), the Tame Beast verdicts it agrees with, the tames that tell it nothing new (tameIsNews), and the pet
-- trainers and Beast Training entries it agrees with (trainerIsNews, trainingIsNews). Returns how many went.
function Collector:PurgeKnown()
  local removed = 0
  local tames = DB.collected and DB.collected.tames
  if type(tames) == "table" then
    -- (a list: walked backwards, so removing one does not skip the next)
    for i = #tames, 1, -1 do
      local t = tames[i]
      if type(t) == "table" and t.npc_id and not tameIsNews(t) then
        table.remove(tames, i)
        removed = removed + 1
      end
    end
  end
  local checks = DB.collected and DB.collected.tame_checks
  if type(checks) == "table" then
    for key, check in pairs(checks) do
      if type(check) == "table" and not tameCheckIsNews(check.npc_id or key, check.result) then
        checks[key] = nil
        removed = removed + 1
      end
    end
  end
  local trainers = DB.collected and DB.collected.trainers
  if type(trainers) == "table" then
    for key, trainer in pairs(trainers) do
      if type(trainer) == "table" and trainer.id and not trainerIsNews(trainer) then
        trainers[key] = nil
        removed = removed + 1
      end
    end
  end
  local book = DB.collected and DB.collected.beast_training
  if type(book) == "table" then
    for key, entry in pairs(book) do
      if type(entry) == "table" and not trainingIsNews(entry) then
        book[key] = nil
        removed = removed + 1
      end
    end
  end
  local creatures = DB.collected and DB.collected.creatures
  if type(creatures) ~= "table" then return removed end
  for key, c in pairs(creatures) do
    if type(c) == "table" and c.id and inData(c) then
      creatures[key] = nil -- (clearing a field while traversing is allowed)
      removed = removed + 1
    end
  end
  if removed > 0 then
    Addon:Debug("collector:", removed, "sighting(s), tame(s), Tame Beast verdict(s), trainer(s) and Beast Training entries the addon's data now holds were removed from the collected data")
  end
  return removed
end

-- Creatures already reported as ignored this session (npc id), so debug mode says so once, not on every scan.
local ignored = {}

-- Sightings the data already holds completely (inData), this session: not kept in the collected data. Each waits here,
-- and is kept (and shared) as soon as a later sighting of it adds something the data lacks (another level or zone).
local waiting = {}

-- When each creature's model was last asked for (npc id -> GetTime()), so one whose model the game has not loaded yet
-- is asked again now and then, not on every scan.
local DISPLAY_RETRY = 5 -- seconds
local displayAsked = {}

function Collector:Record(unit)
  if not (DB.global and DB.global.collect) then return end
  if not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return end

  local guid = UnitGUID(unit)
  if not guid then return end
  local unitType, _, _, instanceId, _, id = strsplit("-", guid)
  if unitType ~= "Creature" or not id then return end
  if Addon.IGNORED_NPC_IDS[tonumber(id)] then return end

  local creatures = DB.collected.creatures
  if not creatures then
    creatures = {}
    DB.collected.creatures = creatures
  end

  -- Each creature id is collected once. Later sightings only widen the level
  -- range and add the zone.
  local c = creatures[id] or waiting[id]
  if c then
    -- What changed, made only when something did: a creature in view is seen again on every scan, and most of
    -- those sightings change nothing.
    local updates
    if c.shared_by then
      -- Shared by another user, and now seen yourself: it is your own record from here on.
      c.shared_by = nil
      updates = {}
      updates[#updates + 1] = "seen yourself (was shared)"
    end
    local level = Addon:Plain(UnitLevel(unit)) -- (secret in combat: not compared or saved)
    if level and level > 0 then
      if not c.level_min or level < c.level_min then
        c.level_min = level
        updates = updates or {}
        updates[#updates + 1] = "lowest level " .. level
      end
      if not c.level_max or level > c.level_max then
        c.level_max = level
        updates = updates or {}
        updates[#updates + 1] = "highest level " .. level
      end
    end
    local zoneId = nearYou(unit) and getZoneMapId() -- (only from close by: see nearYou)
    if zoneId then
      c.zones = c.zones or {}
      if not c.zones[zoneId] then
        c.zones[zoneId] = true
        updates = updates or {}
        updates[#updates + 1] = "new zone " .. zoneId
      end
    end
    -- Its model, when not read yet (a record from before the addon read models, or one still loading).
    if not c.display_id and (GetTime() - (displayAsked[id] or 0)) > DISPLAY_RETRY then
      displayAsked[id] = GetTime()
      c.display_id = UnitDisplayId(unit)
      if c.display_id then
        updates = updates or {}
        updates[#updates + 1] = "model " .. c.display_id
      end
    end
    -- Only a change is reported: a creature in view is seen again on every scan.
    if updates and waiting[id] then
      -- One the data held completely: kept once it adds something the data lacks.
      if inData(c) then return end
      waiting[id] = nil
      creatures[id] = c
      Addon:Debug("collector: recorded", c.name, "(" .. id .. ") now that it differs from the data:", table.concat(updates, ", "))
      changed()
      share("creature", c)
      return
    end
    if updates then
      Addon:Debug("collector: updated", c.name, "(" .. id .. "):", table.concat(updates, ", "))
      changed()
      if not c.shared_by then shareCreature(c) end
    end
    return
  end

  -- Only the beasts of the pet families in the data (not demons, humanoids or critters, nor families that are not
  -- out yet), matched by family id so that every client language counts. The English name is saved. One already
  -- found to be none of those is passed over before asking the game again (in a city, most nameplates are).
  if ignored[id] then return end
  local family, familyId, familyText = Addon:UnitFamily(unit)
  if not family then
    ignored[id] = true -- (reported once: the next sighting stops at the check above)
    Addon:Debug("collector: ignored", UnitName(unit), "(" .. id .. "):",
      familyText and ("family " .. familyText .. " is not in the data") or "no pet family")
    return
  end
  local creatureType, creatureTypeId = Addon:UnitCreatureType(unit)

  -- Every unit value goes through Addon:Plain: in combat the game can hand out "secret" values, which cannot be
  -- compared or saved (the saved file holds nil for them) and would stop the records from being signed at logout.
  local Plain = function(value) return Addon:Plain(value) end
  local level = Plain(UnitLevel(unit))
  if not (level and level > 0) then level = nil end
  local zoneId = nearYou(unit) and getZoneMapId() or nil -- (only from close by: see nearYou)

  local mainhand, offhand = UnitAttackSpeed(unit)
  mainhand, offhand = Plain(mainhand), Plain(offhand)
  c = {
    id = tonumber(id),
    collected = time(),
    name = Plain(UnitName(unit)) or Addon:NPCName(id),
    family = family,
    family_id = familyId,
    creature_type = creatureType,
    creature_type_id = creatureTypeId,
    classification = Plain(UnitClassification(unit)),
    level_min = level,
    level_max = level,
    zones = zoneId and { [zoneId] = true } or {},
    power_type = Plain((UnitPowerType(unit))),
    health_max = Plain(UnitHealthMax(unit)),
    power_max = Plain(UnitPowerMax(unit)),
    sex = Plain(UnitSex(unit)),
    mainhand_speed = mainhand,
    offhand_speed = offhand,
    instance_id = tonumber(instanceId),
    display_id = UnitDisplayId(unit),
  }
  displayAsked[id] = GetTime()

  local mapId, x, y = getObserverPosition()
  if mapId then
    c.map_id = mapId
    c.x = x
    c.y = y
    c.ui_map_id = zoneId -- Zone of this first position (nil when the creature was too far off to tell).
    c.subzone = GetSubZoneText()
  end

  -- Nothing the data lacks: not kept (it waits, in case a later sighting of it adds something).
  if inData(c) then
    waiting[id] = c
    return Addon:Debug("collector: not recording", c.name, "(" .. id .. "): the data already has it")
  end

  creatures[id] = c
  share("creature", c)
  Collector:NotifyNew("sighting", c)
  Addon:Debug("collector: recorded", c.name, "(" .. id .. ")", family, "level " .. tostring(level),
    c.classification or "", "speed " .. tostring(mainhand), "zone " .. tostring(zoneId), "model " .. tostring(c.display_id))
  changed()
end

function Collector:Count()
  local n = 0
  for _ in pairs(DB.collected.creatures or {}) do n = n + 1 end
  return n
end

function Collector:Clear()
  DB.collected.creatures = {}
  DB.collected.pets = nil -- Pets are no longer collected; this clears what an earlier version saved.
  DB.collected.beast_training = {}
  DB.collected.trainers = {}
  DB.collected.tames = {}
  DB.collected.tame_checks = {}
end

-- ============================================================================
-- Pet trainers
-- ============================================================================

-- The npc being talked to (the "npc" unit while a trainer or vendor window is open): its id and unit token. Only
-- that unit counts, never the target: the Beast Training window is opened with no npc at all (often with a beast
-- targeted). A beast is never a trainer.
local function interactionNpc()
  local unit = "npc"
  if not UnitExists(unit) or UnitIsPlayer(unit) then return end
  if Addon:UnitIsBeast(unit) or Addon:Plain((UnitCreatureFamily(unit))) then return end
  local unitType, _, _, _, _, id = strsplit("-", UnitGUID(unit) or "")
  if unitType == "Creature" and id then return tonumber(id), unit end
end

-- Whether an npc is a pet trainer, the only trainers recorded (a stable master or another trainer can open the same
-- trainer window). One is in the trainer data (by npc id, so in any language), or titled exactly "Pet Trainer", in
-- English, as the website takes them. Anything else is left out, so uploads carry no other trainers' chatter: no
-- stable masters, no "Wolf Pet Trainer" and the like, and no unknown trainer whose title is in another language.
local function isPetTrainer(id, title)
  if Addon.TameableTrainers and Addon.TameableTrainers[tonumber(id) or 0] then return true end
  return type(title) == "string" and title:match("^%s*(.-)%s*$"):lower() == "pet trainer"
end
Collector.IsPetTrainer = isPetTrainer -- (shared trainers are checked the same way, in share.lua)

-- Whether the game client runs in English. Beast Training is collected only there, so its names and ranks reach the
-- website in English, as the website takes them.
local function englishClient()
  local locale = GetLocale and GetLocale() or "enUS"
  return locale == "enUS" or locale == "enGB"
end
Collector.EnglishClient = englishClient -- (shared Beast Training is only taken there too, in share.lua)

-- On a client in another language, takes out the Beast Training an earlier version collected there.
local function dropForeignTraining()
  if englishClient() or not DB.collected then return end
  if next(DB.collected.beast_training or {}) then
    DB.collected.beast_training = {}
    Addon:Debug("collector: Beast Training is collected on English clients only; cleared it")
  end
end

-- Takes out "trainers" an earlier version recorded from the Beast Training window: the beast that was targeted
-- (a tameable creature, or one collected as a creature), not a trainer.
local function dropBeastTrainers()
  local trainers = DB.global and DB.collected.trainers
  if not trainers then return end
  for id, trainer in pairs(trainers) do
    local npc = tonumber(id)
    if (Addon.TameableNPCs and Addon.TameableNPCs[npc]) or (DB.collected.creatures and DB.collected.creatures[tostring(npc)]) then
      trainers[id] = nil
      Addon:Debug("collector: removed", tostring(npc), "from the trainers: it is a beast, not a trainer")
    elseif type(trainer) == "table" and not isPetTrainer(id, trainer.title) then
      trainers[id] = nil
      Addon:Debug("collector: removed", tostring(trainer.name), "from the trainers: a", trainer.title, "is no pet trainer")
    end
  end
end

-- The npc's title ("Pet Trainer", "Beast Trainer", ...), the second line of its tooltip.
local function npcTitle(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  local line = ok and data and data.lines and data.lines[2]
  return line and line.leftText or nil
end

-- Talking to a pet trainer (a trainer window that teaches pet abilities) records the trainer and everything the
-- window shows: who and where they are, and each entry with its price, level and status.
function Collector:RecordTrainer()
  if not (DB.global and DB.global.collect) then return end

  local Training = Addon:GetModule("Training")
  local services = Training:ReadServices(false)
  local teachesPets = false
  for _, service in ipairs(services) do
    if Training:IsPetAbility(service.name) then teachesPets = true break end
  end
  if not teachesPets then return end -- Some other trainer.

  local id, unit = interactionNpc()
  if not id then return Addon:Debug("collector: trainer window open, but no npc to record") end
  -- Only pet trainers (a stable master, for one, opens a trainer window that lists pet abilities too).
  local title = npcTitle(unit)
  if not isPetTrainer(id, title) then
    return Addon:Debug("collector: not recording", tostring(UnitName(unit)), "-", title, "is no pet trainer")
  end

  local trainers = DB.collected.trainers
  if not trainers then
    trainers = {}
    DB.collected.trainers = trainers
  end
  local now = time()
  local trainer = trainers[id] or { first_seen = now }
  trainers[id] = trainer

  trainer.id = id
  trainer.name = Addon:Plain(UnitName(unit)) or trainer.name or Addon:NPCName(id)
  trainer.title = title or trainer.title
  trainer.unconfirmed = nil -- (an earlier version marked trainers titled in another language; none are kept now)
  -- Your standing with the trainer (4 Neutral, 5 Friendly ... 8 Exalted): prices are lower at Friendly and up, so the
  -- website works the full price back from it.
  trainer.reaction = Addon:Plain(UnitReaction(unit, "player")) or trainer.reaction
  trainer.level = Addon:Plain(UnitLevel(unit)) or trainer.level
  trainer.faction = UnitFactionGroup and Addon:Plain((UnitFactionGroup(unit))) or trainer.faction
  trainer.ui_map_id = getZoneMapId()
  local mapId, x, y = getObserverPosition()
  if mapId then
    trainer.map_id, trainer.x, trainer.y = mapId, x, y -- The player's position: the trainer is within a few yards.
  end
  trainer.subzone = GetSubZoneText()
  trainer.last_seen = now

  -- Everything in the window, as it is now (what is offered changes with the pet and its level).
  local entries = {}
  for _, service in ipairs(services) do
    entries[#entries + 1] = {
      name = service.name,
      rank = service.rank ~= "" and service.rank or nil,
      spell_id = service.spell_id,
      category = service.category,
      cost = service.cost,
      required_level = service.level_req,
      icon = service.icon,
      pet_ability = Training:IsPetAbility(service.name) or nil,
    }
  end
  trainer.services = entries
  trainer.shared_by = nil -- seen yourself now
  -- A trainer the data already has, with the same title, prices and ranks, tells the website nothing: not kept, and
  -- not shared.
  if not trainerIsNews(trainer) then
    trainers[id] = nil
    changed()
    return Addon:Debug("collector: not recording", trainer.name, "(" .. id .. "): the data already has it as it is")
  end
  share("trainer", trainer)
  for _, service in ipairs(entries) do
    share("service", {
      trainer_id = id, spell_id = service.spell_id, name = service.name, rank = service.rank, cost = service.cost,
      required_level = service.required_level, category = service.category, pet_ability = service.pet_ability,
    })
  end

  Addon:Debug("collector: recorded pet trainer", trainer.name, "(" .. id .. ")", trainer.title or "", #entries,
    "entries, zone " .. tostring(trainer.ui_map_id))
  changed()
end

-- Anything the same trainer sells (the vendor window), kept with the trainer.
function Collector:RecordMerchant()
  if not (DB.global and DB.global.collect) then return end
  local id = interactionNpc()
  local trainer = id and DB.collected.trainers and DB.collected.trainers[id]
  if not trainer then return end -- Only vendors that were recorded as pet trainers.

  local get = GetMerchantItemInfo or (C_MerchantFrame and C_MerchantFrame.GetItemInfo)
  if not (get and GetMerchantNumItems) then return end
  local items = {}
  for index = 1, GetMerchantNumItems() do
    local ok, a, b, c, d, e, f, g = pcall(get, index)
    if ok and a then
      local name, icon, price, quantity, available, usable, extended
      if type(a) == "table" then
        name, icon, price, quantity, available, usable, extended = a.name, a.iconFileID or a.texture, a.price,
          a.stackCount, a.numAvailable, a.isUsable, a.hasExtendedCost
      else
        name, icon, price, quantity, available, usable, extended = a, b, c, d, e, f, g
      end
      local link = GetMerchantItemLink and GetMerchantItemLink(index)
      items[#items + 1] = {
        name = name, icon = icon, price = price, quantity = quantity, available = available,
        usable = usable or nil, extended_cost = extended or nil,
        item_id = link and tonumber(link:match("item:(%d+)")) or nil,
      }
    end
  end
  trainer.merchant = items
  Addon:Debug("collector: recorded", #items, "items sold by", trainer.name, "(" .. id .. ")")
  changed()
end

-- ============================================================================
-- Beast training window
-- ============================================================================

function Collector:RecordBeastTraining()
  if not (DB.global and DB.global.collect) then return end
  if InCombatLockdown() then return end
  -- English clients only: the window's names and ranks are in the client's language.
  if not englishClient() then return end

  -- Beast Training is the class trainer window on this client. Only pet
  -- abilities from the data are read, so the normal class trainer isn't
  -- recorded.
  local book = DB.collected.beast_training
  if not book then
    book = {}
    DB.collected.beast_training = book
  end

  local services = Addon:GetModule("Training"):ReadServices(true)
  local now = time()
  for _, service in ipairs(services) do
    local rank = service.rank
    local key = service.name .. "|" .. tostring(rank or "")
    local entry = book[key] or {}
    entry.families = nil -- Trainer purchases are the same for every family.

    entry.name = service.name
    entry.rank = rank ~= "" and rank or nil
    entry.spell_id = service.spell_id or entry.spell_id
    entry.category = service.category
    entry.cost = service.cost
    entry.required_level = service.level_req
    entry.last_seen = now
    entry.shared_by = nil -- seen yourself now
    -- An ability the data already has at this rank tells the website nothing: not kept, and not shared.
    if trainingIsNews(entry) then
      book[key] = entry
      share("training", entry)
    else
      book[key] = nil
    end

  end

  local count = #services
  if count > 0 then
    Addon:Debug("collected beast training", count, "entries")
  end
end

-- ============================================================================
-- Events
-- ============================================================================

-- Runs `fn(...)`, reporting errors in debug mode instead of raising them.
-- Unit info may be "secret" on newer clients.
local function safely(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then Addon:Debug(name .. " error:", err) end
end

-- Debounce for events that fire in bursts. `fn` is a method of Collector.
local pending = {}
local function schedule(key, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(1, function()
    pending[key] = nil
    safely(key, fn, Collector)
  end)
end

-- ============================================================================
-- Taming
-- ============================================================================

-- A tamed beast becomes your pet, and a pet's GUID only carries the generic hunter pet id (165189), so the creature
-- is read from your target when the Tame Beast channel starts: its GUID still has its own npc id then. The tame is
-- confirmed when a new pet appears (UNIT_PET) soon after with the creature's family and level; a new pet is named
-- after its family ("Boar"), not the creature. You cannot tame with a pet out, so that is the new one. The pet is then read a few times over the next seconds (its spellbook fills in after it
-- appears): the abilities and ranks it came with, its passives (Faster Attack, ...) and its attack speed. Each tame is
-- kept in `DB.collected.tames`, newest last.

local TAME_BEAST = 1515 -- Tame Beast. Also matched by name, in case Forever's spell id differs.
local TAME_WAIT = 15 -- seconds after the channel ends to wait for the pet
local CHANNEL_LIMIT = 40 -- seconds after it starts, in case the channel's end is never seen
local READ_DELAYS = { 0.5, 1.5, 3, 6 } -- seconds after the pet appears to read it

local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function isTameSpell(spellId)
  if not spellId then return false end
  if spellId == TAME_BEAST then return true end
  local name = spellName(spellId)
  return name ~= nil and name == spellName(TAME_BEAST)
end

-- The pet's spellbook: { { spell_id, name, rank, passive, slot } }. Entries without a spell (Attack, Follow, ...)
-- are left out.
local function readPetSpellbook()
  local spells = {}
  local count
  if C_SpellBook and C_SpellBook.HasPetSpells then
    count = C_SpellBook.HasPetSpells()
  elseif HasPetSpells then
    count = HasPetSpells()
  end
  if not count or count == 0 then return spells end

  local petBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
  local bookType = BOOKTYPE_PET or "pet"
  for slot = 1, count do
    local name, subName, spellId, passive
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and petBank then
      local info = C_SpellBook.GetSpellBookItemInfo(slot, petBank)
      if info then
        name, subName, spellId, passive = info.name, info.subName, info.spellID, info.isPassive
      end
    elseif GetSpellBookItemName then
      name, subName = GetSpellBookItemName(slot, bookType)
      local _, id = GetSpellBookItemInfo(slot, bookType)
      -- The old pet spellbook gives an action id: the spell id is in its low 24 bits.
      spellId = id and id % 0x1000000 or nil
      passive = IsPassiveSpell and IsPassiveSpell(slot, bookType) or nil
    end
    if name and spellId and spellId > 0 then
      local rank = subName ~= "" and subName or nil
      if not rank and C_Spell and C_Spell.GetSpellSubtext then rank = C_Spell.GetSpellSubtext(spellId) end
      -- Saved in English whatever the client's language: the data's name and rank for its abilities.
      local ability = Addon:AbilityOfSpell(spellId)
      if ability then name, rank = ability.name, ("Rank %d"):format(ability.rank) else rank = Addon:RankText(rank) end
      spells[#spells + 1] = {
        spell_id = spellId, name = name, rank = rank ~= "" and rank or nil, passive = passive and true or nil, slot = slot,
      }
    end
  end
  return spells
end
Collector.ReadPetSpellbook = readPetSpellbook -- also used by the Stable tab (src/stable.lua)

-- Whether the game lets a creature be tamed, from the hunter's own Tame Beast: the channel starting proves it can be
-- (even when the hunter then cancels it), and the game's "Creature not tameable" error proves it cannot. Kept in
-- `DB.collected.tame_checks` by npc id (the newest verdict), and only when it is news: a creature the data does not
-- list that can be tamed, or one it lists that cannot (tameCheckIsNews). The website shows them on the uploads page.

-- `id`: the target's npc id, when the caller has read it already.
local function recordTameCheck(result, id)
  if not (DB.global and DB.global.collect) or not UnitExists("target") then return end
  if not id then
    local kind, _, _, _, _, guidId = strsplit("-", UnitGUID("target") or "")
    if kind ~= "Creature" or not guidId then return end
    id = guidId
  end
  if not tameCheckIsNews(id, result) then return end -- (what the data says already)

  local checks = DB.collected.tame_checks
  if not checks then
    checks = {}
    DB.collected.tame_checks = checks
  end
  if checks[id] and checks[id].result == result then return end
  local level = Addon:Plain(UnitLevel("target"))
  local family, familyId, familyText = Addon:UnitFamily("target")
  local check = {
    npc_id = tonumber(id),
    name = Addon:Plain(UnitName("target")),
    family = family or familyText,
    family_id = familyId,
    level = level and level > 0 and level or nil,
    classification = Addon:Plain(UnitClassification("target")),
    ui_map_id = getZoneMapId(),
    subzone = GetSubZoneText(),
    result = result,
    collected = time(),
  }
  checks[id] = check
  changed()
  local L = Addon:GetModule("Locale")
  local about = ("|cFF1FA5D1%s|r"):format(check.name or "?")
  print(("|cFF007EA6%s|r: %s"):format(Addon.TITLE,
    (result == TAMEABLE and L.TAME_CHECK_YES_NOTICE or L.TAME_CHECK_NO_NOTICE):format(about)))
  Addon:Debug("collector: tame check", check.name, "(" .. id .. "):", result)
end

-- The game's error for a creature that cannot be tamed, in the client's own language (its global string), else the
-- English text; compared without case, edge spaces or a closing full stop. Worked out once: every UI error is checked.
local function plainError(text) return (text:lower():gsub("^%s+", ""):gsub("[%s%.]+$", "")) end
local NOT_TAMEABLE_ERROR = plainError(SPELL_FAILED_NOT_TAMEABLE or "Creature not tameable")

local function isNotTameableError(message)
  return type(message) == "string" and plainError(message) == NOT_TAMEABLE_ERROR
end

function Collector:UIError(errorType, message)
  -- (the client passes the error's type and its text; older ones only the text)
  local text = type(message) == "string" and message or errorType
  if isNotTameableError(text) then recordTameCheck(NOT_TAMEABLE) end
end

local pendingTame -- the creature being tamed: from the channel's start until its pet appears, or it times out

local function dropTame(tame, why)
  if pendingTame == tame then
    pendingTame = nil
    Addon:Debug("collector: not recording the tame of", tame.name, "(" .. tame.npc_id .. "):", why)
  end
end

function Collector:TameStarted(spellId, castGUID)
  if not (DB.global and DB.global.collect) then return end
  if not UnitExists("target") then return Addon:Debug("collector: Tame Beast started without a target") end
  local kind, _, _, _, _, id = strsplit("-", UnitGUID("target") or "")
  if kind ~= "Creature" or not id then
    return Addon:Debug("collector: Tame Beast started on", UnitName("target"), "but it is not a creature (" .. tostring(kind) .. ")")
  end
  recordTameCheck(TAMEABLE, id) -- (the channel started: it can be tamed, whether or not this tame finishes)

  local level = Addon:Plain(UnitLevel("target"))
  local mapId, x, y = getZonePosition() -- on the zone's map: where the beast is (see getZonePosition)
  local family, familyId, familyText = Addon:UnitFamily("target")
  local tame = {
    npc_id = tonumber(id),
    name = Addon:Plain(UnitName("target")),
    family = family or familyText, -- English when the data knows the family
    family_id = familyId,
    family_text = familyText, -- as the game names it (a new pet is named this): see isTamedPet
    level = level and level > 0 and level or nil,
    classification = Addon:Plain(UnitClassification("target")),
    creature_speed = Addon:Plain((UnitAttackSpeed("target"))),
    tame_spell_id = spellId,
    ui_map_id = getZoneMapId(),
    map_id = mapId, x = x, y = y,
    subzone = GetSubZoneText(),
    cast_guid = castGUID,
    started = GetTime(),
  }
  pendingTame = tame
  Addon:Debug("collector: taming", tame.name, "(" .. tame.npc_id .. ")", tame.family or "no family",
    "level " .. tostring(tame.level), "spell " .. tostring(spellId))
  C_Timer.After(CHANNEL_LIMIT, function() dropTame(tame, "no pet appeared") end)
end

function Collector:TameStopped(failed)
  local tame = pendingTame
  if not tame then return end
  if failed then
    -- Kept: some clients report a stopped channel this way too. A failed tame simply brings no pet.
    tame.failed = true
    return Addon:Debug("collector: the tame of", tame.name, "was interrupted or failed (waiting for a pet anyway)")
  end
  tame.stopped = GetTime()
  Addon:Debug("collector: Tame Beast channel ended on", tame.name, "- waiting for the new pet")
  C_Timer.After(TAME_WAIT, function() dropTame(tame, "no pet appeared") end)
end

-- Reads the tamed pet into its record, if it is still the pet that was tamed.
-- The tames whose abilities are settled (entry -> true): what the pet came with is its first spellbook that has
-- anything in it. Later reads only update its level and attack speed, since anything new by then is what the hunter
-- taught it. Opening Beast Training (the only way to teach a pet) while a tame is still being read settles it too.
local spellsSettled = setmetatable({}, { __mode = "k" })
local reading = setmetatable({}, { __mode = "k" }) -- the tames still being read

function Collector:SettleTameSpells()
  for entry in pairs(reading) do
    if not spellsSettled[entry] then
      spellsSettled[entry] = true
      Addon:Debug("collector: Beast Training opened while reading the tame of", entry.name, "- its abilities are settled")
    end
  end
end

function Collector:ReadTamedPet(entry, last)
  if last then reading[entry] = nil end
  if not (UnitExists("pet") and UnitGUID("pet") == entry.pet_guid) then return end
  local spells = spellsSettled[entry] and (entry.spells or {}) or readPetSpellbook()
  if #spells > 0 then spellsSettled[entry] = true end
  local before = entry.spells and #entry.spells or -1
  entry.pet_level = Addon:Plain(UnitLevel("pet")) or entry.pet_level
  local petFamily, petFamilyId, petFamilyText = Addon:UnitFamily("pet")
  entry.pet_family = petFamily or petFamilyText or entry.pet_family
  entry.pet_family_id = petFamilyId or entry.pet_family_id
  entry.attack_speed = Addon:Plain((UnitAttackSpeed("pet"))) or entry.attack_speed
  if #spells >= math.max(before, 0) then entry.spells = spells end
  entry.reads = (entry.reads or 0) + 1
  if #spells ~= before and (#spells > 0 or last) then
    local names = {}
    for _, spell in ipairs(spells) do
      names[#names + 1] = spell.name .. (spell.rank and (" " .. spell.rank) or "") .. " (" .. spell.spell_id .. ")"
    end
    Addon:Debug("collector:", entry.name, "pet spellbook:", #spells, "spells -", table.concat(names, ", "))
    changed()
  end
  if last then
    share("tame", entry)
    Addon:Debug("collector: recorded tame of", entry.name, "(" .. entry.npc_id .. "):", #(entry.spells or {}),
      "spells, attack speed " .. tostring(entry.attack_speed), "pet level " .. tostring(entry.pet_level))
  end
end

-- Whether the pet out now is the beast being tamed: the same family and level, and named after its family (as a
-- new pet is) or after the creature. An old pet called instead has its own name or level, or another family.
-- (A value the game keeps secret in combat is not checked.)
local function isTamedPet(tame)
  local petName = Addon:Plain(UnitName("pet"))
  local _, _, petFamily = Addon:UnitFamily("pet") -- both compared as the game names them, in the client's language
  local petLevel = Addon:Plain(UnitLevel("pet"))
  if tame.family_text and petFamily and petFamily ~= tame.family_text then return false, "family " .. tostring(petFamily) end
  if petName and petName ~= tame.family_text and petName ~= tame.name then return false, "named " .. tostring(petName) end
  if tame.level and petLevel and petLevel > 0 and petLevel ~= tame.level then return false, "level " .. tostring(petLevel) end
  return true
end

function Collector:PetChanged()
  local tame = pendingTame
  if not tame or not UnitExists("pet") then return end
  local ok, why = isTamedPet(tame)
  if not ok then
    return Addon:Debug("collector: a pet appeared while taming", tame.name, "but it is not the same beast (" .. why .. ")")
  end
  pendingTame = nil

  local entry = {
    npc_id = tame.npc_id, name = tame.name, family = tame.family, family_id = tame.family_id, level = tame.level,
    classification = tame.classification, creature_speed = tame.creature_speed, tame_spell_id = tame.tame_spell_id,
    ui_map_id = tame.ui_map_id, map_id = tame.map_id, x = tame.x, y = tame.y, subzone = tame.subzone,
    tamed = time(), pet_guid = UnitGUID("pet"),
    -- The hunter, credited on the site's Tamed badge ("Verified Tame: <date> by <name>"): only with Send Name on.
    tamed_by = DB.global.send_name == true and Addon:PlayerName() or nil,
  }
  DB.collected.tames = DB.collected.tames or {}
  table.insert(DB.collected.tames, entry)
  Collector:NotifyNew("tame", entry)
  Addon:Debug("collector: tame of", tame.name, "(" .. tame.npc_id .. ") confirmed - reading the new pet")
  changed()
  reading[entry] = true
  for i, delay in ipairs(READ_DELAYS) do
    C_Timer.After(delay, function() safely("tame", Collector.ReadTamedPet, Collector, entry, i == #READ_DELAYS) end)
  end
end

-- Any spell of yours that finishes while taming is reported in debug mode (to learn what a tame casts: Classic
-- casts a second "Tame Beast", 13481, when it succeeds). The channel itself is left out.
function Collector:SpellDuringTame(spellId)
  if pendingTame and spellId and spellId ~= pendingTame.tame_spell_id then
    Addon:Debug("collector: spell finished during the tame:", tostring(spellName(spellId)), "(" .. spellId .. ")")
  end
end

-- ============================================================================
-- Nameplates
-- ============================================================================

-- Every enemy nameplate in range is a unit token, so nothing has to be targeted or hovered. The nameplate
-- event only fires when a plate appears, so the plates already up are read when collecting starts and again
-- every few seconds.
local SCAN_SECONDS = 5

function Collector:ScanNameplates()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then safely("collect", Collector.Record, Collector, unit) end
  end
end

-- Send Name turned off: takes your name off the tames already collected (tamed_by), so the file is anonymous again.
function Collector:RemoveNames()
  local removed = 0
  for _, tame in ipairs(DB.collected.tames or {}) do
    if tame.tamed_by then
      tame.tamed_by = nil
      removed = removed + 1
    end
  end
  Addon:Debug("collector: Send Name off, removed the name from", removed, "tame(s)")
end

-- A one-time chat tip about Send Name, once per account, for players who have it off (the default). It is never turned
-- on for them: it puts their name on the website. The first load decides it either way (`send_name_tip`), so whoever
-- turns Send Name off later never gets it.
local SEND_NAME_TIP_DELAY = 15 -- seconds after loading in, past the login messages

-- A chat notice when Collect Mode records a creature the addon's data does not have: a sighting of it, or a tame of
-- it (the most wanted: a new tameable beast, and what it comes with). Once per creature and kind a session, so a beast
-- in view does not repeat it. `force`: always (the debug samples).
local announced = {}
function Collector:NotifyNew(kind, entry, force)
  local id = tonumber(entry and (entry.npc_id or entry.id))
  if not id or (Addon.TameableNPCs and Addon.TameableNPCs[id]) then return end
  local key = kind .. ":" .. id
  if announced[key] and not force then return end
  announced[key] = true
  local L = Addon:GetModule("Locale")
  local level = entry.level or entry.level_min
  local about = ("|cFF1FA5D1%s|r (%s%s)"):format(entry.name or "?", entry.family or L.UNKNOWN,
    level and (", " .. L.LEVEL:lower() .. " " .. level) or "")
  local text = (kind == "tame" and L.NEW_TAME_NOTICE or L.NEW_SIGHTING_NOTICE):format(about)
  print(("|cFF007EA6%s|r: |cFFFF8000%s|r %s"):format(Addon.TITLE, L.NEW_BADGE, text))
end

function Collector:SendNameTip()
  local global = DB.global
  if not global or global.send_name_tip then return end
  global.send_name_tip = true
  if global.send_name == true then return end
  C_Timer.After(SEND_NAME_TIP_DELAY, function()
    print(("|cFF007EA6%s|r: %s"):format(Addon.TITLE, Addon:GetModule("Locale").SEND_NAME_TIP))
  end)
end

local scanTicker -- the repeating scan while collecting

-- `/tsl debug collect check`: says why nothing is being collected. Each nameplate in range is looked at
-- the way the collector looks at it, and what the game answers is printed (errors included, such as values
-- the client hides from addons).
function Collector:Diagnose()
  local say = function(...) print(Addon.TITLE .. " collect check:", ...) end
  say("collecting is", DB.global.collect and "on" or "OFF (turn it on in Options, Collection)",
    "| debug is", DB.global.debug and "on" or "off",
    "| scanning every " .. SCAN_SECONDS .. "s:", scanTicker and "yes" or "no")
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return say("no C_NamePlate.GetNamePlates") end
  local plates = C_NamePlate.GetNamePlates()
  say(#plates, "nameplates in range; nameplateShowEnemies =", tostring(GetCVar and GetCVar("nameplateShowEnemies")))
  for i = 1, math.min(#plates, 8) do
    local unit = plates[i].namePlateUnitToken or (plates[i].UnitFrame and plates[i].UnitFrame.unit)
    local ok, result = pcall(function()
      local guid = UnitGUID(unit)
      local kind, _, _, _, _, id = strsplit("-", guid)
      local family, familyId, familyText = Addon:UnitFamily(unit)
      return ("%s %s id=%s family=%s (%s) known=%s"):format(tostring(UnitName(unit)), kind, tostring(id),
        tostring(familyText), tostring(familyId), tostring(family ~= nil))
    end)
    say("  " .. tostring(unit) .. ":", ok and result or ("ERROR " .. tostring(result)))
  end
end

-- An earlier version turned on `nameplateShowFriendlyPets` while collecting (to see other players' pets) and
-- kept the original value in the saved settings. Pets are no longer collected, so that is never changed now; this
-- only puts back a value an earlier session left changed.
local function restoreCollectCVars()
  local backup = DB.global.cvar_backup
  if not backup then return end
  if SetCVar then
    for name, value in pairs(backup) do pcall(SetCVar, name, value) end
  end
  DB.global.cvar_backup = nil
end

local function setScanning(enabled)
  if enabled and not scanTicker and C_Timer and C_Timer.NewTicker then
    scanTicker = C_Timer.NewTicker(SCAN_SECONDS, function()
      if DB.global and DB.global.collect then Collector:ScanNameplates() end
    end)
  elseif not enabled and scanTicker then
    scanTicker:Cancel()
    scanTicker = nil
  end
end

-- Events are only registered while collecting, so nothing runs when it's off.
local EVENTS = {
  "PLAYER_TARGET_CHANGED",
  "UPDATE_MOUSEOVER_UNIT",
  "NAME_PLATE_UNIT_ADDED",
  "TRAINER_SHOW",
  "TRAINER_UPDATE",
  "MERCHANT_SHOW",
  "UI_ERROR_MESSAGE", -- (Tame Beast's "Creature not tameable")
}

-- Your own spells and pet, for taming (only the player's are wanted).
local PLAYER_EVENTS = {
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_PET",
}

function Collector:SetEnabled(enabled)
  for _, event in ipairs(EVENTS) do
    -- Not every client has every event.
    pcall(enabled and frame.RegisterEvent or frame.UnregisterEvent, frame, event)
  end
  for _, event in ipairs(PLAYER_EVENTS) do
    if not enabled then
      pcall(frame.UnregisterEvent, frame, event)
    elseif frame.RegisterUnitEvent then
      pcall(frame.RegisterUnitEvent, frame, event, "player")
    else
      pcall(frame.RegisterEvent, frame, event)
    end
  end
  setScanning(enabled)
  local Share = Addon:GetModule("Share")
  if Share.SetEnabled then safely("share", Share.SetEnabled, Share, enabled) end
  if enabled then
    safely("collect", dropBeastTrainers)
    safely("collect", dropForeignTraining)
    safely("collect", Collector.ScanNameplates, Collector)
  end
end

frame:SetScript("OnEvent", function(_, event, unit, castGUID, spellId)
  if event:find("^UNIT_SPELLCAST_") or event == "UNIT_PET" then
    if unit ~= "player" then return end
    if event == "UNIT_PET" then
      safely("tame", Collector.PetChanged, Collector)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      safely("tame", Collector.SpellDuringTame, Collector, spellId)
    elseif isTameSpell(spellId) then
      if event == "UNIT_SPELLCAST_CHANNEL_START" then
        safely("tame", Collector.TameStarted, Collector, spellId, castGUID)
      elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        safely("tame", Collector.TameStopped, Collector, false)
      else
        safely("tame", Collector.TameStopped, Collector, true)
      end
    end
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    safely("collect", Collector.Record, Collector, "mouseover")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    safely("collect", Collector.Record, Collector, unit)
  elseif event == "PLAYER_TARGET_CHANGED" then
    safely("collect", Collector.Record, Collector, "target")
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    safely("tame", Collector.SettleTameSpells, Collector) -- (before anything can be taught from it)
    schedule("trainer", Collector.RecordBeastTraining)
    schedule("trainer_npc", Collector.RecordTrainer)
  elseif event == "MERCHANT_SHOW" then
    schedule("merchant", Collector.RecordMerchant)
  elseif event == "UI_ERROR_MESSAGE" then
    safely("tame", Collector.UIError, Collector, unit, castGUID) -- (its arguments: the error's type and text)
  elseif event == "PLAYER_LOGIN" then
    -- Collecting is on by default and remembered (the Collect Mode option).
    frame:UnregisterEvent("PLAYER_LOGIN")
    restoreCollectCVars()
    if DB.global.collect then Collector:SetEnabled(true) end
  end
end)

-- Saved settings are loaded by PLAYER_LOGIN; collecting starts then (when it is on).
frame:RegisterEvent("PLAYER_LOGIN")
