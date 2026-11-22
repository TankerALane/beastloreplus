-- Beast Lore Plus: options panel (Settings canvas, with the old Interface Options fallback)
local _, BLP = ...

local Options = {}
BLP.Options = Options

local panel, category
local checks = {}

local SETTINGS = {
    { key = "minimap", label = "Show the minimap button",
      get = function() return not BLP.db.minimap.hide end,
      set = function(v) BLP.Minimap.SetShown(v) end },
    { key = "share", label = "Share tames with other Beast Lore Plus users",
      tip = "Sends the abilities of beasts you tame to your guild and the hidden BeastLorePlus channel, and joins that channel. Reports from others never change the bundled data.",
      get = function() return BLP.db.share end,
      set = function(v) BLP.Community.SetSharing(v) end },
    { key = "showUnknown", label = "Show grey \"?\" rows (status unknown until you open Beast Training)",
      get = function() return BLP.db.showUnknown end,
      set = function(v) BLP.db.showUnknown = v end },
    { key = "showNpcId", label = "Show the beast's NPC ID (debug)",
      get = function() return BLP.db.showNpcId end,
      set = function(v) BLP.db.showNpcId = v BLP.Finder.Refresh() end },
}

function Options.Sync()
    for _, cb in ipairs(checks) do cb:SetChecked(cb.setting.get() and true or false) end
end

local function build()
    panel = CreateFrame("Frame")
    panel.name = "Beast Lore Plus"

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture(BLP.LOGO)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
    title:SetText("Beast Lore Plus")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(("Version %s \226\128\148 Decoupled Lane Studio \226\128\148 support@decoupledlane.com"):format(BLP.version))

    local y = -84
    for _, s in ipairs(SETTINGS) do
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        cb.setting = s
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(s.label)
        cb:SetScript("OnClick", function(self) s.set(self:GetChecked() and true or false) Options.Sync() end)
        if s.tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(s.label)
                GameTooltip:AddLine(s.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        checks[#checks + 1] = cb
        y = y - 32
    end

    local finder = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    finder:SetSize(180, 24)
    finder:SetPoint("TOPLEFT", 20, y - 12)
    finder:SetText("Open Ability Finder")
    finder:SetScript("OnClick", function() BLP.Finder.Toggle() end)

    local export = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    export:SetSize(180, 24)
    export:SetPoint("LEFT", finder, "RIGHT", 10, 0)
    export:SetText("Export tames (/blp export)")
    export:SetScript("OnClick", function() BLP.Community.ShowExport() end)

    local legend = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    legend:SetPoint("TOPLEFT", finder, "BOTTOMLEFT", 0, -20)
    legend:SetJustifyH("LEFT")
    local g = BLP.DOT_GAP
    legend:SetText(("%s%syou know this rank or higher\n%s%syou know a lower rank (upgrade)\n%s%syou have not learned it\n%s%sunknown: open Beast Training once"):format(
        BLP.DotString("known", 14), g, BLP.DotString("upgrade", 14), g, BLP.DotString("missing", 14), g,
        BLP.DotString("unknown", 14), g))
    legend:SetSpacing(4)

    panel:SetScript("OnShow", Options.Sync)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Beast Lore Plus")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options.Open()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

BLP.OnInit(function()
    local ok, err = pcall(build)
    if not ok then BLP.Print("options panel unavailable:", err) end
end)
