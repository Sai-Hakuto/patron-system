--[[==========================================================================
  PATRON SYSTEM - CONFIGURATION MODULE v1.0 (НОВАЯ АРХИТЕКТУРА)
  Централизованная конфигурация всех модулей системы покровителей
============================================================================]]

-- Создаем глобальный модуль конфигурации
PatronSystemConfig = PatronSystemConfig or {}

--[[==========================================================================
  ОСНОВНЫЕ НАСТРОЙКИ СИСТЕМЫ
============================================================================]]

-- Версия и основные параметры
PatronSystemConfig.VERSION = "1.0.0"
PatronSystemConfig.BUILD_DATE = "2024-01-01"
PatronSystemConfig.ADDON_PREFIX = "PatronSystem"

-- Режимы работы
PatronSystemConfig.DEBUG_MODE = false               -- Глобальный режим отладки
PatronSystemConfig.DEVELOPMENT_MODE = false        -- Режим разработки (больше логов)
PatronSystemConfig.PERFORMANCE_MODE = true         -- Режим производительности

--[[==========================================================================
  НАСТРОЙКИ ЛОГИРОВАНИЯ (ДЛЯ PatronLogger)
============================================================================]]

PatronSystemConfig.LOGGING = {
  ENABLED = true,
  LEVEL = "DEBUG",         -- DEBUG|INFO|WARN|ERROR
  AIO = { REQUESTS = true, RESPONSES = true },
}

--[[==========================================================================
  НАСТРОЙКИ БАЗЫ ДАННЫХ (ДЛЯ PatronDBManager)
============================================================================]]

PatronSystemConfig.DATABASE = {
    -- Основная таблица
    TABLE_NAME = "custom_patron_system_progress",   -- Имя таблицы в БД
    
    -- Кэширование
    CACHE_ENABLED = true,                           -- Включить кэширование
    CACHE_EXPIRY_SECONDS = 300,                     -- 5 минут жизни кэша
    CLEAR_CACHE_ON_LOGOUT = true,                   -- Очищать кэш при выходе
    
    -- Безопасность и ограничения
    MAX_JSON_SIZE = 50000,                          -- Максимальный размер JSON поля
    RETRY_COUNT = 3,                                -- Повторные попытки при ошибке
    QUERY_TIMEOUT = 5,                              -- Таймаут запроса в секундах
    
    -- Оптимизация
    AUTO_SAVE_CHANGES = true,                       -- Автосохранение изменений
    BATCH_OPERATIONS = false,                       -- Пакетные операции (будущее)
    USE_TRANSACTIONS = false                        -- Транзакции (будущее)
}

--[[==========================================================================
  НАСТРОЙКИ ДИАЛОГОВ (ДЛЯ PatronDialogueCore)
============================================================================]]

PatronSystemConfig.DIALOGUE = {
    -- Кэширование диалогов
    CACHE_ENABLED = true,                           -- Кэшировать диалоговые узлы
    VALIDATE_STRUCTURE = true,                      -- Валидировать структуру диалогов
    
    -- Логирование
    LOG_NAVIGATION = true,                          -- Логировать навигацию по диалогам
    LOG_CONDITIONS = true,                          -- Логировать проверку условий
    
    -- Безопасность
    VALIDATE_PLAYER_CHOICES = true,                 -- Проверять выбор игрока
    CHECK_CHOICE_CONDITIONS = true,                 -- Проверять условия выбора
    
    -- Производительность
    PRELOAD_PATRON_DIALOGUES = false,               -- Предзагружать диалоги покровителей
    MAX_CACHE_SIZE = 100                            -- Максимум диалогов в кэше
}

--[[==========================================================================
  НАСТРОЙКИ ИГРОВОЙ ЛОГИКИ (ДЛЯ PatronGameLogicCore)
============================================================================]]

