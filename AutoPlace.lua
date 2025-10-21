--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    AUTO PLACE MODULE                          ║
    ║   Optimized queue-based placement with debouncing            ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoPlace = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local TileManager
local CacheManager
local debugLog

-- Placement queue
local placementQueue = {} -- Queue of eggs waiting to be placed
local isPlacing = false -- Prevent concurrent placements
local lastPlacementTime = 0
local PLACEMENT_COOLDOWN = 2 -- Minimum 2 seconds between placements

-- Dormant mode
local isDormant = false
local dormantReason = ""

-- Settings
local config = {}

--[[
    Ocean pet types
]]
local OCEAN_PET_TYPES = {
    ["Shark"] = true,
    ["Whale"] = true,
    ["Dolphin"] = true,
    ["Octopus"] = true,
    ["Jellyfish"] = true,
    ["Seahorse"] = true,
    ["Turtle"] = true,
    ["Crab"] = true,
    ["Lobster"] = true,
    ["Starfish"] = true,
}

local function isOceanPetType(petType)
    return OCEAN_PET_TYPES[petType] == true
end

--[[
    Get containers
]]
local function getEggContainer()
    return LocalPlayer:FindFirstChild("Inventory") 
        and LocalPlayer.Inventory:FindFirstChild("Egg")
end

--[[
    Check if egg is available to place
]]
local function isAvailableEgg(node)
    if not node or not node:IsA("Folder") then return false end
    local rootPart = node:FindFirstChild("RootPart")
    if not rootPart then return false end
    return rootPart:GetAttribute("Equipped") ~= true
end

--[[
    Get next egg from queue
]]
local function getNextEggFromQueue()
    if #placementQueue == 0 then return nil end
    return table.remove(placementQueue, 1)
end

--[[
    Add egg to placement queue (with deduplication)
]]
function AutoPlace.queueEgg(uid, eggType, mutation)
    -- Check if already in queue
    for _, item in ipairs(placementQueue) do
        if item.uid == uid then
            return false -- Already queued
        end
    end
    
    -- Add to queue
    table.insert(placementQueue, {
        uid = uid,
        eggType = eggType,
        mutation = mutation,
        queuedAt = tick()
    })
    
    debugLog(string.format("📥 Queued egg: %s [%s] (Queue: %d)", 
        eggType or "Unknown", mutation or "None", #placementQueue))
    
    return true
end

--[[
    Scan inventory and queue all unplaced eggs
]]
function AutoPlace.scanAndQueueEggs()
    local eggs = getEggContainer()
    if not eggs then return 0 end
    
    local queued = 0
    for _, node in ipairs(eggs:GetChildren()) do
        if isAvailableEgg(node) then
            local attrs = CacheManager.getAttributes(node)
            if attrs then
                if AutoPlace.queueEgg(attrs.uid, attrs.eggType, attrs.mutation) then
                    queued = queued + 1
                end
            end
        end
    end
    
    return queued
end

--[[
    Focus item
]]
local function focusItem(itemUID)
    local success = pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("CharacterRE"):FireServer("Focus", itemUID)
    end)
    return success
end

--[[
    Place item on tile
]]
local function placeItem(farmPart, itemUID)
    if not farmPart or not itemUID then return false end
    
    -- Calculate surface position
    local surfacePosition = farmPart.Position + Vector3.new(0, farmPart.Size.Y / 2, 0)
    
    -- Set Deploy attribute
    pcall(function()
        LocalPlayer:SetAttribute("Deploy", true)
    end)
    
    -- Press key "2"
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Two, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Two, false, game)
    task.wait(0.05)
    
    -- Send place command
    local args = {
        "Place",
        {
            ["CFrame"] = CFrame.new(surfacePosition),
            ["UID"] = itemUID
        }
    }
    
    local success = pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("CharacterRE"):FireServer(unpack(args))
    end)
    
    if success then
        task.wait(0.2)
        TileManager.markTileOccupied(farmPart)
        return true
    end
    
    return false
end

--[[
    Process placement queue
]]
local function processQueue()
    if isPlacing then return end
    if isDormant then return end
    if #placementQueue == 0 then return end
    
    -- Check cooldown
    local now = tick()
    if now - lastPlacementTime < PLACEMENT_COOLDOWN then
        return
    end
    
    isPlacing = true
    
    local eggData = getNextEggFromQueue()
    if not eggData then
        isPlacing = false
        return
    end
    
    local uid = eggData.uid
    local eggType = eggData.eggType
    local mutation = eggData.mutation
    
    debugLog(string.format("🥚 Processing: %s [%s] (Queue: %d)", 
        eggType or "Unknown", mutation or "None", #placementQueue))
    
    -- Check if egg is ocean type
    local isOcean = eggType and isOceanPetType(eggType) or false
    
    -- Get available tile
    local tile = TileManager.getAvailableTile(isOcean)
    if not tile then
        -- No tiles available - enter dormant mode
        isDormant = true
        dormantReason = string.format("No %s tiles available", isOcean and "ocean" or "regular")
        debugLog("💤 Entering dormant mode: " .. dormantReason)
        
        -- Put egg back in queue
        table.insert(placementQueue, 1, eggData)
        
        isPlacing = false
        return
    end
    
    -- Place egg
    focusItem(uid)
    task.wait(0.15)
    
    local placed = placeItem(tile, uid)
    if placed then
        debugLog(string.format("✅ Placed: %s [%s] on %s tile", 
            eggType or "Unknown", mutation or "None", isOcean and "Ocean" or "Regular"))
        lastPlacementTime = tick()
    else
        debugLog(string.format("❌ Failed to place: %s", eggType or "Unknown"))
        -- Put back in queue to retry
        table.insert(placementQueue, 1, eggData)
    end
    
    task.wait(0.3)
    isPlacing = false
end

--[[
    Wake up from dormant mode
]]
function AutoPlace.wakeUp(trigger)
    if not isDormant then return end
    
    isDormant = false
    dormantReason = ""
    debugLog("⚡ Auto Place reactivated by: " .. trigger)
    
    -- Process queue immediately
    task.spawn(processQueue)
end

--[[
    Main loop
]]
function AutoPlace.start()
    debugLog("✅ Auto Place started (Queue-based system)")
    
    -- Setup tile monitoring with wake-up callback
    TileManager.setupMonitoring(function(trigger)
        AutoPlace.wakeUp(trigger)
    end)
    
    -- Main loop
    task.spawn(function()
        while config.Enabled do
            pcall(function()
                if not isDormant then
                    -- Scan for new eggs and queue them
                    AutoPlace.scanAndQueueEggs()
                    
                    -- Process queue
                    processQueue()
                end
            end)
            
            -- Dynamic wait based on state
            if isDormant then
                task.wait(10) -- Sleep longer when dormant
            elseif #placementQueue > 0 then
                task.wait(2) -- Process queue every 2 seconds
            else
                task.wait(3) -- Check for new eggs every 3 seconds
            end
        end
    end)
end

--[[
    Stop auto place
]]
function AutoPlace.stop()
    config.Enabled = false
    placementQueue = {}
    isDormant = false
    debugLog("⏹️ Auto Place stopped")
end

--[[
    Get stats
]]
function AutoPlace.getStats()
    return {
        queueSize = #placementQueue,
        isDormant = isDormant,
        dormantReason = dormantReason,
        isPlacing = isPlacing
    }
end

--[[
    Initialize module
]]
function AutoPlace.init(dependencies)
    TileManager = dependencies.TileManager
    CacheManager = dependencies.CacheManager
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
    
    -- Initialize TileManager
    TileManager.initialize()
end

return AutoPlace

