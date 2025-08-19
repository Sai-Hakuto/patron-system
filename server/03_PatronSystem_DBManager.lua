--[[==========================================================================
  PATRON SYSTEM - DATABASE MANAGER v3.0 (ПРОВЕРЕННЫЕ МЕТОДЫ)
  Все методы протестированы в patron_system_db_operations_101
  Безопасная работа с БД, JSON парсинг, кэширование
============================================================================]]

-- Загружаем зависимости
local json_loaded, json = pcall(require, "dkjson")
if not json_loaded then
    error("КРИТИЧЕСКАЯ ОШИБКА: dkjson не найден! DBManager не может работать без JSON поддержки.")
end

-- Проверяем наличие логгера
if not PatronLogger then
    error("КРИТИЧЕСКАЯ ОШИБКА: PatronLogger не загружен! Загрузите 01_PatronSystem_Logger.lua первым.")
end

-- Создаем модуль
PatronDBManager = PatronDBManager or {}

--[[==========================================================================
  КОНФИГУРАЦИЯ И СОСТОЯНИЕ
============================================================================]]

local DB_CONFIG = {
    TABLE_NAME = "custom_patron_system_progress",
    CACHE_EXPIRY_SECONDS = 300,        -- 5 минут кэш
    MAX_JSON_SIZE = 50000,             -- Максимальный размер JSON поля
    RETRY_COUNT = 3,                   -- Повторные попытки при ошибке
    ENABLE_CACHE = true                -- Включить кэширование
}

-- Кэш данных игроков в памяти
local playerDataCache = {}
local playerCacheTimestamps = {}

-- Статистика работы
local dbStats = {
    queriesExecuted = 0,
    cacheHits = 0,
    cacheMisses = 0,
    errors = 0
}

--[[==========================================================================
  УТИЛИТЫ ДЛЯ БЕЗОПАСНОЙ РАБОТЫ С БД
============================================================================]]

-- Безопасное выполнение SQL запроса с логированием
function PatronDBManager.SafeQuery(sql, operation)
    local startTime = os.clock()
    
    local success, result = pcall(function()
        return WorldDBQuery(sql)
    end)
    
    local duration = math.floor((os.clock() - startTime) * 1000)
    dbStats.queriesExecuted = dbStats.queriesExecuted + 1
    
    if success then
        PatronLogger:SQL("DBManager", operation or "Query", "SUCCESS", duration)
        return result
    else
        dbStats.errors = dbStats.errors + 1
        PatronLogger:Error("DBManager", operation or "Query", "SQL execution failed", {
            error = tostring(result),
            sql_preview = string.sub(sql, 1, 100) .. "..."
        })
        return nil
    end
end

-- Безопасное выполнение SQL команды
function PatronDBManager.SafeExecute(sql, operation)
    local startTime = os.clock()
    
    local success, error_msg = pcall(function()
        WorldDBExecute(sql)
        return true
    end)
    
    local duration = math.floor((os.clock() - startTime) * 1000)
    dbStats.queriesExecuted = dbStats.queriesExecuted + 1
    
    if success then
        PatronLogger:SQL("DBManager", operation or "Execute", "SUCCESS", duration)
        return true
    else
        dbStats.errors = dbStats.errors + 1
        PatronLogger:Error("DBManager", operation or "Execute", "SQL execution failed", {
            error = tostring(error_msg),
            sql_preview = string.sub(sql, 1, 100) .. "..."
        })
        return false
    end
end

-- Безопасное получение строки из результата
function PatronDBManager.SafeGetString(result, index, defaultValue, fieldName)
    local success, value = pcall(function() 
        return result:GetString(index) 
    end)
    
    if success and value then
        PatronLogger:Verbose("DBManager", "SafeGetString", "Field retrieved", {
            field = fieldName or index,
            length = string.len(value)
        })
        return value
    else
        PatronLogger:Warning("DBManager", "SafeGetString", "Field read failed", {
            field = fieldName or index,
            using_default = defaultValue or "empty"
        })
        return defaultValue or ""
    end
end

-- Безопасное получение числа из результата
function PatronDBManager.SafeGetUInt32(result, index, defaultValue, fieldName)
    local success, value = pcall(function() 
        return result:GetUInt32(index) 
    end)
    
    if success and value then
        PatronLogger:Verbose("DBManager", "SafeGetUInt32", "Field retrieved", {
            field = fieldName or index,
            value = value
        })
        return value
    else
        PatronLogger:Warning("DBManager", "SafeGetUInt32", "Field read failed", {
            field = fieldName or index,
            using_default = defaultValue or 0
        })
        return defaultValue or 0
    end
