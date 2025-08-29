--[[==========================================================================
  PATRON SYSTEM - GAME LOGIC CORE v1.0 (ПОЛНАЯ ВЕРСИЯ)
  Выполнение игровых действий и эффектов
  
  ОТВЕТСТВЕННОСТЬ:
  - Выполнение действий диалогов
  - Изменение ресурсов и состояния игрока
  - Работа с Player API (деньги, ауры)
  - НЕ занимается диалоговой навигацией
============================================================================]]

local AIO = AIO or require("AIO")
local json = json or require("dkjson")

-- Проверяем зависимости
if not PatronLogger then
    error("PatronLogger не загружен! Загрузите 01_PatronSystem_Logger.lua")
end

if not PatronDBManager then
    error("PatronDBManager не загружен! Загрузите 03_PatronSystem_DBManager.lua")
end

PatronLogger:Info("GameLogicCore", "Initialize", "Loading game logic core module v1.0")

-- Создаем модуль
PatronGameLogicCore = PatronGameLogicCore or {}

--[[==========================================================================
  КОНФИГУРАЦИЯ МОДУЛЯ
============================================================================]]

local GAMELOGIC_CONFIG = {
    LOG_ACTIONS = true,                 -- Логировать выполнение действий
    LOG_RESOURCE_CHANGES = true,        -- Логировать изменения ресурсов
    VALIDATE_ACTIONS = true,            -- Валидировать параметры действий
    AUTO_SAVE_CHANGES = true            -- Автоматически сохранять изменения в БД
}

-- Статистика выполнения действий
local actionStats = {
    total_executed = 0,
    successful = 0,
    failed = 0,
    by_type = {}
}

--[[==========================================================================
  ОСНОВНЫЕ МЕТОДЫ ВЫПОЛНЕНИЯ ДЕЙСТВИЙ
============================================================================]]

-- Выполнить все действия диалога
function PatronGameLogicCore.ExecuteDialogueActions(actions, player, playerProgress)
    if not actions or #actions == 0 then
        PatronLogger:Debug("GameLogicCore", "ExecuteDialogueActions", "No actions to execute")
        return {success = true, results = {}}
    end
    
    PatronLogger:Info("GameLogicCore", "ExecuteDialogueActions", "Starting action execution", {
        player = player:GetName(),
        action_count = #actions
    })
    
    local results = {}
    local allSuccessful = true
    
    for i, action in ipairs(actions) do
        actionStats.total_executed = actionStats.total_executed + 1
        
        local result = PatronGameLogicCore.ExecuteSingleAction(action, player, playerProgress)
        table.insert(results, result)
        
        if result.success then
            actionStats.successful = actionStats.successful + 1
        else
            actionStats.failed = actionStats.failed + 1
            allSuccessful = false
            
            PatronLogger:Warning("GameLogicCore", "ExecuteDialogueActions", "Action failed", {
                action_index = i,
                action_type = action.Type,
                error = result.error
            })
            
            -- Останавливаемся на первой неудаче
            break
        end
    end
    
    -- Автоматически сохраняем изменения если все успешно
    if allSuccessful and GAMELOGIC_CONFIG.AUTO_SAVE_CHANGES then
        local playerGuid = tostring(player:GetGUID())
        local saveSuccess = PatronDBManager.SavePlayerProgress(playerGuid, playerProgress)
        
        if not saveSuccess then
            PatronLogger:Error("GameLogicCore", "ExecuteDialogueActions", "Failed to save changes to database")
            return {success = false, error = "Failed to save changes", results = results}
        end
        
        -- НОВОЕ: Инвалидируем кэш SmallTalk при изменении состояния игрока
        if PatronSmallTalkCore then
            -- Инвалидируем кэш для всех покровителей поскольку ресурсы могут влиять на любого из них
            PatronSmallTalkCore.InvalidatePlayerCache(playerGuid)
            
            PatronLogger:Debug("GameLogicCore", "ExecuteDialogueActions", "SmallTalk cache invalidated after player state change", {
                player_guid = playerGuid
            })
        end
    end
    
    PatronLogger:Info("GameLogicCore", "ExecuteDialogueActions", "Action execution completed", {
        total_actions = #actions,
        successful = allSuccessful,
        results_count = #results
    })
    
    return {
        success = allSuccessful,
        results = results,
        actionCount = #actions
    }
end

