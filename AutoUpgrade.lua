--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                   AUTO UPGRADE MODULE                         ║
    ║   Automatically upgrade conveyor belt                        ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local AutoUpgrade = {}

-- Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Module dependencies
local debugLog

-- Settings
local config = {}
local isEnabled = false

--[[
    Get current conveyor level
]]
local function getCurrentConveyorLevel()
    local player = Players.LocalPlayer
    if not player then return 0 end
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local data = playerGui:FindFirstChild("Data")
    if not data then return 0 end
    local gameFlag = data:FindFirstChild("GameFlag")
    if not gameFlag then return 0 end
    local conveyorLevel = gameFlag:GetAttribute("Conveyor")
    return tonumber(conveyorLevel) or 0
end

--[[
    Get player net worth
]]
local function getPlayerNetWorth()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local data = playerGui:FindFirstChild("Data")
    if not data then return 0 end
    local moneyValue = data:FindFirstChild("Money")
    if not moneyValue then return 0 end
    return tonumber(moneyValue.Value) or 0
end

--[[
    Fire conveyor upgrade
]]
local function fireConveyorUpgrade(index)
    local args = { "Upgrade", tonumber(index) or index }
    local ok = pcall(function()
        ReplicatedStorage:WaitForChild("Remote"):WaitForChild("ConveyorRE"):FireServer(table.unpack(args))
    end)
    return ok
end

--[[
    Main loop
]]
function AutoUpgrade.start()
    isEnabled = true
    debugLog("✅ Auto Upgrade started")
    
    task.spawn(function()
        while isEnabled do
            pcall(function()
                local currentLevel = getCurrentConveyorLevel()
                local targetLevel = config.UpgradeTier or 10
                
                if currentLevel >= targetLevel then
                    task.wait(5)
                else
                    local nextLevel = currentLevel + 1
                    local upgradeCost = config.UpgradeConfig and config.UpgradeConfig[nextLevel]
                    
                    if upgradeCost then
                        local netWorth = getPlayerNetWorth()
                        if netWorth >= upgradeCost then
                            debugLog("⬆️ Upgrading conveyor to level " .. nextLevel)
                            fireConveyorUpgrade(nextLevel)
                            task.wait(1)
                        else
                            task.wait(2)
                        end
                    else
                        task.wait(2)
                    end
                end
            end)
        end
    end)
end

--[[
    Stop auto upgrade
]]
function AutoUpgrade.stop()
    isEnabled = false
    debugLog("⏹️ Auto Upgrade stopped")
end

--[[
    Initialize module
]]
function AutoUpgrade.init(dependencies)
    debugLog = dependencies.debugLog or function() end
    config = dependencies.config or {}
end

return AutoUpgrade

