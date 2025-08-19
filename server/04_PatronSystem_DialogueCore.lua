--[[==========================================================================
  PATRON SYSTEM - DIALOGUE CORE v1.0 (ПОЛНАЯ ВЕРСИЯ)
  Чистая диалоговая логика и навигация
  
  ОТВЕТСТВЕННОСТЬ:
  - Навигация по диалогам
  - Проверка условий доступности
  - Определение действий к выполнению
  - НЕ выполняет сами действия (делегирует в GameLogicCore)
============================================================================]]

-- Проверяем зависимости
if not PatronLogger then
    error("PatronLogger не загружен! Загрузите 01_PatronSystem_Logger.lua")
end

if not PatronDBManager then
    error("PatronDBManager не загружен! Загрузите 03_PatronSystem_DBManager.lua")
end

PatronLogger:Info("DialogueCore", "Initialize", "Loading dialogue core module v1.0")

-- Загружаем диалоговые данные
local dialogues_loaded, DialogueData = pcall(require, "patron_system.data.data_dialogues")
if not dialogues_loaded then
    PatronLogger:Error("DialogueCore", "Initialize", "Failed to load dialogue data", {
        error = tostring(DialogueData)
    })
    error("DialogueData не загружен!")
end

-- Загружаем данные персонажей
local characters_loaded, CharacterData = pcall(require, "patron_system.data.data_characters")  
if not characters_loaded then
    PatronLogger:Error("DialogueCore", "Initialize", "Failed to load character data", {
        error = tostring(CharacterData)
    })
    error("CharacterData не загружен!")
end

-- Создаем модуль
PatronDialogueCore = PatronDialogueCore or {}

--[[==========================================================================
  КОНФИГУРАЦИЯ МОДУЛЯ
============================================================================]]

local DIALOGUE_CONFIG = {
    CACHE_ENABLED = true,               -- Кэшировать загруженные узлы
    VALIDATE_STRUCTURE = true,          -- Валидировать структуру диалогов
    LOG_NAVIGATION = true,              -- Логировать навигацию
    LOG_CONDITIONS = true               -- Логировать проверку условий
}

-- Кэш диалоговых узлов
local nodeCache = {}
local cacheStats = {
    hits = 0,
    misses = 0
}

--[[==========================================================================
  ТОЧКИ ВХОДА В ДИАЛОГОВУЮ СИСТЕМУ
============================================================================]]

-- Начать диалог с покровителем (первое обращение или возобновление)
function PatronDialogueCore.StartDialogue(player, patronId)
    PatronLogger:Info("DialogueCore", "StartDialogue", "Starting dialogue with patron", {
        player = player:GetName(),
        patron_id = patronId
    })
    
    -- Валидируем параметры
    if not player or not patronId then
        PatronLogger:Error("DialogueCore", "StartDialogue", "Invalid parameters")
        return nil
    end
    
    -- Очищаем кэш для получения свежих данных из БД
    local playerGuid = tostring(player:GetGUID()) 
    PatronLogger:Debug("DialogueCore", "StartDialogue", "Clearing player cache", {
        player_guid = playerGuid
    })
    PatronDBManager.ClearPlayerCache(playerGuid)
    
    -- Загружаем состояние диалога игрока
    local dialogueState = PatronDialogueCore.LoadDialogueState(player, patronId)
    if not dialogueState then
        PatronLogger:Error("DialogueCore", "StartDialogue", "Failed to load dialogue state")
        return nil
    end
    
    local savedNodeId = dialogueState.currentDialogue
    
    -- ИСПРАВЛЕНИЕ: Проверяем, является ли сохраненный узел MajorNode
    local startNodeId = savedNodeId
    if savedNodeId then
        local isMajor = PatronDialogueCore.IsMajorNode(savedNodeId)
        PatronLogger:Debug("DialogueCore", "StartDialogue", "Checking saved node", {
            saved_node = savedNodeId,
            is_major_node = isMajor
        })
        
        if not isMajor then
            PatronLogger:Warning("DialogueCore", "StartDialogue", "Saved node is not MajorNode, resetting", {
                saved_node = savedNodeId,
                is_major = false
            })
            
            -- Ищем последний MajorNode для данного покровителя
            startNodeId = PatronDialogueCore.GetInitialDialogueForPatron(patronId)
            
            PatronLogger:Info("DialogueCore", "StartDialogue", "Reset to initial dialogue", {
                saved_node = savedNodeId,
                start_node = startNodeId,
                reason = "saved_node_not_major"
            })
            
            -- ИСПРАВЛЕНИЕ: Принудительно сохраняем начальный диалог в БД
            local success = PatronDBManager.UpdateJSONField(
                playerGuid, 
                "patrons", 
                {"patrons", tostring(patronId), "currentDialogue"}, 
                startNodeId
            )
            
            if success then
                PatronLogger:Info("DialogueCore", "StartDialogue", "Initial dialogue saved to DB", {
                    patron_id = patronId,
                    start_node = startNodeId
                })
            else
                PatronLogger:Error("DialogueCore", "StartDialogue", "Failed to save initial dialogue to DB")
            end
        else
            PatronLogger:Info("DialogueCore", "StartDialogue", "Continuing from saved MajorNode", {
                saved_node = savedNodeId,
                is_major = true
            })
        end
    else
        PatronLogger:Info("DialogueCore", "StartDialogue", "No saved node, using initial", {
            patron_id = patronId
        })
        startNodeId = PatronDialogueCore.GetInitialDialogueForPatron(patronId)
    end
    
    PatronLogger:Debug("DialogueCore", "StartDialogue", "Dialogue state determined", {
        saved_node = savedNodeId,
        start_node = startNodeId,
        patron_id = patronId,
        relationship_points = dialogueState.relationshipPoints,
        events_count = #dialogueState.events
    })
    
    -- Продолжаем с определенного узла
    return PatronDialogueCore.ContinueDialogue(player, startNodeId)
