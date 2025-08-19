--[[==========================================================================
  PATRON SYSTEM - DATA MANAGER (РЕФАКТОРИНГ ЭТАП 1)
  Единственный источник данных с централизованным кэшированием
============================================================================]]

-- Заполняем DataManager в уже созданном неймспейсе
PatronSystemNS.DataManager = {
    -- Состояние
    initialized = false,
    
    -- Кэши данных
    speakerCache = {},
    dialogueStateCache = {},
    blessingCache = {},
    
    -- НОВОЕ: Система callbacks для асинхронных запросов
    pendingRequests = {}, -- { "patron_1" = {callback1, callback2, ...} }
    
    -- Настройки кэширования
    cacheTimeout = 300, -- 5 минут
    maxCacheSize = 100
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.DataManager:Initialize()
    if self.initialized then return end
    
    PatronSystemNS.Logger:Info("DataManager инициализирован (РЕФАКТОРИНГ)")
    self.initialized = true
    
    -- Запускаем периодическую очистку кэша
    self:StartCacheCleanup()
end

--[[==========================================================================
  ОСНОВНОЙ МЕТОД - ЕДИНАЯ ТОЧКА ДЛЯ ВСЕХ ЗАПРОСОВ ДАННЫХ
============================================================================]]

-- НОВЫЙ ГЛАВНЫЙ МЕТОД: Получить данные или запросить если нет в кэше
function PatronSystemNS.DataManager:GetOrRequestSpeakerData(speakerID, speakerType, callback)
    local cacheKey = speakerType .. "_" .. speakerID
    
    PatronSystemNS.Logger:Data("GetOrRequestSpeakerData: " .. cacheKey)
    
    -- 1. Проверяем кэш
    local cachedData = self:GetFromCache(self.speakerCache, cacheKey)
    if cachedData then
        PatronSystemNS.Logger:Data("Данные найдены в кэше: " .. cacheKey)
        
        -- Данные есть в кэше - возвращаем сразу
        if callback then
            -- Вызываем callback асинхронно для единообразия
            C_Timer.After(0.01, function()
                callback(cachedData)
            end)
        end
        return cachedData
    end
    
    -- 2. Данных нет в кэше - нужно запрашивать
    PatronSystemNS.Logger:Data("Данных в кэше нет, запрашиваем: " .. cacheKey)
    
    -- 3. Проверяем, не идет ли уже запрос для этих данных
    if self.pendingRequests[cacheKey] then
        PatronSystemNS.Logger:Data("Запрос уже в процессе, добавляем callback: " .. cacheKey)
        
        -- Запрос уже идет - просто добавляем callback в очередь
        if callback then
            table.insert(self.pendingRequests[cacheKey], callback)
        end
        return nil -- данные придут асинхронно
    end
    
    -- 4. Создаем новый запрос
    PatronSystemNS.Logger:Data("Создаем новый запрос: " .. cacheKey)
    
    self.pendingRequests[cacheKey] = {}
    if callback then
        table.insert(self.pendingRequests[cacheKey], callback)
    end
    
    -- 5. Отправляем запрос на сервер
    self:RequestSpeakerDataFromServer(speakerID, speakerType)
    
    return nil -- данные придут асинхронно
end

--[[==========================================================================
  МЕТОДЫ ДЛЯ ОБРАТНОЙ СОВМЕСТИМОСТИ (DEPRECATED)
============================================================================]]

-- DEPRECATED: Используйте GetOrRequestSpeakerData() вместо этого
function PatronSystemNS.DataManager:GetSpeakerData(speakerID, speakerType)
    PatronSystemNS.Logger:Warn("DEPRECATED: GetSpeakerData() устарел, используйте GetOrRequestSpeakerData()")
    
    return self:GetOrRequestSpeakerData(speakerID, speakerType, function(data)
        -- Для обратной совместимости уведомляем UI старым способом
        if PatronSystemNS.UIManager then
            PatronSystemNS.UIManager:OnSpeakerDataReceived(data)
        end
    end)
end

--[[==========================================================================
  ОБРАБОТКА ПОЛУЧЕННЫХ ДАННЫХ С СЕРВЕРА
============================================================================]]

-- НОВЫЙ МЕТОД: Обработка данных, полученных с сервера
function PatronSystemNS.DataManager:OnDataReceived(speakerData)
    if not speakerData or not speakerData.SpeakerID or not speakerData.SpeakerType then
        PatronSystemNS.Logger:Error("Некорректные данные от сервера")
        return
    end
    
    local cacheKey = speakerData.SpeakerType .. "_" .. speakerData.SpeakerID
    
    PatronSystemNS.Logger:Data("Получены данные с сервера: " .. cacheKey)
    
    -- 1. Сохраняем в кэш
    self:SetToCache(self.speakerCache, cacheKey, speakerData)
    
    -- 2. Вызываем все ожидающие callbacks
    local callbacks = self.pendingRequests[cacheKey]
    if callbacks then
        PatronSystemNS.Logger:Data("Вызываем " .. #callbacks .. " ожидающих callbacks для " .. cacheKey)
        
        for _, callback in ipairs(callbacks) do
            if type(callback) == "function" then
                local success, err = pcall(callback, speakerData)
                if not success then
                    PatronSystemNS.Logger:Error("Ошибка в callback: " .. tostring(err))
                end
            end
        end
        
        -- Очищаем список ожидающих callbacks
        self.pendingRequests[cacheKey] = nil
    end
    
    PatronSystemNS.Logger:Data("Обработка данных завершена: " .. cacheKey)
end

-- УСТАРЕВШИЙ МЕТОД: Для обратной совместимости
function PatronSystemNS.DataManager:UpdateSpeakerCache(speakerData)
    PatronSystemNS.Logger:Warn("DEPRECATED: UpdateSpeakerCache() устарел, используйте OnDataReceived()")
    self:OnDataReceived(speakerData)
end

--[[==========================================================================
  СЕТЕВЫЕ ЗАПРОСЫ (ПРИВАТНЫЕ МЕТОДЫ)
============================================================================]]

-- Отправить запрос данных на сервер
function PatronSystemNS.DataManager:RequestSpeakerDataFromServer(speakerID, speakerType)
    PatronSystemNS.Logger:AIO("Запрос данных с сервера: " .. speakerID .. " (" .. speakerType .. ")")
    
    -- Используем совместимость со старым API
    if speakerType == PatronSystemNS.Config.SpeakerType.PATRON then
        AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestPatronData", speakerID)
    else
        AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestSpeakerData", {
            speakerID = speakerID,
            speakerType = speakerType
        })
    end
