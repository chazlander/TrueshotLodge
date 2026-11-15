local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Bounties" tab: what we still want hunters to find, as on TrueshotLodge.com/bounties, worked out from the
-- addon's data. On the left: the Pet Bounties (Missing Rares, Missing Normals, Missing Forever, Missing Attack Speed,
-- Missing Zone, Missing Model);
-- the Unique Ability Targets (every rank of a family's unique ability, with the untamed creatures that might have it);
-- and
-- The Untamables (the hidden creatures hunters have uploaded, listed only so everyone can see what uploads brought in).
-- On the right, the selected one with its creatures and their Map Location buttons. The title bar's Zone Filter keeps
-- the creatures of the zone you are in, and Filter by Level the ones you can tame now (their lowest level at most yours).

local Line, PlayClick = Helpers.Line, Helpers.PlayClick
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON

local function Tamed(npc)
  return type(npc.tamed) == "string" and npc.tamed ~= ""
end

-- Whether the data has map points for a creature: the website lists rares, normal tames and attack speeds only for those.
local function HasMapPoints(npc)
  return npc.maps ~= nil and next(npc.maps) ~= nil
end

-- Whether a creature has a look (data/Looks.lua): the ids of those that do are gathered the first time it is asked.
local withLook
local function HasLook(id)
  if not withLook then
    withLook = {}
    for _, looks in pairs(Addon.TameableLooks or {}) do
      for _, look in ipairs(looks) do
        for _, npcId in ipairs(look.npcs or {}) do withLook[npcId] = true end
      end
    end
  end
  return withLook[id] == true
end

-- The pet bounties, in the website's order and with its words (app/Controllers/Bounties.php and PetModel::BOUNTIES).
-- KEEP IN STEP with those two: a bounty added or changed there is added or changed here. `wants(npc, id)` is the
-- website's condition, read from the data file.
local PET_BOUNTIES = {
  { key = "rares", name = L.BOUNTY_RARES, wanted = L.BOUNTY_RARES_WANTED, text = L.BOUNTY_RARES_TEXT,
    wants = function(npc) return (npc.class or ""):find("Rare", 1, true) ~= nil and not Tamed(npc) and HasMapPoints(npc) end },
  { key = "normals", name = L.BOUNTY_NORMALS, wanted = L.BOUNTY_NORMALS_WANTED, text = L.BOUNTY_NORMALS_TEXT,
    wants = function(npc) return (npc.class or ""):find("Rare", 1, true) == nil and not Tamed(npc) and HasMapPoints(npc) end },
  -- New in WoW Forever (`forever` in the data: patch 1.60 or later) and nobody has tamed it, located or not.
  { key = "forever", name = L.BOUNTY_FOREVER, wanted = L.BOUNTY_FOREVER_WANTED, text = L.BOUNTY_FOREVER_TEXT,
    wants = function(npc) return npc.forever == true and not Tamed(npc) end },
  { key = "attack-speed", name = L.BOUNTY_SPEED, wanted = L.BOUNTY_SPEED_WANTED, text = L.BOUNTY_SPEED_TEXT,
    wants = function(npc) return npc.speed == nil and HasMapPoints(npc) end },
  { key = "zone", name = L.BOUNTY_ZONE, wanted = L.BOUNTY_ZONE_WANTED, text = L.BOUNTY_ZONE_TEXT,
    wants = function(npc) return not (npc.zones and #npc.zones > 0) end },
  { key = "model", name = L.BOUNTY_MODEL, wanted = L.BOUNTY_MODEL_WANTED, text = L.BOUNTY_MODEL_TEXT,
    wants = function(_, id) return not HasLook(id) end },
}

-- Every rank of a family's unique ability (the website's Unique Ability Targets), each with how many known creatures
-- have it (`known`) and its potential targets: the family's creatures nobody has tamed, whose levels reach from the
-- pet level of the rank before to that of the rank after (from level 1 for a first rank, with no top for a last one),
-- less those known to have a rank of it (they have theirs). As the website works them out. The data does not change
-- while playing, so this is done once.
local uniqueEntries
local function UniqueRankTargets()
  if uniqueEntries then return uniqueEntries end
  uniqueEntries = {}
  for key, ability in pairs(Addon.TameableAbilities or {}) do
    local family = ability.unique and ability.learned_by and ability.learned_by[1]
    if family then
      local known, numbered = {}, {}
      for index, rank in ipairs(ability.ranks) do
        numbered[#numbered + 1] = { rank = rank, number = rank.rank or index }
        for _, id in ipairs(rank.npc_ids or {}) do known[id] = true end
      end
      for _, this in ipairs(numbered) do
        local before, after
        for _, other in ipairs(numbered) do
          if other.number < this.number and (not before or other.number > before.number) then before = other end
          if other.number > this.number and (not after or other.number < after.number) then after = other end
        end
        local low = before and before.rank.pet_level or 1
        local high = after and after.rank.pet_level or nil
        local targets = {}
        for id, npc in pairs(Addon.TameableNPCs or {}) do
          if npc.family == family and npc.min and not Tamed(npc) and not known[id] and not npc.not_tameable then
            if (npc.max or npc.min) >= low and (not high or npc.min <= high) then targets[#targets + 1] = id end
          end
        end
        uniqueEntries[#uniqueEntries + 1] = {
          key = "unique:" .. key .. ":" .. this.number, ability = ability, rank = this.rank, number = this.number,
          family = family, before = before, after = after, low = low, high = high, targetIds = targets,
          known = this.rank.npc_ids and #this.rank.npc_ids or 0,
        }
      end
    end
  end
  table.sort(uniqueEntries, function(a, b)
    if a.ability.key ~= b.ability.key then return a.ability.key < b.ability.key end
    return a.number < b.number
  end)
  return uniqueEntries
end

-- Which creatures each pet bounty wants (the raw data is enough to tell; only those are made ready to show). The
-- tests read only the data file, which does not change while playing, so this is done once.
local wantedIds
local function WantedIds()
  if wantedIds then return wantedIds end
  wantedIds = {}
  for _, bounty in ipairs(PET_BOUNTIES) do wantedIds[bounty.key] = {} end
  for id, npc in pairs(Addon.TameableNPCs or {}) do
    -- (a creature the game refuses to tame is nothing to find: no bounty wants it, as on the website)
    if not Addon.IGNORED_NPC_IDS[id] and not npc.not_tameable then
      for _, bounty in ipairs(PET_BOUNTIES) do
        if bounty.wants(npc, id) then table.insert(wantedIds[bounty.key], id) end
      end
    end
  end
  return wantedIds
end

-- The Untamables' ids (Addon.TameableUntamables, from the export), in no order: BountyCreatures sorts them.
local untamableIds
local function UntamableIds()
  if untamableIds then return untamableIds end
  untamableIds = {}
  for id in pairs(Addon.TameableUntamables or {}) do untamableIds[#untamableIds + 1] = id end
  return untamableIds
end

-- "level 24 (Rank 3)", or "level 1" for no rank before.
local function LevelAt(level, neighbour)
  return neighbour and L.BOUNTY_LEVEL_RANK:format(level, L.RANK, neighbour.number) or L.BOUNTY_LEVEL:format(level)
end

-- Where a rank without source most likely is, as the website says it.
local function RangeText(entry)
  if not entry.high then return L.BOUNTY_RANGE_FROM:format(LevelAt(entry.low, entry.before)) end
  return L.BOUNTY_RANGE_BETWEEN:format(LevelAt(entry.low, entry.before), LevelAt(entry.high, entry.after))
end

-- ----------------------------------------------------------------------------
-- The creatures of a bounty, with the filters
-- ----------------------------------------------------------------------------

-- Whether a creature passes the filters: the search (its name holds what was typed; not asked with `anyName`, for an
-- entry whose own name matched: Window:HeadingMatches), the Zone Filter (the zone you are in) and Filter by Level (one
-- you can tame now).
function Window:BountyNPCShown(npc, zone, level, anyName)
  if not anyName and not self:NPCMatchesSearch(npc, self:CreatureSearch()) then return false end
  if self:RaresOnly() and not self:NPCIsRare(npc) then return false end -- (the Rares filter)
  if zone and not self:NPCInZone(npc, zone) then return false end
  if DB.global.filter_by_level and not (npc.min and npc.min <= level) then return false end
  return true
end

-- The creatures, ready to show (Addon:GetNPC, or Addon:GetUntamable for The Untamables when `untamables` is set),
-- that pass the filters: the lowest level first, or with Filter by Level on the highest first (the closest to yours).
-- Creatures without a known level come last.
function Window:BountyCreatures(ids, zone, level, untamables, anyName)
  local list = {}
  for _, id in ipairs(ids) do
    local npc
    if untamables then npc = Addon:GetUntamable(id) else npc = Addon:GetNPC(id) end
    if npc and self:BountyNPCShown(npc, zone, level, anyName) then list[#list + 1] = npc end
  end
  local highestFirst = DB.global.filter_by_level
  table.sort(list, function(a, b)
    if (a.min ~= nil) ~= (b.min ~= nil) then return a.min ~= nil end
    if a.min and a.min ~= b.min then
      if highestFirst then return a.min > b.min end
      return a.min < b.min
    end
    return (a.name or "") < (b.name or "")
  end)
  return list
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

-- How a heading's rows are sorted: alphabetically (the default), or by their number of creatures, the most first.
-- Right-clicking the heading switches it; the choice is saved (DB.global.bounty_sort: heading key -> "count").
local function SortedByCount(groupKey)
  return (DB.global.bounty_sort or {})[groupKey] == "count"
end

local function SortRows(group)
  local byCount = SortedByCount(group.key)
  table.sort(group.rows, function(a, b)
    if byCount and a.count ~= b.count then return a.count > b.count end
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return (a.sortNumber or 0) < (b.sortNumber or 0)
  end)
  group.sortable = true
  group.title = group.name
  group.hint = byCount and L.BOUNTY_SORT_BY_NAME or L.BOUNTY_SORT_BY_COUNT
end

function Window:ToggleBountySort(groupKey)
  DB.global.bounty_sort = DB.global.bounty_sort or {}
  DB.global.bounty_sort[groupKey] = not SortedByCount(groupKey) and "count" or nil
  self:RefreshBounties()
end

-- The headers with their rows: { { key, name, rows = { { key, kind, label, count, creatures, bounty | entry } } } }.
-- While searching (the search box looks for creatures), a row none of whose creatures match is not listed.
function Window:GetBountyGroups()
  local searching = self:CreatureSearch() ~= nil
  local zone, level = self:ZoneFilter(), UnitLevel("player") or 1
  local groups = {}

  -- (How to claim one is in the Help section: tab-help.lua.)

  local wanted = WantedIds()
  local pets = { key = "bounties:pets", name = L.PET_BOUNTIES, rows = {} }
  for _, bounty in ipairs(PET_BOUNTIES) do
    local named = self:HeadingMatches(bounty.name)
    local creatures = self:BountyCreatures(wanted[bounty.key], zone, level, false, named)
    if #creatures > 0 or not searching or named then
      pets.rows[#pets.rows + 1] = { key = bounty.key, kind = "pet", label = bounty.name, count = #creatures,
        creatures = creatures, bounty = bounty, sortName = bounty.name }
    end
  end
  if #pets.rows > 0 then
    SortRows(pets)
    groups[#groups + 1] = pets
  end

  local unique = { key = "bounties:unique", name = L.UNIQUE_TARGETS, rows = {} }
  for _, entry in ipairs(UniqueRankTargets()) do
    local title = ("%s (%s %d)"):format(entry.ability.name, L.RANK, entry.number)
    local named = self:HeadingMatches(title, entry.family)
    local creatures = self:BountyCreatures(entry.targetIds, zone, level, false, named)
    if #creatures > 0 or not searching or named then
      unique.rows[#unique.rows + 1] = { key = entry.key, kind = "unique", count = #creatures, creatures = creatures,
        entry = entry, title = title, sortName = entry.ability.name, sortNumber = entry.number,
        label = ("|T%s:14:14:0:0|t %s"):format(Addon:FamilyIcon(entry.family) or QUESTION_MARK_ICON, title) }
    end
  end
  if #unique.rows > 0 then
    SortRows(unique)
    groups[#groups + 1] = unique
  end

  -- The Untamables: one entry, Hidden Creatures, listing them. Nothing to claim, so it has no sort to switch.
  local named = self:HeadingMatches(L.UNTAMABLES_NAME, L.UNTAMABLES)
  local creatures = self:BountyCreatures(UntamableIds(), zone, level, true, named)
  if #creatures > 0 or not searching or named then
    groups[#groups + 1] = { key = "bounties:untamables", name = L.UNTAMABLES, title = L.UNTAMABLES, rows = {
      { key = "untamables", kind = "untamables", label = L.UNTAMABLES_NAME, count = #creatures, creatures = creatures },
    } }
  end
  return groups
end

local function BountyOnClick(button)
  PlayClick()
  Window:SelectBounty(button.ftBounty.key)
end

local function BountyOnEnter(button)
  local row = button.ftBounty
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if row.kind == "pet" then
    GameTooltip:SetText(row.bounty.name)
    GameTooltip:AddLine(row.bounty.wanted, 1, 1, 1)
  elseif row.kind == "untamables" then
    GameTooltip:SetText(row.label)
    GameTooltip:AddLine(L.UNTAMABLES_WANTED, 1, 1, 1)
  elseif row.kind == "unique" then
    GameTooltip:SetText(row.title)
    GameTooltip:AddLine(Addon:FamilyLabel(row.entry.family), 1, 1, 1)
  else
    GameTooltip:SetText(row.label)
  end
  GameTooltip:Show()
end

function Window:InitBountyButton(button, row)
  button.Label:SetText(row.label)
  button.Label:SetVertexColor(Colors.Default:GetRGB())
  -- The number of creatures, on the right like a badge (as on the website, and the ability tabs' ranks).
  self:SetRowCount(button, row.count)
  self:SetRowSelected(button, self.selectedBounty == row.key)

  button.ftBounty = row
  button:RegisterForClicks("LeftButtonUp") -- (a row the Collected Data tab used also took right-clicks)
  button:SetScript("OnClick", BountyOnClick)
  button:SetScript("OnEnter", BountyOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:RefreshBounties()
  local groups = self:GetBountyGroups()
  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.bountyByKey = {}
  self.bountyHeadersSeen = self.bountyHeadersSeen or {}
  local first
  for _, group in ipairs(groups) do
    self.listKeys[#self.listKeys + 1] = group.key
    -- A header starts open the first time it is shown; after that it stays as the player left it.
    if not self.bountyHeadersSeen[group.key] then
      self.bountyHeadersSeen[group.key] = true
      self.expanded[group.key] = true
    end
    -- (sortable: right-clicking the heading switches the sort; hint: its tooltip says how)
    local category = provider:Insert({ categoryInfo = { name = group.name }, key = group.key, sortable = group.sortable,
      title = group.title, hint = group.hint })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows) do
      category:Insert({ bounty = row })
      self.bountyByKey[row.key] = row
      first = first or row.key
    end
  end
  -- The selection: the one shown before, else the one saved (sticky selections), else the first.
  if not (self.selectedBounty and self.bountyByKey[self.selectedBounty]) then
    local saved = self:Sticky() and DB.global.selections.BOUNTIES
    self.selectedBounty = (saved and self.bountyByKey[saved]) and saved or first
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetText(L.WANTED_TAMES)
  self:UpdateToggleButton()
  self:UpdateBountyDetails()
end

function Window:SelectBounty(key)
  self.selectedBounty = key
  self:Remember()
  self:MarkSelected("bounty", function(row) return row.key == key end)
  self:UpdateBountyDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

-- The creature list under the description: its label with the count (and the zone, with the Zone Filter on), or why
-- it is empty. `showFamily`: each creature's family in its row too (a list of mixed families, as the website's bounties).
function Window:ShowBountyCreatures(creatures, label, emptyText, showFamily)
  self.npcShowFamily = showFamily == true -- (read by Window:InitNPCRow)
  local zone = self:ZoneFilter()
  if #creatures > 0 then
    local text = label:format(#creatures)
    if zone then text = ("%s  %s"):format(text, Colors.Muted(zone.name)) end
    self.npcLabel:SetText(text)
  elseif zone or DB.global.filter_by_level or self:RaresOnly() then
    self.npcLabel:SetText(L.BOUNTY_FILTERED_NONE)
  else
    self.npcLabel:SetText(emptyText)
  end
  self.npcLabel:Show()
  self.npcBox:SetDataProvider(CreateDataProvider(creatures))
  self.npcBox:SetShown(#creatures > 0)
  self.npcBar:SetShown(#creatures > 0)
end

function Window:UpdateBountyDetails()
  local row = self.selectedBounty and self.bountyByKey and self.bountyByKey[self.selectedBounty]
  if not row then
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  -- A pet bounty (and The Untamables): the name across the whole pane, what it wants in white under it (no facts), and
  -- the creatures straight after. The others keep the usual layout.
  local wide = row.kind == "pet" or row.kind == "untamables"
  self:SetTopWide(wide, wide)
  self.npcLabel:ClearAllPoints()
  if wide then
    self.npcLabel:SetPoint("TOP", self.subtitle, "BOTTOM", 0, -12)
    self.npcLabel:SetPoint("LEFT", self.details, "LEFT", Window.DETAILS_LEFT, 0)
  else
    self.npcLabel:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -14)
  end
  self.npcLabel:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)

  local lines = {}
  local description -- each kind below sets it
  local function add(line) if line then lines[#lines + 1] = line end end
  if row.kind == "pet" then
    self.icon:SetTexture(Window.BOUNTY_ICON)
    self.name:SetText(row.bounty.name)
    self.subtitle:SetText(row.bounty.text)
    self:ShowBountyCreatures(row.creatures, L.BOUNTY_CREATURES, L.BOUNTY_NONE, true)
  elseif row.kind == "untamables" then
    self.icon:SetTexture(Window.BOUNTY_ICON)
    self.name:SetText(L.UNTAMABLES)
    self.subtitle:SetText(L.UNTAMABLES_TEXT)
    self:ShowBountyCreatures(row.creatures, L.UNTAMABLES_CREATURES, L.UNTAMABLES_NONE, true)
  else
    local entry = row.entry
    self.icon:SetTexture(entry.ability.icon or QUESTION_MARK_ICON)
    self.name:SetText(entry.ability.name)
    self.subtitle:SetText(("%s %d"):format(L.RANK, entry.number))
    add(Line(L.FAMILY, Addon:FamilyLabel(entry.family)))
    add(Line(L.PET_LEVEL, entry.rank.pet_level))
    add(Line(L.BOUNTY_KNOWN_COUNT, entry.known))
    add(Line(L.BOUNTY_TARGET_COUNT, #row.creatures))
    -- What is known of it, then where the untamed ones that might have it are.
    description = entry.known == 0 and L.BOUNTY_UNIQUE_TEXT:format(entry.family, RangeText(entry))
      or L.BOUNTY_UNIQUE_KNOWN_TEXT:format(entry.known, entry.family, RangeText(entry))
    self:ShowBountyCreatures(row.creatures, L.BOUNTY_TARGETS, L.BOUNTY_TARGETS_NONE:format(entry.family))
  end

  self.facts:SetText(table.concat(lines, "\n"))
  self.description:SetText(description or "")
  self:PlaceDescription()
end
