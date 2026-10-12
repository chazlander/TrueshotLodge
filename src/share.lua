local _, Addon = ...
local Share = Addon:GetModule("Share")
local DB = Addon:GetModule("DB")

-- Sharing collected data with other TrueshotLodge users, while collecting. The addon joins two hidden chat channels
-- (removed from every chat window): TrueshotLodge, for everyone, and one for the zone you are in (TrueshotLodge1411 in
-- Durotar, switched as you move, joined as a temporary channel), which reaches the players around you even where the
-- global one does not. Both are kept after every other channel you are in, so they never take the numbers of the
-- game's own channels (General, Trade, ...). Each
-- entry the collector records goes out once per session (no heartbeats) to both channels and, while you are in a
-- group, to the group (party, raid or instance). With "Collect Data From Others" on (Advanced Options, off by
-- default), entries from other users are added to the collected data with `shared_by` (who sent it); they never
-- replace your own records and are never sent on again (nothing is relayed: an entry travels one hop).
--
-- The TrueshotLodge users you hear from are remembered (saved) and the ones the channels do not seem to reach (not
-- heard on a channel in the last 10 minutes) also get each update by whisper, which reaches them in any zone. The
-- moderators (MODERATORS below) are whispered whenever they are online. Whispering someone who is offline makes the
-- game say "No player named 'X' is currently playing.": they are forgotten then (moderators are only
-- skipped for 10 minutes), and that line is hidden. The addon says hello once when it loads in, so the users who hear
-- it remember you (and whisper a welcome back so you know them).
--
-- To keep the traffic small: entries are packed several to a message (one per line, up to 255 bytes), the channels
-- and group come first and whispers after them, whispers are limited to WHISPERS_PER_MINUTE, and everything is paced
-- (a burst of BURST, then one message every SEND_EVERY seconds; a throttled send waits).
--
-- A message is lines of "<kind>|1,<field>,<field>,...", fields percent-escaped (so no field holds a line break):
--   C  wild sighting   id, name, family, level min, level max, classification, attack speed, uiMapID, x, y, type
--   T  tame            npc id, name, family, level, classification, creature speed, pet level, pet family, pet attack
--                      speed, uiMapID, x, y, tamed (time); then ";" and the spells: spell id:rank:passive, "/"-separated
--   R  pet trainer     id, name, title, level, faction, uiMapID, x, y, subzone
--   S  trainer service trainer id, spell id, name, rank, price (copper), required level, status, pet ability (1/0)
--   B  Beast Training  spell id, name, rank, price (copper), required level, status
--   H  hello           addon version (when the addon loads in); answered with a whispered
--   W  welcome         addon version
--   P  ping            token (/tsl debug shared ping); answered with a whispered
--   Q  answer          token

-- The moderators: characters that are whispered every update whenever they are online (they collect the data for
-- the website). One name per line, e.g.  "Name",
local MODERATORS = {
}

local PREFIX = "TrueshotLodge"
local CHANNEL = "TrueshotLodge"
local MAX_BYTES = 255
local SEND_EVERY = 0.5 -- seconds between messages (a burst of up to BURST goes out at once)
local BURST = 4
local QUEUE_LIMIT = 400 -- lines waiting to be broadcast
local WHISPER_LIMIT = 60 -- lines waiting to be whispered, per user (the oldest go first when it is full)
local WHISPERS_PER_MINUTE = 30
local CHANNEL_REACH = 600 -- seconds: a user heard on a channel this recently is reached by the channels
local OFFLINE_SKIP = 600 -- seconds a moderator is skipped after the game says they are not playing
local THROTTLED = { [3] = true, [8] = true } -- SendAddonMessage results: addon / channel message throttle

local frame = CreateFrame("Frame")
local enabled = false
local queue = {} -- lines to broadcast, oldest first
local pending, pendingOrder = {}, {} -- name -> lines to whisper them; the names in turn
local sent = {} -- lines already sent this session
local tokens, tokenAt, blockedUntil = BURST, 0, 0
local whisperTimes = {} -- GetTime() of the whispers in the last minute
local ticker, joinTimer

-- What /tsl debug shared reports.
local stats = { sent = 0, failed = 0, throttled = 0, received = 0, added = 0, echoes = 0, dropped = {}, lastResult = nil,
  joinTries = 0, moves = 0, cleaned = 0, pings = {}, answers = {}, hellos = {}, routes = {}, forgotten = {}, lines = 0 }

local function Drop(reason)
  stats.dropped[reason] = (stats.dropped[reason] or 0) + 1
end

local function Clock()
  return date and date("%H:%M:%S") or true
end

-- ----------------------------------------------------------------------------
-- The TrueshotLodge users you know (saved: DB.global.share_peers, name -> { first, last } (time()))
-- ----------------------------------------------------------------------------

