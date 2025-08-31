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

-- Загружаем данные о благословениях
local BlessingsData = require("data.data_blessings")

-- Логируем загрузку данных о благословениях
if BlessingsData then
    local count = 0
    local ids = {}
    for id, data in pairs(BlessingsData) do
        count = count + 1
        table.insert(ids, tostring(id))
    end
    PatronLogger:Info("MainAIO", "Initialize", "BlessingsData loaded", {
        blessing_count = count,
        blessing_ids = table.concat(ids, ", ")
    })
else
    PatronLogger:Error("MainAIO", "Initialize", "Failed to load BlessingsData")
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

-- Safety configuration and guards (added to prevent runaway recursion and spam)
local SAFETY = {
    ENABLE_REENTRANCY_GUARD = true,
    MAX_NESTED_CALLS = 128,
    COOLDOWNS_MIN_INTERVAL = 0.25, -- seconds
}

-- Global guard to prevent unbounded nested handler invocations
local __currentNestedDepth = 0

-- Per-player rate limit state for noisy requests
local __lastCooldownsRequest = {}

-- Per-player blessing request mutex system
local __playerBlessingBusy = {}    -- [playerGUID] = true/false
local __playerBlessingQueue = {}   -- [playerGUID] = {request1, request2, ...}

-- Per-player purchase request mutex system (защита от дублирования покупок)
local __playerPurchaseBusy = {}    -- [playerGUID] = true/false
local __playerPurchaseQueue = {}   -- [playerGUID] = {request1, request2, ...}

-- Idempotency system - TTL cache для обработанных requestId
local __processedRequests = {}     -- [requestId] = {timestamp, result}
local REQUEST_TTL_SECONDS = 300    -- 5 минут TTL для обработанных запросов

--[[==========================================================================
  FORWARD DECLARATIONS
============================================================================]]

-- Forward declarations для взаимно зависимых функций
local HandlePlayerChoice
local HandleRequestBlessingCore
local HandlePurchaseRequestCore

--[[==========================================================================
  PER-PLAYER BLESSING MUTEX SYSTEM
============================================================================]]

-- Проверить занятость игрока
local function IsPlayerBlessingBusy(playerGUID)
    return __playerBlessingBusy[playerGUID] == true
end

-- Поставить игрока в занятое состояние
local function SetPlayerBlessingBusy(playerGUID, busy)
    __playerBlessingBusy[playerGUID] = busy
    if not busy then
        __playerBlessingBusy[playerGUID] = nil -- очищаем чтобы не засорять память
    end
end

-- Добавить запрос в очередь игрока
local function EnqueueBlessingRequest(playerGUID, player, data)
    if not __playerBlessingQueue[playerGUID] then
        __playerBlessingQueue[playerGUID] = {}
    end
    
    table.insert(__playerBlessingQueue[playerGUID], {
        player = player,
        data = data,
        timestamp = os.time()
    })
    
    PatronLogger:Debug("MainAIO", "EnqueueBlessingRequest", "Request queued", {
        playerGUID = playerGUID,
        queue_length = #__playerBlessingQueue[playerGUID]
    })
end

-- Обработать следующий запрос из очереди игрока
local function ProcessNextBlessingRequest(playerGUID)
    local queue = __playerBlessingQueue[playerGUID]
    if not queue or #queue == 0 then
        return -- очереди нет или пуста
    end
    
    local nextRequest = table.remove(queue, 1) -- FIFO - берем первый
    
    PatronLogger:Debug("MainAIO", "ProcessNextBlessingRequest", "Processing queued request", {
        playerGUID = playerGUID,
        remaining_in_queue = #queue
    })
    
    -- Устанавливаем мьютекс для следующего запроса
    SetPlayerBlessingBusy(playerGUID, true)
    
    -- Обрабатываем запрос напрямую (минуя проверку мьютекса)
    local success, error = pcall(HandleRequestBlessingCore, nextRequest.player, nextRequest.data)
    
    -- Освобождаем мьютекс
    SetPlayerBlessingBusy(playerGUID, false)
    
    if not success then
        PatronLogger:Error("MainAIO", "ProcessNextBlessingRequest", "Error processing queued request", {
            playerGUID = playerGUID,
            error = tostring(error)
        })
    end
    
    -- Рекурсивно обрабатываем следующий запрос из очереди (если есть)
    ProcessNextBlessingRequest(playerGUID)
    
    -- Очищаем очередь игрока если она пуста
    if #queue == 0 then
        __playerBlessingQueue[playerGUID] = nil
    end
end

--[[==========================================================================
  PER-PLAYER PURCHASE MUTEX SYSTEM
============================================================================]]

-- Проверить занятость игрока покупкой
local function IsPlayerPurchaseBusy(playerGUID)
    return __playerPurchaseBusy[playerGUID] == true
end