PatronSystemConfig.GAME_LOGIC = {
    -- Выполнение действий
    LOG_ACTIONS = true,                             -- Логировать выполнение действий
    LOG_RESOURCE_CHANGES = true,                    -- Логировать изменения ресурсов
    VALIDATE_ACTIONS = true,                        -- Валидировать параметры действий
    AUTO_SAVE_CHANGES = true,                       -- Автосохранение после действий
    
    -- Безопасность
    CHECK_PERMISSIONS = true,                       -- Проверять права на действия
    VALIDATE_RESOURCES = true,                      -- Проверять ресурсы перед тратой
    PREVENT_EXPLOITS = true,                        -- Защита от эксплойтов
    
    -- Лимиты ресурсов
    MAX_SOULS = 999999,                             -- Максимум душ
    MAX_SUFFERING = 999999,                         -- Максимум страданий
    MAX_RELATIONSHIP_POINTS = 2000,                 -- Максимум очков отношений
    
    -- Производительность
    BATCH_RESOURCE_UPDATES = false,                 -- Пакетные обновления ресурсов
    CACHE_PLAYER_STATS = true                       -- Кэшировать статистику игрока
}

--[[==========================================================================
  НАСТРОЙКИ AIO (ДЛЯ MAIN ФАЙЛА)
============================================================================]]

PatronSystemConfig.AIO = {
    -- Основные параметры
    PREFIX = "PatronSystem",                        -- Префикс AIO сообщений
    ENABLE_RETRY = true,                            -- Повторная отправка при ошибке
    MAX_MESSAGE_SIZE = 8192,                        -- Максимальный размер сообщения
    
    -- Безопасность
    VALIDATE_INCOMING = true,                       -- Валидировать входящие данные
    CHECK_PLAYER_PERMISSIONS = true,                -- Проверять права игрока
    RATE_LIMITING = true,                           -- Ограничение частоты запросов
    MAX_REQUESTS_PER_SECOND = 10,                   -- Максимум запросов в секунду
    
    -- Логирование
    LOG_INCOMING_REQUESTS = false,                  -- Логировать входящие запросы
    LOG_OUTGOING_RESPONSES = false,                 -- Логировать исходящие ответы
    LOG_ERRORS = true                               -- Логировать ошибки AIO
}

--[[==========================================================================
  НАСТРОЙКИ ИГРОВОГО ПРОЦЕССА
============================================================================]]

PatronSystemConfig.GAMEPLAY = {
    -- Покровители
    AUTO_INIT_PLAYER = true,                        -- Автоинициализация при входе
    STARTING_RELATIONSHIP_POINTS = 0,               -- Начальные очки отношений
    PRAYER_COOLDOWN_SECONDS = 3600,                 -- Кулдаун молитвы (1 час)
    
    -- Последователи
    MAX_ACTIVE_FOLLOWERS = 1,                       -- Максимум активных последователей
    FOLLOWER_LEVEL_CAP = 20,                        -- Максимальный уровень последователя
    
    -- Благословения
    MAX_BLESSING_SLOTS = 6,                         -- Максимум слотов благословений
    DEFAULT_BLESSING_COOLDOWN = 60,                 -- Стандартный кулдаун благословения
    
    -- Ресурсы
    STARTING_SOULS = 0,                             -- Начальное количество душ
    STARTING_SUFFERING = 0,                         -- Начальное количество страданий
    SOUL_DROP_CHANCE = 0.1,                         -- Шанс выпадения души с моба (10%)
    SUFFERING_DROP_CHANCE = 0.05                    -- Шанс выпадения страданий (5%)
}

--[[==========================================================================
  НАСТРОЙКИ РАЗРАБОТКИ И ОТЛАДКИ
============================================================================]]

