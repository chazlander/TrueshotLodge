local _, Addon = ...
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Families" tab, as TrueshotLodge.com/families: the pet families by type (Cunning, Ferocity, Tenacity) on the left,
-- each with its number of tameable creatures; on the right the selected one: its unique ability, type and diet, the
-- common and passive abilities it learns, and its tameable creatures with their Map Location buttons. The title bar's
-- Zone Filter and Filter by Level narrow the creatures, as on the Bounties tab.

local Line, PlayClick, SetSpellTooltip = Helpers.Line, Helpers.PlayClick, Helpers.SetSpellTooltip
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON
local COUNT_COLOR = { 0.78, 0.69, 0.55 } -- the tan of the website's count badges
local TYPE_ORDER = { Cunning = 1, Ferocity = 2, Tenacity = 3 } -- then families without a type

-- Each family's tameable creatures (npc ids), worked out once: the data does not change while playing.
local creatureIds
local function FamilyCreatureIds(family)
  if not creatureIds then
    creatureIds = {}
    for id, npc in pairs(Addon.TameableNPCs or {}) do
      if npc.family and not Addon.IGNORED_NPC_IDS[id] then
        creatureIds[npc.family] = creatureIds[npc.family] or {}
        table.insert(creatureIds[npc.family], id)
      end
    end
  end
  return creatureIds[family] or {}
end

