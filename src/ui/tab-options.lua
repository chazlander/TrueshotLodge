local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The "Options" tab, in the same list and details layout as the other tabs: the settings by group on the left, the
-- selected one on the right with what it does and its control (a checkbox, the UI Scale slider, the Reset Tab Order
-- button).

local function Setting(key, label, description, icon, get, set)
  return { key = key, label = label, description = description, icon = icon, kind = "check", get = get, set = set }
end

local function GlobalSetting(key, label, description, icon, default)
  return Setting(key, label, description, icon,
    function()
      if DB.global[key] == nil then return default end
      return DB.global[key] == true
    end,
    function(value) DB.global[key] = value end)
end

-- The groups and their settings, in order.
local function Groups()
  return {
    { key = "options:general", name = L.GENERAL, settings = {
      Setting("minimap", L.MINIMAP_ICON, L.MINIMAP_ICON_TOOLTIP, "Interface\\Icons\\INV_Misc_Map_01",
        function() return not DB.global.minimapIcon.hide end,
        function() Addon:GetModule("MinimapIcon"):Toggle() end),
      GlobalSetting("sticky_selections", L.STICKY_SELECTIONS, L.STICKY_SELECTIONS_TOOLTIP,
        "Interface\\Icons\\INV_Misc_PocketWatch_02", true),
    } },
    { key = "options:tooltips", name = L.TOOLTIPS, settings = {
      GlobalSetting("npc_tooltips", L.PET_TOOLTIPS, L.PET_TOOLTIPS_TOOLTIP, "Interface\\Icons\\Ability_Hunter_BeastTaming", true),
      GlobalSetting("ability_tooltips", L.PET_ABILITY_TOOLTIPS, L.PET_ABILITY_TOOLTIPS_TOOLTIP,
        "Interface\\Icons\\Ability_Hunter_BeastTraining", true),
    } },
    { key = "options:visual", name = L.VISUAL, settings = {
      { key = "ui_scale", label = L.UI_SCALE, description = L.UI_SCALE_TOOLTIP, icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
        kind = "scale" },
      { key = "tab_order", label = L.TAB_ORDER, description = L.RESET_TAB_ORDER_TOOLTIP, icon = "Interface\\Icons\\INV_Misc_Gear_01",
        kind = "taborder" },
    } },
    { key = "options:collection", name = L.COLLECTION, settings = {
      Setting("collect", L.COLLECT_MODE, L.COLLECT_MODE_TOOLTIP, "Interface\\Icons\\INV_Misc_Note_02",
        function() return DB.global.collect == true end,
        function(value)
          DB.global.collect = value
          Addon:GetModule("Collector"):SetEnabled(value)
          Window:OnCollectChanged() -- the Collected Data tab appears and disappears with it
        end),
      -- Off (the default): tames are recorded without a name. Turning it off also takes the name off those collected.
      -- Its example badge shows today's date and your character's name.
      Setting("send_name", L.SEND_NAME,
        function() return L.SEND_NAME_TOOLTIP:format(date("%Y-%m-%d"), Addon:PlayerName() or "?") end,
        "Interface\\Icons\\INV_Misc_Note_06",
        function() return DB.global.send_name == true end,
        function(value)
          DB.global.send_name = value
          if not value then Addon:GetModule("Collector"):RemoveNames() end
        end),
    } },
    { key = "options:sharing", name = L.DATA_SHARING, settings = {
      GlobalSetting("share_shard", L.SHARE_SHARD, L.SHARE_SHARD_TOOLTIP, "Interface\\Icons\\INV_Letter_15", true),
      GlobalSetting("share_zone", L.SHARE_ZONE, L.SHARE_ZONE_TOOLTIP, "Interface\\Icons\\INV_Letter_15", true),
      GlobalSetting("share_group", L.SHARE_GROUP, L.SHARE_GROUP_TOOLTIP, "Interface\\Icons\\INV_Letter_15", true),
      GlobalSetting("share_moderators", L.SHARE_MODERATORS, L.SHARE_MODERATORS_TOOLTIP, "Interface\\Icons\\INV_Letter_15", true),
      GlobalSetting("receive_shared", L.RECEIVE_DATA, L.RECEIVE_SHARED_TOOLTIP, "Interface\\Icons\\INV_Letter_15", false),
    } },
    -- Last, for development.
    { key = "options:advanced", name = L.ADVANCED, settings = {
      GlobalSetting("debug", L.DEBUG_MODE, L.DEBUG_MODE_TOOLTIP, "Interface\\Icons\\INV_Misc_Wrench_01", false),
    } },
  }
end

