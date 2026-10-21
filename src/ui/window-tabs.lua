local _, Addon = ...
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The side tabs, down the window's right edge and (any the player drags across) its left one. The list of them is
-- Window.TABS, in window.lua.

local TABS = Window.TABS

-- The side tabs can be moved: hold the left mouse button on one for a moment, drag it up or down (or across the window
-- to the other side) and let go.
-- The order is saved for the character (`DB.char.tab_order`). The tabs are placed by slot, not chained to each other,
-- so a tab that is hidden (Collected Data without Collect Mode) leaves no gap wherever it sits.
local TAB_GAP = 2 -- the space between tabs
-- The tabs' size against the template's (90%). Their offsets are in their own scale, so the column shrinks with them.
local TAB_SCALE = 0.9
-- Both columns start at the bottom of the header band, where the panes begin (72 under the window's top, just under
-- the logo): the first tab's offset, in the tabs' own scale.
local PANES_TOP = 72
local TAB_TOP = -PANES_TOP / TAB_SCALE
local leftNudge = 4 -- the left column moved this much toward the window (the art does not sit at the frame's edge)
local DRAG_DELAY = 0.4 -- seconds the button is held before the tab lifts

local noSideTab = {} -- tabs given no side tab (`noSideTab` in Window.TABS: Options and Help, the title bar's buttons)
for _, info in ipairs(TABS) do
  if info.noSideTab then noSideTab[info.key] = true end
end

-- Whether a side tab shows: not one of the title bar's sections, not turned off (Options, Tab Organization), and the
-- Collected Data tab only with Collect Mode on (its own checkbox).
local function TabVisible(key)
  if noSideTab[key] or (DB.char.tab_hidden or {})[key] then return false end
  return key ~= "COLLECTOR" or DB.global.collect == true
end

function Window:TabShown(key)
  return TabVisible(key)
end

-- The side tabs Tab Organization lists, with a checkbox each: all but the title bar's sections and Collected Data.
function Window:OrganizableTabs()
  local list = {}
  for _, info in ipairs(TABS) do
    if not noSideTab[info.key] and info.key ~= "COLLECTOR" then list[#list + 1] = info end
  end
  return list
end

-- Shows or hides a side tab. The last one showing stays (returns false then). Hiding the tab you are on goes to the
-- first that shows.
function Window:SetTabShown(key, shown)
  DB.char.tab_hidden = DB.char.tab_hidden or {}
  if not shown then
    local left = 0
    for _, info in ipairs(self:OrganizableTabs()) do
      if info.key ~= key and TabVisible(info.key) then left = left + 1 end
    end
    if left == 0 then return false end
  end
  DB.char.tab_hidden[key] = (not shown) or nil
  if not TabVisible(self.tab) and not (self.titleSections or {})[self.tab] then
    self:SelectTab(self:KnownTab(nil))
  end
  self:UpdateTabs()
  return true
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

-- Each tab sits on the window's right edge (the usual) or its left one: `DB.char.tab_side[key] = "left"`. Drag a tab
-- past the window's middle and it snaps to the other side. Each side is a column of its own, in the character's order.
local function SideOf(key)
  return (DB.char.tab_side or {})[key] == "left" and "left" or "right"
end

-- The first tab's offset (in the tabs' own scale) on a side.
local function TabTop(side)
  return TAB_TOP -- (the same on both sides)
end

-- A tab at `y` on a side: its edge against the window's.
local function PlaceTab(tab, frame, side, y)
  tab:ClearAllPoints()
  if side == "left" then
    tab:SetPoint("TOPRIGHT", frame, "TOPLEFT", leftNudge, y)
  else
    tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, y)
  end
end

-- The template's art is drawn to stick out to the right: on the left side it is mirrored (each texture's coordinates
-- swapped left for right, the icon's own offset turned around; the icon itself is not flipped).
local FLIP = { LEFT = "RIGHT", RIGHT = "LEFT", TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "BOTTOMRIGHT",
  BOTTOMRIGHT = "BOTTOMLEFT" }
-- A part's anchors turned around left for right (the template insets its parts unevenly, so flipping the art alone
-- leaves the tab's frame off the window's edge on the left).
local function MirrorAnchors(region)
  local points = {}
  for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
  if #points == 0 then return end
  region:ClearAllPoints()
  for _, p in ipairs(points) do
    local point, relativeTo, relativePoint, x, y = p[1], p[2], p[3], p[4], p[5]
    region:SetPoint(FLIP[point] or point, relativeTo, FLIP[relativePoint] or relativePoint, -(x or 0), y or 0)
  end
