local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Looks" tab, as TrueshotLodge.com/looks: the looks each family's creatures come in (the creatures that look
-- alike: the same model and textures, whatever their size; data/Looks.lua). On the left the families,
-- each a heading with its looks under it (the number of its creatures beside each; gold when only one creature has
-- it, the only place to get that look); on the right the selected look: its 3D model, drawn by the game from its
-- display id (model-viewer.lua: drag to turn it, right-drag to move it, the mouse wheel to zoom), then the creatures
-- with that look and their Map buttons. The title bar's Zone Filter and Filter by Level narrow the creatures, as on the Families tab: a
-- look none of whose creatures are left is not listed.

local PlayClick = Helpers.PlayClick
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON
local UNIQUE_COLOR = Colors.Gold -- as the website's edge on a look only one creature has

-- A look's name: its texture's (in the data), else its creature's when only one has it, else the family's ("Bat": the
-- family's own look, with no colour of its own). As the website's look_name(). The pet profile names its looks so too.
function Addon:LookName(look, family)
  if look.name then return look.name end
  local first = #look.npcs == 1 and Addon:GetNPC(look.npcs[1])
  return first and first.name or Addon:FamilyLabel(family)
end

-- The model (model-viewer.lua), made once and shown only on this tab (Window:UpdateTabs).
function Window:LookWidgets()
  if not self.lookWidgets then self.lookWidgets = Helpers.NewModelViewer(self.details) end
  return self.lookWidgets
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

-- The families with their looks: { { key, family, info, rows = { { key, family, look, name, total, creatures } } } },
-- by family name. With a search (which looks for creatures), a look shows when one of its creatures matches.
function Window:GetLookGroups()
  local zone, level = self:ZoneFilter(), UnitLevel("player") or 1
  local filtered = zone ~= nil or DB.global.filter_by_level or self:RaresOnly() or DB.global.filter_tamed
    or DB.global.filter_favorites or self:CreatureSearch() ~= nil
  local groups = {}
  for family, looks in pairs(Addon.TameableLooks or {}) do
    local info = Addon.TameableFamilies and Addon.TameableFamilies[family]
    if info then
      local group = { key = "looks:" .. family, family = family, info = info, rows = {} }
      for _, look in ipairs(looks) do
        local name = Addon:LookName(look, family)
        local named = self:HeadingMatches(name, family)
        local creatures = self:BountyCreatures(look.npcs, zone, level, false, named) -- (the filters, the search)
        if #creatures > 0 or not filtered then
          group.rows[#group.rows + 1] = { key = family .. ":" .. look.display, family = family, look = look,
            name = name, total = #look.npcs, creatures = creatures }
        end
      end
      if #group.rows > 0 then groups[#groups + 1] = group end
    end
  end
  table.sort(groups, function(a, b) return a.family < b.family end)
  return groups
end

local function LookOnClick(button)
  PlayClick()
  Window:SelectLook(button.ftLook.key)
end

local function LookOnEnter(button)
  local row = button.ftLook
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.name)
  GameTooltip:AddLine(Addon:FamilyLabel(row.family), 1, 1, 1)
  if row.total == 1 then
    Helpers.TipLine(L.LOOK_UNIQUE_TOOLTIP, UNIQUE_COLOR, true)
  end
  GameTooltip:Show()
end

function Window:InitLookButton(button, row)
  button.Label:SetText(row.name)
  button.Label:SetVertexColor((row.total == 1 and UNIQUE_COLOR or Colors.Default):GetRGB())
  -- The number of its creatures (with the filters), on the right like a badge (as on the Families tab).
  self:SetRowCount(button, #row.creatures)
  self:SetRowSelected(button, self.selectedLook == row.key)

  button.ftLook = row
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", LookOnClick)
  button:SetScript("OnEnter", LookOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:RefreshLooks()
  local groups = self:GetLookGroups()
  self.lookByKey = {}
  local first
  for _, group in ipairs(groups) do
    for _, row in ipairs(group.rows) do
      self.lookByKey[row.key] = row
      first = first or row.key
    end
  end
  -- The selection: the one shown before, else the one saved (sticky selections), else the first.
  if not (self.selectedLook and self.lookByKey[self.selectedLook]) then
    local saved = self:Sticky() and DB.global.selections.LOOKS
    self.selectedLook = (saved and self.lookByKey[saved]) and saved or first
  end
  local selectedFamily = self.selectedLook and self.lookByKey[self.selectedLook].family

  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.lookHeadersSeen = self.lookHeadersSeen or {}
  local looks, creatures = 0, 0
  for _, group in ipairs(groups) do
    self.listKeys[#self.listKeys + 1] = group.key
    -- A family starts closed the first time it is shown (all open would be a long list), but the selected look's;
    -- after that it stays as the player left it.
    if not self.lookHeadersSeen[group.key] then
      self.lookHeadersSeen[group.key] = true
      self.expanded[group.key] = group.family == selectedFamily or nil
    end
    local name = ("|T%s:16:16:0:0|t %s"):format(group.info.icon or QUESTION_MARK_ICON, Addon:FamilyLabel(group.family))
    local category = provider:Insert({ categoryInfo = { name = name }, key = group.key })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows) do
      category:Insert({ look = row })
      looks, creatures = looks + 1, creatures + #row.creatures
    end
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetFormattedText(L.LOOK_COUNTS, looks, creatures)
  self:UpdateToggleButton()
  self:UpdateLookDetails()
end

function Window:SelectLook(key)
  self.selectedLook = key
  self:Remember()
  self:MarkSelected("look", function(row) return row.key == key end)
  self:UpdateLookDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

function Window:UpdateLookDetails()
  local row = self.selectedLook and self.lookByKey and self.lookByKey[self.selectedLook]
  local box = self:LookWidgets()
  if not row then
    box:Hide()
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  box:Show()

  -- The model at the top, where the other tabs have their icon, name and facts (hidden here: Window:UpdateTabs). The
  -- list already says the look's name and family, and how many creatures have it.
  self.description:SetText("")
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", self.details, "TOPLEFT", Window.DETAILS_LEFT, -Window.DETAILS_TOP)
  box:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)
  box:ShowModel(row.look.display)

  self:ShowBountyCreatures(row.creatures, L.LOOK_CREATURES, L.LOOK_NONE)
end
