local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer or Players:GetChildAdded():Wait()

local PROXY_URL = "https://bss-proxy.benjaameen.workers.dev"
local queue_teleport = queue_on_teleport or syn.queue_on_teleport or fluxus.queue_on_teleport

local function hop()
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local apiUrl = string.format("%s/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true", PROXY_URL, placeId)
    
    local success, response = pcall(function()
        return game:HttpGet(apiUrl)
    end)

    if success then
        local data = game:GetService("HttpService"):JSONDecode(response)
        if data and data.data then
            for _, server in ipairs(data.data) do
                if server.id ~= currentJobId and server.playing < server.maxPlayers then
                    
                    if queue_teleport then
                        queue_teleport([[
                            repeat task.wait() until game:IsLoaded()
                            loadstring(game:HttpGet("https://raw.githubusercontent.com/benjaameen/bss/main/server-hop.lua"))()
                        ]])
                    end

                    TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                    break
                end
            end
        end
    end
end

hop()
