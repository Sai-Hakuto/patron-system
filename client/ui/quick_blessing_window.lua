--[[============================================================================
  PATRON SYSTEM — QUICK BLESSING WINDOW
  Быстрая панель благословений на основе client_solution
  Показывает только активные благословения с isInPanel = true
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

-- Создаем окно на базе BaseWindow
NS.QuickBlessingWindow = BW:New("QuickBlessingWindow", {
    windowType = NS.Config.WindowType.DEBUG,  -- Можно создать отдельный тип для быстрой панели
    hooks = {
        onInit = function(self)
            -- Специфичная инициализация быстрой панели
            self.activeBlessings = {}
            self.buttons = {}
            self.keybindOwner = self.frame
            
            -- Настройка клавиш при показе/скрытии
            self.frame:SetScript("OnShow", function() self:ApplyKeybinds() end)
            self.frame:SetScript("OnHide", function() self:ClearKeybinds() end)
            
            -- Обновление клавиш после выхода из боя
            local eventFrame = CreateFrame("Frame")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:SetScript("OnEvent", function()
                if self.frame:IsShown() then 
                    self:ApplyKeybinds() 
                end
            end)
        end,
        onLockToggle = function(self, isLocked)
            -- Хук для логирования при изменении блокировки
            NS.Logger:Info("QuickBlessingWindow: блокировка изменена на " .. tostring(isLocked))
        end
    }
})

--[[==========================================================================
  ПЕРЕОПРЕДЕЛЕНИЕ МЕТОДОВ BASEWINDOW
============================================================================]]

--- Переопределяем создание фрейма для специфичных настроек быстрой панели
function NS.QuickBlessingWindow:CreateFrame()
    -- Вызываем базовый метод для создания стандартного фрейма
    BW.prototype.CreateFrame(self)
    
    -- Настраиваем размер для быстрой панели (только если фрейм только что создан)
    if self.frame then
        self.frame:SetSize(260, 120)  -- Начальный размер, будет динамически изменяться
        
        -- Если это первый раз, то позиция уже установлена BaseWindow
        -- При динамическом изменении размера позиция не меняется
    end
    
    -- Убираем стандартный фон BaseWindow и ставим наш
    self.frame:SetBackdrop(nil)
    local bg = self.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.85)
    self.elements.background = bg
    
    NS.Logger:UI("Создан специализированный фрейм QuickBlessingWindow")
end

--- Переопределяем создание элементов для кастомизации заголовка и добавления портрета
function NS.QuickBlessingWindow:CreateCore()
    -- Вызываем базовый метод для создания стандартных элементов (заголовок, кнопка закрытия)
    BW.prototype.CreateCore(self)
    
    -- Переопределяем заголовок
    if self.elements.title then
        self.elements.title:SetText("Blessings")
    end
    
    -- Создаем кнопку-замок используя новый метод из BaseWindow
    self:CreateLockButton()

    -- Портрет игрока
    local portrait = self.frame:CreateTexture("QuickBlessingPortrait", "ARTWORK")
    portrait:SetSize(36, 36)
    portrait:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -42)
    self.elements.portrait = portrait
    
    -- Обновляем портрет
    self:UpdatePlayerPortrait()
    
    NS.Logger:UI("Созданы элементы QuickBlessingWindow с использованием BaseWindow")
end

--- Переопределяем Show для загрузки активных благословений
function NS.QuickBlessingWindow:Show(payload)
    NS.Logger:UI("Показ быстрой панели благословений")
    
    -- СНАЧАЛА вызываем базовый метод Show, который создает фрейм
    BW.prototype.Show(self, payload)
    
    -- ПОТОМ инициализируем наши таблицы
    if not self.activeBlessings then
        self.activeBlessings = {}
    end
    if not self.buttons then
        self.buttons = {}
    end
    
    -- ПОТОМ работаем с данными (теперь фрейм уже существует)
    self:LoadActiveBlessings()
    self:CreateBlessingButtons()
    self:AdjustWindowSize()
    self:UpdatePlayerPortrait()
    
    -- Запрашиваем текущие кулдауны при показе панели
    self:RequestCooldownUpdate()
end

