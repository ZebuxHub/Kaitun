-- ═══════════════════════════════════════════════════════════════
-- KAITUN DASHBOARD MODULE
-- Handles the blank screen dashboard UI creation and updates
-- ═══════════════════════════════════════════════════════════════

local module = {}

-- Module will receive these dependencies from main script
local LocalPlayer = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

function module.init(dependencies)
    -- Inject dependencies from main script
    module.debugLog = dependencies.debugLog
    module.getPlayerNetWorth = dependencies.getPlayerNetWorth
    module.getAssignedIslandName = dependencies.getAssignedIslandName
    module.formatNumber = dependencies.formatNumber
    module.formatTime = dependencies.formatTime
    module.getLikeProgress = dependencies.getLikeProgress
    module.loadEggConfig = dependencies.loadEggConfig
    module.sessionStats = dependencies.sessionStats
    module.recordSessionData = dependencies.recordSessionData
    module.calculatePerHour = dependencies.calculatePerHour
    module.createMiniGraph = dependencies.createMiniGraph
    module.createEggCard = dependencies.createEggCard
    module.totalPickUps = dependencies.totalPickUps
    module.getgenv = dependencies.getgenv
    
    -- System states
    module.autoBuyEnabled = dependencies.autoBuyEnabled
    module.autoPlaceEnabled = dependencies.autoPlaceEnabled
    module.autoHatchEnabled = dependencies.autoHatchEnabled
    module.autoFeedEnabled = dependencies.autoFeedEnabled
    module.autoSellEnabled = dependencies.autoSellEnabled
    module.autoPickUpPetEnabled = dependencies.autoPickUpPetEnabled
    module.autoEquipBestEnabled = dependencies.autoEquipBestEnabled
    module.autoFishEnabled = dependencies.autoFishEnabled
    module.autoLikeEnabled = dependencies.autoLikeEnabled
end

local blankScreenGui = nil
local blackScreenElements = {}
local dashboardVisible = true
local blackScreenUpdateThread = nil

