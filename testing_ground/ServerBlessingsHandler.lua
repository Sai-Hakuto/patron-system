local AIO = AIO or require("AIO")
local json = require("dkjson")
local BlessingsHandler = AIO.AddHandlers("blessings", {})

local SPELL_REQ_OPCODE = 0x35F0

local CONFIG = {
    API_URL = "http://127.0.0.1/api.php",
    CURL_PATH = "curl"
}

-- Конфигурация благословений на сервере
local ServerBlessingsConfig = {
    blessing_power = {
        name = "Благословение Силы",
        description = "Придает вам неимоверную силу!",
        spell_id = 132959,
        cost_item_id = 500000,
        cost_amount = 0,
        cooldown_seconds = 60,
    },
    blessing_stamina = {
        name = "Благословение Стойкости",
        description = "Повышает вашу выносливость и живучесть!",
        spell_id = 48743,
        cost_item_id = 500000,
        cost_amount = 0,
        cooldown_seconds = 60,
    },
    blessing_attack = {
        name = "Благословение Атаки",
        description = "Призывает мощный удар по врагу!",
        spell_id = 133,          -- ID заклинания для анимации
        damage = 500,              -- Количество урона
        damage_school = 7,        -- Школа урона (0=физ, 1=свет, 2=огонь, 3=природа, 4=лед, 5=тьма, 6=аркан, 7 - чистый дамаг)
        cost_item_id = 500000,
        cost_amount = 0,
        cooldown_seconds = 10,
        requires_target = true,   -- Требует цель
        is_offensive = true,      -- Является атакующим
    },
	blessing_aoe = {
	  name = "Благословение Ливня",
	  spell_id = 190356,            -- визуал Blizzard по земле
	  is_offensive = true,
	  is_aoe = true,
	  requires_target = true,
	  radius = 8.0,
	  tick_ms = 500,
	  duration_ms = 4000,
	  damage_per_tick = 120,
	  damage_school = 4,            -- не критично, дальше пойдём через CastCustomSpell
	  tick_spell_id = 116,         -- <=== одноцелевой спелл для тиков (подменим bp0)
	  cooldown_seconds = 12,
	  cost_item_id = 500000, cost_amount = 0
	},
}

-- Таблица для отслеживания кулдаунов по игрокам и благословениям
local playerCooldowns = {}

-- Deserialize configuration parameters from the incoming message.
local function deserializeConfig(msg)
    local cfg = {}
    if not msg or not msg.ReadUByte then
        return cfg
    end

    cfg.triggered = msg:ReadUByte() ~= 0
    cfg.bp0 = msg:ReadInt32()
    cfg.bp1 = msg:ReadInt32()
    cfg.bp2 = msg:ReadInt32()
    cfg.castItem = msg:ReadULong()
    cfg.originalCaster = msg:ReadGUID()

    -- AoE specific options
    cfg.mainSpell = msg:ReadUInt32()
    cfg.radius = msg:ReadFloat()
    cfg.durationMs = msg:ReadUInt32()
    cfg.tickMs = msg:ReadUInt32()

    return cfg
end

-- Helper to resolve target GUID to a unit; falls back to player.
local function resolveTarget(player, guid)
    if not guid or guid == 0 then
        return player
    end

    local map = player:GetMap and player:GetMap()
    if map and map.GetWorldObject then
        local obj = map:GetWorldObject(guid)
        if obj then
            return obj
        end
    end
    return player
end

local function doBuff(player, visualSpellId, targetGUID, cfg)
    local target = resolveTarget(player, targetGUID)
    if visualSpellId and visualSpellId > 0 then
        pcall(player.CastSpell, player, target, visualSpellId, cfg.triggered)
    end
end

local function doSingle(player, visualSpellId, targetGUID, cfg)
    local target = resolveTarget(player, targetGUID)
    local spell = cfg.mainSpell or visualSpellId
    pcall(player.CastCustomSpell, player, target, spell, cfg.triggered, cfg.bp0 or 0, cfg.bp1 or 0, cfg.bp2 or 0, cfg.castItem or 0, cfg.originalCaster)
    if visualSpellId and visualSpellId > 0 and visualSpellId ~= spell then
        pcall(player.CastSpell, player, target, visualSpellId, true)
    end
end

