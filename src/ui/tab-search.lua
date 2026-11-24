local ADDON_NAME, Addon = ...
local Colors = Addon:GetModule("Colors")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local PinHelper = Addon:GetModule("PinHelper")
local Window = Addon:GetModule("Window")

-- The Database Search tab (window.lua's TABS, key "SEARCHTOP" -- a leftover from when this file was
-- tab-search-top.lua, kept rather than renaming it everywhere it is checked): the filters across the top as
-- dropdowns, closer to TrueshotLodge.com/search's own layout. The matching and sorting rules live on their own
-- (search-filters.lua); this file is just this layout's widgets, built around its own filter state (ST). An earlier
-- layout with the filters as rows down the left shared this same file name before it was deleted; once this one won
-- out and the file was renamed, there was nothing left for that name to disambiguate from.

local ST = Window:NewSearchFilterState()

-- GAP is negative: UIDropDownMenuTemplate's visible border sits inset from the frame's own edges (room for an
-- optional icon before the text that none of these use), so chaining dropdowns at a 0 offset leaves that built-in
-- padding as a visible gap between boxes. This pulls them back together; nudge it a few more pixels either way if
-- the in-game gap isn't fully gone.
local GAP, ROW_GAP = -32, 4
local SEARCH_DELAY = 0.15 -- seconds of no typing before the free-text search box's results follow (window.lua's own)

-- Each filter dropdown's width: fixed rather than measured off its own text at creation time -- a FontString's
-- GetStringWidth() measured before anything has ever been drawn (as these are, on first login) was coming back
-- short of what the dropdown's own font needs, which is why "Type"/"Classification"/"Ability" were still clipping
-- to "Ty..." and the like even though each was supposedly sized to its own label. These are tighter than that first
-- fix: all seven filters have to fit across one row, so every one of them is sized to its real worst case and no
-- more (a short button label for Classification, and Diet/Taming/Zone showing just the chosen item once one is
-- picked, not "Diet: " or "Taming: " in front of it -- ChoiceSummary). Zone is the one exception: its names vary too
-- much to size for the worst case without starving every other dropdown, so its longest entries still clip.
local FAMILY_DROPDOWN_WIDTH = 90 -- "Family (18)": by far the most items of any of them
-- local TYPE_DROPDOWN_WIDTH = 65 -- (commented out with the Type dropdown below; uncomment both together)
local CLASS_DROPDOWN_WIDTH = 65 -- "Class (5)": only 5 classifications exist (SEARCH_CLASS_ITEMS)
local DIET_DROPDOWN_WIDTH = 75 -- the longest food name alone, once one is picked
local TAMING_DROPDOWN_WIDTH = 78 -- "Untamed", "Sighted", etc. alone, once one is picked
local ABILITY_DROPDOWN_WIDTH = 85
local ZONE_DROPDOWN_WIDTH = 100 -- zone names vary a lot more than the others; the longest ones still clip, and that's fine

-- The Map/Status button: one fixed width for all of "Map", L.NO_COORDINATES ("No Coord"), the "?" (Unknown Zone)
-- and L.SEARCH_TOP_INSTANCE ("Instance") overrides below, rather than Window:SetMapButton's own per-text sizing
-- (sized to its word, which made the column jump around row to row).
local MAP_BUTTON_WIDTH = 70

-- The results table's columns: Creature takes what is left, Family/Unique/Common (icons alone, no names -- the icon
-- is the family or the ability; Common has room for two, a creature's rarer second one included) /Level/Atk (attack
-- speed) are fixed-width columns, Zone takes what is left between them and Status (the Map button, which hugs the
-- row's right edge regardless of the window's width). The same x-offsets place the column headers
-- (Window:CreateSearchTopList).
local ROW_HEIGHT = 20
local FAVORITE_X = 2 -- the favorite star, at the far left of the row (and of the "Creature" header above it)
local NAME_X = 22
local FAMILY_X = 200
local UNIQUE_X = 240 -- the family's own exclusive ability, if this creature teaches a rank of it
local COMMON_X = 294 -- one or two of the abilities every family can learn (Bite, Claw, ...), if this creature teaches a rank;
-- wider than a 38px-even split would give Common: Unique's column needs the room to fit "Unique" in full, not "Uniq"
local LEVEL_X, LEVEL_WIDTH = 358, 34
local SPEED_X, SPEED_WIDTH = 400, 32
local ZONE_X = 442
local COMMON_ICON_GAP = 4 -- between the Common column's two icon slots

-- Faint vertical lines between columns (Window:CreateSearchTopList's divider frame), each a few pixels before its
-- column starts, the same "-4" gap the sortable headers already size themselves to.
local DIVIDER_X = { FAMILY_X - 4, UNIQUE_X - 4, COMMON_X - 4, LEVEL_X - 4, SPEED_X - 4, ZONE_X - 4 }

-- Dropdown menus are one of the few WoW widgets that still need a real global name (their internals build their
-- sub-widgets' names from it), so each gets one of its own instead of the usual anonymous CreateFrame.
local function DropdownName(suffix) return ADDON_NAME .. "SearchTop" .. suffix end

-- A dropdown's button text: the base label alone when nothing is chosen, a count when more than one thing can be
-- chosen at once (Family, Type, Classification, Ability), or the chosen item's own label when only one can be
-- (Taming, Diet).
local function MultiSummary(baseLabel, set)
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  if count == 0 then return baseLabel end
  return ("%s (%d)"):format(baseLabel, count)
end

-- Just the chosen item's own label once one is picked (its column position already says which filter it is), not
-- "Diet: Meat"/"Taming: Untamed" -- there isn't room across one row for the label and the choice both.
local function ChoiceSummary(baseLabel, items, value)
  if value ~= "" then
    for _, item in ipairs(items) do
      if item.key == value then return item.label end
    end
  end
  return baseLabel
end

-- A dropdown where any number of items can be checked on at once (Family, Type, Classification, Ability): `set` is
-- the filter state's own table, so toggling an item here is the same thing tab-search.lua's matching rows toggle.
local function NewMultiDropdown(parent, name, baseLabel, items, set, onChange, width)
  local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dropdown, width)
  UIDropDownMenu_Initialize(dropdown, function(_, level)
    for _, item in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.arg1 = item.label, item.key
      info.isNotRadio, info.keepShownOnClick = true, true
      info.checked = set[item.key] == true
      info.func = function(_, key, _, checked)
        set[key] = checked or nil
        UIDropDownMenu_SetText(dropdown, MultiSummary(baseLabel, set))
        onChange()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetText(dropdown, MultiSummary(baseLabel, set))
  dropdown.ftRefresh = function() UIDropDownMenu_SetText(dropdown, MultiSummary(baseLabel, set)) end
  return dropdown
end

-- A dropdown where only one item is chosen at a time (Taming, Diet): `getValue`/`setValue` read and write the
-- filter state's own field.
local function NewChoiceDropdown(parent, name, baseLabel, items, getValue, setValue, onChange, width)
  local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dropdown, width)
  UIDropDownMenu_Initialize(dropdown, function(_, level)
    for _, item in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.arg1 = item.label, item.key
      info.checked = getValue() == item.key
      info.func = function(_, key)
        setValue(key)
        UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, key))
        onChange()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, getValue()))
  dropdown.ftRefresh = function() UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, getValue())) end
  return dropdown