-- Выполнить одно действие
function PatronGameLogicCore.ExecuteSingleAction(action, player, playerProgress)
    if GAMELOGIC_CONFIG.VALIDATE_ACTIONS then
        if not PatronGameLogicCore.ValidateActionParameters(action) then
            return {success = false, error = "Invalid action parameters", action = action}
        end
    end
    
    local actionType = action.Type
    local result = {success = false, action = action, oldValue = nil, newValue = nil}
    
    -- Обновляем статистику по типам
    if not actionStats.by_type[actionType] then
        actionStats.by_type[actionType] = 0
    end
    actionStats.by_type[actionType] = actionStats.by_type[actionType] + 1
    
    if GAMELOGIC_CONFIG.LOG_ACTIONS then
        PatronLogger:Debug("GameLogicCore", "ExecuteSingleAction", "Executing action", {
            action_type = actionType
        })
    end
    
    -- РЕСУРСЫ
    if actionType == "ADD_SOULS" then
        result = PatronGameLogicCore.ModifyPlayerSouls(player, action.Amount, playerProgress)
        
    elseif actionType == "LOST_SOULS" then
        result = PatronGameLogicCore.ModifyPlayerSouls(player, -action.Amount, playerProgress)
        
    elseif actionType == "ADD_SUFFERING" then
        result = PatronGameLogicCore.ModifyPlayerSuffering(player, action.Amount, playerProgress)
        
    elseif actionType == "LOST_SUFFERING" then
        result = PatronGameLogicCore.ModifyPlayerSuffering(player, -action.Amount, playerProgress)
        
    elseif actionType == "ADD_MONEY" then
        result = PatronGameLogicCore.ModifyPlayerMoney(player, action.Amount)
        
    elseif actionType == "LOST_MONEY" then
        result = PatronGameLogicCore.ModifyPlayerMoney(player, -action.Amount)
        
    -- ПОКРОВИТЕЛИ
    elseif actionType == "ADD_POINTS" then
        result = PatronGameLogicCore.AddPatronPoints(player, action.PatronID, action.Amount, playerProgress)
        
    elseif actionType == "ADD_EVENT" then
        result = PatronGameLogicCore.AddPatronEvent(player, action.PatronID, action.EventName, playerProgress)
        
    elseif actionType == "REMOVE_EVENT" then
        result = PatronGameLogicCore.RemovePatronEvent(player, action.PatronID, action.EventName, playerProgress)
        
    elseif actionType == "SET_MAJOR_NODE" then
        result = PatronGameLogicCore.SetMajorNode(player, action.PatronID, action.NodeID, playerProgress, action.FollowerID)
        
    -- БЛАГОСЛОВЕНИЯ (ПЛЕЙСХОЛДЕРЫ)
    elseif actionType == "UNLOCK_BLESSING" then
        result = PatronGameLogicCore.UnlockBlessing(player, action.BlessingID, playerProgress)
        
    elseif actionType == "REMOVE_BLESSING" then
        result = PatronGameLogicCore.RemoveBlessing(player, action.BlessingID, playerProgress)
        
    -- ПОСЛЕДОВАТЕЛИ (ПЛЕЙСХОЛДЕРЫ)
    elseif actionType == "UNLOCK_FOLLOWER" then
        result = PatronGameLogicCore.UnlockFollower(player, action.FollowerID, playerProgress)
        
    elseif actionType == "ACTIVATE_FOLLOWER" then
        result = PatronGameLogicCore.ActivateFollower(player, action.FollowerID, playerProgress)
        
    elseif actionType == "LEVEL_UP_FOLLOWER" then
        result = PatronGameLogicCore.LevelUpFollower(player, action.FollowerID, playerProgress)
        
    -- АУРЫ И ЭФФЕКТЫ (ПЛЕЙСХОЛДЕРЫ)
    elseif actionType == "APPLY_AURA" then
        result = PatronGameLogicCore.ApplyAura(player, action.AuraSpellID, action.Duration, action.SoundID)
        
    elseif actionType == "REMOVE_AURA" then
        result = PatronGameLogicCore.RemoveAura(player, action.AuraSpellID)
        
    elseif actionType == "PLAY_SOUND" then
        result = PatronGameLogicCore.PlaySoundEffect(player, action.SoundID)
        
    -- ПРЕДМЕТЫ (ПЛЕЙСХОЛДЕРЫ)
    elseif actionType == "ADD_ITEM" then
        result = PatronGameLogicCore.AddItem(player, action.ItemID, action.Amount)
        
    elseif actionType == "REMOVE_ITEM" then
        result = PatronGameLogicCore.RemoveItem(player, action.ItemID, action.Amount)
        
    else
        result = {
            success = false, 
            error = "Unknown action type: " .. tostring(actionType),
            action = action
        }
    end
    
    if GAMELOGIC_CONFIG.LOG_ACTIONS then
        PatronLogger:Info("GameLogicCore", "ExecuteSingleAction", "Action executed", {
            action_type = actionType,
            success = result.success,
            message = result.message or result.error,
            old_value = result.oldValue,
            new_value = result.newValue
        })
    end
    
    return result
end

--[[==========================================================================
  РЕСУРСЫ (ПОЛНАЯ РЕАЛИЗАЦИЯ)
============================================================================]]

-- Изменить количество душ игрока
function PatronGameLogicCore.ModifyPlayerSouls(player, amount, playerProgress)
    local oldValue = playerProgress.souls or 0
    local newValue = math.max(0, oldValue + amount)
    
    playerProgress.souls = newValue
    
    local result = {
        success = true,
        message = (amount > 0 and "Added " or "Removed ") .. math.abs(amount) .. " souls",
        oldValue = oldValue,
        newValue = newValue,
        action = {Type = amount > 0 and "ADD_SOULS" or "LOST_SOULS", Amount = math.abs(amount)}
    }
    
    if GAMELOGIC_CONFIG.LOG_RESOURCE_CHANGES then
        PatronLogger:Info("GameLogicCore", "ModifyPlayerSouls", "Souls modified", {
            player = player:GetName(),
            amount = amount,
            old_value = oldValue,
            new_value = newValue
        })
    end
    
    return result
end

-- Изменить количество страданий игрока
function PatronGameLogicCore.ModifyPlayerSuffering(player, amount, playerProgress)
    local oldValue = playerProgress.suffering or 0
    local newValue = math.max(0, oldValue + amount)
    
    playerProgress.suffering = newValue
    
    local result = {
        success = true,
        message = (amount > 0 and "Added " or "Removed ") .. math.abs(amount) .. " suffering",
        oldValue = oldValue,
        newValue = newValue,
        action = {Type = amount > 0 and "ADD_SUFFERING" or "LOST_SUFFERING", Amount = math.abs(amount)}
    }
    
    if GAMELOGIC_CONFIG.LOG_RESOURCE_CHANGES then
        PatronLogger:Info("GameLogicCore", "ModifyPlayerSuffering", "Suffering modified", {
            player = player:GetName(),
            amount = amount,
            old_value = oldValue,
            new_value = newValue
        })
    end
    
    return result
