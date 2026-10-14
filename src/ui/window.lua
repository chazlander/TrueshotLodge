local ADDON_NAME, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local PinHelper = Addon:GetModule("PinHelper")
local UI = Addon:GetModule("UI")
local Window = Addon:GetModule("Window")
local Helpers = Addon:GetModule("Helpers")
local NewText, TemplateExists = Helpers.NewText, Helpers.TemplateExists
local SetSpellTooltip = Helpers.SetSpellTooltip

-- The tabs live in files of their own: window-tabs.lua (the column of tabs), tab-abilities.lua (Unique, Common,
-- Passive, Passive Attack Speed), tab-trainers.lua, tab-stable.lua, tab-options.lua, tab-collector.lua; the helpers
-- they share are in helpers.lua. This file is the window itself: the frame, the list and the details they fill.
--
-- The addon's window, styled after the profession window (Blacksmithing, ...): abilities as collapsible
-- headers with their ranks under them on the left, the selected rank on the right, and side tabs for
-- Unique, Common, Passive and Options. It reuses Blizzard's frame templates and art; Blizzard's
-- profession templates are loaded on demand. When anything it needs is missing, the window is not shown
-- and a message says why.

local TEMPLATES_ADDON = "Blizzard_ProfessionsTemplates"
local REQUIRED_TEMPLATES = {
  "PortraitFrameTemplate",
  "NineSlicePanelTemplate",
  "SearchBoxTemplate",
  "WowScrollBoxList",
  "MinimalScrollBar",
  "LargeSideTabButtonTemplate",
  "UIPanelButtonTemplate",
  "CheckboxWithLabelTemplate",
  "ProfessionsRecipeListCategoryTemplate",
  "ProfessionsRecipeListRecipeTemplate",
}

-- The frame is as wide as the profession background art (665 pixels) plus the 3 pixel frame edge on each side.
local WIDTH, HEIGHT = 671, 594
-- UI Scale on the Options tab: the window's own scale, in steps of 5%.
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 1.5, 0.05
local LIST_WIDTH = Helpers.LIST_WIDTH
local HEADER_X = 84 -- where the tab's title and count start: clear of the logo, with some room
local DETAILS_TOP = 12 -- the room above the details pane's top row (the icon, name and facts)
local DETAILS_LEFT = 12 -- the room left of the details pane's content
local FACTS_X = 246 -- where the details start in the right-hand pane (right of the icon, name and rank)
Window.DETAILS_TOP, Window.DETAILS_LEFT = DETAILS_TOP, DETAILS_LEFT -- (the Families tab lays out its own top row)
local MINI_MAP_WIDTH = Helpers.MINI_MAP_WIDTH
-- The details icon: Blizzard's CircularGiantItemButtonTemplate (true), or a ring drawn here (false). Since October 2026
-- the client draws that template's ring wrong: a dark square over part of the icon, in Blizzard's own profession window
-- too. Set it back to true once a client update fixes it.
local BLIZZARD_ICON_RING = false

-- The Bounties tab's icon: the website's Bounties tab icon (a contract), or a scroll when this client lacks it.
Window.BOUNTY_ICON = (GetFileIDFromPath and GetFileIDFromPath("Interface\\Icons\\INV_Inscription_80_Contract_Embers"))
  or "Interface\\Icons\\INV_Scroll_03"

