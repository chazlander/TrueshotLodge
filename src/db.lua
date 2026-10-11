local _, Addon = ...
local DB = Addon:GetModule("DB")

-- Saved settings and collected data, in the `TrueshotLodgeDB` saved variable:
--
--   TrueshotLodgeDB = { global = { ... }, char = { ["Name - Realm"] = { ... } } }
--   TrueshotLodgeCollected = { creatures = { ... }, tames = { ... }, trainers = { ... }, beast_training = { ... } }
--
-- `DB.global` is shared by all characters and `DB.char` belongs to the logged-in one. What Collect Mode records is
-- `DB.collected`, a saved variable of its own (still in the same file, TrueshotLodge.lua): the website reads only it
-- from an upload, and clearing it never touches the settings. The addon was called
-- ForeverTamed until October 2026; its saved data (ForeverTamedDB) is not carried over.

local defaults = {
  char = {
    trained = {},
    trained_ids = {},
    known_ids = {}, -- spell id -> true, for ranks the character has known (kept between sessions)
    -- The Stable tab's cache (src/stable.lua): `pets` is a copy of each pet seen out (name|family -> level, spells, ...),
    -- `slots` is what the stable held the last time it was opened, `active` the key of the pet last seen out.
    stable = { pets = {}, slots = {} },
    tab_order = {}, -- the side tabs' keys in the order the character put them (drag a tab); empty = the usual order
  },
  global = {
    minimapIcon = { hide = false },
    npc_tooltips = true,
    sticky_selections = true,
    -- Data Sharing (Options tab): who your collected data is sent to, each on its own, and taking in what others send.
    share_shard = true, -- the hidden TrueshotLodge channel, and the users you have heard from (by whisper)
    share_zone = true, -- the hidden channel of the zone you are in
    share_group = true, -- your party, raid or instance group
    share_moderators = true, -- whispered to the moderators when they are online
    receive_shared = false, -- add the entries other TrueshotLodge users share to the collected data
    share_peers = {}, -- name -> { first, last }: the TrueshotLodge users heard from, whispered each update (src/share.lua)
    ui_scale = 1, -- the window's scale (UI Scale on the Options tab), 0.5 to 1.5
    filter_by_level = false,
    filter_by_faction = false,
    zone_filter = false, -- the Zone Filter checkbox in the window's title bar (src/ui/zone-filter.lua)
    filter_by_pet = false,
    last_tab = "UNIQUE",
    selections = {}, -- tab -> { ability = slug, rank = n } or the trainer's id
    debug = false,
    collect = true, -- Collect Mode: record (and share) what is seen; on by default
    send_name = false, -- Send Name: put your character's name on the beasts you tame (tamed_by); off = anonymous
  },
  -- What Collect Mode records (TrueshotLodgeCollected).
  collected = {
    creatures = {}, -- npc id -> the creature as seen in the wild
    tames = {}, -- the beasts tamed, newest last
    trainers = {}, -- npc id -> the pet trainers talked to while collecting, with what they teach and sell
    beast_training = {}, -- "name|rank" -> the entries of the Beast Training window
  },
}

-- What Collect Mode records: kept in the settings (DB.global) before it had a saved variable of its own.
local COLLECTED_KEYS = { "creatures", "tames", "trainers", "beast_training", "pets" }

-- Fills in missing values from `source`, recursing into tables; values already set are kept.
local function ApplyDefaults(target, source)
  for key, value in pairs(source) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      ApplyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

-- Called once this addon's saved variables are loaded (ADDON_LOADED).
function DB:Initialize()
  local saved = _G.TrueshotLodgeDB
  if type(saved) ~= "table" then saved = {} end
  _G.TrueshotLodgeDB = saved

  if type(saved.global) ~= "table" then saved.global = {} end
  if type(saved.char) ~= "table" then saved.char = {} end
  -- Keyed by your full name ("Spike Skylance - <realm>": in WoW Forever two characters can share a first name). What
  -- an earlier version kept under the first name alone is moved over once.
  local realm = GetRealmName() or "?"
  local charKey = ("%s - %s"):format(Addon:PlayerName() or "?", realm)
  local oldKey = ("%s - %s"):format(Addon:Plain(UnitName("player")) or "?", realm)
  if saved.char[charKey] == nil and oldKey ~= charKey and type(saved.char[oldKey]) == "table" then
    saved.char[charKey], saved.char[oldKey] = saved.char[oldKey], nil
  end
  if type(saved.char[charKey]) ~= "table" then saved.char[charKey] = {} end

  -- The collected data: its own saved variable. What an earlier version kept in the settings is moved over once.
  local collected = _G.TrueshotLodgeCollected
  if type(collected) ~= "table" then collected = {} end
  _G.TrueshotLodgeCollected = collected
  for _, key in ipairs(COLLECTED_KEYS) do
    if saved.global[key] ~= nil then
      if type(collected[key]) ~= "table" or next(collected[key]) == nil then collected[key] = saved.global[key] end
      saved.global[key] = nil
    end
  end

  ApplyDefaults(saved.global, defaults.global)
  ApplyDefaults(saved.char[charKey], defaults.char)
  ApplyDefaults(collected, defaults.collected)

  -- Earlier versions saved every rank a trainer window listed as trained, learned or not (all seven Growl ranks at
  -- level 22): cleared once. The pet's spellbook (known_ids) marks the real ones again.
  local char = saved.char[charKey]
  if (char.trained_version or 1) < 2 then
    char.trained, char.trained_ids = {}, {}
    char.trained_version = 2
  end

  self.global = saved.global
  self.char = saved.char[charKey]
  self.collected = collected
  self.Initialize = nil
end
