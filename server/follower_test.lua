-- Unified Helper System
-- Объединяет функционал найма, боевой логики и маунтов в одном файле

local AIO = AIO or require("AIO")
local HireHandlers = AIO.AddHandlers("hire", {})

if PatronLogger then
    PatronLogger:Info("FollowerTest", "Init", "follower_test.lua loaded")
else
    print("[PatronSystem] follower_test.lua loaded")
end

-- ========== КОНСТАНТЫ ==========
local HELPER_COST = 10   -- стоимость найма в меди
local SCAN_RADIUS = 20   -- радиус сканирования для поиска врагов
local HELPER_NPC_IDS = {9400000, 9400001, 9400002}

-- ========== ДАННЫЕ ХЕЛПЕРОВ ==========
local helperWeapons = {
    [9400000] = {6905, 228891},
    [9400001] = {6905, 228891},
    [9400002] = {6905, 228891}
}

-- Статы и характеристики хелперов
local helperStats = {
    [9400000] = { -- Алайя - танк/защитник
        healthMultiplier = 2.5  -- 250% от базового HP
    },
    [9400001] = { -- Арле'Кино - дамагер
        healthMultiplier = 1.8  -- 180% от базового HP
    },
    [9400002] = { -- Узан Дул - хилер/поддержка
        healthMultiplier = 2.0  -- 200% от базового HP
    }
}

local transmogEffects = {
    back = {
        { name = "Jetpack", spellID = 256205 },
        { name = "Backpack", spellID = 472705 },
        { name = "Plague Pack", spellID = 250088 },
        { name = "Fire Wings", spellID = 466487 },
        { name = "Pumpkin Helm", spellID = 393900 }
    },
    aura = {
        { name = "Ghostly Aura", spellID = 474318 },
        { name = "Lightning Fists", spellID = 1216575 },
        { name = "Deathknight", spellID = 473545 },
        { name = "Pirate", spellID = 430467 },
        { name = "Captain", spellID = 439264 }
    }
}

local mountSpells = {
    [9400000] = 1214940,
    [9400001] = 1214940,
    [9400002] = 1214940
}

local helperNameMap = {
    ["алайя"] = 1,
    ["арле'кино"] = 2,
    ["узан дул"] = 3
}

-- ========== БОЕВАЯ ЛОГИКА ==========
local npcCombatLogic = {
    [9400000] = function(helper, enemy) -- Алайя: Melee + Spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 330669)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true)
        end
    end,
    [9400001] = function(helper, enemy) -- Арле'Кино: Melee + Spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 845)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true)
        end
    end,
    [9400002] = function(helper, enemy) -- Узан Дул: Healer + Melee
        local owner = helper:GetOwner()
        if owner and owner:GetHealthPct() < 50 then
            helper:CastSpell(owner, 2061) -- Heal
        elseif helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 337429) -- Swipe
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true)
        end
    end
}

-- ========== УТИЛИТЫ ==========
local function ApplyTransmogEffect(npc, effectSpellID)
    if npc and effectSpellID then
        npc:CastSpell(npc, effectSpellID, true)
    end
end

-- Применить статы к хелперу
local function ApplyHelperStats(npc, helperID)
    local stats = helperStats[helperID]
    if not stats then return end

    -- Применяем HP множитель - делаем хп равным игроку x2
    local owner = npc:GetOwner()
    if owner then
        local playerHP = owner:GetMaxHealth()
        local newHP = playerHP * 2
        npc:SetMaxHealth(newHP)
        npc:SetHealth(newHP)
    end

    -- Включаем регенерацию здоровья
    npc:SetRegeneratingHealth(true)

    -- Иммунитет к эффектам контроля
    local IMMUNE_MECHANICS = {
        1,  -- MECHANIC_CHARM
        5,  -- MECHANIC_FEAR
        7,  -- MECHANIC_ROOT
        10, -- MECHANIC_SLEEP
        11, -- MECHANIC_SNARE
        12, -- MECHANIC_STUN
        17  -- MECHANIC_POLYMORPH
    }
    for _, mechanic in ipairs(IMMUNE_MECHANICS) do
        npc:SetImmuneTo(mechanic, true)
    end
end

