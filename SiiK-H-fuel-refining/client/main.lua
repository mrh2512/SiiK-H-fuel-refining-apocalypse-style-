local QBCore = exports['qb-core']:GetCoreObject()
local context = nil

-- =========================
-- NUI hard-close on load/restart
-- =========================
CreateThread(function()
  Wait(500)
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end)

AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Wait(250)
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  context = nil
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
  Wait(500)
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  context = nil
end)

CreateThread(function()
  while true do
    Wait(0)
    if IsControlJustPressed(0, 322) then -- ESC
      SetNuiFocus(false, false)
      SendNUIMessage({ action = 'close' })
      context = nil
    end
  end
end)

-- qb-hud compat decor
CreateThread(function()
  if not DecorIsRegisteredAsType('_FUEL_LEVEL', 1) then
    DecorRegister('_FUEL_LEVEL', 1)
  end
end)

-- =========================
-- Placement zone checks (client)
-- =========================
local function inZone(pos, zone)
  local c = zone.coords
  local center = vector3(c.x, c.y, c.z)
  return #(pos - center) <= (zone.radius or 0.0)
end

local function canPlaceHere(pos)
  if not Config.Placement or not Config.Placement.Enabled then return true, nil end

  for _, z in ipairs(Config.Placement.BlockedZones or {}) do
    if inZone(pos, z) then
      return false, ("You can't place here (%s zone)."):format(z.name or "Blocked")
    end
  end
  for _, z in ipairs(Config.Placement.NoPlacePoints or {}) do
    if inZone(pos, z) then
      return false, ("You can't place here (%s zone)."):format(z.name or "Blocked")
    end
  end

  if Config.Placement.RequireAllowedZone then
    for _, z in ipairs(Config.Placement.AllowedZones or {}) do
      if inZone(pos, z) then return true, nil end
    end
    return false, "You must place this inside an allowed industrial/oil zone."
  end

  return true, nil
end

-- =========================
-- NUI helpers
-- =========================
local function OpenUI(data)
  SetNuiFocus(true, true)
  SendNUIMessage({ action='open', payload=data })
end

local function CloseUI()
  SetNuiFocus(false, false)
  SendNUIMessage({ action='close' })
  context = nil
end

RegisterNUICallback('close', function(_, cb) CloseUI(); cb(true) end)

-- =========================
-- Easy qb-minigames wrapper
-- =========================
local function DoSkillbar(rounds, _, _, cb)
  if not exports['qb-minigames'] or not exports['qb-minigames'].Skillbar then
    cb(true); return
  end

  CreateThread(function()
    local keys = "e"
    local difficulty = "easy"

    for i = 1, rounds do
      local success = exports['qb-minigames']:Skillbar(difficulty, keys)
      if not success then cb(false); return end
      Wait(100)
    end

    cb(true)
  end)
end

-- =========================
-- Shared model/anim helpers
-- =========================
local function loadModel(model)
  RequestModel(model)
  while not HasModelLoaded(model) do Wait(0) end
end

local function loadAnimDict(dict)
  RequestAnimDict(dict)
  while not HasAnimDictLoaded(dict) do Wait(0) end
end

-- =========================
-- Jerrycan prop + animation (refuel)
-- =========================
local activeCanObj = nil
local activeAnimDict = nil
local activeAnimName = nil

local function startRefuelAnimWithCan(durationMs)
  local ped = PlayerPedId()

  local model = `w_am_jerrycan`
  local dict = "timetable@gardener@filling_can"
  local anim = "gar_ig_5_filling_can"

  loadModel(model)
  loadAnimDict(dict)

  activeAnimDict = dict
  activeAnimName = anim

  if DoesEntityExist(activeCanObj) then
    DeleteEntity(activeCanObj)
    activeCanObj = nil
  end

  local canObj = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
  activeCanObj = canObj

  AttachEntityToEntity(
    canObj,
    ped,
    GetPedBoneIndex(ped, 28422),
    0.12, 0.02, -0.02,
    20.0, 160.0, 10.0,
    true, true, false, true, 1, true
  )

  TaskPlayAnim(ped, dict, anim, 2.0, 2.0, -1, 49, 0.0, false, false, false)

  CreateThread(function()
    local endTime = GetGameTimer() + (durationMs or 4500)
    while GetGameTimer() < endTime do
      Wait(200)
      if activeAnimDict and activeAnimName and not IsEntityPlayingAnim(ped, activeAnimDict, activeAnimName, 3) then
        TaskPlayAnim(ped, activeAnimDict, activeAnimName, 2.0, 2.0, -1, 49, 0.0, false, false, false)
      end
    end
  end)