end

-- Продолжить диалог с определенного узла
function PatronDialogueCore.ContinueDialogue(player, nodeId)
    if DIALOGUE_CONFIG.LOG_NAVIGATION then
        PatronLogger:Debug("DialogueCore", "ContinueDialogue", "Continuing dialogue from node", {
            player = player:GetName(),
            node_id = nodeId
        })
    end
    
    -- Получаем узел диалога
    local dialogueNode = PatronDialogueCore.GetDialogueNode(nodeId)
    if not dialogueNode then
        PatronLogger:Error("DialogueCore", "ContinueDialogue", "Dialogue node not found", {
            node_id = nodeId
        })
        return nil
    end
    
    -- Загружаем прогресс игрока для проверки условий
    local playerGuid = tostring(player:GetGUID())
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not playerProgress then
        PatronLogger:Error("DialogueCore", "ContinueDialogue", "Failed to load player progress")
        return nil
    end
    
    -- Получаем доступные варианты ответов
    local allChoices = PatronDialogueCore.GetAvailableChoices(nodeId, player, playerProgress)
    
    -- ИСПРАВЛЕНИЕ: Отфильтровываем только доступные варианты для клиента
    local availableChoices = {}
    for _, choice in ipairs(allChoices) do
        if choice.available then
            table.insert(availableChoices, choice)
        end
    end
    
    -- Клиент должен сам решать, показывать ли кнопку "Продолжить" на основе hasNextNode
    
    -- НОВОЕ: Определяем портрет персонажа
    local portraitKey = PatronDialogueCore.GetCharacterPortrait(dialogueNode.SpeakerID, dialogueNode.Portrait)
    local characterName = PatronDialogueCore.GetCharacterName(dialogueNode.SpeakerID)
    
    local result = {
        id = nodeId, -- ИСПРАВЛЕНИЕ: клиент ожидает 'id', а не 'nodeId'
        nodeId = nodeId, -- Оставляем для обратной совместимости
        speakerId = dialogueNode.SpeakerID,
        text = dialogueNode.Text,
        answers = availableChoices, -- ИСПРАВЛЕНИЕ: клиент ожидает 'answers', а не 'choices'
        choices = availableChoices, -- Оставляем для обратной совместимости
        isMajorNode = PatronDialogueCore.IsMajorNode(nodeId),
        patronId = PatronDialogueCore.DeterminePatronFromNode(nodeId),
        -- ИСПРАВЛЕНИЕ: Добавляем информацию о следующем узле для кнопки "Продолжить"
        nextNodeId = dialogueNode.NextNodeID,
        hasNextNode = dialogueNode.NextNodeID ~= nil,
        -- НОВОЕ: Передаем информацию о портрете и персонаже
        portrait = portraitKey,
        characterName = characterName
    }
    
    if DIALOGUE_CONFIG.LOG_NAVIGATION then
        PatronLogger:Info("DialogueCore", "ContinueDialogue", "Dialogue prepared", {
            node_id = nodeId,
            speaker_id = dialogueNode.SpeakerID,
            total_choices = #allChoices,
            available_choices = #availableChoices,
            is_major_node = result.isMajorNode
        })
        
        -- Детальное логирование доступных вариантов ответов
        for i, choice in ipairs(availableChoices) do
            PatronLogger:Info("DialogueCore", "ContinueDialogue", "Available answer " .. i, {
                choice_id = choice.id,
                choice_text = choice.text,
                available = choice.available
            })
        end
    end
    
    return result
