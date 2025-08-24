local AIO = AIO or require("AIO")
local json = json or require("dkjson")

local EQUIPMENT_SLOT_MAINHAND = 15   -- Eluna Player:GetEquippedItemBySlot(15) → Item  (slot 15 = main-hand). :contentReference[oaicite:6]{index=6}
local AP_PER_DPS = 3.5               -- Retail 6.0.2+: 1 DPS на 3.5 AP. :contentReference[oaicite:7]{index=7}
local PET_INHERIT = 0.70             -- 70% силы владельца для петов (требование ТЗ)
local AOE_CAP_DEFAULT = 8            -- мягкий кап целей
local VARIANCE_PCT = 0.25            -- ±25% дисперсия

local playerCooldowns = {}           -- GUID → { [blessingID]=lastCast }

local ServerBlessingsConfig = {
  blessing_stamina = { -- BUFF
    name = "Благословение Силы",
    description = "Придает вам неимоверную силу!",
    spell_id = 48743,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 60,
    cost_item_id = 500000, cost_amount = 0,
  },

  blessing_power = { -- BUFF
    name = "Благословение Стойкости",
    description = "Повышает вашу выносливость и живучесть!",
    spell_id = 132959,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 20,
    cost_item_id = 500000, cost_amount = 0,
  },

  blessing_attack = { -- SINGLE
    name = "Благословение Атаки",
    description = "Призывает мощный удар по врагу!",
    spell_id = 133,  -- визуал (опционально)
    is_offensive = true, requires_target = true, is_aoe = false,
    cooldown_seconds = 10, range = 40.0,
    cost_item_id = 500000, cost_amount = 0,
    -- эффект урона — в какой слот bp подставлять рассчитанное значение
    effect = 25, effect2 = nil, effect3 = nil,
    dmg_effect = "effect",
    currencyK = 2.9,
  },

  blessing_aoe = { -- AOE
    name = "Благословение Ливня",
    description = "Призывает мощный удар по площади на последней позиции врага",
    spell_id = 190356,          -- визуал на землю
    spell_tick_id = 228599,     -- тик-спелл
    is_offensive = true, is_aoe = true, requires_target = true,
    radius = 8.0, tick_ms = 500, duration_ms = 14000,
    cooldown_seconds = 12, range = 40.0,
    cost_item_id = 500000, cost_amount = 0,
    effect = 25, effect2 = nil, effect3 = nil,  -- базовая «искра»
    dmg_effect = "effect",
    currencyK = 2.9,
    aoe_cap_targets = 8
  },
}


-- ======================= [ ROUTER ] =============================

local BlessingsHandler = AIO.AddHandlers("blessings", {})

