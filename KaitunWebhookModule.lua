--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║         🦁 ZEBUX KAITUN - WEBHOOK MODULE 🦁                  ║
    ║   Extracted from Kaitun_SelfContained.lua                    ║
    ║   Load from GitHub to reduce main file size                  ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local WebhookModule = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Helper function to get today's gift count
local function getTodayGiftCount()
    if not LocalPlayer or not LocalPlayer.PlayerGui or not LocalPlayer.PlayerGui.Data then
        return 0
    end
    
    local userFlag = LocalPlayer.PlayerGui.Data:FindFirstChild("UserFlag")
    if not userFlag then return 0 end
    
    local success, result = pcall(function()
        return userFlag:GetAttribute("TodaySendGiftCount")
    end)
    return success and result or 0
end

-- Helper function to get player tickets
local function getPlayerTickets()
    if not LocalPlayer then return 0 end
    local attrValue = LocalPlayer:GetAttribute("Ticket")
    if type(attrValue) == "number" then return attrValue end
    if type(attrValue) == "string" then return tonumber(attrValue) or 0 end
    return 0
end

-- Function to get fruit inventory
function WebhookModule.getFruitInventory()
    local fruits = {}
    
    if not LocalPlayer then return fruits end
    
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return fruits end
    
    local data = playerGui:FindFirstChild("Data")
    if not data then return fruits end
    
    local asset = data:FindFirstChild("Asset")
    if not asset then return fruits end
    
    -- Load fruit data dynamically from game's ResPetFood module
    local FruitData = {}
    pcall(function()
        local cfgFolder = ReplicatedStorage:FindFirstChild("Config")
        if cfgFolder then
            local fruitModule = cfgFolder:FindFirstChild("ResPetFood")
            if fruitModule then
                FruitData = require(fruitModule)
            end
        end
    end)
    
    -- If no module found, return empty
    if not next(FruitData) then
        return fruits
    end
    
    -- Read from Attributes
    local ok, attrs = pcall(function()
        return asset:GetAttributes()
    end)
    if ok and type(attrs) == "table" then
        for id, item in pairs(FruitData) do
            if type(item) == "table" then
                local display = item.Name or id
                local amount = attrs[display] or attrs[id]
                if type(amount) == "string" then amount = tonumber(amount) or 0 end
                if type(amount) == "number" and amount > 0 then
                    fruits[display] = amount
                end
            end
        end
    end
    
    return fruits
end

-- Function to get pet inventory (unplaced pets only)
function WebhookModule.getPetInventory()
    local pets = {}
    
    if not LocalPlayer then return pets end
    
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return pets end
    
    local data = playerGui:FindFirstChild("Data")
    if not data then return pets end
    
    local petContainer = data:FindFirstChild("Pets")
    if not petContainer then return pets end
    
    for _, child in ipairs(petContainer:GetChildren()) do
        if child:IsA("Configuration") then
            local dAttr = child:GetAttribute("D")
            local petType = child:GetAttribute("T")
            local mutation = child:GetAttribute("M")
            
            -- Only count unplaced pets (no D attribute)
            if not dAttr and petType then
                if mutation == "Dino" then mutation = "Jurassic" end
                
                if not pets[petType] then
                    pets[petType] = { total = 0, mutations = {} }
                end
                
                pets[petType].total = pets[petType].total + 1
                
                if mutation then
                    if not pets[petType].mutations[mutation] then
                        pets[petType].mutations[mutation] = 0
                    end
                    pets[petType].mutations[mutation] = pets[petType].mutations[mutation] + 1
                end
            end
        end
    end
    
    return pets
end

-- Function to get egg inventory (unhatched eggs only)
function WebhookModule.getEggInventory()
    local eggs = {}
    
    if not LocalPlayer then return eggs end
    
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return eggs end
    
    local data = playerGui:FindFirstChild("Data")
    if not data then return eggs end
    
    local eggContainer = data:FindFirstChild("Egg")
    if not eggContainer then return eggs end
    
    for _, child in ipairs(eggContainer:GetChildren()) do
        if child:IsA("Configuration") then
            local dAttr = child:GetAttribute("D")
            local eggType = child:GetAttribute("T")
            local mutation = child:GetAttribute("M")
            
            -- Only count unhatched eggs (no D attribute)
            if not dAttr and eggType then
                if mutation == "Dino" then mutation = "Jurassic" end
                
                if not eggs[eggType] then
                    eggs[eggType] = { total = 0, mutations = {} }
                end
                
                eggs[eggType].total = eggs[eggType].total + 1
                
                if mutation then
                    if not eggs[eggType].mutations[mutation] then
                        eggs[eggType].mutations[mutation] = 0
                    end
                    eggs[eggType].mutations[mutation] = eggs[eggType].mutations[mutation] + 1
                end
            end
        end
    end
    
    return eggs
end

