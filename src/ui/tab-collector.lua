local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local Collector = Addon:GetModule("Collector")
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")
local Helpers = Addon:GetModule("Helpers")
local Line, LevelText, Money = Helpers.Line, Helpers.LevelText, Helpers.Money
local SpellIcon, ZoneNames = Helpers.SpellIcon, Helpers.ZoneNames

local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON

local function FamilyIcon(family)
  return Addon:FamilyIcon(family) or QUESTION_MARK_ICON
end

-- "1.20 (Faster Attack VI)", or nil without a speed (so the line is left out).
local function SpeedText(speed)
  return speed and Addon:AttackSpeedText(speed) or nil
end

-- The "Collected Data" tab: while collecting is on, what the collector has recorded so far, in the same list and
-- details layout as the other tabs, in three sections: Wild Sightings (the creatures seen, by family), Tamed
-- Creatures (the beasts you tamed) and Trainers (the pet trainers talked to, and the Beast Training entries). A creature that is not in the addon's data yet is highlighted, since that is what the
-- collector is for.

local NEW_COLOR = CreateColorFromHexString and CreateColorFromHexString("FFC6AF8D")
  or { GetRGB = function() return 0.776, 0.686, 0.553 end }
-- In front of an entry another TrueshotLodge user shared (`shared_by`): a blue dot.
local SHARED_DOT = "|cFF3FA9F5\226\128\162|r " -- U+2022 BULLET

local function Collecting()
  return DB.global ~= nil and DB.global.collect == true
end

local STATUS_WORDS = { available = true, unavailable = true, used = true }

-- ----------------------------------------------------------------------------
-- The data, as list groups: { { key, name, rows = { { key, kind, label, data, isNew } } } }
-- ----------------------------------------------------------------------------