end

-- EditBox:SetText fires OnTextChanged even when the text does not change (as tab-search.lua's Level boxes).
local function SyncText(box, value)
  if box:GetText() ~= value then box:SetText(value) end
end

-- A plain icon button that toggles a boolean filter directly (Forever, Favorites): no checkbox or label, since the
-- icon itself already says what it is -- full color when on, dimmed when off. `draw(icon, on)` sets the icon's own
-- look for each state: Forever's infinity glyph just needs an alpha change, Favorites reuses the exact star every
-- creature row uses (Helpers.SetFavoriteIcon), which already swaps atlases rather than fading.
local function NewFilterIconButton(parent, draw, tooltipText, getOn, toggle)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(20, 20)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  button.icon = icon
  local function Redraw() draw(icon, getOn()) end
  button.ftRefresh = Redraw
  button:SetScript("OnClick", function()
    toggle()
    Redraw()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltipText, 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  Redraw()
  return button
end

-- Every zone a tameable creature is in, each with the zones.id behind it (not just its name, npc.zone_names:
-- resolved here instead, off npc.zones, since zone_names drops the id once it is resolved to a name). Built once:
-- only this tab has a Zone dropdown, so it is not in search-filters.lua's shared option lists. Forces every
-- creature to be prepared first (Addon:GetNPC), since zones is read off the raw data directly.
local ZONE_ITEMS
function Window:SearchZoneItems()
  if ZONE_ITEMS then return ZONE_ITEMS end
  local seen = {} -- name -> zones.id
  for id in pairs(Addon.TameableNPCs or {}) do
    local npc = Addon:GetNPC(id)
    for _, zoneId in ipairs(npc and npc.zones or {}) do
      local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zoneId)
      if name then seen[name] = zoneId end
    end
  end
  ZONE_ITEMS = {}
  for name, zoneId in pairs(seen) do ZONE_ITEMS[#ZONE_ITEMS + 1] = { key = name, label = name, zoneId = zoneId } end
  ZONE_ITEMS[#ZONE_ITEMS + 1] = { key = "", label = L.SEARCH_ANY } -- (listed last; shown first by the sort below)
  table.sort(ZONE_ITEMS, function(a, b)
    if a.key == "" or b.key == "" then return a.key == "" end
    return a.label < b.label
  end)
  return ZONE_ITEMS
end

-- Which of the Zone dropdown's submenus a zone belongs to: the name of its own continent, found by walking C_Map's
-- own parent chain at runtime to the map whose own parent is the root (nil, or Cosmic/World-type: the "Azeroth" map
-- that sits above Eastern Kingdoms and Kalimdor both) -- not a hand-kept zone list, and not just Eastern Kingdoms
-- and Kalimdor by name: a zone on a continent of its own (Zephras Isle, a Forever one) gets its own submenu the same
-- way, with nothing to add here when one more shows up. Checking the PARENT's type, not asking whether the zone's
-- own map is itself Continent-type, is what makes that work for a custom top-level map like Zephras Isle's, which
-- has no parent to climb to but was never actually tagged Continent either. A zone with no ui_map_id at all is a
-- dungeon in every case this data has (every open-world zone with a tameable creature has one, confirmed with
-- compare_db.py, 2026-11), so that -- and a chain that runs out of parents to check, which should not happen on
-- this data -- fall back to Instances.
local ZONE_GROUP_CACHE = {}
local function ZoneGroup(zoneId)
  local cached = zoneId and ZONE_GROUP_CACHE[zoneId]
  if cached then return cached end
  local group = L.SEARCH_ZONE_INSTANCES
  local mapId = zoneId and Addon.TameableZoneUiMaps and Addon.TameableZoneUiMaps[zoneId]
  local guard = 0
  while mapId and guard < 8 do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    if not info then break end
    local parentInfo = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
    if not parentInfo or parentInfo.mapType == Enum.UIMapType.Cosmic or parentInfo.mapType == Enum.UIMapType.World then
      group = info.name
      break
    end
    mapId = info.parentMapID
    guard = guard + 1
  end
  if zoneId then ZONE_GROUP_CACHE[zoneId] = group end
  return group
end

-- The Zone dropdown's items (Window:SearchZoneItems), sorted into their submenus (by continent, plus Instances);
-- "Any" is returned on its own, since it sits at the top level rather than inside one of them. `order` lists the
-- submenus actually in use, alphabetically except Instances last (it is not a continent, so it reads as the odd one
-- out grouped with the rest rather than sorted in among them).
local function ZoneGroups(items)
  local any, byGroup, order = nil, {}, {}
  for _, item in ipairs(items) do
    if item.key == "" then
      any = item
    else
      local groupName = ZoneGroup(item.zoneId)
      local group = byGroup[groupName]
      if not group then
        group = {}
        byGroup[groupName] = group
        order[#order + 1] = groupName
      end
      group[#group + 1] = item
    end
  end
  table.sort(order, function(a, b)
    if a == L.SEARCH_ZONE_INSTANCES or b == L.SEARCH_ZONE_INSTANCES then return b == L.SEARCH_ZONE_INSTANCES end
    return a < b
  end)
  return any, byGroup, order
end

-- The Zone dropdown: each continent (and Instances) as its own submenu, "Any" alone at the top level, built with
-- classic UIDropDownMenuTemplate's own multi-level support (hasArrow + menuList open a second UIDropDownMenu_AddButton
-- pass at level 2, the same way Blizzard's own nested menus work -- no extra wiring needed beyond that). Unlike
-- NewChoiceDropdown, items is read once at creation (Window:SearchZoneItems() is already cached) rather than passed
-- in, since it needs grouping first.
local function NewZoneDropdown(parent, name, baseLabel, getValue, setValue, onChange, width)
  local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dropdown, width)
  local items = Window:SearchZoneItems()
  local anyItem, groups, order = ZoneGroups(items)

  local function Choose(key)
    setValue(key)
    UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, key))
    CloseDropDownMenus()
    onChange()
  end
  local function AddChoice(item, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.arg1 = item.label, item.key
    info.checked = getValue() == item.key
    info.func = function(_, key) Choose(key) end
    UIDropDownMenu_AddButton(info, level)
  end

  UIDropDownMenu_Initialize(dropdown, function(_, level, menuList)
    level = level or 1
    if level == 1 then
      AddChoice(anyItem, level)
      for _, groupName in ipairs(order) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.hasArrow, info.menuList = groupName, true, true, groupName
        UIDropDownMenu_AddButton(info, level)
      end
    else
      for _, item in ipairs(groups[menuList] or {}) do AddChoice(item, level) end
    end
  end)
  UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, getValue()))
  dropdown.ftRefresh = function() UIDropDownMenu_SetText(dropdown, ChoiceSummary(baseLabel, items, getValue())) end
  return dropdown
end

function Window:RefreshSearchTop()
  self.searchResults = self:GetSearchResults(ST)
  local count = #self.searchResults
  local text = count > 0 and L.SEARCH_RESULTS:format(count) or L.SEARCH_NONE
  local zone = self:ZoneFilter()
  if zone and count > 0 then text = ("%s  %s"):format(text, Colors.Muted(zone.name)) end
  self.headerCount:SetText(text)
  self:UpdateSearchTopDetails()
end

-- Turning the header's Level Filter button on also sets the Level row's own Max box to your character level
-- (Window:CreateFilterButtons): the generic filter (DB.global.filter_by_level, a plain "<= your level" check) still
-- applies regardless, but this tab's own range box is made to agree with it rather than silently go on showing 60.
function Window:SearchTopUseCharacterLevel()
  local level = Addon:Plain(UnitLevel("player"))
  if not level or level <= 0 then return end
  ST.levelMax = tostring(level)
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- Turning the header's Zone Filter button on also picks your current zone in this tab's own Zone dropdown, the same
-- way (self:PlayerZone, zone-filter.lua): the generic filter still applies regardless of whether the dropdown's own
-- list happens to carry that exact name.
function Window:SearchTopUseCurrentZone()
  local zone = self:PlayerZone()
  if not zone then return end
  ST.zone = zone.name
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- Turning the header's Favorites button on also ticks this tab's own Favorites icon (Window:CreateFilterButtons):
-- the generic filter (DB.global.filter_favorites) still applies regardless, but the tab's own icon is made to agree
-- with it rather than silently stay unlit.
function Window:SearchTopUseFavorites()
  ST.favorites = true
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- Turning the header's Level Filter button back off resets the Max box to 60 (every level), undoing
-- SearchTopUseCharacterLevel: left at your level with the button now off, it would look like a leftover with
-- nothing left to explain it.
function Window:SearchTopResetLevel()
  ST.levelMax = "60"
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- Turning the header's Zone Filter button back off resets the Zone dropdown to Any, undoing SearchTopUseCurrentZone.
function Window:SearchTopResetZone()
  ST.zone = ""
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- Turning the header's Favorites button back off unticks the tab's own Favorites icon too, undoing
-- SearchTopUseFavorites.
function Window:SearchTopResetFavorites()
  ST.favorites = false
  self:SyncSearchTopControls()
  self:RefreshSearchTop()
end

-- The dropdown bar: built once; Window:UpdateSearchTopBar places and fills it,
-- above the search box's usual place, only while this tab shows. Row 1 is every filter dropdown (Family, Type,
-- Classification, Diet, Taming, Ability, Zone); row 2 is the Level range, Forever, Clear Filters and the free-text
-- search -- sorting lives in the column headers below (Window:SetSearchTopSort), not a dropdown here.
function Window:CreateSearchTopBar(frame)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetSize(640, 54) -- (a real size: a frame with only points and no size can end up 0 wide, as the Level row was)
  bar:Hide()
  self.searchTopBar = bar

  local familyItems, _, foodItems = self:SearchFilterOptionLists()

  local function Changed() self:RefreshSearchTop() end

  -- Row 1: every filter, each its own dropdown, every one of them trimmed to its real worst case (see the widths
  -- above) so all six fit across one row.
  local family = NewMultiDropdown(bar, DropdownName("Family"), L.SEARCH_FAMILY, familyItems, ST.family, Changed,
    FAMILY_DROPDOWN_WIDTH)
  family:SetPoint("TOPLEFT", bar, "TOPLEFT", -16, 0)
  bar.FamilyDropdown = family

  -- Type (Ferocity/Tenacity/Cunning) is commented out for now, not deleted: ST.type and TypeOk (search-filters.lua)
  -- are untouched, so re-enabling this is just uncommenting it (and the "_" above, and TYPE_DROPDOWN_WIDTH) and
  -- re-chaining Class off it again.
  -- local typeDrop = NewMultiDropdown(bar, DropdownName("Type"), L.SEARCH_TYPE, typeItems, ST.type, Changed,
  --   TYPE_DROPDOWN_WIDTH)
  -- typeDrop:SetPoint("LEFT", family, "RIGHT", GAP, 0)
  -- bar.TypeDropdown = typeDrop

  local class = NewMultiDropdown(bar, DropdownName("Class"), L.SEARCH_TOP_CLASS, Window.SEARCH_CLASS_ITEMS,
    ST.class, Changed, CLASS_DROPDOWN_WIDTH)
  class:SetPoint("LEFT", family, "RIGHT", GAP, 0)
  bar.ClassDropdown = class

  local diet = NewChoiceDropdown(bar, DropdownName("Diet"), L.SEARCH_DIET, foodItems, function() return ST.food end,
    function(v) ST.food = v end, Changed, DIET_DROPDOWN_WIDTH)
  diet:SetPoint("LEFT", class, "RIGHT", GAP, 0)
  bar.DietDropdown = diet

  local taming = NewChoiceDropdown(bar, DropdownName("Tame"), L.SEARCH_TAMING, Window.SEARCH_TAMING_ITEMS,
    function() return ST.taming end, function(v) ST.taming = v end, Changed, TAMING_DROPDOWN_WIDTH)
  taming:SetPoint("LEFT", diet, "RIGHT", GAP, 0)
  bar.TamingDropdown = taming

  local ability = NewMultiDropdown(bar, DropdownName("Ability"), L.SEARCH_ABILITY, self:SearchAbilityItems(),
    ST.ability, Changed, ABILITY_DROPDOWN_WIDTH)
  ability:SetPoint("LEFT", taming, "RIGHT", GAP, 0)
  bar.AbilityDropdown = ability

  local zone = NewZoneDropdown(bar, DropdownName("Zone"), L.SEARCH_ZONE,
    function() return ST.zone end, function(v) ST.zone = v end, Changed, ZONE_DROPDOWN_WIDTH)
  zone:SetPoint("LEFT", ability, "RIGHT", GAP, 0)
  bar.ZoneDropdown = zone

  -- Row 2: the Level boxes, Forever, and Clear Filters, chained off each other so none can ever land on top of
  -- another.
  local levelLabel = Helpers.NewText(bar, "GameFontNormal")
  levelLabel:SetText(L.SEARCH_TOP_COL_LEVEL)
  levelLabel:SetPoint("TOPLEFT", family, "BOTTOMLEFT", 16, -ROW_GAP)

  local minBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
  minBox:SetSize(28, 20)
  minBox:SetAutoFocus(false)
  minBox:SetNumeric(true)
  minBox:SetPoint("LEFT", levelLabel, "RIGHT", 6, 0)

  local dash = Helpers.NewText(bar, "GameFontNormal")
  dash:SetText("-")
  dash:SetPoint("LEFT", minBox, "RIGHT", 3, 0)

  local maxBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
  maxBox:SetSize(28, 20)
  maxBox:SetAutoFocus(false)
  maxBox:SetNumeric(true)
  maxBox:SetPoint("LEFT", dash, "RIGHT", 6, 0)

  local pending
  local function ApplyLevel()
    ST.levelMin = minBox:GetText() ~= "" and minBox:GetText() or "0"
    ST.levelMax = maxBox:GetText() ~= "" and maxBox:GetText() or "60"
    if pending then pending:Cancel() end
    if C_Timer and C_Timer.NewTimer then
      pending = C_Timer.NewTimer(0.2, function() pending = nil Changed() end)
    else
      Changed()
    end
  end
  minBox:SetScript("OnTextChanged", ApplyLevel)
  maxBox:SetScript("OnTextChanged", ApplyLevel)
  minBox:SetScript("OnEnterPressed", minBox.ClearFocus)
  maxBox:SetScript("OnEnterPressed", maxBox.ClearFocus)
  bar.MinBox, bar.MaxBox = minBox, maxBox

  local forever = NewFilterIconButton(bar,
    function(icon, on)
      icon:SetTexture(Addon.FOREVER_ICON)
      icon:SetAlpha(on and 1 or 0.35)
    end, L.SEARCH_FOREVER, function() return ST.forever end,
    function() ST.forever = not ST.forever Changed() end)
  forever:SetPoint("LEFT", maxBox, "RIGHT", 10, 0)
  bar.ForeverCheck = forever

  local favorites = NewFilterIconButton(bar,
    function(icon, on) Helpers.SetFavoriteIcon(icon, on) end, L.SEARCH_FAVORITES, function() return ST.favorites end,
    function() ST.favorites = not ST.favorites Changed() end)
  favorites:SetSize(18, 18) -- a hair smaller than Forever: the star reads busier at the same size
  favorites:SetPoint("LEFT", forever, "RIGHT", 10, 0)
  bar.FavoritesCheck = favorites

  local clear = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
  clear:SetSize(60, 22)
  clear:SetText(L.SEARCH_TOP_CLEAR)
  -- Placed in Window:UpdateSearchTopBar, not here: its right edge matches the row list's own (searchTopBox), which
  -- does not exist yet this early (CreateSearchTopList runs after this function).
  clear:SetScript("OnClick", function()
    Window:ResetSearchFilters(ST)
    Window.search = ""
    if Window.searchBox then Window.searchBox:SetText("") end
    if bar.SearchBox then bar.SearchBox:SetText("") end
    Window:SyncSearchTopControls()
    Changed()
  end)
  bar.ClearButton = clear

  -- A free-text search of its own: the shared sidebar's search box (Window.searchBox) is hidden while this tab is
  -- shown (window.lua's fullWidth), so this tab needs its own. It writes the same Window.search the sidebar's box
  -- does (Window:CreatureSearch, SearchNPCShown), so the two never disagree about what matched last. Placed in
  -- Window:UpdateSearchTopBar (both edges), alongside Clear: same reasoning as Clear's own comment above.
  local search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:SetHeight(20)
  local pendingSearch
  search:HookScript("OnTextChanged", function(box)
    local text = (box:GetText() or ""):lower()
    if pendingSearch then pendingSearch:Cancel() pendingSearch = nil end
    local function apply()
      Window.search = text
      if Window.searchBox and Window.searchBox ~= box then SyncText(Window.searchBox, box:GetText()) end
      Changed()
    end
    if text == "" or not (C_Timer and C_Timer.NewTimer) then
      apply()
      return
    end
    pendingSearch = C_Timer.NewTimer(SEARCH_DELAY, apply)
  end)
  bar.SearchBox = search

  return bar
end

-- Syncs every control's own display to the filter state: needed after Clear Filters, since otherwise each dropdown
-- or box only updates itself when its own value changes.
function Window:SyncSearchTopControls()
  local bar = self.searchTopBar
  if not bar then return end
  -- (TypeDropdown is commented out above along with the Type dropdown itself)
  for _, dropdown in ipairs({ bar.FamilyDropdown, bar.ClassDropdown, bar.DietDropdown,
    bar.TamingDropdown, bar.AbilityDropdown, bar.ZoneDropdown }) do
    if dropdown.ftRefresh then dropdown.ftRefresh() end
  end
  self:UpdateSearchTopHeaderSort()
  bar.ForeverCheck.ftRefresh()
  bar.FavoritesCheck.ftRefresh()
  SyncText(bar.MinBox, ST.levelMin)
  SyncText(bar.MaxBox, ST.levelMax)
  SyncText(bar.SearchBox, self.search or "")
end

-- Clicking a column header sorts by it (ascending); clicking the same one again reverses it. Replaces the Sort
-- dropdown and its direction button from the first version of this layout.
function Window:SetSearchTopSort(field)
  if ST.sort == field then
    ST.dir = ST.dir == "desc" and "asc" or "desc"
  else
    ST.sort, ST.dir = field, "asc"
  end
  self:UpdateSearchTopHeaderSort()
  self:RefreshSearchTop()
end

-- The sorted-by column's header shows which way (an arrow after its label); every other header shows its label
-- alone.
function Window:UpdateSearchTopHeaderSort()
  local header = self.searchTopHeader
  if not (header and header.buttons) then return end
  -- Plain ASCII, not a Unicode triangle: the game's default fonts don't all carry that glyph (it showed as a tofu
  -- box), and a caret renders everywhere.
  local arrow = ST.dir == "desc" and " v" or " ^"
  for field, button in pairs(header.buttons) do
    button:SetText(field == ST.sort and (button.label .. arrow) or button.label)
  end
end

-- The two fonts a sortable column header's text uses (its own colors, not a plain button's): tan normally, gold
-- under the pointer or while it is the sort -- as Helpers.NewOutlineButton's Map buttons, but text alone, no box.
local headerFonts
local function HeaderFonts()
  if headerFonts then return headerFonts end
  headerFonts = {}
  for state, color in pairs({ Normal = Colors.Tan, Highlight = Colors.Gold }) do
    local font = CreateFont("TrueshotLodgeSearchTopHeader" .. state .. "Font")
    font:CopyFontObject(GameFontNormalSmall)
    font:SetTextColor(color:GetRGB())
    headerFonts[state] = font
  end
  return headerFonts
