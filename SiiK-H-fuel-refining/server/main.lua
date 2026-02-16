local QBCore = exports['qb-core']:GetCoreObject()

local function clamp(v, mn, mx)
  v = tonumber(v) or 0
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function RemoveItemFromPlayer(src, itemName, amount, slot)
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return false end

  amount = tonumber(amount) or 1
  if amount < 1 then amount = 1 end

  local item = slot and (Player.PlayerData.items and Player.PlayerData.items[slot]) or Player.Functions.GetItemByName(itemName)
  if not item or item.name ~= itemName or item.amount < amount then return false end

  Player.Functions.RemoveItem(itemName, amount, slot)
  TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'remove', amount)
  return true
end

local function AddItemToPlayer(src, itemName, amount, slot, info)
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return false end
  amount = tonumber(amount) or 1
  if amount < 1 then amount = 1 end

  Player.Functions.AddItem(itemName, amount, slot, info)
  TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add', amount)
  return true
end

-- =========================
-- SERVER-SIDE PLACEMENT ENFORCEMENT
-- =========================
local function vec3(x,y,z) return {x=x,y=y,z=z} end
local function dist3(a, b)
  local dx = (a.x - b.x)
  local dy = (a.y - b.y)
  local dz = (a.z - b.z)
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function inZone(pos, zone)
  if not zone or not zone.coords or not zone.radius then return false end
  local c = zone.coords
  return dist3(pos, vec3(c.x, c.y, c.z)) <= (tonumber(zone.radius) or 0.0)
end

local function canPlaceHereServer(pos)
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
-- DB CALLBACKS
-- =========================
QBCore.Functions.CreateCallback('SiiK-H-fuel-refining:server:GetDrums', function(_, cb)
  local rows = MySQL.query.await('SELECT id, owner, x, y, z, heading, level, max_level FROM siik_fuel_drums', {})
  cb(rows or {})
end)

QBCore.Functions.CreateCallback('SiiK-H-fuel-refining:server:GetRefineries', function(_, cb)
  local rows = MySQL.query.await('SELECT id, owner, x, y, z, heading FROM siik_refineries', {})
  cb(rows or {})
end)

QBCore.Functions.CreateCallback('SiiK-H-fuel-refining:server:GetPumpjacks', function(_, cb)
  local rows = MySQL.query.await('SELECT id, owner, x, y, z, heading FROM siik_pumpjacks', {})
  cb(rows or {})
end)

-- =========================
-- USEABLE KITS
-- =========================
QBCore.Functions.CreateUseableItem(Config.DrumKitItem, function(src)
  TriggerClientEvent('SiiK-H-fuel-refining:client:StartPlaceDrumSQL', src)
end)

QBCore.Functions.CreateUseableItem(Config.RefineryKitItem, function(src)
  TriggerClientEvent('SiiK-H-fuel-refining:client:StartPlaceRefinerySQL', src)
end)

QBCore.Functions.CreateUseableItem(Config.PumpjackKitItem, function(src)
  TriggerClientEvent('SiiK-H-fuel-refining:client:StartPlacePumpjackSQL', src)
end)

-- ✅ Pass item to client (slot/info may still be missing on some setups, client has fallback)
QBCore.Functions.CreateUseableItem(Config.FuelJerrycan, function(src, item)
  TriggerClientEvent('SiiK-H-fuel-refining:client:UseFuelJerrycan', src, item)
end)

-- =========================
-- CREATE: DRUM
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:CreateDrum', function(x,y,z,heading)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end

  x=tonumber(x); y=tonumber(y); z=tonumber(z); heading=tonumber(heading) or 0.0
  if not x or not y or not z then return end

  local ok, reason = canPlaceHereServer({x=x,y=y,z=z})
  if not ok then return TriggerClientEvent('QBCore:Notify', src, reason, 'error') end

  local kit = Player.Functions.GetItemByName(Config.DrumKitItem)
  if not kit or kit.amount < 1 then return TriggerClientEvent('QBCore:Notify', src, 'Missing oil drum kit.', 'error') end

  local owner = Player.PlayerData.citizenid

  local id = MySQL.insert.await([[
    INSERT INTO siik_fuel_drums (owner, x, y, z, heading, level, max_level)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], { owner, x, y, z, heading, Config.Drum.DefaultStart, Config.Drum.DefaultMax })

  if not id then return end

  RemoveItemFromPlayer(src, Config.DrumKitItem, 1)

  TriggerClientEvent('SiiK-H-fuel-refining:client:AddOrUpdateDrum', -1, {
    id=id, owner=owner, x=x,y=y,z=z, heading=heading, level=Config.Drum.DefaultStart, max_level=Config.Drum.DefaultMax
  })
end)

