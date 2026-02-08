-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ EXECUTOR COMPATIBILITY ]] --
-- I miss you synapse, I don't want to say goodbye.
local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

if not request then
    warn("Executor does not support http requests. Webhooks will not work.")
end

-- [[ CONFIGURATION LOAD LOGIC ]] --
-- Try to get settings from getgenv, otherwise load from file
local Config = getgenv().ViciousConfig

if not Config then
    if isfile and isfile("ViciousBeeConfig.json") then
        print("Loading settings from file...")
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile("ViciousBeeConfig.json"))
        end)
        if success then
            Config = result
        else
            warn("Failed to decode settings file!")
        end
    else
        warn("No settings found! Using defaults.")
        Config = {} -- Might want to hardcode defaults here just in case
    end
end

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local JobId = game.JobId

-- [[ AUTO-EXECUTE AFTER HOP ]] --
-- This ensures the script runs again when you land in the new server
if queue_on_teleport then
    queue_on_teleport([[
        task.wait(3) -- Wait for game to load
        loadstring(game:HttpGet("https://raw.githubusercontent.com/benjaameen/bss/main/vichop.lua"))()
    ]])
end

-- [[ VIC FIELD CALCULATION ]] --
local FieldZones = {}

local function CalculateZones()
    -- Clear previous cache
    FieldZones = {}
    local zonesFolder = Workspace:FindFirstChild("FlowerZones")
    if not zonesFolder then 
        warn("Could not find FlowerZones folder!") 
        return 
    end

    for _, part in pairs(zonesFolder:GetChildren()) do
        if part:IsA("BasePart") then
            local pos = part.Position
            local size = part.Size
            FieldZones[part.Name] = {
                MinX = pos.X - (size.X / 2),
                MaxX = pos.X + (size.X / 2),
                MinZ = pos.Z - (size.Z / 2),
                MaxZ = pos.Z + (size.Z / 2)
            }
        end
    end
    print("Calculated boundaries for " .. tostring(#zonesFolder:GetChildren()) .. " fields.")
end

CalculateZones()

-- [[ HELPER FUNCTIONS ]] --
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

local function SendWebhook(beeName, fieldName)
    if not Config.WebhookUrl or Config.WebhookUrl == "" or Config.WebhookUrl == "YOUR_WEBHOOK_URL_HERE" then return end

    local isFull = #Players:GetPlayers() >= (Players.MaxPlayers - 1)
    local status = isFull and "Server Full (Cannot Join)" or "Server Joinable"
    -- Red if full, Green if joinable
    local embedColor = isFull and 16711680 or 65280 

    local embed = {
        ["title"] = "⚠️ Vicious Bee Found! ⚠️",
        ["description"] = string.format("**Finder:** %s\n**Field:** %s\n**Status:** %s", LocalPlayer.Name, fieldName, status),
        ["color"] = embedColor,
        ["fields"] = {
            {
                ["name"] = "Job ID",
                ["value"] = string.format("```%s```", JobId),
                ["inline"] = false
            },
            {
                ["name"] = "Direct Join Script",
                ["value"] = string.format("```lua\ngame:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', game.Players.LocalPlayer)```", PlaceId, JobId),
                ["inline"] = false
            }
        },
        ["footer"] = {
            ["text"] = "Bee Searcher | Xeno/Universal"
        },
        ["timestamp"] = DateTime.now():ToIsoDate()
    }

    local content = isFull and "Vicious bee found, but server is full." or "@everyone Vicious Bee Found!"
    
    local payload = HttpService:JSONEncode({
        ["content"] = content,
        ["embeds"] = {embed}
    })

    request({
        Url = Config.WebhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = payload
    })
end

local function ServerHop()
    print("Initiating Server Hop...")
    local servers = {}
    local cursor = ""
  
    -- Fetch server list
    -- Note: We use a pcall here to prevent script crashing if Roblox API fails
    local success, result = pcall(function()
        return request({
            Url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s", PlaceId, cursor),
            Method = "GET"
        })
    end)

    if success and result and result.Body then
        local body = HttpService:JSONDecode(result.Body)
        if body and body.data then
            for _, v in pairs(body.data) do
                -- Logic: Not current server, Not full, Not blocked
                if type(v) == "table" and v.playing < v.maxPlayers and v.id ~= JobId then
                    table.insert(servers, v.id)
                end
            end
        end
    end

    if #servers > 0 then
        local randomServer = servers[math.random(1, #servers)]
        print("Teleporting to server: " .. randomServer)
        
        TeleportService:TeleportToPlaceInstance(PlaceId, randomServer, LocalPlayer)
        
        task.wait(Config.RetryDelay or 6)
        ServerHop() 
    else
        warn("No valid servers found. Retrying...")
        task.wait(Config.RetryDelay or 6)
        ServerHop()
    end
end

-- [[ MAIN EXECUTION LOOP ]] --
local function Main()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(2) 
    
    local monstersFolder = Workspace:FindFirstChild("Monsters")
    local viciousFound = false
    local targetBee = nil

    print("Scanning for Vicious Bee...")

    if monstersFolder then
        for _, monster in pairs(monstersFolder:GetChildren()) do
            if string.find(monster.Name, "Vicious") and monster:FindFirstChild("HumanoidRootPart") then
                local pos = monster.HumanoidRootPart.Position
                local detectedField = GetFieldFromPosition(pos)
                
                if detectedField and Config.ValidFields[detectedField] then
                    viciousFound = true
                    targetBee = monster
                    print(">> Vicious Bee found in: " .. detectedField)
                    SendWebhook(monster.Name, detectedField)
                    break 
                elseif not detectedField then
                    print("Found Vicious Bee, but outside known flower zones.")
                else
                    print("Found Vicious Bee in " .. detectedField .. " (Disabled in settings).")
                end
            end
        end
    end

    if viciousFound and targetBee then
        print("Bee found! Waiting for it to be defeated/despawn...")
        
        while targetBee.Parent == monstersFolder do
            task.wait(1)
        end
        
        print("Bee is gone! Resuming server hop in " .. (Config.AfterKillDelay or 5) .. " seconds.")
        task.wait(Config.AfterKillDelay or 5)
        ServerHop()
    else
        print("No Vicious Bee found. Hopping...")
        task.wait(Config.HopDelay or 4)
        ServerHop()
    end
end

Main()
