local ADDON_NAME, Addon = ...

-- ============================================================================
-- Consts
-- ============================================================================

-- Npc ids that are never collected, listed or exported. 165189 is "Generic Hunter Pet": the id every tamed pet
-- carries in its GUID, so it says nothing about which creature a pet came from.
-- Whether a value is "secret": in combat, newer clients give addons some unit values (attack speed, level, ...) that
-- can be shown but not compared, used in arithmetic or used as a table key, nor saved.
function Addon:IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) == true
end

-- The value, or nil when it is secret (for values that are compared or saved).
function Addon:Plain(value)
  if Addon:IsSecret(value) then return nil end
  return value
end

-- Your character's full name. WoW Forever gives characters a surname: UnitName("player") returns the first name and
-- the surname (where other versions return the realm), e.g. "Spike", "Skylance" -> "Spike Skylance". Just the first
-- name when there is no surname; nil when the game hides it.
-- UnitName follows the game's "show surnames" display option and can leave the surname out, so the calls that ignore
-- it come first (as other Forever addons do): UnitNameUnmodified, UnitFullName, then UnitName.
local NAME_CALLS = { "UnitNameUnmodified", "UnitFullName", "UnitName" }

function Addon:PlayerName()
  local firstOnly
  for _, call in ipairs(NAME_CALLS) do
    local fn = _G[call]
    if type(fn) == "function" then
      local ok, first, surname = pcall(fn, "player")
      first, surname = Addon:Plain(first), Addon:Plain(surname)
      if ok and type(first) == "string" and first ~= "" then
        if type(surname) == "string" and surname ~= "" then return first .. " " .. surname end
        firstOnly = firstOnly or first
      end
    end
  end
  return firstOnly
end

-- A character name as the game sends it in chat ("First Surname", or "First-Surname" in older payloads) as
-- "First Surname", the way PlayerName() gives yours.
function Addon:NormalizeName(name)
  if type(name) ~= "string" then return name end
  name = Ambiguate and Ambiguate(name, "none") or name
  return (name:gsub("^([^%s%-]+)%-", "%1 "))
end

-- Whether a name (from chat, or saved) is yours.
function Addon:IsPlayerName(name)
  local me = Addon:PlayerName()
  return type(name) == "string" and me ~= nil and Addon:NormalizeName(name):lower() == me:lower()
end

Addon.IGNORED_NPC_IDS = { [165189] = true }

-- The game version and the build number: 1.60.1.<build> (written into the .toc by each release; a local push puts
-- the current number of commits there).
Addon.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
-- The name players see ("TrueshotLodge", the TOC's Title); ADDON_NAME (TrueshotLodge) names things in code.
Addon.TITLE = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Title") or ADDON_NAME
Addon.ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\icon"
Addon.PIN_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\pin"
-- The infinity mark before the names of creatures added in WoW Forever (patch 1.60 or later).
Addon.FOREVER_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\forever"
-- The question mark icon (INV_Misc_QuestionMark), for anything whose real icon is not known (yet).
Addon.QUESTION_MARK_ICON = 134400

-- ----------------------------------------------------------------------------
-- Pet families, whatever the client's language
-- ----------------------------------------------------------------------------
-- The family data (data/ForeverTameableFamilies.lua) is keyed by the English family name, with the game's family id
-- (CreatureFamily, the website's pet_families.id). The game names a unit's family in the client's language
-- ("Кошка" on a Russian client), so families are matched by that id: UnitCreatureFamily gives it after the name, and
-- C_CreatureInfo.GetCreatureFamilyInfo names each id in the client's language. What is saved and shared is the
-- English name.

local familyById -- family id -> the English name, built from the family data on first use
local function FamiliesById()
  if not familyById then
    familyById = {}
    for name, info in pairs(Addon.TameableFamilies or {}) do familyById[info.id] = name end
  end
  return familyById
end

local localFamilyIds -- family name in the client's language -> family id, built on first use
-- The family id of a family name, in English or in the client's language; nil for a family the data does not know.
function Addon:FamilyId(name)
  if type(name) ~= "string" then return nil end
  local info = self.TameableFamilies and self.TameableFamilies[name]
  if info then return info.id end
  if not localFamilyIds then
    localFamilyIds = {}
    local get = C_CreatureInfo and C_CreatureInfo.GetCreatureFamilyInfo
    for id in pairs(get and FamiliesById() or {}) do
      local ok, family = pcall(get, id)
      if ok and type(family) == "table" and type(family.name) == "string" then localFamilyIds[family.name] = id end
    end
  end
  return localFamilyIds[name]
end

-- The English name of a family named in English or in the client's language; nil for a family the data does not know.
function Addon:EnglishFamily(name)
  local id = self:FamilyId(name)
  return id and FamiliesById()[id] or nil
end

-- A unit's pet family: its English name and family id (nil, nil when the data does not know it), and the name as the
-- game gives it (in the client's language; a demon's family too).
function Addon:UnitFamily(unit)
  local name, id = UnitCreatureFamily(unit)
  name, id = self:Plain(name), self:Plain(id)
  if type(id) ~= "number" then id = self:FamilyId(name) end
  local english = id and FamiliesById()[id] or nil
  return english, english and id or nil, name
end

-- The game's creature type id for beasts (UnitCreatureType's second value).
local CREATURE_TYPE_BEAST = 1

-- A unit's creature type: in English for a beast ("Beast"), otherwise as the game gives it; and the type id.
function Addon:UnitCreatureType(unit)
  local name, id = UnitCreatureType(unit)
  name, id = self:Plain(name), self:Plain(id)
  if type(id) ~= "number" then id = nil end
  if id == CREATURE_TYPE_BEAST then name = "Beast" end
  return name, id
end

-- Whether a unit is a beast, whatever the client's language.
function Addon:UnitIsBeast(unit)
  local name, id = self:UnitCreatureType(unit)
  if id then return id == CREATURE_TYPE_BEAST end
  return name == "Beast"
end

-- The family data of a family named in English or in the client's language (saved data from earlier versions), or nil.
local function FamilyInfo(family)
  local families = Addon.TameableFamilies
  if not (family and families) then return nil end
  return families[family] or families[Addon:EnglishFamily(family) or ""]
end

-- A family's icon (the game's icon file id, from the family data), or nil.
function Addon:FamilyIcon(family)
  local info = FamilyInfo(family)
  return info and info.icon or nil