end

-- УСТАРЕВШИЙ МЕТОД: Для обратной совместимости
function PatronSystemNS.DataManager:RequestSpeakerData(speakerID, speakerType)
    PatronSystemNS.Logger:Warn("DEPRECATED: RequestSpeakerData() устарел")
    self:RequestSpeakerDataFromServer(speakerID, speakerType)
end

--[[==========================================================================
  СОСТОЯНИЕ ДИАЛОГОВ (БЕЗ ИЗМЕНЕНИЙ)
============================================================================]]

-- Получить состояние диалога
function PatronSystemNS.DataManager:GetDialogueState(speakerID, speakerType)
    local cacheKey = speakerType .. "_" .. speakerID
    return self:GetFromCache(self.dialogueStateCache, cacheKey)
end

-- Сохранить состояние диалога
function PatronSystemNS.DataManager:SaveDialogueState(speakerID, speakerType, nodeID)
    local cacheKey = speakerType .. "_" .. speakerID
    local stateData = {
        nodeID = nodeID,
        timestamp = time(),
        speakerID = speakerID,
        speakerType = speakerType
    }
    
    self:SetToCache(self.dialogueStateCache, cacheKey, stateData)
    PatronSystemNS.Logger:Data("Сохранено состояние диалога: " .. cacheKey .. " -> " .. nodeID)
    
    -- Отправляем на сервер для постоянного сохранения
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "SaveDialogueState", {
        speakerID = speakerID,
        speakerType = speakerType,
        nodeID = nodeID,
        timestamp = time()
    })
end

function PatronSystemNS.DataManager:RequestDialogueState(speakerID, speakerType)
    PatronSystemNS.Logger:AIO("Запрос состояния диалога: " .. speakerID .. " (" .. speakerType .. ")")
    
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "LoadDialogueState", {
        speakerID = speakerID,
        speakerType = speakerType
    })
end

--[[==========================================================================
  УПРАВЛЕНИЕ КЭШЕМ (БЕЗ ИЗМЕНЕНИЙ)
============================================================================]]

function PatronSystemNS.DataManager:GetFromCache(cache, key)
    local data = cache[key]
    if not data then
        return nil
    end
    
    -- Проверяем срок действия кэша
    if data.timestamp and (time() - data.timestamp) > self.cacheTimeout then
        cache[key] = nil
        PatronSystemNS.Logger:Data("Кэш устарел: " .. key)
        return nil
    end
    
    return data.data