end

local function stopRefuelAnimAndProp()
  local ped = PlayerPedId()

  if activeAnimDict and activeAnimName then
    StopAnimTask(ped, activeAnimDict, activeAnimName, 1.0)
    RemoveAnimDict(activeAnimDict)
  end
  activeAnimDict = nil
  activeAnimName = nil

  ClearPedSecondaryTask(ped)

  if DoesEntityExist(activeCanObj) then
    DeleteEntity(activeCanObj)
  end
  activeCanObj = nil
end

-- =========================
-- Placement shared helpers
-- =========================
local function rotationToDirection(rot)
  local z = math.rad(rot.z)
  local x = math.rad(rot.x)
  local num = math.abs(math.cos(x))
  return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCam(dist)
  local camRot = GetGameplayCamRot(2)
  local camCoord = GetGameplayCamCoord()
  local direction = rotationToDirection(camRot)
  local dest = camCoord + direction * dist
  local ray = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, 1, PlayerPedId(), 0)
  local _, hit, endCoords = GetShapeTestResult(ray)
  return hit == 1, endCoords
end

local function getMyCitizenId()
  local pdata = QBCore.Functions.GetPlayerData()
  return pdata and pdata.citizenid or nil
end

-- ✅ SLOT FALLBACK (fixes "jerrycan slot missing")
local function FindJerrycanSlot()
  local pdata = QBCore.Functions.GetPlayerData()
  local items = pdata and pdata.items
  if not items then return nil end

  for slot, it in pairs(items) do
    if it and it.name == Config.FuelJerrycan then
      local info = it.info or {}
      local fuel = tonumber(info.fuel) or 0.0
      if fuel > 0.01 then
        return tonumber(slot)
      end
    end
  end

  for slot, it in pairs(items) do
    if it and it.name == Config.FuelJerrycan then
      return tonumber(slot)
    end
  end

  return nil
end

-- =========================
-- DB: DRUMS (levels)
-- =========================
local DrumEntities, DrumData = {}, {}

local function spawnOrUpdateDrum(d)
  local id = tonumber(d.id); if not id then return end
  DrumData[id] = {
    coords = vector3(tonumber(d.x), tonumber(d.y), tonumber(d.z)),
    heading = tonumber(d.heading) or 0.0,
    level = tonumber(d.level) or 0.0,
    max = tonumber(d.max_level) or Config.Drum.DefaultMax,
    owner = d.owner and tostring(d.owner) or nil
  }
  if DrumEntities[id] and DoesEntityExist(DrumEntities[id]) then return end

  loadModel(Config.DrumModel)
  local c = DrumData[id].coords
  local obj = CreateObject(Config.DrumModel, c.x, c.y, c.z - 1.0, false, false, false)
  SetEntityHeading(obj, DrumData[id].heading)
  PlaceObjectOnGroundProperly(obj)
  FreezeEntityPosition(obj, true)
  SetEntityAsMissionEntity(obj, true, true)
  DrumEntities[id] = obj
end