end

-- A family name with the infinity mark (as an inline texture) after it, as on the website, when the family is new in WoW Forever
-- (`forever = true` in the family data, from pet_families.forever: Fox, not Bird of Prey, which only has some new creatures).
function Addon:FamilyLabel(family)
  local info = FamilyInfo(family)
  if info and info.forever then
    return ("%s |T%s:14:14:0:0|t"):format(family, self.FOREVER_ICON)
  end
  return family
end

-- The green dot (the game's own "online" status icon, as in the friends list): a creature someone has tamed, the
-- stable slot of the pet that is out.
Addon.GREEN_DOT = FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"
-- The logo alone (transparent, with a soft shadow): the window's portrait without its ring.
Addon.LOGO = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\logo"

-- ============================================================================
-- Functions
-- ============================================================================

do -- Addon:GetModule()
  local modules = {}

  function Addon:GetModule(key)
    key = key:upper()
    if type(modules[key]) ~= "table" then modules[key] = {} end
    return modules[key]
  end
end

do -- Addon:Debug()
  local DB = Addon:GetModule("DB")

  -- The areas a debug message can come from: its first word ("collector: ...", "share error: ..."), with Options >
  -- Advanced > Debug Mode's checkboxes to show each one (DB.global.debug_on[area] = true; none until ticked).
  Addon.DEBUG_AREAS = { "collector", "share", "integrity", "training", "stable", "tooltip", "window" }
  local AREA_ALIASES = { collected = "collector" } -- ("collected beast training ...")
  local DEBUG_AREA = {}
  for _, area in ipairs(Addon.DEBUG_AREAS) do DEBUG_AREA[area] = true end

  local function Area(first)
    local word = type(first) == "string" and first:match("^(%a+)") or nil
    word = word and word:lower()
    return word and (AREA_ALIASES[word] or word) or nil
  end

  -- Prints only when debug mode is on (the Debug Mode option, Options > Advanced), and its area is ticked.
  function Addon:Debug(...)
    local global = DB.global
    if not (global and global.debug) then return end
    local area = Area((...))
    -- (an area the list does not name prints whenever Debug Mode is on)
    if area and DEBUG_AREA[area] and not (global.debug_on and global.debug_on[area]) then return end
    print("|cFFFF8800[" .. Addon.TITLE .. " debug]|r", ...)
  end
end

do -- Addon:GetLibrary()
  local libraries = {
    HBD = LibStub("HereBeDragons-2.0"),
    HBDPins = LibStub("HereBeDragons-Pins-2.0"),
    LDB = LibStub("LibDataBroker-1.1"),
    LDBIcon = LibStub("LibDBIcon-1.0")
  }

  function Addon:GetLibrary(key)
    return libraries[key] or error("Invalid library: " .. key)
  end
end

do -- Initialization, once this addon's saved variables are loaded.
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("ADDON_LOADED")
  frame:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    Addon:GetModule("DB"):Initialize()
    -- Collected records changed outside the game since the last logout are marked edited (src/integrity.lua).
    local ok, err = pcall(Addon:GetModule("Integrity").Check, Addon:GetModule("Integrity"))
    if not ok then Addon:Debug("integrity: check failed:", err) end
    -- Wild sightings the addon's data now holds (a new release brought them in) are dropped (src/collector.lua).
    ok, err = pcall(Addon:GetModule("Collector").PurgeKnown, Addon:GetModule("Collector"))
    if not ok then Addon:Debug("collector: cleanup failed:", err) end
    -- Shared trainers named in another player's language: named in yours (src/collector.lua).
    ok, err = pcall(Addon:GetModule("Collector").RenameSharedTrainers, Addon:GetModule("Collector"))
    if not ok then Addon:Debug("collector: trainer names failed:", err) end
    Addon:GetModule("MinimapIcon"):Initialize()
    Addon:GetModule("Commands"):Initialize()
    Addon:GetModule("Collector"):SendNameTip()
  end)
end