local function doAOE(player, visualSpellId, targetGUID, cfg)
    local target = resolveTarget(player, targetGUID)
    StartGroundAoE(player, target, {
        spell_id = visualSpellId,
        radius = cfg.radius,
        tick_ms = cfg.tickMs,
        duration_ms = cfg.durationMs,
        tick_spell_id = cfg.mainSpell,
        triggered = cfg.triggered,
        bp0 = cfg.bp0,
        bp1 = cfg.bp1,
        bp2 = cfg.bp2,
        cast_item = cfg.castItem,
        original_caster = cfg.originalCaster,
    })
end

function BlessingsHandler.SpellRequest(player, msg)
    local spellType = msg:ReadUByte()
    local visualSpellId = msg:ReadULong()
    local targetGUID = msg:ReadGUID()
    local cfg = deserializeConfig(msg)

    if spellType == 0 then
        doBuff(player, visualSpellId, targetGUID, cfg)
    elseif spellType == 1 then
        doSingle(player, visualSpellId, targetGUID, cfg)
    elseif spellType == 2 then
        doAOE(player, visualSpellId, targetGUID, cfg)
    end
end

AIO.AddCustomPacketHandler(SPELL_REQ_OPCODE, BlessingsHandler.SpellRequest)

-- Серверная функция для запроса благословения с клиента
function BlessingsHandler.RequestBlessing(player, data)
    print("----------------------------------------------------------------")
    print("[BlessingUI - Server DEBUG] -- Начало RequestBlessing --")

    local success_pcall, result_pcall = pcall(function()
        local playerName = player:GetName()
        print("[BlessingUI - Server DEBUG] Получен запрос от: " .. playerName)
        print("[BlessingUI - Server DEBUG] Данные запроса: " .. tostring(data.blessingID))

        local blessingID = data.blessingID
        local blessingInfo = ServerBlessingsConfig[blessingID]

        if not blessingInfo then
            player:SendBroadcastMessage("Неизвестное благословение.")
            print("[BlessingUI - Server DEBUG] ОШИБКА: Неизвестное благословение ID: " .. tostring(blessingID))
            return
        end
        print("[BlessingUI - Server DEBUG] Благословение найдено: " .. blessingInfo.name .. " (Spell ID: " .. tostring(blessingInfo.spell_id) .. ")")

        -- === ЛОГИКА ОБРАБОТКИ ЦЕЛИ ===
        local finalSpellTarget = player -- По умолчанию цель - сам игрок

        if blessingInfo.requires_target then
            local targetUnit = player:GetSelection()

            if not targetUnit or not targetUnit:IsInWorld() then
                player:SendBroadcastMessage("Вам нужно выбрать цель для этого благословения, " .. blessingInfo.name .. ".")
                print("[BlessingUI - Server DEBUG] ОШИБКА: Нет выбранной цели или цель не находится в мире.")
                return
            end

            finalSpellTarget = targetUnit

            if blessingInfo.is_offensive then
                -- 1. Проверка на атаку самого себя
                if targetUnit:GetGUID() == player:GetGUID() then
                    player:SendBroadcastMessage(("Вы не можете атаковать себя с помощью %s!"):format(blessingInfo.name))
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Попытка атаковать себя.")
                    return
                end

                -- НОВАЯ ЛОГИКА ПРОВЕРКИ ДРУЖЕБНОСТИ ЧЕРЕЗ GetFriendlyUnitsInRange
                -- Примечание: Для этой проверки нам понадобится достаточно большой радиус,
                -- чтобы гарантировать, что цель, если она дружественна, попадет в этот радиус.
                -- Использование текущей дистанции до цели или фиксированного большого радиуса.
                local checkRadius = 60.0 -- Например, 60 метров, чтобы охватить большинство сценариев
                local friendlyUnits = player:GetFriendlyUnitsInRange(checkRadius)
                print("[BlessingUI - Server DEBUG] Количество дружественных юнитов найдено в радиусе " .. checkRadius .. ": " .. tostring(#friendlyUnits))

                local isTargetFriendly = false
                if friendlyUnits then
                    for i, unit in ipairs(friendlyUnits) do
                        if unit and unit:GetGUID() == targetUnit:GetGUID() then
                            isTargetFriendly = true
                            break
                        end
                    end
                end

                if isTargetFriendly then
                    player:SendBroadcastMessage("Вы не можете атаковать дружественную цель с помощью " .. blessingInfo.name .. "!")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Попытка атаковать дружественную цель (найдена в списке дружественных).")
                    return
                end
                -- КОНЕЦ НОВОЙ ЛОГИКИ

                -- 3. Проверка, жива ли цель
                if not targetUnit:IsAlive() then
                    player:SendBroadcastMessage("Ваша цель мертва.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель мертва.")
                    return
                end

                -- 4. Безопасная проверка "атакуемости" для существ (Creature)
                local success, isTargetable = pcall(targetUnit.IsTargetableForAttack, targetUnit)
                if success and not isTargetable then
                    player:SendBroadcastMessage("Эту цель нельзя атаковать.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель не является атакуемой (IsTargetableForAttack вернул false).")
                    return
                end
                
                -- 5. Проверка дистанции
                local max_range = 40.0
                if player:GetDistance(targetUnit) > max_range then
                    player:SendBroadcastMessage("Ваша цель находится слишком далеко.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель слишком далеко.")
                    return
                end
            end
        end
        print("[BlessingUI - Server DEBUG] Обработка цели завершена. Конечная цель: " .. tostring(finalSpellTarget:GetName()))

        -- === ПРОВЕРКИ ИГРОКА ===
        
        -- Проверка активности ауры (только для не-атакующих)
        if not blessingInfo.is_offensive and blessingInfo.spell_id and player:HasAura(blessingInfo.spell_id) then
            player:SendBroadcastMessage(("%s уже активен!"):format(blessingInfo.name))
            print("[BlessingUI - ServerDEBUG] Благословение уже активно.")
            return
        end
		
		if not blessingInfo.is_offensive then
			-- 1) Визуал (мгновенно, без стоимости)
			if blessingInfo.spell_id > 0 then
				pcall(player.CastSpell, player, finalSpellTarget, blessingInfo.spell_id, true) -- Unit:CastSpell(target, spell, triggered)
				-- triggered=true: мгновенно, без стоимости/GCD. Возвращает ничего.
			end

			-- 2) Гарантированно повесим ауру, если её нет
			local existing = finalSpellTarget:GetAura(blessingInfo.spell_id)  -- вернёт Aura или nil
			if not existing then
				local ok, auraObj = pcall(player.AddAura, player, blessingInfo.spell_id, finalSpellTarget) -- Unit:AddAura(spell, target)
				if ok and auraObj and blessingInfo.aura_duration_ms then
					-- при необходимости можно задать/обновить длительность
					auraObj:SetMaxDuration(blessingInfo.aura_duration_ms)
					auraObj:SetDuration(blessingInfo.aura_duration_ms)
				end
			end
		end

        -- Проверка кулдауна
        local playerGUID = player:GetGUIDLow()
        if not playerCooldowns[playerGUID] then playerCooldowns[playerGUID] = {} end
        local lastCastTime = playerCooldowns[playerGUID][blessingID] or 0
        local currentTime = os.time()

        if currentTime - lastCastTime < blessingInfo.cooldown_seconds then
            local remainingTime = blessingInfo.cooldown_seconds - (currentTime - lastCastTime)
            player:SendBroadcastMessage(("Вы не можете использовать %s еще %.0f сек."):format(blessingInfo.name, remainingTime))
            print("[BlessingUI - Server DEBUG] Благословение на кулдауне. Осталось: " .. remainingTime .. " сек.")
            return
        end
        print("[BlessingUI - Server DEBUG] Проверка кулдауна пройдена.")

        -- Проверка и списание стоимости
        if blessingInfo.cost_item_id and blessingInfo.cost_amount > 0 then
            if player:GetItemCount(blessingInfo.cost_item_id) < blessingInfo.cost_amount then
                player:SendBroadcastMessage("Вам не хватает реагентов для этого благословения.")
                print("[BlessingUI - Server DEBUG] Недостаточно предметов.")
                return
            end
            player:RemoveItem(blessingInfo.cost_item_id, blessingInfo.cost_amount)
            print("[BlessingUI - Server DEBUG] Предметы списаны.")
        end

        -- === ПРИМЕНЕНИЕ ЭФФЕКТА ===
		if blessingInfo.is_offensive then
			if blessingInfo.is_aoe then
				-- AoE: центр по выбранной цели (или по игроку, если не требуется цель)
				local center = finalSpellTarget or player
				StartGroundAoE(player, center, {
					spell_id        = blessingInfo.spell_id,
					radius          = blessingInfo.radius,
					tick_ms         = blessingInfo.tick_ms,
					duration_ms     = blessingInfo.duration_ms,
					damage_per_tick = blessingInfo.damage_per_tick,
					damage_school   = blessingInfo.damage_school,
				})
			elseif blessingInfo.damage and blessingInfo.damage > 0 then
				-- Single-target (как у тебя работает сейчас: CastCustomSpell с fallback)
				local ok1, err1 = pcall(player.CastCustomSpell, player, finalSpellTarget,
					blessingInfo.spell_id, true, blessingInfo.damage, 0, 0)
				if not ok1 then
					local school = blessingInfo.damage_school or 1
					local ok2 = pcall(player.DealDamage, player, finalSpellTarget,
						blessingInfo.damage, false, school, blessingInfo.spell_id)
					if not ok2 then print("[Blessings] DealDamage fallback failed") end
				end
			else
				if blessingInfo.spell_id > 0 then
					pcall(player.CastSpell, player, finalSpellTarget, blessingInfo.spell_id, true) -- обычный визуал. :contentReference[oaicite:5]{index=5}
				end
			end
		end

        -- Считаем операцию успешной
        playerCooldowns[playerGUID][blessingID] = currentTime
        player:SendBroadcastMessage(("Вы успешно использовали %s!"):format(blessingInfo.name))
        print("[BlessingUI - Server DEBUG] УСПЕХ: " .. playerName .. " использовал " .. blessingInfo.name)
        
    end) -- Конец корневого pcall

    if not success_pcall then
        print("[BlessingUI - Server DEBUG] КРИТИЧЕСКАЯ ОШИБКА в RequestBlessing: " .. tostring(result_pcall))
        if player and pcall(player.GetName, player) then
            player:SendBroadcastMessage("На сервере произошла критическая ошибка при обработке вашего запроса.")
        end
    end
    print("----------------------------------------------------------------")
