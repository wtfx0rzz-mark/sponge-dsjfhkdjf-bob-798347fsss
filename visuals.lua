-- visuals.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    assert(C and UI and UI.Tabs and UI.Tabs.Visuals, "visuals.lua: Visuals tab missing")

    local Services   = C.Services or {}
    local Players    = Services.Players or game:GetService("Players")
    local WS         = Services.WS      or game:GetService("Workspace")
    local Run        = Services.Run     or game:GetService("RunService")

    local lp         = C.LocalPlayer or Players.LocalPlayer
    local VisualsTab = UI.Tabs.Visuals

    --========================
    -- Shared State
    --========================
    C.State         = C.State or {}
    C.State.Toggles = C.State.Toggles or {}
    local toggles   = C.State.Toggles

    --------------------------------------------------
    -- Player Highlighter
    --------------------------------------------------
    local PLAYER_HL_NAME = "__PlayerTrackerHL__"

    local runningPlayers       = false
    local playerAddedConn      = nil
    local playerRemovingConn   = nil
    local charAddedConns       = {}

    local function ensureHighlight(character)
        if not character then return nil end
        local hl = character:FindFirstChild(PLAYER_HL_NAME)
        if not hl or not hl:IsA("Highlight") then
            hl = Instance.new("Highlight")
            hl.Name = PLAYER_HL_NAME
            hl.Adornee = character
            hl.FillTransparency    = 1       -- outline only
            hl.OutlineTransparency = 0
            hl.OutlineColor        = Color3.fromRGB(255, 255, 0)
            hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent              = character
        end
        hl.Enabled = true
        return hl
    end

    local function clearHighlight(character)
        if not character then return end
        local hl = character:FindFirstChild(PLAYER_HL_NAME)
        if hl and hl:IsA("Highlight") then
            hl:Destroy()
        end
    end

    local function attachToCharacter(plr, character)
        if not character or plr == lp then return end
        ensureHighlight(character)
    end

    local function trackPlayer(plr)
        if plr == lp then return end

        if plr.Character then
            attachToCharacter(plr, plr.Character)
        end

        if charAddedConns[plr] then
            charAddedConns[plr]:Disconnect()
        end
        charAddedConns[plr] = plr.CharacterAdded:Connect(function(ch)
            attachToCharacter(plr, ch)
        end)
    end

    local function untrackPlayer(plr)
        if charAddedConns[plr] then
            charAddedConns[plr]:Disconnect()
            charAddedConns[plr] = nil
        end
        if plr.Character then
            clearHighlight(plr.Character)
        end
    end

    local function startPlayerTracker()
        if runningPlayers then return end
        runningPlayers = true

        for _, plr in ipairs(Players:GetPlayers()) do
            trackPlayer(plr)
        end

        if playerAddedConn then
            playerAddedConn:Disconnect()
        end
        playerAddedConn = Players.PlayerAdded:Connect(function(plr)
            if runningPlayers then
                trackPlayer(plr)
            end
        end)

        if playerRemovingConn then
            playerRemovingConn:Disconnect()
        end
        playerRemovingConn = Players.PlayerRemoving:Connect(function(plr)
            untrackPlayer(plr)
        end)
    end

    local function stopPlayerTracker()
        if not runningPlayers then return end
        runningPlayers = false

        if playerAddedConn then
            playerAddedConn:Disconnect()
            playerAddedConn = nil
        end
        if playerRemovingConn then
            playerRemovingConn:Disconnect()
            playerRemovingConn = nil
        end

        for plr, conn in pairs(charAddedConns) do
            if conn then conn:Disconnect() end
            charAddedConns[plr] = nil
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lp and plr.Character then
                clearHighlight(plr.Character)
            end
        end
    end

    --------------------------------------------------
    -- Ad Blocker (Hide / Delete)
    --------------------------------------------------
    local AD_SCAN_INTERVAL = 60

    local adHideOn   = (toggles.AdblockHide   == true)
    local adDeleteOn = (toggles.AdblockDelete == true)

    local adScanRunning = false
    local processedHidden  = setmetatable({}, { __mode = "k" })
    local processedDeleted = setmetatable({}, { __mode = "k" })

    local function isAdInstance(inst)
        if not inst or not inst.Name then return false end
        local name = string.lower(inst.Name)

        -- Names seen in screenshots: AdPortal, AdGui, AdGuiAdornee, etc.
        if name:find("adportal", 1, true) then return true end
        if name:find("adguiadornee", 1, true) then return true end
        if name:find("adgui", 1, true) then return true end

        -- Product GUI with DevProductId attribute
        if inst:GetAttribute("DevProductId") ~= nil then
            return true
        end

        return false
    end

    local function adRoot(inst)
        if not inst then return nil end
        local root = inst
        local last = inst
        while root.Parent and root.Parent ~= WS do
            last = root
            root = root.Parent
        end
        -- Prefer immediate child of Workspace (e.g. "Ad", "Buttons")
        if root.Parent == WS then
            return root
        end
        return last
    end

    local function hideAdTree(root)
        if not root or processedHidden[root] then return end
        processedHidden[root] = true

        local function hideOne(obj)
            if obj:IsA("BasePart") then
                pcall(function()
                    obj.Transparency = 1
                    obj.CanCollide   = false
                    obj.CanTouch     = false
                    obj.CanQuery     = false
                end)
            elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") or obj:IsA("ScreenGui") then
                pcall(function()
                    if obj:IsA("BillboardGui") then
                        obj.Enabled = false
                    else
                        obj.Enabled = false
                    end
                end)
            elseif obj:IsA("GuiObject") then
                pcall(function()
                    obj.Visible = false
                end)
            elseif obj:IsA("ProximityPrompt") then
                pcall(function()
                    obj.Enabled = false
                end)
            elseif obj:IsA("ClickDetector") then
                pcall(function()
                    obj.MaxActivationDistance = 0
                end)
            end
        end

        hideOne(root)
        local ok, children = pcall(root.GetDescendants, root)
        if ok then
            for _, d in ipairs(children) do
                hideOne(d)
            end
        end
    end

    local function deleteAdTree(root)
        if not root or processedDeleted[root] then return end
        processedDeleted[root] = true
        processedHidden[root]  = nil
        pcall(function()
            root:Destroy()
        end)
    end

    local function adScanOnce()
        if not (adHideOn or adDeleteOn) then return end
        local ok, desc = pcall(WS.GetDescendants, WS)
        if not ok or not desc then return end

        for _, inst in ipairs(desc) do
            if isAdInstance(inst) then
                local root = adRoot(inst) or inst
                if adDeleteOn then
                    deleteAdTree(root)
                elseif adHideOn then
                    hideAdTree(root)
                end
            end
        end
    end

    local function ensureAdScanner()
        if adScanRunning then return end
        adScanRunning = true
        task.spawn(function()
            while adHideOn or adDeleteOn do
                adScanOnce()
                local elapsed = 0
                while elapsed < AD_SCAN_INTERVAL and (adHideOn or adDeleteOn) do
                    local step = math.min(1, AD_SCAN_INTERVAL - elapsed)
                    task.wait(step)
                    elapsed += step
                end
            end
            adScanRunning = false
        end)
    end

    --------------------------------------------------
    -- UI: Player + Adblock
    --------------------------------------------------
    VisualsTab:Section({
        Title = "Player Visuals",
        Icon  = "user",
    })

    VisualsTab:Toggle({
        Title    = "Highlight Other Players",
        Value    = (toggles.PlayerTracker ~= false),
        Callback = function(on)
            on = (on == true)
            toggles.PlayerTracker = on
            if on then
                startPlayerTracker()
            else
                stopPlayerTracker()
            end
        end
    })

    VisualsTab:Divider()

    VisualsTab:Section({
        Title = "Adblock",
        Icon  = "shield",
    })

    VisualsTab:Toggle({
        Title    = "Adblock: Hide Ads (local)",
        Value    = (toggles.AdblockHide == true), -- default OFF
        Callback = function(on)
            adHideOn = (on == true)
            toggles.AdblockHide = adHideOn
            if adHideOn or adDeleteOn then
                adScanOnce()
                ensureAdScanner()
            end
        end
    })

    VisualsTab:Toggle({
        Title    = "Adblock: Delete Ads",
        Value    = (toggles.AdblockDelete == true), -- default OFF
        Callback = function(on)
            adDeleteOn = (on == true)
            toggles.AdblockDelete = adDeleteOn
            if adHideOn or adDeleteOn then
                adScanOnce()
                ensureAdScanner()
            end
        end
    })

    -- Auto-enable player tracker if previously on or unset
    if toggles.PlayerTracker ~= false then
        startPlayerTracker()
    end

    -- If user previously enabled adblock, resume it
    if adHideOn or adDeleteOn then
        adScanOnce()
        ensureAdScanner()
    end
end
