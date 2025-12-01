-- actions.lua
return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        assert(C and C.Services, "actions.lua: missing C.Services")
        assert(UI and UI.Tabs and (UI.Tabs.Actions or UI.Tabs.Main), "actions.lua: Actions/Main tab missing")

        local Players = C.Services.Players or game:GetService("Players")
        local RS      = C.Services.RS      or game:GetService("ReplicatedStorage")
        local WS      = C.Services.WS      or game:GetService("Workspace")
        local Run     = C.Services.Run     or game:GetService("RunService")

        local lp = C.LocalPlayer or Players.LocalPlayer

        local Tabs = UI.Tabs or {}
        local tab  = Tabs.Actions or Tabs.Nudge or Tabs.Main
        if not tab then return end

        --------------------------------------------------------------------
        -- Shared / State
        --------------------------------------------------------------------
        C.State             = C.State             or {}
        C.State.Toggles     = C.State.Toggles     or {}
        C.State.NudgeConfig = C.State.NudgeConfig or {}

        local Toggles = C.State.Toggles

        --------------------------------------------------------------------
        -- Auto-Slap Helper
        --------------------------------------------------------------------
        local AUTO_SWING  = (Toggles.AutoSlap ~= false)  -- default ON unless explicitly set false
        local SWING_DELAY = 0.00
        local RAY_RANGE   = 24

        local PLAYER_WHITELIST = {
            daJasminat0r = true,
        }

        local function getContainers()
            local ws          = WS
            local charsFolder = ws:FindFirstChild("Characters")
            local playersFold = ws:FindFirstChild("Players")

            local char
            if charsFolder then
                char = charsFolder:FindFirstChild(lp.Name)
            end
            if not char then
                char = lp.Character
            end

            local backpack
            if playersFold then
                local pModel = playersFold:FindFirstChild(lp.Name)
                if pModel then
                    backpack = pModel:FindFirstChild("Backpack")
                end
            end
            if not backpack then
                backpack = lp:FindFirstChild("Backpack")
            end

            return char, backpack
        end

        local function getRoot(inst)
            if not inst then return nil end
            if inst:IsA("BasePart") then
                return inst
            end
            if inst:IsA("Model") then
                return inst:FindFirstChild("HumanoidRootPart")
                    or inst.PrimaryPart
                    or inst:FindFirstChildWhichIsA("BasePart")
            end
            local part = inst:FindFirstChildWhichIsA("BasePart", true)
            return part
        end

        local function equipTool(tool)
            if not tool then return end
            local char = select(1, getContainers())
            if not char then return end
            if tool.Parent ~= char then
                local hum = char:FindFirstChildWhichIsA("Humanoid")
                if hum then
                    hum:EquipTool(tool)
                else
                    tool.Parent = char
                end
            end
        end

        local function findBestSlapTool()
            local char, backpack = getContainers()
            local candidates = {}

            local function scan(container)
                if not container then return end
                for _, inst in ipairs(container:GetChildren()) do
                    if inst:IsA("Tool") and inst.Name:find("SLAPtula") then
                        table.insert(candidates, inst)
                    end
                end
            end

            scan(backpack)
            scan(char)

            local best, bestKB = nil, -math.huge
            for _, tool in ipairs(candidates) do
                local kb = tool:GetAttribute("KnockbackForce") or 0
                if kb > bestKB then
                    bestKB = kb
                    best = tool
                end
            end

            return best, bestKB
        end

        local function getSlapRemote(tool)
            if not tool then return nil end
            local comm = tool:FindFirstChild("SlapTool_Comm")
            if not comm then return nil end
            local rfFolder = comm:FindFirstChild("RF")
            if not rfFolder then return nil end
            local rf = rfFolder:FindFirstChild("Slap")
            if rf and rf:IsA("RemoteFunction") then
                return rf
            end
            return nil
        end

        local function getBestPlayerTarget()
            local lpChar = select(1, getContainers())
            local lpRoot = getRoot(lpChar)
            if not lpRoot then return nil end

            local bestPlayer, bestPos
            local bestDist = math.huge

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and not PLAYER_WHITELIST[plr.Name] then
                    local targetChar
                    local charsFolder = WS:FindFirstChild("Characters")
                    if charsFolder then
                        targetChar = charsFolder:FindFirstChild(plr.Name)
                    end
                    if not targetChar then
                        targetChar = plr.Character
                    end

                    if targetChar then
                        local root = getRoot(targetChar)
                        if root then
                            local dist = (root.Position - lpRoot.Position).Magnitude
                            if dist <= RAY_RANGE and dist < bestDist then
                                bestDist   = dist
                                bestPlayer = plr
                                bestPos    = root.Position
                            end
                        end
                    end
                end
            end

            return bestPlayer, bestPos
        end

        local function getBestObjectTarget()
            local lpChar = select(1, getContainers())
            local lpRoot = getRoot(lpChar)
            if not lpRoot then return nil end

            local bestPos
            local bestDist = math.huge

            local function consider(inst)
                local root = getRoot(inst)
                if not root then return end
                local dist = (root.Position - lpRoot.Position).Magnitude
                if dist <= RAY_RANGE and dist < bestDist then
                    bestDist = dist
                    bestPos  = root.Position
                end
            end

            local hive = WS:FindFirstChild("JellyfishHive")
            if hive then
                consider(hive)
            end

            local sundaeRoot = WS:FindFirstChild("SundaeSentry")
            if sundaeRoot then
                consider(sundaeRoot)
            end

            for _, inst in ipairs(WS:GetDescendants()) do
                local nameLower = string.lower(inst.Name)
                if nameLower:find("turret") or nameLower:find("sentry") then
                    consider(inst)
                end
            end

            return bestPos
        end

        local lastSwing = 0

        Run.Heartbeat:Connect(function()
            if not AUTO_SWING then return end
            if time() - lastSwing < SWING_DELAY then return end

            local char = select(1, getContainers())
            local lpRoot = getRoot(char)
            if not char or not lpRoot then return end

            local bestTool = select(1, findBestSlapTool())
            if not bestTool then return end

            equipTool(bestTool)

            local remote = getSlapRemote(bestTool)
            if not remote then return end

            local remoteArg1
            local targetPos

            local playerTarget, playerPos = getBestPlayerTarget()
            if playerTarget and playerPos then
                remoteArg1 = playerTarget
                targetPos  = playerPos
            else
                local objectPos = getBestObjectTarget()
                if not objectPos then
                    return
                end
                remoteArg1 = lp
                targetPos  = objectPos
            end

            local dir = targetPos - lpRoot.Position
            local unitDir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, 0)

            lastSwing = time()

            pcall(function()
                remote:InvokeServer(remoteArg1, unitDir)
            end)
        end)

        --------------------------------------------------------------------
        -- Trap blockers (Ketchup/Jelly traps) + toggle
        --------------------------------------------------------------------
        local trapAvoidOn  = (Toggles.TrapAvoid ~= false) -- default ON
        local trapBlockers = {}                          -- { BasePart, ... }

        local function registerTrapPart(part)
            if not part then return end
            trapBlockers[#trapBlockers+1] = part
        end

        local function applyTrapAvoidance()
            for i = #trapBlockers, 1, -1 do
                local p = trapBlockers[i]
                if p and p.Parent then
                    p.CanCollide = trapAvoidOn
                else
                    trapBlockers[i] = trapBlockers[#trapBlockers]
                    trapBlockers[#trapBlockers] = nil
                end
            end
        end

        local function makeTrapBlockerFor(trap)
            if not trap or not trap:IsDescendantOf(WS) then return end
            if trap:FindFirstChild("TrapBlocker", true) then return end

            local hit = trap:FindFirstChild("Hitbox", true) or getRoot(trap)
            if not hit or not hit:IsA("BasePart") then return end

            hit.CanCollide = false

            local baseSize = hit.Size + Vector3.new(4, 2, 4)

            local block = Instance.new("Part")
            block.Name = "TrapBlocker"
            block.Anchored = true
            block.CanCollide = trapAvoidOn
            block.CanTouch = false
            block.Transparency = 1
            block.Size = baseSize
            block.CFrame = hit.CFrame
            block.Parent = trap
            registerTrapPart(block)

            local step = Instance.new("Part")
            step.Name = "TrapBlockerStep"
            step.Anchored = true
            step.CanCollide = trapAvoidOn
            step.CanTouch = false
            step.Transparency = 1

            local stepSizeX = math.max(1, baseSize.X - 2)
            local stepSizeZ = math.max(1, baseSize.Z - 2)
            local stepSizeY = math.max(1, baseSize.Y * 0.5)

            step.Size = Vector3.new(stepSizeX, stepSizeY, stepSizeZ)
            step.CFrame = hit.CFrame * CFrame.new(0, (baseSize.Y + stepSizeY) / 2, 0)
            step.Parent = trap
            registerTrapPart(step)
        end

        local function createTrapBlockers()
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst.Name == "KetchupTrap" or inst.Name == "JellyTrap" then
                    makeTrapBlockerFor(inst)
                end
            end

            WS.DescendantAdded:Connect(function(inst)
                if inst.Name == "KetchupTrap" or inst.Name == "JellyTrap" then
                    task.defer(makeTrapBlockerFor, inst)
                end
            end)
        end

        createTrapBlockers()
        applyTrapAvoidance()

        --------------------------------------------------------------------
        -- Existing helpers (Shockwave / Nudge / Fling)
        --------------------------------------------------------------------
        local function hrp(p)
            p = p or lp
            local ch = p.Character or p.CharacterAdded:Wait()
            return ch:FindFirstChild("HumanoidRootPart")
        end

        local function mainPart(obj)
            if not obj or not obj.Parent then return nil end
            if obj:IsA("BasePart") then return obj end
            if obj:IsA("Model") then
                if obj.PrimaryPart then return obj.PrimaryPart end
                return obj:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end

        local function getParts(target)
            local t = {}
            if not target then return t end
            if target:IsA("BasePart") then
                t[1] = target
            elseif target:IsA("Model") then
                for _, d in ipairs(target:GetDescendants()) do
                    if d:IsA("BasePart") then
                        t[#t+1] = d
                    end
                end
            end
            return t
        end

        local function setCollide(model, on, snap)
            local parts = getParts(model)
            if on and snap then
                return
            end
            local s = {}
            for _, p in ipairs(parts) do
                s[p] = p.CanCollide
            end
            return s
        end

        local function zeroAssembly(model)
            for _, p in ipairs(getParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end

        local function getRemote(...)
            local re = RS:FindFirstChild("RemoteEvents")
            if not re then return nil end
            for _, n in ipairs({...}) do
                local x = re:FindFirstChild(n)
                if x then return x end
            end
            return nil
        end

        local REM = { StartDrag = nil, StopDrag = nil }

        local function resolveRemotes()
            REM.StartDrag = getRemote("RequestStartDraggingItem", "StartDraggingItem")
            REM.StopDrag  = getRemote("StopDraggingItem", "RequestStopDraggingItem")
        end

        resolveRemotes()

        local function safeStartDrag(model)
            if REM.StartDrag and model and model.Parent then
                pcall(function()
                    REM.StartDrag:FireServer(model)
                end)
                return true
            end
            return false
        end

        local function safeStopDrag(model)
            if REM.StopDrag and model and model.Parent then
                pcall(function()
                    REM.StopDrag:FireServer(model)
                end)
                return true
            end
            return false
        end

        local function finallyStopDrag(model)
            task.delay(0.05, function()
                pcall(safeStopDrag, model)
            end)
            task.delay(0.20, function()
                pcall(safeStopDrag, model)
            end)
        end

        local function pulseDragOnce(model)
            if not (model and model.Parent) then return end
            if REM.StartDrag then
                pcall(function()
                    REM.StartDrag:FireServer(model)
                end)
            end
            if REM.StopDrag then
                pcall(function()
                    REM.StopDrag:FireServer(model)
                end)
            end
        end

        local function isCharacterModel(m)
            return m
                and m:IsA("Model")
                and m:FindFirstChildOfClass("Humanoid") ~= nil
        end

        local function isNPCModel(m)
            if not isCharacterModel(m) then return false end
            if Players:GetPlayerFromCharacter(m) then return false end
            local n = (m.Name or ""):lower()
            if n:find("horse", 1, true) then return false end
            return true
        end

        local function charDistancePart(m)
            if not (m and m:IsA("Model")) then return nil end
            local h = m:FindFirstChild("HumanoidRootPart")
            if h and h:IsA("BasePart") then return h end
            local pp = m.PrimaryPart
            if pp and pp:IsA("BasePart") then return pp end
            return nil
        end

        local function horiz(v)
            return Vector3.new(v.X, 0, v.Z)
        end

        local function unitOr(v, fallback)
            local m = v.Magnitude
            if m > 1e-3 then
                return v / m
            end
            return fallback
        end

        local Nudge = {
            Dist     = 50,
            Up       = 20,
            Radius   = 15,
            SelfSafe = 3.5,
        }

        local AutoNudge = {
            Enabled     = false,
            MaxPerFrame = 16,
        }

        -- player fling state
        local flingEnabled     = false
        local flingPower       = 10000
        local flingLoopStarted = false

        local function ensureFlingLoop()
            if flingLoopStarted then return end
            flingLoopStarted = true

            task.spawn(function()
                local c, root, vel
                local movel = 0.1
                while true do
                    Run.Heartbeat:Wait()
                    if flingEnabled then
                        while flingEnabled and not (c and c.Parent and root and root.Parent) do
                            Run.Heartbeat:Wait()
                            c = lp.Character
                            root = c and c:FindFirstChild("HumanoidRootPart")
                        end

                        if flingEnabled and root and root.Parent then
                            vel = root.Velocity
                            root.Velocity = vel * flingPower + Vector3.new(0, flingPower, 0)
                            Run.RenderStepped:Wait()
                            if flingEnabled and c and c.Parent and root and root.Parent then
                                root.Velocity = vel
                            end
                            Run.Stepped:Wait()
                            if flingEnabled and c and c.Parent and root and root.Parent then
                                root.Velocity = vel + Vector3.new(0, movel, 0)
                                movel = -movel
                            end
                        end
                    end
                end
            end)
        end

        local function preDrag(model)
            local started = safeStartDrag(model)
            if started then
                task.wait(0.02)
            end
            return started
        end

        local function impulseItem(model, fromPos)
            local mp = mainPart(model)
            if not mp then return end

            pulseDragOnce(model)

            local pos  = mp.Position
            local away = horiz(pos - fromPos)
            local dist = away.Magnitude
            if dist < 1e-3 then return end

            if dist < Nudge.SelfSafe then
                local out = fromPos + away.Unit * (Nudge.SelfSafe + 0.5)
                local snap0 = setCollide(model, false)
                zeroAssembly(model)
                if model:IsA("Model") then
                    model:PivotTo(CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z)))
                else
                    mp.CFrame = CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z))
                end
                setCollide(model, true, snap0)

                mp   = mainPart(model) or mp
                pos  = mp.Position
                away = horiz(pos - fromPos)
                dist = away.Magnitude
                if dist < 1e-3 then
                    away = Vector3.new(0, 0, 1)
                end
            end

            local dir        = unitOr(away, Vector3.new(0, 0, 1))
            local horizSpeed = math.clamp(Nudge.Dist, 10, 160) * 4.0
            local upSpeed    = math.clamp(Nudge.Up,   5,  80) * 7.0

            task.spawn(function()
                local started = preDrag(model)
                local snap    = setCollide(model, false)

                for _, p in ipairs(getParts(model)) do
                    pcall(function()
                        p:SetNetworkOwner(lp)
                    end)
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end

                local mass = math.max(mp:GetMass(), 1)

                pcall(function()
                    mp:ApplyImpulse(
                        dir * horizSpeed * mass +
                        Vector3.new(0, upSpeed * mass, 0)
                    )
                end)

                pcall(function()
                    mp:ApplyAngularImpulse(Vector3.new(
                        (math.random() - 0.5) * 150,
                        (math.random() - 0.5) * 200,
                        (math.random() - 0.5) * 150
                    ) * mass)
                end)

                mp.AssemblyLinearVelocity =
                    dir * horizSpeed + Vector3.new(0, upSpeed, 0)

                task.delay(0.14, function()
                    if started then
                        pcall(safeStopDrag, model)
                    end
                end)

                task.delay(0.45, function()
                    if snap then
                        setCollide(model, true, snap)
                    end
                end)

                task.delay(0.9, function()
                    for _, p in ipairs(getParts(model)) do
                        pcall(function()
                            p:SetNetworkOwner(nil)
                        end)
                        pcall(function()
                            if p.SetNetworkOwnershipAuto then
                                p:SetNetworkOwnershipAuto()
                            end
                        end)
                    end
                end)
            end)
        end

        local function impulseNPC(mdl, fromPos)
            local r = charDistancePart(mdl)
            if not r then return end

            local pos  = r.Position
            local away = horiz(pos - fromPos)
            local dist = away.Magnitude

            if dist < Nudge.SelfSafe then
                away = unitOr(horiz(pos - fromPos), Vector3.new(0, 0, 1))
                pos  = fromPos + away * (Nudge.SelfSafe + 0.5)
            end

            local dir = unitOr(away, Vector3.new(0, 0, 1))
            local vel =
                dir * (math.clamp(Nudge.Dist, 10, 160) * 2.0) +
                Vector3.new(0, math.clamp(Nudge.Up, 5, 80) * 3.0, 0)

            pcall(function()
                r.AssemblyLinearVelocity = vel
            end)
        end

        local function nudgeShockwave(origin, radius)
            local myChar = lp.Character
            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { myChar }

            local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
            local seen  = {}

            for _, part in ipairs(parts) do
                if part:IsA("BasePart") and not part.Anchored then
                    if not (myChar and part:IsDescendantOf(myChar)) then
                        local mdl = part:FindFirstAncestorOfClass("Model") or part
                        if not seen[mdl] then
                            seen[mdl] = true

                            if isCharacterModel(mdl) then
                                if isNPCModel(mdl) then
                                    impulseNPC(mdl, origin)
                                end
                            else
                                impulseItem(mdl, origin)
                            end
                        end
                    end
                end
            end
        end

        --------------------------------------------------------------------
        -- EdgeButtons container
        --------------------------------------------------------------------
        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")

        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function()
                edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            end)
            edgeGui.Parent = playerGui
        end

        local stack = edgeGui:FindFirstChild("EdgeStack")
        if not stack then
            stack = Instance.new("Frame")
            stack.Name = "EdgeStack"
            stack.AnchorPoint = Vector2.new(1, 0)
            stack.Position = UDim2.new(1, -6, 0, 6)
            stack.Size = UDim2.new(0, 130, 1, -12)
            stack.BackgroundTransparency = 1
            stack.BorderSizePixel = 0
            stack.Parent = edgeGui

            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end

        --------------------------------------------------------------------
        -- Shockwave edge button
        --------------------------------------------------------------------
        local shockBtn = stack:FindFirstChild("ShockwaveEdge")
        if not shockBtn then
            shockBtn = Instance.new("TextButton")
            shockBtn.Name = "ShockwaveEdge"
            shockBtn.Size = UDim2.new(1, 0, 0, 30)
            shockBtn.Text = "Shockwave"
            shockBtn.TextSize = 12
            shockBtn.Font = Enum.Font.GothamBold
            shockBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
            shockBtn.TextColor3 = Color3.new(1, 1, 1)
            shockBtn.BorderSizePixel = 0
            shockBtn.Visible = false
            shockBtn.LayoutOrder = 50
            shockBtn.Parent = stack

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = shockBtn
        else
            shockBtn.Text = "Shockwave"
            shockBtn.LayoutOrder = shockBtn.LayoutOrder ~= 0 and shockBtn.LayoutOrder or 50
            shockBtn.Visible = false
        end

        shockBtn.MouseButton1Click:Connect(function()
            local r = hrp()
            if r then
                nudgeShockwave(r.Position, Nudge.Radius)
            end
        end)

        --------------------------------------------------------------------
        -- Restore Nudge config from state
        --------------------------------------------------------------------
        if C.State.NudgeConfig.Dist   then Nudge.Dist   = C.State.NudgeConfig.Dist   end
        if C.State.NudgeConfig.Up     then Nudge.Up     = C.State.NudgeConfig.Up     end
        if C.State.NudgeConfig.Radius then Nudge.Radius = C.State.NudgeConfig.Radius end

        local initialEdge = (Toggles.EdgeShockwave == true)

        --------------------------------------------------------------------
        -- UI: Shockwave / Auto Nudge / Trap Avoid / Auto Slap / Fling
        --------------------------------------------------------------------
        tab:Section({ Title = "Shockwave Nudge", Icon = "zap" })

        tab:Toggle({
            Title = "Edge Button: Shockwave",
            Value = initialEdge,
            Callback = function(v)
                local on = (v == true)
                Toggles.EdgeShockwave = on
                if shockBtn then
                    shockBtn.Visible = on
                end
            end
        })

        tab:Slider({
            Title = "Nudge Distance",
            Value = { Min = 10, Max = 160, Default = Nudge.Dist },
            Callback = function(v)
                local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
                if n then
                    Nudge.Dist = math.clamp(math.floor(n + 0.5), 10, 160)
                    C.State.NudgeConfig.Dist = Nudge.Dist
                end
            end
        })

        tab:Slider({
            Title = "Nudge Height",
            Value = { Min = 5, Max = 80, Default = Nudge.Up },
            Callback = function(v)
                local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
                if n then
                    Nudge.Up = math.clamp(math.floor(n + 0.5), 5, 80)
                    C.State.NudgeConfig.Up = Nudge.Up
                end
            end
        })

        tab:Slider({
            Title = "Nudge Radius",
            Value = { Min = 5, Max = 60, Default = Nudge.Radius },
            Callback = function(v)
                local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
                if n then
                    Nudge.Radius = math.clamp(math.floor(n + 0.5), 5, 60)
                    C.State.NudgeConfig.Radius = Nudge.Radius
                end
            end
        })

        tab:Toggle({
            Title = "Auto Nudge (within Radius)",
            Value = AutoNudge.Enabled,
            Callback = function(on)
                AutoNudge.Enabled = (on == true)
            end
        })

        -- Auto Nudge Heartbeat
        local autoConn
        local acc = 0

        if autoConn then
            autoConn:Disconnect()
            autoConn = nil
        end

        autoConn = Run.Heartbeat:Connect(function(dt)
            if not AutoNudge.Enabled then return end
            acc += dt
            if acc < 0.2 then return end
            acc = 0

            local r = hrp()
            if not r then return end
            nudgeShockwave(r.Position, Nudge.Radius)
        end)

        --------------------------------------------------------------------
        -- Trap Avoidance toggle
        --------------------------------------------------------------------
        tab:Section({ Title = "Trap Protection" })

        tab:Toggle({
            Title = "Avoid Ketchup/Jelly Traps",
            Value = trapAvoidOn,
            Callback = function(v)
                trapAvoidOn = (v == true)
                Toggles.TrapAvoid = trapAvoidOn
                applyTrapAvoidance()
            end
        })

        --------------------------------------------------------------------
        -- Auto Slap toggle (replaces on-screen button)
        --------------------------------------------------------------------
        tab:Section({ Title = "Slap Helper" })

        tab:Toggle({
            Title = "Auto Slap",
            Value = AUTO_SWING,
            Callback = function(v)
                AUTO_SWING = (v == true)
                C.State.Toggles.AutoSlap = AUTO_SWING
                lastSwing = 0
            end
        })

        --------------------------------------------------------------------
        -- Fling UI wiring
        --------------------------------------------------------------------
        tab:Section({ Title = "Fling Players" })

        tab:Slider({
            Title = "Fling Power",
            Value = { Min = 5000, Max = 55000, Default = flingPower },
            Callback = function(v)
                local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
                if n then
                    flingPower = math.clamp(math.floor(n + 0.5), 5000, 55000)
                end
            end
        })

        tab:Toggle({
            Title = "Fling Players",
            Value = flingEnabled,
            Callback = function(on)
                flingEnabled = (on == true)
                if flingEnabled then
                    ensureFlingLoop()
                end
            end
        })

        --------------------------------------------------------------------
        -- CharacterAdded: keep EdgeButtons + Shockwave visibility
        --------------------------------------------------------------------
        Players.LocalPlayer.CharacterAdded:Connect(function()
            local pg = lp:WaitForChild("PlayerGui")
            local eg = pg:FindFirstChild("EdgeButtons")
            if eg and eg.Parent ~= pg then
                eg.Parent = pg
            end
            local on = (C.State and C.State.Toggles and C.State.Toggles.EdgeShockwave == true) or false
            if shockBtn then
                shockBtn.Visible = on
            end
        end)

        if shockBtn then
            shockBtn.Visible = initialEdge
        end
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Actions] module error: " .. tostring(err))
    end
end