end

function PatronSystemNS.DataManager:SetToCache(cache, key, data)
    cache[key] = {
        data = data,
        timestamp = time()
    }
    
    -- Проверяем размер кэша и очищаем старые записи
    self:CleanupCache(cache)
end

function PatronSystemNS.DataManager:CleanupCache(cache)
    local cacheSize = 0
    for _ in pairs(cache) do
        cacheSize = cacheSize + 1
    end
    
    if cacheSize <= self.maxCacheSize then
        return
    end
    
    -- Удаляем самые старые записи
    local entries = {}
    for key, entry in pairs(cache) do
        table.insert(entries, {key = key, timestamp = entry.timestamp})
    end
    
    table.sort(entries, function(a, b) return a.timestamp < b.timestamp end)
    
    local toRemove = cacheSize - self.maxCacheSize
    for i = 1, toRemove do
        cache[entries[i].key] = nil
    end
    
    PatronSystemNS.Logger:Data("Очищено записей кэша: " .. toRemove)
end

function PatronSystemNS.DataManager:ClearCache()
    self.speakerCache = {}
    self.dialogueStateCache = {}
    self.blessingCache = {}
    self.pendingRequests = {} -- НОВОЕ: Очищаем ожидающие запросы
    PatronSystemNS.Logger:Data("Весь кэш очищен")
end

function PatronSystemNS.DataManager:StartCacheCleanup()
    -- Периодическая очистка кэша каждые 5 минут
    C_Timer.NewTicker(300, function()
        PatronSystemNS.Logger:Data("Запуск периодической очистки кэша")
        
        -- Очищаем устаревшие записи
        for _, cache in pairs({self.speakerCache, self.dialogueStateCache, self.blessingCache}) do
            for key, entry in pairs(cache) do
                if entry.timestamp and (time() - entry.timestamp) > self.cacheTimeout then
                    cache[key] = nil
                end
            end
        end
        
        -- НОВОЕ: Очищаем старые pending запросы (на случай если что-то пошло не так)
        -- TODO: Добавить таймаут для pending запросов
    end)
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ (БЕЗ ИЗМЕНЕНИЙ)
============================================================================]]

function PatronSystemNS.DataManager:HasCachedData(speakerID, speakerType)
    local cacheKey = speakerType .. "_" .. speakerID
    return self:GetFromCache(self.speakerCache, cacheKey) ~= nil
end

function PatronSystemNS.DataManager:GetCachedData(speakerID, speakerType)
    local cacheKey = speakerType .. "_" .. speakerID
    return self:GetFromCache(self.speakerCache, cacheKey)
end

function PatronSystemNS.DataManager:IsValidSpeaker(speakerID, speakerType)
    return PatronSystemNS.Config:GetSpeakerByID(speakerID, speakerType) ~= nil
end

-- Обновить кэш прогресса игрока
function PatronSystemNS.DataManager:UpdatePlayerProgressCache(progressData)
    -- Сохраняем прогресс в специальном кэше
    self.playerProgressCache = progressData
    PatronSystemNS.Logger:Data("Кэш прогресса игрока обновлен")
end

-- Получить прогресс игрока из кэша
function PatronSystemNS.DataManager:GetPlayerProgress()
    return self.playerProgressCache
end

-- Получить данные покровителя с учетом прогресса
function PatronSystemNS.DataManager:GetPatronWithProgress(patronID)
    local progress = self:GetPlayerProgress()
    if not progress or not progress.patrons then
        return nil
    end
    
    return progress.patrons[tostring(patronID)]
end

function PatronSystemNS.DataManager:GetCacheStats()
    local stats = {}
    
    for cacheName, cache in pairs({
        speakers = self.speakerCache,
        dialogues = self.dialogueStateCache,
        blessings = self.blessingCache
    }) do
        local count = 0
        for _ in pairs(cache) do
            count = count + 1
        end
        stats[cacheName] = count
    end
    
    -- НОВОЕ: Статистика pending запросов
    local pendingCount = 0
    for _ in pairs(self.pendingRequests) do
        pendingCount = pendingCount + 1
    end
    stats.pending = pendingCount
    
    return stats
end

print("|cff00ff00[PatronSystem]|r DataManager загружен (РЕФАКТОРИНГ ЭТАП 1)")