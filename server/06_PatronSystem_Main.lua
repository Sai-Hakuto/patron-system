--[[==========================================================================
  PATRON SYSTEM - MAIN AIO SERVER HANDLER v2.0
  Модернизированный серверный AIO обработчик для системы покровителей
  
  ОТВЕТСТВЕННОСТЬ:
  - Обработка всех AIO запросов от клиента
  - Координация между модулями (DialogueCore, GameLogicCore, DBManager)
  - Отправка ответов клиенту через AIO
  - Централизованная обработка ошибок и логирование
============================================================================]]

-- Проверяем зависимости
if not PatronLogger then
    error("PatronLogger не загружен! Загрузите 01_PatronSystem_Logger.lua")
end

if not PatronDBManager then
    error("PatronDBManager не загружен! Загрузите 03_PatronSystem_DBManager.lua")
end

if not PatronDialogueCore then
    error("PatronDialogueCore не загружен! Загрузите 04_PatronSystem_DialogueCore.lua")
end

if not PatronGameLogicCore then
    error("PatronGameLogicCore не загружен! Загрузите 05_PatronSystem_GameLogicCore.lua")
end

if not PatronSmallTalkCore then
    error("PatronSmallTalkCore не загружен! Загрузите 04A_PatronSystem_SmallTalkCore.lua")
end

PatronLogger:Info("MainAIO", "Initialize", "Loading main AIO handler v2.0")

-- Логируем состояние всех зависимостей
PatronLogger:Info("MainAIO", "Initialize", "Dependency check", {
    logger_loaded = PatronLogger ~= nil,
    db_manager_loaded = PatronDBManager ~= nil, 
    dialogue_core_loaded = PatronDialogueCore ~= nil,
    game_logic_core_loaded = PatronGameLogicCore ~= nil,
    smalltalk_core_loaded = PatronSmallTalkCore ~= nil
})

-- Загружаем AIO и устанавливаем префикс
local AIO = AIO or require("AIO")
local ADDON_PREFIX = "PatronSystem"

-- Загружаем данные покровителей и последователей
PatronLogger:Info("MainAIO", "Initialize", "Loading patrons data...")
local patronsData_loaded, PatronsData = pcall(require, "data.data_patrons_followers")
if not patronsData_loaded then
    PatronLogger:Error("MainAIO", "Initialize", "Failed to load patrons data", {
        error = tostring(PatronsData)
    })
    error("PatronsData не загружен! Проверьте файл data/data_patrons_followers.lua")
end
PatronLogger:Info("MainAIO", "Initialize", "Patrons data loaded successfully")

-- Загружаем данные smalltalk фраз
PatronLogger:Info("MainAIO", "Initialize", "Loading smalltalks data...")
local smalltalks_loaded, SmallTalksData = pcall(require, "data.data_smalltalks")
if not smalltalks_loaded then
    PatronLogger:Error("MainAIO", "Initialize", "Failed to load smalltalks data", {
        error = tostring(SmallTalksData)
    })
    error("SmallTalksData не загружен! Проверьте файл data/data_smalltalks.lua")
end
PatronLogger:Info("MainAIO", "Initialize", "SmallTalks data loaded successfully")

PatronLogger:Info("MainAIO", "Initialize", "Data files loaded successfully", {
    patrons_count = PatronsData.Patrons and #PatronsData.Patrons or 0,
    followers_count = PatronsData.Followers and #PatronsData.Followers or 0,
    smalltalks_loaded = SmallTalksData and true or false
})

-- Создаем модуль
PatronAIOMain = PatronAIOMain or {}

--[[==========================================================================
  КОНФИГУРАЦИЯ МОДУЛЯ
============================================================================]]

local AIO_CONFIG = {
    LOG_ALL_REQUESTS = true,        -- Логировать все входящие запросы
    LOG_RESPONSES = true,           -- Логировать все исходящие ответы
    VALIDATE_PLAYERS = true,        -- Проверять валидность игроков
    ERROR_RECOVERY = true           -- Пытаться восстановиться после ошибок
}

-- Статистика AIO операций
local aioStats = {
    totalRequests = 0,
    successfulRequests = 0,
    failedRequests = 0,
    requestTypes = {}
}

--[[==========================================================================
  FORWARD DECLARATIONS
============================================================================]]

