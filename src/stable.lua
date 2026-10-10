local _, Addon = ...
local Collector = Addon:GetModule("Collector")
local DB = Addon:GetModule("DB")
local Stable = Addon:GetModule("Stable")

-- The Stable tab's data: a copy of your pets, kept in `DB.char.stable` so they can be looked at anywhere, with the
-- stable master out of reach and the pet out of the world.
--
--   * Whenever a pet is out it is copied into `pets` (name, level, family, attack speed, its stats such as health,
--     armor and damage, its experience and its spellbook), under its name and family. So the copy of a pet that is
--     stabled is the last one taken while it was out.
--   * When the stable is opened or changes (PET_STABLE_SHOW / PET_STABLE_UPDATE), the pets in its five slots are read
--     and each is matched with its copy by name and family; that is what is kept in `slots`. A pet put in the stable
--     is cached the moment the stable updates. A pet that was stabled before the addon saw it has no stats or spells
--     until it is out once.
--   * Two pets with the same name and family share a copy: give them different names to keep them apart.

-- The slots shown, as in the game's stable: slot 1 is the Current Pet, the others are the Stabled Pets (2 on this
-- server for now; a stable slot can still have to be bought, see GetPurchased).
Stable.SLOTS = 3

local READ_DELAYS = { 1, 3, 6 } -- seconds after a pet appears: its spellbook fills in after it does

-- The resistance schools shown, as UnitResistance numbers.
Stable.RESISTANCES = {
  { id = 6, name = "Arcane" }, { id = 2, name = "Fire" }, { id = 4, name = "Frost" },
  { id = 3, name = "Nature" }, { id = 5, name = "Shadow" },
}

local function Key(name, family)
  return tostring(name) .. "|" .. tostring(family or "")
end

local function Store()
  return DB.char and DB.char.stable
end

-- Cleans up what earlier versions saved: copies of a pet that was not loaded yet (named "Unknown") and experience of
-- 0 of 0 (read while the pet was changing). Once, at login.
local function CleanUp()
  local store = Store()
  if not store then return end
  for key, copy in pairs(store.pets) do
    if copy.name == (UNKNOWNOBJECT or "Unknown") then
      store.pets[key] = nil
      if store.active == key then store.active = nil end
    elseif copy.stats and copy.stats.xp_max == 0 then
      copy.stats.xp, copy.stats.xp_max = nil, nil
    end
  end
end

-- Tells the window (when it is showing the tab) that the data changed.
function Stable:Changed()
  self.version = (self.version or 0) + 1
  local window = Addon:GetModule("Window")
  if window.OnStableChanged then window:OnStableChanged() end
end

-- ----------------------------------------------------------------------------
-- The pet that is out
-- ----------------------------------------------------------------------------

local function Number(value)
  value = Addon:Plain(value)
  return type(value) == "number" and value or nil
end

-- Calls `func` and returns its results, or nothing when the client has no such function or it fails.
local function Call(func, ...)
  if type(func) ~= "function" then return end
  local ok, a, b, c, d = pcall(func, ...)
  if ok then return a, b, c, d end
end

-- The pet's statistics, as the pet window shows them. A value the client does not give (or hides in combat) is left out.
local function ReadStats()
  local stats = { res = {} }
  stats.health = Number((Call(UnitHealthMax, "pet")))
  stats.armor = Number(select(2, Call(UnitArmor, "pet")))
  local low, high = Call(UnitDamage, "pet")
  stats.damage_min, stats.damage_max = Number(low), Number(high)
  local base, plus, minus = Call(UnitAttackPower, "pet")
  base, plus, minus = Number(base), Number(plus) or 0, Number(minus) or 0
  stats.attack_power = base and (base + plus + minus) or nil
  stats.crit = Number((Call(_G.GetPetCritChance or _G.GetPetMeleeCritChance)))
  local run = Number(select(2, Call(GetUnitSpeed, "pet")))
  stats.speed = run and run > 0 and (run / 7 * 100) or nil -- as a percentage of the base run speed (7 yards a second)
  for _, school in ipairs(Stable.RESISTANCES) do
    stats.res[school.id] = Number(select(2, Call(UnitResistance, "pet", school.id)))
  end
  -- The client answers 0 of 0 while the pet is changing (summoned, stabled, not loaded yet): that is no experience to
  -- keep, so the copy keeps the last real one.
  local xp, xpMax = Call(GetPetExperience)
  xp, xpMax = Number(xp), Number(xpMax)
  if xpMax and xpMax > 0 then stats.xp, stats.xp_max = xp, xpMax end
  return stats
