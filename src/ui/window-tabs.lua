local _, Addon = ...
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The column of side tabs down the window's right edge (the list of them is Window.TABS, in window.lua).

local TABS = Window.TABS

-- The side tabs can be moved: hold the left mouse button on one for a moment, drag it up or down the column and let go.
-- The order is saved for the character (`DB.char.tab_order`). The tabs are placed by slot, not chained to each other,
-- so a tab that is hidden (Collected Data without Collect Mode) leaves no gap wherever it sits.
local TAB_TOP, TAB_GAP = -60, 2 -- the first tab's offset under the frame's top right corner, and the space between tabs
local DRAG_DELAY = 0.4 -- seconds the button is held before the tab lifts
-- The tabs' size against the template's (90%). Their offsets are in their own scale, so the column shrinks with them.
local TAB_SCALE = 0.9

local noSideTab = {} -- tabs given no side tab (`noSideTab` in Window.TABS: none at the moment)
for _, info in ipairs(TABS) do
  if info.noSideTab then noSideTab[info.key] = true end
end

local function TabVisible(key)
  return not noSideTab[key] and (key ~= "COLLECTOR" or DB.global.collect == true)
end

-- The tabs' keys in the character's order: the saved order, then any tab it does not name in its usual place.
function Window:TabOrder()
  local order, seen = {}, {}
  for _, key in ipairs(DB.char.tab_order or {}) do
    for _, info in ipairs(TABS) do
      if info.key == key and not seen[key] then
        seen[key] = true
        order[#order + 1] = key
      end
    end
  end
  for _, info in ipairs(TABS) do
    if not seen[info.key] then order[#order + 1] = info.key end
  end
  return order
end

-- The keys of the tabs that show, in `order`.
local function VisibleKeys(order, without)
  local keys = {}
  for _, key in ipairs(order) do
    if key ~= without and TabVisible(key) then keys[#keys + 1] = key end
  end
  return keys
end

-- Places the tabs one under another in `order` (a tab being dragged is left to the cursor).
function Window:LayoutTabs(order, dragged)
  local byKey = {}
  for _, tab in ipairs(self.tabs) do byKey[tab.key] = tab end
  local y = TAB_TOP
  for _, key in ipairs(order or self:TabOrder()) do
    local tab = byKey[key]
    if tab and TabVisible(key) then
      if tab ~= dragged then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 0, y)
      end
      y = y - self.tabStep
    end
  end
end

function Window:BeginTabDrag(tab)
  self.dragTab = tab
  GameTooltip:Hide()
  tab:SetFrameLevel(tab:GetFrameLevel() + 20) -- over the other tabs
  self.dragDriver:Show()
end

-- Follows the cursor: the tab goes where it is, and the others make room for it.
function Window:UpdateTabDrag()
  local tab, frame = self.dragTab, self.frame
  local visible = VisibleKeys(self:TabOrder(), tab.key)
  local count = #visible + 1
  local _, cursor = GetCursorPosition()
  -- (in the tabs' own scale, as their offsets are)
  local offset = (cursor / frame:GetEffectiveScale() - frame:GetTop()) / TAB_SCALE - self.tabStep / 2
  offset = math.max(TAB_TOP - (count - 1) * self.tabStep, math.min(TAB_TOP, offset))
  tab:ClearAllPoints()
  tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, offset)

  local index = math.floor((TAB_TOP - offset) / self.tabStep + 0.5) + 1
  table.insert(visible, math.max(1, math.min(count, index)), tab.key)
  self.dragOrder = visible
  self:LayoutTabs(visible, tab)
end

-- Lets go: the tab takes its new place and the order is saved. Tabs that are hidden keep their own places.
function Window:EndTabDrag()
  local tab = self.dragTab
  if not tab then return end
  self.dragTab = nil
  self.dragDriver:Hide()
  tab:SetFrameLevel(tab:GetFrameLevel() - 20)

  if self.dragOrder then
    local nextVisible, order = 1, {}
    for _, key in ipairs(self:TabOrder()) do
      if TabVisible(key) then
        order[#order + 1] = self.dragOrder[nextVisible]
        nextVisible = nextVisible + 1
      else
        order[#order + 1] = key
      end
    end
    DB.char.tab_order = order
  end
  self.dragOrder = nil
  self:LayoutTabs()
  -- The mouse-up that ends the drag must not also select the tab.
  self.justDragged = true
  C_Timer.After(0.1, function() self.justDragged = false end)
end

-- Puts the tabs back in their usual order (the button on the Options tab).
function Window:ResetTabOrder()
  DB.char.tab_order = {}
  if self.tabs then self:LayoutTabs() end
end

function Window:CreateSideTabs(frame)
  self.tabs = {}
  for _, info in ipairs(TABS) do
    if not info.noSideTab then
      local tab = CreateFrame("Frame", nil, frame, "LargeSideTabButtonTemplate")
      tab:SetScale(TAB_SCALE)
      tab:EnableMouse(true)
      tab.Icon:SetTexture(info.icon)
      if tab.SetFillToInterior then tab:SetFillToInterior(true) end
      tab.tooltipText = info.label
      tab:SetScript("OnEnter", function(this)
        if self.dragTab then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(info.label)
        GameTooltip:AddLine(L.TAB_DRAG_HINT, 0.6, 0.6, 0.6)
        GameTooltip:Show()
      end)
      tab:SetScript("OnLeave", GameTooltip_Hide)
      tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if self.dragTab or self.justDragged then return end
        if button == "LeftButton" and upInside ~= false then self:SelectTab(info.key) end
      end)
      -- Held for a moment, the tab lifts and follows the cursor.
      tab:HookScript("OnMouseDown", function(this, button)
        if button ~= "LeftButton" then return end
        self.pressToken = (self.pressToken or 0) + 1
        local token = self.pressToken
        C_Timer.After(DRAG_DELAY, function()
          if self.pressToken == token and not self.dragTab and IsMouseButtonDown("LeftButton") then
            self:BeginTabDrag(this)
          end
        end)
      end)
      tab:HookScript("OnMouseUp", function() self.pressToken = (self.pressToken or 0) + 1 end)
      tab.key = info.key
      self.tabs[#self.tabs + 1] = tab
    end
  end
  local height = self.tabs[1]:GetHeight()
  self.tabStep = (height and height > 0 and height or 56) + TAB_GAP

  -- Moves the lifted tab each frame and drops it when the button is released.
  local driver = CreateFrame("Frame", nil, frame)
  driver:Hide()
  driver:SetScript("OnUpdate", function()
    if not self.dragTab then return end
    if IsMouseButtonDown("LeftButton") then
      self:UpdateTabDrag()
    else
      self:EndTabDrag()
    end
  end)
  driver:SetScript("OnHide", function() if self.dragTab then self:EndTabDrag() end end)
  self.dragDriver = driver

  self:LayoutTabs()
end