end

-- Обработать выбор игрока
function PatronDialogueCore.ProcessPlayerChoice(player, choiceNodeId)
    PatronLogger:Info("DialogueCore", "ProcessPlayerChoice", "Processing player choice", {
        player = player:GetName(),
        choice_node_id = choiceNodeId
    })
    
    local playerGuid = tostring(player:GetGUID())
    
    -- Загружаем прогресс игрока
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not playerProgress then
        PatronLogger:Error("DialogueCore", "ProcessPlayerChoice", "Failed to load player progress")
        return {success = false, error = "Failed to load player data"}
    end
    
    -- Валидируем выбор игрока
    if not PatronDialogueCore.ValidatePlayerChoice(player, choiceNodeId, playerProgress) then
        PatronLogger:Warning("DialogueCore", "ProcessPlayerChoice", "Invalid player choice", {
            choice_node_id = choiceNodeId
        })
        return {success = false, error = "Invalid choice"}
    end
    
    -- Получаем узел выбора
    local choiceNode = PatronDialogueCore.GetDialogueNode(choiceNodeId)
    if not choiceNode then
        PatronLogger:Error("DialogueCore", "ProcessPlayerChoice", "Choice node not found")
        return {success = false, error = "Choice not found"}
    end
    
    local result = {
        success = true,
        choiceNodeId = choiceNodeId,
        hasActions = choiceNode.Actions and #choiceNode.Actions > 0 or false,
        hasNextNode = choiceNode.NextNodeID and true or false
    }
    
    -- Если есть действия - подготавливаем их для выполнения (но НЕ выполняем сами)
    if choiceNode.Actions then
        result.actions = choiceNode.Actions
        PatronLogger:Debug("DialogueCore", "ProcessPlayerChoice", "Actions prepared for execution", {
            action_count = #choiceNode.Actions
        })
    end
    
    -- Если есть следующий узел - переходим к нему
    if choiceNode.NextNodeID then
        result.nextDialogue = PatronDialogueCore.ContinueDialogue(player, choiceNode.NextNodeID)
        if DIALOGUE_CONFIG.LOG_NAVIGATION then
            PatronLogger:Debug("DialogueCore", "ProcessPlayerChoice", "Moving to next node", {
                next_node_id = choiceNode.NextNodeID
            })
        end
    else
        -- Диалог завершен
        result.dialogueComplete = true
        PatronLogger:Info("DialogueCore", "ProcessPlayerChoice", "Dialogue completed")
    end
    
    return result
end

--[[==========================================================================
  НАВИГАЦИЯ И ПОЛУЧЕНИЕ ДАННЫХ
============================================================================]]

-- Получить узел диалога с кэшированием
function PatronDialogueCore.GetDialogueNode(nodeId)
    if not nodeId then
        return nil
    end
    
    -- Проверяем кэш
    if DIALOGUE_CONFIG.CACHE_ENABLED and nodeCache[nodeId] then
        cacheStats.hits = cacheStats.hits + 1
        PatronLogger:Verbose("DialogueCore", "GetDialogueNode", "Cache hit", {
            node_id = nodeId
        })
        return nodeCache[nodeId]
    end
    
    -- Загружаем из данных
    local node = DialogueData[nodeId]
    if node then
        cacheStats.misses = cacheStats.misses + 1
        
        -- Валидируем структуру если включено
        if DIALOGUE_CONFIG.VALIDATE_STRUCTURE then
            if not PatronDialogueCore.ValidateNodeStructure(node, nodeId) then
                PatronLogger:Warning("DialogueCore", "GetDialogueNode", "Invalid node structure", {
                    node_id = nodeId
                })
            end
        end
        
        -- Сохраняем в кэш
        if DIALOGUE_CONFIG.CACHE_ENABLED then
            nodeCache[nodeId] = node
        end
        
        PatronLogger:Verbose("DialogueCore", "GetDialogueNode", "Node loaded", {
            node_id = nodeId,
            speaker_id = node.SpeakerID,
            is_player_option = node.IsPlayerOption or false
        })
    else
        PatronLogger:Warning("DialogueCore", "GetDialogueNode", "Node not found", {
            node_id = nodeId
        })
    end
    
    return node