-- Forward declarations для взаимно зависимых функций
local HandlePlayerChoice

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]

-- Валидация игрока
local function ValidatePlayer(player)
    if not player then
        PatronLogger:Error("MainAIO", "ValidatePlayer", "Player object is nil")
        return false
    end
    
    if not player:IsInWorld() then
        PatronLogger:Warning("MainAIO", "ValidatePlayer", "Player is not in world", {
            player = player:GetName()
        })
        return false
    end
    
    return true
end

-- Обновление статистики запросов
local function UpdateRequestStats(requestType, success)
    aioStats.totalRequests = aioStats.totalRequests + 1
    
    if success then
        aioStats.successfulRequests = aioStats.successfulRequests + 1
    else
        aioStats.failedRequests = aioStats.failedRequests + 1
    end
    
    if not aioStats.requestTypes[requestType] then
        aioStats.requestTypes[requestType] = 0
    end
    aioStats.requestTypes[requestType] = aioStats.requestTypes[requestType] + 1
end

-- Унифицированный снэпшот прогресса для клиента
local function BuildProgressSnapshot(playerGuid, playerProgress)
    -- при необходимости сбрасываем кэш и читаем свежие данные
    if not playerProgress then
        PatronDBManager.ClearPlayerCache(playerGuid)
        playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    end

    local function toBool(v)
        if v == true or v == 1 or v == "1" or v == "true" then return true end
        return false
    end

    local snapshot = {
        souls = (playerProgress and playerProgress.souls) or 0,
        suffering = (playerProgress and playerProgress.suffering) or 0,
        patrons = {},
        followers = {},
        blessings = {}
    }

    -- patrons: только безопасные ключевые поля
    if playerProgress and type(playerProgress.patrons) == "table" then
        for pid, p in pairs(playerProgress.patrons) do
            local key = tostring(pid)
            local rp = 0
            local cur = nil
            if type(p) == "table" then
                rp  = tonumber(p.relationshipPoints) or 0
                cur = tonumber(p.currentDialogue) or nil
            end
            snapshot.patrons[key] = {
                relationshipPoints = rp,
                currentDialogue = cur
            }
        end
    end

    -- followers: важные флаги открытия/активации
    if playerProgress and type(playerProgress.followers) == "table" then
        for fid, f in pairs(playerProgress.followers) do
            local key = tostring(fid)
            local isD, isA = false, false
            if type(f) == "table" then
                isD = toBool(f.isDiscovered)
                isA = toBool(f.isActive)
            end
            snapshot.followers[key] = {
                isDiscovered = isD,
                isActive = isA
            }
        end
    end

    -- blessings: как есть (если структура уже безопасна для клиента)
    if playerProgress and type(playerProgress.blessings) == "table" then
        snapshot.blessings = playerProgress.blessings
    end

    return snapshot
end


-- Безопасная отправка ответа клиенту
local function SafeSendResponse(player, responseType, data)
    if not ValidatePlayer(player) then
        return false
    end
    
    local success, err = pcall(function()
        AIO.Handle(player, ADDON_PREFIX, responseType, data)
    end)
    
    if success then
        if AIO_CONFIG.LOG_RESPONSES then
            PatronLogger:AIO("MainAIO", "SafeSendResponse", "Response sent: " .. responseType, {
                player = player:GetName(),
                response_type = responseType
            })
        end
        return true
    else
        PatronLogger:Error("MainAIO", "SafeSendResponse", "Failed to send response", {
            player = player:GetName(),
            response_type = responseType,
            error = tostring(err)
        })
        return false
    end
end

-- Обработчик ошибок для всех AIO запросов
local function HandleAIOError(requestType, player, err)
    PatronLogger:Error("MainAIO", "HandleAIOError", "AIO request failed", {
        request_type = requestType,
        player = player and player:GetName() or "UNKNOWN",
        error = tostring(err)
    })
    
    if AIO_CONFIG.ERROR_RECOVERY and player then
        SafeSendResponse(player, "Error", {
            message = "Произошла ошибка на сервере. Пожалуйста, повторите попытку.",
            requestType = requestType
        })
    end
end

--[[==========================================================================
  ОСНОВНЫЕ ОБРАБОТЧИКИ ДАННЫХ
============================================================================]]