end

--[[==========================================================================
  JSON УТИЛИТЫ (БЕЗОПАСНЫЕ)
============================================================================]]

-- Безопасная JSON сериализация
function PatronDBManager.SafeEncodeJSON(data, fieldName)
    if not data then
        return "{}"
    end
    
    local success, result = pcall(json.encode, data)
    if success and result then
        -- Проверяем размер
        if string.len(result) > DB_CONFIG.MAX_JSON_SIZE then
            PatronLogger:Warning("DBManager", "SafeEncodeJSON", "JSON too large", {
                field = fieldName,
                size = string.len(result),
                max_size = DB_CONFIG.MAX_JSON_SIZE
            })
            return "{}"
        end
        
        -- Экранируем для SQL
        result = result:gsub("\\", "\\\\"):gsub("'", "\\'")
        
        PatronLogger:JSON("DBManager", "SafeEncodeJSON", "encode", true, {
            field = fieldName,
            size = string.len(result)
        })
        return result
    else
        PatronLogger:JSON("DBManager", "SafeEncodeJSON", "encode", false, {
            field = fieldName,
            error = tostring(result)
        })
        return "{}"
    end
end

-- Безопасный JSON парсинг
function PatronDBManager.SafeDecodeJSON(jsonString, fieldName)
    if not jsonString or jsonString == "" or jsonString == "null" then
        return {}
    end
    
    local success, result = pcall(json.decode, jsonString)
    if success and result then
        PatronLogger:JSON("DBManager", "SafeDecodeJSON", "decode", true, {
            field = fieldName,
            size = string.len(jsonString)
        })
        return result
    else
        PatronLogger:JSON("DBManager", "SafeDecodeJSON", "decode", false, {
            field = fieldName,
            error = tostring(result)
        })
        return {}
    end
end

--[[==========================================================================
  КЭШИРОВАНИЕ ДАННЫХ ИГРОКОВ
============================================================================]]

-- Получить ключ кэша для игрока
function PatronDBManager.GetCacheKey(playerGuid)
    return "player_" .. tostring(playerGuid)
end

-- Проверить, актуален ли кэш
function PatronDBManager.IsCacheValid(playerGuid)
    if not DB_CONFIG.ENABLE_CACHE then
        return false
    end
    
    local cacheKey = PatronDBManager.GetCacheKey(playerGuid)
    local timestamp = playerCacheTimestamps[cacheKey]
    
    if not timestamp then
        return false
    end
    
    return (os.time() - timestamp) < DB_CONFIG.CACHE_EXPIRY_SECONDS
end

-- Сохранить данные в кэш
function PatronDBManager.CachePlayerData(playerGuid, data)
    if not DB_CONFIG.ENABLE_CACHE then
        return
    end
    
    local cacheKey = PatronDBManager.GetCacheKey(playerGuid)
    playerDataCache[cacheKey] = data
    playerCacheTimestamps[cacheKey] = os.time()
    
    PatronLogger:Debug("DBManager", "CachePlayerData", "Data cached", {
        player_guid = playerGuid,
        cache_key = cacheKey
    })
end

-- Получить данные из кэша
function PatronDBManager.GetCachedPlayerData(playerGuid)
    if not DB_CONFIG.ENABLE_CACHE then
        return nil
    end
    
    local cacheKey = PatronDBManager.GetCacheKey(playerGuid)
    
    if PatronDBManager.IsCacheValid(playerGuid) then
        dbStats.cacheHits = dbStats.cacheHits + 1
        PatronLogger:Debug("DBManager", "GetCachedPlayerData", "Cache hit", {
            player_guid = playerGuid
        })
        return playerDataCache[cacheKey]
    else
        dbStats.cacheMisses = dbStats.cacheMisses + 1
        PatronLogger:Debug("DBManager", "GetCachedPlayerData", "Cache miss", {
            player_guid = playerGuid
        })
        return nil
    end
end

-- Очистить кэш игрока
function PatronDBManager.ClearPlayerCache(playerGuid)
    local cacheKey = PatronDBManager.GetCacheKey(playerGuid)
    playerDataCache[cacheKey] = nil
    playerCacheTimestamps[cacheKey] = nil
    
    PatronLogger:Debug("DBManager", "ClearPlayerCache", "Cache cleared", {
        player_guid = playerGuid
    })
