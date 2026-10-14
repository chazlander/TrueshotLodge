local ADDON_NAME, Addon = ...
local Commands = Addon:GetModule("Commands")
local PinHelper = Addon:GetModule("PinHelper")
local UI = Addon:GetModule("UI")

-- `/trueshotlodge [command]`, or `/tsl [command]` for short.
function Commands:Initialize()
  _G["SLASH_" .. ADDON_NAME:upper() .. "1"] = "/" .. ADDON_NAME:lower()
  _G["SLASH_" .. ADDON_NAME:upper() .. "2"] = "/tsl"
  SlashCmdList[ADDON_NAME:upper()] = function(message) self:Handle(message) end
  self.Initialize = nil
end

-- The words of a command line, e.g. "debug collect clear" -> { "debug", "collect", "clear" }.
local function GetArgs(message)
  local args = {}
  for word in tostring(message or ""):gmatch("%S+") do args[#args + 1] = word:lower() end
  return args
end

local function Say(...)
  print("|cFFFF8800[" .. Addon.TITLE .. " debug]|r", ...)
end

-- The debug commands, `/tsl debug <command> [option]`, in the order `/tsl debug` lists them.
local DEBUG_COMMANDS = {
  { "collect", "turn Collect Mode on or off" },
  { "collect check", "why nothing is being collected" },
  { "collect count", "how many creatures are collected" },
  { "collect clear", "delete everything collected" },
  { "shared", "what Data Sharing is doing" },
  { "shared ping", "test who hears you" },
  { "stable", "what the game says about your pets, next to the Stable tab's copies" },
  { "npc <id>", "what the game, our data and your collected data say about a creature" },
  { "training", "the open trainer's pet abilities and costs, and the pet's training points" },
  { "training scan", "globals that might belong to the Beast Training window" },
  { "training events", "print each event as it first fires (again to stop)" },
  { "icon", "the parts of the details icon" },
}

local Debug = {}

function Debug.collect(option)
  local global = Addon:GetModule("DB").global
  local Collector = Addon:GetModule("Collector")
  if option == "clear" then
    Collector:Clear()
    return Say("collect: cleared")
  elseif option == "count" then
    return Say("collect:", Collector:Count(), "creatures")
  elseif option == "check" then
    return Collector:Diagnose()
  end
  global.collect = not global.collect
  Collector:SetEnabled(global.collect)
  Addon:GetModule("Window"):OnCollectChanged()
  return Say("collect:", global.collect and "on" or "off", "(" .. Collector:Count() .. " creatures)")
end

function Debug.shared(option)
  if option == "ping" then return Addon:GetModule("Share"):Ping() end
  return Addon:GetModule("Share"):Status()
end

function Debug.stable()
  return Addon:GetModule("Stable"):Diagnose()
end

-- `/tsl debug npc <id>`: what the game, our data and your collected data say about a creature.
function Debug.npc(option)
  local id = tonumber(option)
  if not id or id <= 0 then return Say("npc: give an npc id, e.g. /tsl debug npc 3123") end

  local game = Addon:NPCGameName(id)
  Say("npc " .. id .. ":", game and ('the game says "' .. game .. '"') or "the game does not give a name yet (try again)")

  local npc = Addon.TameableNPCs[id]
  if npc then
    local levels = npc.min and ((npc.max and npc.max ~= npc.min) and (npc.min .. "-" .. npc.max) or npc.min) or "?"
    local maps = 0
    for _ in pairs(npc.maps or {}) do maps = maps + 1 end
    Say("  our data:", npc.name, "|", npc.family, "| level", levels, npc.class or "normal",
      "| attack speed", tostring(npc.speed or "?"), "|", #(npc.zones or {}), "zone(s),", maps, "map(s)",
      npc.tamed and ("| tamed " .. npc.tamed) or "")
  else
    Say("  our data: not in it")
  end

  local creatures = Addon:GetModule("DB").collected.creatures
  local c = creatures and creatures[tostring(id)]
  if c then
    local zones = 0
    for _ in pairs(c.zones or {}) do zones = zones + 1 end
    Say("  you collected:", tostring(c.name), "|", tostring(c.family), "| level", tostring(c.level_min) .. "-" .. tostring(c.level_max),
      "| speed", tostring(c.mainhand_speed), "|", zones, "zone(s)", c.shared_by and ("| shared by " .. c.shared_by) or "")
  else
    Say("  you collected: nothing of it")
  end
end

function Debug.icon()
  return Addon:GetModule("Window"):DescribeIcon()
end

-- Lists globals that might belong to the Beast Training UI.
local function ScanTrainingGlobals()
  local found = {}
  local function scan(tbl, prefix)
    for k, v in pairs(tbl) do
      if type(k) == "string" then
        local lower = k:lower()
        if lower:find("beast") or lower:find("craft") or lower:find("pettrain")
            or lower:find("traininglist") or lower:find("petspell") then
          found[#found + 1] = prefix .. k .. "(" .. type(v) .. ")"
        end
      end
    end
  end
  scan(_G, "")
  for k, v in pairs(_G) do
    if type(k) == "string" and k:match("^C_") and type(v) == "table" then
      scan(v, k .. ".")
    end
  end
  table.sort(found)
  Say("training scan:", #found, "matches")
  for i = 1, #found, 6 do
    print(table.concat(found, ", ", i, math.min(i + 5, #found)))
  end
end

-- Prints each distinct event fired while on, to find the window's events.
local function ToggleEventScan()
  Addon.eventScan = not Addon.eventScan
  if Addon.eventScan then
    local seen = {}
    Addon.eventScanFrame = Addon.eventScanFrame or CreateFrame("Frame")
    Addon.eventScanFrame:SetScript("OnEvent", function(_, event)
      if not seen[event] and Addon.eventScan then
        seen[event] = true
        Say("event:", event)
      end
    end)
    Addon.eventScanFrame:RegisterAllEvents()
  else
    Addon.eventScanFrame:UnregisterAllEvents()
  end
  return Say("event scan:", Addon.eventScan and "on" or "off")
end

-- Diagnostics for the Beast Training detection.
function Debug.training(option)
  if option == "scan" then return ScanTrainingGlobals() end
  if option == "events" then return ToggleEventScan() end

  local trained = Addon:GetModule("DB").char.trained
  local count = 0
  for _ in pairs(trained or {}) do count = count + 1 end
  local services = Addon:GetModule("Training"):ReadServices()
  Say("training:",
    "GetNumTrainerServices=" .. tostring(GetNumTrainerServices ~= nil),
    "C_Trainer=" .. tostring(C_Trainer ~= nil),
    "ClassTrainerFrame=" .. tostring(ClassTrainerFrame ~= nil),
    "open services=" .. #services,
    "saved=" .. count)
  -- The pet's training points, when the client has them: total, then spent (classic GetPetTrainingPoints).
  local function joined(values)
    local parts = {}
    for i = 1, values.n do parts[i] = tostring(values[i]) end
    return table.concat(parts, ", ")
  end
  local tp = _G.GetPetTrainingPoints and { n = 2, GetPetTrainingPoints() } or nil
  Say("training: pet training points (total, spent):", tp and joined(tp) or "n/a (no GetPetTrainingPoints)")
  -- Show the pet abilities (matching the data), with the raw rank text and every cost value the game gives.
  local names = {}
  for _, ability in pairs(Addon.TameableAbilities) do names[ability.name:lower()] = true end
  local shown = 0
  for _, s in ipairs(services) do
    if names[tostring(s.name):lower()] and shown < 30 then
      shown = shown + 1
      local link = _G.GetTrainerServiceItemLink and GetTrainerServiceItemLink(s.index)
      print(("  #%d %s | rank=[%s] | %s | costs=[%s] | lvl=%s | spell=%s | link=%s"):format(
        s.index, tostring(s.name), tostring(s.rank), tostring(s.category),
        joined(s.costs or { n = 1, s.cost }), tostring(s.level_req), tostring(s.spell_id), tostring(link)))
    end
  end
end

-- `/tsl debug [command] [option]`: works only while Debug Mode (Options > Advanced) is on.
function Commands:HandleDebug(command, option)
  if not Addon:GetModule("DB").global.debug then
    return print(Addon.TITLE .. ": the debug commands need Debug Mode on (Options tab, Advanced).")
  end
  local run = command and Debug[command]
  if run then return run(option) end
  if command then Say("unknown command:", command) end
  Say("commands (/tsl debug ...):")
  for _, entry in ipairs(DEBUG_COMMANDS) do
    print(("  |cFFFFD100%s|r - %s"):format(entry[1], entry[2]))
  end
end

function Commands:Handle(message)
  local args = GetArgs(message)
  local cmd = args[1]
  if cmd == "clear" then
    return PinHelper:Clear()
  elseif cmd == "debug" then
    return self:HandleDebug(args[2], args[3])
  end
  UI:Toggle()
end
