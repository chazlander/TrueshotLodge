-- luacheck (.tools/luacheck.exe): finds syntax errors and misspelled names before the addon reaches the game.
--   .tools\luacheck.exe src data
-- The push runs it first (.tools/push-local.ps1) and stops on an error. A WoW API it does not know yet shows as
-- "accessing undefined variable": when it is a real one, add it to read_globals below.

std = "lua51" -- WoW's Lua
max_line_length = false
exclude_files = { "libs/" } -- third-party (LibStub, CallbackHandler, HereBeDragons)

ignore = {
  "212", -- unused argument: event handlers and callbacks take arguments they need not use
}

-- The globals the addon writes.
globals = {
  "SlashCmdList",
  "StaticPopupDialogs",
}

-- The game's API (and the libraries' globals) the addon reads.
read_globals = {
  -- Lua extensions in WoW
  "date", "time", "strsplit", "tinsert", "wipe", "issecretvalue",

  -- C_ namespaces
  "C_AddOns", "C_ChatInfo", "C_Map", "C_MerchantFrame", "C_NamePlate", "C_Spell", "C_SpellBook", "C_StableInfo",
  "C_Timer", "C_TooltipInfo", "C_Trainer", "C_XMLUtil",

  -- Frames, mixins and UI utilities
  "ChatFrameUtil", "ClassTrainerFrame", "CreateColor", "CreateColorFromHexString", "CreateDataProvider", "CreateFrame",
  "CreateScrollBoxListLinearView", "CreateScrollBoxListTreeListView", "CreateTreeDataProvider", "DEFAULT_CHAT_FRAME",
  "Enum", "GameTooltip", "GameTooltip_Hide", "GameTooltip_SetTitle", "ListHeaderMixin", "MinimalSliderWithSteppersMixin",
  "NineSliceUtil", "ScrollUtil", "Spell", "StaticPopup_Show", "TooltipDataProcessor", "UIParent", "UISpecialFrames",
  "WorldMapFrame", "OpenWorldMap", "ToggleWorldMap",

  -- Constants and strings
  "BOOKTYPE_PET", "CANCEL", "ERR_CHAT_PLAYER_NOT_FOUND_S", "FACTION_ALLIANCE", "FACTION_HORDE", "FRIENDS_TEXTURE_ONLINE",
  "HIGHLIGHT_FONT_COLOR", "LE_PARTY_CATEGORY_INSTANCE", "NUM_CHAT_WINDOWS", "SOUNDKIT", "UNKNOWNOBJECT",

  -- Functions
  "Ambiguate", "BreakUpLargeNumbers", "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveChannel", "GetCVar",
  "GetChannelName", "GetCursorPosition", "GetFileIDFromPath", "GetMerchantItemInfo", "GetMerchantItemLink",
  "GetMerchantNumItems", "GetNumTrainerServices", "GetPetExperience", "GetPetTrainingPoints", "GetRealZoneText",
  "GetRealmName", "GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellInfo", "GetSpellTexture", "GetStablePetInfo",
  "GetSubZoneText", "GetTime", "GetTrainerServiceItemLink", "GetUnitSpeed", "HasPetSpells", "InCombatLockdown",
  "IsInGroup", "IsInRaid", "IsLoggedIn", "IsMouseButtonDown", "IsPassiveSpell", "IsPlayerSpell", "IsSpellKnown",
  "JoinPermanentChannel", "JoinTemporaryChannel", "LeaveChannelByName", "LoadAddOn", "PlaySound",
  "RemoveChatWindowChannel", "SetCVar",

  -- Units
  "UnitArmor", "UnitAttackPower", "UnitAttackSpeed", "UnitClassification", "UnitCreatureFamily", "UnitCreatureType",
  "UnitDamage", "UnitExists", "UnitFactionGroup", "UnitGUID", "UnitHealthMax", "UnitIsDead", "UnitIsPlayer", "UnitLevel",
  "UnitName", "UnitPlayerControlled", "UnitPowerMax", "UnitPowerType", "UnitReaction", "UnitResistance", "UnitSex",
  "UnitTokenFromGUID",

  -- Libraries (libs/)
  "LibStub", "HBD_PINS_WORLDMAP_SHOW_WORLD",
}
