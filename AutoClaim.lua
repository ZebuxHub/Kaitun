--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    AUTO CLAIM MODULE                          ║
    ║   Batch claiming money from placed pets                      ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoClaim = {}

-- Dependencies
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies
local debugLog

-- Settings
local config = {}
local isEnabled = false

-- Constants
local BATCH_SIZE = 10

--[[
    Get owned pet names
]]
local function getOwnedPetNames()
    local names = {}
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local data = playerGui and playerGui:FindFirstChild("Data")
    local petsContainer = data and data:FindFirstChild("Pets")
    if petsContainer then
        for _, child in ipairs(petsContainer:GetChildren()) do
            local n = child:IsA("ValueBase") and tostring(child.Value) or tostring(child.Name)
            if n and n ~= "" then table.insert(names, n) end
        end
    end
    return names
end

--[[
    Claim money for pet
]]
local function claimMoneyForPet(petName)
    if not petName or petName == "" then return false end
    local petsFolder = workspace:FindFirstChild("Pets")
    if not petsFolder then return false end
    local petModel = petsFolder:FindFirstChild(petName)
    if not petModel then return false end
    local root = petModel:FindFirstChild("RootPart")
    if not root then return false end
    local re = root:FindFirstChild("RE")
    if not re or not re.FireServer then return false end
    local ok = pcall(function() re:FireServer("Claim") end)
    return ok
end

--[[
    Main loop
]]
function AutoClaim.start()
    isEnabled = true
    debugLog("✅ Auto Claim started")
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                local names = getOwnedPetNames()
                if #names == 0 then 
                    task.wait(1) 
                    return 
                end
                
                -- Batch claiming
                for i = 1, #names, BATCH_SIZE do
                    if not isEnabled then break end
                    for j = i, math.min(i + BATCH_SIZE - 1, #names) do
                        task.spawn(function() 
                            claimMoneyForPet(names[j]) 
                        end)
                    end
                    task.wait(config.ClaimDelay or 1.0)
                end
            end)
            
            task.wait(1)
        end
    end)
end

--[[
    Stop auto claim
]]
function AutoClaim.stop()
    isEnabled = false
    debugLog("⏹️ Auto Claim stopped")
end

--[[
    Initialize module
]]
function AutoClaim.init(dependencies)
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
end

return AutoClaim