-- Получение данных покровителя
local function HandleRequestPatronData(player, patronId)
    PatronLogger:Info("MainAIO", "HandleRequestPatronData", "Processing patron data request", {
        player = player:GetName(),
        patron_id = patronId
    })
    
    -- Валидация patronId
    if not patronId or type(patronId) ~= "number" then
        PatronLogger:Warning("MainAIO", "HandleRequestPatronData", "Invalid patronId type", {
            patron_id = patronId,
            patron_type = type(patronId)
        })
        SafeSendResponse(player, "Error", {
            message = "Неверный тип ID покровителя"
        })
        return false
    end
    
    -- Проверяем, есть ли такой покровитель в данных
    local patronInfo = PatronsData.Patrons[patronId]
    if not patronInfo then
        PatronLogger:Warning("MainAIO", "HandleRequestPatronData", "Patron not found in data", {
            patron_id = patronId
        })
        SafeSendResponse(player, "Error", {
            message = "Покровитель не найден"
        })
        return false
    end
    
    -- Загружаем прогресс игрока из БД
    local playerGuid = tostring(player:GetGUID())
    
    -- Очищаем кэш для получения свежих данных из БД
    PatronDBManager.ClearPlayerCache(playerGuid)
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        PatronLogger:Error("MainAIO", "HandleRequestPatronData", "Failed to load player progress")
        SafeSendResponse(player, "Error", {
            message = "Не удалось загрузить данные игрока"
        })
        return false
    end
    
    -- Строим безопасные данные покровителя для клиента
    local safePatronData = PatronGameLogicCore.BuildSafePatronData(player, patronId, playerProgress)
    
    -- Добавляем информацию о покровителе из загруженных данных
    safePatronData.PatronID = patronInfo.PatronID
    safePatronData.Name = patronInfo.Name
    safePatronData.Description = patronInfo.Description
    safePatronData.Alignment = patronInfo.Aligment -- Обратите внимание: в данных опечатка "Aligment"
    safePatronData.NpcEntryID = patronInfo.NpcEntryID
    
    -- НОВОЕ: Используем SmallTalkCore для динамического выбора фраз с учетом условий
    local selectedSmallTalk = PatronSmallTalkCore.SelectRandomSmallTalk(player, patronId)
    safePatronData.smallTalk = selectedSmallTalk
    
    -- НОВОЕ: Добавляем список всех доступных SmallTalk для клиента
    local availableSmallTalks = PatronSmallTalkCore.GetSmallTalkListForClient(player, patronId)
    safePatronData.availableSmallTalks = availableSmallTalks
    
    PatronLogger:Info("MainAIO", "HandleRequestPatronData", "Sending patron data to client", {
        patron_name = safePatronData.Name,
        relationship_points = safePatronData.relationshipPoints,
        small_talk = safePatronData.smallTalk
    })
    
    -- ВАЖНО: Отправляем UpdatePatronData, как ожидает клиент
    SafeSendResponse(player, "UpdatePatronData", safePatronData)
    return true
end

