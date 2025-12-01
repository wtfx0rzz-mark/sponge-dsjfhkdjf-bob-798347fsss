-- ui.lua

local Players = game:GetService("Players")
local lp      = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Window = WindUI:CreateWindow({
    Title            = "Mark Universal",
    Icon             = "moon",
    Author           = "Mark",
    Folder           = "Spongebob",
    Size             = UDim2.fromOffset(520, 360),
    Transparent      = false,
    Theme            = "Dark",
    Resizable        = true,
    SideBarWidth     = 150,
    HideSearchBar    = false,
    ScrollBarEnabled = true,
    User = {
        Enabled   = true,
        Anonymous = false,
        Callback  = function()
            WindUI:Notify({
                Title   = "User Info",
                Content = "Logged In As: " .. (lp.DisplayName or lp.Name),
                Duration = 2,
                Icon    = "user",
            })
        end,
    },
})

-- Main toggle key
Window:SetToggleKey(Enum.KeyCode.V)

local Tabs = {
    Main = Window:Tab({
        Title = "Main",
        Icon  = "home",
        Desc  = "Core controls",
    }),

    Player = Window:Tab({
        Title = "Player",
        Icon  = "user",
        Desc  = "Movement / utilities / godmode",
    }),

    Visuals = Window:Tab({
        Title = "Visuals",
        Icon  = "eye",
        Desc  = "ESP / tracking / visual helpers",
    }),

    Actions = Window:Tab({
        Title = "Actions",
        Icon  = "zap",
        Desc  = "Shockwave nudge and utilities",
    }),
}

return {
    Lib    = WindUI,
    Window = Window,
    Tabs   = Tabs,
}
