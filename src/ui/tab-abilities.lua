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

-- A rank's state on this tab, at the level the list was last drawn for (see Addon:RankState).
function Window:RankState(ability, rankIndex)
  return Addon:RankState(ability, rankIndex, self.playerLevel)
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
-- With the Zone Filter on or a search typed, a rank is listed only while one of its creatures passes them
-- (CreatureCount): the list on the left then matches the creatures on the right.
function Window:RankShown(rank)
  if self:CreatureCount(rank) == 0 then return false end
  if self.tab == "ATTACK" then return not DB.global.filter_by_level or #self:AttackNPCs(rank) > 0 end
  return not DB.global.filter_by_level or self:InLevelRange(rank)
end

-- The ranks a trainer teaches (the data's `trainer` abilities: Growl and the passives), built the first time it is
-- needed. They are learned from no creature, so the Zone Filter has nothing to say about them.
local trainerRanks
local function TrainerRank(rank)
  if not trainerRanks then
    trainerRanks = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      if ability.trainer then
        for _, taught in ipairs(ability.ranks) do trainerRanks[taught] = true end
      end
    end
  end
  return trainerRanks[rank] == true
end

-- How many of a rank's creatures pass the filters and the search that are on (all of them when none is), and how many
-- of those someone has tamed (the green count). The filters: the Zone Filter (self.listZone: they live in the zone
-- you are in), the Rares filter (self.listRares), the Tamed filter (self.listTamed), the Favorites filter
-- (self.listFavorites) and the search (self.listSearch: their name holds what was typed), all set when the list is
-- drawn; on the attack speeds, with Filter by Level on, only those you can tame now. Worked out once per rank each
-- time the list is drawn (self.rankCreatures).
function Window:RankCreatures(rank)
  self.rankCreatures = self.rankCreatures or {}
  local counted = self.rankCreatures[rank]
  if not counted then
    local zone, search, rares, tamed = self.listZone, self.listSearch, self.listRares, self.listTamed
    local favorites = self.listFavorites
    -- (an ability whose own name matched, with Window.SEARCH_HEADINGS on, is listed whole: GetAbilities)
    if search and self.namedRanks and self.namedRanks[rank] then search = nil end
    local byLevel = self.tab == "ATTACK" and DB.global.filter_by_level
    local level = self.playerLevel or (UnitLevel and UnitLevel("player")) or 1
    counted = { n = 0, tamed = 0 }
    for _, id in ipairs(rank.npc_ids or {}) do
      local npc = Addon:GetNPC(id)
      local isTamed = npc and Addon:NPCMark(npc) == "tamed"
      if npc and (not zone or self:NPCInZone(npc, zone)) and self:NPCMatchesSearch(npc, search)
          and (not rares or self:NPCIsRare(npc)) and (not byLevel or (npc.min and npc.min <= level))
          and (not tamed or isTamed) and (not favorites or Addon:IsFavorite(npc.id)) then
        counted.n = counted.n + 1
        if isTamed then counted.tamed = counted.tamed + 1 end
      end
    end
    self.rankCreatures[rank] = counted
  end
  return counted.n, counted.tamed
end

-- A rank's count with the Zone Filter, the Rares filter, the Tamed filter, the Favorites filter or a search on
-- (RankCreatures); nil with none of them on. A rank a trainer teaches has no creatures: those filters say nothing
-- about it (nil), and a search for creatures does not find it (0).
function Window:CreatureCount(rank)
  local search = self.listSearch
  if search and self.namedRanks and self.namedRanks[rank] then search = nil end
  if not (self.listZone or search or self.listRares or self.listTamed or self.listFavorites) then return nil end
  if TrainerRank(rank) then return search and 0 or nil end
  return (self:RankCreatures(rank))
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

  -- The rank's number of tameable creatures, on the right like a badge (as on the website). The template's Count
  -- (the "[2]" a recipe shows for how many can be crafted) is moved to the row's right edge for it.
  -- With the Zone Filter on or a search typed, the number of them that pass.
  local creatures = self:CreatureCount(rank) or (rank.npc_ids and #rank.npc_ids or 0)
  -- Every one of them tamed: the count in green (Colors.Tamed), as the website's badge.
  local _, tamed = self:RankCreatures(rank)
  local complete = creatures > 0 and tamed == creatures and not TrainerRank(rank)
  self:SetRowCount(button, creatures > 0 and creatures or nil, complete and Colors.Tamed or nil)
  self:SetRowSelected(button, self.selected ~= nil and self.selected.ability == ability
    and self.selected.rankIndex == rankIndex)

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

-- Abilities on the current tab that pass the filters and the search, by name. The search looks for creatures (a rank
-- shows while one of its creatures matches: RankShown); on the Passive tab, which has none, for the ability's name.
function Window:GetAbilities()
  local abilities = {}
  local byName = self.tab == "PASSIVE" and self.search ~= "" and self.search or nil
  -- With Window.SEARCH_HEADINGS on, the ranks of an ability whose own name matches: the search does not narrow them.
  self.namedRanks = nil
  if self.SEARCH_HEADINGS and self:CreatureSearch() then
    self.namedRanks = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      if Addon:GetAbilityTab(ability) == self.tab and self:HeadingMatches(ability.name) then
        for _, rank in ipairs(ability.ranks) do self.namedRanks[rank] = true end
      end
    end
  end
  for _, ability in pairs(Addon.TameableAbilities) do
    if Addon:GetAbilityTab(ability) == self.tab and #ability.ranks > 0
        and (not byName or ability.name:lower():find(byName, 1, true))
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
  -- The Zone Filter's zone for this drawing of the list (the Passive tab has no Zone button: trainers teach those),
  -- and each rank's number of creatures in it, counted afresh.
  self.listZone = self.tab ~= "PASSIVE" and self:ZoneFilter() or nil
  self.listSearch = self:CreatureSearch() -- (what was typed, on the tabs that list creatures)
  self.listRares = self:RaresOnly() -- (the Rares filter)
  self.listTamed = DB.global.filter_tamed -- (the Tamed filter)
  self.listFavorites = DB.global.filter_favorites -- (the Favorites filter)
  self.rankCreatures = {}
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
    for _, ability in ipairs(abilities) do
      local rank = ability.ranks[1]
      beasts = beasts + (self:CreatureCount(rank) or #self:AttackNPCs(rank)) -- (those that pass the zone and search)
    end
    self.headerCount:SetFormattedText(L.ATTACK_SPEED_COUNT, #abilities, beasts)
  else
    self.headerCount:SetFormattedText(L.RANKS_KNOWN, known, total)
  end
  self:UpdateToggleButton()

  self:UpdateDetails()
end

-- Whether the rank shown can be marked known by hand: one of the ability tabs, a rank that is learned (not an attack
-- speed, which belongs to a beast).
local ABILITY_TABS = { UNIQUE = true, COMMON = true, PASSIVE = true }
function Window:CanMarkKnown()
  local sel = self.selected
  return ABILITY_TABS[self.tab] == true and sel ~= nil and not sel.ability.attack_speed
end

-- A click on the details icon, with Known Ability Edit on (Options, Advanced: Window.knownEdit, this session only):
-- marks the rank shown known, or takes the mark back, by hand (Addon:SetRankKnown), and redraws the list and the
-- details in its new color. A rank the game verified (Beast Training listed it, or it was learned) stays known:
-- nothing happens. Returns whether it changed anything.
function Window:ToggleSelectedKnown()
  if not (self.knownEdit and self:CanMarkKnown()) then return false end
  local sel = self.selected
  if Addon:IsRankVerified(sel.ability, sel.rankIndex) then return false end
  local known = not Addon:IsRankKnown(sel.ability, sel.rankIndex)
  Addon:SetRankKnown(sel.ability, sel.rankIndex, known)
  if PlaySound and SOUNDKIT then
    PlaySound(known and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  end
  self:Refresh()
  return true
end

function Window:Select(ability, rankIndex)
  self.selected = { ability = ability, rankIndex = rankIndex }
  self:Remember()
  self:MarkSelected("rankInfo", function(info) return info.ability == ability and info.rankIndex == rankIndex end)
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
    Helpers.TipLine(L.CAN_LEARN, Colors.Available)
  else
    Helpers.TipLine(L.CANNOT_LEARN, Colors.Muted)
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
    local facts = {
      Helpers.Line(L.PET_LEVEL, rank.pet_level or 1),
      Helpers.Line(L.TRAINING_COST, rank.training_cost or 0),
    }
    -- What a trainer charges for it (the ranks a trainer sells), as on the website.
    if rank.trainer_cost then facts[#facts + 1] = Helpers.Line(L.PRICE, Helpers.Money(rank.trainer_cost)) end
    self.facts:SetText(table.concat(facts, "\n"))
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
  -- The Rares filter: only the rare creatures.
  if self:RaresOnly() then
    local rare = {}
    for _, npc in ipairs(npcs) do
      if self:NPCIsRare(npc) then rare[#rare + 1] = npc end
    end
    npcs = rare
  end
  -- The Tamed filter: only the creatures already tamed.
  if DB.global.filter_tamed then
    local tamed = {}
    for _, npc in ipairs(npcs) do
      if Addon:NPCMark(npc) == "tamed" then tamed[#tamed + 1] = npc end
    end
    npcs = tamed
  end
  -- The Favorites filter: only your favorites.
  if DB.global.filter_favorites then
    local favorites = {}
    for _, npc in ipairs(npcs) do
      if Addon:IsFavorite(npc.id) then favorites[#favorites + 1] = npc end
    end
    npcs = favorites
  end
  -- The search: only the creatures whose name holds what was typed.
  local total, search = #npcs, self:CreatureSearch()
  if search and not (self.namedRanks and self.namedRanks[rank]) then
    local found = {}
    for _, npc in ipairs(npcs) do
      if self:NPCMatchesSearch(npc, search) then found[#found + 1] = npc end
    end
    npcs = found
  end
  -- The Zone Filter: only the creatures in the player's zone, "2 of 5 in Westfall".
  local zone = self:ZoneFilter()
  if zone then
    local inZone = {}
    for _, npc in ipairs(npcs) do
      if self:NPCInZone(npc, zone) then inZone[#inZone + 1] = npc end
    end
    npcs = inZone
  end

  -- Learned from a Hunter or Pet Trainer, not from tamed creatures (`trainer` in the data: Growl and the passives). Its
  -- first rank without a price is the one every pet starts with (Growl Rank 1). As the website says it.
  local fromTrainer = ability.trainer == true or (ability.passive and not ability.unique and not ability.attack_speed)
  local knownByAll = fromTrainer and (rank.rank or rankIndex) == 1 and not rank.trainer_cost
  -- A unique rank no known creature has is a bounty (tab-bounties.lua): say so, and lead to it.
  local bounty = ability.unique and total == 0 and ("unique:%s:%d"):format(ability.key, rank.rank or rankIndex)
  self.npcShowFamily = false -- (a bounty's list names each creature's family; these are one ability's)
  self.npcLabel:SetText(knownByAll and L.KNOWN_BY_EVERY_PET or fromTrainer and L.LEARNED_FROM_TRAINER
    or bounty and ("%s (0): %s"):format(L.TAMEABLE_NPCS, L.UNIQUE_RANK_NONE)
    or zone and L.TAMEABLE_IN_ZONE:format(L.TAMEABLE_NPCS, #npcs, total, zone.name)
    or ("%s (%d):"):format(L.TAMEABLE_NPCS, #npcs))
  if bounty then
    local button = self.mapButton
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", self.npcLabel, "BOTTOMLEFT", 0, -8)
    button:SetText(L.UNIQUE_RANK_BOUNTY)
    button:SetWidth(math.ceil((button:GetTextWidth() or 200) + 24))
    button:SetScript("OnClick", function()
      PlayClick()
      self.selectedBounty = bounty
      self:SelectTab("BOUNTIES")
    end)
    button:Show()
  end
  local provider = CreateDataProvider(fromTrainer and {} or npcs)
  self.npcBox:SetDataProvider(provider)
  self.npcBox:SetShown(not fromTrainer)
  self.npcBar:SetShown(not fromTrainer)
end
