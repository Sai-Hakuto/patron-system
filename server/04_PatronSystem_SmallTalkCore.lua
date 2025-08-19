--[[==========================================================================
  PATRON SYSTEM - SMALLTALK CORE v1.0
  Динамическая система фраз покровителей с условной доступностью
  
  ОТВЕТСТВЕННОСТЬ:
  - Фильтрация SmallTalk фраз по условиям доступности
  - Приоритезация фраз (более специфичные фразы показываются чаще)
  - Рандомный выбор из доступных фраз
  - Кэширование результатов для оптимизации
============================================================================]]

-- Проверяем зависимости
if not PatronLogger then
    error("PatronLogger не загружен! Загрузите 01_PatronSystem_Logger.lua")
end

-- PatronDialogueCore будет загружен позже, используем его функции валидации через проверку существования

PatronLogger:Info("SmallTalkCore", "Initialize", "Loading SmallTalk core module v1.0")

-- Загружаем SmallTalk данные
local smalltalks_loaded, SmallTalksData = pcall(require, "data.data_smalltalks")
if not smalltalks_loaded then
    PatronLogger:Error("SmallTalkCore", "Initialize", "Failed to load smalltalks data", {
        error = tostring(SmallTalksData)
    })
    error("SmallTalksData не загружен!")
end

-- Создаем модуль
PatronSmallTalkCore = PatronSmallTalkCore or {}

--[[==========================================================================
  КОНФИГУРАЦИЯ МОДУЛЯ
============================================================================]]

local SMALLTALK_CONFIG = {
    CACHE_ENABLED = true,               -- Кэшировать результаты фильтрации
    LOG_SELECTION = true,               -- Логировать выбор фраз
    LOG_FILTERING = true,               -- Логировать процесс фильтрации
    PRIORITY_WEIGHT_MULTIPLIER = 2      -- Множитель для весов приоритетных фраз
}

-- Кэш отфильтрованных SmallTalk для игроков
local playerSmallTalkCache = {}
local cacheStats = {
    hits = 0,
    misses = 0,
    invalidations = 0
}

math.randomseed(os.time())
for _ = 1, 3 do math.random() end

--[[==========================================================================
  ОСНОВНЫЕ ФУНКЦИИ
============================================================================]]

-- Получить все доступные SmallTalk фразы для игрока и покровителя
function PatronSmallTalkCore.GetAvailableSmallTalks(player, patronId)
    local playerGuid = tostring(player:GetGUID())
    local cacheKey = playerGuid .. "_" .. patronId
    
    -- Проверяем кэш
    if SMALLTALK_CONFIG.CACHE_ENABLED and playerSmallTalkCache[cacheKey] then
        cacheStats.hits = cacheStats.hits + 1
        if SMALLTALK_CONFIG.LOG_FILTERING then
            PatronLogger:Debug("SmallTalkCore", "GetAvailableSmallTalks", "Cache hit", {
                player = player:GetName(),
                patron_id = patronId,
                cached_count = #playerSmallTalkCache[cacheKey]
            })
        end
        return playerSmallTalkCache[cacheKey]
    end
    
    cacheStats.misses = cacheStats.misses + 1
    
    -- Загружаем прогресс игрока
    local playerProgress = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not playerProgress then
        PatronLogger:Error("SmallTalkCore", "GetAvailableSmallTalks", "Failed to load player progress")
        return {}
    end
    
    -- Получаем список SmallTalk для покровителя
    local patronSmallTalks = SmallTalksData[patronId]
    if not patronSmallTalks then
        if SMALLTALK_CONFIG.LOG_FILTERING then
            PatronLogger:Warning("SmallTalkCore", "GetAvailableSmallTalks", "No SmallTalk data for patron", {
                patron_id = patronId
            })
        end
        return {}
    end
    
    local availableSmallTalks = {}
    local totalCount = 0
    local availableCount = 0
    
    for _, smallTalk in ipairs(patronSmallTalks) do
        totalCount = totalCount + 1
        
        -- Проверяем условия доступности
        local isAvailable = true
        if smallTalk.Conditions then
            isAvailable = PatronSmallTalkCore.ValidateConditions(smallTalk.Conditions, player, playerProgress)
        end
        
        if isAvailable then
            availableCount = availableCount + 1
            table.insert(availableSmallTalks, {
                replica = smallTalk.Replica,
                priority = smallTalk.Priority or 1,
                conditions = smallTalk.Conditions
            })
        end
        
        if SMALLTALK_CONFIG.LOG_FILTERING then
            PatronLogger:Verbose("SmallTalkCore", "GetAvailableSmallTalks", "SmallTalk processed", {
                replica_preview = string.sub(smallTalk.Replica, 1, 30) .. "...",
                available = isAvailable,
                priority = smallTalk.Priority or 1,
                has_conditions = smallTalk.Conditions and #smallTalk.Conditions > 0 or false
            })
        end
    end
    
    -- Сохраняем в кэш
    if SMALLTALK_CONFIG.CACHE_ENABLED then
        playerSmallTalkCache[cacheKey] = availableSmallTalks
    end
    
    if SMALLTALK_CONFIG.LOG_FILTERING then
        PatronLogger:Info("SmallTalkCore", "GetAvailableSmallTalks", "SmallTalks filtered", {
            player = player:GetName(),
            patron_id = patronId,
            total_count = totalCount,
            available_count = availableCount
        })
    end
    
    return availableSmallTalks
