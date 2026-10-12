local _, Addon = ...
local DB = Addon:GetModule("DB")
local Integrity = Addon:GetModule("Integrity")

-- A tag on every record of the collected data (`sig`), so a file changed by hand before it is uploaded shows as such.
--
--   - At logout (and /reload), just before the game writes the saved file, every record is signed.
--   - At load, every record is checked: one whose tag no longer matches was changed outside the game and is marked
--     `edited = true` for good (the mark is signed with the rest, so it cannot be dropped again without the tag).
--   - The website checks the same tags on upload (app/Libraries/CollectorIntegrity.php) and shows what fails.
--   - The file also says which addon version saved it (`collected.addon`: version, saved_at, its own tag).
--
-- Not a lock: the addon's code is public, so someone determined can re-sign a forged record. It catches hand edits.
-- KEEP IN STEP with CollectorIntegrity.php: the key, the kinds, how a record is written out and the hash.

local KEY = "TrueshotLodge|collected|v1|3f9c1e7a"
-- The collected data's parts; records in a list (tames) are tagged without their position, which moves.
local KINDS = { "creatures", "tames", "trainers", "beast_training", "pets" }
local LISTS = { tames = true }

local floor, format, concat, sort = math.floor, string.format, table.concat, table.sort

-- A number as text: whole numbers without decimals, others to 6 decimals.
local function NumberText(n)
  if n ~= n or n == math.huge or n == -math.huge then return "x" end
  if n == floor(n) and math.abs(n) < 2 ^ 53 then return format("%.0f", n) end
  return format("%.6f", n)
end

local function KeyText(k)
  if type(k) == "number" then return NumberText(k) end
  if type(k) == "boolean" then return k and "true" or "false" end
  return tostring(k)
end

-- Whether a table's keys are exactly 1..n (a list).
local function IsList(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k ~= floor(k) then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

-- A value written out one fixed way: n<number>, s<length>:<text>, T/F, [list], {key=value,...} by key.
local function Canon(v, top)
  local t = type(v)
  if t == "number" then return "n" .. NumberText(v) end
  if t == "string" then return "s" .. #v .. ":" .. v end
  if t == "boolean" then return v and "T" or "F" end
  if t ~= "table" then return "?" end
  if next(v) == nil then return "{}" end
  local parts = {}
  if IsList(v) then
    for i = 1, #v do parts[i] = Canon(v[i]) end
    return "[" .. concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do
    if not (top and k == "sig") then keys[#keys + 1] = k end
  end
  sort(keys, function(a, b) return KeyText(a) < KeyText(b) end)
  for i, k in ipairs(keys) do parts[i] = KeyText(k) .. "=" .. Canon(v[k]) end
  return "{" .. concat(parts, ",") .. "}"
end

-- a XOR b for two bytes, in plain arithmetic.
local function Xor8(a, b)
  local result, bitValue = 0, 1
  for _ = 1, 8 do
    if a % 2 ~= b % 2 then result = result + bitValue end
    a, b, bitValue = floor(a / 2), floor(b / 2), bitValue * 2
  end
  return result
end

-- FNV-1a, 32 bits, as 8 hex digits. The XOR only touches the lowest byte; the multiplication is split so it stays
-- exact in Lua's numbers.
local function Hash(text)
  local h = 2166136261
  for i = 1, #text do
    local low = h % 256
    h = h - low + Xor8(low, text:byte(i))
    h = (h * 403 + (h % 256) * 16777216) % 4294967296 -- h * 16777619, mod 2^32
  end
  return format("%08x", h)
end

-- The tag of one record: its kind, its key (none in a list) and everything in it but the tag.
function Integrity:Tag(kind, key, record)
  return Hash(KEY .. "|" .. kind .. "|" .. (LISTS[kind] and "" or KeyText(key)) .. "|" .. Canon(record, true))
end

-- Calls fn(kind, key, record) for every record of the collected data.
local function EachRecord(fn)
  local collected = DB.collected
  if type(collected) ~= "table" then return end
  for _, kind in ipairs(KINDS) do
    if type(collected[kind]) == "table" then
      for key, record in pairs(collected[kind]) do
        if type(record) == "table" then fn(kind, key, record) end
      end
    end
  end
end

-- At load: marks the records changed outside the game. Records without a tag (from before tags) are left as they are.
function Integrity:Check()
  local edited = 0
  EachRecord(function(kind, key, record)
    if type(record.sig) == "string" and not record.edited and record.sig ~= self:Tag(kind, key, record) then
      record.edited = true
      edited = edited + 1
    end
  end)
  if edited > 0 then Addon:Debug("integrity:", edited, "collected record(s) were changed outside the game: marked edited") end
  return edited
end

-- At logout: signs every record, as the game is about to write the saved file, and notes which addon version saved
-- it (`addon`, tagged too): when the data changes in a way old files cannot follow, the website can ask for an upload
-- from a newer version.
function Integrity:SignAll()
  EachRecord(function(kind, key, record) record.sig = self:Tag(kind, key, record) end)
  if type(DB.collected) == "table" then
    local addon = { version = Addon.VERSION, saved_at = time() }
    addon.sig = self:Tag("addon", "", addon)
    DB.collected.addon = addon
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function()
  local ok, err = pcall(Integrity.SignAll, Integrity)
  if not ok then Addon:Debug("integrity: signing failed:", err) end
end)
