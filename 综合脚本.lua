-- ============================================================
-- 919191ttt 综合脚本 (v3.1 - 完整版)
-- 功能: 飞行/穿墙/甩飞/传送/AI对话/API弹窗/制作人
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer

-- ==================== 工具函数 ====================
local function create(c, p)
    local o = Instance.new(c)
    for k, v in pairs(p or {}) do o[k] = v end
    return o
end

local function roundify(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = o
    return c
end

local function addStroke(o, color, th)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(255, 255, 255)
    s.Thickness = th or 1
    s.Transparency = 0.6
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = o
    return s
end

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ==================== HTTP 请求兼容层 ====================
local function httpRequest(options)
    local ok, res
    if syn and syn.request then
        ok, res = pcall(syn.request, options)
    elseif http and http.request then
        ok, res = pcall(http.request, options)
    elseif request then
        ok, res = pcall(request, options)
    elseif http_request then
        ok, res = pcall(http_request, options)
    else
        return false, "未找到 HTTP 请求函数，请使用支持 request 的执行器"
    end
    if not ok then return false, tostring(res) end
    return true, res
end

-- ==================== AI 配置 ====================
local AI_CONFIG = {
    ApiKey = "",
    ApiUrl = "https://api.deepseek.com/chat/completions",
    Model = "deepseek-chat",
    MaxHistory = 12,
    SystemPrompt = [[你是一个 Roblox 游戏专家助手，名叫"919191ttt AI"。
你可以：
1. 回答用户关于 Roblox 游戏的各种问题
2. 分析用户提供的游戏信息，识别游戏名称和类型
3. 给出针对性的游戏攻略和建议
4. 提供 Roblox 脚本编程帮助

请用中文回答，回答要简洁明了、实用。如果是游戏攻略，请列出具体步骤。]]
}

-- ==================== 游戏信息收集 ====================
local function collectGameContext()
    local ctx = {}
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        ctx.GameName = info.Name
        ctx.Creator = info.Creator and info.Creator.Name or "未知"
    end)
    ctx.PlaceId = tostring(game.PlaceId)
    ctx.JobId = game.JobId

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            ctx.Health = math.floor(hum.Health)
            ctx.MaxHealth = math.floor(hum.MaxHealth)
            ctx.WalkSpeed = math.floor(hum.WalkSpeed)
            ctx.JumpPower = math.floor(hum.JumpPower or 0)
        end
        if hrp then
            ctx.Position = string.format("(%.0f, %.0f, %.0f)",
                hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        end
    end

    local uiTexts = {}
    local function scan(parent, depth)
        if depth > 4 or #uiTexts >= 40 then return end
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local t = child.Text
                if t and #t > 0 and #t < 60 and not t:match("^%s*$") then
                    table.insert(uiTexts, t)
                end
            end
            pcall(scan, child, depth + 1)
        end
    end
    pcall(scan, LocalPlayer:FindFirstChild("PlayerGui"), 0)
    ctx.UITexts = uiTexts

    local nearby = {}
    if char and char:FindFirstChild("HumanoidRootPart") then
        local hrp = char.HumanoidRootPart
        for _, obj in pairs(workspace:GetChildren()) do
            if #nearby >= 20 then break end
            if obj:IsA("Model") or obj:IsA("BasePart") then
                local ok, pos = pcall(function()
                    if obj:IsA("Model") then
                        local pp = obj.PrimaryPart
                        return pp and pp.Position or nil
                    end
                    return obj.Position
                end)
                if ok and pos and (pos - hrp.Position).Magnitude < 150 then
                    table.insert(nearby, obj.Name)
                end
            end
        end
    end
    ctx.NearbyObjects = nearby

    local plist = {}
    for _, p in pairs(Players:GetPlayers()) do
        table.insert(plist, p.Name)
    end
    ctx.Players = plist

    return ctx
end

-- ==================== AI 对话逻辑 ====================
local conversationHistory = {}

local function addHistory(role, content)
    table.insert(conversationHistory, { role = role, content = content })
    if #conversationHistory > AI_CONFIG.MaxHistory then
        table.remove(conversationHistory, 1)
    end
end

local function callAI(userMessage, callback)
    if AI_CONFIG.ApiKey == "" then
        callback(false, "请先设置 API Key")
        return
    end

    addHistory("user", userMessage)

    local messages = { { role = "system", content = AI_CONFIG.SystemPrompt } }
    for _, m in ipairs(conversationHistory) do
        table.insert(messages, m)
    end

    local body = HttpService:JSONEncode({
        model = AI_CONFIG.Model,
        messages = messages,
        max_tokens = 1200,
        temperature = 0.7,
        stream = false,
    })

    local options = {
        Url = AI_CONFIG.ApiUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. AI_CONFIG.ApiKey,
        },
        Body = body,
    }

    task.spawn(function()
        local ok, res = httpRequest(options)
        if not ok then
            callback(false, "请求失败: " .. tostring(res))
            return
        end

        local statusCode = res.StatusCode or res.Status
        if statusCode ~= 200 then
            callback(false, "API 返回 " .. tostring(statusCode) .. ": " .. tostring(res.Body))
            return
        end

        local parseOk, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not parseOk or not data.choices or not data.choices[1] then
            callback(false, "解析响应失败")
            return
        end

        local reply = data.choices[1].message.content
        addHistory("assistant", reply)
        callback(true, reply)
    end)