end

-- безопасные константы для DealDamage
-- Включить/выключить диагностику в лог

-- Blizzard-like AoE: визуал в точке + тики урона
if not StartGroundAoE then
  function StartGroundAoE(player, centerUnit, info)
    if not (player and centerUnit and player:IsInWorld() and centerUnit:IsInWorld()) then return end

    -- фиксируем координаты центра «лужи»
    local cx, cy, cz = centerUnit:GetX(), centerUnit:GetY(), centerUnit:GetZ()

    local spellId    = tonumber(info.spell_id) or 190356
    local radius     = tonumber(info.radius)   or 12.0
    local tickMs     = tonumber(info.tick_ms)  or 500
    local durationMs = tonumber(info.duration_ms) or 4000
    local tickSpell  = tonumber(info.tick_spell_id) or 0
    if tickSpell == 0 then return end

    local triggered = info.triggered
    local bp0 = tonumber(info.bp0) or 0
    local bp1 = tonumber(info.bp1) or 0
    local bp2 = tonumber(info.bp2) or 0
    local castItem = info.cast_item
    local originalCaster = info.original_caster

    -- визуал по земле (мгновенно, без GCD/стоимости)
    pcall(player.CastSpellAoF, player, cx, cy, cz, spellId, true)          -- :contentReference[oaicite:2]{index=2}

    local ticks = math.max(1, math.floor(durationMs / tickMs))

    -- Тик привязываем к Player: RegisterEvent даёт (eventId, delay, repeats, worldobject)
    local function onTick(eventId, _delay, repeatsLeft, wo)
      -- wo — это живой WorldObject (= твой Player) на момент вызова
      if not (wo and wo.IsInWorld and wo:IsInWorld()) then
        -- таймер уедет автоматически, но можно снять явно
        if wo and wo.RemoveEventById then wo:RemoveEventById(eventId) end  -- :contentReference[oaicite:3]{index=3}
        return
      end

      -- радиус поиска вокруг игрока, чтобы накрыть удалённый центр
      local pdist   = wo:GetDistance(cx, cy, cz) or 0                      -- :contentReference[oaicite:4]{index=4}
      local searchR = math.min(120, pdist + radius + 10)

      -- пул врагов: единый список юнитов (игроки/мобы) вокруг игрока
      local pool = wo:GetUnfriendlyUnitsInRange(searchR) or {}             -- :contentReference[oaicite:5]{index=5}

      local hits = 0
      for _, u in ipairs(pool) do
        if u and u:IsInWorld() and u:IsAlive() and (u:GetDistance(cx, cy, cz) or 1e9) <= radius then
          -- ВАЖНО: self = wo (живой Player из колбэка), а не «player» из внешней области
          local ok = pcall(wo.CastCustomSpell, wo, u, tickSpell, triggered, bp0, bp1, bp2, castItem, originalCaster)
          if ok then hits = hits + 1 end
        end
      end

      -- можно оставить отладку
      -- print(("[AOE] tick pdist=%.1f searchR=%.1f cand=%d hits=%d"):format(pdist, searchR, #pool, hits))
      if repeatsLeft and repeatsLeft <= 1 then
        -- финальный тик: ничего дополнительного не нужно
      end
    end

    -- Привязанный к Player таймер (безопаснее, чем глобальный CreateLuaEvent)
    player:RegisterEvent(onTick, tickMs, ticks)                             -- :contentReference[oaicite:7]{index=7}
  end
end


-- Generic spell helpers

local function resolveGuid(guid, player)
    if not guid or (player and guid == player:GetGUID()) then
        return player
    end
    local target = GetPlayerByGUID and GetPlayerByGUID(guid) or nil
    if not target and player and player.GetMap then
        local map = player:GetMap()
        if map and map.GetCreatureByGUID then
            target = map:GetCreatureByGUID(guid)
        end
    end
    return target
end

function doBuff(player, spellId, guid, cfg)
    if not player or not spellId then return end
    local target = resolveGuid(guid, player)
    if not target or not target:IsInWorld() then return end
    if not player:IsFriendlyTo(target) then return end
    if cfg and cfg.range and player:GetDistance(target) > cfg.range then return end
    pcall(player.CastSpell, player, target, spellId, true)
end

function doSingle(player, spellId, guid, cfg)
    if not player or not spellId then return end
    cfg = cfg or {}
    local target = resolveGuid(guid, player)
    if not target or not target:IsInWorld() then return end
    if cfg.onlyHostile and player:IsFriendlyTo(target) then return end
    if cfg.range and player:GetDistance(target) > cfg.range then return end
    local bp0 = cfg.bp0 or 0
    local bp1 = cfg.bp1 or 0
    local bp2 = cfg.bp2 or 0
    local triggered = cfg.triggered ~= false
    pcall(player.CastCustomSpell, player, target, spellId, triggered, bp0, bp1, bp2)
end

function doAOE(player, aoeSpellId, guid, cfg)
    if not player or not aoeSpellId or not cfg or not cfg.mainSpell then return end
    cfg.radius = cfg.radius or 5
    cfg.tickMs = cfg.tickMs or 1000
    cfg.durationMs = cfg.durationMs or cfg.tickMs
    local center = resolveGuid(guid, player) or player
    if not center or not center:IsInWorld() then return end

    pcall(player.CastSpellAoF, player, center:GetX(), center:GetY(), center:GetZ(), aoeSpellId, true)

    local ticks = math.max(1, math.floor(cfg.durationMs / cfg.tickMs))
    local cx, cy, cz = center:GetX(), center:GetY(), center:GetZ()

    local function onTick(eventId, delay, repeats, caster)
        if not caster or not caster:IsInWorld() then
            if caster and caster.RemoveEventById then caster:RemoveEventById(eventId) end
            return
        end
        local pdist = caster:GetDistance(cx, cy, cz) or 0
        local searchR = math.min(120, pdist + cfg.radius + 10)
        local pool = caster:GetUnfriendlyUnitsInRange(searchR) or {}
        for _, unit in ipairs(pool) do
            if unit and unit:IsInWorld() and unit:IsAlive() and (unit:GetDistance(cx, cy, cz) or 1e9) <= cfg.radius then
                pcall(caster.CastCustomSpell, caster, unit, cfg.mainSpell, true, cfg.bp0 or 0, cfg.bp1 or 0, cfg.bp2 or 0)
            end
        end
    end

    player:RegisterEvent(onTick, cfg.tickMs, ticks)
end

--------------------------------------------------------------------

print("[BlessingUI] Серверный обработчик BlessingsHandler загружен (С ТЕСТОВОЙ ФУНКЦИЕЙ).")
