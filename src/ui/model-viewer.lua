local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")

-- A creature's 3D model in a dark, bronze-edged box, drawn by the game: drag to turn it, right-drag to move it, the
-- mouse wheel to zoom; and, while the mouse is over the box, the game's own model buttons along its top (zoom in and
-- out, turn left and right, reset), as on the stable's pet. The Looks tab and the pet profile each have one. The zoom
-- the player leaves it at is kept for the next model the box shows; the turn and the move start over with each.

local NewText = Helpers.NewText

local MODEL_HEIGHT = 190 -- the box's height until its owner sets another
local MODEL_FACING = math.rad(35) -- turned a little, as the website's 3D views start
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.6, 2.5, 0.1 -- the camera's distance against the frame's own framing
local TURN_SPEED = 0.012 -- radians per pixel the cursor moves while turning a model
-- Moving a model: how much of the scene the frame shows from top to bottom, against how far the camera stands from
-- the model (about the game's model camera's field of view), so the model keeps up with the cursor whatever its size;
-- and the camera's distance when the client cannot tell it. The client sometimes answers with a number that means
-- nothing (about 8e37 for the pet profile's box, seen in November 2026): a distance over PAN_DISTANCE_MAX is not
-- believed, or the first pixel of a drag would throw the creature out of its box.
local PAN_VIEW = 0.9
local PAN_DISTANCE = 4
local PAN_DISTANCE_MAX = 100

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
  if not (ok and type(distance) == "number" and distance > 0 and distance <= PAN_DISTANCE_MAX) then
    distance = PAN_DISTANCE
  end
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
  if dx == 0 and dy == 0 then return end -- (a click, or the cursor held still: the model stays as it is)
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
  box.shown = shown -- (the buttons show over a model only)
  return shown
end

-- ----------------------------------------------------------------------------
-- The model buttons
-- ----------------------------------------------------------------------------

-- The game's model buttons, drawn from its own art sheet with the coordinates its templates use
-- (Blizzard_SharedXML ModelFrames.xml, ModelControlButtonTemplate): a square behind each icon, darker while held, and
-- a glow on hover. The icons are the sheet's.
local CONTROL_ART = "Interface\\Common\\UI-ModelControlPanel"
local CONTROL_SQUARE = { 0.296875, 0.546875, 0.1484375, 0.2734375 }
local CONTROL_SQUARE_DOWN = { 0.015625, 0.265625, 0.1484375, 0.2734375 }
local CONTROL_GLOW = { 0.578125, 0.828125, 0.0078125, 0.1328125 }
local CONTROL_SIZE, CONTROL_ART_SIZE, CONTROL_GAP = 22, 20, 2
local TURN_RATE = 2.5 -- radians a second while a turn button is held
local NEXT_ZOOM = -1 -- (the wheel's delta for zooming out)

local CONTROLS = {
  { key = "zoomIn", icon = { 0.578125, 0.828125, 0.1484375, 0.2734375 }, tooltip = ZOOM_IN or L.ZOOM_IN,
    detail = KEY_MOUSEWHEELUP, wheel = 1 },
  { key = "zoomOut", icon = { 0.296875, 0.546875, 0.0078125, 0.1328125 }, tooltip = ZOOM_OUT or L.ZOOM_OUT,
    detail = KEY_MOUSEWHEELDOWN, wheel = NEXT_ZOOM },
  { key = "turnLeft", icon = { 0.015625, 0.265625, 0.2890625, 0.4140625 }, tooltip = ROTATE_LEFT or L.TURN_LEFT,
    detail = L.TURN_HINT, turn = 1 },
  { key = "turnRight", icon = { 0.578125, 0.828125, 0.2890625, 0.4140625 }, tooltip = ROTATE_RIGHT or L.TURN_RIGHT,
    detail = L.TURN_HINT, turn = -1 },
  { key = "reset", icon = { 0.015625, 0.265625, 0.0078125, 0.1328125 }, tooltip = RESET_POSITION or L.RESET_VIEW,
    detail = L.MOVE_HINT, reset = true },
}

-- Turns the model while a turn button is held (its OnUpdate).
local function TurnOnUpdate(button, elapsed)
  local model = button.model
  model.facing = (model.facing or MODEL_FACING) + button.control.turn * TURN_RATE * elapsed
  pcall(model.SetFacing, model, model.facing)
end

-- The buttons' frame shows while the mouse is over the box (the model or a button), and only over a model.
local function UpdateControls(box)
  local controls = box.controls
  if not controls then return end
  controls:SetShown(box.shown == true and (box:IsMouseOver() or controls:IsMouseOver()))
end

local function NewControls(box)
  local model = box.model
  local controls = CreateFrame("Frame", nil, box)
  controls:SetSize(#CONTROLS * CONTROL_SIZE + (#CONTROLS - 1) * CONTROL_GAP, CONTROL_SIZE)
  controls:SetPoint("TOP", box, "TOP", 0, -6)
  controls:SetFrameLevel(model:GetFrameLevel() + 5)
  controls:Hide()
  for index, control in ipairs(CONTROLS) do
    local button = CreateFrame("Button", nil, controls)
    button:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    button:SetPoint("LEFT", (index - 1) * (CONTROL_SIZE + CONTROL_GAP), 0)
    button.model, button.control = model, control
    button.square = button:CreateTexture(nil, "BACKGROUND")
    button.square:SetTexture(CONTROL_ART)
    button.square:SetTexCoord(unpack(CONTROL_SQUARE))
    button.square:SetSize(CONTROL_ART_SIZE, CONTROL_ART_SIZE)
    button.square:SetPoint("CENTER")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(CONTROL_ART)
    button.icon:SetTexCoord(unpack(control.icon))
    button.icon:SetSize(CONTROL_ART_SIZE, CONTROL_ART_SIZE)
    button.icon:SetPoint("CENTER")
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetTexture(CONTROL_ART)
    glow:SetTexCoord(unpack(CONTROL_GLOW))
    glow:SetSize(CONTROL_ART_SIZE, CONTROL_ART_SIZE)
    glow:SetPoint("CENTER")
    -- Held: the darker square and the icon nudged down, as the game's; a turn button turns the model meanwhile.
    button:SetScript("OnMouseDown", function(this)
      this.square:SetTexCoord(unpack(CONTROL_SQUARE_DOWN))
      this.icon:SetPoint("CENTER", 1, -1)
      if this.control.turn then this:SetScript("OnUpdate", TurnOnUpdate) end
    end)
    button:SetScript("OnMouseUp", function(this)
      this.square:SetTexCoord(unpack(CONTROL_SQUARE))
      this.icon:SetPoint("CENTER", 0, 0)
      this:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnHide", function(this) this:GetScript("OnMouseUp")(this) end)
    button:SetScript("OnClick", function(this)
      local m, c = this.model, this.control
      if c.wheel then
        m:GetScript("OnMouseWheel")(m, c.wheel)
      elseif c.reset then
        m.zoom, m.panY, m.panZ, m.facing = 1, 0, 0, MODEL_FACING
        pcall(m.SetFacing, m, MODEL_FACING)
        ApplyZoom(m)
        ApplyPan(m)
      end
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_INVENTORY_ROTATE_CHARACTER then
        PlaySound(SOUNDKIT.IG_INVENTORY_ROTATE_CHARACTER)
      end
    end)
    button:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText(this.control.tooltip, 1, 1, 1)
      if this.control.detail then Helpers.TipLine(this.control.detail, Colors.Muted, true) end
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      GameTooltip_Hide()
      UpdateControls(box)
    end)
  end
  box.controls = controls
end

-- `/tsl debug model`: what a model box's camera and position are (after a drag: where it was left), to find why a
-- model leaves its box. Returns a line of text.
function Helpers.DescribeModelViewer(box)
  local model = box and box.model
  if not model then return "no model frame" end
  local function call(name)
    if type(model[name]) ~= "function" then return "n/a" end
    local values = { pcall(model[name], model) }
    if not values[1] then return "error" end
    local parts = {}
    for index = 2, #values do
      parts[#parts + 1] = type(values[index]) == "number" and ("%.3f"):format(values[index]) or tostring(values[index])
    end
    return table.concat(parts, ", ")
  end
  return ("shown=%s size=%dx%d scale=%.2f | camera distance=%s | position=%s | model scale=%s | zoom=%s by camera=%s | "
    .. "pan y=%s z=%s | per pixel=%.5f | facing=%s | dragging=%s"):format(tostring(model:IsShown()),
    model:GetWidth() or 0, model:GetHeight() or 0, model:GetEffectiveScale() or 0, call("GetCameraDistance"),
    call("GetPosition"), call("GetModelScale"), tostring(model.zoom or 1), tostring(model.zoomedByCamera),
    tostring(model.panY), tostring(model.panZ), PanPerPixel(model), tostring(model.facing), tostring(model.dragButton))
end

-- The box, in `parent`; its owner places it (its height is MODEL_HEIGHT until set). box:ShowModel(display, creatureId)
-- shows a creature.
function Helpers.NewModelViewer(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetHeight(MODEL_HEIGHT)
  local background = box:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.035, 0.03, 0.85)
  for _, edge in ipairs(Helpers.AddEdges(box, 1, "BORDER")) do edge:SetColorTexture(Colors.Metal:GetRGBA(0.8)) end -- bronze

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
    -- The model buttons, while the mouse is over the box.
    NewControls(box)
    model:SetScript("OnEnter", function() UpdateControls(box) end)
    model:SetScript("OnLeave", function() UpdateControls(box) end)
  end

  box.noModel = NewText(box, "GameFontDisable", "CENTER")
  box.noModel:SetPoint("CENTER")
  box.noModel:SetText(L.LOOK_NO_MODEL)

  box.ShowModel = ShowModel
  return box
end