end

-- Выбрать случайную SmallTalk фразу с учетом приоритетов
function PatronSmallTalkCore.SelectRandomSmallTalk(player, patronId)
    local availableSmallTalks = PatronSmallTalkCore.GetAvailableSmallTalks(player, patronId)
    
    if #availableSmallTalks == 0 then
        if SMALLTALK_CONFIG.LOG_SELECTION then
            PatronLogger:Warning("SmallTalkCore", "SelectRandomSmallTalk", "No available SmallTalks", {
                player = player:GetName(),
                patron_id = patronId
            })
        end
        return "..." -- Фраза по умолчанию
    end
    
    -- Создаем взвешенный список для приоритетов
    local weightedList = {}
    local totalWeight = 0
    
    for _, smallTalk in ipairs(availableSmallTalks) do
        -- Вес = приоритет * множитель (чем выше приоритет, тем больше вес)
        local weight = smallTalk.priority * SMALLTALK_CONFIG.PRIORITY_WEIGHT_MULTIPLIER
        totalWeight = totalWeight + weight
        
        table.insert(weightedList, {
            replica = smallTalk.replica,
            priority = smallTalk.priority,
            weight = weight,
            cumulativeWeight = totalWeight
        })
    end
	
    -- Выбираем случайную фразу с учетом весов
    local randomValue = math.random() * totalWeight
    local selectedSmallTalk = nil
    
    for _, item in ipairs(weightedList) do
        if randomValue <= item.cumulativeWeight then
            selectedSmallTalk = item
            break
        end
    end
    
    -- Fallback на первую фразу если что-то пошло не так
    if not selectedSmallTalk then
        selectedSmallTalk = weightedList[1]
    end
    
    if SMALLTALK_CONFIG.LOG_SELECTION then
        PatronLogger:Info("SmallTalkCore", "SelectRandomSmallTalk", "SmallTalk selected", {
            player = player:GetName(),
            patron_id = patronId,
            replica_preview = string.sub(selectedSmallTalk.replica, 1, 50) .. "...",
            priority = selectedSmallTalk.priority,
            weight = selectedSmallTalk.weight,
            total_weight = totalWeight,
            available_options = #availableSmallTalks
        })
    end
    
    return selectedSmallTalk.replica
end

-- Получить список доступных SmallTalk для передачи клиенту
function PatronSmallTalkCore.GetSmallTalkListForClient(player, patronId)
    local availableSmallTalks = PatronSmallTalkCore.GetAvailableSmallTalks(player, patronId)
    
    -- Преобразуем в формат для клиента
    local clientList = {}
    for _, smallTalk in ipairs(availableSmallTalks) do
        table.insert(clientList, {
            text = smallTalk.replica,
            priority = smallTalk.priority
        })
    end
    
    return clientList
