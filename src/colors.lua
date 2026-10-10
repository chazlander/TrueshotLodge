local _, Addon = ...
local Colors = Addon:GetModule("Colors")

local colorMap = {
  Primary = "FF007EA6",
  Highlight = "FFE3E34F",
  Label = "FFFFD100",
  Text = "FFF4F0EB",
  Muted = "FF808080",
  -- The state colors, meaning the same everywhere in the addon (see Colors.State):
  Default = "FFFFFFFF", -- white: nothing to say
  Complete = "FFFFD100", -- yellow: complete (known)
  Available = "FF1EFF00", -- green: available (can be learned, not yet)
  Unavailable = "FF808080", -- grey: unavailable
}

-- Default text color (replaces plain white), as `r, g, b` for tooltip APIs.
do
  local r, g, b = CreateColorFromHexString(colorMap.Text):GetRGB()
  Colors.TextRGB = { r, g, b }
end

-- A state's color as a color object, for SetVertexColor / SetTextColor: Colors.State.Available:GetRGB().
Colors.State = {}
for _, state in ipairs({ "Default", "Complete", "Available", "Unavailable" }) do
  Colors.State[state] = CreateColorFromHexString(colorMap[state])
end

for name, hex in pairs(colorMap) do
  local r, g, b = CreateColorFromHexString(hex):GetRGBAsBytes()
  local opaque = ("|cFF%.2x%.2x%.2x"):format(r, g, b) -- Built once, reused.
  Colors[name] = setmetatable({}, {
    __call = function(self, text, alpha)
      if alpha == nil or alpha == 1 then
        return opaque .. (text or "") .. "|r"
      end
      return ("|c%.2x%.2x%.2x%.2x%s|r"):format(alpha * 255, r, g, b, text or "")
    end
  })
end