-- Серверная функция для запроса благословения с клиента
function BlessingsHandler.RequestBlessing(player, data)
    print("----------------------------------------------------------------")
    print("[BlessingUI - Server DEBUG] -- Начало RequestBlessing --")

    local success_pcall, result_pcall = pcall(function()
        local playerName = player:GetName()
        print("[BlessingUI - Server DEBUG] Получен запрос от: " .. playerName)
        print("[BlessingUI - Server DEBUG] Данные запроса: " .. tostring(data.blessingID))

        local blessingID = data.blessingID
        local info = ServerBlessingsConfig[blessingID]

        if not info then
            player:SendBroadcastMessage("Неизвестное благословение.")
            print("[BlessingUI - Server DEBUG] ОШИБКА: Неизвестное благословение ID: " .. tostring(blessingID))
            return
        end
        print("[BlessingUI - Server DEBUG] Благословение найдено: " .. info.name .. " (Spell ID: " .. tostring(info.spell_id) .. ")")

        -- === ЛОГИКА ОБРАБОТКИ ЦЕЛИ === (встроенная как в старом коде)
        local finalSpellTarget = player -- По умолчанию цель - сам игрок

        if info.requires_target then
            local targetUnit = player:GetSelection()

            if not targetUnit or not targetUnit:IsInWorld() then
                player:SendBroadcastMessage("Вам нужно выбрать цель для этого благословения, " .. info.name .. ".")
                print("[BlessingUI - Server DEBUG] ОШИБКА: Нет выбранной цели или цель не находится в мире.")
                return
            end

            finalSpellTarget = targetUnit

            if info.is_offensive then
                -- 1. Проверка на атаку самого себя
                if targetUnit:GetGUID() == player:GetGUID() then
                    player:SendBroadcastMessage(("Вы не можете атаковать себя с помощью %s!"):format(info.name))
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Попытка атаковать себя.")
                    return
                end

                -- 2. Проверка дружебности
                local checkRadius = 60.0
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
                    player:SendBroadcastMessage("Вы не можете атаковать дружественную цель с помощью " .. info.name .. "!")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Попытка атаковать дружественную цель (найдена в списке дружественных).")
                    return
                end

                -- 3. Проверка, жива ли цель
                if not targetUnit:IsAlive() then
                    player:SendBroadcastMessage("Ваша цель мертва.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель мертва.")
                    return
                end

                -- 4. Проверка "атакуемости"
                local success, isTargetable = pcall(targetUnit.IsTargetableForAttack, targetUnit)
                if success and not isTargetable then
                    player:SendBroadcastMessage("Эту цель нельзя атаковать.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель не является атакуемой (IsTargetableForAttack вернул false).")
                    return
                end
                
                -- 5. Проверка дистанции
                local max_range = info.range or 40.0
                if player:GetDistance(targetUnit) > max_range then
                    player:SendBroadcastMessage("Ваша цель находится слишком далеко.")
                    print("[BlessingUI - Server DEBUG] ОШИБКА: Цель слишком далеко.")
                    return
                end
            end
        end
        print("[BlessingUI - Server DEBUG] Обработка цели завершена. Конечная цель: " .. tostring(finalSpellTarget:GetName()))

        -- === ПРОВЕРКИ ИГРОКА === (встроенные как в старом коде)
        
        -- Проверка активности ауры (только для не-атакующих)
        if not info.is_offensive and info.spell_id and player:HasAura(info.spell_id) then
            player:SendBroadcastMessage(("%s уже активен!"):format(info.name))
            print("[BlessingUI - ServerDEBUG] Благословение уже активно.")
            return
        end
		
		if not info.is_offensive then
			-- 1) Визуал (мгновенно, без стоимости)
			if info.spell_id > 0 then
				pcall(player.CastSpell, player, finalSpellTarget, info.spell_id, true)
			end

			-- 2) Гарантированно повесим ауру, если её нет
			local existing = finalSpellTarget:GetAura(info.spell_id)
			if not existing then
				local ok, auraObj = pcall(player.AddAura, player, info.spell_id, finalSpellTarget)
				if ok and auraObj and info.aura_duration_ms then
					auraObj:SetMaxDuration(info.aura_duration_ms)
					auraObj:SetDuration(info.aura_duration_ms)
				end
			end
		end

        -- Проверка кулдауна
        local playerGUID = player:GetGUIDLow()
        if not playerCooldowns[playerGUID] then playerCooldowns[playerGUID] = {} end
        local lastCastTime = playerCooldowns[playerGUID][blessingID] or 0
        local currentTime = os.time()

        if currentTime - lastCastTime < info.cooldown_seconds then
            local remainingTime = info.cooldown_seconds - (currentTime - lastCastTime)
            player:SendBroadcastMessage(("Вы не можете использовать %s еще %.0f сек."):format(info.name, remainingTime))
            print("[BlessingUI - Server DEBUG] Благословение на кулдауне. Осталось: " .. remainingTime .. " сек.")
            return
        end
        print("[BlessingUI - Server DEBUG] Проверка кулдауна пройдена.")

        -- Проверка и списание стоимости
        if info.cost_item_id and info.cost_amount > 0 then
            if player:GetItemCount(info.cost_item_id) < info.cost_amount then
                player:SendBroadcastMessage("Вам не хватает реагентов для этого благословения.")
                print("[BlessingUI - Server DEBUG] Недостаточно предметов.")
                return
            end
            player:RemoveItem(info.cost_item_id, info.cost_amount)
            print("[BlessingUI - Server DEBUG] Предметы списаны.")
        end

        -- === ПРИМЕНЕНИЕ ЭФФЕКТА ===
        if info.is_aoe then
            -- Используем стабильную StartGroundAoE (как в старом коде)
            StartGroundAoE(player, finalSpellTarget, info)
        elseif info.is_offensive then
            -- Динамический расчет урона для single атаки
            local singleDamage = PatronCalc_SingleBudget(player, info)
            local bp0, bp1, bp2 = build_bp_triplet(info, singleDamage)
            local tickId = info.spell_tick_id or info.spell_id
            if tickId and tickId > 0 then
                pcall(player.CastCustomSpell, player, finalSpellTarget, tickId, true, bp0, bp1, bp2)
                print(("[BlessingUI - Server DEBUG] Single attack: damage=%d"):format(singleDamage))
            end
        else
            DoBuff(player, finalSpellTarget, info)
        end

        -- Считаем операцию успешной
        local playerGUID = player:GetGUIDLow()
        if not playerCooldowns[playerGUID] then playerCooldowns[playerGUID] = {} end
        playerCooldowns[playerGUID][blessingID] = os.time()
        player:SendBroadcastMessage(("Вы успешно использовали %s!"):format(info.name))
        print("[BlessingUI - Server DEBUG] УСПЕХ: " .. playerName .. " использовал " .. info.name)
        
    end) -- Конец корневого pcall

    if not success_pcall then
        print("[BlessingUI - Server DEBUG] КРИТИЧЕСКАЯ ОШИБКА в RequestBlessing: " .. tostring(result_pcall))
        if player and pcall(player.GetName, player) then
            player:SendBroadcastMessage("На сервере произошла критическая ошибка при обработке вашего запроса.")
        end
    end
    print("----------------------------------------------------------------")