--- Получение данных фолловера
local function HandleRequestFollowerData(player, requestData)
    PatronLogger:Info("MainAIO", "HandleRequestFollowerData", "Processing follower data request", {
        player = player:GetName(),
        request_data = requestData
    })
    
    -- Парсим данные запроса
    local followerId, speakerType
    if type(requestData) == "table" then
        followerId = requestData.speakerID
        speakerType = requestData.speakerType
    else
        followerId = requestData -- fallback для простого числа
        speakerType = "follower"
    end
    
    -- Валидация followerId
    if not followerId or type(followerId) ~= "number" then
        PatronLogger:Warning("MainAIO", "HandleRequestFollowerData", "Invalid followerId type", {
            follower_id = followerId,
            follower_type = type(followerId)
        })
        SafeSendResponse(player, "Error", {
            message = "Неверный тип ID фолловера"
        })
        return false
    end
    
    -- Проверяем, есть ли такой фолловер в данных
    local followerInfo = PatronsData.Followers[followerId]
    if not followerInfo then
        PatronLogger:Warning("MainAIO", "HandleRequestFollowerData", "Follower not found in data", {
            follower_id = followerId
        })
        SafeSendResponse(player, "Error", {
            message = "Фолловер не найден"
        })
        return false
    end
    
    -- Загружаем прогресс игрока из БД
    local playerGuid = tostring(player:GetGUID())
    
    -- Очищаем кэш для получения свежих данных из БД
    PatronDBManager.ClearPlayerCache(playerGuid)
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        PatronLogger:Error("MainAIO", "HandleRequestFollowerData", "Failed to load player progress")
        SafeSendResponse(player, "Error", {
            message = "Не удалось загрузить данные игрока"
        })
        return false
    end
    
    -- ПРОВЕРКА: Открыт ли этот фолловер у игрока?
    local isFollowerUnlocked = false
    if playerProgress.followers and playerProgress.followers[tostring(followerId)] then
        isFollowerUnlocked = true
        PatronLogger:Info("MainAIO", "HandleRequestFollowerData", "Follower is unlocked", {
            follower_id = followerId,
            follower_name = followerInfo.FollowerName
        })
    else
        PatronLogger:Info("MainAIO", "HandleRequestFollowerData", "Follower is locked", {
            follower_id = followerId,
            follower_name = followerInfo.FollowerName
        })
    end
    
    -- Получаем SmallTalk через SmallTalkCore
    local smallTalk = isFollowerUnlocked and PatronSmallTalkCore.SelectRandomSmallTalk(player, followerId) or "Этот фолловер пока не открыт."
    local availableSmallTalks = isFollowerUnlocked and PatronSmallTalkCore.GetSmallTalkListForClient(player, followerId) or {}
    
    -- Строим данные фолловера для клиента
    local safeFollowerData = {
        SpeakerID = followerId,
        SpeakerType = "follower",
        Name = followerInfo.FollowerName,
        PatronID = followerInfo.PatronID, -- К какому покровителю привязан
        Alignment = followerInfo.Aligment, -- используем орфографию из исходных данных
        Description = followerInfo.Description,
        NpcEntryID = followerInfo.NpcEntryID,

        -- Статус доступности
        isUnlocked = isFollowerUnlocked,

        -- Базовые данные для совместимости с системой диалогов
        relationshipPoints = 0,
        smallTalk = smallTalk,
        availableSmallTalks = availableSmallTalks
    }
    
    -- Если фолловер заблокирован, отправляем ограниченные данные
    if not isFollowerUnlocked then
        safeFollowerData.smallTalk = "Вы еще не открыли этого фолловера. Развивайте отношения с покровителями для получения новых союзников."
        safeFollowerData.Name = "???"  -- Скрываем имя
        safeFollowerData.Description = "Заблокированный фолловер"
        safeFollowerData.availableSmallTalks = {}
    end
    
    PatronLogger:Info("MainAIO", "HandleRequestFollowerData", "Sending follower data to client", {
        follower_name = safeFollowerData.Name,
        is_unlocked = isFollowerUnlocked
    })
    
    -- ВАЖНО: Отправляем UpdateSpeakerData, как ожидает клиент
    SafeSendResponse(player, "UpdateSpeakerData", safeFollowerData)
    return true
end

-- Инициализация нового игрока
local function HandleRequestPlayerInit(player)
    PatronLogger:Info("MainAIO", "HandleRequestPlayerInit", "Processing player initialization", {
        player = player and player:GetName() or "unknown"
    })

    if not ValidatePlayer(player) then
        SafeSendResponse(player, "Error", { message = "Игрок недействителен" })
        return false
    end

    local playerGuid = tostring(player:GetGUID())
    local playerExists = PatronDBManager.PlayerExists(playerGuid)
    local isNewPlayer = not playerExists

    local initData = {
        isNewPlayer = isNewPlayer,
        message = isNewPlayer and "Добро пожаловать в Систему Покровителей!" or "Данные загружены успешно"
    }

    -- Если новый игрок — создаём базовые данные
    if isNewPlayer then
        local newPlayerData = {
            souls = 0,
            suffering = 0,
            patrons = {
                ["1"] = { relationshipPoints = 0, events = {}, currentDialogue = 10001 }, -- Пустота
                ["2"] = { relationshipPoints = 0, events = {}, currentDialogue = 20001 }, -- Дракон Лорд
                ["3"] = { relationshipPoints = 0, events = {}, currentDialogue = 30001 }  -- Элуна
            },
            followers = {},
            blessings = {}
        }

        local created = PatronDBManager.SavePlayerProgress(playerGuid, newPlayerData)
        if not created then
            PatronLogger:Error("MainAIO", "HandleRequestPlayerInit", "Failed to create new player data", {
                player_guid = playerGuid
            })
            initData.error = true
            initData.message = "Ошибка создания данных игрока"
            -- даже при ошибке попробуем отдать пустой прогресс ниже
        end
    end

    -- Загружаем свежий прогресс и строим единый снэпшот
    PatronDBManager.ClearPlayerCache(playerGuid)
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not playerProgress then
        PatronLogger:Error("MainAIO", "HandleRequestPlayerInit", "Failed to load player progress", {
            player_guid = playerGuid
        })
        initData.error = true
        initData.message = initData.message or "Не удалось загрузить данные игрока"
        initData.progressData = {
            souls = 0, suffering = 0, patrons = {}, followers = {}, blessings = {}
        }
    else
        initData.progressData = BuildProgressSnapshot(playerGuid, playerProgress)
    end

    SafeSendResponse(player, "PlayerInitialized", initData)
    return true