end

-- Получить доступные варианты ответов
function PatronDialogueCore.GetAvailableChoices(nodeId, player, playerProgress)
    local node = PatronDialogueCore.GetDialogueNode(nodeId)
    if not node or not node.AnswerOptions then
        PatronLogger:Debug("DialogueCore", "GetAvailableChoices", "No answer options", {
            node_id = nodeId,
            has_node = node and true or false
        })
        return {}
    end
    
    if DIALOGUE_CONFIG.LOG_NAVIGATION then
        PatronLogger:Debug("DialogueCore", "GetAvailableChoices", "Processing answer options", {
            node_id = nodeId,
            total_options = #node.AnswerOptions
        })
    end
    
    local availableChoices = {}
    
    for i, choiceId in ipairs(node.AnswerOptions) do
        local choiceNode = PatronDialogueCore.GetDialogueNode(choiceId)
        if choiceNode then
            -- Проверяем условия доступности
            local isAvailable = true
            if choiceNode.Conditions then
                isAvailable = PatronDialogueCore.ValidateConditions(choiceNode.Conditions, player, playerProgress)
            end
            
            table.insert(availableChoices, {
                id = choiceId,
                text = choiceNode.Text,
                available = isAvailable,
                hasActions = choiceNode.Actions and #choiceNode.Actions > 0 or false,
                nextNode = choiceNode.NextNodeID
            })
            
            if DIALOGUE_CONFIG.LOG_NAVIGATION then
                PatronLogger:Verbose("DialogueCore", "GetAvailableChoices", "Choice processed", {
                    choice_id = choiceId,
                    available = isAvailable,
                    has_actions = choiceNode.Actions and #choiceNode.Actions > 0 or false
                })
            end
        else
            PatronLogger:Warning("DialogueCore", "GetAvailableChoices", "Choice node not found", {
                choice_id = choiceId
            })
        end
    end
    
    local availableCount = 0
    for _, choice in ipairs(availableChoices) do
        if choice.available then
            availableCount = availableCount + 1
        end
    end
    
    if DIALOGUE_CONFIG.LOG_NAVIGATION then
        PatronLogger:Debug("DialogueCore", "GetAvailableChoices", "Choices processed", {
            total_choices = #availableChoices,
            available_choices = availableCount
        })
    end
    
    return availableChoices
end

-- Получить текущий диалог покровителя
function PatronDialogueCore.GetCurrentDialogue(player, patronId)
    local dialogueState = PatronDialogueCore.LoadDialogueState(player, patronId)
    if dialogueState then
        return dialogueState.currentDialogue
    end
    return nil
end

-- Получить следующий узел в цепочке
function PatronDialogueCore.GetNextNode(currentNodeId)
    local node = PatronDialogueCore.GetDialogueNode(currentNodeId)
    return node and node.NextNodeID
end

--[[==========================================================================
  ВАЛИДАЦИЯ
============================================================================]]

-- Проверить, может ли игрок выбрать данный вариант
function PatronDialogueCore.ValidatePlayerChoice(player, choiceId, playerProgress)
    local choiceNode = PatronDialogueCore.GetDialogueNode(choiceId)
    if not choiceNode then
        PatronLogger:Debug("DialogueCore", "ValidatePlayerChoice", "Choice node not found", {
            choice_id = choiceId
        })
        return false
    end
    
    if not choiceNode.IsPlayerOption then
        PatronLogger:Debug("DialogueCore", "ValidatePlayerChoice", "Not a player option", {
            choice_id = choiceId
        })
        return false
    end
    
    -- Проверяем условия если есть
    if choiceNode.Conditions then
        return PatronDialogueCore.ValidateConditions(choiceNode.Conditions, player, playerProgress)
    end
    
    return true
end