local PEERS_KEPT = 50 -- remembered
local PEERS_WHISPERED = 25 -- whispered each update at most (besides the moderators)
local whispered = {} -- name -> GetTime() of the last whisper (to tell an "is not playing" answer to ours)
local heardOnChannel = {} -- name -> GetTime() they were last heard on one of the channels
local offlineUntil = {} -- name -> GetTime() until which a moderator is skipped

local isModerator = {}
for _, name in ipairs(MODERATORS) do isModerator[name] = true end

local function Peers()
  DB.global.share_peers = DB.global.share_peers or {}
  return DB.global.share_peers
end

local function RememberPeer(name)
  if not name or name == "" or Addon:IsPlayerName(name) then return end
  offlineUntil[name] = nil -- heard from them: they are online
  local peers = Peers()
  local peer = peers[name]
  if not peer then
    peer = { first = time() }
    peers[name] = peer
    Addon:Debug("share: now know", name, "has TrueshotLodge")
  end
  peer.last = time()
  -- Keep the list bounded: forget the ones heard from longest ago.
  local count, oldest, oldestAt = 0, nil, math.huge
  for other, info in pairs(peers) do
    count = count + 1
    if (info.last or 0) < oldestAt then oldest, oldestAt = other, info.last or 0 end
  end
  if count > PEERS_KEPT and oldest then peers[oldest] = nil end
end