end


--[[==========================================================================
  ОБРАБОТЧИКИ ДИАЛОГОВ
============================================================================]]

-- Начало диалога с покровителем
local function HandleStartDialogue(player, patronId)
    PatronLogger:Info("MainAIO", "HandleStartDialogue", "Starting dialogue with patron", {
        player = player:GetName(),
        patron_id = patronId
    })
    
    local dialogueData = PatronDialogueCore.StartDialogue(player, patronId)
    if not dialogueData then
        PatronLogger:Error("MainAIO", "HandleStartDialogue", "Failed to start dialogue")
        SafeSendResponse(player, "Error", {
            message = "Не удалось начать диалог с покровителем"
        })
        return false
    end
    
    SafeSendResponse(player, "UpdateDialogue", dialogueData)
    return true
end

-- Продолжение диалога (умная логика)
local function HandleContinueDialogue(player, nodeId)
    -- ИСПРАВЛЕНИЕ: Проверяем тип nodeId - клиент иногда отправляет таблицы
    if type(nodeId) == "table" then
        -- Логируем содержимое таблицы для отладки
        local tableContent = {}
        for k, v in pairs(nodeId) do
            local key = tostring(k)
            local value = tostring(v)
            -- Ограничиваем длину значений для читаемости
            if string.len(value) > 50 then
                value = string.sub(value, 1, 50) .. "..."
            end
            tableContent[key] = value
        end
        
        PatronLogger:Warning("MainAIO", "HandleContinueDialogue", "Received table instead of nodeId", {
            player = player:GetName(),
            table_content = tableContent
        })
        
        -- Пытаемся извлечь ID из таблицы разными способами
        local extractedId = nil
        if nodeId.id then
            extractedId = nodeId.id
        elseif nodeId.nodeId then  
            extractedId = nodeId.nodeId
        elseif nodeId.nodeID then
            extractedId = nodeId.nodeID  
        elseif nodeId[1] then -- Может быть массив
            extractedId = nodeId[1]
        else
            -- Пробуем найти числовое значение в таблице
            for k, v in pairs(nodeId) do
                if type(v) == "number" and v > 10000 and v < 40000 then
                    extractedId = v
                    PatronLogger:Info("MainAIO", "HandleContinueDialogue", "Found nodeId by scanning table", {
                        key = k,
                        value = v
                    })
                    break
                end
            end
        end
        
        if extractedId then
            nodeId = extractedId
            PatronLogger:Info("MainAIO", "HandleContinueDialogue", "Successfully extracted nodeId", {
                extracted_id = nodeId
            })
        else
            PatronLogger:Error("MainAIO", "HandleContinueDialogue", "Cannot extract nodeId from table", {
                table_content = tableContent
            })
            SafeSendResponse(player, "Error", {
                message = "Неверный формат данных диалога"
            })
            return false
        end
    end
    
    -- Приводим к числу
    nodeId = tonumber(nodeId)
    if not nodeId then
        PatronLogger:Error("MainAIO", "HandleContinueDialogue", "Invalid nodeId - not a number")
        SafeSendResponse(player, "Error", {
            message = "Неверный ID узла диалога"
        })
        return false
    end
    
    PatronLogger:Info("MainAIO", "HandleContinueDialogue", "Continuing dialogue", {
        player = player:GetName(),
        node_id = nodeId
    })
    
    -- ИСПРАВЛЕНИЕ: Определяем тип узла
    local dialogueNode = PatronDialogueCore.GetDialogueNode(nodeId)
    if not dialogueNode then
        PatronLogger:Error("MainAIO", "HandleContinueDialogue", "Dialogue node not found", {
            node_id = nodeId
        })
        SafeSendResponse(player, "Error", {
            message = "Узел диалога не найден"
        })
        return false
    end
    
    -- ИСПРАВЛЕНИЕ: Если это узел игрока (IsPlayerOption), обрабатываем как выбор
    if dialogueNode.IsPlayerOption then
        PatronLogger:Info("MainAIO", "HandleContinueDialogue", "Node is player choice - processing as choice", {
            node_id = nodeId
        })
        
        -- Перенаправляем на обработчик выбора игрока
        return HandlePlayerChoice(player, nodeId)
    end
    
    -- Если это узел покровителя, обрабатываем логику "Продолжить"
    local currentNode = PatronDialogueCore.GetDialogueNode(nodeId)
    if not currentNode then
        PatronLogger:Error("MainAIO", "HandleContinueDialogue", "Current node not found")
        SafeSendResponse(player, "Error", {
            message = "Узел диалога не найден"
        })
        return false
    end
    
    -- ИСПРАВЛЕНИЕ: Если есть NextNodeID - переходим к нему, иначе показываем текущий
    local targetNodeId = nodeId
    if currentNode.NextNodeID then
        targetNodeId = currentNode.NextNodeID
        PatronLogger:Info("MainAIO", "HandleContinueDialogue", "Advancing to next node", {
            current_node = nodeId,
            next_node = targetNodeId
        })
    else
        PatronLogger:Debug("MainAIO", "HandleContinueDialogue", "No NextNodeID, showing current node", {
            current_node = nodeId
        })
    end
    
    local dialogueData = PatronDialogueCore.ContinueDialogue(player, targetNodeId)
    if not dialogueData then
        PatronLogger:Warning("MainAIO", "HandleContinueDialogue", "No dialogue data returned - ending dialogue")
        SafeSendResponse(player, "DialogueEnded", {
            message = "Диалог завершен"
        })
        return true
    end
    
    SafeSendResponse(player, "UpdateDialogue", dialogueData)
    return true
