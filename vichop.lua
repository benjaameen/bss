-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ EXECUTOR COMPATIBILITY ]] --
-- I miss you synapse
local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

-- [[ CONFIGURATION LOAD ]] --
local Config = getgenv().ViciousConfig or {}

-- [[ PROXIES ]] --

-- 1. SERVER HOP PROXIES (For Roblox API)
local RobloxProxyDomains = {
    "https://games.roblox.com", -- Home Proxy
    "https://bss-proxy.arkvldiscord2.workers.dev",
    "https://bss-proxy.arkvldiscord3.workers.dev",
    "https://bss-proxy.arkvldiscord4.workers.dev"
}

-- 2. WEBHOOK PROXY (For Discord API)
local WebhookProxy = "https://discord-proxy.arkvldiscord.workers.dev/" 

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local JobId = game.JobId

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
    if Config.UseFieldChecks == false then return "Unknown (Checks Disabled)" end
    for fieldName, bounds in pairs(FieldZones) do
        if position.X >= bounds.MinX and position.X <= bounds.MaxX and
           position.Z >= bounds.MinZ and position.Z <= bounds.MaxZ then
            return fieldName
        end
    end
    return nil
end

-- [[ WEBHOOK SENDER ]] --
local function SendWebhook(beeName, fieldName)
    if not Config.WebhookUrl or Config.WebhookUrl == "" then 
        warn("Webhook URL missing.")
        return 
    end
    
    print("Attempting to send webhook...")

    -- CONSTRUCT URL
    -- If WebhookProxy is set, we replace 'discord.com/api' with the proxy URL
    local targetUrl = Config.WebhookUrl
    if WebhookProxy ~= "" then
        -- This regex replaces https://discord.com/api/webhooks/ID/TOKEN with proxy
        targetUrl = string.gsub(targetUrl, "https://discord.com/api", WebhookProxy)
    end

    local isFull = #Players:GetPlayers() >= (Players.MaxPlayers - 1)
    local status = isFull and "Server Full" or "Server Joinable"
    local embedColor = isFull and 16711680 or 65280 

    local pingContent = "@everyone Vicious Bee Found!"
    if Config.UserId and tostring(Config.UserId) ~= "" then
        pingContent = string.format("<@%s> Vicious Bee Found!", tostring(Config.UserId))
    end

    local embed = {
        ["title"] = "⚠️ Vicious Bee Found! ⚠️",
        ["description"] = string.format("**Finder:** %s\n**Field:** %s\n**Status:** %s", LocalPlayer.Name, fieldName, status),
        ["color"] = embedColor,
        ["fields"] = {
            { ["name"] = "Job ID", ["value"] = string.format("```%s```", JobId), ["inline"] = false },
            { ["name"] = "Join Script", ["value"] = string.format("```lua\ngame:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', game.Players.LocalPlayer)```", PlaceId, JobId), ["inline"] = false }
        },
        ["footer"] = { ["text"] = "Benjaameen's Custom Hopper" },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }

    local payload = HttpService:JSONEncode({
        ["content"] = pingContent,
        ["embeds"] = {embed},
        ["username"] = "Vicious Bee Tracker",
        ["avatar_url"] = "https://tr.rbxcdn.com/e8c460136d8d933390c9b0e27db68541/150/150/Image/Png"
    })

    local success, response = pcall(function()
        return request({
            Url = targetUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        })
    end)

    if success then
        if response.StatusCode == 204 or response.StatusCode == 200 then
            print("Webhook sent successfully!")
        else
            warn("Webhook Failed! Code: " .. tostring(response.StatusCode))
            -- If 404, it means the proxy URL is wrong or the worker code isn't deployed right
            -- If 429, the proxy is handling rate limits (wait and retry happens inside the proxy usually, or here)
        end
    else
        warn("Webhook Request Error: " .. tostring(response))
    end
end

-- [[ SERVER HOP ]] --
local function ServerHop()
    print("Initiating Server Hop...")
    task.wait(math.random(1, 3))
    
    local cursor = ""
    local foundServer = false
    local attempts = 0
    
    while not foundServer and attempts < 15 do
        attempts = attempts + 1
        
        local currentProxy = RobloxProxyDomains[math.random(1, #RobloxProxyDomains)]
        local url = string.format("%s/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s", currentProxy, PlaceId, cursor)
        print("Scanning via: " .. currentProxy)
        
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
                    task.wait(8)
                    foundServer = false
                elseif body.nextPageCursor then
                    cursor = body.nextPageCursor
                else
                    cursor = ""
                end
            end
        else
            warn("Proxy Error (" .. (result and result.StatusCode or "Unknown") .. "). Rotating...")
            task.wait(0.5)
        end
    end
    
    warn("Hop loop ended without success. Retrying...")
    task.wait(5)
    ServerHop()
end

-- [[ MAIN ]] --
local function Main()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(3)
    
    local monsters = Workspace:FindFirstChild("Monsters")
    local found = false
    local target = nil
    
    if monsters then
        for _, mob in pairs(monsters:GetChildren()) do
            if string.find(mob.Name, "Vicious") and mob:FindFirstChild("HumanoidRootPart") then
                local field = GetFieldFromPosition(mob.HumanoidRootPart.Position)
                local isValid = field and (Config.ValidFields == nil or Config.ValidFields[field] == true)
                
                if isValid then
                    found = true
                    target = mob
                    print("!! VICIOUS BEE FOUND IN " .. field .. " !!")
                    SendWebhook(mob.Name, field)
                    break
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
