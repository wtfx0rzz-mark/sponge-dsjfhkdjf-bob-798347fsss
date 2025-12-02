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
    -- Player Highlighter (works even if invisible)
    --------------------------------------------------
    local PLAYER_HL_NAME       = "__PlayerTrackerHL__"
    local TRACKER_FOLDER_NAME  = "__PlayerTrackerModels__"

    local runningPlayers       = false
    local playerAddedConn      = nil
    local playerRemovingConn   = nil
    local charAddedConns       = {}

    local trackerFolder = WS:FindFirstChild(TRACKER_FOLDER_NAME)

    local function ensureTrackerFolder()
        if trackerFolder and trackerFolder.Parent then
            return trackerFolder
        end
        trackerFolder = WS:FindFirstChild(TRACKER_FOLDER_NAME)
        if not trackerFolder then
            trackerFolder = Instance.new("Folder")
            trackerFolder.Name = TRACKER_FOLDER_NAME
            trackerFolder.Parent = WS
        end
        return trackerFolder
    end

    ensureTrackerFolder()

    local trackers        = {}  -- [Player] = { model = Model, part = Part }
    local trackerStepConn = nil

    local function destroyTracker(plr)
        local t = trackers[plr]
        if not t then return end
        if t.model then
            pcall(function()
                t.model:Destroy()
            end)
        end
        trackers[plr] = nil
    end

    local function getOrCreateTracker(plr)
        if not plr or plr == lp then return nil end

        local t = trackers[plr]
        if t and t.model and t.model.Parent then
            return t
        end

        local folder = ensureTrackerFolder()

        local model = Instance.new("Model")
        model.Name = "__PlayerTrackerModel__" .. (plr.UserId or plr.Name)
        model.Parent = folder

        local part = Instance.new("Part")
        part.Name = "HitboxPart"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Transparency = 1
        part.Size = Vector3.new(4, 6, 4)
        part.Parent = model

        t = { model = model, part = part }
        trackers[plr] = t
        return t
    end

    local function ensureHighlight(plr)
        if not plr or plr == lp then return nil end

        local t = getOrCreateTracker(plr)
        if not t or not t.part then return nil end

        local container = t.model
        local hl = container:FindFirstChild(PLAYER_HL_NAME)
        if not hl or not hl:IsA("Highlight") then
            hl = Instance.new("Highlight")
            hl.Name = PLAYER_HL_NAME
            hl.Adornee = t.part
            hl.FillTransparency    = 1
            hl.OutlineTransparency = 0
            hl.OutlineColor        = Color3.fromRGB(255, 255, 0)
            hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent              = container
        end
        hl.Enabled = true
        return hl
    end

    local function clearHighlight(plr)
        destroyTracker(plr)
    end

    -- bounds / hitbox helpers so invisible players still get a visible box
    local function findHitboxPart(char)
        if not char then return nil end

        local candidates = {
            "Hitbox", "HitBox", "HitboxPart", "HitBoxPart",
            "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"
        }

        for _, name in ipairs(candidates) do
            local part = char:FindFirstChild(name, true)
            if part and part:IsA("BasePart") then
                return part
            end
        end

        local ok, desc = pcall(char.GetDescendants, char)
        if ok then
            for _, d in ipairs(desc) do
                if d:IsA("BasePart") then
                    return d
                end
            end
        end

        return nil
    end

    local function getCharBounds(char)
        if not char then return nil, nil end

        local pad = Vector3.new(0.25, 0.25, 0.25)

        local ok, cf, size = pcall(char.GetBoundingBox, char)
        if ok and cf and size then
            if size.X > 1 and size.Y > 2 and size.Z > 1 then
                return cf, size + pad
            end
        end

        local hb = findHitboxPart(char)
        if hb then
            local s = hb.Size
            local sx = math.max(s.X, 2)
            local sy = math.max(s.Y, 4)
            local sz = math.max(s.Z, 2)
            return hb.CFrame, Vector3.new(sx, sy, sz) + pad
        end

        return nil, nil
    end

    local function ensureTrackerUpdate()
        if trackerStepConn then return end
        trackerStepConn = Run.Heartbeat:Connect(function()
            for plr, t in pairs(trackers) do
                local ch = plr.Character
                if ch and ch.Parent and t.part and t.part.Parent then
                    local cf, size = getCharBounds(ch)
                    if cf and size then
                        t.part.CFrame = cf
                        t.part.Size   = size
                    end
                end
            end
        end)
    end

    local function stopTrackerUpdate()
        if trackerStepConn then
            trackerStepConn:Disconnect()
            trackerStepConn = nil
        end
    end

    local function attachToCharacter(plr, character)
        if not character or plr == lp then return end
        ensureHighlight(plr)
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
        clearHighlight(plr)
    end

    local function startPlayerTracker()
        if runningPlayers then return end
        runningPlayers = true

        ensureTrackerFolder()

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

        ensureTrackerUpdate()
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
            if plr ~= lp then
                clearHighlight(plr)
            end
        end

        stopTrackerUpdate()
        trackers = {}
    end

    --------------------------------------------------
    -- Base Timers (world billboards for bases)
    --------------------------------------------------
    local BASES_FOLDER_NAME = "PlayerBases"
    local BASE_MODEL_PREFIX = "^PlayerBaseTemplate_"
    local BASE_LABEL_OFFSET = Vector3.new(0, 4.5, 0)

    local baseTimersVisible = (toggles.BaseTimers == true)

    local function safeAttrs(inst)
        local ok, at = pcall(function()
            return inst:GetAttributes()
        end)
        return ok and at or {}
    end

    local function getAttr(inst, key)
        local at = safeAttrs(inst)
        return at and at[key]
    end

    local function chooseBaseAnchor(model)
        local perm = model:FindFirstChild("_PERMANENT")
        if perm then
            local door = perm:FindFirstChild("BaseEntrance")
            if door and door:IsA("BasePart") then
                return door
            end
        end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
            return model.PrimaryPart
        end
        return model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function computeLockState(model)
        local locked    = getAttr(model, "Locked")
        local unlockTs  = tonumber(getAttr(model, "UnlockTimestamp"))
        local lockDur   = tonumber(getAttr(model, "LockDuration"))
        local now       = os.time()

        if unlockTs and unlockTs > now then
            return true, math.max(0, unlockTs - now)
        end

        if locked == true then
            return true, math.max(0, lockDur or 0)
        end

        return false, 0
    end

    local function mmss(sec)
        sec = math.max(0, math.floor(sec or 0))
        local m = math.floor(sec / 60)
        local s = sec % 60
        return string.format("%d:%02d", m, s)
    end

    local baseUI    = {}  -- [model] = { gui, title, timer, anchor, model }
    local basesList = {}  -- array of base models

    local myBaseModel  = nil
    local lockedMyBase = false

    local function makeBaseBillboard(anchor)
        local gui = Instance.new("BillboardGui")
        gui.Name = "BaseLockLabel"
        gui.Adornee = anchor
        gui.AlwaysOnTop = true
        gui.Size = UDim2.fromOffset(160, 40)
        gui.MaxDistance = 1e9
        gui.StudsOffsetWorldSpace = BASE_LABEL_OFFSET
        gui.ResetOnSpawn = false
        gui.Parent = lp:WaitForChild("PlayerGui")
        gui.Enabled = baseTimersVisible

        local holder = Instance.new("Frame")
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.fromScale(1, 1)
        holder.Parent = gui

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextScaled = true
        title.Size = UDim2.new(1, 0, 0.5, 0)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.Text = "…"
        title.TextColor3 = Color3.new(1, 1, 1)
        title.Parent = holder

        local timer = Instance.new("TextLabel")
        timer.Name = "Timer"
        timer.BackgroundTransparency = 1
        timer.Font = Enum.Font.GothamBold
        timer.TextScaled = true
        timer.Size = UDim2.new(1, 0, 0.5, 0)
        timer.Position = UDim2.new(0, 0, 0.5, 0)
        timer.Text = ""
        timer.TextColor3 = Color3.new(1, 1, 1)
        timer.Parent = holder

        return gui, title, timer
    end

    local function updateBaseBillboardVisibility()
        for _, entry in pairs(baseUI) do
            if entry.gui then
                entry.gui.Enabled = baseTimersVisible
            end
        end
    end

    local function createBaseUI(model)
        if baseUI[model] then
            return
        end
        local anchor = chooseBaseAnchor(model)
        if not anchor then
            return
        end
        local gui, title, timer = makeBaseBillboard(anchor)
        baseUI[model] = {
            gui    = gui,
            title  = title,
            timer  = timer,
            anchor = anchor,
            model  = model,
        }
    end

    local function addExistingBasesOnce()
        local folder = WS:FindFirstChild(BASES_FOLDER_NAME)
        if not folder then
            return
        end
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and child.Name:match(BASE_MODEL_PREFIX) then
                createBaseUI(child)
                table.insert(basesList, child)
            end
        end
    end

    addExistingBasesOnce()

    local function trySelectMyBaseOnce(char)
        if lockedMyBase or myBaseModel then
            return
        end

        local hrp = char:FindFirstChild("HumanoidRootPart")
            or char:WaitForChild("HumanoidRootPart", 5)
        if not hrp then
            return
        end

        local t0 = time()
        while #basesList == 0 and time() - t0 < 3.0 do
            addExistingBasesOnce()
            task.wait(0.1)
        end
        if #basesList == 0 then
            return
        end

        local nearest, bestD = nil, math.huge
        for _, m in ipairs(basesList) do
            local anchor = chooseBaseAnchor(m)
            if anchor then
                local d = (anchor.Position - hrp.Position).Magnitude
                if d < bestD then
                    nearest, bestD = m, d
                end
            end
        end

        myBaseModel  = nearest
        lockedMyBase = myBaseModel ~= nil
    end

    local basesFolder = WS:FindFirstChild(BASES_FOLDER_NAME)
    if basesFolder then
        basesFolder.ChildAdded:Connect(function(child)
            if child:IsA("Model") and child.Name:match(BASE_MODEL_PREFIX) then
                createBaseUI(child)
                table.insert(basesList, child)
                if lp.Character then
                    trySelectMyBaseOnce(lp.Character)
                end
            end
        end)
    else
        WS.ChildAdded:Connect(function(child)
            if child.Name == BASES_FOLDER_NAME then
                basesFolder = child
                child.ChildAdded:Connect(function(grand)
                    if grand:IsA("Model") and grand.Name:match(BASE_MODEL_PREFIX) then
                        createBaseUI(grand)
                        table.insert(basesList, grand)
                        if lp.Character then
                            trySelectMyBaseOnce(lp.Character)
                        end
                    end
                end)
            end
        end)
    end

    task.spawn(function()
        while true do
            for _, entry in pairs(baseUI) do
                if entry.anchor and entry.anchor:IsDescendantOf(WS) then
                    local locked, rem = computeLockState(entry.model)
                    if locked and rem > 0 then
                        entry.title.Text = "LOCKED"
                        entry.title.TextColor3 = Color3.fromRGB(255, 80, 80)
                        entry.timer.Text = mmss(rem)
                    else
                        entry.title.Text = "OPEN"
                        entry.title.TextColor3 = Color3.fromRGB(120, 255, 120)
                        entry.timer.Text = ""
                    end
                    entry.gui.Enabled = baseTimersVisible
                end
            end
            task.wait(0.25)
        end
    end)

    if lp.Character then
        trySelectMyBaseOnce(lp.Character)
    end
    lp.CharacterAdded:Connect(trySelectMyBaseOnce)

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

        if name:find("adportal", 1, true) then return true end
        if name:find("adguiadornee", 1, true) then return true end
        if name:find("adgui", 1, true) then return true end

        if inst:GetAttribute("DevProductId") ~= nil then
            return true
        end

        return false
    end

    local function adRoot(inst)
        if not inst then return nil end
        local root = inst
        local last = inst
        while root.Parent and root.Parent ~= WS then
            last = root
            root = root.Parent
        end
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
                    obj.Enabled = false
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
    -- UI: Player + Adblock + Base Timers
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
        Value    = (toggles.AdblockHide == true),
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
        Value    = (toggles.AdblockDelete == true),
        Callback = function(on)
            adDeleteOn = (on == true)
            toggles.AdblockDelete = adDeleteOn
            if adHideOn or adDeleteOn then
                adScanOnce()
                ensureAdScanner()
            end
        end
    })

    VisualsTab:Divider()

    VisualsTab:Section({
        Title = "Base Timers",
        Icon  = "clock",
    })

    VisualsTab:Toggle({
        Title    = "Base Timer Labels",
        Value    = baseTimersVisible,
        Callback = function(on)
            baseTimersVisible = (on == true)
            toggles.BaseTimers = baseTimersVisible
            updateBaseBillboardVisibility()
        end
    })

    if toggles.PlayerTracker ~= false then
        startPlayerTracker()
    end

    if adHideOn or adDeleteOn then
        adScanOnce()
        ensureAdScanner()
    end

    updateBaseBillboardVisibility()
end