function Window:GetCollectedGroups()
  local search = self.search or ""
  local function matches(text)
    return search == "" or tostring(text):lower():find(search, 1, true) ~= nil
  end

  local groups, byFamily = {}, {}
  for id, c in pairs(DB.collected.creatures or {}) do
    local family = c.family or L.UNKNOWN
    if not Addon.IGNORED_NPC_IDS[tonumber(id)] and matches((c.name or "") .. " " .. family) then
      local group = byFamily[family]
      if not group then
        group = { key = "creatures:" .. family, family = family, rows = {} }
        byFamily[family] = group
        groups[#groups + 1] = group
      end
      group.rows[#group.rows + 1] = {
        key = "c:" .. tostring(id), kind = "creature", data = c, isNew = Addon.TameableNPCs[c.id] == nil,
        store = "creatures", storeKey = id,
        label = ("%s  |cFF9D9D9D%s %s|r"):format(c.name or "?", L.LEVEL, LevelText(c.level_min, c.level_max)),
      }
    end
  end
  table.sort(groups, function(a, b) return a.family < b.family end)
  for _, group in ipairs(groups) do
    table.sort(group.rows, function(a, b) return (a.data.name or "") < (b.data.name or "") end)
    group.name = ("|T%s:18:18:0:0|t %s (%d)"):format(FamilyIcon(group.family), Addon:FamilyLabel(group.family), #group.rows)
  end

  -- Tamed beasts, newest first.
  local tames = { rows = {} }
  for index, tame in ipairs(DB.collected.tames or {}) do
    if matches((tame.name or "") .. " " .. (tame.family or "")) then
      tames.rows[#tames.rows + 1] = {
        key = "m:" .. index, kind = "tame", data = tame, index = index, store = "tames", storeKey = index,
        label = ("%s  |cFF9D9D9D%s %s|r"):format(tame.name or "?", L.LEVEL, tostring(tame.level or "?")),
      }
    end
  end
  table.sort(tames.rows, function(a, b) return a.index > b.index end)

  local training = { key = "training", name = ("%s (%%d)"):format(L.BEAST_TRAINING), rows = {} }
  for key, entry in pairs(DB.collected.beast_training or {}) do
    if matches(entry.name or "") then
      -- Older saved entries hold the status ("used") where the rank should be.
      local rank = (entry.rank and not STATUS_WORDS[entry.rank]) and entry.rank or nil
      training.rows[#training.rows + 1] = {
        key = "t:" .. tostring(key), kind = "training", data = entry, rank = rank, store = "beast_training", storeKey = key,
        label = ("%s%s"):format(entry.name or "?", rank and (" " .. rank) or ""),
      }
    end
  end
  -- By name, then by rank as a number (Rank 10 comes after Rank 9).
  table.sort(training.rows, function(a, b)
    local aName, bName = a.data.name or "", b.data.name or ""
    if aName ~= bName then return aName < bName end
    local aRank, bRank = tonumber((a.rank or ""):match("%d+")) or 0, tonumber((b.rank or ""):match("%d+")) or 0
    if aRank ~= bRank then return aRank < bRank end
    return (a.rank or "") < (b.rank or "")
  end)

  local trainers = { key = "trainers", name = ("%s (%%d)"):format(L.TRAINERS), rows = {} }
  for id, trainer in pairs(DB.collected.trainers or {}) do
    if matches((trainer.name or "") .. " " .. (trainer.title or "")) then
      trainers.rows[#trainers.rows + 1] = {
        key = "r:" .. tostring(id), kind = "trainer", data = trainer, store = "trainers", storeKey = id,
        label = ("%s  |cFF9D9D9D%s|r"):format(trainer.name or "?",
          trainer.ui_map_id and ZoneNames({ [trainer.ui_map_id] = true }) or ""),
      }
    end
  end
  table.sort(trainers.rows, function(a, b) return (a.data.name or "") < (b.data.name or "") end)

  -- The three sections (each only when it has something): Tamed Creatures, Wild Sightings with a header per family,
  -- and Trainers with Beast Training as a header of its own under the trainers.
  local sections = {}
  if #tames.rows > 0 then
    sections[#sections + 1] = { key = "section:tamed", section = true, rows = tames.rows,
      name = ("%s (%d)"):format(L.TAMED_CREATURES, #tames.rows) }
  end
  local wild = 0
  for _, group in ipairs(groups) do wild = wild + #group.rows end
  if wild > 0 then
    sections[#sections + 1] = { key = "section:wild", section = true, rows = {}, children = groups,
      name = ("%s (%d)"):format(L.WILD_SIGHTINGS, wild) }
  end
  if #trainers.rows + #training.rows > 0 then
    local children = {}
    if #training.rows > 0 then
      training.name = training.name:format(#training.rows)
      children[1] = training
    end
    sections[#sections + 1] = { key = "section:trainers", section = true, rows = trainers.rows, children = children,
      name = ("%s (%d)"):format(L.TRAINERS, #trainers.rows + #training.rows) }
  end
  return sections
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

local function CollectedOnClick(button, mouseButton)
  if mouseButton == "RightButton" then
    Window:AskToDelete(button.ftCollected)
  else
    Window:SelectCollected(button.ftCollected.key)
  end
end

local function CollectedOnEnter(button)
  local row = button.ftCollected
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.data.name or "?")
  if row.kind == "creature" then
    GameTooltip:AddLine(row.isNew and "Not in the data yet" or "In the data, with something new", 1, 1, 1)
  end
  if row.data.shared_by then GameTooltip:AddLine(("%s: %s"):format(L.SHARED_BY, row.data.shared_by), 1, 1, 1) end
  if row.store then GameTooltip:AddLine(L.RIGHT_CLICK_TO_DELETE, 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

function Window:InitCollectedButton(button, row)
  button.Label:SetText((row.data.shared_by and SHARED_DOT or "") .. row.label)
  button.Label:SetWidth(button:GetWidth() - 20)
  button.Label:SetVertexColor((row.isNew and NEW_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  button.Count:Hide()

  local selected = self.selectedCollected == row.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

  button.ftCollected = row
  -- Only this tab's rows take a right-click (the rows are shared with the other tabs, which set left-click back).
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", CollectedOnClick)
  button:SetScript("OnEnter", CollectedOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:RefreshCollector()
  if not Collecting() then
    -- Turned off while looking at it: back to the first tab.
    self:SelectTab("UNIQUE")
    return
  end

  local sections = self:GetCollectedGroups()
  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.collectedByKey = {}
  self.sectionsSeen = self.sectionsSeen or {}
  local first, total = nil, 0
  -- A header with its entries, then its own headers under it (a section's families, Beast Training).
  local function add(parent, group)
    self.listKeys[#self.listKeys + 1] = group.key
    -- A section starts open the first time it appears; after that it stays as the player left it.
    if group.section and not self.sectionsSeen[group.key] then
      self.sectionsSeen[group.key] = true
      self.expanded[group.key] = true
    end
    local category = parent:Insert({ categoryInfo = { name = group.name }, key = group.key })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows or {}) do
      category:Insert({ collected = row })
      self.collectedByKey[row.key] = row
      first = first or row.key
      total = total + 1
    end
    for _, child in ipairs(group.children or {}) do add(category, child) end
  end
  for _, section in ipairs(sections) do add(provider, section) end
  if not (self.selectedCollected and self.collectedByKey[self.selectedCollected]) then
    self.selectedCollected = first
  end

  -- Keep the scroll position: new records arrive while the tab is open.
  self.collectedVersion = Collector.version
  self.scrollBox:SetDataProvider(provider, true)
  self.noResults:SetShown(first == nil)
  local creatures, training = Collector:Count(), self:CountOf(DB.collected.beast_training)
  local trainers, tames = self:CountOf(DB.collected.trainers), #(DB.collected.tames or {})
  self.headerCount:SetFormattedText(L.COLLECTED_COUNTS, creatures + tames + training + trainers, creatures, tames, training,
    trainers)
  self:UpdateToggleButton()
  self:UpdateCollectedDetails()
end

function Window:CountOf(tbl)
  local n = 0
  for _ in pairs(tbl or {}) do n = n + 1 end
  return n
end

function Window:SelectCollected(key)
  self.selectedCollected = key
  self.scrollBox:ForEachFrame(function(button, node)
    local row = node:GetData().collected
    if row then
      button.SelectedOverlay:SetShown(row.key == key)
      button.HighlightOverlay:SetShown(row.key ~= key)
    end
  end)
  self:UpdateCollectedDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

function Window:UpdateCollectedDetails()
  local row = self.selectedCollected and self.collectedByKey and self.collectedByKey[self.selectedCollected]
  if not row then
    self.details:Hide()
    return
  end
  self.details:Show()
  self.npcLabel:Hide()
  self.npcBox:Hide()
  self.npcBar:Hide()
  self.mapButton:Hide()
  self.miniMap:Hide()

  local d = row.data
  local lines, description
  if row.kind == "creature" then
    self.icon:SetTexture(FamilyIcon(d.family))
    self.name:SetText(d.name or "?")
    self.subtitle:SetText(d.family or "")
    local seen = {}
    if d.x and d.y then seen[#seen + 1] = ("%.1f, %.1f"):format(d.x, d.y) end
    if d.subzone and d.subzone ~= "" then seen[#seen + 1] = d.subzone end
    lines = {
      Line(L.NPC_ID, d.id),
      Line(L.LEVEL, LevelText(d.level_min, d.level_max)),
      Line(L.ATTACK_SPEED, SpeedText(d.mainhand_speed)),
      Line(L.TYPE, d.creature_type),
      Line(L.LOCATION, ZoneNames(d.zones)),
      Line(L.COORDINATES, table.concat(seen, " - ")),
      Line(L.COLLECTED_AT, d.collected and date("%Y-%m-%d %H:%M", d.collected) or nil),
    }
    description = row.isNew and Colors.Highlight(L.NOT_IN_DATA) or L.IN_DATA
  elseif row.kind == "tame" then
    -- A tamed beast: the creature, and what its pet came with (spells, ranks, attack speed).
    self.icon:SetTexture(FamilyIcon(d.family))
    self.name:SetText(d.name or "?")
    self.subtitle:SetText(L.TAMED .. (d.family and (" - " .. d.family) or ""))
    local seen = {}
    if d.x and d.y then seen[#seen + 1] = ("%.1f, %.1f"):format(d.x, d.y) end
    if d.subzone and d.subzone ~= "" then seen[#seen + 1] = d.subzone end
    lines = {
      Line(L.NPC_ID, d.npc_id),
      Line(L.LEVEL, d.level),
      Line(L.PET_LEVEL, d.pet_level),
      Line(L.ATTACK_SPEED, SpeedText(d.attack_speed)),
      Line(L.LOCATION, d.ui_map_id and ZoneNames({ [d.ui_map_id] = true }) or nil),
      Line(L.COORDINATES, table.concat(seen, " - ")),
      Line(L.COLLECTED_AT, d.tamed and date("%Y-%m-%d %H:%M", d.tamed) or nil),
    }
    local spells = {}
    for _, spell in ipairs(d.spells or {}) do
      local icon = SpellIcon(spell.spell_id)
      spells[#spells + 1] = ("%s%s%s%s"):format(icon and ("|T" .. icon .. ":16:16:0:0|t ") or "", spell.name or "?",
        spell.rank and (" " .. spell.rank) or "", spell.passive and (" |cFF9D9D9D(" .. L.PASSIVE .. ")|r") or "")
    end
    description = #spells > 0 and table.concat(spells, "\n") or Colors.Highlight(L.NO_PET_SPELLS)
  elseif row.kind == "trainer" then
    self.icon:SetTexture(QUESTION_MARK_ICON)
    self.name:SetText(d.name or "?")
    self.subtitle:SetText(d.title or "")
    local where = {}
    if d.x and d.y then where[#where + 1] = ("%.1f, %.1f"):format(d.x, d.y) end
    if d.subzone and d.subzone ~= "" then where[#where + 1] = d.subzone end
    lines = {
      Line(L.NPC_ID, d.id),
      Line(L.LEVEL, d.level),
      Line(L.FACTION, d.faction),
      Line(L.LOCATION, d.ui_map_id and ZoneNames({ [d.ui_map_id] = true }) or nil),
      Line(L.COORDINATES, table.concat(where, " - ")),
      Line(L.SERVICES, d.services and #d.services or 0),
      Line(L.SELLS, d.merchant and #d.merchant or nil),
    }
    -- What the window offered: each entry with its price, the pet abilities first.
    local offered = {}
    for _, service in ipairs(d.services or {}) do
      offered[#offered + 1] = ("%s%s - %s%s"):format(service.name or "?", service.rank and (" " .. service.rank) or "",
        Money(service.cost), service.category and (" (" .. service.category .. ")") or "")
    end
    local shown = {}
    for i = 1, math.min(#offered, 12) do shown[i] = offered[i] end
    if #offered > 12 then shown[#shown + 1] = ("... +%d"):format(#offered - 12) end
    description = table.concat(shown, "\n")
  else
    self.icon:SetTexture(SpellIcon(d.spell_id) or d.icon or QUESTION_MARK_ICON)
    self.name:SetText(d.name or "?")
    self.subtitle:SetText(row.rank or "")
    -- The price is in copper and the level is what the trainer window lists; the status is for this character.
    lines = {
      Line(L.PRICE, d.cost and Money(d.cost) or nil),
      Line(L.LEVEL_REQUIRED, d.required_level),
      Line(L.STATUS, d.category),
      Line(L.SPELL_ID, d.spell_id),
    }
    description = ""
  end

  -- Entries other TrueshotLodge users shared say who sent them.
  if d.shared_by then table.insert(lines, 1, Line(L.SHARED_BY, d.shared_by)) end
  local shown = {}
  for i = 1, 8 do if lines[i] then shown[#shown + 1] = lines[i] end end
  self.facts:SetText(table.concat(shown, "\n"))
  self.description:SetText(description or "")
  self:PlaceDescription()
end

-- ----------------------------------------------------------------------------
-- Clearing the data
-- ----------------------------------------------------------------------------

local CLEAR_POPUP = "TRUESHOTLODGE_CLEAR_COLLECTED"

local function ClearCollected()
  Collector:Clear()
  Collector.version = Collector.version + 1
  Window.selectedCollected = nil
  if Window.tab == "COLLECTOR" then Window:RefreshCollector() end
end

-- Right-click on an entry: asks, then removes just that entry from the saved data.
local DELETE_POPUP = "TRUESHOTLODGE_DELETE_COLLECTED"

local function DeleteCollected(row)
  local store = DB.collected[row.store]
  if not store then return end
  if row.store == "tames" then
    table.remove(store, row.storeKey) -- a list: the later tames move up
  else
    store[row.storeKey] = nil
  end
  Collector.version = Collector.version + 1
  if Window.selectedCollected == row.key then Window.selectedCollected = nil end
  if Window.tab == "COLLECTOR" then Window:RefreshCollector() end
end

function Window:AskToDelete(row)
  if not (row and row.store and row.storeKey ~= nil) then return end
  local label = (row.data.name or "?") .. (row.rank and (" " .. row.rank) or "")
  local what = ({ creature = L.CREATURE, tame = L.TAME, training = L.BEAST_TRAINING, trainer = L.TRAINER })[row.kind] or ""
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs[DELETE_POPUP] = StaticPopupDialogs[DELETE_POPUP] or {
      text = "%s",
      button1 = L.DELETE,
      button2 = CANCEL,
      OnAccept = function(_, data) DeleteCollected(data) end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    StaticPopup_Show(DELETE_POPUP, L.DELETE_COLLECTED_CONFIRM:format(label, what), nil, row)
  else
    DeleteCollected(row)
  end
end

-- Asks first: the collected data only exists in the saved settings.
function Window:AskToClear()
  local creatures, training = Collector:Count(), self:CountOf(DB.collected.beast_training)
  local trainers, tames = self:CountOf(DB.collected.trainers), #(DB.collected.tames or {})
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs[CLEAR_POPUP] = StaticPopupDialogs[CLEAR_POPUP] or {
      text = "%s",
      button1 = L.CLEAR_DATA,
      button2 = CANCEL,
      OnAccept = ClearCollected,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    StaticPopup_Show(CLEAR_POPUP, L.CLEAR_DATA_CONFIRM:format(creatures, tames, training, trainers))
  else
    ClearCollected()
  end
end

-- The button sits at the far right of the tab's heading, and only shows on this tab.
function Window:CreateClearButton(frame)
  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetSize(100, 22)
  button:SetPoint("TOPRIGHT", -16, -34)
  button:SetText(L.CLEAR_DATA)
  button:SetScript("OnClick", function() self:AskToClear() end)
  button:Hide()
  self.clearButton = button
end

function Window:UpdateClearButton()
  if self.clearButton then self.clearButton:SetShown(self.tab == "COLLECTOR") end
end

-- ----------------------------------------------------------------------------
-- Following the collector
-- ----------------------------------------------------------------------------

-- Called when collecting is turned on or off: the tab appears and disappears with it.
function Window:OnCollectChanged()
  if not self.frame then return end
  self:UpdateTabs()
  if self.tab == "COLLECTOR" and not Collecting() then self:SelectTab("UNIQUE") end
end

-- While the tab is open, the window looks at the collector's change counter a few times a second and
-- rebuilds the list when it moved. Polling (instead of reacting to each record) cannot miss a change, and a
-- burst of records costs one rebuild.
local POLL_SECONDS = 0.5

function Window:HookCollectorPolling(frame)
  local elapsed = 0
  frame:HookScript("OnUpdate", function(_, delta)
    if self.tab ~= "COLLECTOR" then return end
    elapsed = elapsed + delta
    if elapsed < POLL_SECONDS then return end
    elapsed = 0
    if self.collectedVersion ~= Collector.version then
      local ok, err = pcall(self.RefreshCollector, self)
      if not ok then
        self.collectedVersion = Collector.version -- Don't retry the same failure every poll.
        Addon:Debug("collector tab error:", err)
      end
    end
  end)
end
