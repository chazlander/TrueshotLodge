local ADDON_NAME, Addon = ...
local Collector = Addon:GetModule("Collector")
local DB = Addon:GetModule("DB")

-- Collects data about creatures seen around the player into
-- `DB.collected.creatures` (SavedVariables), keyed by npc id. Enable with
-- the Collect Mode option. Upload the saved file (WTF/Account/<account>/
-- SavedVariables/TrueshotLodge.lua) on the website's collector page to compare it
-- with the database.

local SAMPLE_PRECISION = 100 -- Round positions to 1/100th of a percent.

local frame = CreateFrame("Frame")

-- Only the beasts of the pet families in the data are collected (not demons, humanoids or critters, nor
-- families that are not out yet). The family name is compared as the game gives it, which is the data's
-- English name on an English client.
local function isKnownFamily(family)
  return family ~= nil and Addon.TameableFamilies ~= nil and Addon.TameableFamilies[family] ~= nil
end

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

-- Creatures already reported as ignored this session (npc id), so debug mode says so once, not on every scan.
local ignored = {}

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
  local c = creatures[id]
  if c then
    local changed = {}
    if c.shared_by then
      -- Shared by another user, and now seen yourself: it is your own record from here on.
      c.shared_by = nil
      changed[#changed + 1] = "seen yourself (was shared)"
    end
    local level = UnitLevel(unit)
    if level and level > 0 then
      if not c.level_min or level < c.level_min then
        c.level_min = level
        changed[#changed + 1] = "lowest level " .. level
      end
      if not c.level_max or level > c.level_max then
        c.level_max = level
        changed[#changed + 1] = "highest level " .. level
      end
    end
    local zoneId = getZoneMapId()
    if zoneId then
      c.zones = c.zones or {}
      if not c.zones[zoneId] then
        c.zones[zoneId] = true
        changed[#changed + 1] = "new zone " .. zoneId
      end
    end
    -- Only a change is reported: a creature in view is seen again on every scan.
    if #changed > 0 then
      Addon:Debug("collector: updated", c.name, "(" .. id .. "):", table.concat(changed, ", "))
      Collector.version = Collector.version + 1
      if Collector.onChange then Collector.onChange() end
      if not c.shared_by then share("creature", c) end
    end
    return
  end

  -- Only creatures of a known pet family.
  local family = UnitCreatureFamily(unit)
  if not isKnownFamily(family) then
    if not ignored[id] then
      ignored[id] = true
      Addon:Debug("collector: ignored", UnitName(unit), "(" .. id .. "):",
        family and ("family " .. family .. " is not in the data") or "no pet family")
    end
    return
  end

  local level = UnitLevel(unit)
  if not (level and level > 0) then level = nil end
  local zoneId = getZoneMapId()

  local mainhand, offhand = UnitAttackSpeed(unit)
  mainhand, offhand = Addon:Plain(mainhand), Addon:Plain(offhand) -- secret in combat: not saved
  c = {
    id = tonumber(id),
    collected = time(),
    name = UnitName(unit),
    family = family,
    creature_type = UnitCreatureType(unit),
    classification = UnitClassification(unit),
    level_min = level,
    level_max = level,
    zones = zoneId and { [zoneId] = true } or {},
    power_type = UnitPowerType(unit),
    health_max = UnitHealthMax(unit),
    power_max = UnitPowerMax(unit),
    sex = UnitSex(unit),
    mainhand_speed = mainhand,
    offhand_speed = offhand,
    instance_id = tonumber(instanceId),
  }

  local mapId, x, y = getObserverPosition()
  if mapId then
    c.map_id = mapId
    c.x = x
    c.y = y
    c.ui_map_id = zoneId -- Zone of this first position.
    c.subzone = GetSubZoneText()
  end

  creatures[id] = c
  share("creature", c)
  Addon:Debug("collector: recorded", c.name, "(" .. id .. ")", family, "level " .. tostring(level),
    c.classification or "", "speed " .. tostring(mainhand), "zone " .. tostring(zoneId))
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
  if Addon:Plain(UnitCreatureType(unit)) == "Beast" or Addon:Plain(UnitCreatureFamily(unit)) then return end
  local unitType, _, _, _, _, id = strsplit("-", UnitGUID(unit) or "")
  if unitType == "Creature" and id then return tonumber(id), unit end
end

-- Takes out "trainers" an earlier version recorded from the Beast Training window: the beast that was targeted
-- (a tameable creature, or one collected as a creature), not a trainer.
-- Whether an npc's title makes it a pet trainer ("Pet Trainer", "Wolf Pet Trainer", ...). A stable master or another
-- trainer can open the same trainer window, but only pet trainers are recorded.
local function isPetTrainerTitle(title)
  return type(title) == "string" and title:lower():find("pet trainer", 1, true) ~= nil
end

local function dropBeastTrainers()
  local trainers = DB.global and DB.collected.trainers
  if not trainers then return end
  for id, trainer in pairs(trainers) do
    local npc = tonumber(id)
    if (Addon.TameableNPCs and Addon.TameableNPCs[npc]) or (DB.collected.creatures and DB.collected.creatures[tostring(npc)]) then
      trainers[id] = nil
      Addon:Debug("collector: removed", tostring(npc), "from the trainers: it is a beast, not a trainer")
    elseif type(trainer) == "table" and trainer.title and not isPetTrainerTitle(trainer.title) then
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
  if title and not isPetTrainerTitle(title) then
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
  trainer.name = UnitName(unit)
  trainer.title = npcTitle(unit) or trainer.title
  -- Your standing with the trainer (4 Neutral, 5 Friendly ... 8 Exalted): prices are lower at Friendly and up, so the
  -- website works the full price back from it.
  trainer.reaction = Addon:Plain(UnitReaction(unit, "player")) or trainer.reaction
  trainer.level = UnitLevel(unit)
  trainer.faction = UnitFactionGroup and UnitFactionGroup(unit) or nil
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
    book[key] = entry
    entry.families = nil -- Trainer purchases are the same for every family.

    entry.name = service.name
    entry.rank = rank ~= "" and rank or nil
    entry.spell_id = service.spell_id or entry.spell_id
    entry.category = service.category
    entry.cost = service.cost
    entry.required_level = service.level_req
    entry.last_seen = now
    entry.shared_by = nil -- seen yourself now
    share("training", entry)

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
      spells[#spells + 1] = {
        spell_id = spellId, name = name, rank = rank ~= "" and rank or nil, passive = passive and true or nil, slot = slot,
      }
    end
  end
  return spells
end
Collector.ReadPetSpellbook = readPetSpellbook -- also used by the Stable tab (src/stable.lua)

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

  local level = Addon:Plain(UnitLevel("target"))
  local mapId, x, y = getObserverPosition()
  local tame = {
    npc_id = tonumber(id),
    name = Addon:Plain(UnitName("target")),
    family = Addon:Plain(UnitCreatureFamily("target")),
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
function Collector:ReadTamedPet(entry, last)
  if not (UnitExists("pet") and UnitGUID("pet") == entry.pet_guid) then return end
  local spells = readPetSpellbook()
  local before = entry.spells and #entry.spells or -1
  entry.pet_level = Addon:Plain(UnitLevel("pet")) or entry.pet_level
  entry.pet_family = Addon:Plain(UnitCreatureFamily("pet")) or entry.pet_family
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
  local petFamily = Addon:Plain(UnitCreatureFamily("pet"))
  local petLevel = Addon:Plain(UnitLevel("pet"))
  if tame.family and petFamily and petFamily ~= tame.family then return false, "family " .. tostring(petFamily) end
  if petName and petName ~= tame.family and petName ~= tame.name then return false, "named " .. tostring(petName) end
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
    npc_id = tame.npc_id, name = tame.name, family = tame.family, level = tame.level,
    classification = tame.classification, creature_speed = tame.creature_speed, tame_spell_id = tame.tame_spell_id,
    ui_map_id = tame.ui_map_id, map_id = tame.map_id, x = tame.x, y = tame.y, subzone = tame.subzone,
    tamed = time(), pet_guid = UnitGUID("pet"),
  }
  DB.collected.tames = DB.collected.tames or {}
  table.insert(DB.collected.tames, entry)
  Addon:Debug("collector: tame of", tame.name, "(" .. tame.npc_id .. ") confirmed - reading the new pet")
  changed()
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
      local family = UnitCreatureFamily(unit)
      return ("%s %s id=%s family=%s known=%s"):format(tostring(UnitName(unit)), kind, tostring(id),
        tostring(family), tostring(isKnownFamily(family)))
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
    schedule("trainer", Collector.RecordBeastTraining)
    schedule("trainer_npc", Collector.RecordTrainer)
  elseif event == "MERCHANT_SHOW" then
    schedule("merchant", Collector.RecordMerchant)
  elseif event == "PLAYER_LOGIN" then
    -- Collecting is on by default and remembered (the Collect Mode option).
    frame:UnregisterEvent("PLAYER_LOGIN")
    restoreCollectCVars()
    if DB.global.collect then Collector:SetEnabled(true) end
  end
end)

-- Saved settings are loaded by PLAYER_LOGIN; collecting starts then (when it is on).
frame:RegisterEvent("PLAYER_LOGIN")