local function EquipHelperItem(creature, helperID, itemID)
    local validItems = helperWeapons[helperID]
    if not validItems then return false end

    for _, validItem in ipairs(validItems) do
        if validItem == itemID then
            creature:SetEquipmentSlots(itemID, 0, 0)
            return true
        end
    end
    return false
end

function GetNPCByHelperID(player, fullHelperID)
    local npcList = player:GetCreaturesInRange(50)
    for _, npc in ipairs(npcList) do
        if npc:GetEntry() == fullHelperID and npc:GetOwnerGUID() == player:GetGUID() then
            return npc
        end
    end
    return nil
end

-- ========== БОЕВЫЕ ФУНКЦИИ ==========
local function HandleDefensiveCombat(helper)
    local owner = helper:GetOwner()
    if not owner then return end

    local enemies = owner:GetCreaturesInRange(SCAN_RADIUS)
    for _, enemy in ipairs(enemies) do
        if enemy:IsInCombat() and enemy:GetVictim() == owner then
            local npcID = helper:GetEntry()
            local combatLogic = npcCombatLogic[npcID]

            if combatLogic then
                combatLogic(helper, enemy)
            else
                helper:Attack(enemy, true)
            end
            return
        end
    end
end

local function RunDefensiveCombatChecks()
    for _, player in ipairs(GetPlayersInWorld()) do
        local npcs = player:GetCreaturesInRange(50)
        for _, npc in ipairs(npcs) do
            if npc:GetOwnerGUID() == player:GetGUID() then
                HandleDefensiveCombat(npc)
            end
        end
    end
end

-- ========== ФУНКЦИИ МАУНТОВ ==========
local MountedHelpers = {}

local function MountHelpers(player)
    for _, helperID in ipairs(HELPER_NPC_IDS) do
        local npc = GetNPCByHelperID(player, helperID)
        if npc and npc:IsAlive() and not npc:IsMounted() then
            npc:Mount(447413)
            MountedHelpers[helperID] = true
        end
    end
end

local function DismountHelpers(player)
    for _, helperID in ipairs(HELPER_NPC_IDS) do
        local npc = GetNPCByHelperID(player, helperID)
        if npc and npc:IsAlive() and npc:IsMounted() then
            npc:Dismount()
            MountedHelpers[helperID] = false
        end
    end
end

local function SyncHelperMounts(player)
    if player:HasAura(32, 6, 100) then -- проверка ауры маунта
        MountHelpers(player)
    else
        DismountHelpers(player)
    end
end

-- ========== AIO HANDLERS ==========
function HireHandlers.HireHelper(player, data)
    local helperIndex = data.helperIndex
    local itemID = data.itemID
    local backSpellID = data.backSpellID
    local auraSpellID = data.auraSpellID

    if PatronLogger then
        PatronLogger:Info("HireHelper", "Start", "params", { helperIndex = helperIndex, itemID = itemID, backSpellID = backSpellID, auraSpellID = auraSpellID })
    end

    -- Проверка валидности индекса
    if not HELPER_NPC_IDS[helperIndex] then 
        return AIO.Handle(player, "hire", "HireResult", {
            success = false,
            helperIndex = helperIndex,
            error = "Неверный индекс фолловера"
        })
    end
    
    local helperID = HELPER_NPC_IDS[helperIndex]
    local existingHelper = GetNPCByHelperID(player, helperID)

    if existingHelper then existingHelper:DespawnOrUnsummon() end
    
    -- Проверка стоимости (если включена)
    -- if player:GetCoinage() < HELPER_COST then 
    --     return AIO.Handle(player, "hire", "HireResult", {
    --         success = false,
    --         helperIndex = helperIndex,
    --         error = "Недостаточно денег для найма (" .. HELPER_COST .. " медь)"
    --     })
    -- end
    
    local x, y, z, o = player:GetLocation()
    local newNPC = player:SpawnCreature(helperID, x, y, z, o, 8, 0)

    if not newNPC then 
        return AIO.Handle(player, "hire", "HireResult", {
            success = false,
            helperIndex = helperIndex,
            error = "Не удалось создать NPC (ID: " .. helperID .. ")"
        })
    end

    newNPC:SetOwnerGUID(player:GetGUID())
    newNPC:SetLevel(player:GetLevel())
    newNPC:SetFaction(player:GetFaction())
    newNPC:SetReactState(1)
    newNPC:MoveFollow(player, 1.0, 2.0)
    
    -- Применяем кастомные статы для данного хелпера
    local ok, err = pcall(ApplyHelperStats, newNPC, helperID)
    if not ok and PatronLogger then
        PatronLogger:Error("HireHelper", "ApplyHelperStats", err)
    end

    if itemID then EquipHelperItem(newNPC, helperID, itemID) end
    if backSpellID then ApplyTransmogEffect(newNPC, backSpellID) end
    
    -- player:ModifyMoney(-HELPER_COST) -- Убрано для тестирования
    
    if PatronLogger then
        PatronLogger:Info("HireHelper", "Success", "Helper spawned", { helperIndex = helperIndex, helperID = helperID })
    end
    -- Возвращаем успешный результат
    return AIO.Handle(player, "hire", "HireResult", {
        success = true,
        helperIndex = helperIndex,
        message = "Фолловер успешно призван"
    })
