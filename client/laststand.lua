Laststand = Laststand or {
    isResourceStarting = false
}
InLaststand = false
LaststandTime = 0

lastStandDict = 'combat@damage@writhe'
lastStandAnim = 'writhe_loop'

isEscorted = false
local isEscorting = false
local isInCriticalState = false
local activeTimerId = nil

local function loadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(5)
    end
end

local function PlayDeathAnimation()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    
    if not isInCriticalState then
        loadAnimDict(lastStandDict)
        TaskPlayAnim(ped, lastStandDict, lastStandAnim, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local function ResetLaststandState()
    if activeTimerId then
        activeTimerId = nil
    end
    InLaststand = false
    LaststandTime = 0
    isInCriticalState = false
    SendNUIMessage({
        action = 'hide'
    })
    SendNUIMessage({
        action = 'resetUI'
    })
end

local function SyncPlayerState()
    if InLaststand then
        if LaststandTime <= 0 and not isInCriticalState then
            isInCriticalState = true
            TriggerServerEvent('hospital:server:SetCriticalState', true)
            SendNUIMessage({
                action = 'setCritical',
                critical = true,
                emsCooldown = Config.DocCooldown * 60
            })
            QBCore.Functions.Notify('You are now in critical condition', 'error')
            
            local ped = PlayerPedId()
            SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)
            Wait(1000)
            
            loadAnimDict('dead')
            TaskPlayAnim(ped, 'dead', 'dead_a', 1.0, 1.0, -1, 2, 0, false, false, false)
            


        end
    end
end

local function StartLaststandTimer()
    if activeTimerId then
        return
    end
    

    activeTimerId = GetGameTimer()
    
    CreateThread(function()
        local myTimerId = activeTimerId
        
        -- Initial UI update
        SendNUIMessage({
            action = 'updateTimer',
            time = LaststandTime
        })
        
        while InLaststand do
            Wait(1000)
            if myTimerId ~= activeTimerId then
                return
            end
            
            if not isInCriticalState and LaststandTime > 0 then
                LaststandTime = LaststandTime - 1
                
                TriggerServerEvent('hospital:server:SetLaststandTime', LaststandTime)
                SendNUIMessage({
                    action = 'updateTimer',
                    time = LaststandTime
                })
                if LaststandTime <= 0 then
                    if not isInCriticalState then
                        SyncPlayerState()
                    end
                end
            else
                break
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
    if Laststand.isResourceStarting then
        return
    end
    
    if bool then
        PlayDeathAnimation() -- Start with injured animation
    end
    
    local ped = PlayerPedId()
    
    if bool then
        local Player = QBCore.Functions.GetPlayerData()
        
        InLaststand = true
        isInCriticalState = false
        
        if Player.metadata and Player.metadata.laststandTime and Player.metadata.laststandTime > 0 then
            LaststandTime = Player.metadata.laststandTime
        else
            LaststandTime = Config.DeathTime
        end
        
        TriggerServerEvent('hospital:server:SetLaststandStatus', true)
        TriggerServerEvent('hospital:server:SetLaststandTime', LaststandTime)
        
        Wait(2000)
        
        SendNUIMessage({
            action = 'initState',
            show = true,
            critical = false,
            time = LaststandTime,
            emsCooldown = Config.DocCooldown * 60,
            billCost = Config.BillCost
        })
        
        SetNuiFocus(true, false)
        StartLaststandTimer()
    else
        ResetLaststandState()
        
        TriggerServerEvent('hospital:server:SetLaststandStatus', false)
        TriggerServerEvent('hospital:server:SetLaststandTime', 0)
        
        SetNuiFocus(false, false)
    
    end
    
    if bool then
        Wait(1000)
        while GetEntitySpeed(ped) > 0.5 or IsPedRagdoll(ped) do Wait(10) end
        local pos = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        
        QBCore.Functions.TriggerCallback('hospital:server:getEmsCount', function(amount)
            if amount < Config.MinimalDoctors then
                SendNUIMessage({
                    action = 'setStatus',
                    status = 'no_ems'
                })
            end
        end)
        
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
        
        TriggerServerEvent('hospital:server:ambulanceAlert', Lang:t('info.civ_down'))
    else
        TaskPlayAnim(ped, lastStandDict, 'exit', 1.0, 8.0, -1, 1, -1, false, false, false)
        
        -- First disable critical state
        SendNUIMessage({
            action = 'setCritical',
            critical = false
        })

        -- Then hide UI and release NUI focus
        SendNUIMessage({
            action = 'hide'
        })
        SetNuiFocus(false, false)
        InLaststand = false
    end
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
    
    Laststand.isResourceStarting = true
    
    local Player = QBCore.Functions.GetPlayerData()
    if not Player or not Player.metadata then 
        Laststand.isResourceStarting = false
        return 
    end
    
    SendNUIMessage({
        action = 'hide'
    })
    
    Wait(500)
    
    InLaststand = Player.metadata.inlaststand or false
    LaststandTime = Player.metadata.laststandTime or 0
    isInCriticalState = Player.metadata.isincritical or false
    
    SendNUIMessage({
        action = 'initState',
        show = InLaststand,
        critical = isInCriticalState,
        time = LaststandTime,
        emsCooldown = Config.DocCooldown * 60,
        billCost = Config.BillCost
    })
    
    if InLaststand then
        SetNuiFocus(true, false)
        
        if not isInCriticalState and LaststandTime > 0 then
            StartLaststandTimer()
        end
        
        CheckEmsAndUpdateUI()
    end
    
    Laststand.isResourceStarting = false
end)

local isPlayerLoaded = false

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if isPlayerLoaded then return end
    isPlayerLoaded = true
    
    Wait(2000)
    local Player = QBCore.Functions.GetPlayerData()
    if not Player or not Player.metadata then return end
    
    InLaststand = Player.metadata.inlaststand
    LaststandTime = Player.metadata.laststandTime
    isInCriticalState = Player.metadata.isincritical
    
    SendNUIMessage({
        action = 'initState',
        show = InLaststand,
        critical = isInCriticalState,
        time = LaststandTime,
        emsCooldown = Config.DocCooldown * 60,
        billCost = Config.BillCost
    })
    
    if InLaststand then
        SetNuiFocus(true, false)
        PlayDeathAnimation()
        
        if not isInCriticalState and LaststandTime > 0 then
            StartLaststandTimer()
        end
        
        CheckEmsAndUpdateUI()
        
        if Player.metadata.injail > 0 then
            TriggerEvent('prison:client:Enter', Player.metadata.injail)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isPlayerLoaded = false
    if activeTimerId then
        activeTimerId = nil
    end
    -- Reset local variables
    InLaststand = false
    LaststandTime = 0
    isInCriticalState = false
end)

RegisterNetEvent('hospital:client:SetLaststandStatus', function(bool)
    if Laststand.isResourceStarting then
        return
    end

    if not bool and activeTimerId then
        activeTimerId = nil
    end
    InLaststand = bool
    
    if bool then
        PlayDeathAnimation()
    else
        local ped = PlayerPedId()
        ClearPedTasks(ped)
    end
end)



RegisterNetEvent('hospital:client:SyncLaststandTime', function(time)
    LaststandTime = time
    if InLaststand then
        if time <= 0 and not isInCriticalState then
            isInCriticalState = true
            PlayDeathAnimation()
        elseif not isInCriticalState and time > 0 then
            StartLaststandTimer()
            PlayDeathAnimation()
        end
    end
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