PatronSystemConfig.DEVELOPMENT = {
    -- Тестирование
    ENABLE_TEST_COMMANDS = false,                   -- Включить тестовые команды
    ENABLE_DEBUG_PANELS = false,                    -- Включить панели отладки
    ALLOW_STATE_MANIPULATION = false,               -- Разрешить изменение состояния
    
    -- Производительность
    SHOW_PERFORMANCE_STATS = false,                 -- Показывать статистику производительности
    MEASURE_EXECUTION_TIME = false,                 -- Измерять время выполнения
    LOG_MEMORY_USAGE = false,                       -- Логировать использование памяти
    
    -- Отладка
    DUMP_PLAYER_DATA = false,                       -- Дампить данные игрока
    VALIDATE_DATA_INTEGRITY = false,                -- Проверять целостность данных
    TRACE_EXECUTION_FLOW = false                    -- Трассировать поток выполнения
}

--[[==========================================================================
  МЕТОДЫ УПРАВЛЕНИЯ КОНФИГУРАЦИЕЙ
============================================================================]]

-- Получить значение конфигурации по пути
function PatronSystemConfig:Get(path, defaultValue)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        table.insert(keys, key)
    end
    
    local current = self
    for _, key in ipairs(keys) do
        if type(current) == "table" and current[key] ~= nil then
            current = current[key]
        else
            return defaultValue
        end
    end
    
    return current
end

