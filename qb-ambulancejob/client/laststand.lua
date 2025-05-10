Laststand = Laststand or {}
InLaststand = false
LaststandTime = 0
lastStandDict = 'combat@damage@writhe'
lastStandAnim = 'writhe_loop'
isEscorted = false
local isEscorting = false
local isInCriticalState = false

local function StartLaststandTimer()
    CreateThread(function()
        while InLaststand and not isInCriticalState do
            Wait(1000)
            if LaststandTime > 0 then
                LaststandTime = LaststandTime - 1
                
                TriggerServerEvent('hospital:server:SetLaststandTime', LaststandTime)
                SendNUIMessage({
                    action = 'updateTimer',
                    time = LaststandTime
                })

                if LaststandTime <= 0 then
                    isInCriticalState = true
                    LaststandTime = 0
                    
                    TriggerServerEvent('hospital:server:SetLaststandTime', LaststandTime)
                    TriggerServerEvent('hospital:server:SetCriticalState', true)
                    
                    SendNUIMessage({
                        action = 'setCritical',
                        critical = true,
                        emsCooldown = Config.DocCooldown * 60
                    })
                    QBCore.Functions.Notify('You are now in critical condition', 'error')
                    break
                end
            end
        end
    end)
end
local function LoadAnimation(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(100)
    end
end

local function GetClosestPlayer()
    local closestPlayers = QBCore.Functions.GetPlayersFromCoords()
    local closestDistance = -1
    local closestPlayer = -1
    local coords = GetEntityCoords(PlayerPedId())

    for i = 1, #closestPlayers, 1 do
        if closestPlayers[i] ~= PlayerId() then
            local pos = GetEntityCoords(GetPlayerPed(closestPlayers[i]))
            local distance = #(pos - coords)

            if closestDistance == -1 or closestDistance > distance then
                closestPlayer = closestPlayers[i]
                closestDistance = distance
            end
        end
    end

    return closestPlayer, closestDistance
end

function SetLaststand(bool)
    local ped = PlayerPedId()

    TriggerServerEvent('hospital:server:SetLaststandStatus', bool)
    
    if bool then
        LaststandTime = Config.DeathTime
        isInCriticalState = false

        TriggerServerEvent('hospital:server:SetLaststandTime', LaststandTime)
        Wait(1000)
        while GetEntitySpeed(ped) > 0.5 or IsPedRagdoll(ped) do Wait(10) end
        local pos = GetEntityCoords(ped)
        
        SendNUIMessage({
            action = 'show'
        })
        
        QBCore.Functions.TriggerCallback('hospital:server:getEmsCount', function(amount)
            if amount < Config.MinimalDoctors then
                SendNUIMessage({
                    action = 'setStatus',
                    status = 'no_ems'
                })
            end
        end)
        local heading = GetEntityHeading(ped)
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'demo', 0.1)

        if IsPedInAnyVehicle(ped) then
            local veh = GetVehiclePedIsIn(ped)
            local vehseats = GetVehicleModelNumberOfSeats(GetHashKey(GetEntityModel(veh)))
            for i = -1, vehseats do
                local occupant = GetPedInVehicleSeat(veh, i)
                if occupant == ped then
                    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z + 0.5, heading, true, false)
                    SetPedIntoVehicle(ped, veh, i)
                end
            end
        else
            NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z + 0.5, heading, true, false)
        end
        SetEntityHealth(ped, 150)
        if IsPedInAnyVehicle(ped, false) then
            LoadAnimation('veh@low@front_ps@idle_duck')
            TaskPlayAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 1.0, 8.0, -1, 1, -1, false, false, false)
        else
            LoadAnimation(lastStandDict)
            TaskPlayAnim(ped, lastStandDict, lastStandAnim, 1.0, 8.0, -1, 1, -1, false, false, false)
        end
        InLaststand = true

        SendNUIMessage({
            action = 'show'
        })
        SendNUIMessage({
            action = 'updateTimer',
            time = LaststandTime
        })

        SendNUIMessage({
            action = 'setCritical',
            critical = false,
            emsCooldown = Config.DocCooldown * 60 
        })
        
        SetNuiFocus(true, false)

        TriggerServerEvent('hospital:server:ambulanceAlert', Lang:t('info.civ_down'))
        StartLaststandTimer()
    else
        TaskPlayAnim(ped, lastStandDict, 'exit', 1.0, 8.0, -1, 1, -1, false, false, false)
        InLaststand = false
        LaststandTime = 0
        SendNUIMessage({
            action = 'setCritical',
            critical = false
        })

        SetNuiFocus(false, false)
        SendNUIMessage({
            action = 'hide'
        })
    end
    TriggerServerEvent('hospital:server:SetLaststandStatus', bool)
end

exports('SetLaststand', SetLaststand)

