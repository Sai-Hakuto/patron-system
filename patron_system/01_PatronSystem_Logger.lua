--[[==========================================================================
  PATRON SYSTEM - UNIVERSAL LOGGER v1.0
  Единая система логирования для всех модулей системы покровителей
  
  ИСПОЛЬЗОВАНИЕ:
  PatronLogger:Info("DBManager", "LoadPlayer", "Игрок загружен успешно")
  PatronLogger:Error("AIO", "HandleRequest", "Ошибка парсинга JSON", extraData)
  PatronLogger:Warning("GameLogic", "ValidateInput", "Подозрительный запрос")
  PatronLogger:Debug("Core", "ProcessAction", "Выполнение действия", {actionType = "ADD_MONEY"})
============================================================================]]

-- Создаем глобальный логгер
PatronLogger = PatronLogger or {}

-- Конфигурация логирования
local LOGGER_CONFIG = {
    ENABLED = true,
    DEBUG_MODE = false,           -- Показывать DEBUG сообщения
    VERBOSE_MODE = false,         -- Показывать VERBOSE сообщения  
    LOG_TO_FILE = false,          -- В будущем - запись в файл
    SHOW_TIMESTAMP = true,        -- Показывать время
    SHOW_MODULE = true,           -- Показывать модуль
    SHOW_METHOD = true            -- Показывать метод
}

-- Уровни логирования
PatronLogger.LogLevel = {
    ERROR = 1,      -- Критические ошибки
    WARNING = 2,    -- Предупреждения
    INFO = 3,       -- Информационные сообщения
    DEBUG = 4,      -- Отладочная информация
    VERBOSE = 5     -- Детальная отладка
}

-- Префиксы для разных уровней (БЕЗ ЭМОДЗИ)
local LOG_PREFIXES = {
    [PatronLogger.LogLevel.ERROR] = "[ERROR]",
    [PatronLogger.LogLevel.WARNING] = "[WARN]",
    [PatronLogger.LogLevel.INFO] = "[INFO]",
    [PatronLogger.LogLevel.DEBUG] = "[DEBUG]",
    [PatronLogger.LogLevel.VERBOSE] = "[VERBOSE]"
}

--[[==========================================================================
  ОСНОВНЫЕ МЕТОДЫ ЛОГИРОВАНИЯ
============================================================================]]

-- Универсальный метод логирования
function PatronLogger:Log(level, module, method, message, extraData)
    -- Проверяем, нужно ли логировать этот уровень
    if not self:ShouldLog(level) then
        return
    end
    
    -- Строим сообщение
    local logMessage = self:BuildLogMessage(level, module, method, message, extraData)
    
    -- Выводим в консоль
    print(logMessage)
    
    -- В будущем здесь может быть запись в файл или отправка на сервер
end

-- Проверка, нужно ли логировать сообщение данного уровня
function PatronLogger:ShouldLog(level)
    if not LOGGER_CONFIG.ENABLED then
        return false
    end
    
    if level == self.LogLevel.DEBUG and not LOGGER_CONFIG.DEBUG_MODE then
        return false
    end
    
    if level == self.LogLevel.VERBOSE and not LOGGER_CONFIG.VERBOSE_MODE then
        return false
    end
    
    return true
end

-- Построение финального сообщения для вывода
function PatronLogger:BuildLogMessage(level, module, method, message, extraData)
    local parts = {}
    
    -- Временная метка
    if LOGGER_CONFIG.SHOW_TIMESTAMP then
        table.insert(parts, "[" .. os.date("%H:%M:%S") .. "]")
    end
    
    -- Префикс уровня
    table.insert(parts, LOG_PREFIXES[level] or "[UNKNOWN]")
    
    -- Модуль
    if LOGGER_CONFIG.SHOW_MODULE and module then
        table.insert(parts, "[" .. tostring(module) .. "]")
    end
    
    -- Метод
    if LOGGER_CONFIG.SHOW_METHOD and method then
        table.insert(parts, "[" .. tostring(method) .. "]")
    end
    
    -- Основное сообщение
    table.insert(parts, tostring(message))
    
    -- Дополнительные данные
    if extraData then
        local extraStr = self:SerializeExtraData(extraData)
        if extraStr then
            table.insert(parts, "| " .. extraStr)
        end
    end
    
    return table.concat(parts, " ")
end

-- Сериализация дополнительных данных
function PatronLogger:SerializeExtraData(data)
    if type(data) == "table" then
        local items = {}
        for k, v in pairs(data) do
            table.insert(items, tostring(k) .. "=" .. tostring(v))
        end
        return "{" .. table.concat(items, ", ") .. "}"
    else
        return tostring(data)
    end
end

--[[==========================================================================
  УДОБНЫЕ МЕТОДЫ ДЛЯ РАЗНЫХ УРОВНЕЙ
============================================================================]]

-- Критические ошибки
function PatronLogger:Error(module, method, message, extraData)
    self:Log(self.LogLevel.ERROR, module, method, message, extraData)
end