-- Установить значение конфигурации по пути
function PatronSystemConfig:Set(path, value)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        table.insert(keys, key)
    end
    
    local current = self
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    
    local finalKey = keys[#keys]
    local oldValue = current[finalKey]
    current[finalKey] = value
    
    if PatronLogger then
        PatronLogger:Info("Config", "Set", "Configuration updated", {
            path = path,
            old_value = tostring(oldValue),
            new_value = tostring(value)
        })
    else
        print("[PatronSystemConfig] " .. path .. " = " .. tostring(value))
    end
end

-- Проверить, включена ли опция
function PatronSystemConfig:IsEnabled(path)
    return self:Get(path, false) == true
end

-- Получить числовое значение
function PatronSystemConfig:GetNumber(path, defaultValue)
    local value = self:Get(path, defaultValue)
    return type(value) == "number" and value or (defaultValue or 0)
end

-- Получить строковое значение
function PatronSystemConfig:GetString(path, defaultValue)
    local value = self:Get(path, defaultValue)
    return type(value) == "string" and value or (defaultValue or "")
end

-- Переключить булево значение
function PatronSystemConfig:Toggle(path)
    local currentValue = self:Get(path, false)
    self:Set(path, not currentValue)
    return not currentValue
end

--[[==========================================================================
  ПРОФИЛИ КОНФИГУРАЦИИ
============================================================================]]

-- Применить профиль "Разработка"
function PatronSystemConfig:ApplyDevelopmentProfile()
    self:Set("DEBUG_MODE", true)
    self:Set("LOGGING.DEBUG_MODE", true)
    self:Set("LOGGING.VERBOSE_MODE", true)
    self:Set("LOGGING.LOG_PERFORMANCE", true)
    self:Set("LOGGING.LOG_SQL", true)
    self:Set("LOGGING.LOG_AIO", true)
    self:Set("DEVELOPMENT.ENABLE_TEST_COMMANDS", true)
    self:Set("DEVELOPMENT.SHOW_PERFORMANCE_STATS", true)
    
    if PatronLogger then
        PatronLogger:Info("Config", "ApplyDevelopmentProfile", "Development profile activated")
    end
end

-- Применить профиль "Производство"
function PatronSystemConfig:ApplyProductionProfile()
    self:Set("DEBUG_MODE", false)
    self:Set("LOGGING.DEBUG_MODE", false)
    self:Set("LOGGING.VERBOSE_MODE", false)
    self:Set("LOGGING.LOG_PERFORMANCE", false)
    self:Set("LOGGING.LOG_SQL", false)
    self:Set("LOGGING.LOG_AIO", false)
    self:Set("DEVELOPMENT.ENABLE_TEST_COMMANDS", false)
    self:Set("DEVELOPMENT.SHOW_PERFORMANCE_STATS", false)
    self:Set("PERFORMANCE_MODE", true)
    
    if PatronLogger then
        PatronLogger:Info("Config", "ApplyProductionProfile", "Production profile activated")
    end
end

-- Применить профиль "Тестирование"
function PatronSystemConfig:ApplyTestingProfile()
    self:Set("DEBUG_MODE", true)
    self:Set("LOGGING.DEBUG_MODE", true)
    self:Set("LOGGING.VERBOSE_MODE", false)
    self:Set("DATABASE.CACHE_ENABLED", false) -- Отключаем кэш для чистых тестов
    self:Set("DEVELOPMENT.ENABLE_TEST_COMMANDS", true)
    self:Set("DEVELOPMENT.ALLOW_STATE_MANIPULATION", true)
    
    if PatronLogger then
        PatronLogger:Info("Config", "ApplyTestingProfile", "Testing profile activated")
    end
end

--[[==========================================================================
  ВАЛИДАЦИЯ КОНФИГУРАЦИИ
============================================================================]]

-- Проверить конфигурацию на корректность
function PatronSystemConfig:Validate()
    local warnings = {}
    local errors = {}
    
    -- Проверяем критичные настройки
    if not self:Get("DATABASE.TABLE_NAME") or self:Get("DATABASE.TABLE_NAME") == "" then
        table.insert(errors, "DATABASE.TABLE_NAME не может быть пустым")
    end
    
    if self:GetNumber("DATABASE.MAX_JSON_SIZE") < 1000 then
        table.insert(warnings, "DATABASE.MAX_JSON_SIZE слишком мал (< 1000)")
    end
    
    if self:GetNumber("DATABASE.CACHE_EXPIRY_SECONDS") < 60 then
        table.insert(warnings, "DATABASE.CACHE_EXPIRY_SECONDS слишком мал (< 60)")
    end
    
    if self:GetNumber("AIO.MAX_REQUESTS_PER_SECOND") > 100 then
        table.insert(warnings, "AIO.MAX_REQUESTS_PER_SECOND слишком высок (> 100)")
    end
    
    if self:GetNumber("GAMEPLAY.MAX_SOULS") > 9999999 then
        table.insert(warnings, "GAMEPLAY.MAX_SOULS может вызвать проблемы с БД")
    end
    
    -- Проверяем логические противоречия
    if self:IsEnabled("PERFORMANCE_MODE") and self:IsEnabled("LOGGING.VERBOSE_MODE") then
        table.insert(warnings, "PERFORMANCE_MODE и VERBOSE_MODE одновременно могут снизить производительность")
    end
    
    if not self:IsEnabled("DATABASE.CACHE_ENABLED") and self:IsEnabled("PERFORMANCE_MODE") then
        table.insert(warnings, "Отключенный кэш БД снижает производительность")
    end
    
    -- Выводим результаты
    for _, error in ipairs(errors) do
        if PatronLogger then
            PatronLogger:Error("Config", "Validate", error)
        else
            print("[CONFIG ERROR] " .. error)
        end
    end
    
    for _, warning in ipairs(warnings) do
        if PatronLogger then
            PatronLogger:Warning("Config", "Validate", warning)
        else
            print("[CONFIG WARNING] " .. warning)
        end
    end
    
    local isValid = #errors == 0
    
    if PatronLogger then
        PatronLogger:Info("Config", "Validate", "Configuration validation completed", {
            is_valid = isValid,
            error_count = #errors,
            warning_count = #warnings
        })
    end
    
    return isValid, warnings, errors
end

-- Показать текущую конфигурацию
function PatronSystemConfig:ShowConfig()
    local config = {
        version = self.VERSION,
        debug_mode = self.DEBUG_MODE,
        performance_mode = self.PERFORMANCE_MODE,
        database_table = self:Get("DATABASE.TABLE_NAME"),
        cache_enabled = self:Get("DATABASE.CACHE_ENABLED"),
        logging_level = self:IsEnabled("LOGGING.VERBOSE_MODE") and "VERBOSE" or 
                       (self:IsEnabled("LOGGING.DEBUG_MODE") and "DEBUG" or "INFO"),
        aio_prefix = self:Get("AIO.PREFIX")
    }
    
    if PatronLogger then
        PatronLogger:Info("Config", "ShowConfig", "Current configuration", config)
    else
        print("[PatronSystemConfig] Current Configuration:")
        for key, value in pairs(config) do
            print("  " .. key .. " = " .. tostring(value))
        end
    end
    
    return config
end

-- Сброс к значениям по умолчанию
function PatronSystemConfig:ResetToDefaults()
    if PatronLogger then
        PatronLogger:Warning("Config", "ResetToDefaults", "Resetting configuration to defaults")
    end
    
    -- Здесь можно было бы перезагрузить весь модуль, но это сложно
    -- Поэтому просто сбрасываем ключевые настройки
    self:Set("DEBUG_MODE", false)
    self:Set("LOGGING.DEBUG_MODE", false)
    self:Set("LOGGING.VERBOSE_MODE", false)
    self:Set("DATABASE.CACHE_ENABLED", true)
    self:Set("PERFORMANCE_MODE", true)
    
    if PatronLogger then
        PatronLogger:Info("Config", "ResetToDefaults", "Configuration reset completed")
    end
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]