end

-- A smaller copy of Helpers.NewOutlineButton's own fonts, for the Map/Status button's "Instance" label alone: it is
-- the longest word that button shows here, and the button is now one fixed width (MAP_BUTTON_WIDTH) for all of its
-- texts rather than sized to each one's own, so shrinking the word is the only room left to make it sit comfortably.
local smallMapFonts
local function SmallMapFonts()
  if smallMapFonts then return smallMapFonts end
  smallMapFonts = {}
  for state, color in pairs({ Normal = Colors.Tan, Highlight = Colors.Gold, Disable = Colors.Disabled }) do
    local font = CreateFont("TrueshotLodgeSearchTopInstance" .. state .. "Font")
    font:CopyFontObject(GameFontNormalSmall)
    local path, _, flags = font:GetFont()
    font:SetFont(path, 9, flags)
    font:SetTextColor(color:GetRGB())
    smallMapFonts[state] = font
  end
  return smallMapFonts
end

-- The results: a compact, single-line-per-row table (Creature, Family, Level, Attack Speed, Zone, Status) with
-- sortable column headers, under the bar, in place of the two-line rows every other tab's creature list uses
-- (Window:InitNPCRow) -- there is more room for filters up top here, so the list earns its keep back by showing
-- more rows at once.
function Window:CreateSearchTopList(frame)
  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(14)
  header:Hide()
  header.buttons = {}
  self.searchTopHeader = header

  local fonts = HeaderFonts()
  -- `center`: Family's label, like Unique's and Common's below, is centered over its column to match its icon
  -- (already centered there, InitSearchTopRow) instead of hugging the column's left edge the way a word with room
  -- to grow (Creature, Level, Atk, Zone) does.
  local function SortHeader(x, width, text, field, center)
    local button = CreateFrame("Button", nil, header)
    button:SetPoint("TOPLEFT", header, "TOPLEFT", x, 0)
    button:SetSize(width, 14)
    local fontString = button:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint(center and "TOP" or "TOPLEFT")
    fontString:SetJustifyH(center and "CENTER" or "LEFT")
    button:SetFontString(fontString)
    button:SetNormalFontObject(fonts.Normal)
    button:SetHighlightFontObject(fonts.Highlight)
    button.label = text
    button:SetText(text)
    button:SetScript("OnClick", function() self:SetSearchTopSort(field) end)
    header.buttons[field] = button
    return button
  end
  SortHeader(NAME_X, FAMILY_X - NAME_X - 4, L.SEARCH_TOP_COL_NAME, "name")
  SortHeader(FAMILY_X, UNIQUE_X - FAMILY_X - 4, L.SEARCH_TOP_COL_FAMILY, "family", true)

  -- Not sortable, like Status: an icon alone (whether a creature teaches an ability and which rank) isn't an order
  -- to sort by. Centered over the column, like the icon below it.
  local uniqueHeader = Helpers.NewText(header, "GameFontNormalSmall", "CENTER")
  uniqueHeader:SetPoint("TOP", header, "TOPLEFT", UNIQUE_X + (COMMON_X - UNIQUE_X) / 2, 0)
  uniqueHeader:SetText(Colors.Tan(L.SEARCH_TOP_COL_UNIQUE))
  local commonHeader = Helpers.NewText(header, "GameFontNormalSmall", "CENTER")
  commonHeader:SetPoint("TOP", header, "TOPLEFT", COMMON_X + (LEVEL_X - COMMON_X) / 2, 0)
  commonHeader:SetText(Colors.Tan(L.SEARCH_TOP_COL_COMMON))

  SortHeader(LEVEL_X, SPEED_X - LEVEL_X - 4, L.SEARCH_TOP_COL_LEVEL, "level")
  SortHeader(SPEED_X, ZONE_X - SPEED_X - 4, L.SEARCH_TOP_COL_SPEED, "speed")
  SortHeader(ZONE_X, 150, L.SEARCH_TOP_COL_ZONE, "zone")

  local status = Helpers.NewText(header, "GameFontNormalSmall", "RIGHT")
  status:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, 0)
  status:SetText(Colors.Tan(L.SEARCH_TOP_COL_STATUS))

  local rule = header:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 0, -2)
  rule:SetPoint("BOTTOMRIGHT", 0, -2)
  rule:SetColorTexture(Colors.Metal:GetRGBA(0.6))

  local box = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  box:Hide()
  local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  bar:Hide()
  local view = CreateScrollBoxListLinearView(1, 1, 0, 0, 1)
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Frame", function(row, npc) self:InitSearchTopRow(row, npc) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  self.searchTopBox, self.searchTopScrollBar = box, bar

  -- The column dividers: one thin, faint line per boundary (DIVIDER_X), spanning the header and every row below it
  -- (Window:UpdateSearchTopBar places this frame to match). Only vertical scrolling happens here, so a column's x
  -- never moves: these can be fixed lines instead of something redrawn per row.
  local dividers = CreateFrame("Frame", nil, frame)
  dividers:Hide()
  for _, x in ipairs(DIVIDER_X) do
    local line = dividers:CreateTexture(nil, "ARTWORK")
    line:SetWidth(1)
    line:SetPoint("TOP", dividers, "TOPLEFT", x, 0)
    line:SetPoint("BOTTOM", dividers, "BOTTOMLEFT", x, 0)
    line:SetColorTexture(Colors.Metal:GetRGBA(0.35))
  end
  self.searchTopDividers = dividers