-- What a setting is now, as shown on its row and in its details: "On" (green), "Off" (grey), "100%".
local function StateText(setting)
  if setting.kind == "check" then
    local on = setting.get()
    return on and L.ON or L.OFF, Colors.State[on and "Available" or "Unavailable"]
  elseif setting.kind == "scale" then
    return ("%d%%"):format(math.floor(Window:SavedScale() * 100 + 0.5)), Colors.State.Default
  end
  return "", Colors.State.Default
end

-- ----------------------------------------------------------------------------
-- The list
-- ----------------------------------------------------------------------------

local function OptionOnClick(button)
  Window:SelectOption(button.ftSetting.key)
end

function Window:InitOptionButton(button, setting)
  button.Label:SetText(setting.label)
  button.Label:SetVertexColor(Colors.State.Default:GetRGB())
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  local text, color = StateText(setting)
  button.Count:ClearAllPoints()
  button.Count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
  button.Count:SetText(text)
  button.Count:SetTextColor(color:GetRGB())
  button.Count:SetShown(text ~= "")
  button.Label:SetWidth(button:GetWidth() - (text ~= "" and 60 or 20))

  local selected = self.selectedOption == setting.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)

  button.ftSetting = setting
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", OptionOnClick)
  button:SetScript("OnEnter", nil)
  button:SetScript("OnLeave", nil)
end

