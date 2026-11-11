local _, Addon = ...
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local PinHelper = Addon:GetModule("PinHelper")
local Window = Addon:GetModule("Window")
local CreatePanel, NewText, PlayClick = Helpers.CreatePanel, Helpers.NewText, Helpers.PlayClick
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON

-- The pet profile: everything TrueshotLodge knows about one tameable creature, on a page of its own. A creature's name
-- opens it wherever the window lists one (the creature lists under an ability, a family, a bounty or a look; Collected
-- Data; the Stable's pets, for the beast they were tamed from). Laid out like the Stable tab: on the left Back, the
-- name and level, and its facts, abilities and looks (each ability and look opens on its own tab); on the right its 3D
-- model (model-viewer.lua) and its Map button. Back goes to the tab, selection or profile you came from.

local MAP_WIDTH, MAP_HEIGHT = 104, 22

-- Each creature's looks, from data/Looks.lua: npc id -> { { family, look } }, built the first time it is needed.
local npcLooks
local function LooksOf(id)
  if not npcLooks then
    npcLooks = {}
    for family, looks in pairs(Addon.TameableLooks or {}) do
      for _, look in ipairs(looks) do
        for _, npcId in ipairs(look.npcs or {}) do
          npcLooks[npcId] = npcLooks[npcId] or {}
          table.insert(npcLooks[npcId], { family = family, look = look })
        end
      end
    end
  end
  return npcLooks[id] or {}
end

-- ----------------------------------------------------------------------------
-- Going there and back
-- ----------------------------------------------------------------------------

-- Opens a creature's profile (its npc id). Where you were is kept for Back: the tab and its selection, or the profile
-- you were on.
function Window:ShowPetProfile(id)
  local npc = Addon:GetNPC(id)
  if not (npc and self:IsAvailable()) then return end
  self:Show()
  if self.tab == "PET" and self.profileNpc == npc.id then return end
  self.petHistory = self.petHistory or {}
  if self.tab == "PET" then
    table.insert(self.petHistory, { tab = "PET", npc = self.profileNpc })
  else
    table.insert(self.petHistory, { tab = self.tab, selected = self.selected })
  end
  self.profileNpc = npc.id
  self.tab = "PET" -- (not saved as the last tab: a profile is not where the window opens)
  self:UpdateTabs()
  self:Refresh()
end

-- Back: to the profile or the tab before, as you left it.
function Window:GoBack()
  local entry = table.remove(self.petHistory or {})
  if not entry then return end
  if entry.tab == "PET" then
    self.profileNpc = entry.npc
  else
    self.tab = entry.tab
    self.selected = entry.selected -- (the ability tabs' selection; the other tabs keep their own)
    self:UpdateTabs()
  end
  self:Refresh()
end

-- Leaves the profile for a tab with something selected there (`select` sets it): an ability, a look or a family. The
-- way back is forgotten, as when a side tab is clicked.
function Window:OpenOnTab(tab, select)
  self.petHistory = nil
  self.tab = tab
  DB.global.last_tab = tab
  self.selected = nil
  select()
  self:Remember()
  self:UpdateTabs()
  self:Refresh()
end

local function OpenAbility(ability, rankIndex)
  Window:OpenOnTab(Addon:GetAbilityTab(ability), function()
    Window.selected = { ability = ability, rankIndex = rankIndex }
    Window.expanded[ability] = true
  end)
end

local function OpenLook(family, look)
  Window:OpenOnTab("LOOKS", function()
    Window.selectedLook = family .. ":" .. look.display
    Window.expanded["looks:" .. family] = true
  end)
end

local function OpenFamily(family)
  local info = Addon.TameableFamilies and Addon.TameableFamilies[family]
  Window:OpenOnTab("FAMILIES", function()
    Window.selectedFamily = family
    Window.expanded["families:" .. ((info and info.type) or L.OTHER)] = true
  end)
end

-- ----------------------------------------------------------------------------
-- Building the page
-- ----------------------------------------------------------------------------

function Window:CreatePetProfile(frame)
  local page = CreateFrame("Frame", nil, frame)
  self.profile = page
  page:SetPoint("TOPLEFT", 5, -72)
  page:SetPoint("BOTTOMRIGHT", -5, 5)
  page:Hide()

  -- Left: Back, the name and level, and the facts.
  local left = CreatePanel(page)
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMLEFT")
  left:SetWidth(Helpers.LIST_WIDTH)

  local back = Helpers.NewOutlineButton(left)
  back:SetSize(70, 22)
  back:SetPoint("TOPLEFT", 10, -10)
  back:SetText(L.BACK)
  back:SetScript("OnClick", function()
    PlayClick()
    self:GoBack()
  end)
  self.profileBack = back

  self.profileTitle = NewText(left, "GameFontHighlightLarge", "CENTER")
  self.profileTitle:SetPoint("TOP", 0, -40)
  self.profileTitle:SetPoint("LEFT", 8, 0)
  self.profileTitle:SetPoint("RIGHT", -8, 0)
  self.profileSubtitle = NewText(left, "GameFontNormal", "CENTER")
  self.profileSubtitle:SetPoint("TOP", self.profileTitle, "BOTTOM", 0, -4)
  self.profileSubtitle:SetPoint("LEFT", 8, 0)
  self.profileSubtitle:SetPoint("RIGHT", -8, 0)

  -- The facts: the Stable tab's list of headers and "label ... value" rows (Window:InitStableRow), some of them links.
  local box = CreateFrame("Frame", nil, left, "WowScrollBoxList")
  box:SetPoint("TOPLEFT", 8, -86)
  box:SetPoint("BOTTOMRIGHT", -22, 8)
  local bar = CreateFrame("EventFrame", nil, left, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
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
    return data.categoryInfo and 25 or data.kind == "note" and 40 or 24
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  self.profileBox = box

  -- Right: the model, filling the pane above the Map button.
  local right = CreatePanel(page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 2, 0)
  right:SetPoint("BOTTOMRIGHT")
  local viewer = Helpers.NewModelViewer(right)
  viewer:SetPoint("TOPLEFT", 10, -10)
  viewer:SetPoint("BOTTOMRIGHT", -10, 40)
  self.profileViewer = viewer

  local map = Helpers.NewOutlineButton(right)
  map:SetSize(MAP_WIDTH, MAP_HEIGHT)
  map:SetPoint("BOTTOMLEFT", 10, 10)
  map:SetMotionScriptsWhileDisabled(true) -- the greyed-out button still says why
  map:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (right-click clears the pins)
  map:SetScript("OnClick", function(button, mouseButton) PinHelper:MapClick(button.npc, mouseButton) end)
  map:SetScript("OnEnter", function(button) PinHelper:ShowMapTooltip(button) end)
  map:SetScript("OnLeave", GameTooltip_Hide)
  self.profileMap = map
end

-- ----------------------------------------------------------------------------
-- The rows for a creature
-- ----------------------------------------------------------------------------

local function ProfileRows(npc)
  local rows = {}
  local function header(label) rows[#rows + 1] = { kind = "header", label = label, key = "pet:" .. label } end
  local function stat(label, value, icon, extra)
    if value == nil or value == "" then return end
    local row = { kind = "stat", label = label, value = tostring(value), icon = icon, stripe = #rows % 2 == 0 }
    for k, v in pairs(extra or {}) do row[k] = v end
    rows[#rows + 1] = row
  end

  local family = Addon.TameableFamilies and Addon.TameableFamilies[npc.family]
  header(L.GENERAL)
  stat(L.FAMILY, Addon:FamilyLabel(npc.family), family and family.icon or QUESTION_MARK_ICON,
    { onClick = function() OpenFamily(npc.family) end, hint = L.PROFILE_OPEN_FAMILY })
  stat(L.TYPE, npc.type)
  stat(L.DIET, npc.diet)
  stat(L.LEVEL, npc.level_range)
  stat(L.ATTACK_SPEED, npc.speed_text)
  stat(L.LOCATION, npc.location or L.UNKNOWN_ZONE)
  if npc.forever then stat(L.NEW_IN_FOREVER, " ", Addon.FOREVER_ICON) end
  if type(npc.tamed) == "string" and npc.tamed ~= "" then
    local by = type(npc.tamed_by) == "string" and npc.tamed_by ~= "" and npc.tamed_by or nil
    stat(L.VERIFIED, by and ("%s, %s"):format(npc.tamed, by) or npc.tamed, Addon.GREEN_DOT)
  end
  stat(L.NPC_ID, npc.id)

  -- The ability ranks it teaches, each opening on its own tab.
  header(L.ABILITIES)
  if #(npc.taught or {}) == 0 then
    rows[#rows + 1] = { kind = "note", label = L.PROFILE_NO_ABILITIES }
  end
  for _, entry in ipairs(npc.taught or {}) do
    local ability, rankIndex = entry.ability, entry.rankIndex
    local rank = ability.ranks[rankIndex]
    local label = ability.attack_speed and ability.name or ("%s %s %d"):format(ability.name, L.RANK, rank.rank or rankIndex)
    rows[#rows + 1] = {
      kind = "stat", label = label, value = Addon:IsRankKnown(ability, rankIndex) and L.KNOWN or "",
      stripe = #rows % 2 == 0, icon = ability.icon, spell = rank.spell_id,
      onClick = function() OpenAbility(ability, rankIndex) end, hint = L.PROFILE_OPEN_ABILITY,
    }
  end

  -- Its looks, each opening on the Looks tab.
  local looks = LooksOf(npc.id)
  if #looks > 0 then
    header(L.LOOKS)
    for _, entry in ipairs(looks) do
      local count = #entry.look.npcs
      rows[#rows + 1] = {
        kind = "stat", label = Addon:LookName(entry.look, entry.family), value = ("(%d)"):format(count),
        stripe = #rows % 2 == 0, onClick = function() OpenLook(entry.family, entry.look) end,
        hint = count == 1 and L.LOOK_UNIQUE_TOOLTIP or L.PROFILE_OPEN_LOOK,
      }
    end
  end
  return rows
end

-- Fills the page for the creature shown (self.profileNpc). The list is the Stable tab's tree: each header open the
-- first time it appears.
function Window:RefreshPetProfile()
  local npc = self.profileNpc and Addon:GetNPC(self.profileNpc)
  if not npc then
    -- Nothing to show (the creature left the data): back where you came from, else the first tab.
    if self.petHistory and #self.petHistory > 0 then return self:GoBack() end
    return self:SelectTab(self:KnownTab(nil))
  end
  self.headerCount:SetText("")
  self.profileBack:SetShown(self.petHistory ~= nil and #self.petHistory > 0)
  self.profileTitle:SetText(npc.name)
  self.profileSubtitle:SetText(("%s %s %s"):format(L.LEVEL, npc.level_range or L.UNKNOWN, Addon:FamilyLabel(npc.family)))
  self.profileBox:SetDataProvider(self:BuildStableTree(ProfileRows(npc)), true)

  -- The model: its first look's display, else the game's own creature (which it may not have loaded).
  local looks = LooksOf(npc.id)
  self.profileViewer:ShowModel(looks[1] and looks[1].look.display, npc.id)

  -- The Map button, as in the creature lists (Window:InitNPCRow).
  local map = self.profileMap
  map.npc = npc
  if npc.ui_map_id and npc.coords and #npc.coords > 0 then
    map:SetText(L.MAP)
    map:SetEnabled(true)
    map.hint = nil
  elseif npc.ui_map_id then
    map:SetText(L.NO_COORDINATES)
    map:SetEnabled(true)
    map.hint = L.NO_COORDINATES_TOOLTIP
  elseif not npc.location then
    map:SetText(L.UNKNOWN_ZONE)
    map:SetEnabled(false)
    map.hint = L.UNKNOWN_ZONE_TOOLTIP
  else
    map:SetText(L.MAP_UNAVAILABLE)
    map:SetEnabled(false)
    map.hint = nil
  end
  map:SetWidth(math.max(44, math.ceil((map:GetTextWidth() or 60) + 24)))
end
