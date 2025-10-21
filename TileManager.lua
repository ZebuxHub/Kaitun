--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                     TILE MANAGER MODULE                       ║
    ║   Optimized tile queue system - O(1) tile access             ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local TileManager = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Tile queues (fast O(1) access)
local availableRegularTiles = {} -- Queue of available regular tiles
local availableOceanTiles = {} -- Queue of available ocean tiles
local lockedTiles = {} -- Set of locked tile positions (never changes unless unlocked)
local occupiedTiles = {} -- Set of occupied tile positions (changes frequently)

-- State
local isInitialized = false
local monitorConnections = {}

--[[
    Get island information
]]
local function getAssignedIslandName()
    local success, result = pcall(function()
        return LocalPlayer:GetAttribute("AssignedIsland")
    end)
    return success and result or nil
end

local function getIslandNumberFromName(islandName)
    if not islandName then return nil end
    local num = islandName:match("%d+")
    return num and tonumber(num) or nil
end

--[[
    Get tile key for position tracking
]]
local function getTileKey(part)
    if not part then return nil end
    local pos = part.Position
    local x = math.floor(pos.X / 8) * 8
    local z = math.floor(pos.Z / 8) * 8
    return string.format("%d,%d", x, z)
end

--[[
    Check if tile is locked (build this ONCE on startup)
]]
local function buildLockedTilesSet()
    lockedTiles = {}
    
    local islandName = getAssignedIslandName()
    if not islandName then return end
    
    local art = workspace:FindFirstChild("Art")
    if not art then return end
    
    local island = art:FindFirstChild(islandName)
    if not island then return end
    
    local env = island:FindFirstChild("ENV")
    if not env then return end
    
    local locksFolder = env:FindFirstChild("Locks")
    if not locksFolder then return end
    
    -- Build set of locked positions
    for _, lockModel in ipairs(locksFolder:GetChildren()) do
        if lockModel:IsA("Model") then
            local lockPart = lockModel:FindFirstChild("Farm") or lockModel:FindFirstChild("WaterFarm")
            if lockPart and lockPart:IsA("BasePart") and lockPart.Transparency == 0 then
                local key = getTileKey(lockPart)
                if key then
                    lockedTiles[key] = true
                end
            end
        end
    end
end

--[[
    Check if tile is occupied (check PlayerBuiltBlocks + Pets)
]]
local function isTileOccupied(tileKey)
    return occupiedTiles[tileKey] == true
end