local TABS = {
  -- First, as on the website (which opens on it).
  { key = "FAMILIES", label = L.FAMILIES, title = L.PET_FAMILIES, icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf" },
  { key = "UNIQUE", label = L.UNIQUE, title = L.UNIQUE_ABILITIES, icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
  { key = "COMMON", label = L.COMMON, title = L.COMMON_ABILITIES, icon = "Interface\\Icons\\Ability_Racial_Cannibalize" },
  { key = "PASSIVE", label = L.PASSIVE, title = L.PASSIVE_ABILITIES, icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina" },
  { key = "ATTACK", label = L.ATTACK_SPEEDS, title = L.ATTACK_SPEEDS, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
  { key = "TRAINERS", label = L.TRAINERS, title = L.TRAINERS, icon = "Interface\\Icons\\Ability_Hunter_BeastTraining" },
  { key = "BOUNTIES", label = L.BOUNTIES, title = L.BOUNTIES, icon = Window.BOUNTY_ICON },
  { key = "STABLE", label = L.STABLE, title = L.STABLE, icon = "Interface\\Icons\\Ability_Hunter_BeastCall" },
  { key = "OPTIONS", label = L.OPTIONS, title = L.OPTIONS, icon = "Interface\\Icons\\INV_Misc_Gear_01" },
  -- Last, so the tabs above never move: it is only shown while collecting is on.
  { key = "COLLECTOR", label = L.COLLECTED_DATA, title = L.COLLECTED_DATA, icon = "Interface\\Icons\\INV_Misc_Note_02" },
}
Window.TABS = TABS -- the side tabs (window-tabs.lua) are made from it

-- ============================================================================
-- Availability
-- ============================================================================

-- Loads Blizzard's profession templates (once) and checks everything the window needs exists.
function Window:IsAvailable()
  if self.available ~= nil then return self.available end

  local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if loadAddOn then
    local ok, loaded, reason = pcall(loadAddOn, TEMPLATES_ADDON)
    if not (ok and loaded) then Addon:Debug("window: could not load", TEMPLATES_ADDON, reason or loaded) end
  end

  local available = CreateScrollBoxListTreeListView and CreateScrollBoxListLinearView and CreateTreeDataProvider
    and CreateDataProvider and ScrollUtil and true or false
  for _, name in ipairs(REQUIRED_TEMPLATES) do
    if not TemplateExists(name) then
      Addon:Debug("window: missing template", name)
      available = false
    end
  end

  if available then
    local ok, err = pcall(self.Create, self)
    if not ok then
      Addon:Debug("window: could not be created:", err)
      if self.frame then self.frame:Hide() end
      available = false
    end
  end

  self.available = available
  return available
end

function Window:IsShown()
  return self.frame ~= nil and self.frame:IsShown()
end

function Window:Show()
  if not self:IsAvailable() then
    print(("|cFF007EA6%s|r: %s"):format(Addon.TITLE, L.WINDOW_UNAVAILABLE))
    return
  end
  self.frame:Show()
end

function Window:Hide()
  if self.frame then self.frame:Hide() end
end

-- The UI module (minimap icon, slash command) opens and closes this window.
function UI:IsShown() return Window:IsShown() end
function UI:Show() Window:Show() end
function UI:Hide() Window:Hide() end
function UI:Toggle()
  if Window:IsShown() then Window:Hide() else Window:Show() end
end

-- ============================================================================
-- Helpers
-- ============================================================================

-- ============================================================================
-- Frame
-- ============================================================================

-- The portrait like the website's: the logo (the TrueshotLodge target) without the bronze ring, a little larger than
-- the round portrait was and centred where it was, over the frame's corner. false brings back the ringed portrait.
local BADGE_PORTRAIT = true
local BADGE_SCALE = 1.2 -- the target against the round portrait's size
local BADGE_PAD = 1.15 -- media/logo.tga's room around the target for its shadow (.tools/build/make_logo_icons.py)

function Window:CreatePortrait(frame)
  frame:SetPortraitToAsset(Addon.ICON)
  if not BADGE_PORTRAIT then return end
  local container = frame.PortraitContainer
  local portrait = (container and container.portrait) or frame.portrait
  if not portrait then return end

  local size = portrait:GetWidth()
  if not size or size <= 0 then size = 60 end
  local badge = CreateFrame("Frame", nil, frame)
  badge:SetSize(size * BADGE_SCALE * BADGE_PAD, size * BADGE_SCALE * BADGE_PAD)
  badge:SetPoint("CENTER", portrait, "CENTER")
  -- Above the border art and anything the template layers over the corner.
  local level = frame:GetFrameLevel()
  if frame.NineSlice then level = math.max(level, frame.NineSlice:GetFrameLevel()) end
  if container then level = math.max(level, container:GetFrameLevel()) end
  badge:SetFrameLevel(level + 10)
  local texture = badge:CreateTexture(nil, "OVERLAY")
  texture:SetAllPoints()
  texture:SetTexture(Addon.LOGO)
  self.badge = badge

  -- No ring: hide the round portrait and give the border the plain corner of a frame without a portrait.
  local ring = container or portrait
  ring:Hide()
  if frame.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    local ok, err = pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, "ButtonFrameTemplateNoPortrait")
    if not ok then Addon:Debug("window: no portrait-less border:", err) end
  end
end

function Window:Create()
  local frameName = ADDON_NAME .. "Frame"
  local frame = CreateFrame("Frame", frameName, UIParent, "PortraitFrameTemplate")
  self.frame = frame
  frame:Hide()
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetTitle(("%s %s"):format(Addon.TITLE, Colors.Primary(Addon.VERSION or "")))
  self:CreatePortrait(frame)
  self:CreateFilterButtons(frame) -- Level, Zone, Pet (and Faction) at the right of the header
  self:CreateZoneFilter(frame) -- the Zone Filter follows you into a new zone (zone-filter.lua)
  frame:SetScale(self:SavedScale())
  frame:HookScript("OnShow", function() self:Refresh() end)
  frame:HookScript("OnHide", function() self:OnHide() end)
  self:HookCollectorPolling(frame)
  self:CreateClearButton(frame)
  -- Filter by Pet follows the pet: relist when it is summoned, dismissed or replaced.
  -- The level filter and highlight follow the character's level.
  frame:RegisterEvent("UNIT_PET")
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:HookScript("OnEvent", function(_, event, unit)
    if not frame:IsShown() then return end
    if unit == "player" then self:UpdateFilterButtons() end -- the Pet button needs a pet
    if event == "PLAYER_LEVEL_UP" or (unit == "player" and DB.global.filter_by_pet) then self:Refresh() end
  end)
  tinsert(UISpecialFrames, frameName) -- Escape closes it.
  -- The close button hides its frame through HideUIPanel, which does nothing in combat. This window is
  -- not protected, so hide it directly; returning false tells the button not to call HideUIPanel.
  frame.onCloseCallback = function()
    frame:Hide()
    return false
  end

  -- The selected tab's title, and a count under it (like the profession window's skill bar): on the left, clear of
  -- the logo, with the filter buttons at the other end of the same band.
  self.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  self.header:SetPoint("TOPLEFT", HEADER_X, -32)
  self.header:SetJustifyH("LEFT")
  local font, size, flags = self.header:GetFont()
  if font and size then self.header:SetFont(font, size - 2, flags) end -- a size under the template's
  self.headerCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.headerCount:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)
  self.headerCount:SetJustifyH("LEFT")
  font, size, flags = self.headerCount:GetFont()
  if font and size then self.headerCount:SetFont(font, size - 1, flags) end

  local background = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
  if background:SetAtlas("Profession-Background-Template2", true) == false then background:Hide() end
  background:SetPoint("TOPLEFT", 3, -21)

  self:CreateSideTabs(frame)
  self:CreateList(frame)
  self:CreateDetails(frame)
  self:CreateStable(frame)

  self.tab = self:Sticky() and self:KnownTab(DB.global.last_tab) or "UNIQUE"
  self.expanded = {} -- ability -> true for headers the player opened
  self:UpdateTabs()
end

-- ----------------------------------------------------------------------------
-- Sticky selections: the ability (rank) or trainer selected on each tab, and the tab itself, are
-- remembered across tab switches and, in the saved settings, across closing and reopening.
-- ----------------------------------------------------------------------------

function Window:Sticky()
  return DB.global.sticky_selections ~= false
end

function Window:KnownTab(key)
  if key == "COLLECTOR" and not DB.global.collect then return "UNIQUE" end
  for _, info in ipairs(TABS) do
    if info.key == key then return key end
  end
  return "UNIQUE"
end

-- Saves what is selected on the current tab.
function Window:Remember()
  if not self:Sticky() then return end
  local selections = DB.global.selections
  if self.tab == "TRAINERS" then
    selections.TRAINERS = self.selectedTrainer and self.selectedTrainer.id or nil
  elseif self.tab == "BOUNTIES" then
    selections.BOUNTIES = self.selectedBounty
  elseif self.tab == "FAMILIES" then
    selections.FAMILIES = self.selectedFamily
  elseif self.tab == "OPTIONS" then
    selections.OPTIONS = self.selectedOption
  elseif self.selected then
    selections[self.tab] = {
      ability = self.selected.ability.key, -- the slug (set in data.lua)
      rank = self.selected.rankIndex,
    }
  end
end

function Window:SelectTab(key)
  if key == self.tab then return end
  self.tab = key
  DB.global.last_tab = key
  self.selected = nil
  if not self:Sticky() then self.selectedTrainer = nil end
  self:UpdateTabs()
  self:Refresh()
end

-- The name and the line under it, right of the icon: up to the facts column, or with `wide` (no facts: a pet bounty,
-- Collected Data) across the whole pane. `white`: the line under it in white (a pet bounty's text) instead of gold.
function Window:SetTopWide(wide, white)
  for _, text in ipairs({ self.name, self.subtitle }) do
    text:ClearAllPoints()
    if text == self.name then
      text:SetPoint("TOPLEFT", self.iconButton, "TOPRIGHT", 12, -6)
    else
      text:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -6)
    end
    if wide then
      text:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)
    else
      text:SetPoint("RIGHT", self.facts, "LEFT", -12, 0)
    end
  end
  self.subtitle:SetFontObject(white and "GameFontHighlight" or "GameFontNormal") -- white text, or the gold rank line