-- What a family learns, as the website lists it: its unique ability, then the common and the passive abilities (those
-- every family learns, and those of its own). The attack speed passives are not learned: they are left out.
local function FamilyAbilities(family)
  local unique, common, passive = nil, {}, {}
  for _, ability in pairs(Addon.TameableAbilities or {}) do
    local tab = Addon:GetAbilityTab(ability)
    local forAll = #(ability.learned_by or {}) == 0
    local own = false
    for _, name in ipairs(ability.learned_by or {}) do
      if name == family then own = true end
    end
    if tab == "UNIQUE" and own then
      unique = ability
    elseif tab == "COMMON" and (forAll or own) then
      common[#common + 1] = ability
    elseif tab == "PASSIVE" and (forAll or own) then
      passive[#passive + 1] = ability
    end
  end
  local byName = function(a, b) return a.name < b.name end
  table.sort(common, byName)
  table.sort(passive, byName)
  return unique, common, passive
end

-- ----------------------------------------------------------------------------
-- The ability icons of the details: each shows the game's own spell tooltip on hover
-- ----------------------------------------------------------------------------

local ICON_SIZE, ICON_GAP, ROW_GAP = 10, 2, 4

local function AbilityOnEnter(button)
  if button.spellId then SetSpellTooltip(button, button.spellId) end
end

-- An icon button (a spell's icon with its tooltip), from the row's pool.
local function IconButton(row, index)
  row.icons = row.icons or {}
  local button = row.icons[index]
  if not button then
    button = CreateFrame("Button", nil, row)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints()
    button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", AbilityOnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    row.icons[index] = button
  end
  return button
end

-- "Common Abilities: [] [] [] []": a label, then the abilities' icons on the same line.
local function FillRow(row, label, abilities)
  row.label:SetText(label .. ":")
  for index, ability in ipairs(abilities) do
    local button = IconButton(row, index)
    button.texture:SetTexture(ability.icon or QUESTION_MARK_ICON)
    button.spellId = ability.ranks[1] and ability.ranks[1].spell_id
    button:ClearAllPoints()
    if index == 1 then
      button:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    else
      button:SetPoint("LEFT", row.icons[index - 1], "RIGHT", ICON_GAP, 0)
    end
    button:Show()
  end
  for index = #abilities + 1, #(row.icons or {}) do row.icons[index]:Hide() end
  row:SetShown(#abilities > 0)
end

-- The details' own parts (made once, shown only on this tab: Window:UpdateTabs): the unique ability under the family
-- name (its icon and name), and right under it the rows of common and passive abilities.
function Window:FamilyWidgets()
  if self.familyWidgets then return self.familyWidgets end
  local details = self.details
  local widgets = CreateFrame("Frame", nil, details)
  widgets:SetSize(1, 1)

  local unique = CreateFrame("Button", nil, widgets)
  unique:SetSize(ICON_SIZE, ICON_SIZE)
  unique:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -4)
  unique.texture = unique:CreateTexture(nil, "ARTWORK")
  unique.texture:SetAllPoints()
  unique.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  unique:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  unique:SetScript("OnEnter", AbilityOnEnter)
  unique:SetScript("OnLeave", GameTooltip_Hide)
  unique.label = unique:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- as the rank under an ability's name
  unique.label:SetPoint("LEFT", unique, "RIGHT", 6, 0)
  widgets.unique = unique

  local abilities = CreateFrame("Frame", nil, widgets) -- placed under the unique ability (UpdateFamilyDetails)
  local function NewRow()
    local row = CreateFrame("Frame", nil, abilities)
    row:SetHeight(ICON_SIZE)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 0, 0)
    return row
  end
  abilities.common, abilities.passive = NewRow(), NewRow()
  widgets.abilities = abilities
  self.familyWidgets = widgets
  return widgets
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

-- The types with their families: { { key, name, rows = { { key, family, info, count, creatures } } } }.
function Window:GetFamilyGroups()
  local search = self.search or ""
  local zone, level = self:ZoneFilter(), UnitLevel("player") or 1
  local byType = {}
  for family, info in pairs(Addon.TameableFamilies or {}) do
    if search == "" or family:lower():find(search, 1, true) then
      local creatures = self:BountyCreatures(FamilyCreatureIds(family), zone, level) -- (with the filters)
      local typeName = info.type or L.OTHER
      byType[typeName] = byType[typeName] or { key = "families:" .. typeName, name = typeName, rows = {} }
      table.insert(byType[typeName].rows, { key = family, family = family, info = info, count = #creatures,
        creatures = creatures })
    end
  end
  local groups = {}
  for _, group in pairs(byType) do
    table.sort(group.rows, function(a, b) return a.family < b.family end)
    groups[#groups + 1] = group
  end
  table.sort(groups, function(a, b)
    local x, y = TYPE_ORDER[a.name] or 99, TYPE_ORDER[b.name] or 99
    if x ~= y then return x < y end
    return a.name < b.name
  end)
  return groups
end

local function FamilyOnClick(button)
  PlayClick()
  Window:SelectFamily(button.ftFamily.key)
end

local function FamilyOnEnter(button)
  local row = button.ftFamily
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(Addon:FamilyLabel(row.family))
  if row.info.type then GameTooltip:AddLine(row.info.type, 1, 1, 1) end
  GameTooltip:Show()
end

function Window:InitFamilyButton(button, row)
  button.Label:SetText(("|T%s:16:16:0:0|t %s"):format(row.info.icon or QUESTION_MARK_ICON, Addon:FamilyLabel(row.family)))
  button.Label:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  -- The number of tameable creatures, on the right like a badge (as on the Bounties tab).
  button.Count:ClearAllPoints()
  button.Count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
  button.Count:SetText(("(%d)"):format(row.count))
  button.Count:SetTextColor(unpack(COUNT_COLOR))
  button.Count:Show()
  button.Label:SetWidth(button:GetWidth() - 60)

  local selected = self.selectedFamily == row.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

  button.ftFamily = row
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", FamilyOnClick)
  button:SetScript("OnEnter", FamilyOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:RefreshFamilies()
  local groups = self:GetFamilyGroups()
  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.familyByKey = {}
  self.familyHeadersSeen = self.familyHeadersSeen or {}
  local first, families, creatures = nil, 0, 0
  for _, group in ipairs(groups) do
    self.listKeys[#self.listKeys + 1] = group.key
    -- A type starts open the first time it is shown; after that it stays as the player left it.
    if not self.familyHeadersSeen[group.key] then
      self.familyHeadersSeen[group.key] = true
      self.expanded[group.key] = true
    end
    local category = provider:Insert({ categoryInfo = { name = group.name }, key = group.key })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows) do
      category:Insert({ family = row })
      self.familyByKey[row.key] = row
      first = first or row.key
      families, creatures = families + 1, creatures + row.count
    end
  end
  -- The selection: the one shown before, else the one saved (sticky selections), else the first.
  if not (self.selectedFamily and self.familyByKey[self.selectedFamily]) then
    local saved = self:Sticky() and DB.global.selections.FAMILIES
    self.selectedFamily = (saved and self.familyByKey[saved]) and saved or first
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetFormattedText(L.FAMILY_COUNTS, families, creatures)
  self:UpdateToggleButton()
  self:UpdateFamilyDetails()
end

function Window:SelectFamily(key)
  self.selectedFamily = key
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local row = node:GetData().family
    if row then
      button.SelectedOverlay:SetShown(row.key == key)
      button.HighlightOverlay:SetShown(row.key ~= key)
    end
  end)
  self:UpdateFamilyDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

function Window:UpdateFamilyDetails()
  local row = self.selectedFamily and self.familyByKey and self.familyByKey[self.selectedFamily]
  if not row then
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  local widgets = self:FamilyWidgets()
  widgets:Show()

  local family, info = row.family, row.info
  local unique, common, passive = FamilyAbilities(family)
  self.icon:SetTexture(info.icon or QUESTION_MARK_ICON)
  self.name:SetText(Addon:FamilyLabel(family))
  -- Under the name: the unique ability's icon and name (its tooltip on hover), or that it has none.
  widgets.unique:SetShown(unique ~= nil)
  if unique then
    self.subtitle:SetText("")
    widgets.unique.texture:SetTexture(unique.icon or QUESTION_MARK_ICON)
    widgets.unique.spellId = unique.ranks[1] and unique.ranks[1].spell_id
    widgets.unique.label:SetText(unique.name)
  else
    self.subtitle:SetText(L.NO_UNIQUE_ABILITY)
  end
  local lines = {}
  local function add(line) if line then lines[#lines + 1] = line end end
  add(Line(L.TYPE, info.type or L.NONE))
  add(Line(L.DIET, info.foods and #info.foods > 0 and table.concat(info.foods, ", ") or L.NONE))
  add(Line(L.TAMEABLE_NPCS, #FamilyCreatureIds(family)))
  self.facts:SetText(table.concat(lines, "\n"))

  -- Where the description goes: a row of common and one of passive ability icons.
  self.description:SetText("")
  self:PlaceDescription()
  local abilities = widgets.abilities
  FillRow(abilities.common, L.COMMON, common)
  FillRow(abilities.passive, L.PASSIVE, passive)
  local y = 0
  for _, line in ipairs({ abilities.common, abilities.passive }) do
    line:ClearAllPoints()
    if line:IsShown() then
      line:SetPoint("TOPLEFT", abilities, "TOPLEFT", 0, -y)
      line:SetPoint("RIGHT", abilities, "RIGHT")
      y = y + ICON_SIZE + ROW_GAP
    end
  end
  abilities:SetHeight(math.max(1, y))
  -- Under the unique ability (or the line saying it has none), beside the family's icon.
  abilities:ClearAllPoints()
  abilities:SetPoint("TOPLEFT", unique and widgets.unique or self.subtitle, "BOTTOMLEFT", 0, -6)
  abilities:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)

  -- The creatures start under whichever is lowest: the icon, the facts, or the ability rows (worked out from the
  -- sizes, as the layout is not resolved yet).
  local top = Window.DETAILS_TOP
  local nameBottom = top + 6 + (self.name:GetStringHeight() or 0) + 4
  local uniqueHeight = unique and math.max(ICON_SIZE, widgets.unique.label:GetStringHeight() or 0)
    or (self.subtitle:GetStringHeight() or 0)
  local rowsBottom = nameBottom + uniqueHeight + 6 + y
  local iconBottom = top + self.iconButton:GetHeight()
  local factsBottom = top + 4 + (self.facts:GetStringHeight() or 0)
  self.npcLabel:ClearAllPoints()
  self.npcLabel:SetPoint("TOPLEFT", self.details, "TOPLEFT", Window.DETAILS_LEFT,
    -(math.max(iconBottom, factsBottom, rowsBottom) + 10))
  self.npcLabel:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)

  self:ShowBountyCreatures(row.creatures, L.FAMILY_CREATURES, L.FAMILY_NONE)
end
