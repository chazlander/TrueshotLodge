local _, Addon = ...
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Looks" tab, as TrueshotLodge.com/looks: the looks each family's creatures come in (the creatures that look
-- alike: the same model and textures, whatever their size; data/Looks.lua). On the left the families,
-- each a heading with its looks under it (the number of its creatures beside each; gold when only one creature has
-- it, the only place to get that look); on the right the selected look: its 3D model, drawn by the game from its
-- display id (drag to turn it, right-drag to move it, the mouse wheel to zoom), then the creatures with that look and
-- their Map buttons. The title bar's Zone Filter and Filter by Level narrow the creatures, as on the Families tab: a
-- look none of whose creatures are left is not listed.

local PlayClick = Helpers.PlayClick
local NewText = Helpers.NewText
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON
local COUNT_COLOR = { 0.78, 0.69, 0.55 } -- the tan of the website's count badges
local UNIQUE_COLOR = { 1, 0.82, 0 } -- gold, as the website's edge on a look only one creature has

local MODEL_HEIGHT = 190
local MODEL_FACING = math.rad(35) -- turned a little, as the website's 3D views start
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.6, 2.5, 0.1 -- the camera's distance against the frame's own framing
local TURN_SPEED = 0.012 -- radians per pixel the cursor moves while turning a model
-- Moving a model: how much of the scene the frame shows from top to bottom, against how far the camera stands from
-- the model (about the game's model camera's field of view), so the model keeps up with the cursor whatever its size;
-- and the camera's distance when the client cannot tell it.
local PAN_VIEW = 0.9
local PAN_DISTANCE = 4

-- A look's name: its texture's (in the data), else its creature's when only one has it, else the family's ("Bat": the
-- family's own look, with no colour of its own). As the website's look_name().
local function LookName(look, family)
  if look.name then return look.name end
  local first = #look.npcs == 1 and Addon:GetNPC(look.npcs[1])
  return first and first.name or Addon:FamilyLabel(family)
end

-- ----------------------------------------------------------------------------
-- The model and its controls (made once, shown only on this tab: Window:UpdateTabs)
-- ----------------------------------------------------------------------------

-- The model shows `look`, facing as it starts, at the zoom the player left it at (Window.lookZoom), moved where the
-- player dragged it (model.panY, model.panZ: back to the middle for each new look).
local function ApplyZoom(model)
  local zoom = Window.lookZoom or 1
  model.zoomedByCamera = model.SetCamDistanceScale and pcall(model.SetCamDistanceScale, model, zoom) or false
  if not model.zoomedByCamera then
    pcall(model.SetModelScale, model, 1 / zoom) -- (where the camera cannot be moved, the model shrinks instead)
  end
end

local function ApplyPan(model)
  pcall(model.SetPosition, model, 0, model.panY or 0, model.panZ or 0)
end

-- How far the model moves for each pixel the cursor does: the part of the scene the frame shows, from the camera's
-- distance (times the zoom, when the zoom moves the camera), spread over the frame's height.
local function PanPerPixel(model)
  local ok, distance = pcall(model.GetCameraDistance, model)
  if not (ok and type(distance) == "number" and distance > 0) then distance = PAN_DISTANCE end
  if model.zoomedByCamera then distance = distance * (Window.lookZoom or 1) end
  local height = model:GetHeight()
  return distance * PAN_VIEW / ((height and height > 0) and height or MODEL_HEIGHT)
end

-- While a mouse button is held on the model: the left turns it with the cursor, the right moves it with the cursor
-- (never so far that its middle leaves the frame).
local function DragOnUpdate(model)
  local x, y = GetCursorPosition()
  local scale = model:GetEffectiveScale() or 1
  local dx, dy = (x - model.dragX) / scale, (y - model.dragY) / scale
  model.dragX, model.dragY = x, y
  if model.dragButton == "LeftButton" then
    model.facing = (model.facing or MODEL_FACING) + dx * TURN_SPEED
    pcall(model.SetFacing, model, model.facing)
  else
    local unit = PanPerPixel(model)
    local maxY, maxZ = unit * model:GetWidth() / 2, unit * model:GetHeight() / 2
    model.panY = math.max(-maxY, math.min(maxY, (model.panY or 0) + dx * unit))
    model.panZ = math.max(-maxZ, math.min(maxZ, (model.panZ or 0) + dy * unit))
    ApplyPan(model)
  end
end

function Window:LookWidgets()
  if self.lookWidgets then return self.lookWidgets end
  local details = self.details
  local box = CreateFrame("Frame", nil, details)
  box:SetHeight(MODEL_HEIGHT)
  local background = box:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.035, 0.03, 0.85)
  for _, edge in ipairs(Helpers.AddEdges(box, 1, "BORDER")) do edge:SetColorTexture(0.42, 0.31, 0.15, 0.8) end -- bronze

  local ok, model = pcall(CreateFrame, "PlayerModel", nil, box)
  if ok and model then
    model:SetPoint("TOPLEFT", 1, -1)
    model:SetPoint("BOTTOMRIGHT", -1, 1)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    -- Drag to turn the model, right-drag to move it: one button at a time, the one pressed first.
    model:SetScript("OnMouseDown", function(this, button)
      if this.dragButton or (button ~= "LeftButton" and button ~= "RightButton") then return end
      this.dragButton = button
      this.dragX, this.dragY = GetCursorPosition()
      this:SetScript("OnUpdate", DragOnUpdate)
    end)
    model:SetScript("OnMouseUp", function(this, button)
      if button ~= this.dragButton then return end
      this.dragButton = nil
      this:SetScript("OnUpdate", nil)
    end)
    model:SetScript("OnHide", function(this)
      this.dragButton = nil
      this:SetScript("OnUpdate", nil)
    end)
    -- The wheel zooms: up closer, down farther. Kept for the next look.
    model:SetScript("OnMouseWheel", function(this, delta)
      Window.lookZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (Window.lookZoom or 1) - delta * ZOOM_STEP))
      ApplyZoom(this)
    end)
    -- A model's framing is set again once it has loaded (setting a model resets it).
    pcall(model.SetScript, model, "OnModelLoaded", function(this)
      pcall(this.SetFacing, this, this.facing or MODEL_FACING)
      ApplyZoom(this)
      ApplyPan(this)
    end)
    box.model = model
  end

  box.noModel = NewText(box, "GameFontDisable", "CENTER")
  box.noModel:SetPoint("CENTER")
  box.noModel:SetText(L.LOOK_NO_MODEL)

  -- Under the frame, on the right.
  box.hint = NewText(box, "GameFontDisableSmall", "RIGHT")
  box.hint:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -5)
  box.hint:SetText(L.LOOK_HINT)

  self.lookWidgets = box
  return box
