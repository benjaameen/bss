-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ EXECUTOR COMPATIBILITY ]] --
-- I miss you synapse
local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

-- [[ 1. LOAD CONFIGURATION ]] --
-- We try to get settings from the executor first. If they don't exist (after a hop), we read the file.
local Config = getgenv().ViciousConfig

if not Config then
    if isfile and isfile("ViciousBeeConfig.json") then
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile("ViciousBeeConfig.json"))
        end)
        if success then
            Config = result
            print("Configuration loaded from file successfully.")
        else
            warn("Failed to decode config file. Using defaults.")
        end
    else
        warn("No config file found. Please run the settings script at least once.")
    end
end

-- Fallback defaults to prevent crashes
Config = Config or {}
Config.ValidFields = Config.ValidFields or { ["Pepper Patch"] = true, ["Mountain Top Field"] = true, ["Coco Field"] = true } -- Safe defaults

-- [[ 2. PROXY SETTINGS ]] --

-- SERVER HOPPING PROXIES (Roblox API)
local RobloxProxyDomains = {
    "https://games.roblox.com",
    "https://bss-proxy.arkvldiscord2.workers.dev",
    "https://bss-proxy.arkvldiscord3.workers.dev",
    "https://bss-proxy.arkvldiscord4.workers.dev"
}

-- WEBHOOK PROXY (Discord API)
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
    -- DEBUG: Print what the script *thinks* the URL is
    if not Config.WebhookUrl or Config.WebhookUrl == "" then 
        warn("CRITICAL: Webhook URL is missing in the Config!")
        return 
    end
    
    print("Attempting to send webhook...")

    -- CONSTRUCT URL
    local targetUrl = Config.WebhookUrl
    
    if WebhookProxy ~= "" then
        -- This logic expects your Config.WebhookUrl to be the normal Discord one
        -- It replaces 'discord.com/api' with your proxy
        if string.find(targetUrl, "discord.com") then
            targetUrl = string.gsub(targetUrl, "https://discord.com/api", WebhookProxy)
            print("Using Proxy URL: " .. targetUrl)
        else
            warn("Webhook URL in config does not look like a Discord URL. Sending directly...")
        end
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
        ["footer"] = { ["text"] = "Benjaameen's Proxy Hopper" },
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
            warn("Response: " .. tostring(response.Body))
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
                -- Fix for nil valid fields
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
