--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    AUTO HATCH MODULE                          ║
    ║   Automatically hatch placed eggs                            ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoHatch = {}

-- Dependencies
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies
local debugLog

-- Settings
local isEnabled = false

-- State
local hatchInFlightByUid = {}

--[[
    Get owner user ID
]]
local function getOwnerUserIdDeep(inst)
    local current = inst
    while current and current ~= workspace do
        if current.GetAttribute then
            local uidAttr = current:GetAttribute("UserId")
            if type(uidAttr) == "number" then return uidAttr end
            if type(uidAttr) == "string" then
                local n = tonumber(uidAttr)
                if n then return n end
            end
        end
        current = current.Parent
    end
    return nil
end

--[[
    Check if player owns instance
]]
local function playerOwnsInstance(inst)
    if not inst then return false end
    local ownerId = getOwnerUserIdDeep(inst)
    return ownerId ~= nil and LocalPlayer and LocalPlayer.UserId == ownerId
end

--[[
    Hatch egg directly
]]
local function hatchEggDirectly(eggUID)
    if hatchInFlightByUid[eggUID] then return false end
    hatchInFlightByUid[eggUID] = true
    
    task.spawn(function()
        pcall(function()
            local eggModel = workspace.PlayerBuiltBlocks:FindFirstChild(eggUID)
            if eggModel and eggModel:FindFirstChild("RootPart") and eggModel.RootPart:FindFirstChild("RF") then
                eggModel.RootPart.RF:InvokeServer("Hatch")
            end
        end)
        task.delay(2, function() hatchInFlightByUid[eggUID] = nil end)
    end)
    
    return true
end

--[[
    Main loop
]]
function AutoHatch.start()
    isEnabled = true
    debugLog("✅ Auto Hatch started")
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                local container = workspace:FindFirstChild("PlayerBuiltBlocks")
                if container then
                    for _, child in ipairs(container:GetChildren()) do
                        if child:IsA("Model") and playerOwnsInstance(child) then
                            local rootPart = child:FindFirstChild("RootPart")
                            if rootPart and rootPart:FindFirstChild("RF") then
                                hatchEggDirectly(child.Name)
                                task.wait(0.1)
                            end
                        end
                    end
                end
            end)
            task.wait(2.0)
        end
    end)
end

--[[
    Stop auto hatch
]]
function AutoHatch.stop()
    isEnabled = false
    debugLog("⏹️ Auto Hatch stopped")
end

--[[
    Initialize module
]]
function AutoHatch.init(dependencies)
    debugLog = dependencies.debugLog or function() end
end

return AutoHatch