end

-- Copies the pet that is out. Nothing is changed while its name or family are hidden by the game (in combat).
function Stable:SnapshotPet()
  local store = Store()
  if not (store and UnitExists("pet")) then return end
  local name = Addon:Plain(UnitName("pet"))
  local family = Addon:Plain(UnitCreatureFamily("pet"))
  if not (name and family) or name == (UNKNOWNOBJECT or "Unknown") then return end

  local key = Key(name, family)
  local entry = store.pets[key] or {}
  entry.name, entry.family = name, family
  entry.level = Number(UnitLevel("pet")) or entry.level
  entry.icon = Addon:FamilyIcon(family) or entry.icon
  entry.attack_speed = Number((UnitAttackSpeed("pet"))) or entry.attack_speed
  local now = ReadStats()
  local stats = entry.stats or { res = {} }
  for k, v in pairs(now) do
    if k == "res" then
      for school, value in pairs(v) do stats.res[school] = value end
    else
      stats[k] = v
    end
  end
  entry.stats = stats
  local ok, spells = pcall(Collector.ReadPetSpellbook)
  if ok and type(spells) == "table" and #spells > 0 then entry.spells = spells end
  entry.cached = time()
  store.pets[key] = entry
  store.active = key
  self:Changed()
end

-- A pet's copy with the live flag: the pet that is out, else the last one seen out (live = false).
function Stable:GetActive()
  local store = Store()
  if not store then return nil end
  local name, family
  if UnitExists("pet") then
    name, family = Addon:Plain(UnitName("pet")), Addon:Plain(UnitCreatureFamily("pet"))
  end
  local copy
  if name and family then
    copy = store.pets[Key(name, family)]
  elseif not UnitExists("pet") then
    copy = store.active and store.pets[store.active]
  end
  if not copy then return nil end
  local entry = {}
  for k, v in pairs(copy) do entry[k] = v end
  entry.live = UnitExists("pet") and true or false
  return entry
end

-- ----------------------------------------------------------------------------
-- The stable
-- ----------------------------------------------------------------------------

-- Whether the client lists the pets by slot (the retail stable: slots 1-5 are the pets you can call, the summoned one
-- among them). Without it (the classic stable) the list is only the pets that are not out.
local function HasSlotList()
  return C_StableInfo ~= nil and C_StableInfo.GetStablePetInfo ~= nil
end
Stable.HasSlotList = HasSlotList

-- The pets the stable holds right now, by slot: slot -> { name, level, family, icon, display_id, creature_id }.
-- The client's own calls are tried (they only answer while the stable is open).
local function ReadStablePets()
  local found = {}
  if HasSlotList() then
    for slot = 1, Stable.SLOTS do
      local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
      if ok and type(info) == "table" and info.name then
        found[slot] = {
          name = info.name, level = info.level, family = info.familyName, icon = info.icon,
          display_id = info.displayID, creature_id = info.creatureID,
        }
      end
    end
  elseif GetStablePetInfo then
    for slot = 1, Stable.SLOTS - 1 do -- the stabled pets; slot 0 (the current pet) is the first box, from GetActive
      local ok, icon, name, level, family = pcall(GetStablePetInfo, slot)
      if ok and name then found[slot + 1] = { name = name, level = level, family = family, icon = icon } end
    end
  end
  return found
end

