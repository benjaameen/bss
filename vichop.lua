-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ EXECUTOR COMPATIBILITY ]] --
local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

-- [[ CONFIGURATION LOAD ]] --
local Config = getgenv().ViciousConfig
if not Config then
    -- Fallback if file reading fails
    if isfile and isfile("ViciousBeeConfig.json") then
        pcall(function()
            Config = HttpService:JSONDecode(readfile("ViciousBeeConfig.json"))
        end)
    end
end
-- Last resort defaults
Config = Config or { RetryDelay = 6, HopDelay = 4, UseFieldChecks = false }

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local JobId = game.JobId

-- [[ QUEUE ON TELEPORT ]] --
-- This keeps the script running on the next server
if queue_on_teleport then
    queue_on_teleport([[
        task.wait(5)
        loadstring(game:HttpGet("https://raw.githubusercontent.com/benjaameen/bss/main/vichop.lua"))()
    ]])
end

-- [[ FIELD ZONES ]] --
local FieldZones = {}
local function CalculateZones()
    local zonesFolder = Workspace:FindFirstChild("FlowerZones")
    if zonesFolder then
        for _, part in pairs(zonesFolder:GetChildren()) do
            if part:IsA("BasePart") then
                local pos = part.Position
                local size = part.Size
                FieldZones[part.Name] = {
                    MinX = pos.X - (size.X / 2), MaxX = pos.X + (size.X / 2),
                    MinZ = pos.Z - (size.Z / 2), MaxZ = pos.Z + (size.Z / 2)
                }
            end
        end
    end
end
CalculateZones()

local function GetFieldFromPosition(position)
    if not Config.UseFieldChecks then return "Unknown (Checks Disabled)" end
    for fieldName, bounds in pairs(FieldZones) do
        if position.X >= bounds.MinX and position.X <= bounds.MaxX and
           position.Z >= bounds.MinZ and position.Z <= bounds.MaxZ then
            return fieldName
        end
    end
    return nil
end

-- [[ WEBHOOK ]] --
local function SendWebhook(beeName, fieldName)
    if not Config.WebhookUrl or Config.WebhookUrl == "" or string.find(Config.WebhookUrl, "discord") == nil then return end
    
    local isFull = #Players:GetPlayers() >= (Players.MaxPlayers - 1)
    local status = isFull and "Server Full" or "Server Joinable"
    local embedColor = isFull and 16711680 or 65280 

    local embed = {
        ["title"] = "⚠️ Vicious Bee Found! ⚠️",
        ["description"] = string.format("**Finder:** %s\n**Field:** %s\n**Status:** %s", LocalPlayer.Name, fieldName, status),
        ["color"] = embedColor,
        ["fields"] = {
            { ["name"] = "Job ID", ["value"] = string.format("```%s```", JobId), ["inline"] = false },
            { ["name"] = "Join Script", ["value"] = string.format("```lua\ngame:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', game.Players.LocalPlayer)```", PlaceId, JobId), ["inline"] = false }
        },
        ["footer"] = { ["text"] = "Benjaameen's Hopper" },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }

    request({
        Url = Config.WebhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({ ["content"] = "@everyone Vicious Bee Found!", ["embeds"] = {embed} })
    })
end

-- [[ OPTIMIZED SERVER HOP ]] --
local function ServerHop()
    print("Initiating Server Hop...")
    
    -- RANDOM DELAY: Crucial for multiple accounts to avoid IP bans/sync issues
    task.wait(math.random(1, 4))
    
    local cursor = ""
    local foundServer = false
    local attempts = 0
    
    while not foundServer and attempts < 10 do -- Prevent infinite loop, try 10 pages
        attempts = attempts + 1
        
        local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s", PlaceId, cursor)
        local response = request({Url = url, Method = "GET"})
        
        if response and response.StatusCode == 200 then
            local body = HttpService:JSONDecode(response.Body)
            if body and body.data then
                local servers = {}
                for _, v in pairs(body.data) do
                    -- Check if server is valid (not full, not current)
                    if type(v) == "table" and v.playing < v.maxPlayers and v.id ~= JobId then
                        table.insert(servers, v.id)
                    end
                end
                
                if #servers > 0 then
                    -- Found servers! Pick one random
                    foundServer = true
                    local targetServer = servers[math.random(1, #servers)]
                    print("Teleporting to: " .. targetServer)
                    
                    TeleportService:TeleportToPlaceInstance(PlaceId, targetServer, LocalPlayer)
                    
                    -- Wait for teleport to happen
                    task.wait(10)
                    -- If code reaches here, teleport failed. Retry loop.
                    print("Teleport failed/timed out. Retrying...")
                    foundServer = false
                end
                
                -- Pagination logic
                if body.nextPageCursor then
                    cursor = body.nextPageCursor
                else
                    -- No more pages, restart cursor
                    cursor = ""
                end
            end
        elseif response and response.StatusCode == 429 then
            warn("Rate limited (429). Waiting 15 seconds...")
            task.wait(15)
        else
            warn("Failed to fetch servers. Retrying...")
            task.wait(2)
        end
    end
    
    -- If we exited the loop without hopping, just retry the function
    task.wait(2)
    ServerHop()
end

-- [[ MAIN LOGIC ]] --
local function Main()
    if not game:IsLoaded() then game.Loaded:Wait() end
    -- Initial wait to let world load
    task.wait(3)
    
    local monsters = Workspace:FindFirstChild("Monsters")
    local found = false
    local target = nil
    
    print("Scanning for Vicious Bee...")
    
    if monsters then
        for _, mob in pairs(monsters:GetChildren()) do
            if string.find(mob.Name, "Vicious") and mob:FindFirstChild("HumanoidRootPart") then
                local field = GetFieldFromPosition(mob.HumanoidRootPart.Position)
                
                if field then
                    if Config.ValidFields[field] then
                        found = true
                        target = mob
                        print("!! FOUND VICIOUS BEE IN " .. field .. " !!")
                        SendWebhook(mob.Name, field)
                        break
                    else
                        print("Found Vicious Bee in " .. field .. " (Ignored by config)")
                    end
                else
                    print("Found Vicious Bee outside known fields.")
                end
            end
        end
    end
    
    if found and target then
        -- Wait for kill
        print("Waiting for bee to die...")
        local start = tick()
        while target.Parent == monsters and (tick() - start) < 600 do -- 10 min timeout
            task.wait(1)
        end
        print("Bee processed. Hopping in " .. (Config.AfterKillDelay or 5) .. "s")
        task.wait(Config.AfterKillDelay or 5)
        ServerHop()
    else
        print("Not found. Hopping in " .. (Config.HopDelay or 4) .. "s")
        task.wait(Config.HopDelay or 4)
        ServerHop()
    end
end

Main()
