--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                     AUTO SELL MODULE                          ║
    ║   Optimized batch processing with caching (5s interval)      ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoSell = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local CacheManager
local debugLog

-- Settings
local config = {}
local isEnabled = false

-- Stats
local sellStats = { petsSold = 0, eggsSold = 0 }

-- Batch settings
local BATCH_SIZE = 5 -- Sell max 5 items per cycle
local SELL_INTERVAL = 5 -- Run every 5 seconds (was 1 second)
local SELL_DELAY = 0.15 -- Delay between individual sells

--[[
    Get containers
]]
local function getPetContainer()
    return LocalPlayer:FindFirstChild("Inventory") 
        and LocalPlayer.Inventory:FindFirstChild("Pet")
end

local function getEggContainer()
    return LocalPlayer:FindFirstChild("Inventory") 
        and LocalPlayer.Inventory:FindFirstChild("Egg")
end

--[[
    Check if pet is unplaced
]]
local function isUnplacedPet(node)
    if not node or not node:IsA("Folder") then return false end
    local rootPart = node:FindFirstChild("RootPart")
    if not rootPart then return false end
    return rootPart:GetAttribute("Equipped") ~= true
end

--[[
    Check if egg is available (not placed)
]]
local function isAvailableEgg(node)
    if not node or not node:IsA("Folder") then return false end
    local rootPart = node:FindFirstChild("RootPart")
    if not rootPart then return false end
    return rootPart:GetAttribute("Equipped") ~= true
end

--[[
    Get mutation type
]]
local function getMutationType(node)
    if not node then return nil end
    local attrs = CacheManager.getAttributes(node)
    if not attrs then return nil end
    
    local mutation = attrs.mutation
    if not mutation or tostring(mutation) == "" then return nil end
    
    -- Handle special case
    if mutation == "Dino" then return "Jurassic" end
    return mutation
end

--[[
    Check if should keep mutation
]]
local function shouldKeepMutation(node)
    if not node then return false end
    local mutationType = getMutationType(node)
    if not mutationType then return false end
    
    local mutationsToKeep = config.MutationsToKeep or {}
    for _, keepMutation in ipairs(mutationsToKeep) do
        if keepMutation == mutationType then return true end
    end
    
    return false
end

--[[
    Check if should keep egg
]]
local function shouldKeepEgg(eggNode)
    if not eggNode then return false end
    
    local attrs = CacheManager.getAttributes(eggNode)
    if not attrs then return false end
    
    local eggType = attrs.eggType
    local mutation = attrs.mutation
    
    local eggsToKeep = config.EggsToKeep or {}
    local mutationsToKeep = config.MutationsToKeep or {}
    
    local keepForEggType = false
    local keepForMutation = false
    
    -- Check egg type
    if eggType then
        for _, keepEggName in ipairs(eggsToKeep) do
            if keepEggName == eggType then
                keepForEggType = true
                break
            end
        end
    end
    
    -- Check mutation
    if mutation and mutation ~= "" then
        keepForMutation = shouldKeepMutation(eggNode)
    end
    
    -- Decision logic
    if #eggsToKeep > 0 and #mutationsToKeep > 0 then
        return keepForEggType and mutation and keepForMutation
    elseif #eggsToKeep > 0 and #mutationsToKeep == 0 then
        return keepForEggType
    elseif #eggsToKeep == 0 and #mutationsToKeep > 0 then
        return mutation and keepForMutation
    else
        return false
    end
end

--[[
    Sell pet by UID
]]
local function sellPetByUid(petUid)
    local ok = pcall(function()
        local args = { "Sell", petUid }
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("PetRE"):FireServer(unpack(args))
    end)
    
    if ok then
        -- Invalidate cache for sold pet
        CacheManager.invalidate(petUid)
    end
    
    return ok
end

--[[
    Sell egg by UID
]]
local function sellEggByUid(eggUid)
    local ok = pcall(function()
        local args = { "Sell", eggUid, true }
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("PetRE"):FireServer(unpack(args))
    end)
    
    if ok then
        -- Invalidate cache for sold egg
        CacheManager.invalidate(eggUid)
    end
    
    return ok