end

local function ShowModel(box, look)
  local model = box.model
  local shown = false
  if model and look then
    pcall(model.ClearModel, model)
    shown = (pcall(model.SetDisplayInfo, model, look.display))
    if shown then
      model.facing = MODEL_FACING
      pcall(model.SetFacing, model, MODEL_FACING)
      ApplyZoom(model)
      model.panY, model.panZ = 0, 0
      ApplyPan(model)
    end
    model:SetShown(shown)
  end
  box.noModel:SetShown(not shown)
  box.hint:SetShown(shown)
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

-- The families with their looks: { { key, family, info, rows = { { key, family, look, name, total, creatures } } } },
-- by family name. With the search, a look shows when it, its family or one of its creatures matches.
function Window:GetLookGroups()
  local search = self.search or ""
  local zone, level = self:ZoneFilter(), UnitLevel("player") or 1
  local filtered = zone ~= nil or DB.global.filter_by_level
  local groups = {}
  for family, looks in pairs(Addon.TameableLooks or {}) do
    local info = Addon.TameableFamilies and Addon.TameableFamilies[family]
    if info then
      local familyMatch = search == "" or family:lower():find(search, 1, true) ~= nil
      local group = { key = "looks:" .. family, family = family, info = info, rows = {} }
      for _, look in ipairs(looks) do
        local name = LookName(look, family)
        local creatures = self:BountyCreatures(look.npcs, zone, level) -- (with the filters)
        local match = familyMatch or name:lower():find(search, 1, true) ~= nil
        if not match then
          for _, npc in ipairs(creatures) do
            if (npc.name or ""):lower():find(search, 1, true) then match = true break end
          end
        end
        if match and (#creatures > 0 or not filtered) then
          group.rows[#group.rows + 1] = { key = family .. ":" .. look.display, family = family, look = look,
            name = name, total = #look.npcs, creatures = creatures }
        end
      end
      if #group.rows > 0 then groups[#groups + 1] = group end
    end
  end
  table.sort(groups, function(a, b) return a.family < b.family end)
  return groups
end

local function LookOnClick(button)
  PlayClick()
  Window:SelectLook(button.ftLook.key)
end

local function LookOnEnter(button)
  local row = button.ftLook
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.name)
  GameTooltip:AddLine(Addon:FamilyLabel(row.family), 1, 1, 1)
  if row.total == 1 then
    GameTooltip:AddLine(L.LOOK_UNIQUE_TOOLTIP, UNIQUE_COLOR[1], UNIQUE_COLOR[2], UNIQUE_COLOR[3], true)
  end
  GameTooltip:Show()
end

function Window:InitLookButton(button, row)
  button.Label:SetText(row.name)
  if row.total == 1 then
    button.Label:SetVertexColor(unpack(UNIQUE_COLOR))
  else
    button.Label:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
  end
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  -- The number of its creatures (with the filters), on the right like a badge (as on the Families tab).
  button.Count:ClearAllPoints()
  button.Count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
  button.Count:SetText(("(%d)"):format(#row.creatures))
  button.Count:SetTextColor(unpack(COUNT_COLOR))
  button.Count:Show()
  button.Label:SetWidth(button:GetWidth() - 60)

  local selected = self.selectedLook == row.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

  button.ftLook = row
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", LookOnClick)
  button:SetScript("OnEnter", LookOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:RefreshLooks()
  local groups = self:GetLookGroups()
  self.lookByKey = {}
  local first
  for _, group in ipairs(groups) do
    for _, row in ipairs(group.rows) do
      self.lookByKey[row.key] = row
      first = first or row.key
    end
  end
  -- The selection: the one shown before, else the one saved (sticky selections), else the first.
  if not (self.selectedLook and self.lookByKey[self.selectedLook]) then
    local saved = self:Sticky() and DB.global.selections.LOOKS
    self.selectedLook = (saved and self.lookByKey[saved]) and saved or first
  end
  local selectedFamily = self.selectedLook and self.lookByKey[self.selectedLook].family

  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.lookHeadersSeen = self.lookHeadersSeen or {}
  local looks, creatures = 0, 0
  for _, group in ipairs(groups) do
    self.listKeys[#self.listKeys + 1] = group.key
    -- A family starts closed the first time it is shown (all open would be a long list), but the selected look's;
    -- after that it stays as the player left it.
    if not self.lookHeadersSeen[group.key] then
      self.lookHeadersSeen[group.key] = true
      self.expanded[group.key] = group.family == selectedFamily or nil
    end
    local name = ("|T%s:16:16:0:0|t %s"):format(group.info.icon or QUESTION_MARK_ICON, Addon:FamilyLabel(group.family))
    local category = provider:Insert({ categoryInfo = { name = name }, key = group.key })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows) do
      category:Insert({ look = row })
      looks, creatures = looks + 1, creatures + #row.creatures
    end
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetFormattedText(L.LOOK_COUNTS, looks, creatures)
  self:UpdateToggleButton()
  self:UpdateLookDetails()
end

function Window:SelectLook(key)
  self.selectedLook = key
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local row = node:GetData().look
    if row then
      button.SelectedOverlay:SetShown(row.key == key)
      button.HighlightOverlay:SetShown(row.key ~= key)
    end
  end)
  self:UpdateLookDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

function Window:UpdateLookDetails()
  local row = self.selectedLook and self.lookByKey and self.lookByKey[self.selectedLook]
  local box = self:LookWidgets()
  if not row then
    box:Hide()
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  box:Show()

  -- The model at the top, where the other tabs have their icon, name and facts (hidden here: Window:UpdateTabs). The
  -- list already says the look's name and family, and how many creatures have it.
  self.description:SetText("")
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", self.details, "TOPLEFT", Window.DETAILS_LEFT, -Window.DETAILS_TOP)
  box:SetPoint("RIGHT", self.details, "RIGHT", -20, 0)
  ShowModel(box, row.look)

  self:ShowBountyCreatures(row.creatures, L.LOOK_CREATURES, L.LOOK_NONE)
end