RegisterNetEvent('SiiK-H-fuel-refining:server:PickupDrum', function(drumId)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end
  drumId = tonumber(drumId); if not drumId then return end

  local cid = Player.PlayerData.citizenid
  local row = MySQL.single.await('SELECT owner FROM siik_fuel_drums WHERE id = ?', { drumId })
  if not row then return TriggerClientEvent('QBCore:Notify', src, 'Drum not found.', 'error') end
  if tostring(row.owner) ~= tostring(cid) then return TriggerClientEvent('QBCore:Notify', src, 'You do not own this drum.', 'error') end

  MySQL.update.await('DELETE FROM siik_fuel_drums WHERE id = ?', { drumId })

  AddItemToPlayer(src, Config.DrumKitItem, 1)
  TriggerClientEvent('SiiK-H-fuel-refining:client:RemoveDrum', -1, drumId)
  TriggerClientEvent('QBCore:Notify', src, 'Drum picked up (kit recovered).', 'success')
end)

RegisterNetEvent('SiiK-H-fuel-refining:server:DrumAddFuel', function(drumId)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end
  drumId = tonumber(drumId); if not drumId then return end

  local refined = Player.Functions.GetItemByName(Config.RefinedFuelItem)
  if not refined or refined.amount < 1 then return TriggerClientEvent('QBCore:Notify', src, 'You need refined fuel.', 'error') end

  local row = MySQL.single.await('SELECT level, max_level FROM siik_fuel_drums WHERE id = ?', { drumId })
  if not row then return TriggerClientEvent('QBCore:Notify', src, 'Drum not found.', 'error') end

  local level = tonumber(row.level) or 0.0
  local maxLevel = tonumber(row.max_level) or Config.Drum.DefaultMax
  if level >= maxLevel - 0.01 then return TriggerClientEvent('QBCore:Notify', src, 'Drum is full.', 'error') end

  RemoveItemFromPlayer(src, Config.RefinedFuelItem, 1)

  local newLevel = clamp(level + Config.Drum.AddPerRefinedFuel, 0.0, maxLevel)
  MySQL.update.await('UPDATE siik_fuel_drums SET level = ? WHERE id = ?', { newLevel, drumId })

  TriggerClientEvent('SiiK-H-fuel-refining:client:UpdateDrumLevel', -1, drumId, newLevel, maxLevel)
  TriggerClientEvent('QBCore:Notify', src, ('Poured fuel (%.0f/%.0f).'):format(newLevel, maxLevel), 'success')
end)

-- ✅ Drum -> charged jerrycan with metadata (Option B)
RegisterNetEvent('SiiK-H-fuel-refining:server:DrumFillJerrycan', function(drumId)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end
  drumId = tonumber(drumId); if not drumId then return end

  local empty = Player.Functions.GetItemByName(Config.EmptyJerrycan)
  if not empty or empty.amount < 1 then
    TriggerClientEvent('QBCore:Notify', src, 'Need an empty jerrycan.', 'error')
    return
  end

  local row = MySQL.single.await('SELECT level, max_level FROM siik_fuel_drums WHERE id = ?', { drumId })
  if not row then
    TriggerClientEvent('QBCore:Notify', src, 'Drum not found.', 'error')
    return
  end

  local level = tonumber(row.level) or 0.0
  local maxLevel = tonumber(row.max_level) or Config.Drum.DefaultMax
  if level < Config.Drum.DrainPerJerrycan then
    TriggerClientEvent('QBCore:Notify', src, 'Not enough fuel in drum.', 'error')
    return
  end

  local canMax = tonumber(Config.VehicleFuel.JerrycanMax) or 25.0
  local info = { fuel = canMax, maxFuel = canMax }

  local slot = empty.slot
  RemoveItemFromPlayer(src, Config.EmptyJerrycan, 1, slot)
  AddItemToPlayer(src, Config.FuelJerrycan, 1, slot, info)

  local newLevel = clamp(level - Config.Drum.DrainPerJerrycan, 0.0, maxLevel)
  MySQL.update.await('UPDATE siik_fuel_drums SET level = ? WHERE id = ?', { newLevel, drumId })

  TriggerClientEvent('SiiK-H-fuel-refining:client:UpdateDrumLevel', -1, drumId, newLevel, maxLevel)
  TriggerClientEvent('QBCore:Notify', src, ('Jerrycan filled (%.0f/%.0f).'):format(newLevel, maxLevel), 'success')
end)