end

-- ==================== 主界面 ====================
local screenGui = create("ScreenGui", {
    Name = "TTT_919191",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
})
pcall(function() screenGui.Parent = game:GetService("CoreGui") end)
if not screenGui.Parent then
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local mainFrameSize = isMobile and UDim2.new(0.92, 0, 0.8, 0) or UDim2.new(0, 560, 0, 420)
local mainFrame = create("Frame", {
    Name = "MainFrame",
    Size = mainFrameSize,
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(22, 22, 32),
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    Active = true,
    Parent = screenGui,
})
roundify(mainFrame, 16)
addStroke(mainFrame, Color3.fromRGB(120, 100, 255), 2)

-- 标题栏
local titleBar = create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = Color3.fromRGB(30, 30, 45),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Parent = mainFrame,
})
roundify(titleBar, 16)
create("Frame", {
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 0, 1, -18),
    BackgroundColor3 = Color3.fromRGB(30, 30, 45),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Parent = titleBar,
})

create("TextLabel", {
    Size = UDim2.new(1, -120, 1, 0),
    Position = UDim2.new(0, 16, 0, 0),
    BackgroundTransparency = 1,
    Text = "919191ttt 综合脚本 v3.1",
    TextColor3 = Color3.fromRGB(220, 215, 255),
    TextSize = isMobile and 17 or 16,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = titleBar,
})

local minimizeBtn = create("TextButton", {
    Size = UDim2.new(0, 40, 0, 34),
    Position = UDim2.new(1, -90, 0, 6),
    BackgroundColor3 = Color3.fromRGB(45, 45, 65),
    BackgroundTransparency = 0.3,
    Text = "−", TextColor3 = Color3.fromRGB(220, 215, 255),
    TextSize = 22, Font = Enum.Font.GothamBold,
    AutoButtonColor = true, Parent = titleBar,
})
roundify(minimizeBtn, 8)

local closeBtn = create("TextButton", {
    Size = UDim2.new(0, 40, 0, 34),
    Position = UDim2.new(1, -46, 0, 6),
    BackgroundColor3 = Color3.fromRGB(180, 60, 60),
    BackgroundTransparency = 0.2,
    Text = "×", TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 22, Font = Enum.Font.GothamBold,
    AutoButtonColor = true, Parent = titleBar,
})
roundify(closeBtn, 8)

-- ==================== 选项卡 ====================
local tabBar = create("Frame", {
    Name = "TabBar",
    Size = UDim2.new(1, -24, 0, 40),
    Position = UDim2.new(0, 12, 0, 56),
    BackgroundTransparency = 1,
    Parent = mainFrame,
})
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = tabBar,
})

local tabContents = {}
local apiModalOpen = false  -- 前向声明，供 switchTab 判断

-- 前向声明弹窗函数
local showApiKeyModal

local function switchTab(tabName)
    for name, frame in pairs(tabContents) do
        frame.Visible = (name == tabName)
    end
    for _, child in pairs(tabBar:GetChildren()) do
        if child:IsA("TextButton") then
            local isActive = (child.Name == tabName)
            TweenService:Create(child, TweenInfo.new(0.2), {
                BackgroundColor3 = isActive
                    and Color3.fromRGB(100, 80, 220)
                    or Color3.fromRGB(40, 40, 58),
                BackgroundTransparency = isActive and 0.1 or 0.4,
            }):Play()
        end
    end

    -- 切到 AI 对话页时若无 Key 自动弹窗
    if tabName == "AIChat" and AI_CONFIG.ApiKey == "" then
        task.delay(0.25, function()
            if AI_CONFIG.ApiKey == "" and not apiModalOpen and showApiKeyModal then
                showApiKeyModal(function()
                    if aiFrame and aiFrame.Parent then
                        -- 存到变量后提示
                    end
                end)
            end
        end)
    end