-- Проверить условия доступности
function PatronDialogueCore.ValidateConditions(conditions, player, playerProgress)
    if not conditions or #conditions == 0 then
        return true
    end
    
    if DIALOGUE_CONFIG.LOG_CONDITIONS then
        PatronLogger:Debug("DialogueCore", "ValidateConditions", "Checking conditions", {
            condition_count = #conditions
        })
    end
    
    for i, condition in ipairs(conditions) do
        if not PatronDialogueCore.ValidateSingleCondition(condition, player, playerProgress) then
            if DIALOGUE_CONFIG.LOG_CONDITIONS then
                PatronLogger:Debug("DialogueCore", "ValidateConditions", "Condition failed", {
                    condition_index = i,
                    condition_type = condition.Type
                })
            end
            return false
        end
    end
    
    if DIALOGUE_CONFIG.LOG_CONDITIONS then
        PatronLogger:Debug("DialogueCore", "ValidateConditions", "All conditions passed")
    end
    
    return true
end

-- Проверить одно условие
function PatronDialogueCore.ValidateSingleCondition(condition, player, playerProgress)
    if condition.Type == "HAS_MONEY" then
        return player:GetCoinage() >= condition.Amount
        
    elseif condition.Type == "HAS_SOULS" then
        return (playerProgress.souls or 0) >= condition.Amount
        
    elseif condition.Type == "HAS_SUFFERING" then
        return (playerProgress.suffering or 0) >= condition.Amount
        
    elseif condition.Type == "MIN_LEVEL" then
        return player:GetLevel() >= condition.Level
        
    elseif condition.Type == "HAS_EVENT" then
        local patronData = playerProgress.patrons[tostring(condition.PatronID)]
        if patronData and patronData.events then
            for _, event in ipairs(patronData.events) do
                if event == condition.EventName then
                    return true
                end
            end
        end
        return false
        
    elseif condition.Type == "NOT_HAS_EVENT" then
        local patronData = playerProgress.patrons[tostring(condition.PatronID)]
        if patronData and patronData.events then
            for _, event in ipairs(patronData.events) do
                if event == condition.EventName then
                    return false
                end
            end
        end
        return true
        
    elseif condition.Type == "MIN_RELATIONSHIP" then
        local patronData = playerProgress.patrons[tostring(condition.PatronID)]
        if patronData then
            return (patronData.relationshipPoints or 0) >= condition.Points
        end
        return false
        
    elseif condition.Type == "HAS_BLESSING" then
        return playerProgress.blessings[tostring(condition.BlessingID)] ~= nil
        
    elseif condition.Type == "HAS_FOLLOWER" then
        local followerData = playerProgress.followers[tostring(condition.FollowerID)]
        return followerData and followerData.isDiscovered
        
    else
        PatronLogger:Warning("DialogueCore", "ValidateSingleCondition", "Unknown condition type", {
            condition_type = condition.Type
        })
        return false
    end
end

--[[==========================================================================
  УПРАВЛЕНИЕ СОСТОЯНИЕМ
============================================================================]]

-- Обновить прогресс диалога
function PatronDialogueCore.UpdateDialogueProgress(player, patronId, nodeId)
    local playerGuid = tostring(player:GetGUID())
    
    -- Используем атомарную операцию DBManager для обновления currentDialogue
    local success = PatronDBManager.UpdateJSONField(
        playerGuid, 
        "patrons", 
        {"patrons", tostring(patronId), "currentDialogue"}, 
        nodeId
    )
    
    if success then
        PatronLogger:Info("DialogueCore", "UpdateDialogueProgress", "Dialogue progress updated", {
            player = player:GetName(),
            patron_id = patronId,
            new_node = nodeId
        })
    else
        PatronLogger:Error("DialogueCore", "UpdateDialogueProgress", "Failed to update dialogue progress")
    end
    
    return success
end

