local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local L = Addon:GetModule("Locale")
local Stable = Addon:GetModule("Stable")
local Window = Addon:GetModule("Window")
local Helpers = Addon:GetModule("Helpers")
local AddEdges, CreatePanel, NewText, SpellIcon = Helpers.AddEdges, Helpers.CreatePanel, Helpers.NewText, Helpers.SpellIcon
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON

-- The "Stable" tab, laid out like the game's pet window and sized like the other tabs (a list-width pane on the left,
-- the rest on the right): on the left the selected pet's name, level, family and statistics; on the right the active
-- pet's box and the stable's slots in a row across the top (the active pet is shown even when it is not out: the last
-- one seen), then its 3D model with its experience bar under it. Everything comes from the copy the Stable module
-- keeps (src/stable.lua), so it can be looked at anywhere, not only at a stable master or with the pet out.

local LEFT_WIDTH = Helpers.LIST_WIDTH -- the other tabs' list width
local SLOTS_TOP = 30 -- the slots' top, under their headings
local MODEL_FACING = math.rad(45) -- the pet's model, turned 45 degrees (negative turns it the other way)
local XP_SECTIONS = 6 -- the experience bar's sections, as in the stable window
local MODEL_ZOOM_OUT = 1.3 -- how far the camera moves back for the turned pet (1 = the frame's own framing)
local SLOT_SIZE, SLOT_GAP, GROUP_GAP = 44, 8, 40 -- GROUP_GAP: between the Current Pet and the Stabled Pets
local SLOT_ART = 64 / 37 -- the game's slot art is 64 pixels for a 37 pixel button
local ROW_HEIGHT, HEADER_HEIGHT, NOTE_HEIGHT = 24, 25, 40
-- Each resistance's icon is the one of its passive ability on the Passive tab (the game supplies it, see data.lua).
local RESISTANCE_ABILITIES = {
  Arcane = "arcane-resistance", Fire = "fire-resistance", Frost = "frost-resistance",
  Nature = "nature-resistance", Shadow = "shadow-resistance",
}

local function ResistanceAbility(school)
  return Addon.TameableAbilities and Addon.TameableAbilities[RESISTANCE_ABILITIES[school]]
end

local function ResistanceIcon(school)
  local ability = ResistanceAbility(school)
  return ability and ability.icon or QUESTION_MARK_ICON
end

-- The spell a resistance's icon stands for: the first rank of its passive, for its description.
local function ResistanceSpell(school)
  local ability = ResistanceAbility(school)
  return ability and ability.ranks[1] and ability.ranks[1].spell_id
end

-- A pet's spells in the order of the ability tabs: Unique, Common, Passive, then the attack speed passive; spells the
-- data does not know come last. Within each, by name then rank.
local TAB_ORDER = { UNIQUE = 1, COMMON = 2, PASSIVE = 3, ATTACK = 4 }
local spellTabs -- spell id -> its ability's tab, built the first time it is needed

local function SortedSpells(spells)
  if not spellTabs then
    spellTabs = {}
    for _, ability in pairs(Addon.TameableAbilities or {}) do
      local tab = Addon:GetAbilityTab(ability)
      for _, rank in ipairs(ability.ranks) do spellTabs[rank.spell_id] = tab end
    end
  end
  local sorted = {}
  for i, spell in ipairs(spells) do sorted[i] = spell end
  table.sort(sorted, function(a, b)
    local aOrder, bOrder = TAB_ORDER[spellTabs[a.spell_id]] or 5, TAB_ORDER[spellTabs[b.spell_id]] or 5
    if aOrder ~= bOrder then return aOrder < bOrder end
    if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
    return tostring(a.rank or "") < tostring(b.rank or "")
  end)
  return sorted
end

-- ----------------------------------------------------------------------------
-- The slots
-- ----------------------------------------------------------------------------

-- A square slot: the pet's icon in a thin frame (gold while selected), its level in the corner.
local function CreateSlot(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(SLOT_SIZE, SLOT_SIZE)

  -- Like the game's own stable: the grey empty slot, the pet's icon in it, the slot's frame over both.
  button.Empty = button:CreateTexture(nil, "BACKGROUND")
  button.Empty:SetSize(SLOT_SIZE * SLOT_ART, SLOT_SIZE * SLOT_ART)
  button.Empty:SetPoint("CENTER")
  button.Empty:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")

  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetAllPoints()

  local frame = button:CreateTexture(nil, "OVERLAY", nil, -1)
  frame:SetSize(SLOT_SIZE * SLOT_ART, SLOT_SIZE * SLOT_ART)
  frame:SetPoint("CENTER", 0, -1)
  frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")

  -- The selected slot glows, like a checked action button.
  button.Selected = button:CreateTexture(nil, "OVERLAY", nil, 1)
  button.Selected:SetAllPoints()
  button.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  button.Selected:SetBlendMode("ADD")

  button.Level = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.Level:SetPoint("BOTTOMRIGHT", -4, 4)

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  highlight:SetBlendMode("ADD")
  return button
end

-- Fills a slot with a pet (or shows it empty).
-- Fills a slot: its pet, or empty (grey), or not bought yet (red, like the game's).
local function ShowSlot(button, pet, selected, locked)
  button.pet = pet
  button.locked = locked
  button.Selected:SetShown(selected)
  if locked then
    button.Empty:SetVertexColor(1, 0.1, 0.1) -- as the game tints a stable slot that is not bought yet
  else
    button.Empty:SetVertexColor(1, 1, 1)
  end
  button.Icon:SetShown(pet ~= nil)
  if pet then button.Icon:SetTexture(pet.icon or QUESTION_MARK_ICON) end
  button.Level:SetText(pet and pet.level or "")
end

local function SlotOnEnter(button)
  local pet = button.pet
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if button.locked then
    GameTooltip:SetText(L.NOT_PURCHASED, 1, 0.3, 0.3)
    GameTooltip:AddLine(L.NOT_PURCHASED_TOOLTIP, 0.6, 0.6, 0.6, true)
  elseif not pet then
    GameTooltip:SetText(button.active and L.STABLE_NO_PET or L.EMPTY_SLOT, 0.6, 0.6, 0.6)
  else
    if button.active then GameTooltip:AddLine(L.CURRENT_PET, 1, 0.82, 0) end
    GameTooltip:AddLine(pet.name or "?", 1, 1, 1)
    GameTooltip:AddLine(("%s %s %s"):format(L.LEVEL, tostring(pet.level or "?"), Addon:FamilyLabel(pet.family or "")), 1, 1, 1)
    if pet.live then
      GameTooltip:AddLine(L.OUT_NOW, 0.4, 1, 0.4)
    elseif button.active then
      GameTooltip:AddLine(L.NOT_OUT, 0.6, 0.6, 0.6)
    elseif pet.cached then
      GameTooltip:AddLine(("%s: %s"):format(L.LAST_SEEN, date("%Y-%m-%d %H:%M", pet.cached)), 0.6, 0.6, 0.6)
    end
  end
  GameTooltip:Show()
end

-- ----------------------------------------------------------------------------
-- Building the tab
-- ----------------------------------------------------------------------------

function Window:CreateStable(frame)
  local stable = CreateFrame("Frame", nil, frame)
  self.stable = stable
  stable:SetPoint("TOPLEFT", 5, -72)
  stable:SetPoint("BOTTOMRIGHT", -5, 5)
  stable:Hide()

  -- Left: the pet's name, level and family, and its statistics.
  local left = CreatePanel(stable)
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMLEFT")
  left:SetWidth(LEFT_WIDTH)
  self.stableLeft = left

  self.stableTitle = NewText(left, "GameFontHighlightLarge", "CENTER") -- the pet's name
  self.stableTitle:SetPoint("TOP", 0, -14)
  self.stableTitle:SetPoint("LEFT", 8, 0)
  self.stableTitle:SetPoint("RIGHT", -8, 0)
  self.stableSubtitle = NewText(left, "GameFontNormal", "CENTER") -- its level and family
  self.stableSubtitle:SetPoint("TOP", self.stableTitle, "BOTTOM", 0, -4)
  self.stableSubtitle:SetPoint("LEFT", 8, 0)
  self.stableSubtitle:SetPoint("RIGHT", -8, 0)

  -- "Last Stable Visit: <date>" at the bottom.
  self.stableVisit = NewText(left, "GameFontDisableSmall")
  self.stableVisit:SetPoint("BOTTOMLEFT", 12, 8)
  self.stableVisit:SetPoint("BOTTOMRIGHT", -12, 8)

  -- The statistics: a scrolling list of headers and "label ... value" rows.
  local top = 14 + 22 + 4 + 16 + 2 -- just under the name and the level
  local box = CreateFrame("Frame", nil, left, "WowScrollBoxList")
  box:SetPoint("TOPLEFT", 8, -top)
  box:SetPoint("BOTTOMRIGHT", -22, 26)
  local bar = CreateFrame("EventFrame", nil, left, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
  -- Same spacing and collapsible headers as the other tabs' lists.
  local view = CreateScrollBoxListTreeListView(10, 5, 5, 0, 5, 1)
  view:SetElementFactory(function(factory, node)
    local data = node:GetData()
    if data.categoryInfo then
      factory("ProfessionsRecipeListCategoryTemplate", function(button)
        button:Init(node)
        button:SetScript("OnClick", function()
          node:ToggleCollapsed()
          self.expanded[data.key] = not node:IsCollapsed() or nil
          button:UpdateCollapsedState(node:IsCollapsed())
        end)
      end)
    else
      factory("Frame", function(row) self:InitStableRow(row, data) end)
    end
  end)
  view:SetElementExtentCalculator(function(_, node)
    local data = node:GetData()
    return data.categoryInfo and HEADER_HEIGHT or data.kind == "note" and NOTE_HEIGHT or ROW_HEIGHT
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  self.stableBox = box

  -- Right: the slots, the model, and the experience bar under it.
  local right = CreatePanel(stable)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 2, 0)
  right:SetPoint("BOTTOMRIGHT")
  local backdrop = right:CreateTexture(nil, "BACKGROUND", nil, 1)
  backdrop:SetColorTexture(0.04, 0.04, 0.05, 0.9)
  backdrop:SetPoint("TOPLEFT", 3, -3)
  backdrop:SetPoint("BOTTOMRIGHT", -3, 3)

  -- The slots across the top, as in the game's stable: the Current Pet (slot 1), then the Stabled Pets, each group
  -- under its heading. The slot of the pet that is out has a green dot.
  local stabled = Stable.SLOTS - 1
  local stabledWidth = stabled * SLOT_SIZE + (stabled - 1) * SLOT_GAP
  local rowWidth = SLOT_SIZE + GROUP_GAP + stabledWidth
  local left0 = -rowWidth / 2
  local function placeSlot(which, x)
    local slot = CreateSlot(right)
    slot:SetPoint("TOPLEFT", right, "TOP", left0 + x, -SLOTS_TOP)
    slot:SetScript("OnClick", function() self:SelectStable(which) end)
    slot:SetScript("OnEnter", SlotOnEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    return slot
  end
  local function heading(text, x, width)
    local label = NewText(right, "GameFontNormal", "CENTER")
    label:SetPoint("BOTTOM", right, "TOP", left0 + x + width / 2, -(SLOTS_TOP - 4))
    label:SetText(text)
  end
  heading(L.CURRENT_PET, 0, SLOT_SIZE)
  heading(L.STABLED_PETS, SLOT_SIZE + GROUP_GAP, stabledWidth)
  self.stableSlots = { placeSlot(1, 0) }
  self.stableSlots[1].active = true
  for i = 2, Stable.SLOTS do
    self.stableSlots[i] = placeSlot(i, SLOT_SIZE + GROUP_GAP + (i - 2) * (SLOT_SIZE + SLOT_GAP))
  end

  local ok, model = pcall(CreateFrame, "PlayerModel", nil, right)
  if ok and model then
    model:SetPoint("TOPLEFT", 6, -(SLOTS_TOP + SLOT_SIZE + 10))
    model:SetPoint("BOTTOMRIGHT", -6, 50)
    self.stableModel = model
  end
  self.stableNoModel = NewText(right, "GameFontDisable", "CENTER")
  self.stableNoModel:SetPoint("CENTER", 0, 20)
  self.stableNoModel:SetText(L.STABLE_NO_MODEL)

  -- The experience bar: the pet's experience towards its next level, as "XP 0/1625".
  local xp = CreateFrame("Frame", nil, right)
  xp:SetHeight(22)
  xp:SetPoint("BOTTOMLEFT", 14, 14)
  xp:SetPoint("BOTTOMRIGHT", -14, 14)
  local xpBack = xp:CreateTexture(nil, "BACKGROUND")
  xpBack:SetAllPoints()
  xpBack:SetColorTexture(0, 0, 0, 0.75)
  -- Green, on the game's own status bar texture, like the pet window's experience bar.
  xp.Fill = xp:CreateTexture(nil, "ARTWORK")
  xp.Fill:SetPoint("TOPLEFT", 1, -1)
  xp.Fill:SetPoint("BOTTOMLEFT", 1, 1)
  xp.Fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  xp.Fill:SetVertexColor(0.1, 0.75, 0.1)
  for _, line in ipairs(AddEdges(xp, 1)) do
    line:SetColorTexture(0.8, 0.65, 0.3, 1) -- gold, like the pet window's bar
  end
  -- Divided into sections like the stable window's experience bar: dark lines over the fill, under the text.
  xp.Dividers = {}
  for i = 1, XP_SECTIONS - 1 do
    local divider = xp:CreateTexture(nil, "OVERLAY", nil, -1)
    divider:SetWidth(2)
    divider:SetColorTexture(0, 0, 0, 0.55)
    xp.Dividers[i] = divider
  end
  local function placeDividers(bar)
    local width = bar:GetWidth() or 0
    for i, divider in ipairs(bar.Dividers) do
      divider:ClearAllPoints()
      divider:SetPoint("TOP", bar, "TOPLEFT", width * i / XP_SECTIONS, -1)
      divider:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * i / XP_SECTIONS, 1)
    end
  end
  xp:SetScript("OnSizeChanged", placeDividers)
  xp:HookScript("OnShow", placeDividers)
  xp.Text = NewText(xp, "GameFontHighlight", "CENTER")
  xp.Text:SetPoint("CENTER")
  xp:Hide()
  self.stableXP = xp

  self.selectedStable = nil
end

-- A row of the statistics list. Rows are recycled by the scroll box: their parts are built once.
function Window:InitStableRow(row, data)
  if not row.ftBuilt then
    row.ftBuilt = true
    row.Plate = row:CreateTexture(nil, "BACKGROUND")
    row.Plate:SetAllPoints()
    row.Swatch = row:CreateTexture(nil, "ARTWORK")
    row.Swatch:SetSize(18, 18)
    row.Swatch:SetPoint("LEFT", 6, 0)
    row.Swatch:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Over the icon: the spell's tooltip on hover (a texture cannot be hovered, so a frame covers it).
    row.IconHover = CreateFrame("Frame", nil, row)
    row.IconHover:SetAllPoints(row.Swatch)
    row.IconHover:EnableMouse(true)
    row.IconHover:SetScript("OnEnter", function(frame)
      if not frame.spell then return end
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, frame.spell)
      if not ok or GameTooltip:NumLines() == 0 then pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. frame.spell) end
      GameTooltip:Show()
    end)
    row.IconHover:SetScript("OnLeave", GameTooltip_Hide)
    row.Label = NewText(row, "GameFontNormal")
    row.Value = NewText(row, "GameFontHighlight", "RIGHT")
    row.Value:SetPoint("RIGHT", -8, 0)
  end

  row.Label:ClearAllPoints()
  row.Swatch:Hide()
  row.Value:SetText("")
  row.Plate:SetColorTexture(1, 1, 1, data.stripe and 0.07 or 0.025)
  row.Label:SetFontObject(data.kind == "note" and "GameFontDisableSmall" or "GameFontNormal")
  row.Label:SetJustifyH("LEFT")
  if data.icon then
    row.Swatch:SetTexture(data.icon)
    row.Swatch:Show()
  end
  row.IconHover.spell = data.spell
  row.IconHover:SetShown(data.icon ~= nil and data.spell ~= nil)
  row.Label:SetPoint("LEFT", data.icon and 30 or 8, 0)
  row.Label:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
  row.Label:SetWordWrap(data.kind == "note") -- a note is a sentence: it wraps instead of being cut off
  row.Label:SetMaxLines(data.kind == "note" and 2 or 1)
  row.Label:SetText(data.label)
  row.Value:SetText(data.value or "")
end

-- ----------------------------------------------------------------------------
-- The rows for a pet
-- ----------------------------------------------------------------------------

local function Group(n)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function StatRows(pet)
  local rows = {}
  local function header(label) rows[#rows + 1] = { kind = "header", label = label, key = "stable:" .. label } end
  local function stat(label, value, icon)
    if value == nil or value == "" then return end
    rows[#rows + 1] = { kind = "stat", label = label, value = tostring(value), icon = icon, stripe = #rows % 2 == 0 }
  end

  local family = pet.family and Addon.TameableFamilies and Addon.TameableFamilies[pet.family]
  local stats = pet.stats or {}
  header(L.GENERAL)
  stat(L.FAMILY, pet.family and Addon:FamilyLabel(pet.family))
  stat(L.TYPE, family and family.type)
  stat(L.DIET, family and family.foods and table.concat(family.foods, ", "))
  stat(L.HEALTH, stats.health and Group(stats.health))
  stat(L.ARMOR, stats.armor and Group(math.floor(stats.armor)))
  if stats.damage_min and stats.damage_max then
    -- As the game's pet window rounds it: the low end down, the high end up.
    stat(L.DAMAGE, ("%d - %d"):format(math.floor(stats.damage_min), math.ceil(stats.damage_max)))
  end
  stat(L.ATTACK_POWER, stats.attack_power and Group(math.floor(stats.attack_power)))
  stat(L.ATTACK_SPEED, pet.attack_speed and ("%.2f"):format(pet.attack_speed)) -- the number (the passive is under Abilities)
  stat(L.CRITICAL_STRIKE, stats.crit and ("%.1f%%"):format(stats.crit))
  stat(L.MOVEMENT_SPEED, stats.speed and ("%d%%"):format(math.floor(stats.speed + 0.5)))
  if not pet.stats then rows[#rows + 1] = { kind = "note", label = L.STABLE_NO_STATS } end

  if pet.stats and next(stats.res or {}) then
    header(L.RESISTANCES)
    for _, school in ipairs(Stable.RESISTANCES) do
      local value = stats.res[school.id]
      if value then
        stat(school.name, value, ResistanceIcon(school.name))
        rows[#rows].spell = ResistanceSpell(school.name)
      end
    end
  end

  if pet.spells and #pet.spells > 0 then
    header(L.ABILITIES)
    for _, spell in ipairs(SortedSpells(pet.spells)) do
      local text = (spell.name or "?") .. (spell.rank and (" " .. spell.rank) or "")
      rows[#rows + 1] = {
        kind = "stat", label = text, value = spell.passive and L.PASSIVE or "", stripe = #rows % 2 == 0,
        icon = SpellIcon(spell.spell_id), spell = spell.spell_id,
      }
    end
  elseif pet.stats then
    header(L.ABILITIES)
    rows[#rows + 1] = { kind = "note", label = pet.live and L.STABLE_NO_ABILITIES or L.STABLE_NO_SPELLS }
  end
  return rows
end

-- The rows as the list's tree: each header a collapsible node with its rows under it. A header starts open the first
-- time it appears; after that it stays as the player left it.
function Window:BuildStableTree(rows)
  local provider = CreateTreeDataProvider()
  self.sectionsSeen = self.sectionsSeen or {}
  local category
  for _, row in ipairs(rows) do
    if row.kind == "header" then
      if not self.sectionsSeen[row.key] then
        self.sectionsSeen[row.key] = true
        self.expanded[row.key] = true
      end
      category = provider:Insert({ categoryInfo = { name = row.label }, key = row.key })
      self:SetCollapsed(category, row.key)
    else
      (category or provider):Insert(row)
    end
  end
  return provider
end

-- ----------------------------------------------------------------------------
-- Showing a pet
-- ----------------------------------------------------------------------------

function Window:SelectStable(i)
  self.selectedStable = i
  self:RefreshStable()
end

-- Shows the pet's model: the live pet by unit, a stabled one by the display or creature id the stable gave.
local function ShowModel(window, pet)
  local model = window.stableModel
  local shown = false
  if model then
    pcall(model.ClearModel, model)
    if pet then
      if pet.live then
        shown = (pcall(model.SetUnit, model, "pet"))
      elseif pet.display_id then
        shown = (pcall(model.SetDisplayInfo, model, pet.display_id))
      elseif pet.creature_id then
        shown = (pcall(model.SetCreature, model, pet.creature_id))
      end
    end
    -- Turned so the pet looks off to one side, not straight out (setting a model resets its facing). Turned, a long
    -- pet is wider than the frame's own framing, which is for the pet facing out, so the camera moves back to fit it
    -- (the model is shrunk instead where the camera cannot be moved).
    if shown then
      pcall(model.SetFacing, model, MODEL_FACING)
      if not (model.SetCamDistanceScale and pcall(model.SetCamDistanceScale, model, MODEL_ZOOM_OUT)) then
        pcall(model.SetModelScale, model, 1 / MODEL_ZOOM_OUT)
      end
    end
    model:SetShown(shown)
  end
  window.stableNoModel:SetShown(pet ~= nil and not shown)
end

function Window:RefreshStable()
  if not self.stable then return end
  local slots, out = Stable:GetSlots()
  -- The Stabled Pets in use, of those bought (all of them while the count is not known).
  local purchased = Stable:GetPurchased()
  local stabled, used = Stable.SLOTS - 1, 0
  for i = 2, Stable.SLOTS do if slots[i] then used = used + 1 end end
  -- First the pet that is out; failing that the first pet there is.
  if self.selectedStable == nil then
    self.selectedStable = out
    if not self.selectedStable then
      for i = 1, Stable.SLOTS do
        if slots[i] then self.selectedStable = i break end
      end
    end
    self.selectedStable = self.selectedStable or 1
  end

  for i, button in ipairs(self.stableSlots) do
    local locked = purchased ~= nil and i > 1 + purchased -- a Stabled Pets slot not bought yet
    ShowSlot(button, slots[i], i == self.selectedStable, locked)
  end
  self.headerCount:SetFormattedText(L.STABLE_COUNT, used, purchased and math.min(purchased, stabled) or stabled)
  local visited = Stable:GetLastVisit()
  self.stableVisit:SetFormattedText(L.LAST_STABLE_VISIT, visited and date("%Y-%m-%d %H:%M", visited) or L.NEVER)

  local pet = slots[self.selectedStable]
  ShowModel(self, pet)
  local xp = self.stableXP
  local stats = pet and pet.stats
  if stats and stats.xp and stats.xp_max and stats.xp_max > 0 then
    xp:Show()
    xp.Fill:SetWidth(math.max(1, ((xp:GetWidth() or 0) - 2) * math.min(1, stats.xp / stats.xp_max)))
    xp.Fill:SetShown(stats.xp > 0)
    xp.Text:SetFormattedText("XP %d/%d", stats.xp, stats.xp_max) -- as the game writes it, without separators
  else
    xp:Hide()
  end

  if not pet then
    self.stableTitle:SetText(self.selectedStable == 1 and L.CURRENT_PET or L.EMPTY_SLOT)
    self.stableSubtitle:SetText(self.selectedStable == 1 and L.STABLE_NO_PET or "")
    self.stableBox:SetDataProvider(CreateTreeDataProvider())
    return
  end
  self.stableTitle:SetText(pet.name or "")
  self.stableSubtitle:SetText(("%s %s %s"):format(L.LEVEL, tostring(pet.level or "?"), Addon:FamilyLabel(pet.family or "")))
  self.stableBox:SetDataProvider(self:BuildStableTree(StatRows(pet)), true)
end

-- Called by the Stable module when the copy changes.
function Window:OnStableChanged()
  if self.frame and self.frame:IsShown() and self.tab == "STABLE" then
    local ok, err = pcall(self.RefreshStable, self)
    if not ok then Addon:Debug("stable tab error:", err) end
  end
end