end

-- Without sticky selections the window starts over each time it is opened.
function Window:OnHide()
  if self:Sticky() then return end
  self.selected, self.selectedTrainer = nil, nil
  self.tab = "UNIQUE"
  self:UpdateTabs()
end

function Window:UpdateTabs()
  for _, tab in ipairs(self.tabs) do
    tab:SetChecked(tab.key == self.tab)
    if tab.key == "COLLECTOR" then tab:SetShown(DB.global.collect == true) end
  end
  -- The Families tab's own parts of the details (tab-families.lua): only there, with the creatures under its ability
  -- rows; on the other tabs the creatures go under the description.
  local families = self.tab == "FAMILIES"
  if self.iconButton then self:SetTopWide(false) end -- (a pet bounty widens it again)
  if self.familyWidgets then self.familyWidgets:SetShown(families) end
  if self.npcLabel then
    self.npcLabel:ClearAllPoints()
    if families then
      self.npcLabel:SetPoint("TOPLEFT", self:FamilyWidgets().abilities, "BOTTOMLEFT", 0, -14)
    else
      self.npcLabel:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -14)
    end
    self.npcLabel:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)
  end
  self:UpdateFilterButtons() -- the tab's own filters
  if not self.dragTab then self:LayoutTabs() end -- (a tab being dragged is placed by the cursor)
  for _, info in ipairs(TABS) do
    if info.key == self.tab then self.header:SetText(info.title) end
  end
  self:UpdateClearButton()
  -- Stable fills the window beside the side tabs; the other tabs use the list and the details.
  local stable = self.tab == "STABLE"
  self.stable:SetShown(stable)
  self.list:SetShown(not stable)
  if stable then
    self.details:Hide()
    self.headerCount:SetText("")
  end
  -- The Options tab's controls sit in the details: only on that tab.
  if self.optionControls and self.tab ~= "OPTIONS" then self.optionControls:Hide() end
end

-- ============================================================================
-- Ability list (left)
-- ============================================================================

