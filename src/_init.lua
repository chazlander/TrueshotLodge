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

-- A family's icon (the game's icon file id, from the family data), or nil.
function Addon:FamilyIcon(family)
  local info = family and self.TameableFamilies and self.TameableFamilies[family]
  return info and info.icon or nil
end

-- A family name with the infinity mark (as an inline texture) before it when the family is new in WoW Forever
-- (`forever = true` in the family data, from pet_families.forever: Fox, not Bird of Prey, which only has some new creatures).
function Addon:FamilyLabel(family)
  local info = family and self.TameableFamilies and self.TameableFamilies[family]
  if info and info.forever then
    return ("|T%s:14:14:0:0|t %s"):format(self.FOREVER_ICON, family)
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

  -- Prints only when debug mode is on (the Debug Mode option, Options > Advanced).
  function Addon:Debug(...)
    local global = DB.global
    if global and global.debug then
      print("|cFFFF8800[" .. Addon.TITLE .. " debug]|r", ...)
    end
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
    Addon:GetModule("MinimapIcon"):Initialize()
    Addon:GetModule("Commands"):Initialize()
  end)
end