end

local function createTabButton(name, displayName, width)
    local btn = create("TextButton", {
        Name = name,
        Size = UDim2.new(0, width or (isMobile and 74 or 90), 1, 0),
        BackgroundColor3 = Color3.fromRGB(40, 40, 58),
        BackgroundTransparency = 0.4,
        Text = displayName,
        TextColor3 = Color3.fromRGB(220, 215, 255),
        TextSize = isMobile and 11 or 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
        Parent = tabBar,
    })
    roundify(btn, 8)
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    btn.Activated:Connect(function() switchTab(name) end)
end

createTabButton("General", "通用")
createTabButton("AIChat", "AI 对话")
createTabButton("OtherScripts", "其他脚本")
createTabButton("Credits", "制作人")

-- ==================== 内容区域 ====================
local contentArea = create("Frame", {
    Name = "ContentArea",
    Size = UDim2.new(1, -24, 1, -112),
    Position = UDim2.new(0, 12, 0, 102),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Parent = mainFrame,
})

local function createContentFrame(tabName)
    local frame = create("ScrollingFrame", {
        Name = tabName,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = Color3.fromRGB(100, 80, 220),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
        Parent = contentArea,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = frame,
    })
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 8),
        Parent = frame,
    })
    tabContents[tabName] = frame
    return frame
end

local generalFrame = createContentFrame("General")
local aiFrame = createContentFrame("AIChat")
local otherFrame = createContentFrame("OtherScripts")
local creditsFrame = createContentFrame("Credits")

-- ==================== 通用功能实现 ====================
local flying = false
local flySpeed = 50
local bodyVelocity, bodyGyro, flyConnection

local function startFly()
    if flying then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChild("Humanoid")
    if not hrp or not humanoid then return end
    flying = true
    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.P = 3000
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.Parent = hrp
    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bodyGyro.P = 9000
    bodyGyro.D = 500
    bodyGyro.CFrame = hrp.CFrame
    bodyGyro.Parent = hrp
    humanoid.PlatformStand = true
    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying then return end
        local cam = workspace.CurrentCamera
        local md = humanoid.MoveDirection
        local vel = Vector3.new(0, 0, 0)
        if md.Magnitude > 0 then
            vel = cam.CFrame:VectorToWorldSpace(Vector3.new(md.X, 0, md.Z)).Unit * flySpeed
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            vel = vel + Vector3.new(0, flySpeed * 0.8, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            vel = vel - Vector3.new(0, flySpeed * 0.8, 0)
        end
        bodyVelocity.Velocity = vel
        bodyGyro.CFrame = cam.CFrame
    end)
end

local function stopFly()
    if not flying then return end
    flying = false
    if flyConnection then flyConnection:Disconnect() flyConnection = nil end
    if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
    local char = LocalPlayer.Character
    if char then
        local h = char:FindFirstChild("Humanoid")
        if h then h.PlatformStand = false end
    end
end

local function setWalkSpeed(s)
    local c = LocalPlayer.Character
    if c then local h = c:FindFirstChild("Humanoid"); if h then h.WalkSpeed = s end end
end

local function setJumpPower(p)
    local c = LocalPlayer.Character
    if c then local h = c:FindFirstChild("Humanoid")
        if h then h.UseJumpPower = true; h.JumpPower = p end
    end
end