end

-- The first `max` abilities (in npc.taught's own name/rank order) on a given ability tab ("UNIQUE" or "COMMON") this
-- creature teaches, as up to `max` return values (nil where there is no such entry). Unique only ever has one
-- column to fill, so it asks for 1; Common has room for two icons, so a creature teaching a second common ability
-- (rare, but it happens) still gets to show it instead of being dropped silently.
local function TaughtOfTab(npc, tab, max)
  local found = {}
  for _, entry in ipairs(npc.taught or {}) do
    if Addon:GetAbilityTab(entry.ability) == tab then
      found[#found + 1] = entry
      if #found >= (max or 1) then break end
    end
  end
  return found[1], found[2]
end

-- Fills one ability icon column: the ability's own icon, with the rank taught as a small number over its corner (as
-- an action button's stack count) -- hidden when the creature teaches none on that tab. There is no room across one
-- row for the ability's name too; the row's own tooltip (PinHelper:AddTooltipLines, via Addon:TaughtLines) already
-- lists every ability this creature teaches in full. The number's color is the rank's own state (Window:RankState,
-- the same yellow/green/grey as the Abilities tab): known, available at your level, or not yet.
local function SetAbilityIcon(icon, rankText, entry)
  if not entry then
    icon:Hide()
    rankText:Hide()
    return
  end
  icon:SetTexture(entry.ability.icon)
  local rank = entry.ability.ranks[entry.rankIndex]
  rankText:SetText(rank.rank or entry.rankIndex)
  rankText:SetTextColor(Colors.State[Window:RankState(entry.ability, entry.rankIndex)]:GetRGB())
  icon:Show()
  rankText:Show()
end

-- A results row: a single line (name with its marks, family, unique/common ability, level, attack speed, zone, and
-- the Map button), unlike the shared, two-line InitNPCRow every other tab uses -- this tab trades the family/rare
-- glow styling for density and column headers.
function Window:InitSearchTopRow(row, npc)
  if not row.ftBuilt then
    row.ftBuilt = true
    -- The favorite star, at the far left of the row (FAVORITE_X): button.npcId is read by its own OnClick below, set
    -- each time the row is filled (Helpers.UpdateFavoriteButton) the same way row.MapButton reads button.npc.
    row.FavoriteButton = Helpers.NewFavoriteButton(row)
    row.FavoriteButton:SetPoint("LEFT", row, "LEFT", FAVORITE_X, 0)
    row.FavoriteButton:SetScript("OnClick", function(button)
      Helpers.PlayClick()
      Addon:ToggleFavorite(button.npcId)
      Helpers.UpdateFavoriteButton(button, button.npcId)
      self:RefreshSearchTop()
    end)
    -- Small, not the plain GameFontHighlight every other tab's name uses: on this tab's single dense line, next to
    -- the Level/Speed/Zone columns' GameFontDisableSmall, the larger size read as a mismatch rather than emphasis.
    -- Staying white (not grey) keeps the name the one thing that still stands out.
    row.NameText = Helpers.NewText(row, "GameFontHighlightSmall")
    row.NameText:SetWordWrap(false)
    -- The family column is the icon alone (no name): the row's own tooltip (PinHelper:AddTooltipLines) already
    -- names the family on hover, and the icon is what the website's own search results lead with.
    row.FamilyIcon = row:CreateTexture(nil, "ARTWORK")
    row.FamilyIcon:SetSize(16, 16)
    row.FamilyIcon:SetPoint("LEFT", row, "LEFT", FAMILY_X + (UNIQUE_X - FAMILY_X - 16) / 2, 0)
    row.UniqueIcon = row:CreateTexture(nil, "ARTWORK")
    row.UniqueIcon:SetSize(16, 16)
    row.UniqueIcon:SetPoint("LEFT", row, "LEFT", UNIQUE_X + (COMMON_X - UNIQUE_X - 16) / 2, 0)
    row.UniqueRank = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.UniqueRank:SetPoint("BOTTOMRIGHT", row.UniqueIcon, "BOTTOMRIGHT", 2, -2)
    -- Two slots, centered as a pair in the column: most creatures only fill the first, but a creature teaching a
    -- second common ability (rare, but it happens) isn't dropped for lack of room.
    local commonPairWidth = 16 * 2 + COMMON_ICON_GAP
    local commonStart = COMMON_X + (LEVEL_X - COMMON_X - commonPairWidth) / 2
    row.CommonIcon = row:CreateTexture(nil, "ARTWORK")
    row.CommonIcon:SetSize(16, 16)
    row.CommonIcon:SetPoint("LEFT", row, "LEFT", commonStart, 0)
    row.CommonRank = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.CommonRank:SetPoint("BOTTOMRIGHT", row.CommonIcon, "BOTTOMRIGHT", 2, -2)
    row.CommonIcon2 = row:CreateTexture(nil, "ARTWORK")
    row.CommonIcon2:SetSize(16, 16)
    row.CommonIcon2:SetPoint("LEFT", row, "LEFT", commonStart + 16 + COMMON_ICON_GAP, 0)
    row.CommonRank2 = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.CommonRank2:SetPoint("BOTTOMRIGHT", row.CommonIcon2, "BOTTOMRIGHT", 2, -2)
    row.LevelText = Helpers.NewText(row, "GameFontDisableSmall")
    row.LevelText:SetPoint("LEFT", row, "LEFT", LEVEL_X, 0)
    row.LevelText:SetWidth(LEVEL_WIDTH)
    row.LevelText:SetWordWrap(false)
    row.SpeedText = Helpers.NewText(row, "GameFontDisableSmall")
    row.SpeedText:SetPoint("LEFT", row, "LEFT", SPEED_X, 0)
    row.SpeedText:SetWidth(SPEED_WIDTH)
    row.SpeedText:SetWordWrap(false)
    row.ZoneText = Helpers.NewText(row, "GameFontDisableSmall")
    row.ZoneText:SetWordWrap(false)
    row.MapButton = Helpers.NewOutlineButton(row)
    row.MapButton:SetSize(MAP_BUTTON_WIDTH, 18)
    row.MapButton:SetPoint("RIGHT", -2, 0)
    row.MapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (right-click clears the pins)
    row.MapButton:SetScript("OnClick", function(button, mouseButton) PinHelper:MapClick(button.npc, mouseButton) end)
    row.MapButton:SetMotionScriptsWhileDisabled(true) -- the greyed-out button still says why
    row.MapButton:SetScript("OnEnter", function(button) PinHelper:ShowMapTooltip(button) end)
    row.MapButton:SetScript("OnLeave", GameTooltip_Hide)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(this)
      if not this.npc then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      PinHelper:AddTooltipLines(this.npc)
      if this.npc.untamable then
        Helpers.TipLine(L.UNTAMABLE_TOOLTIP, Colors.Muted, true)
      else
        Helpers.TipLine(L.PROFILE_CLICK, Colors.Muted)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseUp", function(this, button)
      if button == "LeftButton" and this.npc and not this.npc.untamable and this:IsMouseOver() then
        Helpers.PlayClick()
        Window:ShowPetProfile(this.npc.id)
      end
    end)
    -- Alternating shade (set per-row below, from the result list's own order): subtle enough to stay well under the
    -- rare glow and the gold hover tint, which both draw above it (RareGlow is BACKGROUND sublevel 1; hover is its
    -- own HIGHLIGHT layer), so neither competes with it.
    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(Colors.Gold:GetRGBA(0.1))
    -- A rare creature: the row glows gold from the left, as InitNPCRow's.
    row.RareGlow = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.RareGlow:SetAllPoints()
    row.RareGlow:SetColorTexture(1, 1, 1, 1)
    local r, g, b = Colors.Gold:GetRGB()
    if CreateColor and not pcall(row.RareGlow.SetGradient, row.RareGlow, "HORIZONTAL",
        CreateColor(Colors.Gold:GetRGBA(0.18)), CreateColor(Colors.Gold:GetRGBA(0.02))) then
      pcall(row.RareGlow.SetGradientAlpha, row.RareGlow, "HORIZONTAL", r, g, b, 0.18, r, g, b, 0.02)
    end
    -- A creature added in WoW Forever: the infinity mark before its name, "New in Forever" on hover.
    row.ForeverIcon = CreateFrame("Frame", nil, row)
    row.ForeverIcon:SetSize(12, 12)
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
    -- An elite creature: the skull raid marker before its name.
    row.EliteIcon = row:CreateTexture(nil, "ARTWORK")
    row.EliteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    row.EliteIcon:SetSize(12, 12)
    -- The mark after its name (Addon:NPCMark): tamed (green dot) or sighted (grey eye), as InitNPCRow's.
    local badge = CreateFrame("Frame", nil, row)
    badge:SetSize(12, 12)
    badge:EnableMouse(true)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints()
    badge:SetScript("OnEnter", function(frame)
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      if frame.kind == "sighted" then
        GameTooltip:SetText(L.SIGHTED, 1, 1, 1)
        Helpers.TipLine(L.SIGHTED_TOOLTIP, Colors.Muted, true)
      else
        local text = frame.by and L.VERIFIED_TAME_BY:format(frame.date or "", frame.by)
          or L.VERIFIED_TAME:format(frame.date or "")
        GameTooltip:SetText(text, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    row.TamedBadge = badge
  end

  row.npc = npc
  Helpers.UpdateFavoriteButton(row.FavoriteButton, npc.id)
  local class = npc.class or ""
  local rare, elite = class:find("Rare", 1, true) ~= nil, class:find("Elite", 1, true) ~= nil
  local forever = npc.forever == true
  row.RareGlow:SetShown(rare)

  -- The zebra shade follows the result list's own order (Window:RefreshSearchTop's searchTopIndex), not the row
  -- frame's screen position: the scroll box recycles and repositions these frames as the list scrolls, so only the
  -- data's own index stays put. A row with no index yet (between a refresh and the scroll box's next layout pass)
  -- keeps the paler shade rather than showing nothing.
  local index = self.searchTopIndex and self.searchTopIndex[npc]
  row.Stripe:SetColorTexture(1, 1, 1, (index and index % 2 == 1) and 0.07 or 0.02)

  -- The marks before the name, left to right: infinity, then the skull; the name starts after them.
  local x = NAME_X
  row.ForeverIcon:ClearAllPoints()
  row.ForeverIcon:SetPoint("LEFT", x, 0)
  row.ForeverIcon:SetShown(forever)
  if forever then x = x + 15 end
  row.EliteIcon:ClearAllPoints()
  row.EliteIcon:SetPoint("LEFT", x, 0)
  row.EliteIcon:SetShown(elite)
  if elite then x = x + 15 end

  row.NameText:ClearAllPoints()
  row.NameText:SetPoint("LEFT", x, 0)
  row.NameText:SetPoint("RIGHT", row, "LEFT", FAMILY_X - 8, 0)
  row.NameText:SetText(Colors.NPC(npc.name)
    .. (npc.not_tameable and ("  " .. Colors.Bad(L.TAME_CHECK_NOT_TAMEABLE)) or ""))

  local badge = row.TamedBadge
  local mark = Addon:NPCMark(npc)
  badge:SetShown(mark ~= nil)
  if mark then
    badge.kind = mark
    Addon:SetNPCMarkTexture(badge.icon, mark)
    badge.date = npc.tamed
    badge.by = type(npc.tamed_by) == "string" and npc.tamed_by ~= "" and npc.tamed_by or nil
    local width = row.NameText.GetUnboundedStringWidth and row.NameText:GetUnboundedStringWidth()
      or row.NameText:GetStringWidth()
    local room = row.NameText:GetWidth()
    if room and room > 0 then width = math.min(width, room - 14) end
    badge:ClearAllPoints()
    badge:SetPoint("LEFT", row.NameText, "LEFT", width + 3, 0)
  end

  row.FamilyIcon:SetTexture(Addon:FamilyIcon(npc.family) or Addon.QUESTION_MARK_ICON)
  SetAbilityIcon(row.UniqueIcon, row.UniqueRank, TaughtOfTab(npc, "UNIQUE"))
  local commonA, commonB = TaughtOfTab(npc, "COMMON", 2)
  SetAbilityIcon(row.CommonIcon, row.CommonRank, commonA)
  SetAbilityIcon(row.CommonIcon2, row.CommonRank2, commonB)

  -- Just the level range here, not npc.level_range's "(Rare)"/"(Elite)" suffix: RareGlow and EliteIcon already say
  -- that, in color, without spending column width on the word too.
  row.LevelText:SetText(Helpers.LevelText(npc.min, npc.max))

  -- "?" alone, not L.UNKNOWN ("Unknown"): the column is too narrow for the word, which was clipping to "Unk...".
  if type(npc.speed) == "number" then
    row.SpeedText:SetText(("%.2f"):format(npc.speed) .. (npc.speed_tamed == false and "?" or ""))
  else
    row.SpeedText:SetText("?")
  end

  self:SetMapButton(row.MapButton, npc)
  local status = row.MapButton:GetText()
  -- "?" alone, not L.UNKNOWN_ZONE ("Unknown Zone"): the column is too narrow for the phrase. The button's hint
  -- still explains why on hover (Window:SetMapButton sets it regardless).
  if status == L.UNKNOWN_ZONE then
    row.MapButton:SetText("?")
  -- Unavailable with a known zone (Window:SetMapButton's last branch) is a dungeon in practice: the game has no
  -- UiMapID at all inside one (confirmed live, /run testing in Ruins of Lordaeron and Shadowfang Keep), so a
  -- dungeon creature's npc.ui_map_id is always nil even though its zone name is known. Nothing else lands here.
  -- Window:SetMapButton already enabled the button when the Dungeon Journal has a listing for this zone; the
  -- hint still needs its own wording here, for this tab's shorter "Instance" label.
  elseif status == L.MAP_UNAVAILABLE then
    row.MapButton:SetText(L.SEARCH_TOP_INSTANCE)
    row.MapButton.hint = row.MapButton:IsEnabled() and L.SEARCH_TOP_INSTANCE_JOURNAL_TOOLTIP or L.SEARCH_TOP_INSTANCE_TOOLTIP
  end
  -- One fixed width and font for every row, not Window:SetMapButton's own per-text sizing: Instance gets the
  -- smaller font (SmallMapFonts) since it is the longest word now that the button no longer grows to fit it; every
  -- other text (Map, No Coord, ?) gets the default outline button font back, in case this row last showed Instance
  -- (rows are recycled by the scroll box).
  local fonts = (status == L.MAP_UNAVAILABLE) and SmallMapFonts() or Helpers.OutlineButtonFonts()
  row.MapButton:SetNormalFontObject(fonts.Normal)
  row.MapButton:SetHighlightFontObject(fonts.Highlight)
  row.MapButton:SetDisabledFontObject(fonts.Disable)
  row.MapButton:SetWidth(MAP_BUTTON_WIDTH)
  row.MapButton:SetShown(not npc.untamable)
  row.ZoneText:ClearAllPoints()
  row.ZoneText:SetPoint("LEFT", row, "LEFT", ZONE_X, 0)
  row.ZoneText:SetPoint("RIGHT", row.MapButton, "LEFT", -8, 0)
  row.ZoneText:SetText(npc.location or "?")
end

-- Shown and placed only while this tab is the one showing, spanning the details pane now that the list beside it is
-- hidden (Window:UpdateTabs).
function Window:UpdateSearchTopBar()
  local bar = self.searchTopBar
  if not bar then return end
  local shown = self.tab == "SEARCHTOP"
  bar:SetShown(shown)
  self.searchTopHeader:SetShown(shown)
  self.searchTopBox:SetShown(shown)
  self.searchTopDividers:SetShown(shown)
  if not shown then
    self.searchTopScrollBar:Hide()
    return
  end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", self.details, "TOPLEFT", Window.DETAILS_LEFT, -Window.DETAILS_TOP)
  bar:SetPoint("RIGHT", self.details, "RIGHT", -4, 0) -- every pixel matters: six dropdowns share one row
  bar:SetFrameLevel(self.details:GetFrameLevel() + 10)

  -- The result count and the current zone (when Zone Filter is on) show in the header's own subtitle
  -- (self.headerCount, Window:RefreshSearchTop) instead of a second line here: this tab has no sidebar list of its
  -- own to put a local count on, as the others do, but the subtitle already says it once.
  self.searchTopHeader:ClearAllPoints()
  self.searchTopHeader:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
  -- -20 off bar (which is itself -4 off details), not -14: matches searchTopBox's own right edge exactly (-24 off
  -- details directly), so the "Status" header, Clear and the rows' own Map buttons all land on the same line.
  self.searchTopHeader:SetPoint("RIGHT", bar, "RIGHT", -20, 0)

  self.searchTopBox:ClearAllPoints()
  self.searchTopBox:SetPoint("TOPLEFT", self.searchTopHeader, "BOTTOMLEFT", 0, -4)
  self.searchTopBox:SetPoint("BOTTOMRIGHT", self.details, "BOTTOMRIGHT", -24, 10)
  self.searchTopScrollBar:ClearAllPoints()
  self.searchTopScrollBar:SetPoint("TOPLEFT", self.searchTopBox, "TOPRIGHT", 4, 0)
  self.searchTopScrollBar:SetPoint("BOTTOMLEFT", self.searchTopBox, "BOTTOMRIGHT", 4, 0)
  self.searchTopBox:SetFrameLevel(self.details:GetFrameLevel() + 10)
  self.searchTopScrollBar:SetFrameLevel(self.details:GetFrameLevel() + 10)

  -- Clear's right edge matches the row list's own (self.searchTopBox), not a guess off bar: "TOP" off FavoritesCheck
  -- (Row 2's own height) for y, "RIGHT" off the box for x, same trick as the dividers use for two different
  -- reference frames at once. The search box then just fills what is left between Favorites and Clear, same row,
  -- no further cross-referencing needed.
  bar.ClearButton:ClearAllPoints()
  -- +2, not 0: Clear (22 tall) and FavoritesCheck (18 tall) would share a top edge at 0, but their *centers* would
  -- then sit 2px apart -- half their height difference -- which is what actually needs to match here.
  bar.ClearButton:SetPoint("TOP", bar.FavoritesCheck, "TOP", 0, 2)
  bar.ClearButton:SetPoint("RIGHT", self.searchTopBox, "RIGHT", -2, 0)
  bar.SearchBox:ClearAllPoints()
  bar.SearchBox:SetPoint("LEFT", bar.FavoritesCheck, "RIGHT", 10, 0)
  bar.SearchBox:SetPoint("RIGHT", bar.ClearButton, "LEFT", -10, 0)

  -- The dividers span the header and every row below it: the header's own left/right (clear of the scrollbar) and
  -- top, down to the box's bottom. Above the box's own frame level so the lines show over the rows, not under them.
  self.searchTopDividers:ClearAllPoints()
  self.searchTopDividers:SetPoint("TOPLEFT", self.searchTopHeader, "TOPLEFT", 0, 0)
  self.searchTopDividers:SetPoint("TOPRIGHT", self.searchTopHeader, "TOPRIGHT", 0, 0)
  self.searchTopDividers:SetPoint("BOTTOM", self.searchTopBox, "BOTTOM", 0, 0)
  self.searchTopDividers:SetFrameLevel(self.searchTopBox:GetFrameLevel() + 1)

  self:SyncSearchTopControls()
end

function Window:UpdateSearchTopDetails()
  self.details:Show()
  self.iconButton:Hide()
  self.name:Hide()
  self.subtitle:Hide()
  self.facts:Hide()
  self.nameLink:Hide()
  self.description:Hide()
  self.mapButton:Hide()
  self.miniMap:Hide()
  -- This tab uses its own tabular list (searchTopBox) instead of the shared creature list every other tab draws
  -- into (npcBox/npcLabel).
  self.npcLabel:Hide()
  self.npcBox:Hide()
  self.npcBar:Hide()

  local results = self.searchResults or {}

  -- Each row's zebra shade (InitSearchTopRow) reads its place in this same order, keyed by the npc table itself
  -- rather than its id: a position, not an identity, is all the stripe needs, and it's rebuilt fresh on every
  -- refresh anyway.
  local index = {}
  for i, resultNpc in ipairs(results) do index[resultNpc] = i end
  self.searchTopIndex = index

  self.searchTopBox:SetDataProvider(CreateDataProvider(results))
  self.searchTopBox:SetShown(#results > 0)
  self.searchTopScrollBar:SetShown(#results > 0)
end