function Window:RefreshOptions()
  local search = self.search or ""
  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.optionByKey = {}
  self.sectionsSeen = self.sectionsSeen or {}
  local first
  for _, group in ipairs(Groups()) do
    local listed = {}
    for _, setting in ipairs(group.settings) do
      if search == "" or setting.label:lower():find(search, 1, true) or group.name:lower():find(search, 1, true) then
        setting.group = group.name
        listed[#listed + 1] = setting
      end
    end
    if #listed > 0 then
      self.listKeys[#self.listKeys + 1] = group.key
      -- A group starts open the first time it is listed.
      if not self.sectionsSeen[group.key] then
        self.sectionsSeen[group.key] = true
        self.expanded[group.key] = true
      end
      local category = provider:Insert({ categoryInfo = { name = group.name }, key = group.key })
      self:SetCollapsed(category, group.key)
      for _, setting in ipairs(listed) do
        category:Insert({ setting = setting })
        self.optionByKey[setting.key] = setting
        first = first or setting.key
      end
    end
  end
  if not (self.selectedOption and self.optionByKey[self.selectedOption]) then
    local saved = self:Sticky() and DB.global.selections.OPTIONS
    self.selectedOption = (saved and self.optionByKey[saved] and saved) or first
  end

  self.scrollBox:SetDataProvider(provider, true)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetText("")
  self:UpdateToggleButton()
  self:UpdateOptionDetails()
end

function Window:SelectOption(key)
  self.selectedOption = key
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local setting = node:GetData().setting
    if setting then
      button.SelectedOverlay:SetShown(setting.key == key)
      button.HighlightOverlay:SetShown(setting.key ~= key)
    end
  end)
  self:UpdateOptionDetails()
end

-- ----------------------------------------------------------------------------
-- The details
-- ----------------------------------------------------------------------------

-- The controls under a setting's description: a checkbox, the UI Scale slider, Tab Organization's reset button and
-- tab checkboxes. Made the
-- first time the tab is shown.
function Window:GetOptionControls()
  if self.optionControls then return self.optionControls end
  local controls = CreateFrame("Frame", nil, self.details)
  controls:SetSize(320, 40)

  local check = CreateFrame("CheckButton", nil, controls, "CheckboxWithLabelTemplate")
  check:SetPoint("TOPLEFT", -4, 0)
  check.Text:SetFontObject("GameFontHighlight")
  check.Text:SetText(L.ENABLED)
  check:SetScript("OnClick", function(this)
    local setting = self.optionByKey and self.optionByKey[self.selectedOption]
    if setting and setting.set then setting.set(this:GetChecked() and true or false) end
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    self:RefreshOptions() -- the row's On / Off
  end)
  controls.Check = check

  controls.Slider = self:CreateScaleSlider(controls, function() self:RefreshOptions() end)
  if controls.Slider then controls.Slider:SetPoint("TOPLEFT", 0, -4) end

  local reset = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
  reset:SetHeight(22)
  reset:SetPoint("TOPLEFT", 0, -2) -- (across the whole pane: the controls reach its right edge)
  reset:SetPoint("TOPRIGHT", 0, -2)
  reset:SetText(L.RESET_TAB_ORDER)
  reset:SetScript("OnClick", function() self:ResetTabOrder() end)
  controls.Reset = reset

  -- Tab Organization: a checkbox per side tab to show or hide it, in two columns under the reset button (Collected Data
  -- is not among them: Collect Mode shows it).
  local tabChecks = CreateFrame("Frame", nil, controls)
  tabChecks:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -14)
  tabChecks:SetPoint("TOPRIGHT", reset, "BOTTOMRIGHT", 0, -14)
  tabChecks:SetHeight(10)
  tabChecks.boxes = {}
  for i, info in ipairs(self:OrganizableTabs()) do
    local box = CreateFrame("CheckButton", nil, tabChecks, "CheckboxWithLabelTemplate")
    local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
    -- The first column at the left, the second from the middle of the pane on (room for the longest name).
    if column == 0 then
      box:SetPoint("TOPLEFT", tabChecks, "TOPLEFT", -4, -row * 26)
    else
      box:SetPoint("TOPLEFT", tabChecks, "TOP", 16, -row * 26)
    end
    box.Text:SetFontObject("GameFontHighlight")
    box.Text:SetText(("|T%s:16:16:0:0|t %s"):format(info.icon, info.label))
    box.key = info.key
    box:SetScript("OnClick", function(this)
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      if not self:SetTabShown(this.key, this:GetChecked() and true or false) then
        this:SetChecked(true) -- (the last tab showing stays)
      end
    end)
    tabChecks.boxes[#tabChecks.boxes + 1] = box
  end
  controls.TabChecks = tabChecks

  -- Debug Mode: a checkbox per area of debug messages (collector, share, ...), to silence the noisy ones. Under the
  -- Enabled checkbox, in two columns.
  local debugChecks = CreateFrame("Frame", nil, controls)
  debugChecks:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -12)
  debugChecks:SetPoint("RIGHT", controls, "RIGHT")
  debugChecks:SetHeight(10)
  local heading = debugChecks:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", 0, 0)
  heading:SetText(L.DEBUG_MESSAGES)
  debugChecks.boxes = {}
  for i, area in ipairs(Addon.DEBUG_AREAS) do
    local box = CreateFrame("CheckButton", nil, debugChecks, "CheckboxWithLabelTemplate")
    local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
    if column == 0 then
      box:SetPoint("TOPLEFT", debugChecks, "TOPLEFT", -4, -20 - row * 26)
    else
      box:SetPoint("TOPLEFT", debugChecks, "TOP", 16, -20 - row * 26)
    end
    box.Text:SetFontObject("GameFontHighlight")
    box.Text:SetText(L["DEBUG_AREA_" .. area:upper()] or area)
    box.area = area
    box:SetScript("OnClick", function(this)
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      DB.global.debug_on = DB.global.debug_on or {}
      DB.global.debug_on[this.area] = this:GetChecked() and true or nil
    end)
    debugChecks.boxes[#debugChecks.boxes + 1] = box
  end
  controls.DebugChecks = debugChecks

  self.optionControls = controls
  return controls
end

function Window:UpdateOptionDetails()
  local controls = self:GetOptionControls()
  local setting = self.optionByKey and self.optionByKey[self.selectedOption]
  if not setting then
    self.details:Hide()
    controls:Hide()
    return
  end
  self.details:Show()
  self.npcLabel:Hide()
  self.npcBox:Hide()
  self.npcBar:Hide()
  self.mapButton:Hide()
  self.miniMap:Hide()

  self.icon:SetTexture(setting.icon)
  self.name:SetText(setting.label)
  self.subtitle:SetText(setting.group or "")
  local text, color = StateText(setting)
  self.facts:SetText(text ~= "" and ("%s: %s"):format(Colors.Label(L.STATUS), color:WrapTextInColorCode(text)) or "")
  -- A description can be a function, worked out when it is shown (Send Name's example badge).
  local description = setting.description
  if type(description) == "function" then description = description() end
  self.description:SetText(description or "")
  self:PlaceDescription()

  controls:ClearAllPoints()
  controls:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -16)
  controls:SetPoint("RIGHT", self.details, "RIGHT", -20, 0) -- (the reset button and the tab checkboxes use the width)
  controls:Show()
  controls.Check:SetShown(setting.kind == "check")
  if setting.kind == "check" then controls.Check:SetChecked(setting.get() and true or false) end
  if controls.Slider then
    controls.Slider:SetShown(setting.kind == "scale")
    if setting.kind == "scale" then controls.Slider:SetValue(self:SavedScale()) end
  end
  controls.Reset:SetShown(setting.kind == "taborder")
  controls.TabChecks:SetShown(setting.kind == "taborder")
  controls.DebugChecks:SetShown(setting.key == "debug")
  if setting.key == "debug" then
    for _, box in ipairs(controls.DebugChecks.boxes) do
      box:SetChecked((DB.global.debug_on or {})[box.area] == true)
    end
  end
  if setting.kind == "taborder" then
    for _, box in ipairs(controls.TabChecks.boxes) do box:SetChecked(self:TabShown(box.key)) end
  end
end