end

--[[==========================================================================
  ОСНОВНЫЕ CRUD ОПЕРАЦИИ
============================================================================]]

-- Проверка существования игрока
function PatronDBManager.PlayerExists(playerGuid)
    local sql = string.format("SELECT 1 FROM %s WHERE character_guid = '%s'", 
        DB_CONFIG.TABLE_NAME, tostring(playerGuid))
    
    local result = PatronDBManager.SafeQuery(sql, "PlayerExists")
    local exists = (result ~= nil)
    
    PatronLogger:Info("DBManager", "PlayerExists", "Check completed", {
        player_guid = playerGuid,
        exists = exists
    })
    
    return exists
end

-- Загрузка полного прогресса игрока
function PatronDBManager.LoadPlayerProgress(playerGuid)
    -- Проверяем кэш
    local cachedData = PatronDBManager.GetCachedPlayerData(playerGuid)
    if cachedData then
        return cachedData
    end
    
    local sql = string.format([[
        SELECT 
            CAST(blessings AS CHAR) AS blessings,
            CAST(patrons AS CHAR) AS patrons,
            CAST(followers AS CHAR) AS followers,
            souls, suffering,
            COALESCE(CAST(created_at AS CHAR), '') AS created_at,
            COALESCE(CAST(updated_at AS CHAR), '') AS updated_at
        FROM %s WHERE character_guid='%s'
    ]], DB_CONFIG.TABLE_NAME, tostring(playerGuid))
    
    local result = PatronDBManager.SafeQuery(sql, "LoadPlayerProgress")
    if not result then
        PatronLogger:Warning("DBManager", "LoadPlayerProgress", "Player not found", {
            player_guid = playerGuid
        })
        return nil
    end
    
    -- Безопасное чтение полей
    local blessingsJSON = PatronDBManager.SafeGetString(result, 0, "{}", "blessings")
    local patronsJSON = PatronDBManager.SafeGetString(result, 1, "{}", "patrons")
    local followersJSON = PatronDBManager.SafeGetString(result, 2, "{}", "followers")
    local souls = PatronDBManager.SafeGetUInt32(result, 3, 0, "souls")
    local suffering = PatronDBManager.SafeGetUInt32(result, 4, 0, "suffering")
    local createdAt = PatronDBManager.SafeGetString(result, 5, "", "created_at")
    local updatedAt = PatronDBManager.SafeGetString(result, 6, "", "updated_at")
    
    -- Парсинг JSON данных
    local progressData = {
        blessings = PatronDBManager.SafeDecodeJSON(blessingsJSON, "blessings"),
        patrons = PatronDBManager.SafeDecodeJSON(patronsJSON, "patrons"),
        followers = PatronDBManager.SafeDecodeJSON(followersJSON, "followers"),
        souls = souls,
        suffering = suffering,
        createdAt = createdAt,
        lastUpdated = updatedAt
    }
    
    -- Нормализация данных
    progressData = PatronDBManager.NormalizePlayerData(progressData)
    
    -- Сохраняем в кэш
    PatronDBManager.CachePlayerData(playerGuid, progressData)
    
    PatronLogger:Info("DBManager", "LoadPlayerProgress", "Progress loaded", {
        player_guid = playerGuid,
        souls = souls,
        suffering = suffering
    })
    
    return progressData
end

-- Сохранение полного прогресса игрока
function PatronDBManager.SavePlayerProgress(playerGuid, data)
    -- Валидация данных
    if not PatronDBManager.ValidatePlayerData(data) then
        PatronLogger:Error("DBManager", "SavePlayerProgress", "Invalid data provided")
        return false
    end
    
    local blessingsJSON = PatronDBManager.SafeEncodeJSON(data.blessings, "blessings")
    local patronsJSON = PatronDBManager.SafeEncodeJSON(data.patrons, "patrons")
    local followersJSON = PatronDBManager.SafeEncodeJSON(data.followers, "followers")
    
    local sql = string.format([[
        INSERT INTO %s (character_guid, blessings, patrons, followers, souls, suffering)
        VALUES ('%s','%s','%s','%s',%d,%d)
        ON DUPLICATE KEY UPDATE
          blessings = VALUES(blessings),
          patrons = VALUES(patrons),
          followers = VALUES(followers),
          souls = VALUES(souls),
          suffering = VALUES(suffering),
          updated_at = CURRENT_TIMESTAMP
    ]], DB_CONFIG.TABLE_NAME, tostring(playerGuid),
        blessingsJSON, patronsJSON, followersJSON,
        data.souls or 0, data.suffering or 0)
    
    local success = PatronDBManager.SafeExecute(sql, "SavePlayerProgress")
    
    if success then
        -- Обновляем кэш
        PatronDBManager.CachePlayerData(playerGuid, data)
        
        PatronLogger:Info("DBManager", "SavePlayerProgress", "Progress saved", {
            player_guid = playerGuid,
            souls = data.souls or 0,
            suffering = data.suffering or 0
        })
    end
    
    return success