-- A slot's pet: what the stable says, with the copy of that pet (stats, spells, experience) and the last record of the slot.
local function Combine(pet, copy, before)
  local entry = {
    name = pet.name, level = pet.level or (copy and copy.level), family = pet.family or (copy and copy.family),
    icon = pet.icon or (copy and copy.icon) or Addon:FamilyIcon(pet.family),
    display_id = pet.display_id, creature_id = pet.creature_id,
  }
  for _, field in ipairs({ "attack_speed", "stats", "spells", "cached" }) do
    entry[field] = (copy and copy[field]) or (before and before[field])
  end
  entry.cached = entry.cached or time()
  return entry
end

-- Whether the client itself says it has no pets (so an empty list can be believed away from the stable master too).
local function ClientHasNoPets()
  if not (C_StableInfo and C_StableInfo.GetNumActivePets) then return false end
  local ok, count = pcall(C_StableInfo.GetNumActivePets)
  return ok and Addon:Plain(count) == 0
end

-- Whether the stable's list has a pet by this name (and family, when both are known).
local function ListHas(found, copy)
  for _, pet in pairs(found) do
    if pet.name == copy.name and (pet.family == nil or copy.family == nil or pet.family == copy.family) then
      return true
    end
  end
  return false
end

-- Reads the stable and keeps what is in it, with each pet's copy. This client answers away from the stable master
-- too, so it is read at login and when pets change; an answer of no pets at all is only believed while the stable is
-- open, or when the client says it has none.
--
-- The pet in the active box is checked against the list: a pet that is not out and is not in the list any more (it ran
-- away, was abandoned, ...) is dropped from the active box. (Only on a client whose list holds every pet, the active
-- one among them.)
function Stable:ReadSlots()
  local store = Store()
  if not store then return end
  local found = ReadStablePets()
  if next(found) == nil and not (self.open or ClientHasNoPets()) then return end

  if HasSlotList() and store.active and not UnitExists("pet") then
    local copy = store.pets[store.active]
    if copy and not ListHas(found, copy) then
      Addon:Debug("stable:", copy.name, "is not in the stable list any more: no longer the active pet")
      self:Log("dropped " .. tostring(copy.name) .. " as the active pet (not in the stable list)")
      store.active = nil
    end
  end

  local old, slots = store.slots, {}
  for i = 1, self.SLOTS do
    local pet = found[i]
    if pet then
      local key = Key(pet.name, pet.family)
      local before = old[i] and Key(old[i].name, old[i].family) == key and old[i] or nil
      slots[i] = Combine(pet, store.pets[key], before)
    end
  end
  store.slots = slots
  if self.open then store.visited = time() end -- when the stable was last open (shown on the tab)
  self:Changed()
end

-- How many of the Stabled Pets slots are bought (nil while not known): the client's count, kept from the last time it
-- answered. A slot past it is shown as not bought yet.
local function ReadPurchased()
  local calls = { C_StableInfo and C_StableInfo.GetNumStableSlots or false, _G.GetNumStableSlots or false }
  for _, func in ipairs(calls) do -- (false, not nil, for a missing one: ipairs stops at a nil)
    if type(func) == "function" then
      local ok, count = pcall(func)
      count = ok and Addon:Plain(count)
      if type(count) == "number" then return count end
    end
  end
end

function Stable:GetPurchased()
  local store = Store()
  local count = ReadPurchased()
  if store and count then store.purchased = count end
  return count or (store and store.purchased)
end

-- When the stable was last opened (a time), or nil if never.
function Stable:GetLastVisit()
  local store = Store()
  return store and store.visited
end