end

function HireHandlers.DismissHelper(player, helperIndex)
    if PatronLogger then
        PatronLogger:Info("DismissHelper", "Start", "params", { helperIndex = helperIndex })
    end
    if not HELPER_NPC_IDS[helperIndex] then 
        return AIO.Handle(player, "hire", "DismissResult", {
            success = false,
            helperIndex = helperIndex,
            error = "Неверный индекс фолловера"
        })
    end
    
    local fullHelperID = HELPER_NPC_IDS[helperIndex]
    local npc = GetNPCByHelperID(player, fullHelperID)
    
    if not npc then
        return AIO.Handle(player, "hire", "DismissResult", {
            success = false,
            helperIndex = helperIndex,
            error = "Фолловер не найден в мире"
        })
    end
    
    npc:DespawnOrUnsummon()
    if PatronLogger then
        PatronLogger:Info("DismissHelper", "Success", "Helper dismissed", { helperIndex = helperIndex })
    end
    return AIO.Handle(player, "hire", "DismissResult", {
        success = true,
        helperIndex = helperIndex,
        message = "Фолловер отпущен"
    })
end

-- ========== ОБРАБОТЧИК КОМАНД ЧАТА ==========
local function OnPlayerChat(event, player, msg)
    local lowerMsg = string.lower(msg)
    local helperName, orderStr = string.match(lowerMsg, "^(%a+)%s+(.+)$")

    if helperName and orderStr then
        local order = string.gsub(orderStr, "%s+", "")
        local hIndex = helperNameMap[helperName]

        if hIndex then
            local fullHelperID = HELPER_NPC_IDS[hIndex]
            local npc = GetNPCByHelperID(player, fullHelperID)
            if not npc then return true end

            if order == "attack" then
                local targetUnit = player:GetSelection()
                if targetUnit and targetUnit:IsInWorld() then
                    if targetUnit:GetGUID() == player:GetGUID() then
                        player:SendBroadcastMessage(helperName .. " refuses to attack you!")
                        return true
                    end

                    if targetUnit:GetFaction() == player:GetFaction() or targetUnit:GetFaction() == 35 then
                        player:SendBroadcastMessage(helperName .. " refuses to attack a friendly unit!")
                        return true
                    end

                    npc:AttackStart(targetUnit)
                    player:SendBroadcastMessage(helperName .. " is attacking your selected target!")
                else
                    player:SendBroadcastMessage("No target selected!")
                end
            elseif order == "defend" then
                npc:SetReactState(1)
            elseif order == "return" then
                npc:MoveFollow(player, 1.0, 2.0)
            elseif order == "mountup" then
                local mountSpell = mountSpells[fullHelperID]
                if mountSpell then npc:CastSpell(npc, mountSpell, true) end
            end
            return true
        end
    end
    return false
end

-- ========== СОБЫТИЯ ==========
RegisterPlayerEvent(18, OnPlayerChat) -- Чат события
RegisterPlayerEvent(27, function(event, player) SyncHelperMounts(player) end) -- Синхронизация маунтов

-- Запуск боевой логики каждые 2 секунды
CreateLuaEvent(RunDefensiveCombatChecks, 2000, 0)