-- Поставить игрока в занятое состояние покупки
local function SetPlayerPurchaseBusy(playerGUID, busy)
    __playerPurchaseBusy[playerGUID] = busy
    if not busy then
        __playerPurchaseBusy[playerGUID] = nil -- очищаем чтобы не засорять память
    end
end

-- Добавить запрос покупки в очередь игрока
local function EnqueuePurchaseRequest(playerGUID, player, data)
    if not __playerPurchaseQueue[playerGUID] then
        __playerPurchaseQueue[playerGUID] = {}
    end
    
    table.insert(__playerPurchaseQueue[playerGUID], {
        player = player,
        data = data,
        timestamp = os.time()
    })
    
    PatronLogger:Debug("MainAIO", "EnqueuePurchaseRequest", "Purchase request queued", {
        playerGUID = playerGUID,
        queue_length = #__playerPurchaseQueue[playerGUID]
    })
end

-- Обработать следующий запрос покупки из очереди
local function ProcessNextPurchaseRequest(playerGUID)
    local queue = __playerPurchaseQueue[playerGUID]
    if not queue or #queue == 0 then
        return -- Очередь пуста
    end
    
    local nextRequest = table.remove(queue, 1) -- Берем первый запрос из очереди
    
    PatronLogger:Debug("MainAIO", "ProcessNextPurchaseRequest", "Processing queued purchase", {
        playerGUID = playerGUID,
        remaining_in_queue = #queue
    })
    
    -- Устанавливаем мьютекс для следующего запроса
    SetPlayerPurchaseBusy(playerGUID, true)
    
    -- Обрабатываем запрос напрямую (минуя проверку мьютекса)
    local success, error = pcall(HandlePurchaseRequestCore, nextRequest.player, nextRequest.data)
    
    -- Освобождаем мьютекс
    SetPlayerPurchaseBusy(playerGUID, false)
    
    if not success then
        PatronLogger:Error("MainAIO", "ProcessNextPurchaseRequest", "Error processing queued purchase", {
            playerGUID = playerGUID,
            error = tostring(error)
        })
    end
    
    -- Рекурсивно обрабатываем следующий запрос из очереди (если есть)
    ProcessNextPurchaseRequest(playerGUID)
    
    -- Очищаем очередь игрока если она пуста
    if #queue == 0 then
        __playerPurchaseQueue[playerGUID] = nil
    end
end

--[[==========================================================================
  IDEMPOTENCY SYSTEM - TTL CACHE ДЛЯ REQUESTID
============================================================================]]

-- Проверить, был ли requestId уже обработан
local function IsRequestProcessed(requestId)
    if not requestId then return false end
    
    local cached = __processedRequests[requestId]
    if not cached then return false end
    
    -- Проверяем TTL
    local currentTime = os.time()
    if (currentTime - cached.timestamp) > REQUEST_TTL_SECONDS then
        __processedRequests[requestId] = nil -- Очищаем устаревший кэш
        return false
    end
    
    return true
end

-- Сохранить результат обработки requestId
local function CacheRequestResult(requestId, result)
    if not requestId then return end
    
    __processedRequests[requestId] = {
        timestamp = os.time(),
        result = result
    }
    
    PatronLogger:Debug("MainAIO", "CacheRequestResult", "Request result cached", {
        request_id = requestId,
        success = result and result.success or false
    })
end

-- Получить закэшированный результат
local function GetCachedRequestResult(requestId)
    if not requestId then return nil end
    
    local cached = __processedRequests[requestId]
    if not cached then return nil end
    
    -- Проверяем TTL
    local currentTime = os.time()
    if (currentTime - cached.timestamp) > REQUEST_TTL_SECONDS then
        __processedRequests[requestId] = nil
        return nil
    end
    
    return cached.result
end

-- Очистка устаревших requestId (вызывается периодически)
local function CleanupExpiredRequests()
    local currentTime = os.time()
    local cleanedCount = 0
    
    for requestId, cached in pairs(__processedRequests) do
        if (currentTime - cached.timestamp) > REQUEST_TTL_SECONDS then
            __processedRequests[requestId] = nil
            cleanedCount = cleanedCount + 1
        end
    end
    
    if cleanedCount > 0 then
        PatronLogger:Debug("MainAIO", "CleanupExpiredRequests", "Expired requests cleaned", {
            cleaned_count = cleanedCount
        })
    end
