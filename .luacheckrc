std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/", "tests/" }
ignore = { "212", "213" } -- unused arguments / loop variables (event handler signatures)

globals = {
    "BeastLorePlusDB", "BeastLorePlusCharDB", "SLASH_BEASTLOREPLUS1", "SLASH_BEASTLOREPLUS2",
    "SlashCmdList",
}

read_globals = {
    "C_AddOns", "C_ChatInfo", "C_EventUtils", "C_Spell", "C_SpellBook", "C_Timer", "C_TooltipInfo",
    "C_Trainer", "Enum", "LibStub", "MenuUtil", "Settings", "TooltipDataProcessor",
    "CreateFrame", "UnitCreatureFamily", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "UISpecialFrames", "ChatFontNormal",
    "UnitClass", "UnitCastingInfo", "UnitChannelInfo", "UnitGUID", "UnitName", "UnitLevel", "UnitCreatureType", "UnitFullName",
    "GetBuildInfo", "GetTime", "GetZoneText", "GetChannelName", "GetNormalizedRealmName", "IsInGuild",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetNumCrafts", "GetCraftInfo",
    "GetCraftDisplaySkillLine", "HasPetSpells", "GetSpellBookItemName", "GetSpellInfo", "GetAddOnMetadata",
    "JoinTemporaryChannel", "JoinChannelByName", "LeaveChannelByName", "ChatFrame_RemoveChannel",
    "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "ERR_LEARN_SPELL_S", "SEARCH", "C_Map", "CreateVector2D", "UiMapPoint", "C_SuperTrack", "OpenWorldMap",
    "WorldMapFrame", "ToggleWorldMap", "BOOKTYPE_PET", "NUM_CHAT_WINDOWS", "CLOSE",
    "issecretvalue", "wipe", "tinsert", "time", "date",
}