end

-- Быстрое обновление только ресурсов
function PatronDBManager.UpdateResources(playerGuid, souls, suffering)
    local sql = string.format([[
        UPDATE %s SET souls = %d, suffering = %d, updated_at = CURRENT_TIMESTAMP 
        WHERE character_guid = '%s'
    ]], DB_CONFIG.TABLE_NAME, souls or 0, suffering or 0, tostring(playerGuid))
    
    local success = PatronDBManager.SafeExecute(sql, "UpdateResources")
    
    if success then
        -- Обновляем кэш если он есть
        local cachedData = PatronDBManager.GetCachedPlayerData(playerGuid)
        if cachedData then
            cachedData.souls = souls
            cachedData.suffering = suffering
            PatronDBManager.CachePlayerData(playerGuid, cachedData)
        end
        
        PatronLogger:Info("DBManager", "UpdateResources", "Resources updated", {
            player_guid = playerGuid,
            souls = souls,
            suffering = suffering
        })
    end
    
    return success
end

--[[==========================================================================
  АТОМАРНЫЕ ОПЕРАЦИИ ДЛЯ ОБНОВЛЕНИЯ КОНКРЕТНЫХ ПОЛЕЙ
============================================================================]]

-- Обновление конкретного поля в JSON структуре
function PatronDBManager.UpdateJSONField(playerGuid, jsonFieldName, keyPath, newValue)
    local progressData = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not progressData then
        PatronLogger:Error("DBManager", "UpdateJSONField", "Player data not found")
        return false
    end
    
    -- Навигация по пути ключей (например, {"patrons", "1", "currentDialogue"})
    local current = progressData
    for i = 1, #keyPath - 1 do
        local key = tostring(keyPath[i])
        if not current[key] then
            current[key] = {}
        end
        current = current[key]
    end
    
    -- Устанавливаем значение
    local finalKey = tostring(keyPath[#keyPath])
    current[finalKey] = newValue
    
    local success = PatronDBManager.SavePlayerProgress(playerGuid, progressData)
    
    if success then
        PatronLogger:Debug("DBManager", "UpdateJSONField", "Field updated", {
            player_guid = playerGuid,
            field = jsonFieldName,
            key_path = table.concat(keyPath, "."),
            new_value = tostring(newValue)
        })
    end
    
    return success
end

-- Добавление элемента в массив внутри JSON
function PatronDBManager.AddToJSONArray(playerGuid, keyPath, newElement)
    local progressData = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not progressData then
        return false
    end
    
    -- Навигация к массиву
    local current = progressData
    for i = 1, #keyPath - 1 do
        local key = tostring(keyPath[i])
        if not current[key] then
            current[key] = {}
        end
        current = current[key]
    end
    
    -- Получаем массив
    local arrayKey = tostring(keyPath[#keyPath])
    if not current[arrayKey] then
        current[arrayKey] = {}
    end
    
    -- Проверяем, что элемента еще нет в массиве
    local exists = false
    for _, item in ipairs(current[arrayKey]) do
        if item == newElement then
            exists = true
            break
        end
    end
    
    if not exists then
        table.insert(current[arrayKey], newElement)
    end
    
    local success = PatronDBManager.SavePlayerProgress(playerGuid, progressData)
    
    if success then
        PatronLogger:Debug("DBManager", "AddToJSONArray", "Element added to array", {
            player_guid = playerGuid,
            key_path = table.concat(keyPath, "."),
            element = tostring(newElement),
            was_duplicate = exists
        })
    end
    
    return success
end

-- Инкремент числового поля в JSON структуре
function PatronDBManager.IncrementJSONField(playerGuid, keyPath, increment)
    local progressData = PatronDBManager.LoadPlayerProgress(playerGuid)
    if not progressData then
        return false
    end
    
    -- Навигация к полю
    local current = progressData
    for i = 1, #keyPath - 1 do
        local key = tostring(keyPath[i])
        if not current[key] then
            current[key] = {}
        end
        current = current[key]
    end
    
    -- Инкрементируем поле
    local fieldKey = tostring(keyPath[#keyPath])
    local currentValue = current[fieldKey] or 0
    current[fieldKey] = currentValue + increment
    
    local success = PatronDBManager.SavePlayerProgress(playerGuid, progressData)
    
    if success then
        PatronLogger:Debug("DBManager", "IncrementJSONField", "Field incremented", {
            player_guid = playerGuid,
            key_path = table.concat(keyPath, "."),
            increment = increment,
            old_value = currentValue,
            new_value = current[fieldKey]
        })
    end
    
    return success, current[fieldKey]
end

--[[==========================================================================
  ВАЛИДАЦИЯ И НОРМАЛИЗАЦИЯ ДАННЫХ
============================================================================]]

-- Валидация данных игрока
function PatronDBManager.ValidatePlayerData(data)
    if type(data) ~= "table" then
        PatronLogger:Warning("DBManager", "ValidatePlayerData", "Data is not a table")
        return false
    end
    
    -- Проверяем основные поля
    local requiredFields = {"souls", "suffering", "patrons", "followers", "blessings"}
    for _, field in ipairs(requiredFields) do
        if data[field] == nil then
            PatronLogger:Warning("DBManager", "ValidatePlayerData", "Missing required field", {
                field = field
            })
            return false
        end
    end
    
    -- Проверяем типы
    if type(data.souls) ~= "number" or type(data.suffering) ~= "number" then
        PatronLogger:Warning("DBManager", "ValidatePlayerData", "Invalid resource types")
        return false
    end
    
    if type(data.patrons) ~= "table" or type(data.followers) ~= "table" or type(data.blessings) ~= "table" then
        PatronLogger:Warning("DBManager", "ValidatePlayerData", "Invalid table field types")
        return false
    end
    
    return true
end

-- Нормализация данных после загрузки
function PatronDBManager.NormalizePlayerData(data)
    -- Исправляем типы данных
    if type(data.blessings) ~= "table" then
        data.blessings = {}
    end
    
    if type(data.patrons) ~= "table" then
        data.patrons = {}
    end
    
    if type(data.followers) ~= "table" then
        data.followers = {}
    end
    
    -- Преобразуем числовые ключи в строки для консистентности
    local function normalizeKeys(tbl)
        local normalized = {}
        for k, v in pairs(tbl) do
            normalized[tostring(k)] = v
        end
        return normalized
    end
    
    data.blessings = normalizeKeys(data.blessings)
    data.patrons = normalizeKeys(data.patrons)
    data.followers = normalizeKeys(data.followers)
    
    -- Нормализуем структуру followers
    for followerId, followerData in pairs(data.followers) do
        if type(followerData.isActive) ~= "boolean" then
            followerData.isActive = false
        end
        if type(followerData.isDiscovered) ~= "boolean" then
            followerData.isDiscovered = false
        end
    end
    
    PatronLogger:Debug("DBManager", "NormalizePlayerData", "Data normalized")
    return data
end

--[[==========================================================================
  СТАТИСТИКА И ДИАГНОСТИКА
============================================================================]]

-- Получить статистику работы БД
function PatronDBManager.GetStats()
    return {
        queries_executed = dbStats.queriesExecuted,
        cache_hits = dbStats.cacheHits,
        cache_misses = dbStats.cacheMisses,
        errors = dbStats.errors,
        cache_hit_ratio = dbStats.cacheHits > 0 and 
            math.floor((dbStats.cacheHits / (dbStats.cacheHits + dbStats.cacheMisses)) * 100) or 0
    }
end

-- Показать статистику
function PatronDBManager.ShowStats()
    local stats = PatronDBManager.GetStats()
    PatronLogger:Info("DBManager", "ShowStats", "Database statistics", stats)
end

-- Очистить весь кэш
function PatronDBManager.ClearAllCache()
    playerDataCache = {}
    playerCacheTimestamps = {}
    PatronLogger:Info("DBManager", "ClearAllCache", "All cache cleared")
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

PatronLogger:Info("DBManager", "Initialize", "Patron DB Manager v3.0 loaded", {
    json_available = json_loaded,
    cache_enabled = DB_CONFIG.ENABLE_CACHE,
    table_name = DB_CONFIG.TABLE_NAME
})