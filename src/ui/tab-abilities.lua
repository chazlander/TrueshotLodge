local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The ability tabs: Unique, Common, Passive and Passive Attack Speed are one view with a different set of abilities
-- (Addon:GetAbilityTab). The abilities as headers with their ranks under them on the left; the selected rank on the
-- right, with its tameable creatures.

local ByLevel, GetSpellDescription = Helpers.ByLevel, Helpers.GetSpellDescription
local PlayClick, SetSpellTooltip = Helpers.PlayClick, Helpers.SetSpellTooltip

-- ----------------------------------------------------------------------------
-- States and filters
-- ----------------------------------------------------------------------------

function Window:InLevelRange(rank)
  return (rank.pet_level or 1) <= (self.playerLevel or 1)
end

-- A rank's state, for its color (colors.lua): Complete (known), Available (the character's level has reached it, not
-- known yet) or Unavailable (level not reached). An attack speed is a beast's passive, not learned: Default.
function Window:RankState(ability, rankIndex)
  if ability.attack_speed then return "Default" end
  if Addon:IsRankKnown(ability, rankIndex) then return "Complete" end
  return self:InLevelRange(ability.ranks[rankIndex]) and "Available" or "Unavailable"
end

-- An ability's state, for its header: Available when a rank is, Complete when every rank is known, Unavailable when
-- none is known or reachable yet, and Default otherwise (some known, the next ones not reachable yet).
function Window:AbilityState(ability)
  if ability.attack_speed or #ability.ranks == 0 then return "Default" end
  local known = 0
  for rankIndex in ipairs(ability.ranks) do
    local state = self:RankState(ability, rankIndex)
    if state == "Available" then return "Available" end
    if state == "Complete" then known = known + 1 end
  end
  if known == #ability.ranks then return "Complete" end
  return known == 0 and "Unavailable" or "Default"
end

-- The current pet's family: the pet that is out, else the one in the stable's Current Pet slot (dismissed); nil
-- without a current pet. The data's English name, whatever the client's language.
function Window:CurrentPetFamily()
  local family = UnitExists("pet") and Addon:UnitFamily("pet")
  if family then return family end
  local Stable = Addon:GetModule("Stable")
  local slots = Stable.GetSlots and Stable:GetSlots()
  local current = slots and slots[1]
  return current and current.family or nil
end

-- With Filter by Pet on, only the abilities the current pet's family learns (a family's own, and the ones
-- every family learns). Without a current pet there is nothing to filter by (the option is greyed out), so
-- everything is listed.
function Window:PetShown(ability)
  if not DB.global.filter_by_pet or (self.tab ~= "UNIQUE" and self.tab ~= "COMMON") then return true end
  local family = self:CurrentPetFamily()
  if not family or #ability.learned_by == 0 then return true end
  for _, name in ipairs(ability.learned_by) do
    if name == family then return true end
  end
  return false
end

-- Whether a rank passes the filter (always, unless Filter by Level is on). On the attack speeds, Filter by Level keeps
-- the beasts you can tame now instead (AttackNPCs): a speed is listed while it has one.
function Window:RankShown(rank)
  if self.tab == "ATTACK" then return not DB.global.filter_by_level or #self:AttackNPCs(rank) > 0 end
  return not DB.global.filter_by_level or self:InLevelRange(rank)
end

