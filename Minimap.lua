-- Beast Lore Plus: LibDataBroker launcher + LibDBIcon minimap button
local _, BLP = ...

local Minimap = {}
BLP.Minimap = Minimap

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

function Minimap.SetShown(show)
    BLP.db.minimap.hide = not show
    if DBIcon then
        if show then DBIcon:Show("BeastLorePlus") else DBIcon:Hide("BeastLorePlus") end
    end
    if BLP.Options and BLP.Options.Sync then BLP.Options.Sync() end
end

BLP.OnInit(function()
    if not (LDB and DBIcon) then return end -- libraries missing (dev checkout): slash commands still work
    local launcher = LDB:NewDataObject("BeastLorePlus", {
        type = "launcher",
        text = "Beast Lore Plus",
        icon = BLP.LOGO,
        OnClick = function(_, button)
            if button == "RightButton" then
                if BLP.Options then BLP.Options.Open() end
            else
                BLP.Finder.Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Beast Lore Plus")
            tt:AddLine("Left-click: Ability Finder", 1, 1, 1)
            tt:AddLine("Right-click: options", 1, 1, 1)
            if BLP.isHunter and not (BLP.char and BLP.char.scanned) then
                tt:AddLine(BLP.L.OPEN_TRAINING, 0.6, 0.6, 0.6, true)
            end
        end,
    })
    DBIcon:Register("BeastLorePlus", launcher, BLP.db.minimap)
end)