--[[==========================================================================
  ЗАГРУЗКА АКТИВНЫХ БЛАГОСЛОВЕНИЙ
============================================================================]]
function NS.QuickBlessingWindow:LoadActiveBlessings()
    -- Инициализируем таблицы если они не существуют
    if not self.activeBlessings then
        self.activeBlessings = {}
    end
    if not self.buttons then
        self.buttons = {}
    end
    
    -- Очищаем предыдущие данные
    wipe(self.activeBlessings)
    
    local dm = NS.DataManager
    local data = dm and dm:GetData()
    
    if not (data and data.blessings) then
        NS.Logger:Debug("QuickBlessingWindow: нет данных о благословениях")
        return
    end
    
    -- Собираем активные благословения с isInPanel = true
    for blessingId, blessing in pairs(data.blessings) do
        if blessing.isInPanel and blessing.isDiscovered then
            local blessingData = {
                id = tonumber(blessingId),
                name = blessing.name or "Неизвестное благословение",
                icon = blessing.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                blessing_type = blessing.blessing_type or "Support",
                panelSlot = blessing.panelSlot or 0
            }
            table.insert(self.activeBlessings, blessingData)
            NS.Logger:Debug("QuickBlessingWindow: добавлено благословение " .. blessingData.name)
        end
    end
    
    -- Сортируем по panelSlot для правильного порядка
    table.sort(self.activeBlessings, function(a, b)
        return (a.panelSlot or 0) < (b.panelSlot or 0)
    end)
    
    NS.Logger:Info("QuickBlessingWindow: загружено " .. #self.activeBlessings .. " активных благословений")
end

--[[==========================================================================
  СОЗДАНИЕ КНОПОК БЛАГОСЛОВЕНИЙ
============================================================================]]
function NS.QuickBlessingWindow:CreateBlessingButtons()
    -- Инициализируем таблицы если они не существуют
    if not self.buttons then
        self.buttons = {}
    end
    if not self.activeBlessings then
        self.activeBlessings = {}
    end
    
    -- Удаляем старые кнопки
    for _, button in ipairs(self.buttons) do
        button:Hide()
        button:SetParent(nil)
    end
    wipe(self.buttons)
    
    local buttonSize = 36
    local padding = 10
    local startX = 10 + 36 + 10  -- отступ + портрет + зазор
    local startY = -42
    local maxButtonsPerRow = 5
    
    for i, blessing in ipairs(self.activeBlessings) do
        -- Вычисляем позицию: не больше 5 в ряду
        local row = math.floor((i - 1) / maxButtonsPerRow)
        local col = (i - 1) % maxButtonsPerRow
        
        -- Создаем кнопку
        local button = CreateFrame("Button", "QuickBlessingButton" .. i, self.frame)
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", startX + col * (buttonSize + padding), startY - row * (buttonSize + padding))
        button:EnableMouse(true)
        button:RegisterForClicks("AnyUp")

        -- Устанавливаем иконку
        button:SetNormalTexture(blessing.icon)
        button:SetPushedTexture(blessing.icon)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        button:GetHighlightTexture():SetBlendMode("ADD")

        -- Cooldown overlay (как в стандартных ActionButton)
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:SetDrawEdge(false)
        cooldown:SetHideCountdownNumbers(false)
        button.cooldown = cooldown

        -- Настраиваем тултип
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(blessing.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)

        -- Обработчик клика (как в client_solution)
        button:SetScript("OnClick", function()
            NS.Logger:Info("QuickBlessingWindow: нажато благословение " .. blessing.name .. " (ID: " .. blessing.id .. ")")
            
            -- Проверяем кулдаун перед отправкой запроса
            if button.cooldown and button.cooldown:GetCooldownDuration() > 0 then
                NS.Logger:Debug("QuickBlessingWindow: благословение на кулдауне")
                return
            end
            
            self:RequestBlessing(blessing)
        end)
        
        -- Сохраняем ссылку на данные благословения
        button.blessingData = blessing
        
        table.insert(self.buttons, button)
    end
    
    NS.Logger:Info("QuickBlessingWindow: создано " .. #self.buttons .. " кнопок благословений")
end

--[[==========================================================================
  ОТПРАВКА ЗАПРОСА НА БЛАГОСЛОВЕНИЕ
============================================================================]]
function NS.QuickBlessingWindow:RequestBlessing(blessing)
    -- Используем ту же логику что и в client_solution
    if AIO and AIO.Handle then
        AIO.Handle("PatronSystem", "RequestBlessing", {
            blessingID = blessing.id,
            -- Можно добавить дополнительные модификаторы если нужно
        })
        NS.Logger:Info("QuickBlessingWindow: отправлен запрос благословения " .. blessing.id)
        
        -- После отправки запроса обновляем кулдауны через небольшую задержку
        C_Timer.After(0.5, function()
            self:RequestCooldownUpdate()
        end)
    else
        NS.Logger:Error("QuickBlessingWindow: AIO.Handle недоступен!")
        if NS.UIManager then
            NS.UIManager:ShowMessage("Ошибка связи с сервером", "error")
        end
    end
end

--[[==========================================================================
  УПРАВЛЕНИЕ КЛАВИШАМИ (как в client_solution)
============================================================================]]
function NS.QuickBlessingWindow:ApplyKeybinds()
    if InCombatLockdown() then
        NS.Logger:Debug("QuickBlessingWindow: нельзя менять клавиши в бою")
        return
    end
    
    ClearOverrideBindings(self.keybindOwner)
    
    -- Привязываем SHIFT+1 до SHIFT+0 к первым 10 кнопкам
    local keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}
    for i = 1, math.min(#self.buttons, 10) do
        if keys[i] then
            SetOverrideBindingClick(self.keybindOwner, true, "SHIFT-" .. keys[i], 
                                    "QuickBlessingButton" .. i, "LeftButton")
            NS.Logger:Debug("QuickBlessingWindow: привязана клавиша SHIFT-" .. keys[i] .. " к кнопке " .. i)
        end
    end
end

function NS.QuickBlessingWindow:ClearKeybinds()
    ClearOverrideBindings(self.keybindOwner)
    NS.Logger:Debug("QuickBlessingWindow: клавиши очищены")
end

--[[==========================================================================
  АВТОМАТИЧЕСКАЯ НАСТРОЙКА РАЗМЕРА ОКНА
============================================================================]]
function NS.QuickBlessingWindow:AdjustWindowSize()
    -- Инициализируем таблицу если она не существует
    if not self.activeBlessings then
        self.activeBlessings = {}
    end
    
    local buttonCount = #self.activeBlessings
    
    if buttonCount == 0 then
        -- Если нет благословений, показываем минимальное окно
        self.frame:SetSize(200, 80)
        return
    end
    
    local buttonSize = 36
    local padding = 10
    local portraitWidth = 36
    local baseWidth = 10 + portraitWidth + 10  -- отступы + портрет + зазор
    local baseHeight = 42 + 10  -- заголовок + отступ снизу
    
    -- Вычисляем количество строк (максимум 5 кнопок в ряду)
    local buttonsPerRow = math.min(buttonCount, 5)
    local rows = math.ceil(buttonCount / 5)
    
    -- Вычисляем размеры
    local contentWidth = buttonsPerRow * buttonSize + (buttonsPerRow - 1) * padding
    local totalWidth = baseWidth + contentWidth + 10  -- + правый отступ
    
    local contentHeight = rows * buttonSize + (rows - 1) * padding
    local totalHeight = baseHeight + contentHeight
    
    self.frame:SetSize(totalWidth, totalHeight)
    
    NS.Logger:Debug("QuickBlessingWindow: размер окна установлен " .. totalWidth .. "x" .. totalHeight .. 
                   " для " .. buttonCount .. " благословений (" .. rows .. " строк)")
end

--[[==========================================================================
  ОБНОВЛЕНИЕ ПОРТРЕТА ИГРОКА
============================================================================]]
function NS.QuickBlessingWindow:UpdatePlayerPortrait()
    if self.elements.portrait then
        SetPortraitTexture(self.elements.portrait, "player")
    end
end

--[[==========================================================================
  ОБНОВЛЕНИЕ КУЛДАУНОВ
============================================================================]]
function NS.QuickBlessingWindow:UpdateCooldowns(cooldownData)
    if not self.buttons or not cooldownData then 
        return 
    end
    
    for _, button in ipairs(self.buttons) do
        if button.blessingData and button.cooldown then
            local blessingId = button.blessingData.id
            local cooldownInfo = cooldownData[blessingId]
            
            if cooldownInfo and cooldownInfo.remaining > 0 then
                -- Запускаем анимацию кулдауна
                local startTime = GetTime() - (cooldownInfo.duration - cooldownInfo.remaining)
                button.cooldown:SetCooldown(startTime, cooldownInfo.duration)
                button:Disable() -- Блокируем кнопку
                NS.Logger:Debug("QuickBlessingWindow: кулдаун для " .. blessingId .. " - " .. cooldownInfo.remaining .. "с")
            else
                -- Очищаем кулдаун
                button.cooldown:Clear()
                button:Enable()
            end
        end
    end
end

function NS.QuickBlessingWindow:RequestCooldownUpdate()
    -- Запрашиваем текущие кулдауны с сервера
    if AIO and AIO.Handle then
        AIO.Handle("PatronSystem", "RequestCooldowns", {})
        NS.Logger:Debug("QuickBlessingWindow: запрошены кулдауны с сервера")
    end
end

--[[==========================================================================
  УТИЛИТАРНЫЕ МЕТОДЫ
============================================================================]]
-- IsShown, GetFrame, ToggleDragLock и другие методы теперь наследуются от BaseWindow

-- Обновление данных (вызывается при изменении благословений)
function NS.QuickBlessingWindow:RefreshData()
    if self:IsShown() then
        self:LoadActiveBlessings()
        self:CreateBlessingButtons()
        self:AdjustWindowSize()
        NS.Logger:Info("QuickBlessingWindow: данные обновлены")
    end
end

print("|cff00ff00[PatronSystem]|r QuickBlessingWindow загружен")