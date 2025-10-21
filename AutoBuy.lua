--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                      AUTO BUY MODULE                          ║
    ║   Optimized egg buying with priority system                  ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoBuy = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local debugLog

-- Settings
local config = {}
local isEnabled = false

-- State
local lastAttemptTime = {}
local selectedMutationSet = {}
local eggCounts = {}

-- Constants
local BUY_COOLDOWN = 30 -- Wait 30s before retrying same egg
local BUY_INTERVAL = 2 -- Wait 2s between purchases

--[[
    Get island information
]]
local function getAssignedIslandName()
    local success, result = pcall(function()
        return LocalPlayer:GetAttribute("AssignedIsland")
    end)
    return success and result or nil
end

--[[
    Get egg priority index
]]
local function getEggPriorityIndex(eggType)
    for index, eggName in ipairs(config.EggPriority or {}) do
        if eggName == eggType then 
            return index
        end
    end
    return nil
end

--[[
    Check if should buy egg
]]
local function shouldBuyEgg(eggUID, eggType, eggMutation)
    debugLog(string.format("🔍 Checking egg: %s [%s] (UID: %s)", 
        tostring(eggType), tostring(eggMutation or "No Mutation"), tostring(eggUID)))
    
    -- If no specific eggs configured, buy ANY egg (but respect mutation filter)
    if #config.EggPriority == 0 then
        if #config.MutationPriority > 0 then
            -- If mutation priority is set, ONLY buy eggs with those mutations
            if eggMutation and selectedMutationSet[eggMutation] then
                return true, "Valid (has mutation: " .. eggMutation .. ")"
            else
                return false, "No mutation (mutation filter active)"
            end
        else
            -- No mutation filter, no egg filter = buy EVERYTHING
            return true, "Valid (no filters - buying everything)"
        end
    end
    
    -- Check mutation priority (if configured and egg HAS a mutation)
    if #config.MutationPriority > 0 and eggMutation then
        -- If egg has mutation, check if it's in our priority list
        if not selectedMutationSet[eggMutation] then
            return false, "Mutation not in priority list: " .. tostring(eggMutation)
        end
    end
    
    -- Check if egg is in priority list
    local eggPriorityIndex = getEggPriorityIndex(eggType)
    if not eggPriorityIndex then
        return false, "Not in egg priority list" 
    end
    
    debugLog(string.format("✅ '%s' found in priority list at position %d", eggType, eggPriorityIndex))
    
    -- CHECK: Are there higher priority eggs available?
    for higherIndex = 1, eggPriorityIndex - 1 do
        local higherPriorityEgg = config.EggPriority[higherIndex]
        if higherPriorityEgg then
            -- Check if higher priority egg exists in the shop with matching mutation
            local eggsFolder = ReplicatedStorage:FindFirstChild("Eggs")
            local islandName = getAssignedIslandName()
            if eggsFolder and islandName then
                local islandFolder = eggsFolder:FindFirstChild(islandName)
                if islandFolder then
                    for _, eggConfig in ipairs(islandFolder:GetChildren()) do
                        if eggConfig:IsA("Configuration") then
                            local checkEggType = eggConfig:GetAttribute("T")
                            local checkEggMutation = eggConfig:GetAttribute("M")
                            if checkEggMutation == "Dino" then checkEggMutation = "Jurassic" end
                            
                            -- If higher priority egg exists with valid mutation, don't buy this one
                            if checkEggType == higherPriorityEgg then
                                if #config.MutationPriority == 0 or 
                                   (checkEggMutation and selectedMutationSet[checkEggMutation]) then
                                    return false, "Higher priority egg available: " .. higherPriorityEgg
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return true, "Valid"
end

--[[
    Buy egg by UID
]]
local function buyEggByUID(eggUID)
    pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("CharacterRE"):FireServer("BuyEgg", eggUID)
    end)
end

--[[
    Main loop
]]
function AutoBuy.start()
    isEnabled = true
    debugLog("✅ Auto Buy started")
    
    -- Build mutation set
    selectedMutationSet = {}
    for _, mutation in ipairs(config.MutationPriority or {}) do
        selectedMutationSet[mutation] = true
    end
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                local islandName = getAssignedIslandName()
                
                if islandName and islandName ~= "" then
                    local eggsFolder = ReplicatedStorage:FindFirstChild("Eggs")
                    if eggsFolder then
                        local islandFolder = eggsFolder:FindFirstChild(islandName)
                        if islandFolder then
                            local currentTime = tick()
                            
                            for _, eggConfig in ipairs(islandFolder:GetChildren()) do
                                if not isEnabled then break end
                                
                                if eggConfig:IsA("Configuration") then
                                    local eggUID = eggConfig.Name
                                    local timeSinceLastAttempt = lastAttemptTime[eggUID] and (currentTime - lastAttemptTime[eggUID]) or 999
                                    
                                    if timeSinceLastAttempt >= BUY_COOLDOWN then
                                        local eggType = eggConfig:GetAttribute("T")
                                        local eggMutation = eggConfig:GetAttribute("M")
                                        if eggMutation == "Dino" then eggMutation = "Jurassic" end
                                        
                                        local shouldBuy, reason = shouldBuyEgg(eggUID, eggType, eggMutation)
                                        
                                        if shouldBuy then
                                            debugLog("💰 Buying: " .. eggType .. (eggMutation and (" [" .. eggMutation .. "]") or ""))
                                            lastAttemptTime[eggUID] = currentTime
                                            buyEggByUID(eggUID)
                                            eggCounts[eggType] = (eggCounts[eggType] or 0) + 1
                                            task.wait(BUY_INTERVAL)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            
            task.wait(1)
        end
    end)
end

--[[
    Stop auto buy
]]
function AutoBuy.stop()
    isEnabled = false
    debugLog("⏹️ Auto Buy stopped")
end

--[[
    Get stats
]]
function AutoBuy.getStats()
    return {
        eggCounts = eggCounts
    }
end

--[[
    Initialize module
]]
function AutoBuy.init(dependencies)
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
end

return AutoBuy

