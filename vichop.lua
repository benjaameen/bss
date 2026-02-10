-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ EXECUTOR COMPATIBILITY ]] --
local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

-- [[ CONFIGURATION LOAD ]] --
local Config = getgenv().ViciousConfig or {}

-- [[ PROXY CONFIGURATION ]] --
-- PASTE YOUR CLOUDFLARE WORKER URL HERE!
-- Example: "https://bss-proxy.yourname.workers.dev"
local CustomProxy = "https://bss-proxy.arkvldiscord.workers.dev/" 

local ProxyDomains = {
    CustomProxy, -- Priority 1: Your private worker
    "https://games.roproxy.com", -- Backup 1
    "https://public.roproxy.com", -- Backup 2
    "https://roblox-api-proxy.glitch.me" -- Backup 3 (Sometimes works)
}

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
        ["footer"] = { ["text"] = "Benjaameen's Custom Hopper" },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }

    request({
        Url = Config.WebhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({ ["content"] = "@everyone Vicious Bee Found!", ["embeds"] = {embed} })
    })
end

-- [[ SERVER HOP ]] --
local function ServerHop()
    print("Initiating Server Hop...")
    task.wait(math.random(1, 3)) -- Desync
    
    local cursor = ""
    local foundServer = false
    local attempts = 0
    
    while not foundServer and attempts < 15 do
        attempts = attempts + 1
        
        -- Select Proxy (Skip empty custom proxy if not set)
        local currentProxy = ""
        if CustomProxy ~= "" and attempts < 5 then
            currentProxy = CustomProxy -- Try custom proxy first few times
        else
             -- Fallback to public list if custom fails or isn't set
            local validProxies = {}
            for _, p in pairs(ProxyDomains) do
                if p ~= "" then table.insert(validProxies, p) end
            end
            currentProxy = validProxies[math.random(1, #validProxies)]
        end

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
                    print("Teleport hung. Retrying...")
                    foundServer = false
                elseif body.nextPageCursor then
                    cursor = body.nextPageCursor
                else
                    cursor = ""
                end
            end
        else
            warn("Proxy Error (" .. (result and result.StatusCode or "Unknown") .. "). Rotating...")
            task.wait(1)
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