end

-- Изменить деньги игрока
function PatronGameLogicCore.ModifyPlayerMoney(player, amount)
    local oldValue = player:GetCoinage()
    
    -- Проверяем, хватает ли денег для списания
    if amount < 0 and oldValue < math.abs(amount) then
        return {
            success = false,
            error = "Insufficient money",
            required = math.abs(amount),
            current = oldValue,
            action = {Type = "LOST_MONEY", Amount = math.abs(amount)}
        }
    end
    
    player:ModifyMoney(amount)
    local newValue = player:GetCoinage()
    
    local result = {
        success = true,
        message = (amount > 0 and "Added " or "Removed ") .. math.abs(amount) .. " copper",
        oldValue = oldValue,
        newValue = newValue,
        action = {Type = amount > 0 and "ADD_MONEY" or "LOST_MONEY", Amount = math.abs(amount)}
    }
    
    if GAMELOGIC_CONFIG.LOG_RESOURCE_CHANGES then
        PatronLogger:Info("GameLogicCore", "ModifyPlayerMoney", "Money modified", {
            player = player:GetName(),
            amount = amount,
            old_value = oldValue,
            new_value = newValue
        })
    end
    
    return result
end

-- Получить текущие ресурсы игрока
function PatronGameLogicCore.GetPlayerResources(player)
    local playerGuid = tostring(player:GetGUID())
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        return nil
    end
    
    return {
        souls = playerProgress.souls or 0,
        suffering = playerProgress.suffering or 0,
        money = player:GetCoinage(),
        level = player:GetLevel()
    }
end

--[[==========================================================================
  ПОКРОВИТЕЛИ (ПОЛНАЯ РЕАЛИЗАЦИЯ)
============================================================================]]

-- Добавить очки отношений с покровителем
function PatronGameLogicCore.AddPatronPoints(player, patronId, points, playerProgress)
    local patronKey = tostring(patronId)
    
    if not playerProgress.patrons[patronKey] then
        playerProgress.patrons[patronKey] = {
            relationshipPoints = 0,
            events = {},
            currentDialogue = nil
        }
    end
    
    local oldValue = playerProgress.patrons[patronKey].relationshipPoints or 0
    local newValue = oldValue + points
    
    playerProgress.patrons[patronKey].relationshipPoints = newValue
    
    local result = {
        success = true,
        message = "Added " .. points .. " relationship points with patron " .. patronId,
        oldValue = oldValue,
        newValue = newValue,
        action = {Type = "ADD_POINTS", PatronID = patronId, Amount = points}
    }
    
    PatronLogger:Info("GameLogicCore", "AddPatronPoints", "Relationship points added", {
        player = player:GetName(),
        patron_id = patronId,
        points = points,
        old_value = oldValue,
        new_value = newValue
    })
    
    return result
end

-- Добавить событие к покровителю
function PatronGameLogicCore.AddPatronEvent(player, patronId, eventName, playerProgress)
    local patronKey = tostring(patronId)
    
    if not playerProgress.patrons[patronKey] then
        playerProgress.patrons[patronKey] = {
            relationshipPoints = 0,
            events = {},
            currentDialogue = nil
        }
    end
    
    if not playerProgress.patrons[patronKey].events then
        playerProgress.patrons[patronKey].events = {}
    end
    
    -- Проверяем, что события еще нет
    local events = playerProgress.patrons[patronKey].events
    for _, existingEvent in ipairs(events) do
        if existingEvent == eventName then
            return {
                success = true,
                message = "Event '" .. eventName .. "' already exists for patron " .. patronId,
                action = {Type = "ADD_EVENT", PatronID = patronId, EventName = eventName}
            }
        end
    end
    
    -- Добавляем событие
    table.insert(events, eventName)
    
    local result = {
        success = true,
        message = "Added event '" .. eventName .. "' to patron " .. patronId,
        action = {Type = "ADD_EVENT", PatronID = patronId, EventName = eventName}
    }
    
    PatronLogger:Info("GameLogicCore", "AddPatronEvent", "Event added to patron", {
        player = player:GetName(),
        patron_id = patronId,
        event_name = eventName
    })
    
    return result
end

-- Удалить событие у покровителя
function PatronGameLogicCore.RemovePatronEvent(player, patronId, eventName, playerProgress)
    local patronKey = tostring(patronId)
    
    if not playerProgress.patrons[patronKey] or not playerProgress.patrons[patronKey].events then
        return {
            success = false,
            error = "Patron or events not found",
            action = {Type = "REMOVE_EVENT", PatronID = patronId, EventName = eventName}
        }
    end
    
    local events = playerProgress.patrons[patronKey].events
    local eventRemoved = false
    
    for i = #events, 1, -1 do
        if events[i] == eventName then
            table.remove(events, i)
            eventRemoved = true
            break
        end
    end
    
    local result = {
        success = eventRemoved,
        message = eventRemoved and 
            ("Removed event '" .. eventName .. "' from patron " .. patronId) or
            ("Event '" .. eventName .. "' not found for patron " .. patronId),
        action = {Type = "REMOVE_EVENT", PatronID = patronId, EventName = eventName}
    }
    
    if eventRemoved then
        PatronLogger:Info("GameLogicCore", "RemovePatronEvent", "Event removed from patron", {
            player = player:GetName(),
            patron_id = patronId,
            event_name = eventName
        })
    else
        PatronLogger:Warning("GameLogicCore", "RemovePatronEvent", "Event not found", {
            patron_id = patronId,
            event_name = eventName
        })
    end
    
    return result
end