CreateThread(function()
  Wait(1500)
  QBCore.Functions.TriggerCallback('SiiK-H-fuel-refining:server:GetDrums', function(rows)
    for _, r in ipairs(rows or {}) do spawnOrUpdateDrum(r) end
  end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:AddOrUpdateDrum', function(d) spawnOrUpdateDrum(d) end)

RegisterNetEvent('SiiK-H-fuel-refining:client:RemoveDrum', function(drumId)
  drumId = tonumber(drumId); if not drumId then return end
  if DrumEntities[drumId] and DoesEntityExist(DrumEntities[drumId]) then DeleteEntity(DrumEntities[drumId]) end
  DrumEntities[drumId] = nil
  DrumData[drumId] = nil
end)

local function findDrumIdByEntity(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  local ecoords = GetEntityCoords(entity)
  local bestId, bestDist = nil, 999999.0
  for id, data in pairs(DrumData) do
    local dist = #(ecoords - data.coords)
    if dist < bestDist then bestDist = dist; bestId = id end
  end
  if bestId and bestDist <= Config.Drum.InteractFindRadius then return bestId end
  return nil
end

RegisterNetEvent('SiiK-H-fuel-refining:client:UpdateDrumLevel', function(drumId, level, maxLevel)
  drumId = tonumber(drumId); if not drumId then return end
  level = tonumber(level) or 0.0
  maxLevel = tonumber(maxLevel) or Config.Drum.DefaultMax

  if DrumData[drumId] then
    DrumData[drumId].level = level
    DrumData[drumId].max = maxLevel
  end

  if context and context.type == 'drum' and context.drumId == drumId then
    SendNUIMessage({ action='drumLiveUpdate', payload={ level=level, max=maxLevel } })
  end
end)

-- =========================
-- DB: REFINERIES
-- =========================
local RefineryEntities, RefineryData = {}, {}

local function spawnOrUpdateRefinery(r)
  local id = tonumber(r.id); if not id then return end
  RefineryData[id] = {
    coords = vector3(tonumber(r.x), tonumber(r.y), tonumber(r.z)),
    heading = tonumber(r.heading) or 0.0,
    owner = r.owner and tostring(r.owner) or nil
  }
  if RefineryEntities[id] and DoesEntityExist(RefineryEntities[id]) then return end

  loadModel(Config.RefineryModel)
  local c = RefineryData[id].coords
  local obj = CreateObject(Config.RefineryModel, c.x, c.y, c.z - 1.0, false, false, false)
  SetEntityHeading(obj, RefineryData[id].heading)
  PlaceObjectOnGroundProperly(obj)
  FreezeEntityPosition(obj, true)
  SetEntityAsMissionEntity(obj, true, true)
  RefineryEntities[id] = obj
end

CreateThread(function()
  Wait(1700)
  QBCore.Functions.TriggerCallback('SiiK-H-fuel-refining:server:GetRefineries', function(rows)
    for _, r in ipairs(rows or {}) do spawnOrUpdateRefinery(r) end
  end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:AddOrUpdateRefinery', function(r) spawnOrUpdateRefinery(r) end)

RegisterNetEvent('SiiK-H-fuel-refining:client:RemoveRefinery', function(refId)
  refId = tonumber(refId); if not refId then return end
  if RefineryEntities[refId] and DoesEntityExist(RefineryEntities[refId]) then DeleteEntity(RefineryEntities[refId]) end
  RefineryEntities[refId] = nil
  RefineryData[refId] = nil
end)

local function findRefineryIdByEntity(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  local ecoords = GetEntityCoords(entity)
  local bestId, bestDist = nil, 999999.0
  for id, data in pairs(RefineryData) do
    local dist = #(ecoords - data.coords)
    if dist < bestDist then bestDist = dist; bestId = id end
  end
  if bestId and bestDist <= Config.RefineryPlace.InteractFindRadius then return bestId end
  return nil
end

-- =========================
-- DB: PUMPJACKS
-- =========================
local PumpEntities, PumpData = {}, {}

local function spawnOrUpdatePumpjack(p)
  local id = tonumber(p.id); if not id then return end
  PumpData[id] = {
    coords = vector3(tonumber(p.x), tonumber(p.y), tonumber(p.z)),
    heading = tonumber(p.heading) or 0.0,
    owner = p.owner and tostring(p.owner) or nil
  }
  if PumpEntities[id] and DoesEntityExist(PumpEntities[id]) then return end

  loadModel(Config.PumpjackModel)
  local c = PumpData[id].coords
  local obj = CreateObject(Config.PumpjackModel, c.x, c.y, c.z - 1.0, false, false, false)
  SetEntityHeading(obj, PumpData[id].heading)
  PlaceObjectOnGroundProperly(obj)
  FreezeEntityPosition(obj, true)
  SetEntityAsMissionEntity(obj, true, true)
  PumpEntities[id] = obj
end

CreateThread(function()
  Wait(1600)
  QBCore.Functions.TriggerCallback('SiiK-H-fuel-refining:server:GetPumpjacks', function(rows)
    for _, p in ipairs(rows or {}) do spawnOrUpdatePumpjack(p) end
  end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:AddOrUpdatePumpjack', function(p) spawnOrUpdatePumpjack(p) end)

RegisterNetEvent('SiiK-H-fuel-refining:client:RemovePumpjack', function(pumpId)
  pumpId = tonumber(pumpId); if not pumpId then return end
  if PumpEntities[pumpId] and DoesEntityExist(PumpEntities[pumpId]) then DeleteEntity(PumpEntities[pumpId]) end
  PumpEntities[pumpId] = nil
  PumpData[pumpId] = nil
end)

local function findPumpIdByEntity(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  local ecoords = GetEntityCoords(entity)
  local bestId, bestDist = nil, 999999.0
  for id, data in pairs(PumpData) do
    local dist = #(ecoords - data.coords)
    if dist < bestDist then bestDist = dist; bestId = id end
  end
  if bestId and bestDist <= Config.PumpjackPlace.InteractFindRadius then return bestId end
  return nil
end

-- =========================
-- OPEN UIs
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:client:OpenPumpUI', function(entity)
  context = { type='pump', entity=entity }
  OpenUI({ ui='pump', title='PUMPJACK CONSOLE' })
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:OpenRefineryUI', function(entity)
  context = { type='refinery', entity=entity }
  OpenUI({
    ui='refinery',
    title='REFINERY CONSOLE',
    crudeRequired = Config.Refine.InputAmount,
    refinedOut = Config.Refine.OutputAmount
  })
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:OpenDrumUI', function(entity)
  local drumId = findDrumIdByEntity(entity)
  if not drumId then return QBCore.Functions.Notify('This drum is not registered.', 'error') end

  context = { type='drum', entity=entity, drumId=drumId }
  local d = DrumData[drumId]
  OpenUI({
    ui='drum', title='FUEL DRUM',
    level=d.level, max=d.max,
    drain=Config.Drum.DrainPerJerrycan, add=Config.Drum.AddPerRefinedFuel
  })
end)

-- =========================
-- NUI callbacks
-- =========================
RegisterNUICallback('pump', function(_, cb)
  if not context or context.type ~= 'pump' or not DoesEntityExist(context.entity) then cb(false) return end
  CloseUI()

  DoSkillbar(Config.SkillbarPump.rounds, 0, 0, function(ok)
    if ok then
      TriggerServerEvent('SiiK-H-fuel-refining:server:GiveCrude')
      QBCore.Functions.Notify('Crude oil extracted', 'success')
    else
      QBCore.Functions.Notify('Pumping failed', 'error')
    end
  end)

  cb(true)
end)

RegisterNUICallback('refine', function(_, cb)
  if not context or context.type ~= 'refinery' or not DoesEntityExist(context.entity) then cb(false) return end
  CloseUI()
  TriggerServerEvent('SiiK-H-fuel-refining:server:TryRefine')
  cb(true)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:DoRefineSkill', function(needItem, needAmt, outItem, outAmt)
  DoSkillbar(Config.SkillbarRefine.rounds, 0, 0, function(ok)
    TriggerServerEvent('SiiK-H-fuel-refining:server:RefineResult', ok, needItem, needAmt, outItem, outAmt)
  end)
end)

RegisterNUICallback('drum_pour', function(_, cb)
  if not context or context.type ~= 'drum' then cb(false) return end
  local id = context.drumId
  CloseUI()

  DoSkillbar(Config.SkillbarPour.rounds, 0, 0, function(ok)
    if ok then
      TriggerServerEvent('SiiK-H-fuel-refining:server:DrumAddFuel', id)
    else
      QBCore.Functions.Notify('Pouring failed', 'error')
    end
  end)

  cb(true)
end)

RegisterNUICallback('drum_fill', function(_, cb)
  if not context or context.type ~= 'drum' then cb(false) return end
  local id = context.drumId
  CloseUI()

  DoSkillbar(Config.SkillbarFill.rounds, 0, 0, function(ok)
    if ok then
      TriggerServerEvent('SiiK-H-fuel-refining:server:DrumFillJerrycan', id)
    else
      QBCore.Functions.Notify('Filling failed', 'error')
    end
  end)

  cb(true)
end)

-- =========================
-- OWNER PICKUP
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:client:TryPickupDrum', function(entity)
  local id = findDrumIdByEntity(entity)
  if not id then return QBCore.Functions.Notify('Not registered.', 'error') end
  local myCid = getMyCitizenId()
  local owner = DrumData[id] and DrumData[id].owner
  if not myCid or not owner or tostring(owner) ~= tostring(myCid) then
    return QBCore.Functions.Notify('You do not own this drum.', 'error')
  end
  QBCore.Functions.Progressbar('siik_pickup_drum', 'Picking up drum...', 3500, false, true, {
    disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true,
  }, {}, {}, {}, function()
    TriggerServerEvent('SiiK-H-fuel-refining:server:PickupDrum', id)
  end, function() QBCore.Functions.Notify('Cancelled', 'error') end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:TryPickupRefinery', function(entity)
  local id = findRefineryIdByEntity(entity)
  if not id then return QBCore.Functions.Notify('Not registered.', 'error') end
  local myCid = getMyCitizenId()
  local owner = RefineryData[id] and RefineryData[id].owner
  if not myCid or not owner or tostring(owner) ~= tostring(myCid) then
    return QBCore.Functions.Notify('You do not own this refinery.', 'error')
  end
  QBCore.Functions.Progressbar('siik_pickup_refinery', 'Picking up refinery...', 4500, false, true, {
    disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true,
  }, {}, {}, {}, function()
    TriggerServerEvent('SiiK-H-fuel-refining:server:PickupRefinery', id)
  end, function() QBCore.Functions.Notify('Cancelled', 'error') end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:TryPickupPumpjack', function(entity)
  local id = findPumpIdByEntity(entity)
  if not id then return QBCore.Functions.Notify('Not registered.', 'error') end
  local myCid = getMyCitizenId()
  local owner = PumpData[id] and PumpData[id].owner
  if not myCid or not owner or tostring(owner) ~= tostring(myCid) then
    return QBCore.Functions.Notify('You do not own this pumpjack.', 'error')
  end
  QBCore.Functions.Progressbar('siik_pickup_pumpjack', 'Picking up pumpjack...', 4500, false, true, {
    disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true,
  }, {}, {}, {}, function()
    TriggerServerEvent('SiiK-H-fuel-refining:server:PickupPumpjack', id)
  end, function() QBCore.Functions.Notify('Cancelled', 'error') end)
end)

-- =========================
-- PLACEMENT (SQL)
-- =========================
local placingDrum, placingRefinery, placingPumpjack = false, false, false

local function tooCloseToAny(listData, coords, distMin)
  for _, data in pairs(listData) do
    if data.coords and #(coords - data.coords) < distMin then return true end
  end
  return false
end

local function startPlacement(model, previewDist, rotateStep, tooCloseDist, dataTable, serverEvent)
  local ped = PlayerPedId()
  local heading = GetEntityHeading(ped)
  loadModel(model)

  local pcoords = GetEntityCoords(ped)
  local preview = CreateObject(model, pcoords.x, pcoords.y, pcoords.z, false, false, false)
  SetEntityAlpha(preview, 160, false)
  SetEntityCollision(preview, false, false)
  FreezeEntityPosition(preview, true)

  QBCore.Functions.Notify('[E] Place | [←/→] Rotate | [Backspace] Cancel', 'primary')

  local placing = true
  while placing do
    Wait(0)
    local hit, coords = raycastFromCam(previewDist)
    if hit then
      SetEntityCoords(preview, coords.x, coords.y, coords.z - 1.0, false, false, false, false)
      SetEntityHeading(preview, heading)
      PlaceObjectOnGroundProperly(preview)
    end

    if IsControlJustPressed(0, 174) then heading = heading - rotateStep end
    if IsControlJustPressed(0, 175) then heading = heading + rotateStep end
    if IsControlJustPressed(0, 177) then placing=false; QBCore.Functions.Notify('Cancelled', 'error') end

    if IsControlJustPressed(0, 38) then
      local finalCoords = GetEntityCoords(preview)

      local ok, reason = canPlaceHere(finalCoords)
      if not ok then QBCore.Functions.Notify(reason, 'error') goto afterConfirm end

      if tooCloseToAny(dataTable, finalCoords, tooCloseDist) then
        QBCore.Functions.Notify('Too close to another object.', 'error')
        goto afterConfirm
      end

      TriggerServerEvent(serverEvent, finalCoords.x, finalCoords.y, finalCoords.z, heading)
      QBCore.Functions.Notify('Placed (server validates).', 'success')
      placing = false

      ::afterConfirm::
    end
  end

  if DoesEntityExist(preview) then DeleteEntity(preview) end
end

RegisterNetEvent('SiiK-H-fuel-refining:client:StartPlaceDrumSQL', function()
  if placingDrum then return end
  placingDrum = true
  startPlacement(Config.DrumModel, Config.Drum.Place.PreviewDistance, Config.Drum.Place.RotateStep, Config.Drum.Place.TooCloseDist, DrumData,
    'SiiK-H-fuel-refining:server:CreateDrum')
  placingDrum = false
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:StartPlaceRefinerySQL', function()
  if placingRefinery then return end
  placingRefinery = true
  startPlacement(Config.RefineryModel, Config.RefineryPlace.PreviewDistance, Config.RefineryPlace.RotateStep, Config.RefineryPlace.TooCloseDist, RefineryData,
    'SiiK-H-fuel-refining:server:CreateRefinery')
  placingRefinery = false
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:StartPlacePumpjackSQL', function()
  if placingPumpjack then return end
  placingPumpjack = true
  startPlacement(Config.PumpjackModel, Config.PumpjackPlace.PreviewDistance, Config.PumpjackPlace.RotateStep, Config.PumpjackPlace.TooCloseDist, PumpData,
    'SiiK-H-fuel-refining:server:CreatePumpjack')
  placingPumpjack = false
end)

-- =========================
-- TARGET REGISTRATION
-- =========================
CreateThread(function()
  Wait(1000)

  if Config.Target == 'ox_target' then
    exports.ox_target:addModel(Config.PumpjackModel, {
      { label=Config.TargetPumpLabel, icon=Config.TargetPumpIcon, distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:OpenPumpUI', data.entity) end },
      { label='Pickup Pumpjack (Owner)', icon='fas fa-hand-rock', distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupPumpjack', data.entity) end },
    })

    exports.ox_target:addModel(Config.RefineryModel, {
      { label=Config.TargetRefineryLabel, icon=Config.TargetRefineryIcon, distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:OpenRefineryUI', data.entity) end },
      { label='Pickup Refinery (Owner)', icon='fas fa-hand-rock', distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupRefinery', data.entity) end },
    })

    exports.ox_target:addModel(Config.DrumModel, {
      { label=Config.TargetDrumLabel, icon=Config.TargetDrumIcon, distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:OpenDrumUI', data.entity) end },
      { label='Pickup Drum (Owner)', icon='fas fa-hand-rock', distance=Config.TargetDistance,
        onSelect=function(data) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupDrum', data.entity) end },
    })
  else
    exports['qb-target']:AddTargetModel({ Config.PumpjackModel }, {
      options = {
        { label=Config.TargetPumpLabel, icon=Config.TargetPumpIcon,
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:OpenPumpUI', entity) end },
        { label='Pickup Pumpjack (Owner)', icon='fas fa-hand-rock',
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupPumpjack', entity) end },
      },
      distance = Config.TargetDistance
    })

    exports['qb-target']:AddTargetModel({ Config.RefineryModel }, {
      options = {
        { label=Config.TargetRefineryLabel, icon=Config.TargetRefineryIcon,
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:OpenRefineryUI', entity) end },
        { label='Pickup Refinery (Owner)', icon='fas fa-hand-rock',
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupRefinery', entity) end },
      },
      distance = Config.TargetDistance
    })

    exports['qb-target']:AddTargetModel({ Config.DrumModel }, {
      options = {
        { label=Config.TargetDrumLabel, icon=Config.TargetDrumIcon,
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:OpenDrumUI', entity) end },
        { label='Pickup Drum (Owner)', icon='fas fa-hand-rock',
          action=function(entity) TriggerEvent('SiiK-H-fuel-refining:client:TryPickupDrum', entity) end },
      },
      distance = Config.TargetDistance
    })
  end
end)

-- =========================
-- VEHICLE FUEL (qb-hud)
-- =========================
local function clampFuel(v)
  if v < Config.VehicleFuel.Min then return Config.VehicleFuel.Min end
  if v > Config.VehicleFuel.Max then return Config.VehicleFuel.Max end
  return v
end

local function getFuel(veh)
  if veh == 0 or not DoesEntityExist(veh) then return 0.0 end
  if DecorExistOn(veh, '_FUEL_LEVEL') then return clampFuel(DecorGetFloat(veh, '_FUEL_LEVEL')) end
  return clampFuel(GetVehicleFuelLevel(veh))
end

local function setFuel(veh, fuel)
  if veh == 0 or not DoesEntityExist(veh) then return end
  fuel = clampFuel(fuel)
  SetVehicleFuelLevel(veh, fuel)
  DecorSetFloat(veh, '_FUEL_LEVEL', fuel)
  Entity(veh).state:set(Config.VehicleFuel.StateKey, fuel, true)
  TriggerEvent('hud:client:UpdateFuel', fuel)
end

local function getTargetVehicle()
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh ~= 0 then return veh end

  local pcoords = GetEntityCoords(ped)
  local forward = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.5, 0.0)
  local ray = StartShapeTestRay(pcoords.x, pcoords.y, pcoords.z, forward.x, forward.y, forward.z, 10, ped, 0)
  local _, hit, _, _, ent = GetShapeTestResult(ray)
  if hit == 1 and ent ~= 0 and IsEntityAVehicle(ent) then return ent end
  return 0
end

-- ✅ OPTION B + Prop/Anim + Slot fallback
RegisterNetEvent('SiiK-H-fuel-refining:client:UseFuelJerrycan', function(item)
  if not Config.VehicleFuel.Enabled then
    QBCore.Functions.Notify('Fuel system disabled.', 'error')
    return
  end

  local veh = getTargetVehicle()
  if veh == 0 then
    QBCore.Functions.Notify('No vehicle nearby.', 'error')
    return
  end

  local current = getFuel(veh)
  local maxFuel = Config.VehicleFuel.Max or 100.0
  local missing = maxFuel - current
  if missing <= 0.01 then
    QBCore.Functions.Notify('Tank already full.', 'error')
    return
  end

  local slot = (item and item.slot) or FindJerrycanSlot()
  if not slot then
    QBCore.Functions.Notify('Jerrycan slot missing (could not locate in inventory).', 'error')
    return
  end

  TaskTurnPedToFaceEntity(PlayerPedId(), veh, 800)
  Wait(150)

  local duration = 6500
  startRefuelAnimWithCan(duration)

  QBCore.Functions.Progressbar('siik_refuel', 'Pouring fuel...', duration, false, true, {
    disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true,
  }, {}, {}, {}, function()
    stopRefuelAnimAndProp()
    TriggerServerEvent('SiiK-H-fuel-refining:server:RefuelFromJerrycan', VehToNet(veh), missing, slot)
  end, function()
    stopRefuelAnimAndProp()
    QBCore.Functions.Notify('Cancelled.', 'error')
  end)
end)

RegisterNetEvent('SiiK-H-fuel-refining:client:ApplyRefuel', function(netId, amount)
  local veh = NetToVeh(netId)
  if veh == 0 or not DoesEntityExist(veh) then return end

  local add = tonumber(amount) or 0.0
  if add <= 0.01 then return end

  local current = getFuel(veh)
  local maxFuel = Config.VehicleFuel.Max or 100.0
  local missing = maxFuel - current
  if missing <= 0.01 then return end
  if add > missing then add = missing end

  setFuel(veh, current + add)
  QBCore.Functions.Notify(('Vehicle refueled (+%.0f).'):format(add), 'success')
end)

CreateThread(function()
  if not Config.VehicleFuel.Enabled then return end
  while true do
    Wait(Config.VehicleFuel.TickMs)

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then goto continue end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then goto continue end
    if GetPedInVehicleSeat(veh, -1) ~= ped then goto continue end

    local cls = GetVehicleClass(veh)
    local mult = Config.VehicleFuel.ClassMultiplier[cls] or 1.0
    if mult <= 0.0 then goto continue end

    local fuel = getFuel(veh)
    if fuel <= Config.VehicleFuel.Min then setFuel(veh, Config.VehicleFuel.Min); goto continue end

    local rpm = GetVehicleCurrentRpm(veh)
    local speed = GetEntitySpeed(veh)
    local drain = (Config.VehicleFuel.BaseDrain + (rpm * Config.VehicleFuel.RpmFactor) + (speed * Config.VehicleFuel.SpeedFactor)) * mult
    setFuel(veh, fuel - drain)

    ::continue::
  end
end)

-- =========================================================
-- HUD compatibility exports (ps-hud etc.)
-- =========================================================
exports('GetFuel', function(vehicle)
  if vehicle == nil then return 0.0 end
  local veh = vehicle
  if veh == 0 or not DoesEntityExist(veh) then return 0.0 end
  return getFuel(veh)
end)

exports('SetFuel', function(vehicle, fuel)
  if vehicle == nil then return end
  local veh = vehicle
  if veh == 0 or not DoesEntityExist(veh) then return end
  setFuel(veh, tonumber(fuel) or 0.0)
end)