end

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

    -- blessings: обогащаем данными из data_blessings.lua
    if playerProgress and type(playerProgress.blessings) == "table" then
        snapshot.blessings = {}
        PatronLogger:Info("MainAIO", "BuildProgressSnapshot", "Processing blessings", {
            blessing_count = 0,
            blessing_ids = {}
        })
        
        local processedCount = 0
        for blessingId, blessingFlags in pairs(playerProgress.blessings) do
            local bId = tonumber(blessingId)
            local blessingData = BlessingsData[bId]
            processedCount = processedCount + 1
            
            PatronLogger:Info("MainAIO", "BuildProgressSnapshot", "Processing blessing", {
                blessing_id = blessingId,
                numeric_id = bId,
                has_data = blessingData ~= nil,
                flags = blessingFlags
            })
            
            if blessingData then
                snapshot.blessings[blessingId] = {
                    isDiscovered = blessingFlags.isDiscovered or false,
                    isInPanel = blessingFlags.isInPanel or false,
                    panelSlot = blessingFlags.panelSlot or 0,
                    -- Данные из data_blessings.lua
                    name = blessingData.name,
                    description = blessingData.description,
                    icon = blessingData.icon,
                    blessing_type = blessingData.blessing_type,
                    blessing_id = blessingData.blessing_id
                }
                PatronLogger:Debug("MainAIO", "BuildProgressSnapshot", "Blessing panel state", {
                    blessing_id = blessingId,
                    isInPanel = snapshot.blessings[blessingId].isInPanel
                })
            end
        end
        
        -- Логируем итоговый результат
        local finalBlessingCount = 0
        for k, v in pairs(snapshot.blessings) do
            finalBlessingCount = finalBlessingCount + 1
        end
        PatronLogger:Info("MainAIO", "BuildProgressSnapshot", "Final snapshot created", {
            final_blessing_count = finalBlessingCount,
            processed_count = processedCount
        })
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
        FollowerID = followerId,
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

local HandleStartFollowerDialogue

local function HandleStartDialogue(player, data)
    -- Если получена таблица и указан фолловер - вызываем отдельный обработчик
    if type(data) == "table" and data.speakerType == "follower" then
        local followerId = data.speakerID or data.speakerId
        return HandleStartFollowerDialogue(player, followerId)
    end

    -- Иначе обрабатываем как диалог с покровителем (старое поведение)
    local patronId = data
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
-- Начало диалога с фолловером
HandleStartFollowerDialogue = function(player, followerId)
    PatronLogger:Info("MainAIO", "HandleStartFollowerDialogue", "Starting dialogue with follower", {
        player = player:GetName(),
        follower_id = followerId
    })

    local dialogueData = PatronDialogueCore.StartFollowerDialogue(player, followerId)
    if not dialogueData then
        PatronLogger:Error("MainAIO", "HandleStartFollowerDialogue", "Failed to start follower dialogue")
        SafeSendResponse(player, "Error", {
            message = "Не удалось начать диалог с фолловером"
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
            results = actionResult.results,
            progressData = BuildProgressSnapshot(playerGuid, playerProgress)
        })
        
        -- Проверяем нужна ли перезагрузка данных после разблокировки благословений
        if actionResult.success and actionResult.results then
            local needsDataReload = false
            for _, result in ipairs(actionResult.results) do
                if result.requiresDataReload then
                    needsDataReload = true
                    break
                end
            end
            
            if needsDataReload then
                -- Отправляем обновленный снепшот с новыми данными благословений
                local updatedSnapshot = CreatePlayerSnapshot(player, playerProgress)
                SafeSendResponse(player, "DataUpdated", updatedSnapshot)
                
                PatronLogger:Info("Main", "ProcessChoice", "Blessing data reloaded after unlock", {
                    player = player:GetName()
                })
            end
        end
        
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

-- Обработка обновления панели благословений
local function HandleUpdateBlessingPanel(player, data)
    PatronLogger:Info("MainAIO", "HandleUpdateBlessingPanel", "Updating blessing panel", {
        player = player:GetName(),
        blessing_id = data.blessingId,
        is_in_panel = data.isInPanel,
        panel_slot = data.panelSlot
    })
    
    if not data.blessingId then
        PatronLogger:Error("MainAIO", "HandleUpdateBlessingPanel", "Missing blessingId")
        SafeSendResponse(player, "Error", {
            message = "Отсутствует ID благословения"
        })
        return false
    end
    
    -- Загружаем прогресс игрока
    local playerGuid = tostring(player:GetGUID())
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    
    if not playerProgress then
        PatronLogger:Error("MainAIO", "HandleUpdateBlessingPanel", "Player data not found")
        SafeSendResponse(player, "Error", {
            message = "Данные игрока не найдены"
        })
        return false
    end
    
    -- Проверяем есть ли такое благословение у игрока
    local blessingId = tostring(data.blessingId)
    if not playerProgress.blessings or not playerProgress.blessings[blessingId] then
        PatronLogger:Error("MainAIO", "HandleUpdateBlessingPanel", "Blessing not unlocked", {
            blessing_id = blessingId
        })
        SafeSendResponse(player, "Error", {
            message = "Благословение не разблокировано"
        })
        return false
    end
    
    -- Обновляем флаг isInPanel и позицию в панели
    playerProgress.blessings[blessingId].isInPanel = data.isInPanel or false
    if data.panelSlot then
        playerProgress.blessings[blessingId].panelSlot = data.panelSlot
    end
    
    -- Сохраняем в БД
    local success = PatronDBManager.SavePlayerProgress(playerGuid, playerProgress)
    
    if success then
        PatronLogger:Info("MainAIO", "HandleUpdateBlessingPanel", "Panel updated successfully", {
            blessing_id = blessingId,
            is_in_panel = playerProgress.blessings[blessingId].isInPanel,
            panel_slot = playerProgress.blessings[blessingId].panelSlot
        })
        
        SafeSendResponse(player, "BlessingPanelUpdated", {
            success = true,
            blessingId = data.blessingId,
            isInPanel = playerProgress.blessings[blessingId].isInPanel
        })
    else
        PatronLogger:Error("MainAIO", "HandleUpdateBlessingPanel", "Failed to save blessing panel state")
        SafeSendResponse(player, "Error", {
            message = "Не удалось сохранить состояние панели"
        })
    end
    
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
  ОБРАБОТЧИКИ ИСПОЛЬЗОВАНИЯ БЛАГОСЛОВЕНИЙ