end

-- Обработка выбора игрока  
HandlePlayerChoice = function(player, choiceNodeId)
    PatronLogger:Info("MainAIO", "HandlePlayerChoice", "Processing player choice", {
        player = player:GetName(),
        choice_node_id = choiceNodeId
    })
    
    local choiceResult = PatronDialogueCore.ProcessPlayerChoice(player, choiceNodeId)
    if not choiceResult.success then
        PatronLogger:Error("MainAIO", "HandlePlayerChoice", "Choice processing failed")
        SafeSendResponse(player, "Error", {
            message = choiceResult.error or "Ошибка обработки выбора"
        })
        return false
    end
    
    -- Если есть действия к выполнению
    if choiceResult.hasActions and choiceResult.actions then
        PatronLogger:Info("MainAIO", "HandlePlayerChoice", "Executing dialogue actions", {
            action_count = #choiceResult.actions
        })
        
        local playerGuid = tostring(player:GetGUID())
        local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
        
        local actionResult = PatronGameLogicCore.ExecuteDialogueActions(
            choiceResult.actions, 
            player, 
            playerProgress
        )
        
        SafeSendResponse(player, "ActionsExecuted", {
            success = actionResult.success,
            message = actionResult.success and "Действия выполнены успешно" or actionResult.error,
            results = actionResult.results
        })
        
        -- ИСПРАВЛЕНИЕ: Не возвращаемся сразу, проверяем есть ли следующий диалог
        if not actionResult.success then
            return false
        end
    end
    
    -- Если есть следующий диалог
    if choiceResult.hasNextNode and choiceResult.nextDialogue then
        SafeSendResponse(player, "UpdateDialogue", choiceResult.nextDialogue)
        return true
    end
    
    -- Если диалог завершен
    if choiceResult.dialogueComplete then
        SafeSendResponse(player, "DialogueEnded", {
            message = "Диалог завершен"
        })
        return true
    end
    
    return true