end

function clamp(x, lo, hi) return (x<lo and lo) or (x>hi and hi) or x end
function rand_pm(x) return 1 + (math.random(-x, x) * 0.01) end
function rand_pm25() return rand_pm(25) end

function DoBuff(caster, target, info)
    -- 1) Применим спелл, если он задан
    if info.spell_id > 0 then
        pcall(caster.CastSpell, caster, target, info.spell_id, true)
    end
    -- 2) Гарантированно повесим ауру, если её нет
    local existing = target:GetAura(info.spell_id)
    if not existing then
        local ok, auraObj = pcall(caster.AddAura, caster, info.spell_id, target)
        if ok and auraObj and info.aura_duration_ms then
            auraObj:SetMaxDuration(info.aura_duration_ms)
            auraObj:SetDuration(info.aura_duration_ms)
        end
    end
end


-- Единый бюджет для спела (single) от оружия/AP и валюты
function PatronCalc_SingleBudget(caster, info)
  if not (caster and caster.IsInWorld and caster:IsInWorld()) then return 0 end
  local root, petScale = resolve_caster_and_scale(caster)
  local player = (root.ToPlayer and root:ToPlayer()) and root or nil
  if not player then return 0 end

  local weapDPS = GetWeaponDPS(player)
  local ap      = EstimateAP(player)
  local autoDPS = weapDPS + (ap / AP_PER_DPS)

  local base      = tonumber(info.effect or 0) or 0
  local currencyK = tonumber(info.currencyK or 1.0) or 1.0

  local budget = base + currencyK * autoDPS
  budget = budget * petScale
  budget = budget * (1 + (math.random() * 2 * VARIANCE_PCT - VARIANCE_PCT)) -- ±25%

  return math.floor(clamp(budget, 1, 500000))
end

-- Преобразование «бюджета одиночки» в АоЕ-тик (раздача по целям + мягкий кап)
function AoE_tick_from_single(singleBudget, targetsCount, capTargets, aoeMult)
  local n = math.max(1, targetsCount)
  local cap = capTargets or AOE_CAP_DEFAULT
  local mult = aoeMult or 0.75
  local capScale = (n > cap) and (cap / n) or 1.0
  local perTarget = (singleBudget / n) * mult * capScale
  perTarget = perTarget * (1 + (math.random() * 2 * VARIANCE_PCT - VARIANCE_PCT)) -- ±25%
  return math.max(1, math.floor(perTarget + 0.5))
end

function resolve_caster_and_scale(unit)
  local owner = unit and unit.GetOwner and unit:GetOwner() or nil
  if owner and owner.ToPlayer and owner:ToPlayer() then
    return owner, PET_INHERIT
  end
  return unit, 1.0
end

function effect_index(dmg_effect)
  if type(dmg_effect) == "number" then
    if dmg_effect < 0 then return 0 elseif dmg_effect > 2 then return 2 else return dmg_effect end
  end
  if dmg_effect == "effect2" then return 1
  elseif dmg_effect == "effect3" then return 2
  else return 0 end
end

function build_bp_triplet(info, dmgValue)
  -- backward-compat: поддержим старые damage_per_tick*
  local e0 = tonumber(info.effect  or info.damage_per_tick   or 0) or 0
  local e1 = tonumber(info.effect2 or info.damage_per_tick2  or 0) or 0
  local e2 = tonumber(info.effect3 or info.damage_per_tick3  or 0) or 0
  local idx = effect_index(info.dmg_effect)

  if idx == 0 then e0 = dmgValue
  elseif idx == 1 then e1 = dmgValue
  else e2 = dmgValue end

  return math.floor(e0+0.5), math.floor(e1+0.5), math.floor(e2+0.5)
end

-- Грубая оценка AP от STR/AGI (для привязки к автоатаке достаточно)
local STAT_STRENGTH, STAT_AGILITY = 0, 1
local PRIMARY_BY_CLASS = { [1]="STR",[2]="STR",[3]="AGI",[4]="AGI",[5]="INT",[6]="STR",[7]="INT",[8]="INT",[9]="INT",[10]="AGI",[11]="INT",[12]="AGI",[13]="INT" }

