--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                     AUTO FEED MODULE                          ║
    ║   Optimized big pet feeding system                           ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoFeed = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local debugLog

-- Settings
local config = {}
local isEnabled = false

-- Constants
local FEED_CHECK_INTERVAL = 3 -- Check every 3 seconds

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
    Find big pet station for pet
]]
local function findBigPetStationForPet(petPosition)
    local islandName = getAssignedIslandName()
    if not islandName then return nil end
    
    local art = workspace:FindFirstChild("Art")
    if not art then return nil end
    local island = art:FindFirstChild(islandName)
    if not island then return nil end
    local env = island:FindFirstChild("ENV")
    if not env then return nil end
    local bigPetFolder = env:FindFirstChild("BigPet")
    if not bigPetFolder then return nil end
    
    local closestStation = nil
    local closestDistance = math.huge
    
    for _, station in ipairs(bigPetFolder:GetChildren()) do
        if station:IsA("BasePart") then
            local distance = (station.Position - petPosition).Magnitude
            if distance < closestDistance and distance < 50 then
                closestDistance = distance
                closestStation = station.Name
            end
        end
    end
    
    return closestStation
end

--[[
    Get all big pets
]]
local function getBigPets()
    local pets = {}
    local petsFolder = workspace:FindFirstChild("Pets")
    if not petsFolder then return pets end
    
    for _, petModel in ipairs(petsFolder:GetChildren()) do
        if petModel:IsA("Model") then
            local rootPart = petModel:FindFirstChild("RootPart")
            if rootPart then
                local petUserId = rootPart:GetAttribute("UserId")
                if petUserId and tostring(petUserId) == tostring(LocalPlayer.UserId) then
                    local bigPetGUI = rootPart:FindFirstChild("GUI/BigPetGUI")
                    if bigPetGUI then
                        local stationId = findBigPetStationForPet(rootPart.Position)
                        table.insert(pets, {
                            name = petModel.Name,
                            stationId = stationId,
                            rootPart = rootPart,
                            bigPetGUI = bigPetGUI
                        })
                    end
                end
            end
        end
    end
    
    return pets
end

--[[
    Check if pet is eating
]]
local function isPetEating(petData)
    if not petData or not petData.bigPetGUI then return true end
    local feedGUI = petData.bigPetGUI:FindFirstChild("Feed")
    if not feedGUI or not feedGUI.Visible then return false end
    local feedText = feedGUI:FindFirstChild("TXT")
    if not feedText or not feedText:IsA("TextLabel") then return true end
    local feedTime = feedText.Text
    return feedTime ~= "00:00" and feedTime ~= "???" and feedTime ~= ""
end

--[[
    Equip fruit
]]
local function equipFruit(fruitName)
    if not fruitName or type(fruitName) ~= "string" then return false end
    local ok = pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("CharacterRE"):FireServer("Focus", fruitName)
    end)
    return ok
end

--[[
    Feed pet
]]
local function feedPet(petName)
    if not petName or type(petName) ~= "string" then return false end
    local ok = pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("PetRE"):FireServer("Feed", petName)
    end)
    return ok
end

--[[
    Main loop
]]
function AutoFeed.start()
    isEnabled = true
    debugLog("✅ Auto Feed started")
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                local allBigPets = getBigPets()
                if #allBigPets == 0 then 
                    task.wait(FEED_CHECK_INTERVAL) 
                    return 
                end
                
                for _, petData in ipairs(allBigPets) do
                    if not isEnabled then break end
                    
                    if not isPetEating(petData) then
                        local stationId = petData.stationId
                        local assignedFruits = config.StationAssignments and config.StationAssignments[stationId]
                        
                        if assignedFruits and #assignedFruits > 0 then
                            local fruitName = assignedFruits[1]
                            debugLog(string.format("🍎 Feeding %s at station %s with %s", 
                                petData.name, stationId or "Unknown", fruitName))
                            
                            equipFruit(fruitName)
                            task.wait(0.2)
                            feedPet(petData.name)
                            task.wait(0.5)
                        end
                    end
                end
            end)
            
            task.wait(FEED_CHECK_INTERVAL)
        end
    end)
end

--[[
    Stop auto feed
]]
function AutoFeed.stop()
    isEnabled = false
    debugLog("⏹️ Auto Feed stopped")
end

--[[
    Initialize module
]]
function AutoFeed.init(dependencies)
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
end

return AutoFeed