function Window:CreateList(frame)
  local list = CreateFrame("Frame", nil, frame)
  self.list = list
  list:SetPoint("TOPLEFT", 5, -72)
  list:SetPoint("BOTTOMLEFT", 5, 5)
  list:SetWidth(LIST_WIDTH)

  local background = list:CreateTexture(nil, "BACKGROUND")
  if background:SetAtlas("Professions-background-summarylist") == false then
    background:SetColorTexture(0, 0, 0, 0.4)
  end
  background:SetAllPoints()

  local border = CreateFrame("Frame", nil, list, "NineSlicePanelTemplate")
  border:SetAllPoints()
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
  end

  local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:SetHeight(20)
  search:SetPoint("TOPLEFT", 13, -8)
  search:HookScript("OnTextChanged", function(box)
    self.search = (box:GetText() or ""):lower()
    self:Refresh()
  end)
  self.search = ""

  -- Collapses every header, or opens them all when none is open.
  local toggle = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  toggle:SetSize(22, 22)
  toggle:SetPoint("TOPRIGHT", -8, -10)
  toggle:SetScript("OnClick", function() self:ToggleAll() end)
  toggle:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(self:AnyExpanded() and L.COLLAPSE_ALL or L.EXPAND_ALL)
    GameTooltip:Show()
  end)
  toggle:SetScript("OnLeave", GameTooltip_Hide)
  self.toggleButton = toggle

  -- (The filters are buttons in the header: Window:CreateFilterButtons.)
  search:ClearAllPoints()
  search:SetPoint("TOPLEFT", 13, -11)
  search:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
  self.searchBox = search -- (the Collected Data tab moves the row under its Clear All Data button)

  local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 8, -38)
  scrollBox:SetPoint("BOTTOMRIGHT", -20, 5)
  local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 0, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 0, 0)
  self.scrollBox = scrollBox

  local noResults = NewText(list, "GameFontNormal", "CENTER")
  noResults:SetPoint("TOP", 0, -60)
  noResults:SetText(L.NONE)
  noResults:Hide()
  self.noResults = noResults

  -- Same spacing as the profession recipe list.
  local view = CreateScrollBoxListTreeListView(10, 5, 5, 0, 5, 1)

  view:SetElementFactory(function(factory, node)
    local data = node:GetData()
    if data.categoryInfo then
      factory("ProfessionsRecipeListCategoryTemplate", function(button)
        button:Init(node)
        button.tooltipText = data.family -- shown by ListHeaderMixin.OnEnter
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
          -- Right-click: the Bounties tab's headings switch how their rows are sorted; other headings ignore it.
          if mouseButton == "RightButton" then
            if data.sortable then self:ToggleBountySort(data.key) end
            return
          end
          node:ToggleCollapsed()
          self.expanded[data.key] = not node:IsCollapsed() or nil
          button:UpdateCollapsedState(node:IsCollapsed())
          self:UpdateToggleButton()
        end)
        button:SetScript("OnEnter", function(this)
          ListHeaderMixin.OnEnter(this)
          if data.hint then -- how right-clicking sorts it
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(data.title or data.categoryInfo.name)
            GameTooltip:AddLine(data.hint, 0.6, 0.6, 0.6)
            GameTooltip:Show()
          end
        end)
        button:SetScript("OnLeave", function(this)
          ListHeaderMixin.OnLeave(this)
          if data.hint then GameTooltip:Hide() end
        end)
      end)
    elseif data.rankInfo then
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitRankButton(button, data.rankInfo) end)
    elseif data.setting then
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitOptionButton(button, data.setting) end)
    elseif data.trainer then
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitTrainerButton(button, data.trainer) end)
    elseif data.collected then
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitCollectedButton(button, data.collected) end)
    elseif data.bounty then
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitBountyButton(button, data.bounty) end)
    elseif type(data.family) == "table" then -- (a header's `family` is a name: the unique abilities' tooltip)
      factory("ProfessionsRecipeListRecipeTemplate", function(button) self:InitFamilyButton(button, data.family) end)
    else
      factory("Frame")
    end
  end)

  view:SetElementExtentCalculator(function(_, node)
    return node:GetData().categoryInfo and 25 or 20
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
end

-- The filter buttons at the right of the header: Level, Zone, Pet (and Faction on the Trainers tab), in the Filters
-- box. Each shows on the tabs it applies to; grey while off, red and glowing while on. The setting is
-- DB.global[key]; the Zone Filter's own rules are in zone-filter.lua.
local FILTER_BUTTONS = {
  { key = "filter_by_level", label = L.FILTER_LEVEL, title = L.FILTER_BY_LEVEL, slot = 1,
    tabs = { UNIQUE = true, COMMON = true, PASSIVE = true, ATTACK = true, BOUNTIES = true, FAMILIES = true } },
  { key = "zone_filter", label = L.FILTER_ZONE, title = L.ZONE_FILTER_TITLE, slot = 2,
    tabs = { UNIQUE = true, COMMON = true, ATTACK = true, TRAINERS = true, BOUNTIES = true, FAMILIES = true } },
  { key = "filter_by_pet", label = L.FILTER_PET, title = L.FILTER_BY_PET, slot = 3, tabs = { UNIQUE = true, COMMON = true } },
  -- (the Pet place: the two never show on the same tab)
  { key = "filter_by_faction", label = L.FILTER_FACTION, title = L.FILTER_BY_FACTION, slot = 3, tabs = { TRAINERS = true } },
}
local FILTER_WIDTH, FILTER_HEIGHT, FILTER_GAP = 58, 22, 6
-- The Filters box: fixed at the top right, as wide as three buttons whichever show, from under the title bar down to
-- the top of the panes (the list's top, 72), with the window's own edge on its right.
local FILTER_SLOTS, FILTER_LEFT, FILTER_RIGHT = 3, 10, 8 -- the places; the room before the first and after the last
local FILTER_BOX_TOP, FILTER_BOX_BOTTOM, FILTER_BUTTONS_TOP = 26, 72, 17 -- (the buttons' top: under the label)

-- Whether a filter button can be used now: Pet needs a current pet (summoned or dismissed).
function Window:FilterUsable(filter)
  return filter.key ~= "filter_by_pet" or self:CurrentPetFamily() ~= nil
end

-- The glow of a filter that is on: a soft gold light around the button, pulsing (the addon's own: the game's proc glow
-- does not show on these buttons). Made the first time it is needed.
local function ShowGlow(button, on)
  local glow = button.ftGlow
  if not glow then
    if not on then return end
    glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.75, 0.3)
    -- The art's button square is 36 of its 64 pixels: it overhangs by 14/36 of the button on each side, so its bright
    -- edge falls on the button's own (a wide button needs a wider overhang than a tall one).
    local width, height = button:GetSize()
    local overX, overY = width * 14 / 36, height * 14 / 36
    glow:SetPoint("TOPLEFT", -overX, overY)
    glow:SetPoint("BOTTOMRIGHT", overX, -overY)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.8)
    fade:SetSmoothing("IN_OUT")
    glow.pulse = pulse
    button.ftGlow = glow
  end
  glow:SetShown(on)
  if on then glow.pulse:Play() else glow.pulse:Stop() end
end

function Window:CreateFilterButtons(frame)
  self.filterButtons = {}
  for _, filter in ipairs(FILTER_BUTTONS) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(FILTER_WIDTH, FILTER_HEIGHT)
    button:SetText(filter.label)
    button:SetFrameLevel(frame:GetFrameLevel() + 20) -- over the window's background art
    button:SetMotionScriptsWhileDisabled(true) -- a Pet button without a pet still says why
    button.filter = filter
    button:SetScript("OnClick", function()
      DB.global[filter.key] = not DB.global[filter.key]
      if PlaySound and SOUNDKIT then
        PlaySound(DB.global[filter.key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
      end
      self:UpdateFilterButtons()
      self:Refresh()
    end)
    button:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:SetText(filter.title, 1, 1, 1)
      if filter.key == "zone_filter" then
        local zone = self:PlayerZone()
        if zone then GameTooltip:AddLine(zone.name, 1, 0.82, 0) end
        GameTooltip:AddLine(L.ZONE_FILTER_TOOLTIP, nil, nil, nil, true)
      elseif filter.key == "filter_by_pet" then
        local family = self:CurrentPetFamily()
        GameTooltip:AddLine(family or L.NO_ACTIVE_PET, 1, 0.82, 0)
      end
      GameTooltip:AddLine(DB.global[filter.key] and L.ON or L.OFF, 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    self.filterButtons[#self.filterButtons + 1] = button
  end

  -- The box: "Filters" over the buttons, and a line on its left down to the panes.
  local group = CreateFrame("Frame", nil, frame)
  group:SetFrameLevel(frame:GetFrameLevel() + 19)
  group:SetSize(FILTER_LEFT + FILTER_SLOTS * FILTER_WIDTH + (FILTER_SLOTS - 1) * FILTER_GAP + FILTER_RIGHT,
    FILTER_BOX_BOTTOM - FILTER_BOX_TOP)
  group:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -FILTER_BOX_TOP)
  local label = group:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOP", 0, -3)
  label:SetText(L.FILTERS)
  local line = group:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.78, 0.69, 0.55, 0.45) -- the window's tan, faint
  line:SetWidth(1)
  line:SetPoint("TOPLEFT", 0, 0)
  line:SetPoint("BOTTOMLEFT", 0, 0)
  self.filterGroup = group
  -- Each button in its own place in the box: one that does not apply to the tab is hidden, the others stay put.
  for _, button in ipairs(self.filterButtons) do
    button:SetPoint("TOPLEFT", group, "TOPLEFT", FILTER_LEFT + (button.filter.slot - 1) * (FILTER_WIDTH + FILTER_GAP),
      -FILTER_BUTTONS_TOP)
  end
end

-- Shows the filter buttons that apply to the current tab (each in its place), grey while off, red and glowing while on.
function Window:UpdateFilterButtons()
  if not self.filterButtons then return end
  for _, button in ipairs(self.filterButtons) do
    local filter = button.filter
    local shown = filter.tabs[self.tab] == true
    button:SetShown(shown)
    if shown then
      local usable = self:FilterUsable(filter)
      local on = DB.global[filter.key] == true and usable
      button:SetEnabled(usable)
      -- Grey while off: the red art without its color, and the label greyed.
      for _, part in ipairs({ button.Left, button.Middle, button.Right }) do
        if part and part.SetDesaturated then part:SetDesaturated(not on) end
      end
      local text = button:GetFontString()
      if text then
        if on then text:SetTextColor(1, 0.82, 0) else text:SetTextColor(0.6, 0.6, 0.6) end
      end
      ShowGlow(button, on)
    else
      ShowGlow(button, false)
    end
  end
end

-- Whether a header of the current list is open, and opening or closing them all.
function Window:AnyExpanded()
  for _, key in ipairs(self.listKeys or {}) do
    if self.expanded[key] then return true end
  end
  return false
end

function Window:ToggleAll()
  local open = not self:AnyExpanded()
  for _, key in ipairs(self.listKeys or {}) do
    self.expanded[key] = open or nil
  end
  self:Refresh()
end

function Window:UpdateToggleButton()
  if not self.toggleButton then return end
  local open = self:AnyExpanded()
  self.toggleButton:SetText(open and "-" or "+")
  self.toggleButton:SetShown(true)
end

-- Headers start collapsed; the ones opened stay open across refreshes (search, reopening the window).
function Window:SetCollapsed(category, key)
  local collapse = not self.expanded[key]
  if category.SetCollapsed then
    category:SetCollapsed(collapse)
  elseif collapse and not category:IsCollapsed() then
    category:ToggleCollapsed() -- a new node starts expanded
  end
end

function Window:Refresh()
  if not self.frame then return end
  if self.tab == "OPTIONS" then
    self:RefreshOptions()
    return
  end
  if self.tab == "STABLE" then
    self:UpdateTabs()
    self:RefreshStable()
    return
  end
  if self.tab == "TRAINERS" then
    self:RefreshTrainers()
    return
  end
  if self.tab == "COLLECTOR" then
    self:RefreshCollector()
    return
  end
  if self.tab == "BOUNTIES" then
    self:RefreshBounties()
    return
  end
  if self.tab == "FAMILIES" then
    self:RefreshFamilies()
    return
  end
  self:RefreshAbilities() -- the ability tabs (tab-abilities.lua)
end

-- ============================================================================
-- Details (right)
-- ============================================================================

function Window:CreateDetails(frame)
  local details = CreateFrame("Frame", nil, frame)
  self.details = details
  details:SetPoint("TOPLEFT", self.list, "TOPRIGHT", 2, 0)
  details:SetPoint("BOTTOMRIGHT", -5, 5)

  local background = details:CreateTexture(nil, "BACKGROUND")
  background:SetColorTexture(0, 0, 0, 0.35)
  background:SetAllPoints()
  local border = CreateFrame("Frame", nil, details, "NineSlicePanelTemplate")
  border:SetAllPoints()
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
  end

  -- Round icon in a bronze ring, like the profession recipe's output icon. See BLIZZARD_ICON_RING: while the client draws
  -- that template's ring wrong, the ring is drawn here: three circles, each masked round (the bronze ring, a dark gap,
  -- the icon).
  local iconButton, icon
  if BLIZZARD_ICON_RING and TemplateExists("CircularGiantItemButtonTemplate") then
    iconButton = CreateFrame("Button", nil, details, "CircularGiantItemButtonTemplate")
    icon = iconButton.Icon
    iconButton.IconBorder:SetVertexColor(0.85, 0.68, 0.42) -- bronze, like the profession window
    iconButton.IconBorder:Show()
  else
    iconButton = CreateFrame("Button", nil, details)
    iconButton:SetSize(58, 58)
    local function circle(layer, size)
      local texture = iconButton:CreateTexture(nil, layer)
      texture:SetSize(size, size)
      texture:SetPoint("CENTER")
      local mask = iconButton:CreateMaskTexture()
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(texture)
      texture:AddMaskTexture(mask)
      return texture
    end
    circle("BACKGROUND", 58):SetColorTexture(0.85, 0.68, 0.42) -- the ring: bronze, like the profession window
    circle("BORDER", 54):SetColorTexture(0.06, 0.05, 0.03)
    icon = circle("ARTWORK", 53) -- up to the ring, with a hairline of the dark circle between
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) -- past the icon art's own dark edge, so the picture fills the circle
  end
  iconButton:SetPoint("TOPLEFT", DETAILS_LEFT, -DETAILS_TOP)
  iconButton:SetScript("OnClick", nil)
  iconButton:SetScript("OnEnter", function(this)
    local sel = self.selected
    if sel then SetSpellTooltip(this, sel.ability.ranks[sel.rankIndex].spell_id) end
  end)
  iconButton:SetScript("OnLeave", GameTooltip_Hide)
  self.icon = icon

  -- Top row: icon, then name and rank, then the details (pet level, training cost, families). The
  -- description goes under the row, and the tameable creatures get the rest of the pane.
  self.facts = NewText(details, "GameFontHighlightSmall")
  self.facts:SetPoint("TOPLEFT", details, "TOPLEFT", FACTS_X, -(DETAILS_TOP + 4))
  self.facts:SetPoint("RIGHT", -20, 0)
  self.facts:SetSpacing(3)

  self.name = NewText(details, "GameFontHighlightLarge")

  self.subtitle = NewText(details, "GameFontNormal")
  self.iconButton = iconButton
  self:SetTopWide(false)

  self.description = NewText(details, "GameFontHighlight")
  -- Placed in UpdateDetails, under whichever part of the top row is taller.
  self.description:SetPoint("RIGHT", -20, 0)

  self.npcLabel = NewText(details, "GameFontNormal")
  self.npcLabel:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -14)
  self.npcLabel:SetPoint("RIGHT", -20, 0) -- long text (the passive abilities' note) wraps

  local npcBox = CreateFrame("Frame", nil, details, "WowScrollBoxList")
  npcBox:SetPoint("TOPLEFT", self.npcLabel, "BOTTOMLEFT", 0, -6)
  npcBox:SetPoint("BOTTOMRIGHT", -24, 10)
  local npcBar = CreateFrame("EventFrame", nil, details, "MinimalScrollBar")
  npcBar:SetPoint("TOPLEFT", npcBox, "TOPRIGHT", 4, 0)
  npcBar:SetPoint("BOTTOMLEFT", npcBox, "BOTTOMRIGHT", 4, 0)
  local npcView = CreateScrollBoxListLinearView(2, 2, 0, 0, 2)
  npcView:SetElementExtent(34)
  npcView:SetElementInitializer("Frame", function(row, npc) self:InitNPCRow(row, npc) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(npcBox, npcBar, npcView)
  self.npcBox, self.npcBar = npcBox, npcBar

  -- Trainers tab: one "Map Location" button where the creature list would be.
  local mapButton = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
  mapButton:SetSize(140, 22)
  mapButton:SetPoint("TOPLEFT", self.npcLabel, "TOPLEFT", 0, 0)
  mapButton:Hide()
  self.mapButton = mapButton

  -- Trainers tab: a small copy of the zone map with a pin on the trainer. Built from the game's own map
  -- art (the tiles the world map uses); clicking it opens the world map.
  local miniMap = CreateFrame("Frame", nil, details)
  miniMap:SetSize(MINI_MAP_WIDTH, MINI_MAP_WIDTH * 2 / 3)
  miniMap:SetClipsChildren(true)
  miniMap:EnableMouse(true)
  miniMap.tiles = {}
  local edge = miniMap:CreateTexture(nil, "BACKGROUND")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0, 0, 0, 0.8)
  miniMap.pin = miniMap:CreateTexture(nil, "OVERLAY")
  miniMap.pin:SetTexture(Addon.PIN_ICON)
  miniMap.pin:SetSize(18, 18)
  miniMap:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:SetText(L.MAP_LOCATION)
    GameTooltip:Show()
  end)
  miniMap:SetScript("OnLeave", GameTooltip_Hide)
  miniMap:Hide()
  self.miniMap = miniMap