local noclipEnabled = false
local noclipConnection
local function toggleNoclip(state)
    noclipEnabled = state
    if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
    if state then
        noclipConnection = RunService.Stepped:Connect(function()
            local c = LocalPlayer.Character
            if not c then return end
            for _, p in pairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end
end

local function resetCharacter()
    local c = LocalPlayer.Character
    if c then local h = c:FindFirstChild("Humanoid"); if h then h.Health = 0 end end
end

local function flingPlayer(target)
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local part = Instance.new("Part")
    part.Size = Vector3.new(2, 2, 2)
    part.Transparency = 1
    part.CanCollide = false
    part.CFrame = hrp.CFrame
    part.Parent = hrp
    local att = Instance.new("Attachment")
    att.Parent = part
    local ap = Instance.new("AlignPosition")
    ap.Attachment0 = att
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Position = hrp.Position
    ap.MaxForce = math.huge
    ap.Responsiveness = 200
    ap.Parent = part
    hrp.Velocity = Vector3.new(math.random(-500, 500), math.random(600, 1000), math.random(-500, 500))
    hrp.RotVelocity = Vector3.new(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100))
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if part and part.Parent then
            part.CFrame = part.CFrame * CFrame.Angles(math.rad(50), math.rad(50), math.rad(50))
        else
            conn:Disconnect()
        end
    end)
    task.delay(5, function()
        if conn then conn:Disconnect() end
        if part then part:Destroy() end
    end)
end

local function teleportToPlayer(target)
    if not target or not target.Character then return end
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local myHrp = myChar:FindFirstChild("HumanoidRootPart")
    local tgtHrp = target.Character:FindFirstChild("HumanoidRootPart")
    if myHrp and tgtHrp then
        myHrp.CFrame = tgtHrp.CFrame * CFrame.new(0, 0, -3)
    end
end

-- ==================== 通用 UI 组件 ====================
local generalOrder = 0
local function nextOrder() generalOrder = generalOrder + 1 return generalOrder end

local function sectionLabel(text, parent, order)
    return create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Text = "  " .. text,
        TextColor3 = Color3.fromRGB(160, 145, 255),
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
        Parent = parent,
    })
end

local function createButton(text, callback, parent, order, activeColor)
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Color3.fromRGB(40, 40, 58),
        BackgroundTransparency = 0.3,
        Text = text,
        TextColor3 = Color3.fromRGB(220, 215, 255),
        TextSize = isMobile and 14 or 13,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    roundify(btn, 10)
    local toggled = false
    btn.MouseEnter:Connect(function()
        if not toggled then
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(55, 55, 80),
                BackgroundTransparency = 0.15,
            }):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if not toggled then
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(40, 40, 58),
                BackgroundTransparency = 0.3,
            }):Play()
        end
    end)
    local function onClick()
        local ok, err = pcall(callback)
        if not ok then warn("[919191ttt] " .. tostring(err)) end
    end
    btn.MouseButton1Click:Connect(onClick)
    btn.Activated:Connect(onClick)
    return btn, function(state)
        toggled = state
        TweenService:Create(btn, TweenInfo.new(0.2), {
            BackgroundColor3 = state and (activeColor or Color3.fromRGB(100, 80, 220)) or Color3.fromRGB(40, 40, 58),
            BackgroundTransparency = state and 0.1 or 0.3,
        }):Play()
    end
end

local function createSlider(text, min, max, default, callback, parent, order)
    local container = create("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        LayoutOrder = order,
        Parent = parent,
    })
    roundify(container, 10)
    local label = create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 4),
        BackgroundTransparency = 1,
        Text = text .. "  [ " .. default .. " ]",
        TextColor3 = Color3.fromRGB(200, 195, 240),
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })
    local track = create("Frame", {
        Size = UDim2.new(1, -20, 0, 8),
        Position = UDim2.new(0, 10, 0, 36),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = container,
    })
    roundify(track, 4)
    local fill = create("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(120, 100, 255),
        BorderSizePixel = 0,
        Parent = track,
    })
    roundify(fill, 4)
    local dragging = false
    local function update(x)
        local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * pct)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        label.Text = text .. "  [ " .. val .. " ]"
        if callback then callback(val) end
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

-- ==================== 通用页内容 ====================
sectionLabel("飞行系统", generalFrame, nextOrder())
local flyBtn, setFlyState = createButton("加速度飞行 (开/关)", function()
    if flying then stopFly() setFlyState(false) else startFly() setFlyState(true) end
end, generalFrame, nextOrder())
setFlyState(false)
createSlider("飞行速度", 10, 200, 50, function(v) flySpeed = v end, generalFrame, nextOrder())

sectionLabel("角色属性", generalFrame, nextOrder())
local wsBtn, setWsState = createButton("速度提升 (100)", function()
    setWalkSpeed(100); setWsState(true)
end, generalFrame, nextOrder())
local jpBtn, setJpState = createButton("跳跃提升 (120)", function()
    setJumpPower(120); setJpState(true)
end, generalFrame, nextOrder())
createButton("重置速度/跳跃", function()
    setWalkSpeed(16); setJumpPower(50)
    setWsState(false); setJpState(false)
end, generalFrame, nextOrder())