end

--[[==========================================================================
  ОБРАБОТЧИКИ ДЕЙСТВИЙ
============================================================================]]

-- Обработка действий благословений
local function HandleBlessingAction(player, data)
    PatronLogger:Info("MainAIO", "HandleBlessingAction", "Processing blessing action", {
        player = player:GetName(),
        action = data.action,
        blessing_id = data.blessingId
    })
    
    -- TODO: Реализовать полную логику благословений
    local success = true
    local message = "Благословение " .. (data.action == "use" and "использовано" or "активировано") .. " успешно"
    
    SafeSendResponse(player, "BlessingResult", {
        success = success,
        message = message
    })
    
    return success
end

-- Обработка молитв
local function HandlePrayerAction(player, data)
    PatronLogger:Info("MainAIO", "HandlePrayerAction", "Processing prayer action", {
        player = player:GetName(),
        patron_id = data.patronId
    })
    
    -- TODO: Реализовать полную логику молитв
    local success = true
    local message = "Молитва была услышана покровителем"
    
    SafeSendResponse(player, "PrayerResult", {
        success = success,
        message = message
    })
    
    return success
end

-- Оновлення SmallTalk фраз (патрон/фолловер)
local function HandleRefreshSmallTalk(player, data)
    local speakerId = data and data.speakerId
    local speakerType = data and data.speakerType

    PatronLogger:Info("MainAIO", "HandleRefreshSmallTalk", "Refreshing SmallTalk", {
        player = player:GetName(),
        speaker_id = speakerId,
        speaker_type = speakerType
    })

    -- Инвалидируем кэш для получения новых фраз
    local playerGuid = tostring(player:GetGUID())
    PatronSmallTalkCore.InvalidatePlayerCache(playerGuid, speakerId)

    -- Получаем новую фразу и список доступных
    local newSmallTalk = PatronSmallTalkCore.SelectRandomSmallTalk(player, speakerId)
    local availableSmallTalks = PatronSmallTalkCore.GetSmallTalkListForClient(player, speakerId)

    local refreshData = {
        speakerId = speakerId,
        speakerType = speakerType,
        smallTalk = newSmallTalk,
        availableSmallTalks = availableSmallTalks
    }

    SafeSendResponse(player, "SmallTalkRefreshed", refreshData)

    PatronLogger:Info("MainAIO", "HandleRefreshSmallTalk", "SmallTalk refreshed", {
        speaker_id = speakerId,
        speaker_type = speakerType,
        new_smalltalk_preview = string.sub(newSmallTalk, 1, 30) .. "...",
        available_count = #availableSmallTalks
    })

    return true
end

--[[==========================================================================
  РЕГИСТРАЦИЯ AIO ОБРАБОТЧИКОВ
============================================================================]]

-- Создаем безопасную обертку для всех обработчиков
local function CreateSafeHandler(handlerName, handlerFunc)
    return function(player, ...)
        if AIO_CONFIG.LOG_ALL_REQUESTS then
            PatronLogger:AIO("MainAIO", "RequestReceived", "Incoming: " .. handlerName, {
                player = player and player:GetName() or "UNKNOWN"
            })
        end
        
        if AIO_CONFIG.VALIDATE_PLAYERS and not ValidatePlayer(player) then
            UpdateRequestStats(handlerName, false)
            return
        end
        
        local success, result = pcall(handlerFunc, player, ...)
        UpdateRequestStats(handlerName, success)
        
        if not success then
            HandleAIOError(handlerName, player, result)
        end
        
        return result
    end
end

-- Регистрируем все AIO обработчики
PatronLogger:Info("MainAIO", "Initialize", "Registering AIO handlers")

