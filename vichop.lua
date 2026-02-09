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
    if isfile and isfile("ViciousBeeConfig.json") then
        pcall(function()
            Config = HttpService:JSONDecode(readfile("ViciousBeeConfig.json"))
        end)
    end
end
-- Defaults
Config = Config or { RetryDelay = 6, HopDelay = 4, UseFieldChecks = true, WebhookUrl = "" }

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local JobId = game.JobId

-- [[ PROXY LIST ]] --
-- These are public mirrors of the Roblox API. They prevent your IP from getting rate-limited.
local ProxyDomains = {
    "https://games.roproxy.com",
    "https://public.roproxy.com"
    -- Add more here if you find other working Roblox API mirrors
}

-- [[ QUEUE ON TELEPORT ]] --
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
        ["footer"] = { ["text"] = "Benjaameen's Proxy Hopper" },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }

    request({
        Url = Config.WebhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({ ["content"] = "@everyone Vicious Bee Found!", ["embeds"] = {embed} })
    })
end

-- [[ SERVER HOP WITH PROXY ROTATION ]] --
local function ServerHop()
    print("Initiating Server Hop...")
    
    -- Desync accounts
    task.wait(math.random(1, 3))
    
    local cursor = ""
    local foundServer = false
    local attempts = 0
    
    -- Try scanning up to 10 pages
    while not foundServer and attempts < 10 do
        attempts = attempts + 1
        
        -- Pick a random proxy from the list
        local currentProxy = ProxyDomains[math.random(1, #ProxyDomains)]
        local url = string.format("%s/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s", currentProxy, PlaceId, cursor)
        
        print("Scanning servers via: " .. currentProxy)
        
        local success, result = pcall(function()
            return request({Url = url, Method = "GET"})
        end)
        
        if success and result and result.StatusCode == 200 then
            local body = HttpService:JSONDecode(result.Body)
            if body and body.data then
                local servers = {}
                for _, v in pairs(body.data) do
                    if type(v) == "table" and v.playing < v.maxPlayers and v.id ~= JobId then
                        table.insert(servers, v.id)
                    end
                end
                
                if #servers > 0 then
                    foundServer = true
                    local targetServer = servers[math.random(1, #servers)]
                    print("Teleporting to: " .. targetServer)
                    
                    TeleportService:TeleportToPlaceInstance(PlaceId, targetServer, LocalPlayer)
                    
                    -- Wait for teleport
                    task.wait(8)
                    print("Teleport hang detected. Retrying...")
                    foundServer = false -- Force retry if we are still here
                end
                
                if body.nextPageCursor then
                    cursor = body.nextPageCursor
                else
                    cursor = "" -- Reset cursor to start over if we ran out of pages
                end
            end
        elseif success and result and result.StatusCode == 429 then
            warn("Proxy 429 (Rate Limit). Swapping proxy and retrying...")
            -- Don't wait long, just swap proxy next loop
            task.wait(1) 
        else
            warn("Proxy Failed. Retrying...")
            task.wait(1)
        end
    end
    
    -- Fallback if loop finishes without hop
    warn("Scan finished with no valid servers. Retrying in 5s...")
    task.wait(5)
    ServerHop()
end

-- [[ MAIN LOGIC ]] --
local function Main()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(3)
    
    local monsters = Workspace:FindFirstChild("Monsters")
    local found = false
    local target = nil
    
    print("Scanning for Vicious Bee...")
    
    if monsters then
        for _, mob in pairs(monsters:GetChildren()) do
            if string.find(mob.Name, "Vicious") and mob:FindFirstChild("HumanoidRootPart") then
                local field = GetFieldFromPosition(mob.HumanoidRootPart.Position)
                
                if field and Config.ValidFields[field] then
                    found = true
                    target = mob
                    print("!! FOUND VICIOUS BEE IN " .. field .. " !!")
                    SendWebhook(mob.Name, field)
                    break
                elseif field then
                    print("Vicious Bee in " .. field .. " (Ignored)")
                else
                    print("Vicious Bee outside known fields.")
                end
            end
        end
    end
    
    if found and target then
        local start = tick()
        while target.Parent == monsters and (tick() - start) < 600 do
            task.wait(1)
        end
        task.wait(Config.AfterKillDelay or 5)
        ServerHop()
    else
        task.wait(Config.HopDelay or 4)
        ServerHop()
    end
end

Main()