-- Сохранить MajorNode (точку восстановления)
function PatronDialogueCore.SaveMajorNode(player, patronId, nodeId)
    if not PatronDialogueCore.IsMajorNode(nodeId) then
        PatronLogger:Warning("DialogueCore", "SaveMajorNode", "Node is not a MajorNode", {
            node_id = nodeId
        })
        return false
    end
    
    local success = PatronDialogueCore.UpdateDialogueProgress(player, patronId, nodeId)
    
    if success then
        PatronLogger:Info("DialogueCore", "SaveMajorNode", "Major node saved", {
            player = player:GetName(),
            patron_id = patronId,
            major_node = nodeId
        })
        
        -- НОВОЕ: Инвалидируем кэш SmallTalk при достижении MajorNode
        if PatronSmallTalkCore then
            local playerGuid = tostring(player:GetGUID())
            PatronSmallTalkCore.InvalidatePlayerCache(playerGuid, patronId)
            
            PatronLogger:Debug("DialogueCore", "SaveMajorNode", "SmallTalk cache invalidated after MajorNode save", {
                player_guid = playerGuid,
                patron_id = patronId,
                major_node = nodeId
            })
        end
    end
    
    return success
end

-- Загрузить состояние диалога игрока
function PatronDialogueCore.LoadDialogueState(player, patronId)
    local playerGuid = tostring(player:GetGUID())
    
    PatronLogger:Debug("DialogueCore", "LoadDialogueState", "Loading dialogue state from DB", {
        player_guid = playerGuid,
        patron_id = patronId
    })
    
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        PatronLogger:Error("DialogueCore", "LoadDialogueState", "Failed to load player progress")
        return nil
    end
    
    local patronData = playerProgress.patrons[tostring(patronId)]
    if not patronData then
        PatronLogger:Warning("DialogueCore", "LoadDialogueState", "Patron data not found", {
            patron_id = patronId
        })
        return nil
    end
    
    -- ОТЛАДКА: Логируем, что именно загружено из БД
    PatronLogger:Debug("DialogueCore", "LoadDialogueState", "Raw patron data from DB", {
        patron_id = patronId,
        current_dialogue = patronData.currentDialogue,
        relationship_points = patronData.relationshipPoints,
        events_count = #(patronData.events or {})
    })
    
    local state = {
        currentDialogue = patronData.currentDialogue,
        relationshipPoints = patronData.relationshipPoints or 0,
        events = patronData.events or {}
    }
    
    PatronLogger:Debug("DialogueCore", "LoadDialogueState", "Dialogue state loaded", {
        patron_id = patronId,
        current_dialogue = state.currentDialogue,
        relationship_points = state.relationshipPoints,
        events_count = #state.events
    })
    
    return state
end

--[[==========================================================================
  ПЕРСОНАЖИ И ПОРТРЕТЫ
============================================================================]]

-- Получить портрет персонажа с эмоцией
function PatronDialogueCore.GetCharacterPortrait(speakerID, emotion)
    if not speakerID then return nil end
    
    -- Получаем данные персонажа из CharacterData
    for characterID, characterData in pairs(CharacterData) do
        if characterID == speakerID then
            if emotion and characterData.Emotions and characterData.Emotions[emotion] then
                return characterData.Emotions[emotion]
            end
            return characterData.DefaultPortrait
        end
    end
    
    -- Fallback для неизвестных персонажей
    PatronLogger:Warning("DialogueCore", "GetCharacterPortrait", "Unknown character ID", {
        speaker_id = speakerID
    })
    return nil
end

-- Получить имя персонажа
function PatronDialogueCore.GetCharacterName(speakerID)
    if not speakerID then return "Неизвестный" end
    if speakerID == 0 then return "Игрок" end
    
    -- Получаем имя из CharacterData
    for characterID, characterData in pairs(CharacterData) do
        if characterID == speakerID then
            return characterData.Name
        end
    end
    
    return "Неизвестный персонаж"
end

-- Проверить, существует ли персонаж
function PatronDialogueCore.CharacterExists(speakerID)
    if speakerID == 0 then return true end -- Игрок всегда существует
    
    for characterID, _ in pairs(CharacterData) do
        if characterID == speakerID then
            return true
        end
    end
    return false
end

--[[==========================================================================
  УТИЛИТЫ
============================================================================]]

-- Определить покровителя по ID узла диалога
function PatronDialogueCore.DeterminePatronFromNode(nodeId)
    if nodeId >= 10000 and nodeId < 20000 then
        return 1  -- Пустота
    elseif nodeId >= 20000 and nodeId < 30000 then
        return 2  -- Дракон Лорд
    elseif nodeId >= 30000 and nodeId < 40000 then
        return 3  -- Элуна
    else
        PatronLogger:Warning("DialogueCore", "DeterminePatronFromNode", "Unknown patron for node", {
            node_id = nodeId
        })
        return nil
    end