-- An attack speed's beasts (Addon:GetNPC) that pass Filter by Level: with it on, the ones you can tame now (their
-- lowest level at most yours; a beast of unknown level is left out), as on the Bounties tab.
function Window:AttackNPCs(rank)
  local npcs, level = {}, self.playerLevel or (UnitLevel and UnitLevel("player")) or 1
  for _, id in ipairs(rank.npc_ids or {}) do
    local npc = Addon:GetNPC(id)
    if npc and (not DB.global.filter_by_level or (npc.min and npc.min <= level)) then npcs[#npcs + 1] = npc end
  end
  return npcs
end

-- The saved ability selection of the current tab, when that ability is among `abilities` (the search may
-- have hidden it).
function Window:RememberedSelection(abilities)
  local saved = self:Sticky() and DB.global.selections[self.tab]
  local ability = type(saved) == "table" and Addon.TameableAbilities[saved.ability]
  if not ability then return nil end
  for _, listed in ipairs(abilities) do
    if listed == ability then
      local rank = tonumber(saved.rank)
      if not (rank and ability.ranks[rank] and self:RankShown(ability.ranks[rank])) then
        rank = self:FirstShownRank(ability)
      end
      return { ability = ability, rankIndex = rank }
    end
  end
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

-- Row handlers, shared by every row (the row keeps what it shows), so scrolling creates no functions.
local function RankOnClick(button)
  PlayClick()
  Window:Select(button.ftInfo.ability, button.ftInfo.rankIndex)
end

local function RankOnEnter(button)
  local info = button.ftInfo
  SetSpellTooltip(button, info.ability.ranks[info.rankIndex].spell_id)
end

-- Fills a profession recipe row with one rank of an ability. Blizzard's own `Init` reads live crafting
-- data, so the row is set up here instead.
function Window:InitRankButton(button, info)
  local ability, rankIndex = info.ability, info.rankIndex
  local rank = ability.ranks[rankIndex]
  local known = Addon:IsRankKnown(ability, rankIndex)

  local text = ("%s %d"):format(L.RANK, rank.rank or rankIndex)
  if ability.attack_speed then text = L.ATTACK_SECONDS:format(ability.attack_speed) end
  if known then text = ("%s (%s)"):format(text, L.KNOWN) end
  button.Label:SetText(text)
  button.Label:SetVertexColor(Colors.State[self:RankState(ability, rankIndex)]:GetRGB())
  button.SkillUps:Hide()
  button.LockedIcon:Hide()

  -- The rank's number of tameable creatures, on the right like a badge (as on the website). The template's Count
  -- (the "[2]" a recipe shows for how many can be crafted) is moved to the row's right edge for it.
  local creatures = rank.npc_ids and #rank.npc_ids or 0
  if creatures > 0 then
    button.Count:ClearAllPoints()
    button.Count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.Count:SetText(("(%d)"):format(creatures))
    button.Count:SetTextColor(0.78, 0.69, 0.55) -- tan, like the website's badge
    button.Count:Show()
    button.Label:SetWidth(button:GetWidth() - 60)
  else
    button.Count:Hide()
    button.Label:SetWidth(button:GetWidth() - 20)
  end

  local selected = self.selected and self.selected.ability == ability and self.selected.rankIndex == rankIndex
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

  button.ftInfo = info
  button:RegisterForClicks("LeftButtonUp") -- (a row the Collected Data tab used also took right-clicks)
  button:SetScript("OnClick", RankOnClick)
  button:SetScript("OnEnter", RankOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:FirstShownRank(ability)
  for rankIndex, rank in ipairs(ability.ranks) do
    if self:RankShown(rank) then return rankIndex end
  end
  return 1
end

function Window:HasShownRank(ability)
  for _, rank in ipairs(ability.ranks) do
    if self:RankShown(rank) then return true end
  end
  return false
end

-- Abilities on the current tab that match the search and the filter, by name.
function Window:GetAbilities()
  local abilities = {}
  for _, ability in pairs(Addon.TameableAbilities) do
    if Addon:GetAbilityTab(ability) == self.tab and #ability.ranks > 0
        and (self.search == "" or ability.name:lower():find(self.search, 1, true))
        and self:HasShownRank(ability) and self:PetShown(ability) then
      abilities[#abilities + 1] = ability
    end
  end
  if self.tab == "ATTACK" then
    table.sort(abilities, function(a, b) return a.attack_speed < b.attack_speed end) -- Fastest first.
  else
    table.sort(abilities, function(a, b) return a.name < b.name end)
  end
  return abilities
end

function Window:RefreshAbilities()
  self.playerLevel = UnitLevel and UnitLevel("player") or 1
  local abilities = self:GetAbilities()
  local provider = CreateTreeDataProvider()
  local first
  self.listKeys = {}
  for _, ability in ipairs(abilities) do
    -- Headers start with an icon: a unique ability's family icon (the family name is its tooltip),
    -- otherwise the ability's own icon.
    local icon, family = ability.icon, nil
    if ability.unique and ability.learned_by[1] then
      family = ability.learned_by[1]
      local info = Addon.TameableFamilies and Addon.TameableFamilies[family]
      if info and info.icon then icon = info.icon end
    end
    -- Colored by its state (the template's own header color would otherwise apply).
    local name = Colors[self:AbilityState(ability)](ability.name)
    local header = icon and ("|T%s:18:18:0:0|t %s"):format(icon, name) or name
    self.listKeys[#self.listKeys + 1] = ability
    local category = provider:Insert({ categoryInfo = { name = header }, family = family, key = ability })
    -- The attack speeds start open (the first time each is listed; after that they stay as the player left them).
    if self.tab == "ATTACK" then
      self.attackHeadersSeen = self.attackHeadersSeen or {}
      if not self.attackHeadersSeen[ability] then
        self.attackHeadersSeen[ability] = true
        self.expanded[ability] = true
      end
    end
    self:SetCollapsed(category, ability)
    for rankIndex, rank in ipairs(ability.ranks) do
      if self:RankShown(rank) then
        category:Insert({ rankInfo = { ability = ability, rankIndex = rankIndex } })
      end
    end
    first = first or ability
  end

  -- Keep the selection when it is still listed; otherwise select the first rank shown.
  local selected = self.selected
  local stillListed = false
  if selected then
    for _, ability in ipairs(abilities) do
      if ability == selected.ability and self:RankShown(ability.ranks[selected.rankIndex]) then
        stillListed = true
        break
      end
    end
  end
  if not stillListed then
    self.selected = self:RememberedSelection(abilities)
      or (first and { ability = first, rankIndex = self:FirstShownRank(first) } or nil)
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)

  -- "12 / 78 ranks known" for the abilities listed.
  local total, known = 0, 0
  for _, ability in ipairs(abilities) do
    for rankIndex, rank in ipairs(ability.ranks) do
      if self:RankShown(rank) then
        total = total + 1
        if Addon:IsRankKnown(ability, rankIndex) then known = known + 1 end
      end
    end
  end
  if self.tab == "ATTACK" then
    local beasts = 0
    for _, ability in ipairs(abilities) do beasts = beasts + #self:AttackNPCs(ability.ranks[1]) end
    self.headerCount:SetFormattedText(L.ATTACK_SPEED_COUNT, #abilities, beasts)
  else
    self.headerCount:SetFormattedText(L.RANKS_KNOWN, known, total)
  end
  self:UpdateToggleButton()

  self:UpdateDetails()
end

function Window:Select(ability, rankIndex)
  self.selected = { ability = ability, rankIndex = rankIndex }
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local info = node:GetData().rankInfo
    if info then
      local isSelected = info.ability == ability and info.rankIndex == rankIndex
      button.SelectedOverlay:SetShown(isSelected)
      button.HighlightOverlay:SetShown(not isSelected)
    end
  end)
  self:UpdateDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

-- Learnable By: a row at the top of the pane, above the icon and name, with every pet family's icon spread evenly
-- across the pane's whole width, then a line under it; the families that cannot learn the ability are greyed out.
-- Hover one for its name.
local LEARNABLE_ICON = 24 -- at most: smaller when the pane is too narrow for them all
local LEARNABLE_MIN_GAP = 2
local LEARNABLE_TOP = 4 -- the room above the icons
local LEARNABLE_LINE_GAP = 0 -- between the icons and the line under them (right under them)
local LEARNABLE_BELOW = 12 -- between the line and the ability's icon and name
local LEARNABLE_HEIGHT = LEARNABLE_ICON + LEARNABLE_LINE_GAP + 1 -- the icons, then the line

local function LearnableOnEnter(button)
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(Addon:FamilyLabel(button.family))
  if button.learns then
    GameTooltip:AddLine(L.CAN_LEARN, 0.25, 1, 0.25)
  else
    GameTooltip:AddLine(L.CANNOT_LEARN, 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

-- Spreads the icons across the row, the same gap between each and before the first and after the last (and shrinks
-- them when they would not fit with a small gap).
local function SpreadIcons(row)
  local icons, width = row.icons, row:GetWidth() or 0
  local count = #icons
  if count == 0 or width <= 0 then return end
  local size = math.min(LEARNABLE_ICON, math.floor((width - (count + 1) * LEARNABLE_MIN_GAP) / count))
  local gap = (width - count * size) / (count + 1)
  for index, button in ipairs(icons) do
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", row, "TOPLEFT", gap + (index - 1) * (size + gap), 0)
  end
end

function Window:LearnableRow()
  if self.learnableRow then return self.learnableRow end
  local row = CreateFrame("Frame", nil, self.details)
  row:SetHeight(LEARNABLE_HEIGHT)
  -- The line between it and the ability's details: the pane's own inner border (its top edge), across the whole pane,
  -- or a plain grey line when the client has no such piece.
  row.line = row:CreateTexture(nil, "ARTWORK")
  local edge = self.detailsBorder and self.detailsBorder.TopEdge
  local atlas = edge and edge.GetAtlas and edge:GetAtlas()
  if atlas and row.line:SetAtlas(atlas, true) ~= false then
    row.line:SetHorizTile(true)
  else
    row.line:SetHeight(2)
    row.line:SetColorTexture(0.25, 0.25, 0.25, 0.9)
  end
  row.line:SetPoint("BOTTOMLEFT", 0, 0)
  row.line:SetPoint("BOTTOMRIGHT", 0, 0)
  row.icons = {}
  local families = {}
  for family in pairs(Addon.TameableFamilies or {}) do families[#families + 1] = family end
  table.sort(families)
  for _, family in ipairs(families) do
    local button = CreateFrame("Button", nil, row)
    button:SetSize(LEARNABLE_ICON, LEARNABLE_ICON)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints()
    button.texture:SetTexture(Addon.TameableFamilies[family].icon or Helpers.QUESTION_MARK_ICON)
    button.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.family = family
    button:SetScript("OnEnter", LearnableOnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    row.icons[#row.icons + 1] = button
  end
  row:SetPoint("TOPLEFT", self.details, "TOPLEFT", 0, -LEARNABLE_TOP)
  row:SetPoint("RIGHT", self.details, "RIGHT", 0, 0) -- the pane's whole width
  row:SetScript("OnSizeChanged", SpreadIcons)
  row:Hide()
  self.learnableRow = row
  return row
end

-- Shows the row for an ability: lit for the families that learn it (all of them when it names none: the passives).
function Window:ShowLearnableRow(ability)
  local row = self:LearnableRow()
  local learners = {}
  for _, family in ipairs(ability.learned_by or {}) do learners[family] = true end
  local all = next(learners) == nil
  for _, button in ipairs(row.icons) do
    button.learns = all or learners[button.family] == true
    button.texture:SetDesaturated(not button.learns)
    button:SetAlpha(button.learns and 1 or 0.35)
  end
  row:Show()
  SpreadIcons(row)
  -- The icon, name and facts under it.
  self:SetTopOffset(LEARNABLE_TOP + LEARNABLE_HEIGHT + LEARNABLE_BELOW - Window.DETAILS_TOP)
end

function Window:UpdateAbilityDetails()
  local sel = self.selected
  if not sel then
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  self.npcLabel:Show()

  local ability, rankIndex = sel.ability, sel.rankIndex
  local rank = ability.ranks[rankIndex]

  self.icon:SetTexture(ability.icon)
  self.name:SetText(ability.name)
  if ability.attack_speed then
    self.subtitle:SetText(L.ATTACK_SECONDS:format(ability.attack_speed))
  else
    -- The rank's state after it, in its color: (Known), (Available) or (Unavailable).
    local state = self:RankState(ability, rankIndex)
    local word = ({ Complete = L.KNOWN, Available = L.AVAILABLE, Unavailable = L.UNAVAILABLE })[state]
    self.subtitle:SetText(("%s %d"):format(L.RANK, rank.rank or rankIndex)
      .. (word and ("  %s"):format(Colors[state](("(%s)"):format(word))) or ""))
  end

  local spellId = rank.spell_id
  self.description:SetText(GetSpellDescription(spellId, function(text)
    local current = self.selected
    if current and current.ability.ranks[current.rankIndex].spell_id == spellId then
      self.description:SetText(text)
    end
  end))

  if ability.attack_speed then
    -- The creatures' own attack speed, which this passive stands for.
    self.facts:SetText(("%s: %s"):format(Colors.Label(L.ATTACK_SPEED), L.ATTACK_SECONDS:format(ability.attack_speed)))
    self:LearnableRow():Hide()
    self:SetTopOffset(0)
  else
    self.facts:SetText(table.concat({
      ("%s: %s"):format(Colors.Label(L.PET_LEVEL), rank.pet_level or 1),
      ("%s: %s"):format(Colors.Label(L.TRAINING_COST), rank.training_cost or 0),
    }, "\n"))
    self:ShowLearnableRow(ability)
  end

  self.descriptionBeside = true -- (under the rank, right of the icon: Window:PlaceDescription)
  self:PlaceDescription()

  -- Trainer passives are not learned from creatures.
  local npcs = {}
  if ability.attack_speed then
    npcs = self:AttackNPCs(rank) -- with Filter by Level, the beasts you can tame now
  else
    for _, id in ipairs(rank.npc_ids or {}) do
      local npc = Addon:GetNPC(id)
      if npc then npcs[#npcs + 1] = npc end
    end
  end
  table.sort(npcs, ByLevel)
  -- The Zone Filter: only the creatures in the player's zone, "2 of 5 in Westfall".
  local total, zone = #npcs, self:ZoneFilter()
  if zone then
    local inZone = {}
    for _, npc in ipairs(npcs) do
      if self:NPCInZone(npc, zone) then inZone[#inZone + 1] = npc end
    end
    npcs = inZone
  end

  local fromTrainer = ability.passive and not ability.unique and not ability.attack_speed
  self.npcLabel:SetText(fromTrainer and L.LEARNED_FROM_TRAINER
    or zone and L.TAMEABLE_IN_ZONE:format(L.TAMEABLE_NPCS, #npcs, total, zone.name)
    or ("%s (%d):"):format(L.TAMEABLE_NPCS, #npcs))
  local provider = CreateDataProvider(fromTrainer and {} or npcs)
  self.npcBox:SetDataProvider(provider)
  self.npcBox:SetShown(not fromTrainer)
  self.npcBar:SetShown(not fromTrainer)
end