-- Установить MajorNode для покровителя или последователя
function PatronGameLogicCore.SetMajorNode(player, patronId, nodeId, playerProgress, followerId)
    if patronId then
        local patronKey = tostring(patronId)

        if not playerProgress.patrons[patronKey] then
            playerProgress.patrons[patronKey] = {
                relationshipPoints = 0,
                events = {},
                currentDialogue = nil
            }
        end

        local oldValue = playerProgress.patrons[patronKey].currentDialogue
        playerProgress.patrons[patronKey].currentDialogue = nodeId

        local result = {
            success = true,
            message = "Set major node " .. nodeId .. " for patron " .. patronId,
            oldValue = oldValue,
            newValue = nodeId,
            action = {Type = "SET_MAJOR_NODE", PatronID = patronId, NodeID = nodeId}
        }

        PatronLogger:Info("GameLogicCore", "SetMajorNode", "Major node updated for patron", {
            player = player:GetName(),
            patron_id = patronId,
            old_node = oldValue,
            new_node = nodeId
        })

        return result

    elseif followerId then
        local followerKey = tostring(followerId)

        if not playerProgress.followers[followerKey] then
            playerProgress.followers[followerKey] = {
                isActive = false,
                isDiscovered = false,
                relationshipPoints = 0,
                level = 1,
                events = {},
                currentDialogue = nil
            }
        end

        local oldValue = playerProgress.followers[followerKey].currentDialogue
        playerProgress.followers[followerKey].currentDialogue = nodeId

        local result = {
            success = true,
            message = "Set major node " .. nodeId .. " for follower " .. followerId,
            oldValue = oldValue,
            newValue = nodeId,
            action = {Type = "SET_MAJOR_NODE", FollowerID = followerId, NodeID = nodeId}
        }

        PatronLogger:Info("GameLogicCore", "SetMajorNode", "Major node updated for follower", {
            player = player:GetName(),
            follower_id = followerId,
            old_node = oldValue,
            new_node = nodeId
        })

        return result
    end

    return {success = false, message = "No PatronID or FollowerID provided", action = {Type = "SET_MAJOR_NODE"}}
end

-- Получить ранг отношений по очкам
function PatronGameLogicCore.GetPatronRank(relationshipPoints)
    if relationshipPoints >= 1000 then return 5 end -- Избранный
    if relationshipPoints >= 500 then return 4 end  -- Близкий друг
    if relationshipPoints >= 200 then return 3 end  -- Друг
    if relationshipPoints >= 50 then return 2 end   -- Знакомый
    return 1 -- Незнакомец
end

--[[==========================================================================
  ПЛЕЙСХОЛДЕРЫ - БЛАГОСЛОВЕНИЯ
============================================================================]]

-- ПЛЕЙСХОЛДЕР: Разблокировать благословение
function PatronGameLogicCore.UnlockBlessing(player, blessingId, playerProgress)
    PatronLogger:Info("GameLogicCore", "UnlockBlessing", "PLACEHOLDER: Unlocking blessing", {
        player = player:GetName(),
        blessing_id = blessingId
    })
    
    -- Простая реализация - добавляем в список благословений
    if not playerProgress.blessings then
        playerProgress.blessings = {}
    end
    
    playerProgress.blessings[tostring(blessingId)] = {
        isDiscovered = false,
        isInPanel = false,
        panelSlot = 0
    }
    
    return {
        success = true,
        message = "Blessing " .. blessingId .. " unlocked (PLACEHOLDER)",
        action = {Type = "UNLOCK_BLESSING", BlessingID = blessingId},
        requiresDataReload = true  -- Флаг для обновления кэша на клиенте
    }
end

-- ПЛЕЙСХОЛДЕР: Удалить благословение
function PatronGameLogicCore.RemoveBlessing(player, blessingId, playerProgress)
    PatronLogger:Info("GameLogicCore", "RemoveBlessing", "PLACEHOLDER: Removing blessing", {
        player = player:GetName(),
        blessing_id = blessingId
    })
    
    if playerProgress.blessings then
        playerProgress.blessings[tostring(blessingId)] = nil
    end
    
    return {
        success = true,
        message = "Blessing " .. blessingId .. " removed (PLACEHOLDER)",
        action = {Type = "REMOVE_BLESSING", BlessingID = blessingId}
    }
end

--[[==========================================================================
  СИСТЕМА КУЛДАУНОВ ДЛЯ НЕБОЛЬШИХ СЕРВЕРОВ (LUA КЭШИРОВАНИЕ)
============================================================================]]

-- Получить кулдаун благословения (в секундах, оставшихся)
function PatronGameLogicCore.GetBlessingCooldown(player, blessingId)
    local playerGUID = tostring(player:GetGUIDLow())
    if not PatronGameLogicCore.playerCooldowns[playerGUID] then return 0 end
    
    local lastCastTime = PatronGameLogicCore.playerCooldowns[playerGUID][blessingId] or 0
    local currentTime = os.time()
    local info = PatronGameLogicCore.ServerBlessingsConfig[blessingId]
    
    if not info or not info.cooldown_seconds then return 0 end
    
    local elapsed = currentTime - lastCastTime
    local remaining = info.cooldown_seconds - elapsed
    
    return math.max(0, remaining)
end

-- Установить кулдаун благословения
function PatronGameLogicCore.SetBlessingCooldown(player, blessingId)
    local playerGUID = tostring(player:GetGUIDLow())
    if not PatronGameLogicCore.playerCooldowns[playerGUID] then
        PatronGameLogicCore.playerCooldowns[playerGUID] = {}
    end
    
    PatronGameLogicCore.playerCooldowns[playerGUID][blessingId] = os.time()
    
    PatronLogger:Debug("GameLogicCore", "SetBlessingCooldown", "Cooldown set", {
        player = player:GetName(),
        blessing_id = blessingId,
        cooldown_seconds = PatronGameLogicCore.ServerBlessingsConfig[blessingId] and PatronGameLogicCore.ServerBlessingsConfig[blessingId].cooldown_seconds or "unknown"
    })