end

-- Получить начальный диалог для покровителя
function PatronDialogueCore.GetInitialDialogueForPatron(patronId)
    -- Начальные диалоги покровителей (все MajorNode)
    local initialDialogues = {
        [1] = 10001, -- Пустота
        [2] = 20001, -- Дракон Лорд
        [3] = 30001  -- Элуна
    }
    
    local initialNode = initialDialogues[patronId]
    if not initialNode then
        PatronLogger:Error("DialogueCore", "GetInitialDialogueForPatron", "No initial dialogue for patron", {
            patron_id = patronId
        })
        return nil
    end
    
    PatronLogger:Debug("DialogueCore", "GetInitialDialogueForPatron", "Initial dialogue found", {
        patron_id = patronId,
        initial_node = initialNode
    })
    
    return initialNode
end

-- Проверить, является ли узел MajorNode
function PatronDialogueCore.IsMajorNode(nodeId)
    local node = PatronDialogueCore.GetDialogueNode(nodeId)
    return node and node.MajorNode == true
end

-- Валидировать структуру узла диалога
function PatronDialogueCore.ValidateNodeStructure(node, nodeId)
    if not node.SpeakerID then
        PatronLogger:Warning("DialogueCore", "ValidateNodeStructure", "Missing SpeakerID", {
            node_id = nodeId
        })
        return false
    end
    
    if not node.Text or node.Text == "" then
        PatronLogger:Warning("DialogueCore", "ValidateNodeStructure", "Missing or empty Text", {
            node_id = nodeId
        })
        return false
    end
    
    -- Проверяем логику узла
    if node.IsPlayerOption then
        -- Узел игрока должен иметь NextNodeID или Actions
        if not node.NextNodeID and not node.Actions then
            PatronLogger:Warning("DialogueCore", "ValidateNodeStructure", "Player option without NextNodeID or Actions", {
                node_id = nodeId
            })
            return false
        end
    else
        -- Узел NPC должен иметь AnswerOptions или NextNodeID
        if not node.AnswerOptions and not node.NextNodeID then
            PatronLogger:Warning("DialogueCore", "ValidateNodeStructure", "NPC node without AnswerOptions or NextNodeID", {
                node_id = nodeId
            })
            return false
        end
    end
    
    return true
end

-- Получить статистику диалогов игрока
function PatronDialogueCore.GetDialogueStatistics(player)
    local playerGuid = tostring(player:GetGUID())
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        return nil
    end
    
    local stats = {
        cache_hits = cacheStats.hits,
        cache_misses = cacheStats.misses,
        cache_hit_ratio = cacheStats.hits > 0 and 
            math.floor((cacheStats.hits / (cacheStats.hits + cacheStats.misses)) * 100) or 0,
        patrons = {}
    }
    
    for patronId, patronData in pairs(playerProgress.patrons) do
        stats.patrons[patronId] = {
            current_dialogue = patronData.currentDialogue,
            relationship_points = patronData.relationshipPoints or 0,
            events_count = #(patronData.events or {}),
            is_major_node = PatronDialogueCore.IsMajorNode(patronData.currentDialogue)
        }
    end
    
    return stats
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

-- Подсчитываем общее количество диалогов
local totalNodes = 0
local voidNodes = 0
local dragonNodes = 0
local elunaNodes = 0

for nodeId, _ in pairs(DialogueData) do
    totalNodes = totalNodes + 1
    if nodeId >= 10000 and nodeId < 20000 then
        voidNodes = voidNodes + 1
    elseif nodeId >= 20000 and nodeId < 30000 then
        dragonNodes = dragonNodes + 1
    elseif nodeId >= 30000 and nodeId < 40000 then
        elunaNodes = elunaNodes + 1
    end
end

PatronLogger:Info("DialogueCore", "Initialize", "Dialogue core module loaded successfully", {
    total_dialogue_nodes = totalNodes,
    void_nodes = voidNodes,
    dragon_nodes = dragonNodes,
    eluna_nodes = elunaNodes,
    cache_enabled = DIALOGUE_CONFIG.CACHE_ENABLED,
    validation_enabled = DIALOGUE_CONFIG.VALIDATE_STRUCTURE,
    navigation_logging = DIALOGUE_CONFIG.LOG_NAVIGATION,
    conditions_logging = DIALOGUE_CONFIG.LOG_CONDITIONS
})