end

--[[==========================================================================
  ВАЛИДАЦИЯ УСЛОВИЙ (ПЕРЕИСПОЛЬЗУЕМ ЛОГИКУ ИЗ DIALOGUECORE)
============================================================================]]

-- Проверить условия доступности SmallTalk
function PatronSmallTalkCore.ValidateConditions(conditions, player, playerProgress)
    if not conditions or #conditions == 0 then
        return true
    end
    
    -- Если DialogueCore доступен, используем его валидацию для консистентности
    if PatronDialogueCore and PatronDialogueCore.ValidateConditions then
        return PatronDialogueCore.ValidateConditions(conditions, player, playerProgress)
    end
    
    -- Иначе используем собственную упрощенную валидацию
    for i, condition in ipairs(conditions) do
        if not PatronSmallTalkCore.ValidateSingleCondition(condition, player, playerProgress) then
            return false
        end
    end
    
    return true
end

-- Проверить одно условие (дублируем логику из DialogueCore для независимости)
function PatronSmallTalkCore.ValidateSingleCondition(condition, player, playerProgress)
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
        PatronLogger:Warning("SmallTalkCore", "ValidateSingleCondition", "Unknown condition type", {
            condition_type = condition.Type
        })
        return false
    end
end

--[[==========================================================================
  УПРАВЛЕНИЕ КЭШЕМ
============================================================================]]

-- Очистить кэш для игрока (вызывается при изменении состояния игрока)
function PatronSmallTalkCore.InvalidatePlayerCache(playerGuid, patronId)
    if not SMALLTALK_CONFIG.CACHE_ENABLED then
        return
    end
    
    if patronId then
        -- Очистить кэш для конкретного покровителя
        local cacheKey = playerGuid .. "_" .. patronId
        if playerSmallTalkCache[cacheKey] then
            playerSmallTalkCache[cacheKey] = nil
            cacheStats.invalidations = cacheStats.invalidations + 1
            
            PatronLogger:Debug("SmallTalkCore", "InvalidatePlayerCache", "Cache invalidated for patron", {
                player_guid = playerGuid,
                patron_id = patronId
            })
        end
    else
        -- Очистить весь кэш игрока
        local invalidatedCount = 0
        for cacheKey, _ in pairs(playerSmallTalkCache) do
            if string.find(cacheKey, "^" .. playerGuid .. "_") then
                playerSmallTalkCache[cacheKey] = nil
                invalidatedCount = invalidatedCount + 1
            end
        end
        
        if invalidatedCount > 0 then
            cacheStats.invalidations = cacheStats.invalidations + invalidatedCount
            PatronLogger:Debug("SmallTalkCore", "InvalidatePlayerCache", "Full player cache invalidated", {
                player_guid = playerGuid,
                invalidated_count = invalidatedCount
            })
        end
    end
end

-- Полная очистка кэша
function PatronSmallTalkCore.ClearCache()
    local cacheSize = 0
    for _ in pairs(playerSmallTalkCache) do
        cacheSize = cacheSize + 1
    end
    
    playerSmallTalkCache = {}
    cacheStats.invalidations = cacheStats.invalidations + cacheSize
    
    PatronLogger:Info("SmallTalkCore", "ClearCache", "Full cache cleared", {
        cleared_entries = cacheSize
    })
end

--[[==========================================================================
  ИНТЕГРАЦИЯ С СИСТЕМОЙ СОБЫТИЙ
============================================================================]]

-- Обновить SmallTalk после выполнения действий или достижения MajorNode
function PatronSmallTalkCore.OnPlayerProgressChanged(playerGuid, patronId, changeType)
    -- Инвалидируем кэш
    PatronSmallTalkCore.InvalidatePlayerCache(playerGuid, patronId)
    
    PatronLogger:Debug("SmallTalkCore", "OnPlayerProgressChanged", "Player progress changed", {
        player_guid = playerGuid,
        patron_id = patronId,
        change_type = changeType
    })