sectionLabel("辅助功能", generalFrame, nextOrder())
local ncBtn, setNcState = createButton("穿墙模式 (开/关)", function()
    toggleNoclip(not noclipEnabled); setNcState(noclipEnabled)
end, generalFrame, nextOrder())
setNcState(false)
createButton("重置角色", function() resetCharacter() end, generalFrame, nextOrder())

-- 玩家列表
sectionLabel("玩家列表 (甩飞 / 传送)", generalFrame, nextOrder())
local playerListContainer = create("Frame", {
    Size = UDim2.new(1, 0, 0, 220),
    BackgroundColor3 = Color3.fromRGB(25, 25, 38),
    BackgroundTransparency = 0.2,
    LayoutOrder = nextOrder(),
    Parent = generalFrame,
})
roundify(playerListContainer, 12)
local playerScroll = create("ScrollingFrame", {
    Size = UDim2.new(1, -8, 1, -8),
    Position = UDim2.new(0, 4, 0, 4),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Color3.fromRGB(100, 80, 220),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    Parent = playerListContainer,
})
create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = playerScroll,
})

local function refreshPlayerList()
    for _, ch in pairs(playerScroll:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end
    for i, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundColor3 = Color3.fromRGB(35, 35, 50),
            BackgroundTransparency = 0.3,
            LayoutOrder = i,
            Parent = playerScroll,
        })
        roundify(row, 8)
        create("TextLabel", {
            Size = UDim2.new(0.6, 0, 1, 0),
            Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1,
            Text = plr.Name,
            TextColor3 = Color3.fromRGB(220, 215, 255),
            TextSize = isMobile and 13 or 12,
            Font = Enum.Font.GothamMedium,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        local flingBtn = create("TextButton", {
            Size = UDim2.new(0, 60, 0, 28),
            Position = UDim2.new(1, -140, 0, 6),
            BackgroundColor3 = Color3.fromRGB(180, 60, 60),
            BackgroundTransparency = 0.2,
            Text = "甩飞", TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 12, Font = Enum.Font.GothamBold,
            AutoButtonColor = false, Parent = row,
        })
        roundify(flingBtn, 6)
        local tpBtn = create("TextButton", {
            Size = UDim2.new(0, 60, 0, 28),
            Position = UDim2.new(1, -74, 0, 6),
            BackgroundColor3 = Color3.fromRGB(60, 120, 180),
            BackgroundTransparency = 0.2,
            Text = "传送", TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 12, Font = Enum.Font.GothamBold,
            AutoButtonColor = false, Parent = row,
        })
        roundify(tpBtn, 6)
        flingBtn.MouseButton1Click:Connect(function() flingPlayer(plr) end)
        flingBtn.Activated:Connect(function() flingPlayer(plr) end)
        tpBtn.MouseButton1Click:Connect(function() teleportToPlayer(plr) end)
        tpBtn.Activated:Connect(function() teleportToPlayer(plr) end)
    end
    local layout = playerScroll:FindFirstChildOfClass("UIListLayout")
    if layout then
        playerScroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end
end
refreshPlayerList()
Players.PlayerAdded:Connect(function() task.wait(0.5) refreshPlayerList() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5) refreshPlayerList() end)

-- ==================== AI 对话页面 ====================
local aiOrder = 0
local function nextAIOrder() aiOrder = aiOrder + 1 return aiOrder end

-- 顶部按钮区
local aiTopBar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundTransparency = 1,
    LayoutOrder = nextAIOrder(),
    Parent = aiFrame,
})
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = aiTopBar,
})

local function makeTopBtn(text, color, callback)
    local b = create("TextButton", {
        Size = UDim2.new(0, isMobile and 78 or 90, 1, 0),
        BackgroundColor3 = color or Color3.fromRGB(60, 60, 90),
        BackgroundTransparency = 0.2,
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = isMobile and 11 or 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        Parent = aiTopBar,
    })
    roundify(b, 8)
    b.MouseButton1Click:Connect(callback)
    b.Activated:Connect(callback)
    return b
end