-- The stable's slots: slot number -> pet (empty slots are nil), and the number of the one that is out (or nil).
-- The pet that is out is shown from its live copy. Without a slot list (the classic stable) the current pet is not in
-- the list, so slot 1 is the active pet (the last one seen when none is out).
function Stable:GetSlots()
  local store = Store()
  local slots = {}
  if not store then return slots end
  for i = 1, self.SLOTS do slots[i] = store.slots[i] end

  local active = self:GetActive()
  local out
  if not HasSlotList() then
    slots[1] = active
    out = active and active.live and 1 or nil
  elseif active and active.live then
    for i = 1, self.SLOTS do
      if slots[i] and Key(slots[i].name, slots[i].family) == Key(active.name, active.family) then
        active.display_id, active.creature_id = slots[i].display_id, slots[i].creature_id
        slots[i] = active
        out = i
        break
      end
    end
  end
  return slots, out
end

-- ----------------------------------------------------------------------------
-- Diagnostics: `/tsl debug stable`
-- ----------------------------------------------------------------------------

local LOG_SIZE = 25
local log = {}

local function Safely(func, ...)
  local ok, err = pcall(func, ...)
  if not ok then Addon:Debug("stable:", err) end
end

-- Remembers a pet event (and the pet's state when it happened) for `/tsl debug stable`.
function Stable:Log(text)
  local state = UnitExists("pet") and (UnitIsDead("pet") and "pet dead" or "pet out") or "no pet"
  log[#log + 1] = ("%s  %s  [%s]"):format(date("%H:%M:%S"), text, state)
  if #log > LOG_SIZE then table.remove(log, 1) end
end

local function Say(...)
  print(("|cFF007EA6%s|r stable:"):format(Addon.TITLE), ...)
end

-- What the game says about your pets, next to what is kept, so a pet that is gone can be told from one that is just
-- not out.
function Stable:Diagnose()
  local store = Store()
  if not store then return Say("no saved data yet") end
  if UnitExists("pet") then
    Say(("the game: pet out - %s, %s, level %s%s"):format(tostring(Addon:Plain(UnitName("pet"))),
      tostring(Addon:Plain(UnitCreatureFamily("pet"))), tostring(Addon:Plain(UnitLevel("pet"))),
      UnitIsDead("pet") and ", DEAD" or ""))
  else
    Say("the game: no pet out")
  end
  local copy = store.active and store.pets[store.active]
  if copy then
    Say(("kept as the active pet: %s (%s, level %s), last copied %s"):format(tostring(copy.name), tostring(copy.family),
      tostring(copy.level), copy.cached and date("%Y-%m-%d %H:%M:%S", copy.cached) or "?"))
  else
    Say("kept as the active pet: nothing")
  end
  Say("stable last opened:", store.visited and date("%Y-%m-%d %H:%M:%S", store.visited) or "never",
    "(open now: " .. tostring(self.open == true) .. ")")

  -- The client's own answers, raw. They only mean something with the stable master's window open.
  Say("C_StableInfo.GetStablePetInfo:", tostring(C_StableInfo ~= nil and C_StableInfo.GetStablePetInfo ~= nil),
    "- GetStablePetInfo:", tostring(GetStablePetInfo ~= nil))
  local function value(func, ...)
    if type(func) ~= "function" then return "n/a" end
    local ok, a, b = pcall(func, ...)
    return ok and (tostring(Addon:Plain(a)) .. (b ~= nil and (", " .. tostring(Addon:Plain(b))) or "")) or "error"
  end
  -- The stable's slots, in one line: bought, the next one's price, at a stable master now, pets in each list.
  local C = C_StableInfo or {}
  Say(("  slots: GetNumStableSlots %s, GetNextStableSlotCost %s, IsAtStableMaster %s, GetNumActivePets %s, "
    .. "GetNumStablePets %s"):format(value(C.GetNumStableSlots or _G.GetNumStableSlots),
    value(C.GetNextStableSlotCost or _G.GetNextStableSlotCost), value(C.IsAtStableMaster), value(C.GetNumActivePets),
    value(C.GetNumStablePets)))
  if C_StableInfo and C_StableInfo.GetStablePetInfo then
    for slot = 1, 10 do
      local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
      if ok and type(info) == "table" and info.name then
        Say(("  slot %d: %s, %s, level %s, slotID %s, isActive %s"):format(slot, tostring(info.name),
          tostring(info.familyName), tostring(info.level), tostring(info.slotID), tostring(info.isActive)))
      end
    end
  end
  if GetStablePetInfo then
    for slot = 0, 10 do
      local ok, icon, name, level, family = pcall(GetStablePetInfo, slot)
      if ok and name then Say(("  slot %d: %s, %s, level %s"):format(slot, tostring(name), tostring(family), tostring(level))) end
    end
  end
  for i = 1, self.SLOTS do
    local pet = store.slots[i]
    if pet then Say(("  kept slot %d: %s, %s, level %s"):format(i, tostring(pet.name), tostring(pet.family), tostring(pet.level))) end
  end

  Say("recent pet events (newest last):")
  if #log == 0 then Say("  none since login") end
  for _, line in ipairs(log) do Say("  " .. line) end
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local token = 0

-- Reads the stable's list soon, and again a few seconds later (the client can be slow to give it).
local function ReadSlotsSoon()
  for _, delay in ipairs({ 1, 4 }) do
    C_Timer.After(delay, function() Safely(Stable.ReadSlots, Stable) end)
  end
end

-- Copies the pet now and again a few times over the next seconds, for its spellbook.
local function SnapshotSoon()
  token = token + 1
  local mine = token
  Stable:SnapshotPet()
  for _, delay in ipairs(READ_DELAYS) do
    C_Timer.After(delay, function()
      if mine == token then Stable:SnapshotPet() end
    end)
  end
end

frame:SetScript("OnEvent", function(_, event, first, second)
  if event == "CHAT_MSG_SYSTEM" or event == "UI_INFO_MESSAGE" then
    -- Messages that mention a pet (a pet that ran away, was abandoned, ...), kept for `/tsl debug stable`.
    local text = Addon:Plain(event == "UI_INFO_MESSAGE" and second or first)
    if type(text) == "string" and text:lower():find("pet", 1, true) then Stable:Log(event .. ": " .. text) end
    return
  end
  if event ~= "PLAYER_LOGIN" then Stable:Log(event .. (first and (" " .. tostring(Addon:Plain(first))) or "")) end
  if event == "PLAYER_LOGIN" then
    frame:UnregisterEvent("PLAYER_LOGIN")
    -- Not every client has every event.
    for _, name in ipairs({ "PET_STABLE_SHOW", "PET_STABLE_UPDATE", "PET_STABLE_CLOSED", "PLAYER_ENTERING_WORLD",
      "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE" }) do
      pcall(frame.RegisterEvent, frame, name)
    end
    -- Your pet being summoned, dismissed or replaced, and its level (the player's own events only).
    pcall(frame.RegisterUnitEvent, frame, "UNIT_PET", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_LEVEL", "pet")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_PET_EXPERIENCE", "player", "pet")
    Safely(CleanUp)
    Safely(SnapshotSoon)
    ReadSlotsSoon()
  elseif event == "UNIT_PET" then
    Safely(SnapshotSoon)
    ReadSlotsSoon() -- a pet that ran away shows as one that is gone from the list
    Stable:Changed()
  elseif event == "UNIT_LEVEL" or event == "UNIT_PET_EXPERIENCE" then
    Safely(Stable.SnapshotPet, Stable)
  elseif event == "PLAYER_ENTERING_WORLD" then
    Safely(SnapshotSoon)
    ReadSlotsSoon()
  elseif event == "PET_STABLE_SHOW" then
    Stable.open = true
    -- The pets in the stable list can arrive a moment after the window opens.
    Safely(Stable.ReadSlots, Stable)
    C_Timer.After(0.5, function() if Stable.open then Safely(Stable.ReadSlots, Stable) end end)
  elseif event == "PET_STABLE_UPDATE" then
    Safely(Stable.SnapshotPet, Stable)
    Safely(Stable.ReadSlots, Stable)
  elseif event == "PET_STABLE_CLOSED" then
    Stable.open = false
  end
end)

frame:RegisterEvent("PLAYER_LOGIN")