-- =========================
-- CREATE: REFINERY
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:CreateRefinery', function(x,y,z,heading)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end

  x=tonumber(x); y=tonumber(y); z=tonumber(z); heading=tonumber(heading) or 0.0
  if not x or not y or not z then return end

  local ok, reason = canPlaceHereServer({x=x,y=y,z=z})
  if not ok then return TriggerClientEvent('QBCore:Notify', src, reason, 'error') end

  local kit = Player.Functions.GetItemByName(Config.RefineryKitItem)
  if not kit or kit.amount < 1 then return TriggerClientEvent('QBCore:Notify', src, 'Missing refinery kit.', 'error') end

  local owner = Player.PlayerData.citizenid
  local id = MySQL.insert.await([[
    INSERT INTO siik_refineries (owner, x, y, z, heading)
    VALUES (?, ?, ?, ?, ?)
  ]], { owner, x, y, z, heading })
  if not id then return end

  RemoveItemFromPlayer(src, Config.RefineryKitItem, 1)

  TriggerClientEvent('SiiK-H-fuel-refining:client:AddOrUpdateRefinery', -1, {
    id=id, owner=owner, x=x,y=y,z=z, heading=heading
  })
end)

RegisterNetEvent('SiiK-H-fuel-refining:server:PickupRefinery', function(refId)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end
  refId = tonumber(refId); if not refId then return end

  local cid = Player.PlayerData.citizenid
  local row = MySQL.single.await('SELECT owner FROM siik_refineries WHERE id = ?', { refId })
  if not row then return TriggerClientEvent('QBCore:Notify', src, 'Refinery not found.', 'error') end
  if tostring(row.owner) ~= tostring(cid) then return TriggerClientEvent('QBCore:Notify', src, 'You do not own this refinery.', 'error') end

  MySQL.update.await('DELETE FROM siik_refineries WHERE id = ?', { refId })

  AddItemToPlayer(src, Config.RefineryKitItem, 1)
  TriggerClientEvent('SiiK-H-fuel-refining:client:RemoveRefinery', -1, refId)
  TriggerClientEvent('QBCore:Notify', src, 'Refinery picked up (kit recovered).', 'success')
end)

-- =========================
-- CREATE: PUMPJACK
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:CreatePumpjack', function(x,y,z,heading)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end

  x=tonumber(x); y=tonumber(y); z=tonumber(z); heading=tonumber(heading) or 0.0
  if not x or not y or not z then return end

  local ok, reason = canPlaceHereServer({x=x,y=y,z=z})
  if not ok then return TriggerClientEvent('QBCore:Notify', src, reason, 'error') end

  local kit = Player.Functions.GetItemByName(Config.PumpjackKitItem)
  if not kit or kit.amount < 1 then return TriggerClientEvent('QBCore:Notify', src, 'Missing pumpjack kit.', 'error') end

  local owner = Player.PlayerData.citizenid
  local id = MySQL.insert.await([[
    INSERT INTO siik_pumpjacks (owner, x, y, z, heading)
    VALUES (?, ?, ?, ?, ?)
  ]], { owner, x, y, z, heading })
  if not id then return end

  RemoveItemFromPlayer(src, Config.PumpjackKitItem, 1)

  TriggerClientEvent('SiiK-H-fuel-refining:client:AddOrUpdatePumpjack', -1, {
    id=id, owner=owner, x=x,y=y,z=z, heading=heading
  })
end)

RegisterNetEvent('SiiK-H-fuel-refining:server:PickupPumpjack', function(pumpId)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end
  pumpId = tonumber(pumpId); if not pumpId then return end

  local cid = Player.PlayerData.citizenid
  local row = MySQL.single.await('SELECT owner FROM siik_pumpjacks WHERE id = ?', { pumpId })
  if not row then return TriggerClientEvent('QBCore:Notify', src, 'Pumpjack not found.', 'error') end
  if tostring(row.owner) ~= tostring(cid) then return TriggerClientEvent('QBCore:Notify', src, 'You do not own this pumpjack.', 'error') end

  MySQL.update.await('DELETE FROM siik_pumpjacks WHERE id = ?', { pumpId })

  AddItemToPlayer(src, Config.PumpjackKitItem, 1)
  TriggerClientEvent('SiiK-H-fuel-refining:client:RemovePumpjack', -1, pumpId)
  TriggerClientEvent('QBCore:Notify', src, 'Pumpjack picked up (kit recovered).', 'success')
end)

