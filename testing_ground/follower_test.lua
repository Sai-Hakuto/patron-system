--[[============================================================================
 PatronFollowers_Manager.lua
 PatronSystem — серверный менеджер фолловеров (spawn/despawn + движение)

 Функционал:
  - Приём команд AIO от клиента: SpawnFollower, DespawnFollower, FollowOwner, GuardPoint
  - До 3 фолловеров на игрока одновременно
  - Отдельный FSM на каждого фолловера (FOLLOW_OWNER / GUARD_POINT)
  - Общий сенсор врагов на владельца (раз в 1 сек)
  - Анти-толкучка: разведённые углы/радиусы, рассинхрон тиков 600/750/900 мс

 Требует: Eluna + AIO (канал "PatronSystem")

 ВНИМАНИЕ: логика боя отключена. Только спавн и перемещения.
============================================================================]]--

local AIO = AIO or require("AIO")

local MOD = "[PatronFollowers]"
local CHANNEL = "PatronSystem"

-- Ограничения/настройки
local MAX_FOLLOWERS = 3
local DEFAULT_FOLLOW_DIST = 6.0         -- базовая дистанция следования
local DEFAULT_GUARD_RADIUS = 8.0         -- базовый радиус расстановки при охране точки
local OWNER_SENSOR_RADIUS = 25.0         -- радиус обзора владельца (для кэша окружения)
local OWNER_SENSOR_PERIOD = 1000         -- мс, один сенсор на игрока
local TICK_PERIODS = {600, 750, 900}     -- мс, рассинхрон тиков по индексам 1..3

-- Разводим по углам вокруг "за спиной" игрока (π) и чуть-чуть по радиусу
local FOLLOW_ANGLE_OFFSETS = { -0.45, 0.0, +0.45 }   -- радианы
local FOLLOW_RADIUS_OFFSETS = { 0.4, 0.0, 0.4 }      -- метры
-- При GUARD_POINT раскладываем по окружности равномерно
local function guardAngleFor(slot, total)
  return (2*math.pi) * ((slot-1) / total)
end

-- ---------------------------------------------------------------------------
-- ВНУТРЕННЕЕ СОСТОЯНИЕ
-- ---------------------------------------------------------------------------

-- Контексты владельцев: один на игрока
--  enemies   : { Unit, ... } — общий кэш врагов (опционально для будущих стратегий)
--  followers : [fGUID] = { creature, mode, tickId, slot, followDist, guard = {x,y,z,r}, createdAt }
--  sensorId  : eventId таймера сенсора (висит на Player)
local Owners = {}        -- [ownerGUID] = ctx

-- Быстрый поиск владельца/сост-я по фолловеру
local Followers = {}     -- [followerGUID] = { ownerGUID=..., ... } == ссылка на ctx.followers[fGUID]

-- Утилиты GUID/получение объектов безопасно
local function guid(obj) return obj and obj:GetGUID() end  -- Eluna Object:GetGUID
local function getPlayer(ownerGUID)
  -- ЭТО ВАЖНО: не держим "живые" ссылки долго — всегда достаём по GUID (рекомендация Eluna devs)
  return GetPlayerByGUID(ownerGUID)  -- Global:GetPlayerByGUID
end

-- math helpers
local function polarFrom(owner, dist, angle)
  local x,y,z,o = owner:GetLocation()
  local ax = o + angle
  return x + dist * math.cos(ax), y + dist * math.sin(ax), z
end

-- ---------------------------------------------------------------------------
-- ЛОГИРОВАНИЕ/ОТВЕТЫ В КЛИЕНТ (не обязательно, но удобно)
-- ---------------------------------------------------------------------------
local function sendClientLog(player, msg)
  -- Лёгкий лог назад в аддон (можно скрыть, если не нужен)
  pcall(function()
    AIO.Msg():Add(CHANNEL, "ServerLog", tostring(msg)):Send(player)
  end)
end

local function log(fmt, ...) print(MOD, string.format(fmt, ...)) end

