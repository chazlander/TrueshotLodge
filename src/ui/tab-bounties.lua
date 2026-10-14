local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Bounties" tab: what we still want hunters to find, as on TrueshotLodge.com/bounties, worked out from the
-- addon's data. On the left: How to Claim; the Pet Bounties (Missing Tamed Rares, Missing Attack Speed, Missing Zone);
-- and the Unique Abilities without Source (ranks of a family's unique ability that no known tameable creature has). On
-- the right, the selected one with its creatures and their Map Location buttons. The title bar's Zone Filter keeps the
-- creatures of the zone you are in, and Filter by Level the ones you can tame now (their lowest level at most yours).

local Line, PlayClick = Helpers.Line, Helpers.PlayClick
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON
local COUNT_COLOR = { 0.78, 0.69, 0.55 } -- the tan of the website's count badges

local function Tamed(npc)
  return type(npc.tamed) == "string" and npc.tamed ~= ""
end

-- Whether the data has map points for a creature: the website lists rares and attack speeds only for those.
local function HasMapPoints(npc)
  return npc.maps ~= nil and next(npc.maps) ~= nil
end

-- The pet bounties, in the website's order and with its words (app/Controllers/Bounties.php and PetModel::BOUNTIES).
local PET_BOUNTIES = {
  { key = "rares", name = L.BOUNTY_RARES, wanted = L.BOUNTY_RARES_WANTED, text = L.BOUNTY_RARES_TEXT,
    wants = function(npc) return (npc.class or ""):find("Rare", 1, true) ~= nil and not Tamed(npc) and HasMapPoints(npc) end },
  { key = "attack-speed", name = L.BOUNTY_SPEED, wanted = L.BOUNTY_SPEED_WANTED, text = L.BOUNTY_SPEED_TEXT,
    wants = function(npc) return npc.speed == nil and HasMapPoints(npc) end },
  { key = "zone", name = L.BOUNTY_ZONE, wanted = L.BOUNTY_ZONE_WANTED, text = L.BOUNTY_ZONE_TEXT,
    wants = function(npc) return not (npc.zones and #npc.zones > 0) end },
}

-- The ranks of a family's unique ability that no known tameable creature has, each with its potential targets: the
-- family's creatures nobody has tamed, whose levels reach from the pet level of the rank before to that of the rank
-- after (from level 1 for a first rank, with no top for a last one), less those known to have another rank of it. As
-- the website works them out. The data does not change while playing, so this is done once.
local uniqueEntries
local function UniqueRanksWithoutSource()
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
        if not (this.rank.npc_ids and #this.rank.npc_ids > 0) then
          local before, after
          for _, other in ipairs(numbered) do
            if other.number < this.number and (not before or other.number > before.number) then before = other end
            if other.number > this.number and (not after or other.number < after.number) then after = other end
          end
          local low = before and before.rank.pet_level or 1
          local high = after and after.rank.pet_level or nil
          local targets = {}
          for id, npc in pairs(Addon.TameableNPCs or {}) do
            if npc.family == family and npc.min and not Tamed(npc) and not known[id] then
              if (npc.max or npc.min) >= low and (not high or npc.min <= high) then targets[#targets + 1] = id end
            end
          end
          uniqueEntries[#uniqueEntries + 1] = {
            key = "unique:" .. key .. ":" .. this.number, ability = ability, rank = this.rank, number = this.number,
            family = family, before = before, after = after, low = low, high = high, targetIds = targets,
          }
        end
      end
    end
  end
  table.sort(uniqueEntries, function(a, b)
    if a.ability.key ~= b.ability.key then return a.ability.key < b.ability.key end
    return a.number < b.number
  end)
  return uniqueEntries
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

-- Whether a creature passes the filters: the Zone Filter (the zone you are in) and Filter by Level (one you can tame now).
function Window:BountyNPCShown(npc, zone, level)
  if zone and not self:NPCInZone(npc, zone) then return false end
  if DB.global.filter_by_level and not (npc.min and npc.min <= level) then return false end
  return true
end

-- The creatures, ready to show (Addon:GetNPC), that pass the filters: the lowest level first, or with Filter by
-- Level on the highest first (the closest to yours). Creatures without a known level come last.
function Window:BountyCreatures(ids, zone, level)
  local list = {}
  for _, id in ipairs(ids) do
    local npc = Addon:GetNPC(id)
    if npc and self:BountyNPCShown(npc, zone, level) then list[#list + 1] = npc end
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
function Window:GetBountyGroups()
  local search = self.search or ""
  local function matches(text)
    return search == "" or tostring(text):lower():find(search, 1, true) ~= nil
  end
  local zone, level = self:ZoneFilter(), UnitLevel("player") or 1
  local groups = {}

  -- How to claim one, and whether Collect Mode and Send Name are on. Left out while searching.
  if search == "" then
    groups[#groups + 1] = { key = "bounties:claim", name = L.BOUNTIES_ROW, rows = {
      { key = "claim", kind = "claim", label = L.BOUNTY_HOW_TO_CLAIM },
    } }
  end

  -- Which creatures each pet bounty wants (the raw data is enough to tell; only those are made ready to show).
  local wanted = {}
  for _, bounty in ipairs(PET_BOUNTIES) do wanted[bounty.key] = {} end
  for id, npc in pairs(Addon.TameableNPCs or {}) do
    if not Addon.IGNORED_NPC_IDS[id] then
      for _, bounty in ipairs(PET_BOUNTIES) do
        if bounty.wants(npc) then table.insert(wanted[bounty.key], id) end
      end
    end
  end
  local pets = { key = "bounties:pets", name = L.PET_BOUNTIES, rows = {} }
  for _, bounty in ipairs(PET_BOUNTIES) do
    if matches(bounty.name) then
      local creatures = self:BountyCreatures(wanted[bounty.key], zone, level)
      pets.rows[#pets.rows + 1] = { key = bounty.key, kind = "pet", label = bounty.name, count = #creatures,
        creatures = creatures, bounty = bounty, sortName = bounty.name }
    end
  end
  if #pets.rows > 0 then
    SortRows(pets)
    groups[#groups + 1] = pets
  end

  local unique = { key = "bounties:unique", name = L.UNIQUE_WITHOUT_SOURCE, rows = {} }
  for _, entry in ipairs(UniqueRanksWithoutSource()) do
    local title = ("%s (%s %d)"):format(entry.ability.name, L.RANK, entry.number)
    if matches(title .. " " .. entry.family) then
      local creatures = self:BountyCreatures(entry.targetIds, zone, level)
      unique.rows[#unique.rows + 1] = { key = entry.key, kind = "unique", count = #creatures, creatures = creatures,
        entry = entry, title = title, sortName = entry.ability.name, sortNumber = entry.number,
        label = ("|T%s:14:14:0:0|t %s"):format(Addon:FamilyIcon(entry.family) or QUESTION_MARK_ICON, title) }
    end
  end
  if #unique.rows > 0 then
    SortRows(unique)
    groups[#groups + 1] = unique
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
  button.Label:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  -- The number of creatures, on the right like a badge (as on the website, and the ability tabs' ranks).
  if row.count then
    button.Count:ClearAllPoints()
    button.Count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.Count:SetText(("(%d)"):format(row.count))
    button.Count:SetTextColor(unpack(COUNT_COLOR))
    button.Count:Show()
    button.Label:SetWidth(button:GetWidth() - 60)
  else
    button.Count:Hide()
    button.Label:SetWidth(button:GetWidth() - 20)
  end

  local selected = self.selectedBounty == row.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

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
  local wanted = { rares = 0, ["attack-speed"] = 0, zone = 0, unique = 0 }
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
      if row.kind == "pet" then wanted[row.key] = row.count end
      if row.kind == "unique" then wanted.unique = wanted.unique + 1 end
    end
  end
  -- The selection: the one shown before, else the one saved (sticky selections), else the first.
  if not (self.selectedBounty and self.bountyByKey[self.selectedBounty]) then
    local saved = self:Sticky() and DB.global.selections.BOUNTIES
    self.selectedBounty = (saved and self.bountyByKey[saved]) and saved or first
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetFormattedText(L.BOUNTY_COUNTS, wanted.rares, wanted["attack-speed"], wanted.zone, wanted.unique)
  self:UpdateToggleButton()
  self:UpdateBountyDetails()
end

function Window:SelectBounty(key)
  self.selectedBounty = key
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local row = node:GetData().bounty
    if row then
      button.SelectedOverlay:SetShown(row.key == key)
      button.HighlightOverlay:SetShown(row.key ~= key)
    end
  end)
  self:UpdateBountyDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

-- The creature list under the description: its label with the count (and the zone, with the Zone Filter on), or why
-- it is empty.
function Window:ShowBountyCreatures(creatures, label, emptyText)
  local zone = self:ZoneFilter()
  if #creatures > 0 then
    local text = label:format(#creatures)
    if zone then text = ("%s  |cFF9D9D9D%s|r"):format(text, zone.name) end
    self.npcLabel:SetText(text)
  elseif zone or DB.global.filter_by_level then
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

  local lines = {}
  local description -- each kind below sets it
  local function add(line) if line then lines[#lines + 1] = line end end
  if row.kind == "claim" then
    self.icon:SetTexture(Window.BOUNTY_ICON)
    self.name:SetText(L.BOUNTY_HOW_TO_CLAIM)
    self.subtitle:SetText(L.BOUNTIES_SITE)
    local sendName = DB.global.send_name == true
    add(Line(L.COLLECT_MODE, DB.global.collect and L.ON or L.OFF))
    add(Line(L.SEND_NAME, sendName and L.ON or L.OFF))
    add(Line(L.TAMED_CREATURES, #(DB.collected.tames or {})))
    description = L.BOUNTIES_TEXT .. "\n\n" .. L.BOUNTY_CLAIM_STEPS .. "\n\n"
      .. (sendName and L.BOUNTIES_NAME_ON:format(Addon:PlayerName() or "?") or Colors.Highlight(L.BOUNTIES_NAME_OFF))
    self.npcLabel:Hide()
    self.npcBox:Hide()
    self.npcBar:Hide()
  elseif row.kind == "pet" then
    self.icon:SetTexture(Window.BOUNTY_ICON)
    self.name:SetText(row.bounty.name)
    self.subtitle:SetText(row.bounty.wanted)
    add(Line(L.BOUNTY_CREATURE_COUNT, #row.creatures))
    description = row.bounty.text
    self:ShowBountyCreatures(row.creatures, L.BOUNTY_CREATURES, L.BOUNTY_NONE)
  else
    local entry = row.entry
    self.icon:SetTexture(entry.ability.icon or QUESTION_MARK_ICON)
    self.name:SetText(entry.ability.name)
    self.subtitle:SetText(("%s %d"):format(L.RANK, entry.number))
    add(Line(L.FAMILY, Addon:FamilyLabel(entry.family)))
    add(Line(L.PET_LEVEL, entry.rank.pet_level))
    add(Line(L.BOUNTY_TARGET_COUNT, #row.creatures))
    description = L.BOUNTY_UNIQUE_TEXT:format(entry.family, RangeText(entry))
    self:ShowBountyCreatures(row.creatures, L.BOUNTY_TARGETS, L.BOUNTY_TARGETS_NONE:format(entry.family))
  end

  self.facts:SetText(table.concat(lines, "\n"))
  self.description:SetText(description or "")
  self:PlaceDescription()
end