-- Function to create inventory embed
function WebhookModule.createInventoryEmbed(netWorth, formatNumber)
    local tickets = getPlayerTickets()
    local username = LocalPlayer and LocalPlayer.Name or "Unknown"
    local todayGifts = getTodayGiftCount()
    
    -- Get inventories
    local fruits = WebhookModule.getFruitInventory()
    local pets = WebhookModule.getPetInventory()
    local eggs = WebhookModule.getEggInventory()
    
    -- Sort fruits by count
    local sortedFruits = {}
    for fruitName, count in pairs(fruits) do
        table.insert(sortedFruits, {name = fruitName, count = count})
    end
    table.sort(sortedFruits, function(a, b) return a.count > b.count end)
    
    -- Build fruit list
    local fruitValue = "```diff\n"
    for i, fruitData in ipairs(sortedFruits) do
        fruitValue = fruitValue .. "+ " .. fruitData.name .. " × " .. fruitData.count .. "\n"
        if i >= 10 then break end
    end
    fruitValue = fruitValue .. "```"
    
    if #sortedFruits == 0 then 
        fruitValue = "```diff\nNo fruits found```" 
    end
    
    -- Build pet field (top 5)
    local petValue = "```diff\n"
    local petArr = {}
    for petType, petData in pairs(pets) do
        table.insert(petArr, { name = petType, total = petData.total, mutations = petData.mutations })
    end
    table.sort(petArr, function(a, b) return a.total > b.total end)
    
    for i = 1, math.min(5, #petArr) do
        local it = petArr[i]
        petValue = petValue .. "🐾 " .. it.name .. " × " .. it.total .. "\n"
        
        local mutsArr = {}
        for m, c in pairs(it.mutations) do table.insert(mutsArr, { m = m, c = c }) end
        table.sort(mutsArr, function(a, b) return a.c > b.c end)
        
        for j = 1, math.min(5, #mutsArr) do
            petValue = petValue .. "L 🧬 " .. mutsArr[j].m .. " × " .. mutsArr[j].c .. "\n"
        end
        if i < math.min(5, #petArr) then petValue = petValue .. "\n" end
    end
    
    if #petArr == 0 then
        petValue = "```diff\nNo pets found```"
    else
        petValue = petValue .. "```"
    end
    
    -- Build egg field (top 5)
    local eggValue = "```diff\n"
    local eggArr = {}
    for eggType, eggData in pairs(eggs) do
        table.insert(eggArr, { name = eggType, total = eggData.total, mutations = eggData.mutations })
    end
    table.sort(eggArr, function(a, b) return a.total > b.total end)
    
    for i = 1, math.min(5, #eggArr) do
        local it = eggArr[i]
        eggValue = eggValue .. "🏆 " .. it.name .. " × " .. it.total .. "\n"
        
        local mutsArr = {}
        for m, c in pairs(it.mutations) do table.insert(mutsArr, { m = m, c = c }) end
        table.sort(mutsArr, function(a, b) return a.c > b.c end)
        
        for j = 1, math.min(5, #mutsArr) do
            eggValue = eggValue .. "L 🧬 " .. mutsArr[j].m .. " × " .. mutsArr[j].c .. "\n"
        end
        if i < math.min(5, #eggArr) then eggValue = eggValue .. "\n" end
    end
    
    if #eggArr == 0 then
        eggValue = "```diff\nNo eggs found```"
    else
        eggValue = eggValue .. "```"
    end
    
    -- Create embed
    local embed = {
        content = nil,
        embeds = {
            {
                title = "📊 Kaitun Inventory Snapshot",
                color = 16761095,
                fields = {
                    {
                        name = "User: " .. username,
                        value = "💰 Net Worth:  `" .. formatNumber(netWorth) .. "`\n<:Ticket:1414283452659798167> Ticket: `" .. formatNumber(tickets) .. "`\n🎁 Today Gifts: `" .. todayGifts .. "/500`"
                    },
                    {
                        name = "🪣 Fruits",
                        value = fruitValue,
                    },
                    {
                        name = "🐾 Pets",
                        value = petValue,
                        inline = true
                    },
                    {
                        name = "🥚 Top Eggs",
                        value = eggValue,
                        inline = true
                    }
                },
                footer = {
                    text = "Zebux Kaitun • Build A Zoo"
                }
            }
        },
        attachments = {}
    }
    
    return embed
end

-- Function to send webhook
function WebhookModule.sendWebhook(webhookUrl, embedData, debugLog)
    if not webhookUrl or webhookUrl == "" then
        if debugLog then debugLog("⚠️ Webhook: No URL configured") end
        return false
    end
    
    local success, result = false, "No method available"
    
    -- Try different HTTP methods
    if not success and http_request then
        success, result = pcall(function()
            local response = http_request({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(embedData)
            })
            return response
        end)
        if success and result and result.StatusCode and result.StatusCode >= 200 and result.StatusCode < 300 then
            success = true
        end
    end
    
    if not success and _G.request then
        success, result = pcall(function()
            return _G.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(embedData)
            })
        end)
    end
    
    if not success and syn and syn.request then
        success, result = pcall(function()
            return syn.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(embedData)
            })
        end)
    end
    
    if success then
        if debugLog then debugLog("✅ Webhook sent successfully") end
        return true
    else
        if debugLog then debugLog("❌ Webhook failed: " .. tostring(result)) end
        return false
    end
end

return WebhookModule

