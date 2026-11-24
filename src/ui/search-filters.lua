local _, Addon = ...
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The Database Search filtering and sorting (the website's Search::index(), worked out from the data), kept apart
-- from tab-search.lua's own widgets: the matching and sorting rules on their own, so they stay easy to check against
-- the website's independently of how the filters are laid out on screen. (An earlier, since-deleted layout of that
-- same tab shared this same file and its own filter state, Window:NewSearchFilterState, the same way.)

function Window:NewSearchFilterState()
  return { family = {}, type = {}, class = {}, ability = {}, food = "", taming = "", zone = "", levelMin = "0",
    levelMax = "60", forever = false, favorites = false, sort = "level", dir = "asc" }
end

-- Clears a filter state back to its defaults, in place (so every row or dropdown built from it keeps pointing at the
-- same table). A layout's own Clear Filters control also clears the universal search box; that is not done here, since
-- it is shared window state rather than part of the filters.
function Window:ResetSearchFilters(SF)
  for k in pairs(SF.family) do SF.family[k] = nil end
  for k in pairs(SF.type) do SF.type[k] = nil end
  for k in pairs(SF.class) do SF.class[k] = nil end
  for k in pairs(SF.ability) do SF.ability[k] = nil end
  SF.food, SF.taming, SF.zone = "", "", ""
  SF.levelMin, SF.levelMax = "0", "60"
  SF.forever = false
  SF.favorites = false
  SF.sort, SF.dir = "level", "asc"
end