AIO.AddHandlers(ADDON_PREFIX, {
    
    --=== ИНИЦИАЛИЗАЦИЯ И ДАННЫЕ ===--
    RequestPlayerInit = CreateSafeHandler("RequestPlayerInit", HandleRequestPlayerInit),
    RequestPatronData = CreateSafeHandler("RequestPatronData", HandleRequestPatronData),
    RequestSpeakerData = CreateSafeHandler("RequestSpeakerData", HandleRequestFollowerData), -- НОВАЯ ФУНКЦИЯ
    
    --=== ДИАЛОГИ ===--
    StartDialogue = CreateSafeHandler("StartDialogue", HandleStartDialogue),
    RequestInitialDialogue = CreateSafeHandler("RequestInitialDialogue", HandleStartDialogue), -- Алиас
    ContinueDialogue = CreateSafeHandler("ContinueDialogue", HandleContinueDialogue),
    RequestNextDialogue = CreateSafeHandler("RequestNextDialogue", HandleContinueDialogue), -- Алиас
    RequestContinueDialogue = CreateSafeHandler("RequestContinueDialogue", HandleContinueDialogue), -- Алиас
    ProcessChoice = CreateSafeHandler("ProcessChoice", HandlePlayerChoice),
    
    --=== ДЕЙСТВИЯ ===--
    BlessingAction = CreateSafeHandler("BlessingAction", HandleBlessingAction),
    PrayerAction = CreateSafeHandler("PrayerAction", HandlePrayerAction),
    
    --=== SMALLTALK ===--
    RefreshSmallTalk = CreateSafeHandler("RefreshSmallTalk", HandleRefreshSmallTalk),
    
    --=== ТЕСТИРОВАНИЕ И ОТЛАДКА ===--
    TestEvent = CreateSafeHandler("TestEvent", function(player, message)
        PatronLogger:Info("MainAIO", "TestEvent", "Test message received", {
            player = player:GetName(),
            message = tostring(message)
        })
        
        SafeSendResponse(player, "TestResponse", 
            "Сервер получил: " .. tostring(message) .. " от " .. player:GetName())
        
        return true
    end),
    
    --=== СТАТИСТИКА И ДИАГНОСТИКА ===--
    GetStats = CreateSafeHandler("GetStats", function(player)
        local stats = {
            aio_stats = aioStats,
            db_stats = PatronDBManager.GetStats(),
            dialogue_stats = PatronDialogueCore.GetDialogueStatistics(player),
            game_stats = PatronGameLogicCore.GetGameStatistics(player)
        }
        
        SafeSendResponse(player, "StatsResponse", stats)
        return true
    end)
})

--[[==========================================================================
  УТИЛИТЫ И СТАТИСТИКА МОДУЛЯ
============================================================================]]

-- Получить статистику AIO модуля
function PatronAIOMain.GetStats()
    local successRate = aioStats.totalRequests > 0 and 
        math.floor((aioStats.successfulRequests / aioStats.totalRequests) * 100) or 0
    
    return {
        total_requests = aioStats.totalRequests,
        successful_requests = aioStats.successfulRequests,
        failed_requests = aioStats.failedRequests,
        success_rate = successRate,
        request_types = aioStats.requestTypes
    }
end

-- Показать статистику
function PatronAIOMain.ShowStats()
    local stats = PatronAIOMain.GetStats()
    PatronLogger:Info("MainAIO", "ShowStats", "AIO Handler statistics", stats)
end

-- Сброс статистики
function PatronAIOMain.ResetStats()
    aioStats = {
        totalRequests = 0,
        successfulRequests = 0,
        failedRequests = 0,
        requestTypes = {}
    }
    PatronLogger:Info("MainAIO", "ResetStats", "Statistics reset")
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ ЗАВЕРШЕНА
============================================================================]]

PatronLogger:Info("MainAIO", "Initialize", "Main AIO handler loaded successfully", {
    addon_prefix = ADDON_PREFIX,
    handlers_count = 14, -- Количество зарегистрированных обработчиков (добавлен RefreshSmallTalk)
    config = AIO_CONFIG
})

PatronLogger:Info("MainAIO", "Initialize", "Supported AIO requests", {
    data_requests = {"RequestPlayerInit", "RequestPatronData", "RequestSpeakerData"},
    dialogue_requests = {"StartDialogue", "ContinueDialogue", "ProcessChoice"},
    action_requests = {"BlessingAction", "PrayerAction"},
    smalltalk_requests = {"RefreshSmallTalk"},
    utility_requests = {"TestEvent", "GetStats"}
})

print("|cff00ff00[PatronSystem]|r Main AIO Handler v2.0 loaded successfully - Ready to serve clients!")