end

-- Получить новую SmallTalk фразу после изменений (для отправки клиенту)
function PatronSmallTalkCore.RefreshSmallTalkForClient(player, patronId)
    local newSmallTalk = PatronSmallTalkCore.SelectRandomSmallTalk(player, patronId)
    
    PatronLogger:Info("SmallTalkCore", "RefreshSmallTalkForClient", "SmallTalk refreshed", {
        player = player:GetName(),
        patron_id = patronId,
        new_smalltalk_preview = string.sub(newSmallTalk, 1, 30) .. "..."
    })
    
    return newSmallTalk
end

--[[==========================================================================
  СТАТИСТИКА И ДИАГНОСТИКА
============================================================================]]

-- Получить статистику модуля
function PatronSmallTalkCore.GetStats()
    local cacheHitRatio = cacheStats.hits > 0 and 
        math.floor((cacheStats.hits / (cacheStats.hits + cacheStats.misses)) * 100) or 0
    
    local cacheSize = 0
    for _ in pairs(playerSmallTalkCache) do
        cacheSize = cacheSize + 1
    end
    
    return {
        cache_hits = cacheStats.hits,
        cache_misses = cacheStats.misses,
        cache_invalidations = cacheStats.invalidations,
        cache_hit_ratio = cacheHitRatio,
        cache_size = cacheSize,
        config = SMALLTALK_CONFIG
    }
end

-- Показать статистику для отладки
function PatronSmallTalkCore.ShowStats()
    local stats = PatronSmallTalkCore.GetStats()
    PatronLogger:Info("SmallTalkCore", "ShowStats", "SmallTalk Core statistics", stats)
end

-- Показать все доступные SmallTalk для игрока (для отладки)
function PatronSmallTalkCore.DebugShowAvailableSmallTalks(player, patronId)
    local availableSmallTalks = PatronSmallTalkCore.GetAvailableSmallTalks(player, patronId)
    
    PatronLogger:Info("SmallTalkCore", "DebugShowAvailableSmallTalks", "Available SmallTalks for debug", {
        player = player:GetName(),
        patron_id = patronId,
        count = #availableSmallTalks
    })
    
    for i, smallTalk in ipairs(availableSmallTalks) do
        PatronLogger:Info("SmallTalkCore", "DebugShowAvailableSmallTalks", "SmallTalk " .. i, {
            replica = smallTalk.replica,
            priority = smallTalk.priority
        })
    end
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

-- Подсчитываем общее количество SmallTalk
local totalSmallTalks = 0
local conditionalSmallTalks = 0
local patronsWithSmallTalks = 0

for patronId, smallTalkList in pairs(SmallTalksData) do
    patronsWithSmallTalks = patronsWithSmallTalks + 1
    for _, smallTalk in ipairs(smallTalkList) do
        totalSmallTalks = totalSmallTalks + 1
        if smallTalk.Conditions and #smallTalk.Conditions > 0 then
            conditionalSmallTalks = conditionalSmallTalks + 1
        end
    end
end

PatronLogger:Info("SmallTalkCore", "Initialize", "SmallTalk core module loaded successfully", {
    total_smalltalks = totalSmallTalks,
    conditional_smalltalks = conditionalSmallTalks,
    patrons_with_smalltalks = patronsWithSmallTalks,
    cache_enabled = SMALLTALK_CONFIG.CACHE_ENABLED,
    selection_logging = SMALLTALK_CONFIG.LOG_SELECTION,
    filtering_logging = SMALLTALK_CONFIG.LOG_FILTERING,
    priority_multiplier = SMALLTALK_CONFIG.PRIORITY_WEIGHT_MULTIPLIER
})

print("|cff00ff00[PatronSystem]|r SmallTalk Core v1.0 loaded successfully - Dynamic context-aware phrases ready!")