-- ----------------------------------------------------------------------------
-- Filter option lists, built once from the data (Family and Type and Diet are not known ahead of time: a custom
-- server's families could be named or typed differently).
-- ----------------------------------------------------------------------------

Window.SEARCH_CLASS_ITEMS = {
  { key = "", label = L.SEARCH_CLASS_NORMAL }, { key = "Rare", label = "Rare" }, { key = "Elite", label = "Elite" },
  { key = "Rare Elite", label = "Rare Elite" }, { key = "Boss", label = "Boss" },
}
Window.SEARCH_TAMING_ITEMS = {
  { key = "", label = L.SEARCH_ANY }, { key = "tamed", label = L.SEARCH_TAMED },
  { key = "sighted", label = L.SEARCH_SIGHTED }, { key = "untamed", label = L.SEARCH_UNTAMED },
}

local FAMILY_ITEMS, TYPE_ITEMS, FOOD_ITEMS
function Window:SearchFilterOptionLists()
  if FAMILY_ITEMS then return FAMILY_ITEMS, TYPE_ITEMS, FOOD_ITEMS end
  FAMILY_ITEMS, TYPE_ITEMS, FOOD_ITEMS = {}, {}, {}
  local types, foods = {}, {}
  for name, family in pairs(Addon.TameableFamilies or {}) do
    FAMILY_ITEMS[#FAMILY_ITEMS + 1] = { key = name, label = name }
    if family.type then types[family.type] = true end
    for _, food in ipairs(family.foods or {}) do foods[food] = true end
  end
  for t in pairs(types) do TYPE_ITEMS[#TYPE_ITEMS + 1] = { key = t, label = t } end
  for food in pairs(foods) do FOOD_ITEMS[#FOOD_ITEMS + 1] = { key = food, label = food } end
  FOOD_ITEMS[#FOOD_ITEMS + 1] = { key = "", label = L.SEARCH_ANY } -- (listed last; shown first by the sort below)
  local function byLabel(a, b) return a.label < b.label end
  table.sort(FAMILY_ITEMS, byLabel)
  table.sort(TYPE_ITEMS, byLabel)
  table.sort(FOOD_ITEMS, function(a, b)
    if a.key == "" or b.key == "" then return a.key == "" end
    return byLabel(a, b)
  end)
  return FAMILY_ITEMS, TYPE_ITEMS, FOOD_ITEMS
end

-- Every ability on file (Unique, Common, Passive and the attack speed tiers), by its key (data.lua sets `ability.key`
-- on each one): built once, like the lists above. Not the trainer-only ones (ability.trainer: Growl and the
-- passives, learned from a Hunter or Pet Trainer, as tab-abilities.lua's own fromTrainer puts it) -- no creature's
-- npc.taught ever lists one, so AbilityOk could never match a creature against it anyway.
local ABILITY_ITEMS
function Window:SearchAbilityItems()
  if ABILITY_ITEMS then return ABILITY_ITEMS end
  ABILITY_ITEMS = {}
  for key, ability in pairs(Addon.TameableAbilities or {}) do
    if not ability.trainer then
      ABILITY_ITEMS[#ABILITY_ITEMS + 1] = { key = key, label = ability.name }
    end
  end
  table.sort(ABILITY_ITEMS, function(a, b) return a.label < b.label end)
  return ABILITY_ITEMS
end

-- ----------------------------------------------------------------------------
-- Which creatures match
-- ----------------------------------------------------------------------------

local function Tamed(npc) return type(npc.tamed) == "string" and npc.tamed ~= "" end

local function SetEmpty(t) return next(t) == nil end

local function FamilyOk(npc, SF) return SetEmpty(SF.family) or SF.family[npc.family] == true end
local function TypeOk(npc, SF) return SetEmpty(SF.type) or (npc.type ~= nil and SF.type[npc.type] == true) end

local function ClassOk(npc, SF)
  if SetEmpty(SF.class) then return true end
  return SF.class[npc.class or ""] == true
end

local function DietOk(npc, SF)
  if SF.food == "" then return true end
  local family = Addon.TameableFamilies and Addon.TameableFamilies[npc.family]
  for _, food in ipairs(family and family.foods or {}) do
    if food == SF.food then return true end
  end
  return false
end

-- Any ability the creature teaches that is checked on.
local function AbilityOk(npc, SF)
  if SetEmpty(SF.ability) then return true end
  for _, taught in ipairs(npc.taught or {}) do
    if SF.ability[taught.ability.key] == true then return true end
  end
  return false
end

-- A level range overlaps the creature's own; the boxes default to 0-60 (every level), which filters nothing. A
-- creature with no level on file never matches a narrowed range (as the website's search).
local function LevelOk(npc, SF)
  local lo, hi = tonumber(SF.levelMin) or 0, tonumber(SF.levelMax) or 60
  if lo <= 0 and hi >= 60 then return true end
  if not npc.min then return false end
  return npc.min <= hi and (npc.max or npc.min) >= lo
end

local function TamingOk(npc, SF)
  if SF.taming == "tamed" then return Tamed(npc) end
  if SF.taming == "untamed" then return not Tamed(npc) end
  if SF.taming == "sighted" then return not Tamed(npc) and npc.sighted == true end
  return true
end

local function ForeverOk(npc, SF) return not SF.forever or npc.forever == true end

local function FavoritesOk(npc, SF) return not SF.favorites or Addon:IsFavorite(npc.id) end

-- A specific zone chosen in tab-search.lua's own Zone dropdown (not the header's Zone Filter button, which
-- always means "wherever I am now" and is handled separately below, via self:ZoneFilter()). Empty: no such filter.
local function ZoneOk(npc, SF) return not SF.zone or SF.zone == "" or Window:NPCInZone(npc, { name = SF.zone }) end

-- Whether a creature passes every filter: the universal search box (name), the Zone and Level header filters, and
-- the filters in `SF` (Family, Type, Diet, Ability, Zone, Level range, Classification, Taming, Forever, Favorites).
function Window:SearchNPCShown(npc, SF)
  if not self:NPCMatchesSearch(npc, self:CreatureSearch()) then return false end
  if not (FamilyOk(npc, SF) and TypeOk(npc, SF) and ClassOk(npc, SF) and DietOk(npc, SF) and AbilityOk(npc, SF)
      and ZoneOk(npc, SF) and LevelOk(npc, SF) and TamingOk(npc, SF) and ForeverOk(npc, SF) and FavoritesOk(npc, SF)) then
    return false
  end
  local zone = self:ZoneFilter()
  if zone and not self:NPCInZone(npc, zone) then return false end
  if DB.global.filter_by_level and not (npc.min and npc.min <= (UnitLevel("player") or 1)) then return false end
  -- The header's Rares, Tamed and Favorites buttons (window.lua's FILTER_BUTTONS), now shown and working on this
  -- tab too (CREATURE_LISTS there includes SEARCHTOP). Tamed and Favorites have no tab-local gate the way Rares
  -- does (Window:RaresOnly()), so they read DB.global directly, as Filter by Level does above.
  if self:RaresOnly() and not self:NPCIsRare(npc) then return false end
  if DB.global.filter_tamed and Addon:NPCMark(npc) ~= "tamed" then return false end
  if DB.global.filter_favorites and not Addon:IsFavorite(npc.id) then return false end
  return true
end

-- ----------------------------------------------------------------------------
-- Sorting (the website's SEARCH_SORTS, minus "id")
-- ----------------------------------------------------------------------------

-- "family" and "zone" exist so tab-search.lua's Family and Zone column headers can sort by them too.
Window.SEARCH_SORT_FIELDS = { "level", "name", "speed", "class", "tamed", "family", "zone" }
Window.SEARCH_SORT_FIELD_LABELS = { level = L.SORT_LEVEL, name = L.SORT_NAME, speed = L.SORT_SPEED,
  class = L.SORT_CLASS, tamed = L.SORT_TAMED, family = L.SORT_FAMILY, zone = L.SORT_ZONE }
local CLASS_RANK = { [""] = 0, Rare = 1, Elite = 2, ["Rare Elite"] = 3, Boss = 4 }
local SORT_VALUE = {
  level = function(npc) return npc.min or math.huge end,
  name = function(npc) return (npc.name or ""):lower() end,
  speed = function(npc) return npc.speed or math.huge end,
  class = function(npc) return CLASS_RANK[npc.class or ""] or 0 end,
  tamed = function(npc) return npc.tamed or "" end,
  family = function(npc) return (npc.family or ""):lower() end,
  zone = function(npc) return (npc.location or ""):lower() end,
}

local function CompareResults(a, b, SF)
  local get = SORT_VALUE[SF.sort] or SORT_VALUE.level
  local av, bv = get(a), get(b)
  if av ~= bv then
    if SF.dir == "desc" then return av > bv end
    return av < bv
  end
  return (a.name or "") < (b.name or "")
end

function Window:GetSearchResults(SF)
  local list = {}
  for id in pairs(Addon.TameableNPCs or {}) do
    if not Addon.IGNORED_NPC_IDS[id] then
      local npc = Addon:GetNPC(id)
      if npc and self:SearchNPCShown(npc, SF) then list[#list + 1] = npc end
    end
  end
  table.sort(list, function(a, b) return CompareResults(a, b, SF) end)
  return list
end