end

-- A texture's picture turned around left for right.
local function FlipTexture(region)
  if region.GetTexCoord and region.SetTexCoord then
    local ulx, uly, llx, lly, urx, ury, lrx, lry = region:GetTexCoord()
    region:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly)
  end
end

-- How a tab is mirrored on the left (`/tsl debug tabs art|mask|icon` changes it live, to compare in game):
--   art   the frame art flipped (common-sidetab, its selected glow)
--   mask  the icon's corner mask: "flip" (turned half a turn: a mask ignores flipped coordinates, and its shape is the
--         same top and bottom, so this mirrors it), "keep" (as on the right) or "off" (no mask)
--   icon  the icon's offset turned around (it sits toward the window on either side)
local MIRROR = { art = true, mask = "flip", icon = true }

local function IconMasks(icon)
  local masks = {}
  if icon and icon.GetNumMaskTextures then
    for i = 1, icon:GetNumMaskTextures() do masks[#masks + 1] = icon:GetMaskTexture(i) end
  end
  return masks
end

-- Mirrors a tab for the left side the way MIRROR says (remembering how, so it can be undone exactly), or undoes it.
local function MirrorTab(tab, left)
  if (tab.ftMirrored == true) == left then return end
  local icon = tab.Icon
  if left then
    local how = { art = MIRROR.art, mask = MIRROR.mask, icon = MIRROR.icon, masks = IconMasks(icon) }
    tab.ftHow = how
    for _, region in ipairs({ tab:GetRegions() }) do
      if region ~= icon and not region:IsObjectType("MaskTexture") then
        MirrorAnchors(region)
        if how.art then FlipTexture(region) end
      end
    end
    if how.icon and icon then MirrorAnchors(icon) end
    for _, mask in ipairs(how.masks) do
      MirrorAnchors(mask)
      if how.mask == "flip" and mask.SetRotation then mask:SetRotation(math.pi) end
      if how.mask == "off" then icon:RemoveMaskTexture(mask) end
    end
  else
    local how = tab.ftHow or {}
    for _, region in ipairs({ tab:GetRegions() }) do
      if region ~= icon and not region:IsObjectType("MaskTexture") then
        MirrorAnchors(region)
        if how.art then FlipTexture(region) end
      end
    end
    if how.icon and icon then MirrorAnchors(icon) end
    for _, mask in ipairs(how.masks or {}) do
      if how.mask == "off" then icon:AddMaskTexture(mask) end
      MirrorAnchors(mask)
      if how.mask == "flip" and mask.SetRotation then mask:SetRotation(0) end
    end
    tab.ftHow = nil
  end
  for _, child in ipairs({ tab:GetChildren() }) do MirrorAnchors(child) end
  tab.ftMirrored = left
end

-- The template moves the icon when a tab is pressed and let go (its pressed look), and puts it back where it goes on
-- the right side: on a left tab, that undoes the icon's mirroring. Its offset there is toward the window: negative x
-- (left) on the right side, so a left tab's icon with a negative x has been put back, and is mirrored again.
local function KeepIconMirrored(tab)
  local icon = tab.Icon
  if not (tab.ftMirrored and tab.ftHow and tab.ftHow.icon and icon and icon:GetNumPoints() == 1) then return end
  local _, _, _, x = icon:GetPoint(1)
  if (x or 0) < 0 then MirrorAnchors(icon) end
end
Window.KeepIconMirrored = KeepIconMirrored

-- `/tsl debug tabs art|mask|icon`: changes how the left tabs are mirrored (MIRROR) and redraws them, to compare.
function Window:SetTabMirror(part)
  local say = function(...) print(("|cFF007EA6%s|r tab mirror:"):format(Addon.TITLE), ...) end
  if part == "right" or part == "left" then
    leftNudge = leftNudge + (part == "right" and 1 or -1)
    self:LayoutTabs()
    return say("the left column is", leftNudge, "toward the window (/reload goes back to the usual)")
  end
  if part == "art" then MIRROR.art = not MIRROR.art
  elseif part == "icon" then MIRROR.icon = not MIRROR.icon
  elseif part == "mask" then MIRROR.mask = ({ flip = "keep", keep = "off", off = "flip" })[MIRROR.mask]
  end
  if self.tabs then
    for _, tab in ipairs(self.tabs) do
      if tab.ftMirrored then MirrorTab(tab, false); MirrorTab(tab, true) end
    end
  end
  say(("art %s, mask %s, icon %s"):format(MIRROR.art and "flipped" or "as on the right", MIRROR.mask,
    MIRROR.icon and "toward the window" or "as on the right"), "- /reload goes back to the usual")
end

-- `/tsl debug tabs`: the parts of a left-side tab (or the first tab): each region's type, its art and anchors, and the
-- icon's masks, to check the mirroring.
function Window:DescribeTab()
  local say = function(...) print(("|cFF007EA6%s|r tab:"):format(Addon.TITLE), ...) end
  if not self.tabs then return say("open the window first") end
  local tab = self.tabs[1]
  for _, t in ipairs(self.tabs) do if t.ftMirrored then tab = t; break end end
  say(tab.key, tab.ftMirrored and "(left side, mirrored)" or "(right side)", "size", tab:GetWidth(), tab:GetHeight())
  local function describe(label, region)
    local art = region.GetAtlas and region:GetAtlas() or (region.GetTexture and region:GetTexture())
    local coords = region.GetTexCoord and table.concat({ region:GetTexCoord() }, ",") or "-"
    local points = {}
    for i = 1, region:GetNumPoints() do
      local p, _, rp, x, y = region:GetPoint(i)
      points[#points + 1] = ("%s>%s %s,%s"):format(p, rp, tostring(x), tostring(y))
    end
    say(("  %s %s art=%s coords=%s points=%s"):format(label, region:GetObjectType(), tostring(art), coords,
      table.concat(points, " ; ")))
  end
  for i, region in ipairs({ tab:GetRegions() }) do describe(region == tab.Icon and "icon" or ("region" .. i), region) end
  if tab.Icon and tab.Icon.GetNumMaskTextures then
    for i = 1, tab.Icon:GetNumMaskTextures() do describe("iconmask" .. i, tab.Icon:GetMaskTexture(i)) end
  end
end

-- The keys of the tabs that show on a side, in the character's order.
local function Column(order, side, without)
  local keys = {}
  for _, key in ipairs(order) do
    if key ~= without and TabVisible(key) and SideOf(key) == side then keys[#keys + 1] = key end
  end
  return keys
end

-- Places the tabs: each side's column one under another (`columns`: the order to show while a tab is dragged, which
-- is left to the cursor). Then mirrors each tab for its side, and keeps the window on the screen with its tabs (it is
-- held on screen by its own edges plus the tabs' width on each side that has some).
function Window:LayoutTabs(columns, dragged)
  local byKey = {}
  for _, tab in ipairs(self.tabs) do byKey[tab.key] = tab end
  local order = self:TabOrder()
  columns = columns or { left = Column(order, "left"), right = Column(order, "right") }
  local used = {}
  for _, side in ipairs({ "right", "left" }) do
    local y = TabTop(side)
    for _, key in ipairs(columns[side]) do
      local tab = byKey[key]
      if tab then
        MirrorTab(tab, side == "left")
        KeepIconMirrored(tab)
        if tab ~= dragged then PlaceTab(tab, self.frame, side, y) end
        used[side] = true
        y = y - self.tabStep
      end
    end
  end
  local width = (self.tabs[1] and self.tabs[1]:GetWidth() or 48) * TAB_SCALE
  self.frame:SetClampRectInsets(used.left and -width or 0, used.right and width or 0, 0, 0)
end

function Window:ApplyTabSide()
  if self.tabs then self:LayoutTabs() end
end

function Window:BeginTabDrag(tab)
  self.dragTab = tab
  GameTooltip:Hide()
  tab:SetFrameLevel(tab:GetFrameLevel() + 20) -- over the other tabs
  self.dragDriver:Show()
end

-- Follows the cursor: the tab goes where it is (on the side of the window's middle the cursor is on), and the others
-- on that side make room for it.
function Window:UpdateTabDrag()
  local tab, frame = self.dragTab, self.frame
  local order = self:TabOrder()
  local scale = frame:GetEffectiveScale()
  local cursorX, cursorY = GetCursorPosition()
  local side = cursorX / scale < (frame:GetLeft() + frame:GetRight()) / 2 and "left" or "right"
  local columns = { left = Column(order, "left", tab.key), right = Column(order, "right", tab.key) }
  local column = columns[side]
  local count = #column + 1
  local top = TabTop(side)
  -- (in the tabs' own scale, as their offsets are)
  local offset = (cursorY / scale - frame:GetTop()) / TAB_SCALE - self.tabStep / 2
  offset = math.max(top - (count - 1) * self.tabStep, math.min(top, offset))
  MirrorTab(tab, side == "left")
  PlaceTab(tab, frame, side, offset)

  local index = math.floor((top - offset) / self.tabStep + 0.5) + 1
  table.insert(column, math.max(1, math.min(count, index)), tab.key)
  self.dragColumns, self.dragSide = columns, side
  self:LayoutTabs(columns, tab)
end

-- Lets go: the tab takes its new place and side, and both are saved. Tabs that are hidden keep their own places.
function Window:EndTabDrag()
  local tab = self.dragTab
  if not tab then return end
  self.dragTab = nil
  self.dragDriver:Hide()
  tab:SetFrameLevel(tab:GetFrameLevel() - 20)

  if self.dragColumns then
    DB.char.tab_side = DB.char.tab_side or {}
    DB.char.tab_side[tab.key] = self.dragSide == "left" and "left" or nil
    -- The shown tabs take the slots of the shown ones, right column first, then the left; hidden ones stay put.
    local shown = {}
    for _, side in ipairs({ "right", "left" }) do
      for _, key in ipairs(self.dragColumns[side]) do shown[#shown + 1] = key end
    end
    local nextShown, order = 1, {}
    for _, key in ipairs(self:TabOrder()) do
      if TabVisible(key) then
        order[#order + 1] = shown[nextShown]
        nextShown = nextShown + 1
      else
        order[#order + 1] = key
      end
    end
    DB.char.tab_order = order
  end
  self.dragColumns, self.dragSide = nil, nil
  self:LayoutTabs()
  -- The mouse-up that ends the drag must not also select the tab.
  self.justDragged = true
  C_Timer.After(0.1, function() self.justDragged = false end)
end

-- Puts the tabs back in their usual order, all on the right (the button on the Options tab).
function Window:ResetTabOrder()
  DB.char.tab_order = {}
  DB.char.tab_side = {}
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
        GameTooltip:SetOwner(this, SideOf(info.key) == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT") -- (away from the window)
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
        KeepIconMirrored(this) -- (the template moved it for its pressed look)
        if button ~= "LeftButton" then return end
        self.pressToken = (self.pressToken or 0) + 1
        local token = self.pressToken
        C_Timer.After(DRAG_DELAY, function()
          if self.pressToken == token and not self.dragTab and IsMouseButtonDown("LeftButton") then
            self:BeginTabDrag(this)
          end
        end)
      end)
      tab:HookScript("OnMouseUp", function(this)
        self.pressToken = (self.pressToken or 0) + 1
        KeepIconMirrored(this) -- (after the template's own handler, which put the icon back for the right side)
      end)
      tab.key = info.key
      self.tabs[#self.tabs + 1] = tab
    end
  end
  local height = self.tabs[1]:GetHeight()
  self.tabStep = (height and height > 0 and height or 56) + TAB_GAP
  self:ApplyTabSide()

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