============================================================================]]

-- Обработка запроса с мьютексом (точка входа)
local function HandleRequestBlessingWithMutex(player, data)
    local playerGUID = tostring(player:GetGUIDLow())
    
    -- Проверяем занятость игрока
    if IsPlayerBlessingBusy(playerGUID) then
        PatronLogger:Debug("MainAIO", "HandleRequestBlessingWithMutex", "Player busy, enqueueing request", {
            player = player:GetName(),
            playerGUID = playerGUID
        })
        
        EnqueueBlessingRequest(playerGUID, player, data)
        return -- запрос поставлен в очередь
    end
    
    -- Устанавливаем мьютекс
    SetPlayerBlessingBusy(playerGUID, true)
    
    PatronLogger:Debug("MainAIO", "HandleRequestBlessingWithMutex", "Processing request with mutex", {
        player = player:GetName(),
        blessing_id = data.blessingID
    })
    
    -- Обрабатываем запрос
    local success, error = pcall(HandleRequestBlessingCore, player, data)
    
    -- Освобождаем мьютекс
    SetPlayerBlessingBusy(playerGUID, false)
    
    if not success then
        PatronLogger:Error("MainAIO", "HandleRequestBlessingWithMutex", "Error in blessing processing", {
            player = player:GetName(),
            error = tostring(error)
        })
    end
    
    -- Обрабатываем следующий запрос из очереди (если есть)
    ProcessNextBlessingRequest(playerGUID)
end

-- Отправить ошибку благословения с типом клиенту
local function SendBlessingError(player, errorType, message)
    -- Отправляем сообщение игроку
    if message then
        player:SendBroadcastMessage(message)
    end
    
    -- Отправляем детальную информацию клиенту для звукового сопровождения
    SafeSendResponse(player, "BlessingError", {
        errorType = errorType,
        message = message
    })
    
    PatronLogger:Debug("MainAIO", "SendBlessingError", "Blessing error sent to client", {
        player = player:GetName(),
        errorType = errorType,
        message = message
    })
end