function EstimateAP(u)
  if not (u and u.GetClass and u.GetStat) then return 0 end
  local prim = PRIMARY_BY_CLASS[u:GetClass()] or "STR"
  if prim == "AGI" then return u:GetStat(STAT_AGILITY) or 0
  elseif prim == "STR" then return u:GetStat(STAT_STRENGTH) or 0
  else
    local s = u:GetStat(STAT_STRENGTH) or 0
    local a = u:GetStat(STAT_AGILITY)  or 0
    return 0.5*s + 0.5*a
  end
end

function GetWeaponDPS(player)
  local it = player and player.GetEquippedItemBySlot and player:GetEquippedItemBySlot(EQUIPMENT_SLOT_MAINHAND)
  if not it then return 0 end
  local minD, maxD = nil, nil
  if it.GetDamageInfo then
    minD, maxD = it:GetDamageInfo(0)
    if not (minD and maxD) then minD, maxD = it:GetDamageInfo(1) end
  end
  local spd_ms = it.GetSpeed and it:GetSpeed() or 0
  if not (minD and maxD and spd_ms and spd_ms > 0) then return 0 end
  local avg = 0.5 * (minD + maxD)
  return avg / (spd_ms / 1000)
end

-- ================================================================

-- Точная копия StartGroundAoE из старого файла, но с динамическим расчетом урона
if not StartGroundAoE then
  function StartGroundAoE(player, centerUnit, info)
    if not (player and centerUnit and player:IsInWorld() and centerUnit:IsInWorld()) then return end

    -- фиксируем координаты центра «лужи»
    local cx, cy, cz = centerUnit:GetX(), centerUnit:GetY(), centerUnit:GetZ()

    local spellId    = tonumber(info.spell_id) or 190356
    local radius     = tonumber(info.radius)   or 12.0
    local tickMs     = tonumber(info.tick_ms)  or 500
    local durationMs = tonumber(info.duration_ms) or 4000
    local spell_tick_id = tonumber(info.spell_tick_id) or 2136
    
    -- Рассчитываем базовый урон один раз (как основу для пересчета)
    local singleBase = PatronCalc_SingleBudget(player, info)
    if singleBase <= 0 then return end
    
    print(("[BlessingUI - Server DEBUG] StartGroundAoE: center=(%.1f,%.1f,%.1f) R=%.1f singleBase=%d"):format(cx, cy, cz, radius, singleBase))

    -- визуал по земле (мгновенно, без GCD/стоимости)
    pcall(player.CastSpellAoF, player, cx, cy, cz, spellId, true)

    local ticks = math.max(1, math.floor(durationMs / tickMs))

    -- Тик привязываем к Player: RegisterEvent даёт (eventId, delay, repeats, worldobject)
    local function onTick(eventId, _delay, repeatsLeft, wo)
      -- wo — это живой WorldObject (= твой Player) на момент вызова
      if not (wo and wo.IsInWorld and wo:IsInWorld()) then
        -- таймер уедет автоматически, но можно снять явно
        if wo and wo.RemoveEventById then wo:RemoveEventById(eventId) end
        return
      end

      -- радиус поиска вокруг игрока, чтобы накрыть удалённый центр
      local pdist   = wo:GetDistance(cx, cy, cz) or 0
      local searchR = math.min(120, pdist + radius + 10)

      -- пул врагов: единый список юнитов (игроки/мобы) вокруг игрока
      local pool = wo:GetUnfriendlyUnitsInRange(searchR) or {}

      local hits = 0
      local validTargets = {}
      
      -- Собираем валидные цели
      for _, u in ipairs(pool) do
        if u and u:IsInWorld() and u:IsAlive() and (u:GetDistance(cx, cy, cz) or 1e9) <= radius then
          validTargets[#validTargets + 1] = u
        end
      end
      
      -- Пересчитываем урон на основе количества целей каждый тик
      if #validTargets > 0 then
        local dmgTick = AoE_tick_from_single(singleBase, #validTargets, info.aoe_cap_targets or 8, 0.75)
        local bp0, bp1, bp2 = build_bp_triplet(info, dmgTick)
        
        for _, u in ipairs(validTargets) do
          local ok = pcall(wo.CastCustomSpell, wo, u, spell_tick_id, true, bp0, bp1, bp2)
          if ok then hits = hits + 1 end
        end
      end

      -- отладка
      print(("[BlessingUI - Server DEBUG] AoE tick pdist=%.1f searchR=%.1f pool=%d valid=%d hits=%d"):format(pdist, searchR, #pool, #validTargets, hits))
      
      if repeatsLeft and repeatsLeft <= 1 then
        print("[BlessingUI - Server DEBUG] AoE finished")
      end
    end

    -- Привязанный к Player таймер (безопаснее, чем глобальный CreateLuaEvent)
    player:RegisterEvent(onTick, tickMs, ticks)
  end
end

print("[PatronBlessings] Server handler loaded.")