-- ---------------------------------------------------------------------------
-- СЕНСОР ВЛАДЕЛЬЦА (общий, раз в секунду)
-- ---------------------------------------------------------------------------
local function ensureOwnerContext(player)
  local og = guid(player)
  local ctx = Owners[og]
  if ctx then return ctx end
  ctx = { ownerGUID = og, ownerMapId = player:GetMapId(), enemies = {}, followers = {}, sensorId = nil }
  Owners[og] = ctx

  -- Раз в OWNER_SENSOR_PERIOD обновляем кэш врагов для ВСЕХ его фолловеров
  ctx.sensorId = player:RegisterEvent(function(eventId, delay, calls, who)
    local p = getPlayer(og)
    if not p then return end
    -- Простой сенсор — ближайшие враждебные в радиусе (для будущих стратегий позиционирования)
    ctx.enemies = p:GetUnfriendlyUnitsInRange(OWNER_SENSOR_RADIUS) or {}
  end, OWNER_SENSOR_PERIOD, 0)

  return ctx
end

local function shutdownOwnerContext(player)
  local og = guid(player)
  local ctx = og and Owners[og]
  if not ctx then return end
  -- Снимем все тики с фолловеров (на случай живых существ)
  for fGUID, st in pairs(ctx.followers) do
    if st.creature then st.creature:RemoveEvents() end
  end
  -- Снимем сенсор
  local p = getPlayer(og)
  if p then p:RemoveEvents() end
  Owners[og] = nil
end

-- ---------------------------------------------------------------------------
-- FSM каждого фолловера (только движение)
-- ---------------------------------------------------------------------------
local MODE_FOLLOW = "FOLLOW_OWNER"
local MODE_GUARD  = "GUARD_POINT"

