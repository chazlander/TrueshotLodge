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

-- A quiet button, as the website's Map buttons: a dark fill with a bronze edge and tan text, both gold under the
-- pointer, grey text when disabled. So a long list of creatures leads with their names, not a column of red buttons.
-- The game swaps the fonts and shows the gold edge (its highlight layer) by itself: no scripts to keep. A frame name and
-- template are optional (the pet profile's Target button is a secure one, SecureActionButtonTemplate).
local outlineFonts
local function EnsureOutlineFonts()
  if not outlineFonts then
    outlineFonts = {}
    for state, color in pairs({ Normal = Colors.Tan, Highlight = Colors.Gold, Disable = Colors.Disabled }) do
      local font = CreateFont("TrueshotLodgeOutlineButton" .. state .. "Font")
      font:CopyFontObject(GameFontNormalSmall)
      font:SetTextColor(color:GetRGB())
      outlineFonts[state] = font
    end
  end
  return outlineFonts
end

-- The default font set an outline button uses (Normal/Highlight/Disable), for a caller that swaps a button to a
-- font set of its own (tab-search.lua's smaller "Instance" label) and needs to put the default back.
function Helpers.OutlineButtonFonts()
  return EnsureOutlineFonts()
end

function Helpers.NewOutlineButton(parent, frameName, template)
  local fonts = EnsureOutlineFonts()
  local button = CreateFrame("Button", frameName, parent, template)
  local fill = button:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(0, 0, 0, 0.35)
  for _, line in ipairs(Helpers.AddEdges(button, 1, "BORDER")) do line:SetColorTexture(Colors.Metal:GetRGB()) end
  for _, line in ipairs(Helpers.AddEdges(button, 1, "HIGHLIGHT")) do line:SetColorTexture(Colors.Gold:GetRGB()) end
  local text = button:CreateFontString(nil, "OVERLAY")
  text:SetPoint("CENTER")
  button:SetFontString(text)
  button:SetNormalFontObject(fonts.Normal)
  button:SetHighlightFontObject(fonts.Highlight)
  button:SetDisabledFontObject(fonts.Disable)
  return button
end

-- The favorite star every list row and the Pet Profile toggles a creature's favorite with: Blizzard's own, the exact
-- one the Professions window's recipe list uses -- confirmed live, off the real button
-- (ProfessionsFrame.CraftingPage.SchematicForm.FavoriteButton, found with /fstack): its icon is one atlas,
-- "auctionhouse-icon-favorite" (filled gold) swapped for "auctionhouse-icon-favorite-off" (hollow) as the state
-- changes, not a template with its own states to lean on. A client without these particular atlases (SetAtlas
-- failing, caught with pcall) falls back to a plain star icon instead of breaking.
local FAVORITE_ATLAS_ON = "auctionhouse-icon-favorite"
local FAVORITE_ATLAS_OFF = "auctionhouse-icon-favorite-off"
local FALLBACK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- raid marker 1, the star

function Helpers.NewFavoriteButton(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(13, 13)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  button.icon = icon
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Addon:IsFavorite(self.npcId) and L.REMOVE_FAVORITE or L.SET_FAVORITE, 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  return button
end

-- Draws the favorite star itself (on a plain Texture, not necessarily Helpers.NewFavoriteButton's own icon): the
-- Favorites filter icon on Database Search (Top) uses this directly, since it is one star for the whole list rather
-- than one per creature.
function Helpers.SetFavoriteIcon(icon, on)
  local ok = pcall(icon.SetAtlas, icon, on and FAVORITE_ATLAS_ON or FAVORITE_ATLAS_OFF, false)
  if not ok then
    icon:SetTexture(FALLBACK_TEXTURE)
    icon:SetVertexColor((on and Colors.Gold or Colors.Muted):GetRGB())
  end
end

-- Points a favorite star at a creature and redraws it to match: called whenever the row or page around it refreshes,
-- and again right after a click, so the star just pressed flips without waiting for that.
function Helpers.UpdateFavoriteButton(button, id)
  button.npcId = id
  Helpers.SetFavoriteIcon(button.icon, Addon:IsFavorite(id))
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

-- A line in GameTooltip in one of the palette's colors (Colors.Muted, ...); `wrap` lets a long one run on.
function Helpers.TipLine(text, color, wrap)
  GameTooltip:AddLine(text, color.r, color.g, color.b, wrap)
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
