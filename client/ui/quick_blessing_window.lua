--[[============================================================================
  PATRON SYSTEM — QUICK BLESSING WINDOW
  Быстрая панель благословений на основе client_solution
  Показывает только активные благословения с isInPanel = true
============================================================================]]--

local NS = PatronSystemNS

NS.QuickBlessingWindow = {
    frame = nil,
    elements = {},
    initialized = false,
    activeBlessings = {},
    buttons = {},
    keybindOwner = nil,
    isLocked = false  -- Состояние блокировки перетаскивания
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function NS.QuickBlessingWindow:Initialize()
    if self.initialized then return end
    
    NS.Logger:Info("QuickBlessingWindow инициализация...")
    
    self:CreateFrame()
    self:CreateElements()
    
    self.initialized = true
    NS.Logger:Info("QuickBlessingWindow инициализирован")
end

--[[==========================================================================
  СОЗДАНИЕ ОСНОВНОГО ФРЕЙМА
============================================================================]]
function NS.QuickBlessingWindow:CreateFrame()
    -- Начальный размер - будет динамически изменяться
    self.frame = CreateFrame("Frame", "QuickBlessingFrame", UIParent)
    self.frame:SetSize(260, 120)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame:Hide()

    -- Фон панели (непрозрачный как в client_solution)
    local bg = self.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.85)
    self.elements.background = bg

    -- Настройка клавиш при показе/скрытии
    self.keybindOwner = self.frame
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
    
    NS.Logger:UI("Создан основной фрейм QuickBlessingWindow")
end

--[[==========================================================================
  СОЗДАНИЕ ЭЛЕМЕНТОВ UI
============================================================================]]
function NS.QuickBlessingWindow:CreateElements()
    -- Заголовок
    local title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", self.frame, "TOP", 0, -10)
    title:SetText("Blessings")
    self.elements.title = title

    -- Кнопка-замок для блокировки перетаскивания
    local lockButton = CreateFrame("Button", "QuickBlessingLockButton", self.frame)
    lockButton:SetSize(16, 16)
    lockButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -8)
    
    -- Иконки замка
    local unlockedTexture = "Interface\\Buttons\\LockButton-Unlocked-Up"
    local lockedTexture = "Interface\\Buttons\\LockButton-Locked-Up"
    
    lockButton:SetNormalTexture(unlockedTexture)
    lockButton:SetPushedTexture(unlockedTexture)
    lockButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    
    -- Тултип
    lockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(NS.QuickBlessingWindow.isLocked and "Разблокировать перетаскивание" or "Заблокировать перетаскивание")
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", GameTooltip_Hide)
    
    -- Обработчик клика
    lockButton:SetScript("OnClick", function()
        NS.QuickBlessingWindow:ToggleLock()
    end)
    
    self.elements.lockButton = lockButton

    -- Портрет игрока
    local portrait = self.frame:CreateTexture("QuickBlessingPortrait", "ARTWORK")
    portrait:SetSize(36, 36)
    portrait:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -42)
    self.elements.portrait = portrait
    
    -- Обновляем портрет
    self:UpdatePlayerPortrait()
    
    -- Устанавливаем начальное состояние замка
    self:UpdateLockButton()
    
    NS.Logger:UI("Созданы элементы QuickBlessingWindow")
end

--[[==========================================================================
  ОСНОВНЫЕ МЕТОДЫ ОКНА
============================================================================]]
function NS.QuickBlessingWindow:Show()
    if not self.initialized then
        self:Initialize()
    end
    
    NS.Logger:UI("Показ быстрой панели благословений")
    
    -- Загружаем активные благословения
    self:LoadActiveBlessings()
    
    -- Создаем кнопки благословений
    self:CreateBlessingButtons()
    
    -- Подстраиваем размер окна
    self:AdjustWindowSize()
    
    self.frame:Show()
    
    -- Обновляем портрет
    self:UpdatePlayerPortrait()
end

function NS.QuickBlessingWindow:Hide()
    NS.Logger:UI("Скрытие быстрой панели благословений")
    
    if self.frame then
        self.frame:Hide()
    end
end

function NS.QuickBlessingWindow:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--[[==========================================================================
  ЗАГРУЗКА АКТИВНЫХ БЛАГОСЛОВЕНИЙ
============================================================================]]
function NS.QuickBlessingWindow:LoadActiveBlessings()
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
        button:SetPoint("TOPLEFT", startX + col * (buttonSize + padding), startY - row * (buttonSize + padding))
        button:EnableMouse(true)
        button:RegisterForClicks("AnyUp")

        -- Устанавливаем иконку
        button:SetNormalTexture(blessing.icon)
        button:SetPushedTexture(blessing.icon)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        button:GetHighlightTexture():SetBlendMode("ADD")

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
        AIO.Handle("blessings", "RequestBlessing", {
            blessingID = blessing.id,
            -- Можно добавить дополнительные модификаторы если нужно
        })
        NS.Logger:Info("QuickBlessingWindow: отправлен запрос благословения " .. blessing.id)
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
  УПРАВЛЕНИЕ БЛОКИРОВКОЙ ПЕРЕТАСКИВАНИЯ
============================================================================]]
function NS.QuickBlessingWindow:ToggleLock()
    self.isLocked = not self.isLocked
    
    if self.isLocked then
        -- Блокируем только перетаскивание, но оставляем мышь активной для кнопок
        self.frame:SetMovable(false)
        self.frame:RegisterForDrag()  -- убираем drag события
        NS.Logger:UI("QuickBlessingWindow: перетаскивание заблокировано")
    else
        -- Разблокируем перетаскивание
        self.frame:SetMovable(true)
        self.frame:RegisterForDrag("LeftButton")  -- восстанавливаем drag события
        NS.Logger:UI("QuickBlessingWindow: перетаскивание разблокировано")
    end
    
    self:UpdateLockButton()
end

function NS.QuickBlessingWindow:UpdateLockButton()
    if not self.elements.lockButton then return end
    
    local unlockedTexture = "Interface\\Buttons\\LockButton-Unlocked-Up"
    local lockedTexture = "Interface\\Buttons\\LockButton-Locked-Up"
    
    if self.isLocked then
        self.elements.lockButton:SetNormalTexture(lockedTexture)
        self.elements.lockButton:SetPushedTexture(lockedTexture)
    else
        self.elements.lockButton:SetNormalTexture(unlockedTexture)
        self.elements.lockButton:SetPushedTexture(unlockedTexture)
    end
end

--[[==========================================================================
  УТИЛИТАРНЫЕ МЕТОДЫ
============================================================================]]
function NS.QuickBlessingWindow:IsShown()
    return self.frame and self.frame:IsShown()
end

function NS.QuickBlessingWindow:GetFrame()
    return self.frame
end

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