-- 消息显示
local messageScroll = create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, isMobile and 260 or 240),
    BackgroundColor3 = Color3.fromRGB(25, 25, 38),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Color3.fromRGB(100, 80, 220),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    LayoutOrder = nextAIOrder(),
    Parent = aiFrame,
})
roundify(messageScroll, 12)

local msgLayout = create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = messageScroll,
})
create("UIPadding", {
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 8),
    PaddingBottom = UDim.new(0, 8),
    Parent = messageScroll,
})

local msgOrder = 0
local function addMessage(role, text)
    msgOrder = msgOrder + 1
    local isUser = (role == "user")
    local isSys = (role == "system")

    local bubble = create("Frame", {
        Size = UDim2.new(isSys and 0.9 or 0.85, 0, 0, 40),
        BackgroundColor3 = isSys and Color3.fromRGB(45, 45, 60)
            or (isUser and Color3.fromRGB(60, 100, 160)
            or Color3.fromRGB(80, 60, 140)),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        LayoutOrder = msgOrder,
        Parent = messageScroll,
    })
    bubble.AnchorPoint = isUser and Vector2.new(1, 0) or Vector2.new(0, 0)
    bubble.Position = isUser and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
    roundify(bubble, 12)

    create("TextLabel", {
        Size = UDim2.new(1, -16, 0, 0),
        Position = UDim2.new(0, 8, 0, 8),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 238, 255),
        TextSize = isMobile and 13 or 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = bubble,
    })
    bubble.AutomaticSize = Enum.AutomaticSize.Y

    task.defer(function()
        messageScroll.CanvasSize = UDim2.new(0, 0, 0, msgLayout.AbsoluteContentSize.Y + 20)
        messageScroll.CanvasPosition = Vector2.new(0, math.huge)
    end)
    return bubble
end

-- 欢迎消息
task.delay(0.5, function()
    addMessage("system", "👋 你好！我是 919191ttt AI 助手。\n首次使用请点击 [设置 Key] 填入 DeepSeek API Key，\n或直接点击 [分析当前游戏] 让我看看你在玩什么！")
end)

-- ==================== API Key 弹窗 ====================
showApiKeyModal = function(onSaved)
    if apiModalOpen then return end
    apiModalOpen = true

    local promptGui = create("ScreenGui", {
        Name = "TTT_ApiPrompt",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 100,
    })
    pcall(function() promptGui.Parent = game:GetService("CoreGui") end)
    if not promptGui.Parent then promptGui.Parent = LocalPlayer.PlayerGui end

    local overlay = create("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        Parent = promptGui,
    })

    local boxW = isMobile and 300 or 380
    local boxH = 210
    local box = create("Frame", {
        Size = UDim2.new(0, boxW, 0, boxH),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(26, 26, 40),
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Parent = overlay,
    })
    roundify(box, 14)
    addStroke(box, Color3.fromRGB(120, 100, 255), 2)

    create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.new(0, 10, 0, 12),
        BackgroundTransparency = 1,
        Text = "🔑 请输入 DeepSeek API Key",
        TextColor3 = Color3.fromRGB(220, 215, 255),
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = box,
    })

    create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 28),
        Position = UDim2.new(0, 10, 0, 40),
        BackgroundTransparency = 1,
        Text = "在 platform.deepseek.com 免费申请\n以 sk- 开头的一串字符",
        TextColor3 = Color3.fromRGB(150, 145, 190),
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = box,
    })

    local input = create("TextBox", {
        Size = UDim2.new(1, -20, 0, 40),
        Position = UDim2.new(0, 10, 0, 78),
        BackgroundColor3 = Color3.fromRGB(45, 45, 65),
        BackgroundTransparency = 0.1,
        Text = AI_CONFIG.ApiKey,
        PlaceholderText = "sk-xxxxxxxxxxxxxxxxxxxx",
        PlaceholderColor3 = Color3.fromRGB(130, 125, 165),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = box,
    })
    roundify(input, 8)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = input,
    })

    local cancelBtn = create("TextButton", {
        Size = UDim2.new(0.5, -15, 0, 40),
        Position = UDim2.new(0, 10, 1, -50),
        BackgroundColor3 = Color3.fromRGB(55, 55, 75),
        BackgroundTransparency = 0.2,
        Text = "取消",
        TextColor3 = Color3.fromRGB(220, 215, 255),
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        Parent = box,
    })
    roundify(cancelBtn, 8)

    local saveBtn = create("TextButton", {
        Size = UDim2.new(0.5, -15, 0, 40),
        Position = UDim2.new(0.5, 5, 1, -50),
        BackgroundColor3 = Color3.fromRGB(100, 80, 220),
        BackgroundTransparency = 0.1,
        Text = "保存",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        Parent = box,
    })
    roundify(saveBtn, 8)

    local function close()
        apiModalOpen = false
        promptGui:Destroy()
    end

    cancelBtn.MouseButton1Click:Connect(close)
    cancelBtn.Activated:Connect(close)

    local function save()
        local key = input.Text or ""
        key = key:gsub("%s", "")
        if key == "" then
            input.PlaceholderText = "❌ 不能为空，请粘贴 Key"
            input.PlaceholderColor3 = Color3.fromRGB(255, 120, 120)
            return
        end
        AI_CONFIG.ApiKey = key
        close()
        if onSaved then onSaved() end
    end

    saveBtn.MouseButton1Click:Connect(save)
    saveBtn.Activated:Connect(save)
    input.FocusLost:Connect(function(enter)
        if enter then save() end
    end)

    -- 打开动画
    box.Size = UDim2.new(0, boxW, 0, 0)
    TweenService:Create(box, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, boxW, 0, boxH),
    }):Play()