end

function Window:InitNPCRow(row, npc)
  -- Rows are recycled by the scroll box: build their parts once.
  if not row.ftBuilt then
    row.ftBuilt = true
    row.NameText = NewText(row, "GameFontHighlight")
    row.NameText:SetPoint("TOPLEFT", 4, -3)
    row.NameText:SetPoint("RIGHT", -112, 0)
    row.NameText:SetWordWrap(false)
    row.InfoText = NewText(row, "GameFontDisableSmall")
    row.InfoText:SetPoint("TOPLEFT", 4, -18)
    row.InfoText:SetPoint("RIGHT", -112, 0)
    row.InfoText:SetWordWrap(false)
    row.MapButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.MapButton:SetSize(104, 22)
    row.MapButton:SetPoint("RIGHT", -2, 0)
    row.MapButton:SetScript("OnClick", function(button) PinHelper:ShowOnMap(button.npc) end)
    row.MapButton:SetMotionScriptsWhileDisabled(true) -- the greyed-out button still says why
    row.MapButton:SetScript("OnEnter", function(button)
      if not button.hint then return end
      GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
      GameTooltip:SetText(button:GetText(), 1, 1, 1)
      GameTooltip:AddLine(button.hint, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    row.MapButton:SetScript("OnLeave", GameTooltip_Hide)
    -- Hovering the row shows the creature's details, its attack speed among them.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(this)
      if not this.npc then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      PinHelper:AddTooltipLines(this.npc)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, 0.04)
    -- A rare creature: the row glows gold from the left, with a gold edge (as on the website).
    row.RareGlow = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.RareGlow:SetAllPoints()
    row.RareGlow:SetColorTexture(1, 1, 1, 1)
    if CreateColor and not pcall(row.RareGlow.SetGradient, row.RareGlow, "HORIZONTAL",
        CreateColor(1, 0.82, 0, 0.18), CreateColor(1, 0.82, 0, 0.02)) then
      pcall(row.RareGlow.SetGradientAlpha, row.RareGlow, "HORIZONTAL", 1, 0.82, 0, 0.18, 1, 0.82, 0, 0.02)
    end
    row.RareEdge = row:CreateTexture(nil, "BORDER")
    row.RareEdge:SetPoint("TOPLEFT")
    row.RareEdge:SetPoint("BOTTOMLEFT")
    row.RareEdge:SetWidth(2)
    row.RareEdge:SetColorTexture(1, 0.82, 0, 0.6)
    -- An elite creature: the skull raid marker before its name.
    row.EliteIcon = row:CreateTexture(nil, "ARTWORK")
    row.EliteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    row.EliteIcon:SetSize(14, 14)
    -- A creature added in WoW Forever (patch 1.60 or later): the infinity mark first (as on the website), "New in
    -- Forever" on hover. A frame around the texture, so it can be hovered.
    row.ForeverIcon = CreateFrame("Frame", nil, row)
    row.ForeverIcon:SetSize(14, 14)
    row.ForeverIcon:SetPoint("TOPLEFT", 4, -2)
    row.ForeverIcon:EnableMouse(true)
    local infinity = row.ForeverIcon:CreateTexture(nil, "ARTWORK")
    infinity:SetAllPoints()
    infinity:SetTexture(Addon.FOREVER_ICON)
    row.ForeverIcon:SetScript("OnEnter", function(frame)
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetText(L.NEW_IN_FOREVER, 1, 1, 1)
      GameTooltip:Show()
    end)
    row.ForeverIcon:SetScript("OnLeave", GameTooltip_Hide)
    -- A creature an addon user has tamed (`tamed` in the data, the day of the last tame; `tamed_by`, who): a green dot
    -- after its name, "Verified Tame: <date> by <hunter>" on hover. The frame is a little larger than the dot, to be easier to hover.
    local badge = CreateFrame("Frame", nil, row)
    badge:SetSize(14, 14)
    badge:EnableMouse(true)
    local dot = badge:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints()
    dot:SetTexture(Addon.GREEN_DOT)
    badge:SetScript("OnEnter", function(frame)
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      local text = frame.by and L.VERIFIED_TAME_BY:format(frame.date or "", frame.by) or L.VERIFIED_TAME:format(frame.date or "")
      GameTooltip:SetText(text, 1, 1, 1)
      GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    row.TamedBadge = badge
  end

  local class = npc.class or ""
  local rare, elite = class:find("Rare", 1, true) ~= nil, class:find("Elite", 1, true) ~= nil
  local forever = npc.forever == true
  row.RareGlow:SetShown(rare)
  row.RareEdge:SetShown(rare)
  -- The marks before the name, left to right: infinity, then the skull; the name starts after them.
  local x = 4
  row.ForeverIcon:SetShown(forever)
  if forever then x = x + 17 end
  row.EliteIcon:ClearAllPoints()
  row.EliteIcon:SetPoint("TOPLEFT", x, -2)
  row.EliteIcon:SetShown(elite)
  if elite then x = x + 17 end
  -- The map button: the pins; the zone's map without pins (no map points); greyed out without a zone (or a map).
  local button = row.MapButton
  if npc.ui_map_id and npc.coords and #npc.coords > 0 then
    button:SetText(L.MAP)
    button:SetEnabled(true)
    button.hint = nil
  elseif npc.ui_map_id then
    button:SetText(L.NO_COORDINATES)
    button:SetEnabled(true)
    button.hint = L.NO_COORDINATES_TOOLTIP
  elseif not npc.location then
    button:SetText(L.UNKNOWN_ZONE)
    button:SetEnabled(false)
    button.hint = L.UNKNOWN_ZONE_TOOLTIP
  else
    button:SetText(L.MAP_UNAVAILABLE)
    button:SetEnabled(false)
    button.hint = nil
  end
  -- As wide as its word ("Map" is small); the name and the line under it get the rest of the row.
  button:SetWidth(math.max(44, math.ceil((button:GetTextWidth() or 60) + 24)))
  local reserve = button:GetWidth() + 8
  row.InfoText:ClearAllPoints()
  row.InfoText:SetPoint("TOPLEFT", 4, -18)
  row.InfoText:SetPoint("RIGHT", -reserve, 0)
  local badge = row.TamedBadge
  local tamed = type(npc.tamed) == "string" and npc.tamed ~= ""
  row.NameText:ClearAllPoints()
  row.NameText:SetPoint("TOPLEFT", x, -3)
  -- Room for the dot after the name, which is cut short before it when the row is narrow.
  row.NameText:SetPoint("RIGHT", tamed and -(reserve + badge:GetWidth() + 6) or -reserve, 0)
  row.NameText:SetText(Colors.Primary(npc.name))
  badge:SetShown(tamed)
  if tamed then
    badge.date = npc.tamed
    badge.by = type(npc.tamed_by) == "string" and npc.tamed_by ~= "" and npc.tamed_by or nil
    local width = row.NameText.GetUnboundedStringWidth and row.NameText:GetUnboundedStringWidth()
      or row.NameText:GetStringWidth()
    local room = row.NameText:GetWidth()
    if room and room > 0 then width = math.min(width, room) end
    badge:ClearAllPoints()
    badge:SetPoint("LEFT", row.NameText, "LEFT", width + 3, 0)
  end
  row.npc = npc
  row.InfoText:SetText(("%s %s  %s"):format(L.LEVEL, npc.level_range or L.UNKNOWN, npc.location or L.UNKNOWN_ZONE))
  button.npc = npc
end

function Window:UpdateDetails()
  if self.tab == "TRAINERS" then
    self:UpdateTrainerDetails()
    return
  end
  if self.tab == "COLLECTOR" then
    self:UpdateCollectedDetails()
    return
  end
  if self.tab == "BOUNTIES" then
    self:UpdateBountyDetails()
    return
  end
  if self.tab == "FAMILIES" then
    self:UpdateFamilyDetails()
    return
  end
  if self.tab == "OPTIONS" then
    self:UpdateOptionDetails()
    return
  end
  self:UpdateAbilityDetails() -- the ability tabs (tab-abilities.lua)
end

-- `/tsl debug icon`: every part of the details icon and what is drawn over it, to find art that covers the round icon.
function Window:DescribeIcon()
  local say = function(...) print(("|cFF007EA6%s|r icon:"):format(Addon.TITLE), ...) end
  if not (self.frame and self.iconButton) then return say("open the window first") end
  local function describe(prefix, object)
    local kind = object:GetObjectType()
    local w, h = object:GetSize()
    local extra = ""
    if kind == "Texture" then
      local layer, sub = object:GetDrawLayer()
      extra = (" layer %s/%s texture %s atlas %s masks %d"):format(tostring(layer), tostring(sub),
        tostring(object:GetTexture()), tostring(object.GetAtlas and object:GetAtlas()),
        object.GetNumMaskTextures and object:GetNumMaskTextures() or -1)
    elseif object.GetFrameLevel then
      extra = (" level %d strata %s"):format(object:GetFrameLevel(), tostring(object:GetFrameStrata()))
    end
    say(("%s%s %s shown=%s alpha=%.2f size %dx%d%s"):format(prefix, tostring(object:GetDebugName()), kind,
      tostring(object:IsShown()), object:GetAlpha(), w or 0, h or 0, extra))
  end
  local button = self.iconButton
  describe("button: ", button)
  for _, region in ipairs({ button:GetRegions() }) do describe("  region: ", region) end
  for _, child in ipairs({ button:GetChildren() }) do
    describe("  child: ", child)
    for _, region in ipairs({ child:GetRegions() }) do describe("    region: ", region) end
  end
  -- Frames of the details pane that overlap the icon (anything else could be drawn over it).
  local left, top, right, bottom = button:GetLeft(), button:GetTop(), button:GetRight(), button:GetBottom()
  for _, child in ipairs({ self.details:GetChildren() }) do
    if child ~= button and child:IsShown() and child:GetLeft() and child:GetLeft() < right and child:GetRight() > left
        and child:GetBottom() < top and child:GetTop() > bottom then
      describe("  over it: ", child)
    end
  end
end

-- The description starts under the taller part of the top row: the icon (with the name and subtitle
-- beside it) or the details, which can run to several lines (a long family list, for instance).
function Window:PlaceDescription()
  local iconBottom = DETAILS_TOP + self.iconButton:GetHeight()
  local factsBottom = DETAILS_TOP + 4 + (self.facts:GetStringHeight() or 0)
  self.description:ClearAllPoints()
  self.description:SetPoint("TOPLEFT", self.details, "TOPLEFT", DETAILS_LEFT, -(math.max(iconBottom, factsBottom) + 14))
  self.description:SetPoint("RIGHT", -20, 0)
end

-- ============================================================================
-- Options
-- ============================================================================

-- The saved UI Scale, kept within the slider's range.
function Window:SavedScale()
  local scale = tonumber(DB.global.ui_scale) or 1
  return math.min(MAX_SCALE, math.max(MIN_SCALE, scale))
end

-- Scales the window and keeps its center where it is on the screen, so it grows and shrinks in place.
function Window:ApplyScale(scale)
  local frame = self.frame
  if not frame or math.abs(frame:GetScale() - scale) < 0.001 then return end
  local x, y = frame:GetCenter()
  local before = frame:GetEffectiveScale()
  frame:SetScale(scale)
  if x and y then
    local after = frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * before / after, y * before / after)
  end
end

-- UI Scale: a slider with steppers, inside `parent` (the Options tab places it). The percentage follows the slider;
-- the window is scaled when a step is clicked or the thumb is let go (scaling while dragging would move the slider out
-- from under the cursor), and `changed` runs then.
function Window:CreateScaleSlider(parent, changed)
  if not MinimalSliderWithSteppersMixin then return nil end
  local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetWidth(240)

  local percent = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end
  slider:Init(self:SavedScale(), MIN_SCALE, MAX_SCALE, math.floor((MAX_SCALE - MIN_SCALE) / SCALE_STEP + 0.5),
    { [MinimalSliderWithSteppersMixin.Label.Right] = percent })

  local function save(value)
    value = math.floor(value / SCALE_STEP + 0.5) * SCALE_STEP -- Whole steps only.
    if math.abs(value - self:SavedScale()) < 0.001 then return end
    DB.global.ui_scale = value
    self:ApplyScale(value)
    if changed then changed() end
  end
  local dragging = function()
    return slider.Slider and slider.Slider.IsDraggingThumb and slider.Slider:IsDraggingThumb()
  end
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    if not dragging() then save(value) end
  end, self)
  if slider.Slider then
    slider.Slider:HookScript("OnMouseUp", function(this) save(this:GetValue()) end)
  end
  self.scaleSlider = slider
  return slider
end