end

-- Очистить кулдаун благословения (для админских команд)
function PatronGameLogicCore.ClearBlessingCooldown(player, blessingId)
    local playerGUID = tostring(player:GetGUIDLow())
    if PatronGameLogicCore.playerCooldowns[playerGUID] then
        PatronGameLogicCore.playerCooldowns[playerGUID][blessingId] = nil
        PatronLogger:Info("GameLogicCore", "ClearBlessingCooldown", "Cooldown cleared", {
            player = player:GetName(),
            blessing_id = blessingId
        })
        return true
    end
    return false
end

-- Очистить все кулдауны игрока (при выходе/входе)
function PatronGameLogicCore.ClearAllPlayerCooldowns(player)
    local playerGUID = tostring(player:GetGUIDLow())
    PatronGameLogicCore.playerCooldowns[playerGUID] = nil
    PatronLogger:Info("GameLogicCore", "ClearAllPlayerCooldowns", "All cooldowns cleared", {
        player = player:GetName()
    })
end

-- Получить все активные кулдауны игрока
function PatronGameLogicCore.GetAllPlayerCooldowns(player)
    local playerGUID = tostring(player:GetGUIDLow())
    if not PatronGameLogicCore.playerCooldowns[playerGUID] then return {} end
    
    local activeCooldowns = {}
    local currentTime = os.time()
    
    for blessingId, lastCastTime in pairs(PatronGameLogicCore.playerCooldowns[playerGUID]) do
        local info = PatronGameLogicCore.ServerBlessingsConfig[blessingId]
        if info and info.cooldown_seconds then
            local elapsed = currentTime - lastCastTime
            local remaining = info.cooldown_seconds - elapsed
            
            if remaining > 0 then
                activeCooldowns[blessingId] = {
                    remaining = remaining,
                    total = info.cooldown_seconds,
                    name = info.name
                }
            end
        end
    end
    
    return activeCooldowns
end

-- Проверить, можно ли использовать благословение
function PatronGameLogicCore.CanUseBlessing(player, blessingId)
    PatronLogger:Debug("GameLogicCore", "CanUseBlessing", "Checking blessing usage", {
        player = player:GetName(),
        blessing_id = blessingId
    })
    
    local remaining = PatronGameLogicCore.GetBlessingCooldown(player, blessingId)
    return remaining <= 0
end

-- Применить эффект благословения
function PatronGameLogicCore.ApplyBlessingEffect(player, finalSpellTarget, info)
    PatronLogger:Info("GameLogicCore", "ApplyBlessingEffect", "Applying blessing effect", {
        player = player:GetName(),
        target = finalSpellTarget:GetName(),
        blessing_name = info.name,
        is_aoe = info.is_aoe,
        is_offensive = info.is_offensive
    })
    
    local blessingID = info.blessing_id
    local playerGUID = player:GetGUIDLow()
    
    -- Применяем эффект в зависимости от типа благословения
    if info.is_aoe then
        -- Используем стабильную StartGroundAoE
        StartGroundAoE(player, finalSpellTarget, info)
    elseif info.is_offensive then
        -- Динамический расчет урона для single атаки
        local singleDamage = PatronCalc_SingleBudget(player, info)
        local bp0, bp1, bp2 = build_bp_triplet(info, singleDamage)
        local tickId = info.spell_tick_id or info.spell_id
        if tickId and tickId > 0 then
            pcall(player.CastCustomSpell, player, finalSpellTarget, tickId, true, bp0, bp1, bp2)
            PatronLogger:Debug("GameLogicCore", "ApplyBlessingEffect", "Single attack applied", {
                damage = singleDamage,
                spell_id = tickId
            })
        end
    else
        -- Баффы
        DoBuff(player, finalSpellTarget, info)
    end

    -- Устанавливаем кулдаун через новую систему
    PatronGameLogicCore.SetBlessingCooldown(player, blessingID)
    
    PatronLogger:Info("GameLogicCore", "ApplyBlessingEffect", "Blessing effect applied successfully", {
        blessing_id = blessingID,
        player = player:GetName(),
        cooldown_seconds = info.cooldown_seconds
    })
    
    return {success = true, message = "Blessing applied successfully"}
end

--[[==========================================================================
  МЕХАНИКА - БЛЕССИНГИ
============================================================================]]

local EQUIPMENT_SLOT_MAINHAND = 15   -- Eluna Player:GetEquippedItemBySlot(15) → Item  (slot 15 = main-hand). :contentReference[oaicite:6]{index=6}
local AP_PER_DPS = 3.5               -- Retail 6.0.2+: 1 DPS на 3.5 AP. :contentReference[oaicite:7]{index=7}
local PET_INHERIT = 0.70             -- 70% силы владельца для петов (требование ТЗ)
local AOE_CAP_DEFAULT = 8            -- мягкий кап целей
local VARIANCE_PCT = 0.25            -- ±25% дисперсия

function clamp(x, lo, hi) return (x<lo and lo) or (x>hi and hi) or x end
function rand_pm(x) return 1 + (math.random(-x, x) * 0.01) end
function rand_pm25() return rand_pm(25) end

function DoBuff(caster, target, info)
  local sid = tonumber(info.spell_id or 0) or 0
  if sid <= 0 then return end
  if target:HasAura(sid) then return end

  local ok, auraObj = pcall(caster.CastCustomSpell, caster, target, sid, true)
  if not ok then
    print("[BlessingUI] AddAura failed for spell "..tostring(sid))
    return
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