-- Автоматическая валидация при загрузке
local function InitializeConfig()
    -- Ждем загрузки логгера если он еще не готов
    if PatronLogger then
        PatronLogger:Info("Config", "Initialize", "Patron System Config v1.0 loaded", {
            version = PatronSystemConfig.VERSION,
            build_date = PatronSystemConfig.BUILD_DATE
        })
        
        -- Валидируем конфигурацию
        local isValid, warnings, errors = PatronSystemConfig:Validate()
        if not isValid then
            PatronLogger:Error("Config", "Initialize", "Configuration validation failed - system may not work properly")
        end
        
        -- Показываем текущую конфигурацию если включен DEBUG
        if PatronSystemConfig:IsEnabled("DEBUG_MODE") then
            PatronSystemConfig:ShowConfig()
        end
    else
        print("[PatronSystemConfig] v" .. PatronSystemConfig.VERSION .. " loaded (Logger not available yet)")
    end
end

-- Экспортируем в глобальную область
_G.PatronSystemConfig = PatronSystemConfig

-- Инициализируем
InitializeConfig()

--[[==========================================================================
  ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ В ДРУГИХ МОДУЛЯХ
============================================================================]]

--[[

-- В PatronLogger:
local debugEnabled = PatronSystemConfig:IsEnabled("LOGGING.DEBUG_MODE")
local verboseEnabled = PatronSystemConfig:IsEnabled("LOGGING.VERBOSE_MODE")

-- В PatronDBManager:
local tableName = PatronSystemConfig:GetString("DATABASE.TABLE_NAME", "custom_patron_system_progress")
local cacheEnabled = PatronSystemConfig:IsEnabled("DATABASE.CACHE_ENABLED")
local cacheExpiry = PatronSystemConfig:GetNumber("DATABASE.CACHE_EXPIRY_SECONDS", 300)

-- В PatronDialogueCore:
local validateStructure = PatronSystemConfig:IsEnabled("DIALOGUE.VALIDATE_STRUCTURE")
local logNavigation = PatronSystemConfig:IsEnabled("DIALOGUE.LOG_NAVIGATION")

-- В PatronGameLogicCore:
local logActions = PatronSystemConfig:IsEnabled("GAME_LOGIC.LOG_ACTIONS")
local maxSouls = PatronSystemConfig:GetNumber("GAME_LOGIC.MAX_SOULS", 999999)

-- В Main файле:
local aioPrefix = PatronSystemConfig:GetString("AIO.PREFIX", "PatronSystem")
local validateIncoming = PatronSystemConfig:IsEnabled("AIO.VALIDATE_INCOMING")

--]]