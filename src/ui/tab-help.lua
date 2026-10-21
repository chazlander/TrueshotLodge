local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The Help section, opened with the "?" button by the close button (no side tab): How to Claim (a bounty: how and what
-- you have on), how the filters work, and the slash commands; then Tab Descriptions, what each tab is for. In the same
-- list and details layout as the tabs.

local Line, PlayClick = Helpers.Line, Helpers.PlayClick
local QUESTION_MARK_ICON = Helpers.QUESTION_MARK_ICON

local ENTRIES = {
  { key = "claim", label = L.BOUNTY_HOW_TO_CLAIM, icon = function() return Window.BOUNTY_ICON end },
  { key = "filters", label = L.HELP_FILTERS, icon = function() return "Interface\\Icons\\INV_Misc_Spyglass_03" end },
  { key = "commands", label = L.HELP_COMMANDS, icon = function() return "Interface\\Icons\\INV_Misc_Note_01" end },
}

-- Tab Descriptions: one entry per tab (but Help itself), with the tab's icon and name, in the tabs' order.
local TAB_ENTRIES = {}
for _, tab in ipairs(Window.TABS) do
  if tab.key ~= "HELP" then
    TAB_ENTRIES[#TAB_ENTRIES + 1] = { key = "tab:" .. tab.key, label = tab.title, tab = tab,
      icon = function() return tab.icon end }
  end
end

local GROUPS = {
  { key = "help:main", name = L.HELP, rows = ENTRIES },
  { key = "help:tabs", name = L.HELP_TAB_DESCRIPTIONS, rows = TAB_ENTRIES },
}

local function HelpOnClick(button)
  PlayClick()
  Window:SelectHelp(button.ftHelp.key)
end

function Window:InitHelpButton(button, row)
  button.Label:SetText(("|T%s:16:16:0:0|t %s"):format(row.icon() or QUESTION_MARK_ICON, row.label))
  button.Label:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
  button.Label:SetWidth(button:GetWidth() - 20)
  button.SkillUps:Hide()
  button.LockedIcon:Hide()
  button.Count:Hide()
  local selected = self.selectedHelp == row.key
  button.SelectedOverlay:SetShown(selected)
  button.HighlightOverlay:SetShown(not selected)
  button.ftHelp = row
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", HelpOnClick)
  button:SetScript("OnEnter", nil)
  button:SetScript("OnLeave", nil)
end

function Window:RefreshHelp()
  local provider = CreateTreeDataProvider()
  self.listKeys = {}
  self.helpByKey = {}
  self.helpHeadersSeen = self.helpHeadersSeen or {}
  local search = self.search or ""
  for _, group in ipairs(GROUPS) do
    self.listKeys[#self.listKeys + 1] = group.key
    -- A heading starts open the first time it is shown; after that it stays as the player left it.
    if not self.helpHeadersSeen[group.key] then
      self.helpHeadersSeen[group.key] = true
      self.expanded[group.key] = true
    end
    local category = provider:Insert({ categoryInfo = { name = group.name }, key = group.key })
    self:SetCollapsed(category, group.key)
    for _, row in ipairs(group.rows) do
      if search == "" or row.label:lower():find(search, 1, true) then
        category:Insert({ help = row })
        self.helpByKey[row.key] = row
      end
    end
  end
  if not (self.selectedHelp and self.helpByKey[self.selectedHelp]) then
    local saved = self:Sticky() and DB.global.selections.HELP
    self.selectedHelp = (saved and self.helpByKey[saved]) and saved or (next(self.helpByKey) and ENTRIES[1].key)
  end
  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(next(self.helpByKey) == nil)
  self.headerCount:SetText(L.HELP_SUBTITLE)
  self:UpdateToggleButton()
  self:UpdateHelpDetails()
end

function Window:SelectHelp(key)
  self.selectedHelp = key
  self:Remember()
  self.scrollBox:ForEachFrame(function(button, node)
    local row = node:GetData().help
    if row then
      button.SelectedOverlay:SetShown(row.key == key)
      button.HighlightOverlay:SetShown(row.key ~= key)
    end
  end)
  self:UpdateHelpDetails()
end

function Window:UpdateHelpDetails()
  local row = self.selectedHelp and self.helpByKey and self.helpByKey[self.selectedHelp]
  if not row then
    self.details:Hide()
    return
  end
  self.details:Show()
  self.mapButton:Hide()
  self.miniMap:Hide()
  self.npcLabel:Hide()
  self.npcBox:Hide()
  self.npcBar:Hide()
  self:SetTopWide(false)
  self.icon:SetTexture(row.icon() or QUESTION_MARK_ICON)
  self.name:SetText(row.label)

  local lines, description = {}
  local function add(line) if line then lines[#lines + 1] = line end end
  if row.key == "claim" then
    -- What you have on, then how a bounty is claimed (moved here from the Bounties tab).
    self.subtitle:SetText(L.BOUNTIES_SITE)
    local sendName = DB.global.send_name == true
    add(Line(L.COLLECT_MODE, DB.global.collect and L.ON or L.OFF))
    add(Line(L.SEND_NAME, sendName and L.ON or L.OFF))
    add(Line(L.TAMED_CREATURES, #(DB.collected.tames or {})))
    description = L.BOUNTIES_TEXT .. "\n\n" .. L.BOUNTY_CLAIM_STEPS .. "\n\n"
      .. (sendName and L.BOUNTIES_NAME_ON:format(Addon:PlayerName() or "?") or Colors.Highlight(L.BOUNTIES_NAME_OFF))
  elseif row.tab then
    -- What the tab is for (each tab's own text).
    self.subtitle:SetText(L.HELP_TAB_DESCRIPTIONS)
    description = L["HELP_TAB_" .. row.tab.key] or ""
  elseif row.key == "filters" then
    self.subtitle:SetText(L.FILTERS)
    description = L.HELP_FILTERS_TEXT
  else
    self.subtitle:SetText("/tsl")
    description = L.HELP_COMMANDS_TEXT
  end
  self.facts:SetText(table.concat(lines, "\n"))
  self.description:SetText(description)
  self:PlaceDescription()
end