-- Ядро обработки запроса на использование благословения (без мьютекса)
HandleRequestBlessingCore = function(player, data)
    PatronLogger:Info("MainAIO", "HandleRequestBlessing", "Processing blessing request", {
        player = player:GetName(),
        blessing_id = data.blessingID
    })

    local playerName = tostring(player:GetName())
    PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Request received", {
        player = playerName,
        blessing_id = data.blessingID
    })

    local blessingID = data.blessingID
    local info = BlessingsData[blessingID]

    if not info then
        SendBlessingError(player, "unknown_blessing", "Неизвестное благословение.")
        PatronLogger:Error("MainAIO", "HandleRequestBlessing", "Unknown blessing ID", {
            blessing_id = blessingID
        })
        return
    end
    
    PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Blessing found", {
        blessing_name = info.name,
        spell_id = info.spell_id
    })

    -- === ЛОГИКА ОБРАБОТКИ ЦЕЛИ ===
    local finalSpellTarget = player -- По умолчанию цель - сам игрок

    if info.requires_target then
        local targetUnit = player:GetSelection()

        if not targetUnit or not targetUnit:IsInWorld() then
            SendBlessingError(player, "no_target", "Вам нужно выбрать цель для этого благословения, " .. info.name .. ".")
            PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "No target selected or target not in world")
            return
        end

        finalSpellTarget = targetUnit

        if info.is_offensive then
            -- 1. Проверка на атаку самого себя
            if targetUnit:GetGUID() == player:GetGUID() then
                SendBlessingError(player, "target_self", ("Вы не можете атаковать себя с помощью %s!"):format(info.name))
                PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Attempted self-attack")
                return
            end

            -- 2. Проверка дружебности
                local checkRadius = 60.0
                local friendlyUnits = player:GetFriendlyUnitsInRange(checkRadius)
                
                local isTargetFriendly = false
                if friendlyUnits then
                  for _, unit in ipairs(friendlyUnits) do
                    if unit and unit:GetGUID() == targetUnit:GetGUID() then
                      isTargetFriendly = true
                      break
                    end
                  end
                end

                if isTargetFriendly then
                    SendBlessingError(player, "target_friendly", "Вы не можете атаковать дружественную цель с помощью " .. info.name .. "!")
                    PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Attempted to attack friendly target")
                    return
                end

                -- 3. Проверка, жива ли цель
                if not targetUnit:IsAlive() then
                    SendBlessingError(player, "target_dead", "Ваша цель мертва.")
                    PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Target is dead")
                    return
                end

                -- 4. Проверка "атакуемости"
                local success, isTargetable = pcall(targetUnit.IsTargetableForAttack, targetUnit)
                if success and not isTargetable then
                    SendBlessingError(player, "target_invalid", "Эту цель нельзя атаковать.")
                    PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Target not attackable")
                    return
                end
                
                -- 5. Проверка дистанции
                local max_range = info.range or 40.0
                if player:GetDistance(targetUnit) > max_range then
                    SendBlessingError(player, "target_too_far", "Ваша цель находится слишком далеко.")
                    PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Target too far away")
                    return
                end
            end
        end

        -- === ПРОВЕРКИ ИГРОКА ===
        
        -- Проверка активности ауры (только для не-атакующих)
        if not info.is_offensive and info.spell_id and finalSpellTarget:HasAura(info.spell_id) then
            SendBlessingError(player, "already_has_aura", ("%s уже активен!"):format(info.name))
            PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Blessing already active")
            return
        end

        -- Проверка кулдауна - используем PatronGameLogicCore функции
        if not PatronGameLogicCore.CanUseBlessing(player, blessingID) then
            local remainingCooldown = PatronGameLogicCore.GetBlessingCooldown(player, blessingID)
            SendBlessingError(player, "cooldown", ("Вы не можете использовать %s еще %.0f сек."):format(info.name, remainingCooldown))
            PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Blessing on cooldown", {
                blessing_id = blessingID,
                remaining_seconds = remainingCooldown
            })
            return
        end

        -- Проверка и списание стоимости через PatronGameLogicCore
        if info.cost_item_id and info.cost_amount > 0 then
            -- Проверяем наличие через систему GameLogicCore
            if not PatronGameLogicCore.HasItem(player, info.cost_item_id, info.cost_amount) then
                SendBlessingError(player, "insufficient_reagents", "Вам не хватает реагентов для этого благословения.")
                PatronLogger:Warning("MainAIO", "HandleRequestBlessing", "Insufficient reagents", {
                    required_item_id = info.cost_item_id,
                    required_amount = info.cost_amount
                })
                return
            end
            
            -- Списываем через систему GameLogicCore (с логированием и валидацией)
            local removeResult = PatronGameLogicCore.RemoveItem(player, info.cost_item_id, info.cost_amount)
            if not removeResult.success then
                SendBlessingError(player, "reagent_removal_failed", "Не удалось списать реагенты для благословения.")
                PatronLogger:Error("MainAIO", "HandleRequestBlessing", "Failed to remove reagents", {
                    error = removeResult.message
                })
                return
            end
            
            PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Reagents consumed via GameLogicCore", {
                item_id = info.cost_item_id,
                amount = info.cost_amount
            })
        end

        -- === ПРИМЕНЕНИЕ ЭФФЕКТА ===
        PatronLogger:Info("MainAIO", "HandleRequestBlessing", "Applying blessing effect", {
            blessing_id = blessingID,
            is_aoe = info.is_aoe,
            is_offensive = info.is_offensive,
            target = finalSpellTarget:GetName()
        })

        -- Применяем эффект через GameLogicCore
        local effectResult = PatronGameLogicCore.ApplyBlessingEffect(player, finalSpellTarget, info)
        
    if effectResult and effectResult.success then
        player:SendBroadcastMessage(("Вы успешно использовали %s!"):format(info.name))
        PatronLogger:Info("MainAIO", "HandleRequestBlessing", "Blessing applied successfully", {
            player = playerName,
            blessing_name = info.name
        })
        
        -- Проактивно отправляем обновленные кулдауны клиенту
        local cooldowns = PatronGameLogicCore.playerCooldowns[tostring(player:GetGUIDLow())] or {}
        local cooldownData = {}
        
        for blessingId, _ in pairs(cooldowns) do
            local remaining = PatronGameLogicCore.GetBlessingCooldown(player, blessingId)
            if remaining > 0 then
                local blessingInfo = PatronGameLogicCore.ServerBlessingsConfig[blessingId]
                local duration = blessingInfo and blessingInfo.cooldown_seconds or 60
                
                cooldownData[blessingId] = {
                    remaining = remaining,
                    duration = duration
                }
            end
        end
        
        -- Отправляем кулдауны без дополнительного запроса от клиента
        SafeSendResponse(player, "UpdateCooldowns", cooldownData)
        
        -- Подсчитываем количество кулдаунов
        local cooldownCount = 0
        for _ in pairs(cooldownData) do
            cooldownCount = cooldownCount + 1
        end
        
        PatronLogger:Debug("MainAIO", "HandleRequestBlessing", "Proactive cooldowns sent", {
            player = playerName,
            cooldown_count = cooldownCount
        })
    else
        player:SendBroadcastMessage("Не удалось применить благословение.")
        PatronLogger:Error("MainAIO", "HandleRequestBlessing", "Failed to apply blessing effect")
    end