-- Загружаем данные благословений из файла данных
local BlessingsData = require("data.data_blessings")

-- Используем загруженные данные как конфигурацию сервера
PatronGameLogicCore.ServerBlessingsConfig = BlessingsData

-- Логируем загруженные благословения
if PatronGameLogicCore.ServerBlessingsConfig then
    local count = 0
    local ids = {}
    for id, data in pairs(PatronGameLogicCore.ServerBlessingsConfig) do
        count = count + 1
        table.insert(ids, tostring(id))
    end
    PatronLogger:Info("GameLogicCore", "Initialize", "ServerBlessingsConfig loaded from data_blessings", {
        blessing_count = count,
        blessing_ids = table.concat(ids, ", ")
    })
else
    PatronLogger:Error("GameLogicCore", "Initialize", "Failed to load ServerBlessingsConfig from data_blessings")
    error("ServerBlessingsConfig не загружен! Проверьте файл data/data_blessings.lua")
end

-- Кэш кулдаунов для игроков (для небольших серверов 10-20 игроков)  
PatronGameLogicCore.playerCooldowns = {}           -- GUID → { [blessingID]=lastCast }

-- ======================= [ BLESSING MECHANICS FUNCTIONS ] =============================

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
          if u and u.IsInWorld and u:IsInWorld() and u:IsAlive()
             and (u:GetDistance(cx, cy, cz) or 1e9) <= radius then
            local ok = pcall(wo.CastCustomSpell, wo, u, spell_tick_id, true, bp0, bp1, bp2)
            if ok then hits = hits + 1 end
          end
        end
      end

      -- отладка
      --print(("[BlessingUI - Server DEBUG] AoE tick pdist=%.1f searchR=%.1f pool=%d valid=%d hits=%d"):format(pdist, searchR, #pool, #validTargets, hits))
      
      if repeatsLeft and repeatsLeft <= 1 then
        print("[BlessingUI - Server DEBUG] AoE finished")
      end
    end

    -- Привязанный к Player таймер (безопаснее, чем глобальный CreateLuaEvent)
    player:RegisterEvent(onTick, tickMs, ticks)
  end
end

--[[==========================================================================
  ПЛЕЙСХОЛДЕРЫ - ПОСЛЕДОВАТЕЛИ
============================================================================]]

-- ПЛЕЙСХОЛДЕР: Разблокировать последователя
function PatronGameLogicCore.UnlockFollower(player, followerId, playerProgress)
    PatronLogger:Info("GameLogicCore", "UnlockFollower", "PLACEHOLDER: Unlocking follower", {
        player = player:GetName(),
        follower_id = followerId
    })
    
    local followerKey = tostring(followerId)
    if not playerProgress.followers[followerKey] then
        playerProgress.followers[followerKey] = {
            isActive = false,
            isDiscovered = false,
            relationshipPoints = 0,
            level = 1,
            events = {}
        }
    end
    
    playerProgress.followers[followerKey].isDiscovered = true
    
    return {
        success = true,
        message = "Follower " .. followerId .. " unlocked (PLACEHOLDER)",
        action = {Type = "UNLOCK_FOLLOWER", FollowerID = followerId}
    }
end

-- ПЛЕЙСХОЛДЕР: Активировать последователя
function PatronGameLogicCore.ActivateFollower(player, followerId, playerProgress)
    PatronLogger:Info("GameLogicCore", "ActivateFollower", "PLACEHOLDER: Activating follower", {
        player = player:GetName(),
        follower_id = followerId
    })
    
    -- TODO: Реализовать логику активации последователя
    
    return {
        success = true,
        message = "Follower " .. followerId .. " activated (PLACEHOLDER)",
        action = {Type = "ACTIVATE_FOLLOWER", FollowerID = followerId}
    }
end

-- ПЛЕЙСХОЛДЕР: Повысить уровень последователя
function PatronGameLogicCore.LevelUpFollower(player, followerId, playerProgress)
    PatronLogger:Info("GameLogicCore", "LevelUpFollower", "PLACEHOLDER: Leveling up follower", {
        player = player:GetName(),
        follower_id = followerId
    })
    
    -- TODO: Реализовать систему уровней последователей
    
    return {
        success = true,
        message = "Follower " .. followerId .. " leveled up (PLACEHOLDER)",
        action = {Type = "LEVEL_UP_FOLLOWER", FollowerID = followerId}
    }
end

--[[==========================================================================
  ПЛЕЙСХОЛДЕРЫ - АУРЫ И ЭФФЕКТЫ
============================================================================]]

-- ПЛЕЙСХОЛДЕР: Применить ауру
function PatronGameLogicCore.ApplyAura(player, spellId, duration, soundId)
    PatronLogger:Info("GameLogicCore", "ApplyAura", "PLACEHOLDER: Applying aura", {
        player = player:GetName(),
        spell_id = spellId,
        duration = duration,
        sound_id = soundId
    })
    
    -- Пытаемся применить ауру через Player API
    local success = false
    if player.AddAura then
        success = player:AddAura(spellId, duration * 1000) -- Преобразуем в миллисекунды
    end
    
    -- Воспроизводим звук если указан
    if soundId and soundId > 0 then
        PatronGameLogicCore.PlaySoundEffect(player, soundId)
    end
    
    return {
        success = success,
        message = success and 
            ("Aura " .. spellId .. " applied for " .. duration .. " seconds") or
            ("Failed to apply aura " .. spellId),
        action = {Type = "APPLY_AURA", AuraSpellID = spellId, Duration = duration, SoundID = soundId}
    }
end

-- ПЛЕЙСХОЛДЕР: Снять ауру
function PatronGameLogicCore.RemoveAura(player, spellId)
    PatronLogger:Info("GameLogicCore", "RemoveAura", "PLACEHOLDER: Removing aura", {
        player = player:GetName(),
        spell_id = spellId
    })
    
    -- TODO: Реализовать снятие ауры через Player API
    
    return {
        success = true,
        message = "Aura " .. spellId .. " removed (PLACEHOLDER)",
        action = {Type = "REMOVE_AURA", AuraSpellID = spellId}
    }
end

-- Воспроизвести звуковой эффект
function PatronGameLogicCore.PlaySoundEffect(player, soundId)
    PatronLogger:Debug("GameLogicCore", "PlaySoundEffect", "Playing sound effect", {
        player = player:GetName(),
        sound_id = soundId
    })
    
    local success = false
    local message = ""
    
    if not soundId or soundId <= 0 then
        message = "Invalid sound ID: " .. tostring(soundId)
        PatronLogger:Warning("GameLogicCore", "PlaySoundEffect", message)
    else
        -- Используем WorldObject:PlayDirectSound для проигрывания звука игроку
        pcall(function()
            player:PlayDirectSound(soundId, player)
            success = true
            message = "Sound " .. soundId .. " played successfully"
            PatronLogger:Debug("GameLogicCore", "PlaySoundEffect", "Sound played successfully", {
                sound_id = soundId
            })
        end)
        
        if not success then
            message = "Failed to play sound " .. soundId
            PatronLogger:Warning("GameLogicCore", "PlaySoundEffect", message)
        end
    end
    
    return {
        success = success,
        message = message,
        action = {Type = "PLAY_SOUND", SoundID = soundId}
    }
end

--[[==========================================================================
  ПЛЕЙСХОЛДЕРЫ - ПРЕДМЕТЫ
============================================================================]]

-- ПЛЕЙСХОЛДЕР: Дать предмет игроку
function PatronGameLogicCore.AddItem(player, itemId, amount)
    PatronLogger:Info("GameLogicCore", "AddItem", "PLACEHOLDER: Adding item", {
        player = player:GetName(),
        item_id = itemId,
        amount = amount
    })
    
    -- TODO: Реализовать добавление предметов через Player API
    
    return {
        success = true,
        message = "Added " .. amount .. " of item " .. itemId .. " (PLACEHOLDER)",
        action = {Type = "ADD_ITEM", ItemID = itemId, Amount = amount}
    }
end

-- ПЛЕЙСХОЛДЕР: Забрать предмет у игрока
function PatronGameLogicCore.RemoveItem(player, itemId, amount)
    PatronLogger:Info("GameLogicCore", "RemoveItem", "PLACEHOLDER: Removing item", {
        player = player:GetName(),
        item_id = itemId,
        amount = amount
    })
    
    -- TODO: Реализовать удаление предметов через Player API
    
    return {
        success = true,
        message = "Removed " .. amount .. " of item " .. itemId .. " (PLACEHOLDER)",
        action = {Type = "REMOVE_ITEM", ItemID = itemId, Amount = amount}
    }
end

-- ПЛЕЙСХОЛДЕР: Проверить наличие предмета
function PatronGameLogicCore.HasItem(player, itemId, amount)
    PatronLogger:Debug("GameLogicCore", "HasItem", "PLACEHOLDER: Checking item", {
        player = player:GetName(),
        item_id = itemId,
        amount = amount
    })
    
    -- TODO: Реализовать проверку предметов через Player API
    return true -- Временно возвращаем true
end

--[[==========================================================================
  ВАЛИДАЦИЯ И УТИЛИТЫ
============================================================================]]

-- Валидировать параметры действия
function PatronGameLogicCore.ValidateActionParameters(action)
    if not action or not action.Type then
        PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Action missing Type")
        return false
    end
    
    -- Проверяем специфичные параметры для каждого типа действия
    if action.Type == "ADD_SOULS" or action.Type == "LOST_SOULS" or 
       action.Type == "ADD_SUFFERING" or action.Type == "LOST_SUFFERING" or
       action.Type == "ADD_MONEY" or action.Type == "LOST_MONEY" then
        if not action.Amount or type(action.Amount) ~= "number" or action.Amount <= 0 then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid Amount parameter", {
                action_type = action.Type,
                amount = action.Amount
            })
            return false
        end
    end
    
    if action.Type == "ADD_POINTS" or action.Type == "ADD_EVENT" or
       action.Type == "REMOVE_EVENT" then
        if not action.PatronID or type(action.PatronID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid PatronID parameter", {
                action_type = action.Type,
                patron_id = action.PatronID
            })
            return false
        end
    end

    if action.Type == "ADD_EVENT" or action.Type == "REMOVE_EVENT" then
        if not action.EventName or type(action.EventName) ~= "string" or action.EventName == "" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid EventName parameter", {
                action_type = action.Type,
                event_name = action.EventName
            })
            return false
        end
    end

    if action.Type == "SET_MAJOR_NODE" then
        if ((not action.PatronID or type(action.PatronID) ~= "number") and
            (not action.FollowerID or type(action.FollowerID) ~= "number")) then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid target for SET_MAJOR_NODE", {
                patron_id = action.PatronID,
                follower_id = action.FollowerID
            })
            return false
        end

        if not action.NodeID or type(action.NodeID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid NodeID parameter", {
                action_type = action.Type,
                node_id = action.NodeID
            })
            return false
        end
    end
    
    if action.Type == "UNLOCK_BLESSING" or action.Type == "REMOVE_BLESSING" then
        if not action.BlessingID or type(action.BlessingID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid BlessingID parameter", {
                action_type = action.Type,
                blessing_id = action.BlessingID
            })
            return false
        end
    end
    
    if action.Type == "UNLOCK_FOLLOWER" or action.Type == "ACTIVATE_FOLLOWER" or action.Type == "LEVEL_UP_FOLLOWER" then
        if not action.FollowerID or type(action.FollowerID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid FollowerID parameter", {
                action_type = action.Type,
                follower_id = action.FollowerID
            })
            return false
        end
    end
    
    if action.Type == "APPLY_AURA" then
        if not action.AuraSpellID or type(action.AuraSpellID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid AuraSpellID parameter", {
                action_type = action.Type,
                aura_spell_id = action.AuraSpellID
            })
            return false
        end
        if not action.Duration or type(action.Duration) ~= "number" or action.Duration <= 0 then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid Duration parameter", {
                action_type = action.Type,
                duration = action.Duration
            })
            return false
        end
    end
    
    if action.Type == "ADD_ITEM" or action.Type == "REMOVE_ITEM" then
        if not action.ItemID or type(action.ItemID) ~= "number" then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid ItemID parameter", {
                action_type = action.Type,
                item_id = action.ItemID
            })
            return false
        end
        if not action.Amount or type(action.Amount) ~= "number" or action.Amount <= 0 then
            PatronLogger:Warning("GameLogicCore", "ValidateActionParameters", "Invalid Amount parameter", {
                action_type = action.Type,
                amount = action.Amount
            })
            return false
        end
    end
    
    return true