end

--[[
    Sell pets in batches
]]
local function sellPetsBatch()
    local sellMode = config.Mode or "Pets"
    if sellMode ~= "Pets" and sellMode ~= "Both" then return 0 end
    
    local pets = getPetContainer()
    if not pets then return 0 end
    
    local sold = 0
    local mutationsToKeep = config.MutationsToKeep or {}
    local speedThreshold = config.SpeedThreshold or 0
    
    for _, node in ipairs(pets:GetChildren()) do
        if sold >= BATCH_SIZE then break end -- Batch limit
        if not isEnabled then break end
        
        local uid = node.Name
        if isUnplacedPet(node) then
            local shouldSell = false
            
            -- Check mutation filter
            if #mutationsToKeep > 0 then
                if shouldKeepMutation(node) then
                    -- Skip: has mutation we want to keep
                else
                    shouldSell = true
                end
            else
                -- Check speed threshold (use cached speed!)
                local speed = CacheManager.getPetSpeed(node)
                if speed < speedThreshold then
                    shouldSell = true
                end
            end
            
            if shouldSell then
                if sellPetByUid(uid) then
                    sold = sold + 1
                    sellStats.petsSold = sellStats.petsSold + 1
                    debugLog(string.format("Sold pet: %s (Total: %d)", uid, sellStats.petsSold))
                    task.wait(SELL_DELAY)
                end
            end
        end
    end
    
    return sold
end

--[[
    Sell eggs in batches
]]
local function sellEggsBatch()
    local sellMode = config.Mode or "Pets"
    if sellMode ~= "Eggs" and sellMode ~= "Both" then return 0 end
    
    local eggs = getEggContainer()
    if not eggs then return 0 end
    
    local sold = 0
    
    for _, node in ipairs(eggs:GetChildren()) do
        if sold >= BATCH_SIZE then break end -- Batch limit
        if not isEnabled then break end
        
        local uid = node.Name
        if isAvailableEgg(node) then
            if shouldKeepEgg(node) then
                -- Skip: egg type or mutation we want to keep
            else
                if sellEggByUid(uid) then
                    sold = sold + 1
                    sellStats.eggsSold = sellStats.eggsSold + 1
                    debugLog(string.format("Sold egg: %s (Total: %d)", uid, sellStats.eggsSold))
                    task.wait(SELL_DELAY * 2) -- Eggs need longer delay
                end
            end
        end
    end
    
    return sold
end

--[[
    Main loop
]]
function AutoSell.start()
    isEnabled = true
    debugLog("✅ Auto Sell started (Batch: " .. BATCH_SIZE .. ", Interval: " .. SELL_INTERVAL .. "s)")
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                -- Sell pets in batches
                local petsSold = sellPetsBatch()
                
                -- Sell eggs in batches
                local eggsSold = sellEggsBatch()
                
                -- Log batch summary
                if petsSold > 0 or eggsSold > 0 then
                    debugLog(string.format("📦 Batch complete: %d pets, %d eggs sold", petsSold, eggsSold))
                end
            end)
            
            -- Wait before next cycle (5 seconds instead of 1)
            task.wait(SELL_INTERVAL)
        end
    end)
end

--[[
    Stop auto sell
]]
function AutoSell.stop()
    isEnabled = false
    debugLog("⏹️ Auto Sell stopped")
end

--[[
    Get stats
]]
function AutoSell.getStats()
    return {
        petsSold = sellStats.petsSold,
        eggsSold = sellStats.eggsSold,
        totalSold = sellStats.petsSold + sellStats.eggsSold
    }
end

--[[
    Reset stats
]]
function AutoSell.resetStats()
    sellStats = { petsSold = 0, eggsSold = 0 }
end

--[[
    Initialize module
]]
function AutoSell.init(dependencies)
    CacheManager = dependencies.CacheManager
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
end

return AutoSell