end

-- 顶部按钮
makeTopBtn("分析当前游戏", Color3.fromRGB(100, 80, 220), function()
    if AI_CONFIG.ApiKey == "" then
        showApiKeyModal(function()
            addMessage("system", "✅ API Key 已保存，请再次点击 [分析当前游戏]")
        end)
        return
    end
    addMessage("system", "🔍 正在收集游戏画面信息...")
    local ctx = collectGameContext()
    local prompt = string.format([[
请分析以下 Roblox 游戏信息，告诉我：
1. **这是什么游戏**（游戏名、类型、玩法）
2. **玩家当前状态**（血量、位置、周围环境）
3. **针对性的游戏攻略与建议**（具体步骤）

游戏信息：
- 游戏名: %s
- PlaceId: %s
- 创作者: %s
- 玩家血量: %d/%d
- 移动速度: %d
- 跳跃力: %d
- 位置: %s
- 屏幕 UI 文本: %s
- 附近对象: %s
- 在线玩家: %s
]],
        ctx.GameName or "未知",
        ctx.PlaceId,
        ctx.Creator or "未知",
        ctx.Health or 0, ctx.MaxHealth or 0,
        ctx.WalkSpeed or 0, ctx.JumpPower or 0,
        ctx.Position or "未知",
        table.concat(ctx.UITexts or {}, " | "),
        table.concat(ctx.NearbyObjects or {}, ", "),
        table.concat(ctx.Players or {}, ", ")
    )

    addMessage("user", "【分析当前游戏】")
    local loadingBubble = addMessage("system", "🤔 AI 正在思考中...")

    callAI(prompt, function(ok, reply)
        if loadingBubble and loadingBubble.Parent then
            loadingBubble:Destroy()
        end
        if ok then
            addMessage("assistant", reply)
        else
            addMessage("system", "❌ " .. reply)
        end
    end)
end)

makeTopBtn("清空对话", Color3.fromRGB(180, 60, 60), function()
    for _, ch in pairs(messageScroll:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end
    conversationHistory = {}
    msgOrder = 0
    addMessage("system", "✅ 对话已清空")
end)

makeTopBtn("设置 Key", Color3.fromRGB(60, 140, 100), function()
    showApiKeyModal(function()
        addMessage("system", "✅ API Key 已保存，可以开始对话了")
    end)
end)

-- 底部输入区
local inputBar = create("Frame", {
    Size = UDim2.new(1, 0, 0, isMobile and 50 or 44),
    BackgroundTransparency = 1,
    LayoutOrder = nextAIOrder(),
    Parent = aiFrame,
})

local chatInput = create("TextBox", {
    Size = UDim2.new(1, -76, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = Color3.fromRGB(40, 40, 58),
    BackgroundTransparency = 0.2,
    Text = "",
    PlaceholderText = "输入消息...",
    PlaceholderColor3 = Color3.fromRGB(150, 145, 180),
    TextColor3 = Color3.fromRGB(240, 238, 255),
    TextSize = isMobile and 13 or 12,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    Parent = inputBar,
})
roundify(chatInput, 10)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 10),
    Parent = chatInput,
})