end

-- Получить статистику выполнения действий
function PatronGameLogicCore.GetActionStatistics()
    local successRate = actionStats.total_executed > 0 and 
        math.floor((actionStats.successful / actionStats.total_executed) * 100) or 0
    
    return {
        total_executed = actionStats.total_executed,
        successful = actionStats.successful,
        failed = actionStats.failed,
        success_rate = successRate,
        by_type = actionStats.by_type
    }
end

-- ПЛЕЙСХОЛДЕР: Построить безопасные данные покровителя для клиента
function PatronGameLogicCore.BuildSafePatronData(player, patronId, playerProgress)
    PatronLogger:Debug("GameLogicCore", "BuildSafePatronData", "PLACEHOLDER: Building patron data", {
        player = player:GetName(),
        patron_id = patronId
    })
    
    local patronData = playerProgress.patrons[tostring(patronId)]
    if not patronData then
        return {
            patronId = patronId,
            relationshipPoints = 0,
            currentRank = 1,
            events = {},
            currentDialogue = nil
        }
    end
    
    return {
        patronId = patronId,
        relationshipPoints = patronData.relationshipPoints or 0,
        currentRank = PatronGameLogicCore.GetPatronRank(patronData.relationshipPoints or 0),
        events = patronData.events or {},
        currentDialogue = patronData.currentDialogue
    }
