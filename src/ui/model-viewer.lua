local _, Addon = ...
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")

-- A creature's 3D model in a dark, bronze-edged box, drawn by the game: drag to turn it, right-drag to move it, the
-- mouse wheel to zoom. The Looks tab and the pet profile each have one. The zoom the player leaves it at is kept for
-- the next model the box shows; the turn and the move start over with each.

local NewText = Helpers.NewText

local MODEL_HEIGHT = 190 -- the box's height until its owner sets another
local MODEL_FACING = math.rad(35) -- turned a little, as the website's 3D views start
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.6, 2.5, 0.1 -- the camera's distance against the frame's own framing
local TURN_SPEED = 0.012 -- radians per pixel the cursor moves while turning a model
-- Moving a model: how much of the scene the frame shows from top to bottom, against how far the camera stands from
-- the model (about the game's model camera's field of view), so the model keeps up with the cursor whatever its size;
-- and the camera's distance when the client cannot tell it.
local PAN_VIEW = 0.9
local PAN_DISTANCE = 4

-- The model at the zoom the player left it at (model.zoom), moved where the player dragged it (model.panY, model.panZ).
local function ApplyZoom(model)
  local zoom = model.zoom or 1
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
  if model.zoomedByCamera then distance = distance * (model.zoom or 1) end
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

-- Shows a creature: by its display id (the look), else by its npc id, which the game can only draw for a creature it
-- knows. Facing as it starts, back in the middle, at the zoom the player left it at. Returns whether it shows.
local function ShowModel(box, display, creatureId)
  local model = box.model
  local shown = false
  if model then
    pcall(model.ClearModel, model)
    if display then
      shown = (pcall(model.SetDisplayInfo, model, display))
    elseif creatureId then
      shown = (pcall(model.SetCreature, model, creatureId))
    end
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
  return shown
end

-- The box, in `parent`; its owner places it (its height is MODEL_HEIGHT until set). The hint ("Drag to turn, ...")
-- sits under it on the right. box:ShowModel(display, creatureId) shows a creature.
function Helpers.NewModelViewer(parent)
  local box = CreateFrame("Frame", nil, parent)
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
    -- The wheel zooms: up closer, down farther. Kept for the next model.
    model:SetScript("OnMouseWheel", function(this, delta)
      this.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (this.zoom or 1) - delta * ZOOM_STEP))
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

  box.hint = NewText(box, "GameFontDisableSmall", "RIGHT")
  box.hint:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -5)
  box.hint:SetText(L.LOOK_HINT)

  box.ShowModel = ShowModel
  return box
end
