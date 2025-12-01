-- main.lua

repeat task.wait() until game:IsLoaded()

local function httpget(u)
    return game:HttpGet(u)
end

-- Load UI module
local UI = (function()
    local ok, ret = pcall(function()
        return loadstring(httpget("https://raw.githubusercontent.com/wtfx0rzz-mark/sponge-dsjfhkdjf-bob-798347fsss/main/ui.lua"))()
    end)

    if ok and type(ret) == "table" then
        return ret
    end

    warn("ui.lua load error: " .. tostring(ret))
    error("ui.lua failed to load")
end)()

-- Core context
local C = {}
C.Services = {
    Players = game:GetService("Players"),
    RS      = game:GetService("ReplicatedStorage"),
    WS      = game:GetService("Workspace"),
    Run     = game:GetService("RunService"),
}
C.LocalPlayer = C.Services.Players.LocalPlayer
C.Config      = C.Config or {}
C.State       = C.State or {}

_G.C  = C
_G.R  = _G.R or {}
_G.UI = UI

do
    local tab = UI and UI.Tabs and UI.Tabs.Main
    if tab then
        tab:Paragraph({
            Title = "Welcome",
            Desc  = "Welcome",
        })
    end
end

-- Modules to load
local paths = {
    Player  = "https://raw.githubusercontent.com/wtfx0rzz-mark/sponge-dsjfhkdjf-bob-798347fsss/main/player.lua",
    Actions = "https://raw.githubusercontent.com/wtfx0rzz-mark/sponge-dsjfhkdjf-bob-798347fsss/main/actions.lua",
    Visuals = "https://raw.githubusercontent.com/wtfx0rzz-mark/sponge-dsjfhkdjf-bob-798347fsss/main/visuals.lua",
}

for name, url in pairs(paths) do
    local ok, mod = pcall(function()
        return loadstring(httpget(url))()
    end)
    if ok and type(mod) == "function" then
        pcall(mod, _G.C, _G.R, _G.UI)
    else
        warn(("Failed to load module %s from %s: %s"):format(name, url, tostring(mod)))
    end
end