end

-- ПЛЕЙСХОЛДЕР: Построить безопасные данные прогресса для клиента
function PatronGameLogicCore.BuildSafeProgressData(player, playerProgress)
    PatronLogger:Debug("GameLogicCore", "BuildSafeProgressData", "PLACEHOLDER: Building progress data", {
        player = player:GetName()
    })
    
    -- TODO: Реализовать построение полных безопасных данных
    return {
        souls = playerProgress.souls or 0,
        suffering = playerProgress.suffering or 0,
        patrons = {},
        followers = {},
        blessings = {}
    }
end

-- Получить все действия определенного типа (утилита для отладки)
function PatronGameLogicCore.GetActionsByType(actionType)
    return actionStats.by_type[actionType] or 0
end

-- Получить игровую статистику
function PatronGameLogicCore.GetGameStatistics(player)
    local resources = PatronGameLogicCore.GetPlayerResources(player)
    local actionStats = PatronGameLogicCore.GetActionStatistics()
    
    return {
        player_name = player:GetName(),
        player_guid = player:GetGUID(),
        resources = resources,
        action_statistics = actionStats,
        module_config = {
            auto_save = GAMELOGIC_CONFIG.AUTO_SAVE_CHANGES,
            validation = GAMELOGIC_CONFIG.VALIDATE_ACTIONS,
            action_logging = GAMELOGIC_CONFIG.LOG_ACTIONS,
            resource_logging = GAMELOGIC_CONFIG.LOG_RESOURCE_CHANGES
        }
    }
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

PatronLogger:Info("GameLogicCore", "Initialize", "Game logic core module loaded successfully", {
    auto_save_enabled = GAMELOGIC_CONFIG.AUTO_SAVE_CHANGES,
    validation_enabled = GAMELOGIC_CONFIG.VALIDATE_ACTIONS,
    action_logging = GAMELOGIC_CONFIG.LOG_ACTIONS,
    resource_logging = GAMELOGIC_CONFIG.LOG_RESOURCE_CHANGES
})

-- Инициализируем статистику
actionStats.start_time = os.time()

PatronLogger:Info("GameLogicCore", "Initialize", "Supported action types", {
    resource_actions = {"ADD_SOULS", "LOST_SOULS", "ADD_SUFFERING", "LOST_SUFFERING", "ADD_MONEY", "LOST_MONEY"},
    patron_actions = {"ADD_POINTS", "ADD_EVENT", "REMOVE_EVENT"},
    follower_actions = {"UNLOCK_FOLLOWER", "ACTIVATE_FOLLOWER", "LEVEL_UP_FOLLOWER"},
    dialogue_actions = {"SET_MAJOR_NODE"},
    blessing_actions = {"UNLOCK_BLESSING", "REMOVE_BLESSING"},
    effect_actions = {"APPLY_AURA", "REMOVE_AURA", "PLAY_SOUND"},
    item_actions = {"ADD_ITEM", "REMOVE_ITEM"}
})