--[[
    Build tile queues (regular and ocean)
]]
local function rebuildTileQueues()
    availableRegularTiles = {}
    availableOceanTiles = {}
    
    local islandName = getAssignedIslandName()
    local islandNumber = getIslandNumberFromName(islandName)
    if not islandNumber then return end
    
    local art = workspace:FindFirstChild("Art")
    if not art then return end
    
    local island = art:FindFirstChild(islandName)
    if not island then return end
    
    local env = island:FindFirstChild("ENV")
    if not env then return end
    
    -- Get regular tiles
    local farmFolder = env:FindFirstChild("Farm")
    if farmFolder then
        for _, part in ipairs(farmFolder:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "Farm" then
                local key = getTileKey(part)
                if key and not lockedTiles[key] and not isTileOccupied(key) then
                    table.insert(availableRegularTiles, part)
                end
            end
        end
    end
    
    -- Get ocean tiles
    local waterFarmFolder = env:FindFirstChild("WaterFarm")
    if waterFarmFolder then
        for _, part in ipairs(waterFarmFolder:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "WaterFarm" then
                local key = getTileKey(part)
                if key and not lockedTiles[key] and not isTileOccupied(key) then
                    table.insert(availableOceanTiles, part)
                end
            end
        end
    end
end

--[[
    Mark tile as occupied
]]
function TileManager.markTileOccupied(part)
    if not part then return end
    local key = getTileKey(part)
    if key then
        occupiedTiles[key] = true
    end
end

--[[
    Mark tile as available (freed)
]]
function TileManager.markTileAvailable(part)
    if not part then return end
    local key = getTileKey(part)
    if key then
        occupiedTiles[key] = nil
    end
end

--[[
    Get next available tile (O(1) operation - just pop from queue!)
]]
function TileManager.getAvailableTile(isOcean)
    local queue = isOcean and availableOceanTiles or availableRegularTiles
    
    -- Pop from queue (O(1))
    if #queue > 0 then
        local tile = table.remove(queue, 1)
        
        -- Double-check it's still valid
        local key = getTileKey(tile)
        if key and not isTileOccupied(key) then
            return tile
        else
            -- Tile became occupied, try next one
            return TileManager.getAvailableTile(isOcean)
        end
    end
    
    return nil
end

--[[
    Get queue stats
]]
function TileManager.getStats()
    return {
        regularTiles = #availableRegularTiles,
        oceanTiles = #availableOceanTiles,
        lockedTiles = 0, -- Count locked tiles
        occupiedTiles = 0 -- Count occupied tiles
    }
end

--[[
    Setup event monitoring for tile changes
]]
function TileManager.setupMonitoring(onTileFreed)
    -- Clean up old connections
    for _, conn in ipairs(monitorConnections) do
        conn:Disconnect()
    end
    monitorConnections = {}
    
    local playerUserId = LocalPlayer.UserId
    
    -- Monitor PlayerBuiltBlocks (eggs)
    local playerBuiltBlocks = workspace:FindFirstChild("PlayerBuiltBlocks")
    if playerBuiltBlocks then
        -- Egg placed
        local eggAddedConn = playerBuiltBlocks.ChildAdded:Connect(function(model)
            if not model:IsA("Model") then return end
            task.wait(0.1)
            
            local rootPart = model:FindFirstChild("RootPart")
            if rootPart then
                local itemUserId = rootPart:GetAttribute("UserId")
                if itemUserId and tonumber(itemUserId) == playerUserId then
                    local pos = model:GetPivot().Position
                    local x = math.floor(pos.X / 8) * 8
                    local z = math.floor(pos.Z / 8) * 8
                    local key = string.format("%d,%d", x, z)
                    occupiedTiles[key] = true
                end
            end
        end)
        
        -- Egg removed (hatched)
        local eggRemovedConn = playerBuiltBlocks.ChildRemoved:Connect(function(model)
            task.wait(0.2)
            rebuildTileQueues() -- Rebuild queues when tile freed
            if onTileFreed then
                onTileFreed("egg_hatched")
            end
        end)
        
        table.insert(monitorConnections, eggAddedConn)
        table.insert(monitorConnections, eggRemovedConn)
    end
    
    -- Monitor Pets
    local workspacePets = workspace:FindFirstChild("Pets")
    if workspacePets then
        -- Pet placed
        local petAddedConn = workspacePets.ChildAdded:Connect(function(pet)
            if not pet:IsA("Model") then return end
            task.wait(0.1)
            
            local rootPart = pet:FindFirstChild("RootPart")
            if rootPart then
                local petUserId = rootPart:GetAttribute("UserId")
                if petUserId and tonumber(petUserId) == playerUserId then
                    local pos = pet:GetPivot().Position
                    local x = math.floor(pos.X / 8) * 8
                    local z = math.floor(pos.Z / 8) * 8
                    local key = string.format("%d,%d", x, z)
                    occupiedTiles[key] = true
                end
            end
        end)
        
        -- Pet removed
        local petRemovedConn = workspacePets.ChildRemoved:Connect(function(pet)
            task.wait(0.2)
            rebuildTileQueues()
            if onTileFreed then
                onTileFreed("pet_removed")
            end
        end)
        
        table.insert(monitorConnections, petAddedConn)
        table.insert(monitorConnections, petRemovedConn)
    end
    
    -- Monitor tile unlocks
    local islandName = getAssignedIslandName()
    if islandName then
        local art = workspace:FindFirstChild("Art")
        if art then
            local island = art:FindFirstChild(islandName)
            if island then
                local env = island:FindFirstChild("ENV")
                if env then
                    local locksFolder = env:FindFirstChild("Locks")
                    if locksFolder then
                        local lockRemovedConn = locksFolder.DescendantRemoving:Connect(function(lock)
                            if lock:IsA("BasePart") and (lock.Name == "Farm" or lock.Name == "WaterFarm") then
                                task.wait(0.3)
                                local key = getTileKey(lock)
                                if key then
                                    lockedTiles[key] = nil -- Remove from locked set
                                end
                                rebuildTileQueues()
                                if onTileFreed then
                                    onTileFreed("tile_unlocked")
                                end
                            end
                        end)
                        table.insert(monitorConnections, lockRemovedConn)
                    end
                end
            end
        end
    end
end

--[[
    Initialize tile manager
]]
function TileManager.initialize()
    if isInitialized then return end
    
    -- Build locked tiles set (only once!)
    buildLockedTilesSet()
    
    -- Build initial tile queues
    rebuildTileQueues()
    
    isInitialized = true
end

--[[
    Cleanup
]]
function TileManager.cleanup()
    for _, conn in ipairs(monitorConnections) do
        conn:Disconnect()
    end
    monitorConnections = {}
    isInitialized = false
end

return TileManager