-- =========================
-- Pump reward
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:GiveCrude', function()
  local src = source
  local item = Config.PumpjackReward.item or Config.CrudeItem
  local minA = tonumber(Config.PumpjackReward.min) or 1
  local maxA = tonumber(Config.PumpjackReward.max) or minA
  if maxA < minA then maxA = minA end
  AddItemToPlayer(src, item, math.random(minA, maxA))
end)

-- =========================
-- Refinery flow
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:TryRefine', function()
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end

  local needItem = Config.Refine.InputItem
  local needAmt  = tonumber(Config.Refine.InputAmount) or 1
  local outItem  = Config.Refine.OutputItem
  local outAmt   = tonumber(Config.Refine.OutputAmount) or 1

  local have = Player.Functions.GetItemByName(needItem)
  if not have or have.amount < needAmt then
    return TriggerClientEvent('QBCore:Notify', src, ('Need %dx %s'):format(needAmt, needItem), 'error')
  end

  RemoveItemFromPlayer(src, needItem, needAmt)
  TriggerClientEvent('SiiK-H-fuel-refining:client:DoRefineSkill', src, needItem, needAmt, outItem, outAmt)
end)

RegisterNetEvent('SiiK-H-fuel-refining:server:RefineResult', function(success, needItem, needAmt, outItem, outAmt)
  local src = source

  needItem = needItem or Config.Refine.InputItem
  outItem  = outItem  or Config.Refine.OutputItem
  needAmt  = tonumber(needAmt) or tonumber(Config.Refine.InputAmount) or 1
  outAmt   = tonumber(outAmt)  or tonumber(Config.Refine.OutputAmount) or 1

  if not success then
    AddItemToPlayer(src, needItem, needAmt)
    return TriggerClientEvent('QBCore:Notify', src, 'Refining failed (refunded).', 'error')
  end

  AddItemToPlayer(src, outItem, outAmt)
  TriggerClientEvent('QBCore:Notify', src, 'Refining complete.', 'success')
end)

-- =========================
-- OPTION B: charged jerrycan refuel
-- =========================
RegisterNetEvent('SiiK-H-fuel-refining:server:RefuelFromJerrycan', function(netId, missing, slot)
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if not Player then return end

  slot = tonumber(slot)
  missing = tonumber(missing) or 0.0

  if not slot then
    TriggerClientEvent('QBCore:Notify', src, 'Jerrycan slot missing.', 'error')
    return
  end
  if missing <= 0.01 then
    TriggerClientEvent('QBCore:Notify', src, 'Tank already full.', 'error')
    return
  end

  local item = Player.PlayerData.items and Player.PlayerData.items[slot] or nil
  if not item or item.name ~= Config.FuelJerrycan then
    TriggerClientEvent('QBCore:Notify', src, 'No fuel jerrycan in that slot.', 'error')
    return
  end

  local info = item.info or {}
  local canMax  = tonumber(info.maxFuel) or (tonumber(Config.VehicleFuel.JerrycanMax) or 25.0)
  local canFuel = tonumber(info.fuel) or canMax

  if canFuel <= 0.01 then
    TriggerClientEvent('QBCore:Notify', src, 'Jerrycan is empty.', 'error')
    return
  end

  local pourCap = tonumber(Config.VehicleFuel.RefuelAmount) or canMax
  local pour = math.min(missing, canFuel, pourCap)
  if pour <= 0.01 then
    TriggerClientEvent('QBCore:Notify', src, 'Nothing to pour.', 'error')
    return
  end

  local newFuel = canFuel - pour

  if newFuel <= 0.01 then
    Player.Functions.RemoveItem(Config.FuelJerrycan, 1, slot)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.FuelJerrycan], 'remove', 1)

    Player.Functions.AddItem(Config.EmptyJerrycan, 1, slot)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.EmptyJerrycan], 'add', 1)
  else
    Player.Functions.RemoveItem(Config.FuelJerrycan, 1, slot)

    info.fuel = newFuel
    info.maxFuel = canMax

    Player.Functions.AddItem(Config.FuelJerrycan, 1, slot, info)
  end

  TriggerClientEvent('SiiK-H-fuel-refining:client:ApplyRefuel', src, netId, pour)
end)