end

-- Ядро обработки запроса на покупку за ресурсы (без мьютекса) 
HandlePurchaseRequestCore = function(player, data)
    local playerGuid = tostring(player:GetGUID())
    local playerName = player:GetName()
    local requestId = data.requestId
    
    PatronLogger:Info("MainAIO", "HandlePurchaseRequest", "Processing purchase request", {
        player = playerName,
        item_id = data.itemId,
        cost_souls = data.costSouls,
        cost_suffering = data.costSuffering,
        request_id = requestId
    })
    
    -- IDEMPOTENCY CHECK: Проверяем, не обрабатывался ли уже этот requestId
    if requestId and IsRequestProcessed(requestId) then
        local cachedResult = GetCachedRequestResult(requestId)
        PatronLogger:Info("MainAIO", "HandlePurchaseRequest", "Duplicate request detected - returning cached result", {
            request_id = requestId,
            player = playerName
        })
        
        -- Отправляем закэшированный результат
        if cachedResult then
            if cachedResult.success then
                AIO.Handle(player, "PatronSystem", "PurchaseSuccess", cachedResult.response)
            else
                AIO.Handle(player, "PatronSystem", "PurchaseError", cachedResult.response)
            end
        end
        return
    end
    
    -- Валидация входных данных
    if not data.itemId or not data.costSouls or not data.costSuffering then
        PatronLogger:Error("MainAIO", "HandlePurchaseRequest", "Invalid purchase data", {
            item_id = data.itemId,
            cost_souls = data.costSouls,
            cost_suffering = data.costSuffering
        })
        
        local errorResponse = {
            message = "Некорректные данные покупки",
            errorType = "invalid_data"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Кэшируем результат ошибки
        if requestId then
            CacheRequestResult(requestId, {
                success = false,
                response = errorResponse
            })
        end
        return
    end
    
    local itemId = data.itemId
    local costSouls = data.costSouls or 0
    local costSuffering = data.costSuffering or 0
    
    -- Проверка что игрок имеет достаточно ресурсов (проверяем в кэше с учетом pending delta)
    local currentProgress = PatronResourceBatching:GetOrLoadPlayerCache(playerGuid)
    if not currentProgress then
        PatronLogger:Error("MainAIO", "HandlePurchaseRequest", "Failed to load player progress", {
            player = playerName
        })
        
        local errorResponse = {
            message = "Не удалось загрузить данные игрока",
            errorType = "data_load_failed"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Кэшируем результат ошибки
        if requestId then
            CacheRequestResult(requestId, {
                success = false,
                response = errorResponse
            })
        end
        return
    end
    
    local currentSouls = currentProgress.souls or 0
    local currentSuffering = currentProgress.suffering or 0
    
    if currentSouls < costSouls or currentSuffering < costSuffering then
        PatronLogger:Warning("MainAIO", "HandlePurchaseRequest", "Insufficient resources", {
            player = playerName,
            required_souls = costSouls,
            required_suffering = costSuffering,
            available_souls = currentSouls,
            available_suffering = currentSuffering
        })
        
        local errorResponse = {
            message = string.format("Недостаточно ресурсов. Нужно: %d душ, %d страданий", costSouls, costSuffering),
            errorType = "insufficient_resources"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Кэшируем результат ошибки
        if requestId then
            CacheRequestResult(requestId, {
                success = false,
                response = errorResponse
            })
        end
        return
    end
    
    -- АТОМАРНОЕ СПИСАНИЕ в БД с условием
    local paymentSuccess = PatronDBManager.UpdateResourcesConditional(playerGuid, costSouls, costSuffering)
    
    if not paymentSuccess then
        PatronLogger:Warning("MainAIO", "HandlePurchaseRequest", "Payment failed - insufficient resources in DB", {
            player = playerName,
            cost_souls = costSouls,
            cost_suffering = costSuffering
        })
        
        local errorResponse = {
            message = "Не хватает ресурсов для совершения покупки",
            errorType = "payment_failed"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Кэшируем результат ошибки
        if requestId then
            CacheRequestResult(requestId, {
                success = false,
                response = errorResponse
            })
        end
        return
    end
    
    -- ИСПРАВЛЕНИЕ: НЕ обнуляем pendingDeltas - оставляем накопленные киллы
    -- Периодический флаш позже синхронизирует абсолютные значения через UpdateResources
    -- Это предотвращает потерю накопленных +souls/+suffering от киллов при покупках
    
    -- Применяем эффект покупки в зависимости от типа предмета
    local purchaseResult = nil
    
    if data.purchaseType == "blessing" then
        -- Разблокировка благословения
        purchaseResult = PatronGameLogicCore.UnlockBlessing(player, itemId, currentProgress)
        
    elseif data.purchaseType == "item" then
        -- Выдача предмета
        purchaseResult = PatronGameLogicCore.GiveItem(player, itemId, data.quantity or 1)
        
    elseif data.purchaseType == "patron_upgrade" then
        -- Улучшение отношений с патроном
        purchaseResult = PatronGameLogicCore.UpgradePatronRelationship(player, itemId, data.upgradeAmount or 1)
        
    else
        PatronLogger:Error("MainAIO", "HandlePurchaseRequest", "Unknown purchase type", {
            purchase_type = data.purchaseType
        })
        
        -- Возвращаем ресурсы при неизвестном типе покупки
        PatronDBManager.UpdateResources(playerGuid, 
            (currentProgress.souls or 0) + costSouls, 
            (currentProgress.suffering or 0) + costSuffering)
        
        local errorResponse = {
            message = "Неизвестный тип покупки",
            errorType = "unknown_purchase_type"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Кэшируем результат ошибки
        if requestId then
            CacheRequestResult(requestId, {
                success = false,
                response = errorResponse
            })
        end
        return
    end
    
    -- currentProgress уже обновлён в PatronDBManager.UpdateResourcesConditional через общий кэш
    -- Отправляем мгновенное обновление ресурсов клиенту, используя данные из кэша
    AIO.Handle(player, "PatronSystem", "ResourcesUpdated", {
        souls = currentProgress.souls,
        suffering = currentProgress.suffering
    })

    -- Если изменилась структура данных - отправляем полный снэпшот, используя
    -- текущие данные в памяти вместо повторной загрузки из БД
    if (data.purchaseType == "blessing" or data.purchaseType == "patron_upgrade")
       and purchaseResult and purchaseResult.success then
        local snapshot = BuildProgressSnapshot(playerGuid, currentProgress)
        AIO.Handle(player, "PatronSystem", "DataUpdated", snapshot)
    end
    
    -- Успешное завершение покупки
    local successResponse = {
        itemId = itemId,
        purchaseType = data.purchaseType,
        costSouls = costSouls,
        costSuffering = costSuffering,
        message = string.format("Покупка успешно завершена! Потрачено: %d душ, %d страданий", costSouls, costSuffering)
    }
    
    AIO.Handle(player, "PatronSystem", "PurchaseSuccess", successResponse)
    
    -- Кэшируем результат успеха
    if requestId then
        CacheRequestResult(requestId, {
            success = true,
            response = successResponse
        })
    end
    
    PatronLogger:Info("MainAIO", "HandlePurchaseRequest", "Purchase completed successfully", {
        player = playerName,
        item_id = itemId,
        purchase_type = data.purchaseType,
        souls_spent = costSouls,
        suffering_spent = costSuffering
    })
end

-- Обработчик запроса покупки с мьютексом
local function HandlePurchaseRequest(player, data)
    local playerGUID = tostring(player:GetGUID())
    
    -- Проверяем занятость игрока покупкой
    if IsPlayerPurchaseBusy(playerGUID) then
        PatronLogger:Debug("MainAIO", "HandlePurchaseRequest", "Player busy with purchase, enqueueing", {
            playerGUID = playerGUID
        })
        
        -- Добавляем в очередь
        EnqueuePurchaseRequest(playerGUID, player, data)
        return
    end
    
    -- Устанавливаем мьютекс
    SetPlayerPurchaseBusy(playerGUID, true)
    
    PatronLogger:Debug("MainAIO", "HandlePurchaseRequest", "Processing purchase with mutex", {
        playerGUID = playerGUID,
        item_id = data.itemId
    })
    
    -- Обрабатываем запрос
    local success, error = pcall(HandlePurchaseRequestCore, player, data)
    
    -- Освобождаем мьютекс
    SetPlayerPurchaseBusy(playerGUID, false)
    
    if not success then
        PatronLogger:Error("MainAIO", "HandlePurchaseRequest", "Error in purchase processing", {
            error = tostring(error),
            player = player:GetName()
        })
        
        local errorResponse = {
            message = "Внутренняя ошибка при обработке покупки",
            errorType = "internal_error"
        }
        
        AIO.Handle(player, "PatronSystem", "PurchaseError", errorResponse)
        
        -- Не кэшируем внутренние ошибки, так как они могут быть временными
    end
    
    -- Обрабатываем следующий запрос из очереди
    ProcessNextPurchaseRequest(playerGUID)
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
        
        -- Depth guard to prevent runaway recursion
        if SAFETY.ENABLE_REENTRANCY_GUARD then
            __currentNestedDepth = __currentNestedDepth + 1
            if __currentNestedDepth > SAFETY.MAX_NESTED_CALLS then
                PatronLogger:Error("MainAIO", "CreateSafeHandler", "Nested call depth exceeded", {
                    handler = handlerName,
                    depth = __currentNestedDepth
                })
                __currentNestedDepth = __currentNestedDepth - 1
                UpdateRequestStats(handlerName, false)
                return
            end
        end
        local success, result = pcall(handlerFunc, player, ...)
        UpdateRequestStats(handlerName, success)
        
        if not success then
            HandleAIOError(handlerName, player, result)
        end
        
        if SAFETY.ENABLE_REENTRANCY_GUARD then
            __currentNestedDepth = __currentNestedDepth - 1
            if __currentNestedDepth < 0 then __currentNestedDepth = 0 end
        end
        return result
    end
end

-- Обработчик запроса кулдаунов
local function HandleRequestCooldowns(player)
    if not player then 
        PatronLogger:Error("MainAIO", "HandleRequestCooldowns", "Player is nil")
        return 
    end
    
    local playerId = player:GetGUIDLow()
    local playerIdString = tostring(playerId)
    
    -- Rate-limit spammy cooldown requests per player
    if SAFETY.COOLDOWNS_MIN_INTERVAL and SAFETY.COOLDOWNS_MIN_INTERVAL > 0 then
        local now = os.time()
        local last = __lastCooldownsRequest[playerId]
        if last and (now - last) < SAFETY.COOLDOWNS_MIN_INTERVAL then
            -- Too soon; ignore to avoid server flooding/nesting
            if AIO_CONFIG.LOG_ALL_REQUESTS then
                PatronLogger:Debug("MainAIO", "HandleRequestCooldowns", "Request skipped due to rate limit", {
                    player = player:GetName()
                })
            end
            return
        end
        __lastCooldownsRequest[playerId] = now
    end
    
    local cooldowns = PatronGameLogicCore.playerCooldowns[playerIdString] or {}
    local cooldownData = {}
    
    -- Собираем актуальные кулдауны
    for blessingId, _ in pairs(cooldowns) do
        local remaining = PatronGameLogicCore.GetBlessingCooldown(player, blessingId)
        
        if remaining > 0 then
            local blessingInfo = PatronGameLogicCore.ServerBlessingsConfig[blessingId]
            local duration = blessingInfo and blessingInfo.cooldown_seconds or 60
            
            cooldownData[blessingId] = {
                remaining = remaining,
                duration = duration
            }
        end
    end
    
    -- Подсчитываем количество кулдаунов
    local cooldownCount = 0
    for _ in pairs(cooldownData) do
        cooldownCount = cooldownCount + 1
    end
    
    -- Отправляем данные клиенту
    SafeSendResponse(player, "UpdateCooldowns", cooldownData)
    PatronLogger:Info("MainAIO", "HandleRequestCooldowns", "Cooldowns sent", {
        player = player:GetName(),
        cooldown_count = cooldownCount
    })
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
    UpdateBlessingPanel = CreateSafeHandler("UpdateBlessingPanel", HandleUpdateBlessingPanel),
    
    --=== БЛАГОСЛОВЕНИЯ - ИСПОЛЬЗОВАНИЕ ===--
    RequestBlessing = CreateSafeHandler("RequestBlessing", HandleRequestBlessingWithMutex),
    RequestCooldowns = CreateSafeHandler("RequestCooldowns", HandleRequestCooldowns),
    
    --=== ПОКУПКИ ЗА РЕСУРСЫ ===--
    PurchaseRequest = CreateSafeHandler("PurchaseRequest", HandlePurchaseRequest),
    
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

-- Периодическая очистка кэша requestId
local function CreateRequestCleanupTimer()
    CreateLuaEvent(function()
        CleanupExpiredRequests()
        CreateRequestCleanupTimer() -- Рекурсивный вызов
    end, 60000) -- Каждую минуту
end

-- Запускаем очистку кэша
pcall(CreateRequestCleanupTimer)

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

-- Загружаем дополнительные модули
local followerTestLoaded, followerTestError = pcall(function()
    -- Пробуем сначала require
    require("follower_test")
end)

if not followerTestLoaded then
    PatronLogger:Error("MainAIO", "Initialize", "Failed to load follower test module via require", {
        error = tostring(followerTestError or "unknown error")
    })
    
    -- Пробуем dofile как резервный вариант
    local dofileLoaded, dofileError = pcall(function()
        -- Определяем путь к скрипту относительно текущего файла
        local scriptPath = debug.getinfo(1, "S").source:match("@(.*)[\\/][^\\/]*$")
        if scriptPath then
            dofile(scriptPath .. "/follower_test.lua")
        else
            dofile("follower_test.lua") -- fallback
        end
    end)
    
    if dofileLoaded then
        PatronLogger:Info("MainAIO", "Initialize", "Follower test module loaded via dofile")
        followerTestLoaded = true
    else
        PatronLogger:Error("MainAIO", "Initialize", "Failed to load follower test module via dofile", {
            error = tostring(dofileError or "unknown error")
        })
    end
else
    PatronLogger:Info("MainAIO", "Initialize", "Follower test module loaded successfully via require")
end