-- Предупреждения
function PatronLogger:Warning(module, method, message, extraData)
    self:Log(self.LogLevel.WARNING, module, method, message, extraData)
end

-- Информационные сообщения
function PatronLogger:Info(module, method, message, extraData)
    self:Log(self.LogLevel.INFO, module, method, message, extraData)
end

-- Отладочная информация
function PatronLogger:Debug(module, method, message, extraData)
    self:Log(self.LogLevel.DEBUG, module, method, message, extraData)
end

-- Детальная отладка
function PatronLogger:Verbose(module, method, message, extraData)
    self:Log(self.LogLevel.VERBOSE, module, method, message, extraData)
end

--[[==========================================================================
  СПЕЦИАЛИЗИРОВАННЫЕ МЕТОДЫ
============================================================================]]

-- Логирование производительности
function PatronLogger:Performance(module, operation, timeMs, extraData)
    if not extraData then extraData = {} end
    extraData.duration_ms = timeMs
    self:Debug(module, "Performance", operation, extraData)
end

-- Логирование SQL операций
function PatronLogger:SQL(module, method, operation, timeMs, extraData)
    if not extraData then extraData = {} end
    extraData.sql_operation = operation
    extraData.duration_ms = timeMs
    self:Debug(module, method, "SQL: " .. operation, extraData)
end

-- Логирование AIO сообщений
function PatronLogger:AIO(module, method, message, extraData)
    self:Debug(module, method, "AIO: " .. message, extraData)
end

-- Логирование JSON операций
function PatronLogger:JSON(module, method, operation, success, extraData)
    local message = "JSON " .. operation .. ": " .. (success and "SUCCESS" or "FAILED")
    local level = success and self.LogLevel.DEBUG or self.LogLevel.WARNING
    self:Log(level, module, method, message, extraData)
end

--[[==========================================================================
  КОНФИГУРАЦИЯ И УПРАВЛЕНИЕ
============================================================================]]

-- Включить/выключить отладочный режим
function PatronLogger:SetDebugMode(enabled)
    LOGGER_CONFIG.DEBUG_MODE = enabled
    self:Info("Logger", "SetDebugMode", "Debug mode: " .. (enabled and "ON" or "OFF"))
end

-- Включить/выключить подробный режим
function PatronLogger:SetVerboseMode(enabled)
    LOGGER_CONFIG.VERBOSE_MODE = enabled
    self:Info("Logger", "SetVerboseMode", "Verbose mode: " .. (enabled and "ON" or "OFF"))
end

-- Включить/выключить логирование полностью
function PatronLogger:SetEnabled(enabled)
    LOGGER_CONFIG.ENABLED = enabled
    if enabled then
        print("[INFO] [Logger] [SetEnabled] Logging enabled")
    end
end

-- Получить текущую конфигурацию
function PatronLogger:GetConfig()
    return {
        enabled = LOGGER_CONFIG.ENABLED,
        debug_mode = LOGGER_CONFIG.DEBUG_MODE,
        verbose_mode = LOGGER_CONFIG.VERBOSE_MODE,
        show_timestamp = LOGGER_CONFIG.SHOW_TIMESTAMP,
        show_module = LOGGER_CONFIG.SHOW_MODULE,
        show_method = LOGGER_CONFIG.SHOW_METHOD
    }
end

-- Показать статистику логирования (если нужно)
function PatronLogger:ShowStats()
    self:Info("Logger", "ShowStats", "Logger is active", self:GetConfig())
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

-- Проверяем глобальные переменные
if not _G.PatronLogger then
    _G.PatronLogger = PatronLogger
end

-- Начальное сообщение
PatronLogger:Info("Logger", "Initialize", "Patron System Logger v1.0 loaded successfully")

-- Тестовые сообщения для проверки
PatronLogger:Debug("Logger", "Initialize", "Debug mode test message")
PatronLogger:Verbose("Logger", "Initialize", "Verbose mode test message")

print("[INFO] [Logger] [Initialize] PatronLogger ready for use")

--[[==========================================================================
  ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ (ЗАКОММЕНТИРОВАНЫ)
============================================================================]]

--[[
-- Основное использование:
PatronLogger:Info("DBManager", "LoadPlayer", "Player data loaded successfully")
PatronLogger:Error("AIO", "HandleRequest", "Invalid JSON received", {playerGuid = "12345"})
PatronLogger:Warning("GameLogic", "ValidateInput", "Suspicious request detected")

-- Специализированные методы:
PatronLogger:Performance("DBManager", "LoadPlayerProgress", 150, {playerGuid = "12345"})
PatronLogger:SQL("DBManager", "SavePlayer", "INSERT", 45)
PatronLogger:AIO("Server", "RequestPatronData", "Patron data sent to client")
PatronLogger:JSON("DBManager", "ParseProgress", "decode", true, {size = 1024})

-- Управление режимами:
PatronLogger:SetDebugMode(true)
PatronLogger:SetVerboseMode(false)
PatronLogger:ShowStats()
--]]