local sendBtn = create("TextButton", {
    Size = UDim2.new(0, 70, 1, 0),
    Position = UDim2.new(1, -70, 0, 0),
    BackgroundColor3 = Color3.fromRGB(100, 80, 220),
    BackgroundTransparency = 0.1,
    Text = "发送",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = isMobile and 13 or 12,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
    Parent = inputBar,
})
roundify(sendBtn, 10)

local sending = false
local function sendMessage()
    if sending then return end
    if AI_CONFIG.ApiKey == "" then
        showApiKeyModal()
        return
    end
    local text = chatInput.Text
    if not text or text == "" then return end
    sending = true
    chatInput.Text = ""
    addMessage("user", text)
    local loading = addMessage("system", "🤔 思考中...")
    callAI(text, function(ok, reply)
        sending = false
        if loading and loading.Parent then loading:Destroy() end
        if ok then
            addMessage("assistant", reply)
        else
            addMessage("system", "❌ " .. reply)
        end
    end)
end

sendBtn.MouseButton1Click:Connect(sendMessage)
sendBtn.Activated:Connect(sendMessage)
chatInput.FocusLost:Connect(function(enter)
    if enter then sendMessage() end
end)

-- ==================== 其他脚本页面 ====================
local otherOrder = 0
local function nextOtherOrder() otherOrder = otherOrder + 1 return otherOrder end
sectionLabel("脚本列表", otherFrame, nextOtherOrder())

for _, name in ipairs({ "自动点击", "无限跳跃", "视角解锁", "全图传送", "自定义脚本..." }) do
    createButton(name .. " (待添加)", function()
        warn("[919191ttt] 脚本 '" .. name .. "' 尚未实现")
    end, otherFrame, nextOtherOrder())
end

-- ==================== 制作人页面 ====================
local credOrder = 0
local function nextCredOrder() credOrder = credOrder + 1 return credOrder end
sectionLabel("制作人信息", creditsFrame, nextCredOrder())

local creditsInfo = {
    { label = "脚本名称", value = "919191ttt 综合脚本" },
    { label = "版本", value = "v3.1 (API 弹窗版)" },
    { label = "脚本制作", value = "919191ttt" },
    { label = "AI 助手", value = "DeepSeek" },
    { label = "AI 功能", value = "对话 / 游戏识别 / 攻略" },
    { label = "UI 风格", value = "圆滑卡片式 (参考叶脚本)" },
    { label = "适配平台", value = "PC / 手机 (Android & iOS)" },
}

for _, info in ipairs(creditsInfo) do
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        LayoutOrder = nextCredOrder(),
        Parent = creditsFrame,
    })
    roundify(row, 10)
    create("TextLabel", {
        Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = info.label,
        TextColor3 = Color3.fromRGB(160, 145, 255),
        TextSize = isMobile and 13 or 12,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    create("TextLabel", {
        Size = UDim2.new(0.55, 0, 1, 0),
        Position = UDim2.new(0.45, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = info.value,
        TextColor3 = Color3.fromRGB(220, 215, 255),
        TextSize = isMobile and 13 or 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })
end

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 60),
    BackgroundTransparency = 1,
    Text = "感谢使用 919191ttt 综合脚本\nAI 功能由 DeepSeek 提供支持",
    TextColor3 = Color3.fromRGB(140, 130, 180),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextWrapped = true,
    LayoutOrder = nextCredOrder(),
    Parent = creditsFrame,
})

-- ==================== 窗口交互 ====================
local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local minimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local target = minimized
        and UDim2.new(mainFrameSize.X.Scale, mainFrameSize.X.Offset, 0, 46)
        or mainFrameSize
    TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
        Size = target,
    }):Play()
    minimizeBtn.Text = minimized and "+" or "−"
    contentArea.Visible = not minimized
    tabBar.Visible = not minimized
end)

closeBtn.MouseButton1Click:Connect(function()
    stopFly()
    toggleNoclip(false)
    screenGui:Destroy()
end)

-- ==================== 初始显示 ====================
switchTab("General")
mainFrame.Size = UDim2.new(0, 0, 0, 0)
TweenService:Create(mainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = mainFrameSize,
}):Play()

print("[919191ttt] 脚本 v3.1 加载完成 ✓")
print("[919191ttt] 首次使用 AI 时点击 [AI 对话] 会自动弹出 API Key 输入框")