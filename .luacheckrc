std = "lua51"
max_line_length = false
exclude_files = { "addons/GatherLite/**", "dist/**" }

-- WoW API globals the addons read
read_globals = {
    "C_Minimap", "C_SkillInfo", "C_Spell", "C_Timer",
    "CreateFrame", "GameTooltip", "GetProfessionInfo", "GetProfessions",
    "InCombatLockdown", "Minimap", "UIParent", "UnitClass", "UnitIsDeadOrGhost",
}

-- globals the addons define (slash commands must be globals)
globals = {
    "SlashCmdList",
    "SLASH_GATHERER1", "SLASH_GATHERERDIAG1",
}

files["spec/**"] = {
    std = "+busted",
    -- the mock replaces the whole client API, and specs read frames it creates
    globals = {
        "print", "CreateFrame", "Minimap", "UIParent", "GameTooltip", "SlashCmdList",
        "UnitClass", "UnitIsDeadOrGhost", "InCombatLockdown", "GetProfessions",
        "GetProfessionInfo", "C_SkillInfo", "C_Spell", "C_Minimap", "C_Timer",
    },
    read_globals = { "GathererToggleButton", "SLASH_GATHERER1" },
}
