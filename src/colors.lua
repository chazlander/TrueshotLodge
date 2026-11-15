local _, Addon = ...
local Colors = Addon:GetModule("Colors")

-- The addon's palette: every color the addon draws with, named once. They are the website's colors too
-- (TrueshotLodge-Web/public/css/foreverscheme.css names each one's twin), so a creature's name, a count badge or a
-- faction reads the same in the game and on the site. KEEP IN STEP with that file when one changes.
--
-- Each is used three ways:
--   Colors.Gold("text")        the text wrapped in the color, for chat and font strings
--   Colors.Gold:GetRGB()       r, g, b (0-1), for SetTextColor / SetVertexColor / tooltip lines
--   Colors.Gold:GetRGBA(0.5)   r, g, b and an alpha, for SetColorTexture
-- and Colors.Gold.hex is its "AARRGGBB" text, for a "|c%s" in a format string.
local colorMap = {
  Primary = "FF007EA6", -- teal: the title accent and the chat prefix (the website's small accents)
  NPC = "FF1FA5D1", -- light blue: creature and trainer names (--ft-npc)
  Highlight = "FFE3E34F", -- pale yellow: a classification beside a level, a note that wants attention
  Label = "FFFFD100", -- gold: the label of a "Label: value" line (--ft-gold)
  Gold = "FFFFD100", -- gold: headings, what is lit or selected, a rare creature's glow (--ft-gold)
  Tan = "FFC6AF8D", -- tan: count badges and quiet buttons (--ft-tan)
  Bronze = "FFD9AD6B", -- bronze: the rings around icons (--ft-bronze)
  Metal = "FF6B4F27", -- dark bronze: thin edges (--ft-metal)
  Text = "FFF4F0EB", -- cream: body text (--surface-content)
  Muted = "FF9D9D9D", -- grey: hints and secondary text (--ft-muted)
  Disabled = "FF808080", -- darker grey: what cannot be used
  Alliance = "FF6BA6FF", -- a trainer who serves the Alliance (--ft-alliance)
  Horde = "FFFF6161", -- a trainer who serves the Horde (--ft-horde)
  Good = "FF40C040", -- green: a good verdict, a value an upload would add (--ft-good)
  Tamed = "FFB9F0C4", -- pale green: a count whose creatures are all tamed (the website's Tamed seal, .tamed-badge)
  Bad = "FFE04030", -- red: a bad verdict, what is missing or refused (--ft-bad)
  Shared = "FF3FA9F5", -- blue: an entry another TrueshotLodge user shared
  New = "FFFF8000", -- orange: the NEW badge
  Debug = "FFFF8800", -- orange: debug messages
  -- The state colors, meaning the same everywhere in the addon (see Colors.State):
  Default = "FFFFFFFF", -- white: nothing to say
  Complete = "FFFFD100", -- yellow: complete (known)
  Available = "FF1EFF00", -- green: available (can be learned, not yet)
  Unavailable = "FF808080", -- grey: unavailable
}

local colorMeta = {
  -- Colors.Gold("text"), or Colors.Gold("text", 0.5) for a see-through one.
  __call = function(self, text, alpha)
    if alpha == nil or alpha == 1 then return self.code .. (text or "") .. "|r" end
    return ("|c%.2x%s%s|r"):format(alpha * 255, self.hex:sub(3), text or "")
  end,
}
local colorMethods = {
  GetRGB = function(self) return self.r, self.g, self.b end,
  GetRGBA = function(self, alpha) return self.r, self.g, self.b, alpha or 1 end,
}

for name, hex in pairs(colorMap) do
  local color = setmetatable({ hex = hex, code = "|c" .. hex }, colorMeta) -- (the code is built once, reused)
  color.r, color.g, color.b = CreateColorFromHexString(hex):GetRGB()
  color.GetRGB, color.GetRGBA = colorMethods.GetRGB, colorMethods.GetRGBA
  Colors[name] = color
end

-- Default text color (replaces plain white), as `r, g, b` for tooltip APIs.
Colors.TextRGB = { Colors.Text:GetRGB() }

-- A state's color, by the state's name: Colors.State[Addon:RankState(...)]:GetRGB().
Colors.State = {}
for _, state in ipairs({ "Default", "Complete", "Available", "Unavailable" }) do
  Colors.State[state] = Colors[state]
end

-- A faction's color, by a trainer's `side` ("alliance", "horde"); none for both or unknown.
Colors.Side = { alliance = Colors.Alliance, horde = Colors.Horde }
