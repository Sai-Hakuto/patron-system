--[[==========================================================================
  PATRON SYSTEM - LOGGER MODULE
  Система логирования (загружается третьим)
============================================================================]]

-- Заполняем Logger в уже созданном неймспейсе
PatronSystemNS.Logger = {
    LogLevel = {
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        DEBUG = 4
    },
    currentLevel = nil, -- Будет установлен из конфига
    initialized = false
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.Logger:Initialize()
    if self.initialized then return end

    local lvlFromConfig = nil
    local cfg = PatronSystemNS.Config and PatronSystemNS.Config.Logger
    if cfg and cfg.level then
        local up = string.upper(tostring(cfg.level))
        lvlFromConfig = self.LogLevel[up]
    end

    if lvlFromConfig then
        self.currentLevel = lvlFromConfig
    elseif PatronSystemNS.Config and PatronSystemNS.Config.DEBUG_MODE then
        self.currentLevel = self.LogLevel.DEBUG    -- старое поведение
    else
        self.currentLevel = self.LogLevel.INFO
    end

    self.echoToChat = cfg and cfg.echoToChat or false
    self.initialized = true
    self:Info("Logger инициализирован (уровень: " .. self.currentLevel .. ")")
end

--[[==========================================================================
  ОСНОВНЫЕ ФУНКЦИИ ЛОГИРОВАНИЯ
============================================================================]]
function PatronSystemNS.Logger:Log(message, level)
    level = level or self.LogLevel.INFO
    
    -- Если логгер еще не инициализирован, используем DEBUG уровень
    local currentLevel = self.currentLevel or self.LogLevel.DEBUG
    
    if level > currentLevel then
        return
    end
    
    local prefixes = {
        [self.LogLevel.ERROR] = "|cffff0000[PatronSystem-ERROR]|r",
        [self.LogLevel.WARN] = "|cffffff00[PatronSystem-WARN]|r",
        [self.LogLevel.INFO] = "|cff3399ff[PatronSystem]|r",
        [self.LogLevel.DEBUG] = "|cffff00ff[PatronSystem-Debug]|r"
    }
    
    local fullMessage = (prefixes[level] or prefixes[self.LogLevel.INFO]) .. " " .. tostring(message)
    
    -- Выводим в консоль
    print(fullMessage)
	if self.echoToChat and level <= self.LogLevel.INFO and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(fullMessage)
	end

end

function PatronSystemNS.Logger:Error(message)
    self:Log(message, self.LogLevel.ERROR)
end

function PatronSystemNS.Logger:Warn(message)
    self:Log(message, self.LogLevel.WARN)
end

function PatronSystemNS.Logger:Info(message)
    self:Log(message, self.LogLevel.INFO)
end

function PatronSystemNS.Logger:Debug(message)
    self:Log(message, self.LogLevel.DEBUG)
end

--[[==========================================================================
  СПЕЦИАЛИЗИРОВАННЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.Logger:UI(message)
    self:Debug("[UI] " .. tostring(message))
end

function PatronSystemNS.Logger:AIO(message)
    self:Debug("[AIO] " .. tostring(message))
end

function PatronSystemNS.Logger:Dialogue(message)
    self:Debug("[Dialogue] " .. tostring(message))
end

function PatronSystemNS.Logger:Data(message)
    self:Debug("[Data] " .. tostring(message))
end

function PatronSystemNS.Logger:Server(message)
    self:Debug("[Server] " .. tostring(message))
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.Logger:SetLevel(level)
    self.currentLevel = level
    self:Info("Уровень логирования изменен на: " .. level)
end

function PatronSystemNS.Logger:ToggleDebug()
    if not self.initialized then
        self:Initialize()
    end
    
    if self.currentLevel == self.LogLevel.DEBUG then
        self.currentLevel = self.LogLevel.INFO
        self:Info("Режим отладки ВЫКЛЮЧЕН")
    else
        self.currentLevel = self.LogLevel.DEBUG
        self:Debug("Режим отладки ВКЛЮЧЕН")
    end
end

function PatronSystemNS.Logger:GetCurrentLevel()
    return self.currentLevel or self.LogLevel.INFO
end

function PatronSystemNS.Logger:IsDebugEnabled()
    return (self.currentLevel or self.LogLevel.INFO) >= self.LogLevel.DEBUG
end

print("|cff00ff00[PatronSystem]|r Logger загружен")