local function startFollowerTick(state)
  local c = state.creature
  if not c then return end
  -- Защитим от дублей
  c:RemoveEvents()

  local period = TICK_PERIODS[math.max(1, math.min(state.slot, #TICK_PERIODS))] or 700

  c:RegisterEvent(function(eventId, delay, calls, self)
    -- БЕЗОПАСНОСТЬ: владелец/существо могли исчезнуть
    local ctx = Owners[state.ownerGUID]
    if not ctx then self:RemoveEvents(); return end
    local owner = getPlayer(state.ownerGUID)
    if not owner or not self:IsInWorld() then self:RemoveEvents(); return end

    if state.mode == MODE_FOLLOW then
      local dist  = (state.followDist or DEFAULT_FOLLOW_DIST) + (FOLLOW_RADIUS_OFFSETS[state.slot] or 0)
      local angle = math.pi + (FOLLOW_ANGLE_OFFSETS[state.slot] or 0) -- держимся "сзади" с разносом
      self:MoveFollow(owner, dist, angle)  -- Unit:MoveFollow(target, dist, angle)
    elseif state.mode == MODE_GUARD and state.guard then
      -- Статическая охрана: равномерно раскладываем по окружности r, плюс минимальный дрифт
      local r = state.guard.r or DEFAULT_GUARD_RADIUS
      local baseAng = guardAngleFor(state.slot, math.max(1, state.guard.n or 1))
      local x = state.guard.x + r * math.cos(baseAng)
      local y = state.guard.y + r * math.sin(baseAng)
      local z = state.guard.z
      self:MoveTo(0, x, y, z)             -- Unit:MoveTo
    else
      -- fallback — не знаем режим: просто держимся позади
      self:MoveFollow(owner, DEFAULT_FOLLOW_DIST, math.pi)
    end
  end, period, 0)
end

local function stopFollowerTick(state)
  if state and state.creature then state.creature:RemoveEvents() end
end

-- ---------------------------------------------------------------------------
-- СПАВН/ДЕСПАВН
-- ---------------------------------------------------------------------------

-- Расчёт "слота" для анти-толкучки (1..3)
local function nextSlotFor(ctx)
  local used = { false, false, false }
  for _, st in pairs(ctx.followers) do
    if st.slot and st.slot >= 1 and st.slot <= 3 then used[st.slot] = true end
  end
  for i=1,MAX_FOLLOWERS do if not used[i] then return i end end
  return nil
end

local function spawnFollower(player, payload)
  local ctx = ensureOwnerContext(player)
  -- Лимит
  local count = 0; for _ in pairs(ctx.followers) do count = count + 1 end
  if count >= MAX_FOLLOWERS then
    sendClientLog(player, "Уже призвано максимальное число фолловеров ("..MAX_FOLLOWERS..")")
    return
  end

  local entry = assert(tonumber(payload.entry), "bad entry")
  local mode  = payload.mode or MODE_FOLLOW
  local followDist = tonumber(payload.followDist) or DEFAULT_FOLLOW_DIST

  local slot = nextSlotFor(ctx)
  if not slot then
    sendClientLog(player, "Не удалось подобрать слот для фолловера")
    return
  end

  -- Стартовая точка — чуть позади игрока с угловым оффсетом для слота
  local x0,y0,z0,o = player:GetLocation()
  local dist0  = followDist + (FOLLOW_RADIUS_OFFSETS[slot] or 0)
  local angle0 = math.pi + (FOLLOW_ANGLE_OFFSETS[slot] or 0)
  local sx, sy, sz = polarFrom(player, dist0, angle0)

  -- Спавним с ручным деспавном (MANUAL_DESPAWN)
  local creature = player:SpawnCreature(entry, sx, sy, sz, o, 8 /*MANUAL_DESPAWN*/, 0)  -- WorldObject:SpawnCreature
  if not creature then
    sendClientLog(player, "Не удалось заспавнить существо entry="..entry)
    return
  end

  -- Помечаем владельца и базовую реакцию (без самовольных атак)
  creature:SetOwnerGUID(guid(player))          -- Unit:SetOwnerGUID
  creature:SetReactState(0)                    -- REACT_PASSIVE

  -- Собираем состояние и запускаем тик
  local st = {
    ownerGUID  = guid(player),
    creature   = creature,
    mode       = mode == MODE_GUARD and MODE_GUARD or MODE_FOLLOW,
    followDist = followDist,
    slot       = slot,
    createdAt  = GetGameTime and GetGameTime() or os.time(),
  }

  -- GuardPoint можно прислать сразу в payload.guard = {x,y,z,r}
  if st.mode == MODE_GUARD and payload.guard and payload.guard.x then
    st.guard = { x = payload.guard.x, y = payload.guard.y, z = payload.guard.z, r = payload.guard.r or DEFAULT_GUARD_RADIUS, n = MAX_FOLLOWERS }
  end

  local fGUID = guid(creature)
  ctx.followers[fGUID] = st
  Followers[fGUID] = st

  startFollowerTick(st)

  sendClientLog(player, string.format("Spawn OK: entry=%d slot=%d mode=%s", entry, slot, st.mode))
end

local function despawnFollower(player, payload)
  local ctx = ensureOwnerContext(player)
  local fGUID = tonumber(payload.followerGUID)
  if not fGUID then
    sendClientLog(player, "Despawn: не передан followerGUID")
    return
  end
  local st = ctx.followers[fGUID]
  if not st or not st.creature then
    sendClientLog(player, "Despawn: фолловер не найден")
    return
  end
  stopFollowerTick(st)
  st.creature:DespawnOrUnsummon()   -- Creature:DespawnOrUnsummon
  ctx.followers[fGUID] = nil
  Followers[fGUID] = nil
  sendClientLog(player, "Despawn OK: "..tostring(fGUID))

  -- Если фолловеров больше не осталось — можно выключить сенсор
  local left = 0; for _ in pairs(ctx.followers) do left = left + 1 end
  if left == 0 then
    local p = getPlayer(st.ownerGUID)
    if p then p:RemoveEvents() end
    Owners[st.ownerGUID] = nil
  end
end

local function despawnAll(player)
  local ctx = Owners[guid(player)]
  if not ctx then return end
  for fGUID, st in pairs(ctx.followers) do
    if st.creature then
      stopFollowerTick(st)
      st.creature:DespawnOrUnsummon()
    end
    Followers[fGUID] = nil
    ctx.followers[fGUID] = nil
  end
  local p = getPlayer(ctx.ownerGUID)
  if p then p:RemoveEvents() end
  Owners[ctx.ownerGUID] = nil
  sendClientLog(player, "DespawnAll OK")
end

-- ---------------------------------------------------------------------------
-- ПЕРЕКЛЮЧЕНИЕ РЕЖИМОВ ДВИЖЕНИЯ
-- ---------------------------------------------------------------------------
local function setFollowOwner(player, payload)
  local ctx = ensureOwnerContext(player)
  local fGUID = tonumber(payload.followerGUID)
  local st = fGUID and ctx.followers[fGUID]
  if not st then sendClientLog(player, "FollowOwner: follower not found"); return end
  st.mode = MODE_FOLLOW
  st.followDist = tonumber(payload.followDist) or st.followDist or DEFAULT_FOLLOW_DIST
  startFollowerTick(st)
  sendClientLog(player, string.format("Follower %d -> FOLLOW_OWNER (dist=%.1f)", fGUID, st.followDist or 0))
end

local function setGuardPoint(player, payload)
  local ctx = ensureOwnerContext(player)
  local fGUID = tonumber(payload.followerGUID)
  local st = fGUID and ctx.followers[fGUID]
  if not st then sendClientLog(player, "GuardPoint: follower not found"); return end
  local gx = tonumber(payload.x); local gy = tonumber(payload.y); local gz = tonumber(payload.z)
  if not (gx and gy and gz) then sendClientLog(player, "GuardPoint: bad coords"); return end
  local r = tonumber(payload.r) or DEFAULT_GUARD_RADIUS
  st.mode = MODE_GUARD
  st.guard = { x=gx, y=gy, z=gz, r=r, n=MAX_FOLLOWERS }
  startFollowerTick(st)
  sendClientLog(player, string.format("Follower %d -> GUARD_POINT (r=%.1f)", fGUID, r))
end

-- ---------------------------------------------------------------------------
-- AIO HANDLERS (канал PatronSystem)
-- Payload — один аргумент-таблица (рекомендованный паттерн)
-- ---------------------------------------------------------------------------
local Handlers = AIO.AddHandlers(CHANNEL, {
  Followers_Spawn = function(player, payload)     -- { entry, mode?, followDist?, guard?={x,y,z,r}? }
    local ok, err = pcall(spawnFollower, player, payload or {})
    if not ok then sendClientLog(player, "Spawn ERROR: "..tostring(err)) end
  end,

  Followers_Despawn = function(player, payload)   -- { followerGUID } | { all=true }
    payload = payload or {}
    if payload.all then
      local ok, err = pcall(despawnAll, player)
      if not ok then sendClientLog(player, "DespawnAll ERROR: "..tostring(err)) end
    else
      local ok, err = pcall(despawnFollower, player, payload)
      if not ok then sendClientLog(player, "Despawn ERROR: "..tostring(err)) end
    end
  end,

  Followers_FollowOwner = function(player, payload)  -- { followerGUID, followDist? }
    local ok, err = pcall(setFollowOwner, player, payload or {})
    if not ok then sendClientLog(player, "FollowOwner ERROR: "..tostring(err)) end
  end,

  Followers_GuardPoint = function(player, payload)   -- { followerGUID, x,y,z, r? }
    local ok, err = pcall(setGuardPoint, player, payload or {})
    if not ok then sendClientLog(player, "GuardPoint ERROR: "..tostring(err)) end
  end,
})

-- ---------------------------------------------------------------------------
-- УБОРКА СОСТОЯНИЯ ПРИ ВЫХОДЕ ИГРОКА
-- ---------------------------------------------------------------------------
local PLAYER_EVENT_ON_LOGOUT = 4
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, function(event, player)
  -- Деспавним всё, гасим сенсор и убираем контекст
  local ok, err = pcall(despawnAll, player)
  if not ok then log("Logout cleanup error: %s", tostring(err)) end
end)

log("Loaded PatronFollowers_Manager (AIO channel: %s)", CHANNEL)