-- The users an update is whispered to: the moderators (unless known to be offline), and the users you
-- know the channels do not seem to reach (not heard on a channel lately), the ones heard from most recently first.
-- Each only while its Data Sharing option is on: TSL Moderators, and Same Shard for the users.
local function WhisperNames()
  local now, me = GetTime(), Addon:PlayerName()
  local names, seen = {}, {}
  for _, name in ipairs(DB.global.share_moderators ~= false and MODERATORS or {}) do
    if name ~= me and not (offlineUntil[name] and now < offlineUntil[name]) then
      names[#names + 1] = name
      seen[name] = true
    end
  end
  local list = {}
  for name, info in pairs(DB.global.share_shard ~= false and Peers() or {}) do
    local reached = heardOnChannel[name] and now - heardOnChannel[name] < CHANNEL_REACH
    if not seen[name] and not reached then list[#list + 1] = { name = name, last = info.last or 0 } end
  end
  table.sort(list, function(a, b) return a.last > b.last end)
  for i = 1, math.min(#list, PEERS_WHISPERED) do names[#names + 1] = list[i].name end
  return names
end

-- ----------------------------------------------------------------------------
-- The wire format
-- ----------------------------------------------------------------------------

local function Escape(value)
  if value == nil then return "" end
  if type(value) == "number" then
    value = value == math.floor(value) and tostring(value) or ("%.2f"):format(value)
  end
  return (tostring(value):gsub("[%%,|;/:%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(value)
  return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Splits on a single plain character.
local function Split(text, sep)
  local parts, start = {}, 1
  while true do
    local at = text:find(sep, start, true)
    if not at then
      parts[#parts + 1] = text:sub(start)
      return parts
    end
    parts[#parts + 1] = text:sub(start, at - 1)
    start = at + 1
  end
end

local function Join(kind, fields)
  local escaped = {}
  for i = 1, fields.n or #fields do escaped[i] = Escape(fields[i]) end
  return kind .. "|1," .. table.concat(escaped, ",")
end

local function Text(value)
  if value == nil or value == "" then return nil end
  return Unescape(value)
end

local function Number(value)
  return value ~= nil and value ~= "" and tonumber(value) or nil
end

local function Pack(...) return { n = select("#", ...), ... } end

local ENCODE = {
  creature = function(c)
    return Join("C", Pack(c.id, c.name, c.family, c.level_min, c.level_max, c.classification, c.mainhand_speed,
      c.ui_map_id or next(c.zones or {}), c.x, c.y, c.creature_type))
  end,
  tame = function(t)
    local spells = {}
    for _, spell in ipairs(t.spells or {}) do
      spells[#spells + 1] = Escape(spell.spell_id) .. ":" .. Escape(spell.rank) .. ":" .. (spell.passive and "1" or "0")
    end
    return Join("T", Pack(t.npc_id, t.name, t.family, t.level, t.classification, t.creature_speed, t.pet_level,
      t.pet_family, t.attack_speed, t.ui_map_id, t.x, t.y, t.tamed)) .. ";" .. table.concat(spells, "/")
  end,
  trainer = function(r)
    return Join("R", Pack(r.id, r.name, r.title, r.level, r.faction, r.ui_map_id, r.x, r.y, r.subzone))
  end,
  service = function(s)
    return Join("S", Pack(s.trainer_id, s.spell_id, s.name, s.rank, s.cost, s.required_level, s.category,
      s.pet_ability and 1 or 0))
  end,
  training = function(b)
    return Join("B", Pack(b.spell_id, b.name, b.rank, b.cost, b.required_level, b.category))
  end,
}

-- ----------------------------------------------------------------------------
-- Routes: the global channel, your zone's channel, your group, whispers
-- ----------------------------------------------------------------------------

local zoneChannel -- the name of the channel for the zone you are in ("TrueshotLodge1411"), or nil
local hidden = {} -- channel name -> true once taken out of the chat windows

-- The channel number of a joined channel, or nil.
local function ChannelId(name)
  if not name then return nil end
  local id = GetChannelName and GetChannelName(name)
  return type(id) == "number" and id > 0 and id or nil
end

-- The zone you are in, as its uiMapID: sub-maps (caves, cities' districts) are walked up to their zone.
local function ZoneMapId()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapId = C_Map.GetBestMapForUnit("player")
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
  local info = mapId and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
  while info and zoneType and info.mapType and info.mapType > zoneType and info.parentMapID and info.parentMapID > 0 do
    mapId = info.parentMapID
    info = C_Map.GetMapInfo(mapId)
  end
  return mapId
end

-- The group to send to as well, if any.
local function GroupRoute()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

local function Delivered(ok, result)
  return ok and (result == nil or result == true or result == 0)
end

local function SendTo(message, route, target, label)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, route, target)
  label = label or route
  stats.routes[label] = (stats.routes[label] or 0) + (Delivered(ok, result) and 1 or 0)
  return ok, result
end

-- Takes lines from the front of `list` into one message of at most MAX_BYTES (one line per row).
local function Packed(list)
  local lines, size = {}, 0
  while #list > 0 and (#lines == 0 or size + 1 + #list[1] <= MAX_BYTES) do
    local line = table.remove(list, 1)
    size = size + (#lines > 0 and 1 or 0) + #line
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n"), lines
end

-- Puts lines back at the front of `list` (a throttled send).
local function Unpack(list, lines)
  for i = #lines, 1, -1 do table.insert(list, 1, lines[i]) end
end

local function WhisperBudget(now)
  for i = #whisperTimes, 1, -1 do
    if now - whisperTimes[i] > 60 then table.remove(whisperTimes, i) end
  end
  return #whisperTimes < WHISPERS_PER_MINUTE
end

-- The next user with lines waiting to be whispered (in turn), or nil.
local function NextWhisper()
  while #pendingOrder > 0 do
    local name = table.remove(pendingOrder, 1)
    if pending[name] and #pending[name] > 0 then return name end
    pending[name] = nil
  end
end

-- Sends what is queued: the broadcasts first (to every route there is: the global channel, the zone channel, the
-- group), then the whispers, each message packed with as many lines as fit. At most BURST messages at once and then
-- one every SEND_EVERY seconds; whispers at most WHISPERS_PER_MINUTE. A throttled message waits.
local function Pump()
  if not enabled or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local now = GetTime()
  if now < blockedUntil then return end
  tokens = math.min(BURST, tokens + (now - tokenAt) / SEND_EVERY)
  tokenAt = now
  while tokens >= 1 do
    -- The routes the Data Sharing options allow: Same Shard (the global channel), Same Zone, Same Group. (The
    -- channels are joined either way, to hear what others send.)
    local options = DB.global
    local global = options.share_shard ~= false and ChannelId(CHANNEL) or nil
    local zone = options.share_zone ~= false and ChannelId(zoneChannel) or nil
    local group = options.share_group ~= false and GroupRoute() or nil
    local message, lines, list, target
    if #queue > 0 and (global or zone or group) then
      list = queue
    else
      target = WhisperBudget(now) and NextWhisper()
      if not target then return end -- nothing to send now (or no route yet: it waits)
      list = pending[target]
    end
    message, lines = Packed(list)

    local any, throttled, lastOk, lastResult = false, false, true, nil
    local function try(route, to, label)
      if throttled then return end
      local ok, result = SendTo(message, route, to, label)
      lastOk, lastResult = ok, result
      if ok and THROTTLED[tonumber(result) or -1] then throttled = true end
      any = any or Delivered(ok, result)
    end
    if target then
      whispered[target] = now
      whisperTimes[#whisperTimes + 1] = now
      try("WHISPER", target, "whisper")
      if #list > 0 then pendingOrder[#pendingOrder + 1] = target else pending[target] = nil end
    else
      if global then try("CHANNEL", global, "global channel") end
      if zone then try("CHANNEL", zone, "zone channel") end
      if group then try(group) end
    end
    stats.lastResult = lastOk and tostring(lastResult) or ("error: " .. tostring(lastResult))
    if throttled and not any then
      stats.throttled = stats.throttled + 1
      Unpack(list, lines)
      if target and #list == #lines then table.insert(pendingOrder, 1, target) end
      blockedUntil = now + 2
      return
    end
    tokens = tokens - 1
    if any then
      stats.sent = stats.sent + 1
      stats.lines = stats.lines + #lines
      Addon:Debug("share: sent", #lines, "line(s)" .. (target and (" to " .. target) or ""), message:sub(1, 50))
    else
      stats.failed = stats.failed + 1
      Addon:Debug("share: could not send (" .. tostring(lastResult) .. "):", message:sub(1, 50))
    end
  end
end

-- Queues a line: broadcast it (unless `onlyTo`), and with `whisper` also whisper it to the users the channels do
-- not reach (see WhisperNames); with `onlyTo`, whisper it to that user only. `first` puts it at the front.
function Share:Queue(line, whisper, first, onlyTo)
  local function add(list, limit)
    if #list >= limit then table.remove(list, 1) end
    if first then table.insert(list, 1, line) else list[#list + 1] = line end
  end
  local function whisperTo(name)
    if not pending[name] then
      pending[name] = {}
      pendingOrder[#pendingOrder + 1] = name
    end
    add(pending[name], WHISPER_LIMIT)
  end
  if onlyTo then
    whisperTo(onlyTo)
  else
    add(queue, QUEUE_LIMIT)
    if whisper then
      for _, name in ipairs(WhisperNames()) do whisperTo(name) end
    end
  end
  Pump()
end

-- Sends an entry the collector recorded (kind: creature, tame, trainer, service, training), once per session.
function Share:Send(kind, entry)
  if not (enabled and entry and ENCODE[kind]) then return end
  local ok, line = pcall(ENCODE[kind], entry)
  if not ok or not line then return end
  if #line > MAX_BYTES then
    return Addon:Debug("share: entry too long to send (" .. #line .. " bytes):", line:sub(1, 40))
  end
  if sent[line] then return end
  sent[line] = true
  Share:Queue(line, true)
end

-- Says you are here: once when the addon loads in (see the header).
local function Hello()
  Share:Queue("H|1," .. Escape(Addon.VERSION or "?"), true)
end

-- /tsl debug shared ping: a test message every TrueshotLodge user who hears it answers.
function Share:Ping()
  if not enabled then return print(Addon.TITLE .. " share: not sharing (Collect Mode is off)") end
  Share:Queue("P|1," .. math.floor(GetTime() * 1000), true, true)
  print(Addon.TITLE .. " share: ping sent (channels, group and " .. #WhisperNames()
    .. " whispered users); anyone who hears it answers (see /tsl debug shared)")
end

-- ----------------------------------------------------------------------------
-- The channels
-- ----------------------------------------------------------------------------

-- Takes a channel out of every chat window: it carries addon messages only.
local function HideChannel(name)
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    if RemoveChatWindowChannel then pcall(RemoveChatWindowChannel, i, name) end
    local chatFrame = _G["ChatFrame" .. i]
    if chatFrame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, chatFrame, name) end
  end
  hidden[name] = true
end

-- The global channel is joined as a permanent channel; a zone channel as a temporary one, so the game does not
-- save it and join it again at the next login.
local function JoinChannel(name, temporary)
  stats.joinTries = stats.joinTries + 1
  local frameId = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME:GetID() or 1
  local first, second = JoinPermanentChannel, JoinTemporaryChannel
  if temporary then first, second = second, first end
  local join = first or second
  if join then pcall(join, name, nil, frameId, 1) end
  if ChannelId(name) then Addon:Debug("share: joined the", name, "channel (" .. ChannelId(name) .. ")") end
end

local function LeaveChannel(name)
  if name and ChannelId(name) and LeaveChannelByName then
    pcall(LeaveChannelByName, name)
    Addon:Debug("share: left the", name, "channel")
  end
  if name then hidden[name] = nil end
end

-- The channels you are in, in number order: { { id = 1, name = "General - Durotar" }, ... }, or nil when the game
-- does not give the list.
local function ChannelList()
  if not GetChannelList then return nil end
  local ok, list = pcall(function() return { GetChannelList() } end)
  if not ok or #list % 3 ~= 0 then return nil end
  local channels = {}
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    if Addon:IsSecret(id) or Addon:IsSecret(name) or type(id) ~= "number" or type(name) ~= "string" then return nil end
    channels[#channels + 1] = { id = id, name = name }
  end
  table.sort(channels, function(a, b) return a.id < b.id end)
  return channels
end

-- Where a channel goes in the order: everyone else's first (0), then the global channel (1), then the zone ones (2).
local function ChannelRank(name)
  local lower = name:lower()
  if lower == CHANNEL:lower() then return 1 end
  if lower:match("^" .. CHANNEL:lower() .. "%d+$") then return 2 end
  return 0
end

-- Keeps our channels after every other channel, so they never hold the low numbers the game's own channels
-- (General, Trade, LocalDefense, LookingForGroup) and your own use. A channel joined gets the lowest free number,
-- so after any channel joins or leaves, ours are swapped past the others (the order of the others is kept).
local function MoveChannelsToEnd()
  local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
  local channels = enabled and swap and ChannelList()
  if not channels then return end
  for i = 2, #channels do
    local j = i
    while j > 1 and ChannelRank(channels[j].name) < ChannelRank(channels[j - 1].name) do
      local before, after = channels[j - 1], channels[j]
      if not pcall(swap, before.id, after.id) then return end
      Addon:Debug("share: moved", before.name, "from", before.id, "to", after.id)
      before.name, after.name = after.name, before.name
      stats.moves = stats.moves + 1
      j = j - 1
    end
  end
end

-- Moves the channels a moment after the list changes (one move for a burst of changes).
local moveTimer
local function ScheduleMove()
  if moveTimer or not enabled then return end
  moveTimer = C_Timer.NewTimer(0.2, function()
    moveTimer = nil
    MoveChannelsToEnd()
  end)
end

-- Earlier versions joined the zone channels as permanent ones, which the game joins again at login. Every zone
-- channel of ours but the current zone's is left: once, and again after the channel list changes.
local cleanedUp = false
local function LeaveOldZoneChannels()
  if cleanedUp then return end
  local channels = ChannelList()
  if not channels then return end
  cleanedUp = true
  for _, channel in ipairs(channels) do
    if ChannelRank(channel.name) == 2 and channel.name:lower() ~= (zoneChannel or ""):lower() then
      LeaveChannel(channel.name)
      stats.cleaned = stats.cleaned + 1
    end
  end
end

-- Keeps you in the global channel and in the channel of the zone you are in (leaving the last zone's), each hidden
-- from the chat windows. Runs every few seconds, and soon after a zone change.
local function Upkeep()
  if not enabled then return end
  local zone = ZoneMapId()
  local name = zone and (CHANNEL .. zone) or nil
  if name ~= zoneChannel then
    LeaveChannel(zoneChannel)
    zoneChannel = name
  end
  LeaveOldZoneChannels()
  for _, channelName in ipairs({ CHANNEL, zoneChannel }) do
    if not ChannelId(channelName) then
      JoinChannel(channelName, channelName == zoneChannel)
      ScheduleMove()
    end
    if ChannelId(channelName) and not hidden[channelName] then HideChannel(channelName) end
  end
  Pump()
end

-- Turned on and off with collecting.
local UPKEEP_EVERY = 10
-- Entries an earlier version took in from your own messages (marked shared by you): a tame copying one of yours goes,
-- anything else is yours again.
local function CleanOwnShared()
  if not Addon:PlayerName() or not DB.global then return end
  local function mine(by) return Addon:IsPlayerName(by) end
  -- Your own name heard back on the channel before your full name was known: not another user.
  for name in pairs(Peers()) do
    if mine(name) then Peers()[name] = nil end
  end
  local tames = DB.collected.tames or {}
  local own = {}
  for _, t in ipairs(tames) do
    if not t.shared_by then own[tostring(t.npc_id) .. "|" .. tostring(t.tamed)] = true end
  end
  local removed = 0
  for i = #tames, 1, -1 do
    local t = tames[i]
    if mine(t.shared_by) then
      if own[tostring(t.npc_id) .. "|" .. tostring(t.tamed)] then
        table.remove(tames, i)
        removed = removed + 1
      else
        t.shared_by = nil
      end
    end
  end
  for _, store in ipairs({ "creatures", "trainers", "beast_training" }) do
    for _, entry in pairs(DB.collected[store] or {}) do
      if type(entry) == "table" and mine(entry.shared_by) then entry.shared_by = nil end
    end
  end
  if removed > 0 then
    Addon:Debug("share: removed", removed, "tame(s) that were copies of your own")
    Addon:GetModule("Collector"):NotifyChanged()
  end
end

function Share:SetEnabled(on)
  on = on and true or false
  if on == enabled then return end
  enabled = on
  if on then
    pcall(CleanOwnShared)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHANNEL_COUNT_UPDATE")
    frame:RegisterEvent("CHANNEL_UI_UPDATE")
    tokenAt = GetTime()
    ticker = ticker or C_Timer.NewTicker(SEND_EVERY, Pump)
    -- The first try waits until the game's own channels are in (a few seconds after login).
    if joinTimer then joinTimer:Cancel() end
    joinTimer = C_Timer.NewTicker(UPKEEP_EVERY, Upkeep)
    C_Timer.NewTimer(IsLoggedIn and IsLoggedIn() and 1 or 5, function()
      Upkeep()
      Hello()
    end)
  else
    frame:UnregisterEvent("CHAT_MSG_ADDON")
    frame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    frame:UnregisterEvent("CHANNEL_COUNT_UPDATE")
    frame:UnregisterEvent("CHANNEL_UI_UPDATE")
    if ticker then ticker:Cancel() ticker = nil end
    if joinTimer then joinTimer:Cancel() joinTimer = nil end
    if moveTimer then moveTimer:Cancel() moveTimer = nil end
    queue, pending, pendingOrder = {}, {}, {}
    LeaveChannel(zoneChannel)
    LeaveChannel(CHANNEL)
    zoneChannel = nil
  end
end

-- ----------------------------------------------------------------------------
-- Receiving
-- ----------------------------------------------------------------------------

local function KnownFamily(family)
  return family ~= nil and Addon.TameableFamilies ~= nil and Addon.TameableFamilies[family] ~= nil
end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Each kind: fields -> added to the collected data. Returns true when something was added or widened.
local MERGE = {
  C = function(f, sender)
    local id = Number(f[1])
    local family = Text(f[3])
    if not id or id <= 0 or Addon.IGNORED_NPC_IDS[id] or not KnownFamily(family) then return end
    local creatures = DB.collected.creatures
    local key = tostring(id)
    local low, high, zone = Number(f[4]), Number(f[5]), Number(f[8])
    local c = creatures[key]
    if c then
      -- Only widen what is there (the level range, the zones); your own record keeps the rest.
      local changed = false
      if low and (not c.level_min or low < c.level_min) then c.level_min, changed = low, true end
      if high and (not c.level_max or high > c.level_max) then c.level_max, changed = high, true end
      if zone then
        c.zones = c.zones or {}
        if not c.zones[zone] then c.zones[zone], changed = true, true end
      end
      return changed
    end
    creatures[key] = {
      id = id, name = Text(f[2]), family = family, level_min = low, level_max = high, classification = Text(f[6]),
      mainhand_speed = Number(f[7]), ui_map_id = zone, zones = zone and { [zone] = true } or {}, x = Number(f[9]),
      y = Number(f[10]), creature_type = Text(f[11]), collected = time(), shared_by = sender,
    }
    return true
  end,
  T = function(f, sender, spellText)
    local id = Number(f[1])
    if not id or id <= 0 or Addon.IGNORED_NPC_IDS[id] then return end
    local tamed = Number(f[13])
    DB.collected.tames = DB.collected.tames or {}
    for _, t in ipairs(DB.collected.tames) do
      if t.npc_id == id and t.tamed == tamed and (t.shared_by == sender or not t.shared_by) then return end -- have it
    end
    local spells = {}
    for _, part in ipairs(spellText ~= "" and Split(spellText, "/") or {}) do
      local bits = Split(part, ":")
      local spellId = Number(bits[1])
      if spellId and spellId > 0 then
        spells[#spells + 1] = { spell_id = spellId, name = SpellName(spellId) or ("Spell " .. spellId), rank = Text(bits[2]),
          passive = bits[3] == "1" or nil }
      end
    end
    table.insert(DB.collected.tames, {
      npc_id = id, name = Text(f[2]), family = Text(f[3]), level = Number(f[4]), classification = Text(f[5]),
      creature_speed = Number(f[6]), pet_level = Number(f[7]), pet_family = Text(f[8]), attack_speed = Number(f[9]),
      ui_map_id = Number(f[10]), x = Number(f[11]), y = Number(f[12]), tamed = tamed, spells = spells, shared_by = sender,
    })
    return true
  end,
  R = function(f, sender)
    local id = Number(f[1])
    if not id or id <= 0 then return end
    local trainers = DB.collected.trainers
    local r = trainers[id]
    if r and not r.shared_by then return end -- your own
    r = r or { id = id, services = {}, first_seen = time() }
    trainers[id] = r
    r.name, r.title, r.level, r.faction = Text(f[2]), Text(f[3]), Number(f[4]), Text(f[5])
    r.ui_map_id, r.x, r.y, r.subzone = Number(f[6]), Number(f[7]), Number(f[8]), Text(f[9])
    r.last_seen, r.shared_by = time(), sender
    return true
  end,
  S = function(f, sender)
    local trainerId, spellId = Number(f[1]), Number(f[2])
    if not trainerId or trainerId <= 0 then return end
    local trainers = DB.collected.trainers
    local r = trainers[trainerId]
    if r and not r.shared_by then return end -- your own
    r = r or { id = trainerId, services = {}, first_seen = time(), shared_by = sender }
    trainers[trainerId] = r
    r.services = r.services or {}
    local entry = {
      name = Text(f[3]), rank = Text(f[4]), spell_id = spellId, cost = Number(f[5]), required_level = Number(f[6]),
      category = Text(f[7]), pet_ability = f[8] == "1" or nil,
    }
    for i, service in ipairs(r.services) do
      if service.name == entry.name and service.rank == entry.rank then
        r.services[i] = entry
        return true
      end
    end
    r.services[#r.services + 1] = entry
    return true
  end,
  B = function(f, sender)
    local name, rank = Text(f[2]), Text(f[3])
    if not name then return end
    local book = DB.collected.beast_training
    local key = name .. "|" .. tostring(rank or "")
    if book[key] then return end -- yours (or already shared)
    book[key] = { name = name, rank = rank, spell_id = Number(f[1]), cost = Number(f[4]), required_level = Number(f[5]),
      category = Text(f[6]), last_seen = time(), shared_by = sender }
    return true
  end,
}

-- Whether an addon message came over our channel: by its name, or by its number when the game leaves the name out
-- (it can: QuestTogether checks the number the same way).
local function IsOurChannel(name, localId)
  if type(name) == "string" and name ~= "" then
    local base = (name:match("^%d+%.%s*(.+)$") or name):lower()
    return base == CHANNEL:lower() or (zoneChannel ~= nil and base == zoneChannel:lower())
  end
  local id = tonumber(localId)
  return id ~= nil and id > 0 and (id == ChannelId(CHANNEL) or id == ChannelId(zoneChannel))
end

-- One line of a message from `who`.
local function ReceiveLine(line, who, channel, via)
  local kind, version, rest = line:match("^(%u)|(%d+),(.*)$")
  if not kind then return Drop("unknown message") end
  -- Hello: they just loaded in. Whisper a welcome back so they know you (not to a whispered hello: they know you).
  if kind == "H" then
    stats.hellos[who] = Clock()
    if channel ~= "WHISPER" then Share:Queue("W|1," .. Escape(Addon.VERSION or "?"), false, true, who) end
    return Addon:Debug("share: hello from", who, "(via " .. via .. ")")
  elseif kind == "W" then
    stats.hellos[who] = Clock()
    return Addon:Debug("share: welcome from", who)
  end
  -- A test ping: answer it (once per ping, by whisper), whatever the options. An answer to yours: say who heard it.
  if kind == "P" then
    stats.pings[who] = Clock()
    local answer = "Q|1," .. (rest or "")
    if not sent[answer .. who] then
      sent[answer .. who] = true
      Share:Queue(answer, false, true, who)
    end
    return print(Addon.TITLE .. " share: ping from " .. who .. " (via " .. via .. ")")
  elseif kind == "Q" then
    stats.answers[who] = Clock()
    return print(Addon.TITLE .. " share: " .. who .. " heard your ping (via " .. via .. ")")
  end
  if not (DB.global and DB.global.collect and DB.global.receive_shared) then
    return Drop("Collect Data From Others is off")
  end
  if version ~= "1" or not MERGE[kind] then return Drop("unknown message") end
  local spellText = ""
  if kind == "T" then
    local fieldsText, spells = rest:match("^(.-);(.*)$")
    rest, spellText = fieldsText or rest, spells or ""
  end
  local ok, added = pcall(MERGE[kind], Split(rest, ","), who, spellText)
  if not ok then
    return Addon:Debug("share: could not read a message from", who, "-", tostring(added))
  end
  if added then
    stats.added = stats.added + 1
    Addon:Debug("share: received", kind, "from", who)
    Addon:GetModule("Collector"):NotifyChanged()
  else
    Drop("already had it, or not a pet family (" .. kind .. ")")
  end
end

local function Receive(prefix, message, channel, sender, _, _, localId, channelName)
  if prefix ~= PREFIX or not enabled then return end
  if Addon:IsSecret(message) or Addon:IsSecret(sender) or Addon:IsSecret(channelName) or Addon:IsSecret(localId) then
    return Drop("hidden by the game (in combat)")
  end
  if type(sender) ~= "string" then return Drop("no sender") end
  -- The sender is the one the game reports, never anything in the message.
  -- Their full name, "First Surname" (WoW Forever has surnames; older payloads send "First-Surname").
  local who = Addon:NormalizeName(sender)
  -- Your own messages come back from the channel (and the group).
  local me = Addon:PlayerName()
  if Addon:IsPlayerName(who) then
    stats.echoes = stats.echoes + 1
    return
  end
  stats.received = stats.received + 1
  stats.lastFrom = who
  local fromGroup = channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" or channel == "WHISPER"
  if not fromGroup and (channel ~= "CHANNEL" or not IsOurChannel(channelName, localId)) then
    return Drop(("not our channel (%s %s %s)"):format(tostring(channel), tostring(localId), tostring(channelName)))
  end
  if type(message) ~= "string" or #message > MAX_BYTES then return Drop("bad message") end

  RememberPeer(who) -- they have TrueshotLodge
  if channel == "CHANNEL" then heardOnChannel[who] = GetTime() end -- the channels reach them
  local via = fromGroup and channel or "the channel"
  for line in message:gmatch("[^\n]+") do
    if sent[line] then
      -- A line you sent yourself this session, back under another name: it is yours, not shared.
      stats.echoes = stats.echoes + 1
      Addon:Debug("share: your own line came back as from", who, "(you are", tostring(me) .. ")")
    else
      ReceiveLine(line, who, channel, via)
    end
  end
end

-- /tsl debug shared: what sharing is doing.
function Share:Status()
  local say = function(...) print(Addon.TITLE .. " share:", ...) end
  local global = DB.global or {}
  say("collecting", global.collect and "on" or "OFF", "| sharing", enabled and "on" or "off",
    "| Collect Data From Others", global.receive_shared and "on" or "off")
  local id, zoneId = ChannelId(CHANNEL), ChannelId(zoneChannel)
  say("zone channel", tostring(zoneChannel), zoneId and ("joined as " .. zoneId) or "NOT joined")
  say("channel", CHANNEL, id and ("joined as " .. id) or ("NOT joined (join tries: " .. stats.joinTries .. ")"),
    "| prefix registered", tostring(C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
      and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)))
  local order = {}
  for _, channel in ipairs(ChannelList() or {}) do order[#order + 1] = channel.id .. " " .. channel.name end
  say("channel numbers:", #order > 0 and table.concat(order, ", ") or "unknown",
    "| moved", stats.moves, "time(s)", C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex and ""
      or "(this client cannot move channels)", "| old zone channels left", stats.cleaned)
  local waitingWhispers = 0
  for _, lines in pairs(pending) do waitingWhispers = waitingWhispers + #lines end
  say("sent", stats.sent, "messages (" .. stats.lines .. " lines) | failed", stats.failed, "| throttled", stats.throttled,
    "| waiting", #queue, "to broadcast,", waitingWhispers, "to whisper | last send result", tostring(stats.lastResult))
  local routes = {}
  for route, count in pairs(stats.routes) do routes[#routes + 1] = route .. " " .. count end
  if #routes > 0 then say("delivered by route:", table.concat(routes, ", ")) end
  local names = function(list) local t = {} for who, at in pairs(list) do t[#t + 1] = who .. " (" .. tostring(at) .. ")" end return #t > 0 and table.concat(t, ", ") or "nobody" end
  say("pings heard from:", names(stats.pings), "| answers to your pings from:", names(stats.answers))
  local known = {}
  for name in pairs(Peers()) do known[#known + 1] = name end
  table.sort(known)
  local whisperedNow = WhisperNames()
  say("TrueshotLodge users you know:", #known > 0 and table.concat(known, ", ") or "none yet")
  say("moderators:", #MODERATORS > 0 and table.concat(MODERATORS, ", ") or "none")
  say("whispered each update (moderators, and users the channels do not reach):",
    #whisperedNow > 0 and table.concat(whisperedNow, ", ") or "nobody")
  say("hellos heard from:", names(stats.hellos), "| forgotten (not playing):", names(stats.forgotten))
  say("own messages heard back from the channel", stats.echoes,
    stats.echoes > 0 and "(you are in the channel)" or "")
  say("received", stats.received, "from others", stats.lastFrom and ("(last: " .. stats.lastFrom .. ")") or "",
    "| added", stats.added)
  for reason, count in pairs(stats.dropped) do say("  not added:", reason, "x" .. count) end
end

-- "No player named 'X' is currently playing." right after whispering X: X is offline (or gone). Forget them (an
-- moderator is only skipped for a while), drop what waits for them, and hide the line (it is about our
-- hidden whisper, not one you typed).
local NOT_PLAYING
do
  local text = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
  -- The game's text with its %s for the name: everything else matched literally, the name captured.
  local before, after = text:match("^(.-)%%s(.*)$")
  local literal = function(part) return (part:gsub("([%(%)%.%%%[%]%*%+%-%?%^%$])", "%%%1")) end
  NOT_PLAYING = before and ("^" .. literal(before) .. "(.+)" .. literal(after) .. "$") or "^$"
end

local function NotPlayingFilter(_, _, message, ...)
  if Addon:IsSecret(message) or type(message) ~= "string" then return false end
  local name = message:match(NOT_PLAYING)
  if not name then return false end
  name = name:match("^([^%-]+)") or name
  local at = whispered[name]
  if not at or GetTime() - at > 15 then return false end -- not about one of ours
  whispered[name] = nil
  pending[name] = nil
  if isModerator[name] then
    offlineUntil[name] = GetTime() + OFFLINE_SKIP
    Addon:Debug("share:", name, "is not playing; skipped for a while")
  else
    if DB.global and DB.global.share_peers then DB.global.share_peers[name] = nil end
    stats.forgotten[name] = Clock()
    Addon:Debug("share: forgot", name, "(not playing)")
  end
  return true
end

do
  local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
  if add then pcall(add, "CHAT_MSG_SYSTEM", NotPlayingFilter) end
end
Share.NotPlayingFilter = NotPlayingFilter -- (for the tests)

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    Receive(...)
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    C_Timer.NewTimer(2, Upkeep) -- the map knows the new zone a moment later
  elseif event == "CHANNEL_COUNT_UPDATE" or event == "CHANNEL_UI_UPDATE" then
    if event == "CHANNEL_COUNT_UPDATE" then cleanedUp = false end
    ScheduleMove()
  end
end)
