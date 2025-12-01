-- player.lua
-- Universal hub • Player tab: movement + mobile fly + force fly + noclip + godmode

return function(C, R, UI)
    C  = C  or _G.C
    R  = R  or _G.R
    UI = UI or _G.UI

    local Services = C.Services or {}
    local Players  = Services.Players  or game:GetService("Players")
    local Run      = Services.Run      or game:GetService("RunService")
    local UIS      = Services.UIS      or game:GetService("UserInputService")
    local RS       = Services.RS       or game:GetService("ReplicatedStorage")
    local WS       = Services.WS       or game:GetService("Workspace")

    local lp = C.LocalPlayer or Players.LocalPlayer
    if not (lp and UI and UI.Tabs and UI.Tabs.Player) then return end

    local tab = UI.Tabs.Player

    C.Config         = C.Config or {}
    C.State          = C.State  or {}
    C.State.Toggles  = C.State.Toggles or {}

    ------------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------------

    local function getCharacter()
        return lp.Character or lp.CharacterAdded:Wait()
    end

    local function getHumanoid()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    ------------------------------------------------------------------------
    -- Movement: WalkSpeed / JumpPower
    ------------------------------------------------------------------------

    local DEFAULT_SPEED     = 70
    local DEFAULT_JUMPPOWER = 50

    local function applyMovementConfig()
        local hum = getHumanoid()
        if not hum then return end

        local ws  = tonumber(C.Config.WalkSpeed)  or DEFAULT_SPEED
        local jp  = tonumber(C.Config.JumpPower) or DEFAULT_JUMPPOWER

        hum.UseJumpPower = true
        hum.WalkSpeed    = ws
        hum.JumpPower    = jp
    end

    tab:Section({ Title = "Movement" })

    tab:Slider({
        Title = "Walk Speed",
        Value = {
            Min     = 8,
            Max     = 120,
            Default = tonumber(C.Config.WalkSpeed) or DEFAULT_SPEED
        },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(n, 8, 120)
            C.Config.WalkSpeed = n
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = n end
        end
    })

    tab:Slider({
        Title = "Jump Power",
        Value = {
            Min     = 25,
            Max     = 200,
            Default = tonumber(C.Config.JumpPower) or DEFAULT_JUMPPOWER
        },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(n, 25, 200)
            C.Config.JumpPower = n
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.UseJumpPower = true
                hum.JumpPower    = n
            end
        end
    })

    ------------------------------------------------------------------------
    -- Infinite Jump
    ------------------------------------------------------------------------

    -- default ON unless explicitly saved false
    local infJumpOn  = (C.State.Toggles.InfiniteJump ~= false)
    local infJumpCon = nil

    local function ensureJumpConnection()
        if infJumpCon then return end
        infJumpCon = UIS.JumpRequest:Connect(function()
            if not infJumpOn then return end
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end)
            end
        end)
    end

    local function enableInfiniteJump()
        infJumpOn = true
        C.State.Toggles.InfiniteJump = true
        ensureJumpConnection()
    end

    local function disableInfiniteJump()
        infJumpOn = false
        C.State.Toggles.InfiniteJump = false
        -- keep the connection; it is gated by infJumpOn
    end

    -- Make sure the JumpRequest connection exists from the start
    ensureJumpConnection()

    tab:Toggle({
        Title   = "Infinite Jump",
        Value   = infJumpOn,
        Callback = function(on)
            if on then
                enableInfiniteJump()
            else
                disableInfiniteJump()
            end
        end
    })

    ------------------------------------------------------------------------
    -- Fly (mobile-friendly using ControlModule) + Force Fly
    ------------------------------------------------------------------------

    tab:Section({ Title = "Fly" })

    local flySpeed    = tonumber(C.Config.FlySpeed) or 60
    C.Config.FlySpeed = flySpeed

    local flyEnabled  = C.State.Toggles.Fly or false
    local forceFlyOn  = C.State.Toggles.ForceFly or false

    local FLYING        = false
    local bodyGyro      = nil
    local bodyVelocity  = nil
    local flyRenderConn = nil

    local startForceFly, stopForceFly  -- forward-declared, defined below

    local function stopMobileFly()
        if not FLYING then return end
        FLYING = false

        if flyRenderConn then
            flyRenderConn:Disconnect()
            flyRenderConn = nil
        end

        if bodyVelocity then
            bodyVelocity:Destroy()
            bodyVelocity = nil
        end

        if bodyGyro then
            bodyGyro:Destroy()
            bodyGyro = nil
        end

        local ch  = lp.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum.PlatformStand = false
            end)
        end
    end

    local function ensureFlyBodies(root)
        if not bodyGyro or not bodyGyro.Parent then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bodyGyro.P         = 1000
            bodyGyro.D         = 50
            bodyGyro.CFrame    = root.CFrame
            bodyGyro.Name      = "__MobileFlyBG"
            bodyGyro.Parent    = root
        end

        if not bodyVelocity or not bodyVelocity.Parent then
            bodyVelocity = Instance.new("BodyVelocity")
            bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bodyVelocity.Velocity = Vector3.new()
            bodyVelocity.Name     = "__MobileFlyBV"
            bodyVelocity.Parent   = root
        end
    end

    local function startMobileFly()
        if FLYING then return end

        local ch   = lp.Character
        local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local cam  = WS.CurrentCamera

        if not (hum and root and cam) then return end

        FLYING = true

        hum.PlatformStand = true
        ensureFlyBodies(root)

        if flyRenderConn then
            flyRenderConn:Disconnect()
            flyRenderConn = nil
        end

        flyRenderConn = Run.RenderStepped:Connect(function()
            if not FLYING then return end

            local ch2   = lp.Character
            local hum2  = ch2 and ch2:FindFirstChildOfClass("Humanoid")
            local root2 = ch2 and ch2:FindFirstChild("HumanoidRootPart")
            local cam2  = WS.CurrentCamera

            if not (hum2 and root2 and cam2) then return end

            hum2.PlatformStand = true
            ensureFlyBodies(root2)
            bodyGyro.CFrame    = cam2.CFrame

            local move = Vector3.new()
            local ok, controlModule = pcall(function()
                return require(lp.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
            end)
            if ok and controlModule and controlModule.GetMoveVector then
                move = controlModule:GetMoveVector()
            end

            local vel = Vector3.new()
            vel = vel + cam2.CFrame.RightVector * (move.X * flySpeed)
            vel = vel - cam2.CFrame.LookVector  * (move.Z * flySpeed)

            bodyVelocity.Velocity = vel
        end)
    end

    local function startFly()
        flyEnabled = true
        C.State.Toggles.Fly = true

        if forceFlyOn and stopForceFly then
            stopForceFly()
        end

        startMobileFly()
    end

    local function stopFly()
        flyEnabled = false
        C.State.Toggles.Fly = false
        stopMobileFly()
    end

    ------------------------------------------------------------------------
    -- Force Fly (camera pitch controls up/down, uses Humanoid.MoveDirection)
    ------------------------------------------------------------------------

    local PITCH_DEADZONE = 0.22
    local forceFlyConn   = nil
    local forceDesiredPos  = nil
    local forceLastFaceDir = nil

    startForceFly = function()
        if forceFlyConn then return end

        local ch   = lp.Character
        local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local cam  = WS.CurrentCamera

        if not (hum and root and cam) then return end

        if flyEnabled then
            stopFly()
        end

        forceFlyOn  = true
        C.State.Toggles.ForceFly = true
        forceDesiredPos  = root.Position
        forceLastFaceDir = root.CFrame.LookVector

        forceFlyConn = Run.RenderStepped:Connect(function(dt)
            local ch2   = lp.Character
            local hum2  = ch2 and ch2:FindFirstChildOfClass("Humanoid")
            local root2 = ch2 and ch2:FindFirstChild("HumanoidRootPart")
            local cam2  = WS.CurrentCamera

            if not (hum2 and root2 and cam2) then return end

            hum2.PlatformStand = true

            local move   = hum2.MoveDirection
            local planar = Vector3.new(move.X, 0, move.Z)
            local mag    = planar.Magnitude
            if mag > 1e-3 then
                planar = planar / mag
            else
                planar = Vector3.zero
            end

            local lookY = cam2.CFrame.LookVector.Y
            local vert  = 0
            if mag > 1e-3 then
                local a = math.abs(lookY)
                if a > PITCH_DEADZONE then
                    local t = (a - PITCH_DEADZONE) / (1 - PITCH_DEADZONE)
                    vert = (lookY > 0 and 1 or -1) * t * flySpeed
                end
            end

            local delta = Vector3.zero
            if mag > 1e-3 then
                delta += planar * (flySpeed * dt)
            end
            if vert ~= 0 then
                delta += Vector3.new(0, vert * dt, 0)
            end

            forceDesiredPos = (forceDesiredPos or root2.Position) + delta

            root2.AssemblyLinearVelocity  = Vector3.new()
            root2.AssemblyAngularVelocity = Vector3.new()

            if mag > 1e-3 then
                forceLastFaceDir = planar
            end
            local face   = forceLastFaceDir or root2.CFrame.LookVector
            local faceAt = forceDesiredPos + Vector3.new(face.X, 0, face.Z)
            root2.CFrame = CFrame.new(
                forceDesiredPos,
                Vector3.new(faceAt.X, forceDesiredPos.Y, faceAt.Z)
            )
        end)
    end

    stopForceFly = function()
        if forceFlyConn then
            forceFlyConn:Disconnect()
            forceFlyConn = nil
        end

        local ch   = lp.Character
        local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")

        if hum then
            pcall(function()
                hum.PlatformStand = false
            end)
        end
        if root then
            root.AssemblyLinearVelocity  = Vector3.new()
            root.AssemblyAngularVelocity = Vector3.new()
        end

        forceDesiredPos  = nil
        forceLastFaceDir = nil
        forceFlyOn       = false
        C.State.Toggles.ForceFly = false
    end

    local flyToggleCtrl, forceFlyToggleCtrl

    flyToggleCtrl = tab:Toggle({
        Title   = "Fly (Mobile)",
        Value   = flyEnabled,
        Callback = function(on)
            on = (on == true)
            if on then
                if forceFlyOn then
                    stopForceFly()
                    if forceFlyToggleCtrl and forceFlyToggleCtrl.Set then
                        pcall(function() forceFlyToggleCtrl:Set(false) end)
                    end
                end
                startFly()
            else
                stopFly()
            end
        end
    })

    tab:Slider({
        Title = "Fly Speed",
        Value = {
            Min     = 20,
            Max     = 200,
            Default = flySpeed
        },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(n, 20, 200)
            flySpeed          = n
            C.Config.FlySpeed = n
        end
    })

    forceFlyToggleCtrl = tab:Toggle({
        Title = "Force Fly",
        Value = forceFlyOn,
        Callback = function(on)
            on = (on == true)
            if on then
                if flyEnabled then
                    stopFly()
                    if flyToggleCtrl and flyToggleCtrl.Set then
                        pcall(function() flyToggleCtrl:Set(false) end)
                    end
                end
                startForceFly()
            else
                stopForceFly()
            end
        end
    })

    ------------------------------------------------------------------------
    -- Noclip
    ------------------------------------------------------------------------

    tab:Section({ Title = "Noclip" })

    local noclipOn = C.State.Toggles.Noclip or false

    local function applyNoclipToCharacter(ch)
        if not ch then return end
        for _, d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = false
            end
        end
    end

    local function enableNoclip()
        if noclipOn then return end
        noclipOn = true
        C.State.Toggles.Noclip = true
        applyNoclipToCharacter(lp.Character)
    end

    local function disableNoclip()
        noclipOn = false
        C.State.Toggles.Noclip = false
        local ch = lp.Character
        if not ch then return end
        for _, d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = true
            end
        end
    end

    tab:Toggle({
        Title = "Noclip",
        Value = noclipOn,
        Callback = function(on)
            if on then
                enableNoclip()
            else
                disableNoclip()
            end
        end
    })

    ------------------------------------------------------------------------
    -- Godmode (DamagePlayer remote)
    ------------------------------------------------------------------------

    tab:Section({ Title = "Godmode" })

    local function getDamageRemote()
        local folder = RS:FindFirstChild("RemoteEvents") or RS:FindFirstChild("Events") or RS
        if not folder then return nil end
        local ev = folder:FindFirstChild("DamagePlayer") or folder:FindFirstChild("Damage")
        return ev
    end

    local GOD_INTERVAL = 0.5

    local godNegOn     = C.State.Toggles.GodmodeNegative or false
    local godPosOn     = C.State.Toggles.GodmodePositive or false
    local negConn      = nil
    local posConn      = nil
    local negAcc       = 0
    local posAcc       = 0

    local function stopGodNegative()
        godNegOn = false
        C.State.Toggles.GodmodeNegative = false
        if negConn then
            negConn:Disconnect()
            negConn = nil
        end
        negAcc = 0
    end

    local function stopGodPositive()
        godPosOn = false
        C.State.Toggles.GodmodePositive = false
        if posConn then
            posConn:Disconnect()
            posConn = nil
        end
        posAcc = 0
    end

    local function startGodNegative()
        if godNegOn then return end

        local ev = getDamageRemote()
        if not (ev and ev:IsA("RemoteEvent")) then return end

        if godPosOn then
            stopGodPositive()
        end

        godNegOn = true
        C.State.Toggles.GodmodeNegative = true
        negAcc = 0

        local function tick()
            pcall(function()
                ev:FireServer(-math.huge)
            end)
        end

        tick()

        if negConn then
            negConn:Disconnect()
            negConn = nil
        end

        negConn = Run.Heartbeat:Connect(function(dt)
            if not godNegOn then return end
            negAcc = negAcc + dt
            if negAcc >= GOD_INTERVAL then
                negAcc = 0
                tick()
            end
        end)
    end

    local function startGodPositive()
        if godPosOn then return end

        local ev = getDamageRemote()
        if not (ev and ev:IsA("RemoteEvent")) then return end

        if godNegOn then
            stopGodNegative()
        end

        godPosOn = true
        C.State.Toggles.GodmodePositive = true
        posAcc = 0

        local function tick()
            pcall(function()
                ev:FireServer(math.huge)
            end)
        end

        tick()

        if posConn then
            posConn:Disconnect()
            posConn = nil
        end

        posConn = Run.Heartbeat:Connect(function(dt)
            if not godPosOn then return end
            posAcc = posAcc + dt
            if posAcc >= GOD_INTERVAL then
                posAcc = 0
                tick()
            end
        end)
    end

    tab:Toggle({
        Title = "Godmode (Negative Damage)",
        Value = godNegOn,
        Callback = function(on)
            if on then
                startGodNegative()
            else
                stopGodNegative()
            end
        end
    })

    tab:Toggle({
        Title = "Godmode (Positive Heal)",
        Value = godPosOn,
        Callback = function(on)
            if on then
                startGodPositive()
            else
                stopGodPositive()
            end
        end
    })

    ------------------------------------------------------------------------
    -- Character respawn handling
    ------------------------------------------------------------------------

    lp.CharacterAdded:Connect(function()
        task.defer(function()
            applyMovementConfig()

            if infJumpOn then
                enableInfiniteJump()
            end

            if forceFlyOn then
                startForceFly()
            elseif flyEnabled then
                startFly()
            end

            if noclipOn then
                applyNoclipToCharacter(lp.Character)
            end

            if godNegOn then
                startGodNegative()
            elseif godPosOn then
                startGodPositive()
            end
        end)
    end)

    -- Initial apply on first load
    task.defer(function()
        applyMovementConfig()

        if infJumpOn then
            enableInfiniteJump()
        end

        if forceFlyOn then
            startForceFly()
        elseif flyEnabled then
            startFly()
        end

        if noclipOn then
            applyNoclipToCharacter(lp.Character)
        end

        if godNegOn then
            startGodNegative()
        elseif godPosOn then
            startGodPositive()
        end
    end)

    ------------------------------------------------------------------------
    -- Continuous enforcement loop
    ------------------------------------------------------------------------

    if not C.State.__PlayerMaintainConn then
        local acc = 0
        C.State.__PlayerMaintainConn = Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < 0.25 then return end
            acc = 0

            local ch  = lp.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")

            if hum then
                local ws = tonumber(C.Config.WalkSpeed)  or DEFAULT_SPEED
                local jp = tonumber(C.Config.JumpPower) or DEFAULT_JUMPPOWER

                if math.abs(hum.WalkSpeed - ws) > 1e-2 then
                    hum.WalkSpeed = ws
                end

                if (not hum.UseJumpPower) or math.abs(hum.JumpPower - jp) > 1e-2 then
                    hum.UseJumpPower = true
                    hum.JumpPower    = jp
                end
            end

            if noclipOn and ch then
                applyNoclipToCharacter(ch)
            end

            if infJumpOn and not infJumpCon then
                ensureJumpConnection()
            end

            if flyEnabled and not FLYING then
                startMobileFly()
            elseif (not flyEnabled) and FLYING then
                stopMobileFly()
            end

            if forceFlyOn and not forceFlyConn then
                startForceFly()
            elseif (not forceFlyOn) and forceFlyConn then
                stopForceFly()
            end

            if godNegOn and not negConn then
                startGodNegative()
            elseif (not godNegOn) and negConn then
                stopGodNegative()
            end

            if godPosOn and not posConn then
                startGodPositive()
            elseif (not godPosOn) and posConn then
                stopGodPositive()
            end
        end)
    end
end