local function CheckEmsAndUpdateUI()
    QBCore.Functions.TriggerCallback('hospital:server:getEmsCount', function(amount)
        if amount < Config.MinimalDoctors then
            SendNUIMessage({
                action = 'setStatus',
                status = 'no_ems'
            })
        end
    end)
end



AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    Wait(2000)
    local Player = QBCore.Functions.GetPlayerData()
    if Player then
        InLaststand = Player.metadata.inlaststand
        LaststandTime = Player.metadata.laststandtime or 0

        if InLaststand and LaststandTime <= 0 then
            isInCriticalState = true
            LaststandTime = 0
            TriggerServerEvent('hospital:server:SetCriticalState', true)
        else
            isInCriticalState = Player.metadata.isincritical or false
        end

        if InLaststand or isInCriticalState then
            local uiData = {
                action = 'initState',
                show = true,
                critical = isInCriticalState,
                time = isInCriticalState and 0 or LaststandTime,
                emsCooldown = Config.DocCooldown * 60,
                billCost = Config.BillCost
            }
            
            SendNUIMessage(uiData)
            SetNuiFocus(true, false)

            if not isInCriticalState then
                StartLaststandTimer()
            end

            QBCore.Functions.TriggerCallback('hospital:server:getEmsCount', function(amount)
                if amount < Config.MinimalDoctors then
                    SendNUIMessage({
                        action = 'setStatus',
                        status = 'no_ems'
                    })
                end
            end)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local Player = QBCore.Functions.GetPlayerData()
    if Player then
        InLaststand = Player.metadata.inlaststand or false
        LaststandTime = Player.metadata.laststandtime or Config.LaststandTime

        if InLaststand and LaststandTime <= 0 then
            isInCriticalState = true
            LaststandTime = 0
            TriggerServerEvent('hospital:server:SetCriticalState', true)
        else
            isInCriticalState = Player.metadata.isincritical or false
        end

        
        if InLaststand or isInCriticalState then
            if isInCriticalState then
                SendNUIMessage({
                    action = 'setCritical',
                    critical = true,
                    emsCooldown = Config.DocCooldown * 60
                })
            end

            SendNUIMessage({
                action = 'show'
            })
            SetNuiFocus(true, false)

            if isInCriticalState then
                SendNUIMessage({
                    action = 'updateTimer',
                    time = 0
                })
            else
                StartLaststandTimer()
                SendNUIMessage({
                    action = 'updateTimer',
                    time = LaststandTime
                })
            end
            Wait(500)
            CheckEmsAndUpdateUI()
            StartLaststandTimer()
        end
    end
end)

RegisterNetEvent('hospital:client:SetEscortingState', function(bool)
    isEscorting = bool
end)

RegisterNetEvent('hospital:client:isEscorted', function(bool)
    isEscorted = bool
end)

RegisterNUICallback('callEms', function()
    if not InLaststand then return end
    
    QBCore.Functions.TriggerCallback('hospital:server:getEmsCount', function(amount)
        if amount < Config.MinimalDoctors then
            SendNUIMessage({
                action = 'setStatus',
                status = 'no_ems'
            })
        else
            TriggerEvent('hospital:client:CallEms')
            SendNUIMessage({
                action = 'setStatus',
                status = 'ems_called'
            })
        end
    end)
end)

RegisterNUICallback('respawnPlayer', function()
    if not InLaststand then 
        return 
    end
    TriggerEvent('hospital:client:RespawnAtHospital')
    SendNUIMessage({
        action = 'hide'
    })
end)

RegisterNetEvent('hospital:client:UseFirstAid', function()
    if not isEscorting then
        local player, distance = GetClosestPlayer()
        if player ~= -1 and distance < 1.5 then
            local playerId = GetPlayerServerId(player)
            TriggerServerEvent('hospital:server:UseFirstAid', playerId)
        end
    else
        QBCore.Functions.Notify(Lang:t('error.impossible'), 'error')
    end
end)

RegisterNetEvent('hospital:client:CanHelp', function(helperId)
    if InLaststand then
        if LaststandTime <= 300 then
            TriggerServerEvent('hospital:server:CanHelp', helperId, true)
        else
            TriggerServerEvent('hospital:server:CanHelp', helperId, false)
        end
    else
        TriggerServerEvent('hospital:server:CanHelp', helperId, false)
    end
end)

RegisterNetEvent('hospital:client:HelpPerson', function(targetId)
    local ped = PlayerPedId()
    QBCore.Functions.Progressbar('hospital_revive', Lang:t('progress.revive'), math.random(30000, 60000), false, true, {
        disableMovement = false,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = healAnimDict,
        anim = healAnim,
        flags = 1,
    }, {}, {}, function()
        ClearPedTasks(ped)
        QBCore.Functions.Notify(Lang:t('success.revived'), 'success')
        TriggerServerEvent('hospital:server:RevivePlayer', targetId)
    end, function() 
        ClearPedTasks(ped)
        QBCore.Functions.Notify(Lang:t('error.canceled'), 'error')
    end)
end)
