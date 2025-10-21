--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    CACHE MANAGER MODULE                       ║
    ║   Optimized attribute caching to reduce expensive reads       ║
    ╚═══════════════════════════════════════════════════════════════╝
--]]

local CacheManager = {}

-- Cache storage
local attributeCache = {} -- [uid] = {mutation, eggType, speed, petType, etc}
local speedCache = {} -- [uid] = speed (from UI)
local cacheTimestamps = {} -- [uid] = tick()

-- Cache settings
local CACHE_EXPIRY = 300 -- Cache expires after 5 minutes (attributes rarely change)
local SPEED_CACHE_EXPIRY = 60 -- Speed cache expires after 1 minute

--[[
    Get cached attributes for an item (egg/pet)
    Returns cached data or reads and caches it
]]
function CacheManager.getAttributes(node)
    if not node then return nil end
    
    local uid = node.Name
    local now = tick()
    
    -- Check if cache exists and is valid
    if attributeCache[uid] and cacheTimestamps[uid] then
        if now - cacheTimestamps[uid] < CACHE_EXPIRY then
            return attributeCache[uid]
        end
    end
    
    -- Cache miss or expired - read attributes
    local attributes = {
        mutation = node:GetAttribute("Mutation"),
        eggType = node:GetAttribute("EggType"),
        petType = node:GetAttribute("PetType"),
        speed = node:GetAttribute("Speed"),
        uid = uid
    }
    
    -- Store in cache
    attributeCache[uid] = attributes
    cacheTimestamps[uid] = now
    
    return attributes
end

--[[
    Get pet speed from UI (expensive operation - cache it!)
]]
function CacheManager.getPetSpeed(node, forceRefresh)
    if not node then return 0 end
    
    local uid = node.Name
    local now = tick()
    
    -- Check cache (unless force refresh)
    if not forceRefresh and speedCache[uid] then
        local cacheTime = cacheTimestamps["speed_" .. uid]
        if cacheTime and now - cacheTime < SPEED_CACHE_EXPIRY then
            return speedCache[uid]
        end
    end
    
    -- Cache miss - read from UI
    local speed = 0
    pcall(function()
        local gui = node:FindFirstChild("GUI")
        if gui then
            local billboard = gui:FindFirstChild("BillboardGui")
            if billboard then
                local frame = billboard:FindFirstChild("Frame")
                if frame then
                    local speedLabel = frame:FindFirstChild("Speed")
                    if speedLabel and speedLabel:IsA("TextLabel") then
                        local speedText = speedLabel.Text
                        local speedNum = tonumber(speedText:match("%d+%.?%d*"))
                        if speedNum then
                            speed = speedNum
                        end
                    end
                end
            end
        end
    end)
    
    -- Store in cache
    speedCache[uid] = speed
    cacheTimestamps["speed_" .. uid] = now
    
    return speed
end

--[[
    Invalidate cache for a specific UID (when item is removed/sold)
]]
function CacheManager.invalidate(uid)
    attributeCache[uid] = nil
    speedCache[uid] = nil
    cacheTimestamps[uid] = nil
    cacheTimestamps["speed_" .. uid] = nil
end

--[[
    Clear all caches (use sparingly)
]]
function CacheManager.clearAll()
    attributeCache = {}
    speedCache = {}
    cacheTimestamps = {}
end

--[[
    Get cache statistics (for debugging)
]]
function CacheManager.getStats()
    local attributeCount = 0
    local speedCount = 0
    
    for _ in pairs(attributeCache) do
        attributeCount = attributeCount + 1
    end
    
    for _ in pairs(speedCache) do
        speedCount = speedCount + 1
    end
    
    return {
        attributesCached = attributeCount,
        speedsCached = speedCount,
        totalEntries = attributeCount + speedCount
    }
end

--[[
    Cleanup expired cache entries (run periodically)
]]
function CacheManager.cleanup()
    local now = tick()
    local cleaned = 0
    
    -- Clean attribute cache
    for uid, timestamp in pairs(cacheTimestamps) do
        if now - timestamp > CACHE_EXPIRY then
            if uid:match("^speed_") then
                local actualUid = uid:gsub("^speed_", "")
                speedCache[actualUid] = nil
            else
                attributeCache[uid] = nil
            end
            cacheTimestamps[uid] = nil
            cleaned = cleaned + 1
        end
    end
    
    return cleaned
end

return CacheManager

