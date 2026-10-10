local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")

-- The small pieces the window's tabs share: text, panels, icons, tooltips, and formatting. A helper only one tab uses
-- stays in that tab's file. Data helpers (the family label and icon, attack speed text, ...) are on Addon.

Helpers.QUESTION_MARK_ICON = Addon.QUESTION_MARK_ICON
Helpers.LIST_WIDTH = 269 -- the list on the left of the window's tabs
Helpers.MINI_MAP_WIDTH = 336 -- the Trainers tab's small zone map (its height follows the map's shape)

-- ----------------------------------------------------------------------------
-- Frames and text
-- ----------------------------------------------------------------------------

function Helpers.NewText(parent, font, justify)
  local text = parent:CreateFontString(nil, "OVERLAY", font)
  text:SetJustifyH(justify or "LEFT")
  text:SetJustifyV("TOP")
  return text
end


-- A panel with the window's dark background and inset border.
function Helpers.CreatePanel(parent)
  local panel = CreateFrame("Frame", nil, parent)
  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetColorTexture(0, 0, 0, 0.35)
  background:SetAllPoints()
  local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
  border:SetAllPoints()
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
  end
  return panel
end

-- Four thin lines around `frame` (`size` pixels thick), returned for the caller to color.
function Helpers.AddEdges(frame, size, layer, sublevel)
  local edges = {}
  for _, edge in ipairs({
    { "TOPLEFT", "TOPRIGHT", nil, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size },
    { "TOPLEFT", "BOTTOMLEFT", size, nil }, { "TOPRIGHT", "BOTTOMRIGHT", size, nil },
  }) do
    local line = frame:CreateTexture(nil, layer or "OVERLAY", nil, sublevel)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    if edge[3] then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
    edges[#edges + 1] = line
  end
  return edges
end

function Helpers.TemplateExists(name)
  if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
    return C_XMLUtil.GetTemplateInfo(name) ~= nil
  end
  return true -- No way to check on this client; creating the frame will tell.
end


-- "Label: value" with the label in gold; nil when there is no value (so the line is left out).
function Helpers.Line(label, value)
  if value == nil or value == "" then return nil end
  return ("%s: %s"):format(Colors.Label(label), tostring(value))
end

-- The click sound of the profession window's list.
function Helpers.PlayClick()
  if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.UI_90_BLACKSMITHING_TREEITEMCLICK or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end

-- ----------------------------------------------------------------------------
-- Spells
-- ----------------------------------------------------------------------------

-- A spell's icon, from the game (the question mark until it is known).
function Helpers.SpellIcon(spellId)
  if not spellId then return Addon.QUESTION_MARK_ICON end
  local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
  if not icon and GetSpellTexture then icon = GetSpellTexture(spellId) end
  if not icon then
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    icon = info and info.iconID
  end
  return icon or Addon.QUESTION_MARK_ICON
end

function Helpers.GetSpellDescription(spellId, callback)
  local get = (C_Spell and C_Spell.GetSpellDescription) or _G.GetSpellDescription
  local text = get and get(spellId)
  if (not text or text == "") and Spell and Spell.CreateFromSpellID then
    local spell = Spell:CreateFromSpellID(spellId)
    spell:ContinueOnSpellLoad(function() callback(spell:GetSpellDescription() or "") end)
    return ""
  end
  return text or ""
end

function Helpers.SetSpellTooltip(owner, spellId)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, spellId)
  if not ok or GameTooltip:NumLines() == 0 then
    pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. spellId)
  end
  GameTooltip:Show()
end


-- ----------------------------------------------------------------------------
-- Formatting and sorting
-- ----------------------------------------------------------------------------

-- 12345 copper -> "1g 23s 45c".
function Helpers.Money(copper)
  copper = tonumber(copper)
  if not copper then return "?" end
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. "g" end
  if silver > 0 then parts[#parts + 1] = silver .. "s" end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
  return table.concat(parts, " ")
end

-- "5-6", "12", or "?" without a level.
function Helpers.LevelText(low, high)
  if not low then return "?" end
  if high and high ~= low then return low .. "-" .. high end
  return tostring(low)
end

-- The names of a set of world maps ({ [uiMapID] = true }), sorted, in the player's language.
function Helpers.ZoneNames(zones)
  local names = {}
  for mapId in pairs(zones or {}) do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    names[#names + 1] = info and info.name or ("map " .. tostring(mapId))
  end
  table.sort(names)
  return table.concat(names, ", ")
end

-- Creatures from the lowest level up (those without a level last), then by name.
function Helpers.ByLevel(a, b)
  local aMin, bMin = a.min or math.huge, b.min or math.huge
  if aMin ~= bMin then return aMin < bMin end
  local aMax, bMax = a.max or aMin, b.max or bMin
  if aMax ~= bMax then return aMax < bMax end
  return a.name < b.name
end