function module.updateBlackScreenData()
    if not blackScreenElements.sessionInfo then return end
    
    -- Record session data for graphs
    module.recordSessionData()
    
    local startTime = _G.KaitunState.startTime or os.time()
    local sessionTime = os.time() - startTime
    local netWorth = module.getPlayerNetWorth()
    
    -- Calculate per-hour rates
    local incomePerHour = module.calculatePerHour(module.sessionStats.incomeHistory)
    local eggsPerHour = module.calculatePerHour(module.sessionStats.eggHistory)
    
    -- Update session info with per-hour stats
    pcall(function()
        blackScreenElements.sessionInfo.Text = string.format(
            "⏱️ %s | 💰 %s (+%s/h) | 🥚 %d eggs/h | 🏝️ %s",
            module.formatTime(sessionTime),
            module.formatNumber(netWorth),
            module.formatNumber(incomePerHour),
            math.floor(eggsPerHour),
            module.getAssignedIslandName() or "Unknown"
        )
    end)
    
    -- Update egg inventory
    pcall(function()
        for _, child in ipairs(blackScreenElements.eggScroll:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "UIListLayout" then
                child:Destroy()
            end
        end
        
        local eggInventory = {}
        local inventoryFolder = ReplicatedStorage:FindFirstChild("Inventory")
        if inventoryFolder then
            for _, eggInst in ipairs(inventoryFolder:GetChildren()) do
                if eggInst:IsA("Folder") then
                    local eggType = eggInst:GetAttribute("T")
                    local mutation = eggInst:GetAttribute("M")
                    
                    if eggType then
                        if not eggInventory[eggType] then
                            eggInventory[eggType] = { name = eggType, count = 0, mutations = {} }
                        end
                        eggInventory[eggType].count = eggInventory[eggType].count + 1
                        if mutation then
                            eggInventory[eggType].mutations[mutation] = (eggInventory[eggType].mutations[mutation] or 0) + 1
                        end
                    end
                end
            end
        end
        
        local eggConfig = module.loadEggConfig()
        local sortedEggs = {}
        for eggType, data in pairs(eggInventory) do
            table.insert(sortedEggs, {eggType = eggType, data = data})
        end
        table.sort(sortedEggs, function(a, b) return a.data.count > b.data.count end)
        
        for _, entry in ipairs(sortedEggs) do
            local eggType = entry.eggType
            local data = entry.data
            local eggCfg = eggConfig[eggType] or {}
            
            local goalText = "No Goal"
            local goalMax = 0
            local goalReached = false
            
            if module.getgenv().KaitunConfig.EggPriority then
                for _, priority in ipairs(module.getgenv().KaitunConfig.EggPriority) do
                    if priority.Name == eggType then
                        goalMax = priority.Max or 0
                        goalText = string.format("%d / %d", data.count, goalMax)
                        goalReached = data.count >= goalMax
                        break
                    end
                end
            end
            
            local primaryMutation = "None"
            local maxMutCount = 0
            for mut, count in pairs(data.mutations) do
                if count > maxMutCount then
                    maxMutCount = count
                    primaryMutation = mut
                end
            end
            
            module.createEggCard({
                name = eggType,
                displayName = eggCfg.Name or eggType,
                count = data.count,
                mutation = primaryMutation,
                image = eggCfg.Icon or "",
                goalText = goalText,
                goalMax = goalMax,
                goalReached = goalReached
            }, blackScreenElements.eggScroll)
        end
    end)
    
    -- Update stats and graphs
    pcall(function()
        -- Clear existing content
        for _, child in ipairs(blackScreenElements.statsContainer:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        
        -- Add graphs
        if #module.sessionStats.incomeHistory >= 2 then
            module.createMiniGraph(module.sessionStats.incomeHistory, blackScreenElements.statsContainer, 0, 
                "💰 Income (Last Hour)", Color3.fromRGB(100, 255, 100))
        end
        
        if #module.sessionStats.eggHistory >= 2 then
            module.createMiniGraph(module.sessionStats.eggHistory, blackScreenElements.statsContainer, 70, 
                "🥚 Eggs (Last Hour)", Color3.fromRGB(255, 200, 100))
        end
        
        -- System status content
        for _, child in ipairs(blackScreenElements.statusCardContainer:GetChildren()) do
            child:Destroy()
        end
        
        local likes, dailyComplete, weeklyLikes, weeklyComplete = module.getLikeProgress()
        local regularThreshold = module.getgenv().KaitunConfig.AutoPickUpPetSettings.RegularThreshold or 10000
        local oceanThreshold = module.getgenv().KaitunConfig.AutoPickUpPetSettings.OceanThreshold or 5000
        local likeMode = module.getgenv().KaitunConfig.QuestSettings.AutoLikeMode or "Normal"
        local likeModeText = likeMode == "Unlimited" and " [∞ UNLIMITED]" or ""
        
        local statusText = Instance.new("TextLabel")
        statusText.Size = UDim2.new(1, 0, 0, 0)
        statusText.AutomaticSize = Enum.AutomaticSize.Y
        statusText.BackgroundTransparency = 1
        statusText.TextColor3 = Color3.fromRGB(180, 180, 200)
        statusText.TextSize = 14
        statusText.Font = Enum.Font.Gotham
        statusText.TextXAlignment = Enum.TextXAlignment.Left
        statusText.TextYAlignment = Enum.TextYAlignment.Top
        statusText.TextWrapped = true
        statusText.Parent = blackScreenElements.statusCardContainer
        
        local pickUpStatus = "⏸️ Stopped"
        if module.autoPickUpPetEnabled() then
            pickUpStatus = string.format("✅ Running (R:<%d, O:<%d) [%d picked]", 
                regularThreshold, oceanThreshold, module.totalPickUps())
        end
        
        local equipBestStatus = module.autoEquipBestEnabled() and "✅ Running" or "⏸️ Stopped"
        
        local statsLines = {
            "🎯 Active Systems",
            "",
            "  Auto Buy: " .. (module.autoBuyEnabled() and "✅ Running" or "⏸️ Stopped"),
            "  Auto Place: " .. (module.autoPlaceEnabled() and "✅ Running" or "⏸️ Stopped"),
            "  Auto Hatch: " .. (module.autoHatchEnabled() and "✅ Running" or "⏸️ Stopped"),
            "  Auto Feed: " .. (module.autoFeedEnabled() and "✅ Running" or "⏸️ Stopped"),
            "  Auto Sell: " .. (module.autoSellEnabled() and "✅ Running" or "⏸️ Stopped"),
            "  Auto Pick Up: " .. pickUpStatus,
            "  Auto Equip Best: " .. equipBestStatus,
            "  Auto Fish: " .. (module.autoFishEnabled() and "✅ Running" or "⏸️ Stopped"),
            "",
            "📋 Quest Progress",
            "",
            "  Daily Like: " .. likes .. "/3 " .. (dailyComplete and "✅" or "⏳"),
            "  Weekly Like: " .. weeklyLikes .. "/20 " .. (weeklyComplete and "✅" or "⏳"),
            "  Auto Like: " .. (module.autoLikeEnabled() and ("✅ Running" .. likeModeText) or "⏸️ Stopped"),
        }
        
        statusText.Text = table.concat(statsLines, "\n")
    end)
end

function module.activateBlankScreen()
    if blankScreenGui then return end
    
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    blankScreenGui = Instance.new("ScreenGui")
    blankScreenGui.Name = "KaitunDashboard"
    blankScreenGui.ResetOnSpawn = false
    blankScreenGui.IgnoreGuiInset = true
    blankScreenGui.DisplayOrder = 999999
    blankScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Add responsive UI scaling based on screen size
    local viewportSize = workspace.CurrentCamera.ViewportSize
    local baseWidth = 1920 -- Design base width
    local baseHeight = 1080 -- Design base height
    local scaleX = viewportSize.X / baseWidth
    local scaleY = viewportSize.Y / baseHeight
    local scale = math.min(scaleX, scaleY) -- Use smaller scale to fit both dimensions
    
    -- Clamp scale between 0.5 and 1.5 for reasonable sizes
    scale = math.clamp(scale, 0.5, 1.5)
    
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = scale
    uiScale.Parent = blankScreenGui
    
    -- Clean dark background
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    bg.BorderSizePixel = 0
    bg.Parent = blankScreenGui
    
    -- Main scrolling container for cards
    local container = Instance.new("ScrollingFrame")
    container.Size = UDim2.new(1, -40, 1, -20)
    container.Position = UDim2.new(0, 20, 0, 10)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.ScrollBarThickness = 8
    container.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    container.CanvasSize = UDim2.new(0, 0, 0, 0)
    container.AutomaticCanvasSize = Enum.AutomaticSize.Y
    container.Parent = bg
    
    local containerList = Instance.new("UIListLayout")
    containerList.Padding = UDim.new(0, 15)
    containerList.SortOrder = Enum.SortOrder.LayoutOrder
    containerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    containerList.Parent = container
    
    local containerPadding = Instance.new("UIPadding")
    containerPadding.PaddingTop = UDim.new(0, 10)
    containerPadding.PaddingBottom = UDim.new(0, 10)
    containerPadding.Parent = container
    
    -- Title card
    local titleCard = Instance.new("Frame")
    titleCard.Size = UDim2.new(1, 0, 0, 80)
    titleCard.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    titleCard.BorderSizePixel = 0
    titleCard.LayoutOrder = 1
    titleCard.Parent = container
    
    local titleCardCorner = Instance.new("UICorner")
    titleCardCorner.CornerRadius = UDim.new(0, 16)
    titleCardCorner.Parent = titleCard
    
    local titleCardStroke = Instance.new("UIStroke")
    titleCardStroke.Color = Color3.fromRGB(60, 60, 80)
    titleCardStroke.Thickness = 1
    titleCardStroke.Transparency = 0.6
    titleCardStroke.Parent = titleCard
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 20, 0, 15)
    title.BackgroundTransparency = 1
    title.Text = "🦁 ZEBUX KAITUN - BUILD A ZOO"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 24
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleCard
    
    -- Subtitle
    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -40, 0, 18)
    subtitle.Position = UDim2.new(0, 20, 0, 50)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Professional Automation Suite v2.5 | Event-Driven Architecture"
    subtitle.TextColor3 = Color3.fromRGB(150, 150, 170)
    subtitle.TextSize = 14
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = titleCard
    
    -- Session info card
    local sessionCard = Instance.new("Frame")
    sessionCard.Size = UDim2.new(1, 0, 0, 60)
    sessionCard.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    sessionCard.BorderSizePixel = 0
    sessionCard.LayoutOrder = 2
    sessionCard.Parent = container
    
    local sessionCardCorner = Instance.new("UICorner")
    sessionCardCorner.CornerRadius = UDim.new(0, 16)
    sessionCardCorner.Parent = sessionCard
    
    local sessionCardStroke = Instance.new("UIStroke")
    sessionCardStroke.Color = Color3.fromRGB(60, 60, 80)
    sessionCardStroke.Thickness = 1
    sessionCardStroke.Transparency = 0.6
    sessionCardStroke.Parent = sessionCard
    
    local sessionTitle = Instance.new("TextLabel")
    sessionTitle.Size = UDim2.new(1, -40, 0, 20)
    sessionTitle.Position = UDim2.new(0, 20, 0, 8)
    sessionTitle.BackgroundTransparency = 1
    sessionTitle.Text = "📊 Session Info"
    sessionTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    sessionTitle.TextSize = 16
    sessionTitle.Font = Enum.Font.GothamBold
    sessionTitle.TextXAlignment = Enum.TextXAlignment.Left
    sessionTitle.Parent = sessionCard
    
    local sessionInfo = Instance.new("TextLabel")
    sessionInfo.Size = UDim2.new(1, -40, 0, 22)
    sessionInfo.Position = UDim2.new(0, 20, 0, 32)
    sessionInfo.BackgroundTransparency = 1
    sessionInfo.Text = "Loading..."
    sessionInfo.TextColor3 = Color3.fromRGB(180, 180, 200)
    sessionInfo.TextSize = 14
    sessionInfo.Font = Enum.Font.Gotham
    sessionInfo.TextXAlignment = Enum.TextXAlignment.Left
    sessionInfo.Parent = sessionCard
    
    -- Egg inventory card
    local eggCard = Instance.new("Frame")
    eggCard.Size = UDim2.new(1, 0, 0, 400)
    eggCard.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    eggCard.BorderSizePixel = 0
    eggCard.LayoutOrder = 3
    eggCard.Parent = container
    
    local eggCardCorner = Instance.new("UICorner")
    eggCardCorner.CornerRadius = UDim.new(0, 16)
    eggCardCorner.Parent = eggCard
    
    local eggCardStroke = Instance.new("UIStroke")
    eggCardStroke.Color = Color3.fromRGB(60, 60, 80)
    eggCardStroke.Thickness = 1
    eggCardStroke.Transparency = 0.6
    eggCardStroke.Parent = eggCard
    
    local eggTitle = Instance.new("TextLabel")
    eggTitle.Size = UDim2.new(1, -40, 0, 25)
    eggTitle.Position = UDim2.new(0, 20, 0, 15)
    eggTitle.BackgroundTransparency = 1
    eggTitle.Text = "📦 Egg Inventory"
    eggTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    eggTitle.TextSize = 18
    eggTitle.Font = Enum.Font.GothamBold
    eggTitle.TextXAlignment = Enum.TextXAlignment.Left
    eggTitle.Parent = eggCard
    
    local eggScroll = Instance.new("ScrollingFrame")
    eggScroll.Size = UDim2.new(1, -30, 1, -55)
    eggScroll.Position = UDim2.new(0, 15, 0, 45)
    eggScroll.BackgroundTransparency = 1
    eggScroll.BorderSizePixel = 0
    eggScroll.ScrollBarThickness = 6
    eggScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    eggScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    eggScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    eggScroll.Parent = eggCard
    
    local eggList = Instance.new("UIListLayout")
    eggList.Padding = UDim.new(0, 10)
    eggList.SortOrder = Enum.SortOrder.LayoutOrder
    eggList.Parent = eggScroll
    
    -- Analytics card (for graphs)
    local analyticsCard = Instance.new("Frame")
    analyticsCard.Size = UDim2.new(1, 0, 0, 0)
    analyticsCard.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    analyticsCard.BorderSizePixel = 0
    analyticsCard.LayoutOrder = 4
    analyticsCard.AutomaticSize = Enum.AutomaticSize.Y
    analyticsCard.Parent = container
    
    local analyticsCardCorner = Instance.new("UICorner")
    analyticsCardCorner.CornerRadius = UDim.new(0, 16)
    analyticsCardCorner.Parent = analyticsCard
    
    local analyticsCardStroke = Instance.new("UIStroke")
    analyticsCardStroke.Color = Color3.fromRGB(60, 60, 80)
    analyticsCardStroke.Thickness = 1
    analyticsCardStroke.Transparency = 0.6
    analyticsCardStroke.Parent = analyticsCard
    
    local analyticsTitle = Instance.new("TextLabel")
    analyticsTitle.Size = UDim2.new(1, -40, 0, 25)
    analyticsTitle.Position = UDim2.new(0, 20, 0, 15)
    analyticsTitle.BackgroundTransparency = 1
    analyticsTitle.Text = "📈 Analytics"
    analyticsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    analyticsTitle.TextSize = 18
    analyticsTitle.Font = Enum.Font.GothamBold
    analyticsTitle.TextXAlignment = Enum.TextXAlignment.Left
    analyticsTitle.Parent = analyticsCard
    
    -- Stats container for graphs
    local statsContainer = Instance.new("Frame")
    statsContainer.Size = UDim2.new(1, -40, 0, 0)
    statsContainer.Position = UDim2.new(0, 20, 0, 50)
    statsContainer.BackgroundTransparency = 1
    statsContainer.BorderSizePixel = 0
    statsContainer.AutomaticSize = Enum.AutomaticSize.Y
    statsContainer.Parent = analyticsCard
    
    local statsList = Instance.new("UIListLayout")
    statsList.Padding = UDim.new(0, 12)
    statsList.SortOrder = Enum.SortOrder.LayoutOrder
    statsList.Parent = statsContainer
    
    local statsPadding = Instance.new("UIPadding")
    statsPadding.PaddingBottom = UDim.new(0, 20)
    statsPadding.Parent = statsContainer
    
    -- System status card
    local statusCard = Instance.new("Frame")
    statusCard.Size = UDim2.new(1, 0, 0, 0)
    statusCard.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    statusCard.BorderSizePixel = 0
    statusCard.LayoutOrder = 5
    statusCard.AutomaticSize = Enum.AutomaticSize.Y
    statusCard.Parent = container
    
    local statusCardCorner = Instance.new("UICorner")
    statusCardCorner.CornerRadius = UDim.new(0, 16)
    statusCardCorner.Parent = statusCard
    
    local statusCardStroke = Instance.new("UIStroke")
    statusCardStroke.Color = Color3.fromRGB(60, 60, 80)
    statusCardStroke.Thickness = 1
    statusCardStroke.Transparency = 0.6
    statusCardStroke.Parent = statusCard
    
    local statusCardTitle = Instance.new("TextLabel")
    statusCardTitle.Size = UDim2.new(1, -40, 0, 25)
    statusCardTitle.Position = UDim2.new(0, 20, 0, 15)
    statusCardTitle.BackgroundTransparency = 1
    statusCardTitle.Text = "⚙️ System Status"
    statusCardTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusCardTitle.TextSize = 18
    statusCardTitle.Font = Enum.Font.GothamBold
    statusCardTitle.TextXAlignment = Enum.TextXAlignment.Left
    statusCardTitle.Parent = statusCard
    
    local statusCardContainer = Instance.new("Frame")
    statusCardContainer.Size = UDim2.new(1, -40, 0, 0)
    statusCardContainer.Position = UDim2.new(0, 20, 0, 50)
    statusCardContainer.BackgroundTransparency = 1
    statusCardContainer.AutomaticSize = Enum.AutomaticSize.Y
    statusCardContainer.Parent = statusCard
    
    local statusCardPadding = Instance.new("UIPadding")
    statusCardPadding.PaddingBottom = UDim.new(0, 20)
    statusCardPadding.Parent = statusCard
    
    -- Toggle button (floating, always visible)
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 150, 0, 45)
    toggleButton.Position = UDim2.new(1, -170, 0, 20)
    toggleButton.AnchorPoint = Vector2.new(0, 0)
    toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
    toggleButton.BorderSizePixel = 0
    toggleButton.Text = "Hide Dashboard"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 15
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.ZIndex = 10
    toggleButton.Parent = bg
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 12)
    toggleCorner.Parent = toggleButton
    
    local toggleStroke = Instance.new("UIStroke")
    toggleStroke.Color = Color3.fromRGB(80, 80, 120)
    toggleStroke.Thickness = 2
    toggleStroke.Transparency = 0.4
    toggleStroke.Parent = toggleButton
    
    -- Toggle functionality (simple visibility toggle)
    toggleButton.MouseButton1Click:Connect(function()
        dashboardVisible = not dashboardVisible
        container.Visible = dashboardVisible
        
        if dashboardVisible then
            toggleButton.Text = "Hide Dashboard"
            toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        else
            toggleButton.Text = "Show Dashboard"
            toggleButton.BackgroundColor3 = Color3.fromRGB(60, 100, 200)
        end
    end)
    
    blankScreenGui.Parent = PlayerGui
    
    blackScreenElements = {
        sessionInfo = sessionInfo,
        eggScroll = eggScroll,
        statsContainer = statsContainer,
        statusCardContainer = statusCardContainer,
        toggleButton = toggleButton,
        uiScale = uiScale
    }
    
    -- Initialize session start net worth
    module.sessionStats.startNetWorth = module.getPlayerNetWorth()
    
    -- Handle viewport size changes for responsive scaling
    local camera = workspace.CurrentCamera
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if blankScreenGui and blankScreenGui.Parent and uiScale then
            local newViewportSize = camera.ViewportSize
            local baseWidth = 1920
            local baseHeight = 1080
            local scaleX = newViewportSize.X / baseWidth
            local scaleY = newViewportSize.Y / baseHeight
            local newScale = math.min(scaleX, scaleY)
            newScale = math.clamp(newScale, 0.5, 1.5)
            uiScale.Scale = newScale
        end
    end)
    
    -- Start update loop
    blackScreenUpdateThread = task.spawn(function()
        while blankScreenGui and blankScreenGui.Parent do
            module.updateBlackScreenData()
            task.wait(2)
        end
    end)
    
    module.debugLog("Blank Screen Dashboard activated (Scale: " .. string.format("%.2f", scale) .. ")")
end

return module

