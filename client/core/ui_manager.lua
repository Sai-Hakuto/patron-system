--[[==========================================================================
  PATRON SYSTEM - UI MANAGER (ЭТАП 2 РЕФАКТОРИНГА + НОВЫЕ ОКНА)
  Чистый координатор окон без бизнес-логики + BlessingWindow + ShopWindow
============================================================================]]

-- Заполняем UIManager в уже созданном неймспейсе
PatronSystemNS.UIManager = {
    -- Состояние UI
    initialized = false,
    currentWindow = nil,
    currentSpeaker = nil,
    messageFrame = nil,
    
    -- Реестр открытых окон
    openWindows = {},
    
    -- НОВОЕ: Система внутренних событий
    eventCallbacks = {}
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.UIManager:Initialize()
    if self.initialized then return end
    
    PatronSystemNS.Logger:Info("UIManager инициализирован (ЭТАП 2 + НОВЫЕ ОКНА)")
    self.initialized = true
    
    -- Создаем систему сообщений
    self:CreateMessageFrame()
    
    -- НОВОЕ: Регистрируем базовые события
    self:RegisterEvent("SpeakerDataReceived", function(data) self:OnSpeakerDataReceived(data) end)
    self:RegisterEvent("DialogueUpdated", function(data) self:OnDialogueUpdated(data) end)
    self:RegisterEvent("DialogueEnded", function() self:OnDialogueEnded() end)
end

--[[==========================================================================
  НОВОЕ: СИСТЕМА ВНУТРЕННИХ СОБЫТИЙ
============================================================================]]
function PatronSystemNS.UIManager:RegisterEvent(eventName, callback)
    if not self.eventCallbacks[eventName] then
        self.eventCallbacks[eventName] = {}
    end
    table.insert(self.eventCallbacks[eventName], callback)
    PatronSystemNS.Logger:UI("Зарегистрировано событие: " .. eventName)
end

function PatronSystemNS.UIManager:TriggerEvent(eventName, ...)
    local callbacks = self.eventCallbacks[eventName]
    if not callbacks then return end
    
    PatronSystemNS.Logger:UI("Событие: " .. eventName .. " (" .. #callbacks .. " слушателей)")
    
    for _, callback in ipairs(callbacks) do
        local success, err = pcall(callback, ...)
        if not success then
            PatronSystemNS.Logger:Error("Ошибка в обработчике события " .. eventName .. ": " .. tostring(err))
        end
    end
end

--[[==========================================================================
  УПРОЩЕННОЕ УПРАВЛЕНИЕ ОКНАМИ
============================================================================]]
function PatronSystemNS.UIManager:ShowMainWindow(speakerType, speakerID)
    speakerType = speakerType or PatronSystemNS.Config.SpeakerType.PATRON
    speakerID = speakerID or 1
    
    PatronSystemNS.Logger:UI("Показ главного окна: " .. speakerID .. " (" .. speakerType .. ")")
    
    if speakerType == PatronSystemNS.Config.SpeakerType.PATRON then
        self:ShowPatronWindow(speakerID)
    elseif speakerType == PatronSystemNS.Config.SpeakerType.FOLLOWER then
        self:ShowFollowerWindow(speakerID)
    else
        PatronSystemNS.Logger:Error("Неизвестный тип говорящего: " .. speakerType)
    end
end

-- РЕФАКТОРИНГ: Упрощенный ShowPatronWindow - только UI, без бизнес-логики
function PatronSystemNS.UIManager:ShowPatronWindow(patronID)
    if not PatronSystemNS.PatronWindow then
        PatronSystemNS.Logger:Error("PatronWindow не загружен!")
        return
    end
    
    -- ИСПРАВЛЕНИЕ: Разная логика в зависимости от ситуации
    local shouldUseLastPatron = false
    
    if not patronID then
        -- Если patronID не указан - используем последнего запомненного
        patronID = PatronSystemNS.PatronWindow.lastPatronID or 1
        shouldUseLastPatron = true
        PatronSystemNS.Logger:UI("PatronID не указан, используем последнего: " .. patronID)
    else
        PatronSystemNS.Logger:UI("Показ окна покровителя с явным ID: " .. patronID)
    end
    
    -- НЕ закрываем другие окна - оставляем открытыми
    PatronSystemNS.PatronWindow:Show(patronID)
    self:RegisterWindow(PatronSystemNS.Config.WindowType.PATRON, PatronSystemNS.PatronWindow)
    
    -- Запрос данных всегда (даже для запомненного покровителя)
    PatronSystemNS.DataManager:GetOrRequestSpeakerData(
        patronID,
        PatronSystemNS.Config.SpeakerType.PATRON,
        function(data)
            PatronSystemNS.Logger:UI("Данные покровителя получены, отправляем событие")
            self:TriggerEvent("SpeakerDataReceived", data)
        end
    )
    
    -- НОВОЕ: При переоткрытии окна также запрашиваем обновление SmallTalk
    PatronSystemNS.Logger:UI("Запрашиваем обновление SmallTalk при открытии окна для покровителя: " .. patronID)
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RefreshSmallTalk", {
        speakerId = patronID,
        speakerType = PatronSystemNS.Config.SpeakerType.PATRON
    })
end

function PatronSystemNS.UIManager:ShowPatronWindowSmart()
    -- Эта функция используется из MainWindow для кнопки "Patrons"
    
    if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() then
        -- Окно уже открыто - просто поднимаем его наверх, НЕ меняем покровителя
        PatronSystemNS.Logger:UI("Окно покровителей уже открыто, поднимаем наверх")
        self:BringWindowToFront(PatronSystemNS.Config.WindowType.PATRON)
        return
    end
    
    -- Окно закрыто - открываем с последним запомненным покровителем
    local lastPatronID = PatronSystemNS.PatronWindow.lastPatronID or 1
    PatronSystemNS.Logger:UI("Открываем окно покровителей с последним ID: " .. lastPatronID)
    self:ShowPatronWindow(lastPatronID)
end

function PatronSystemNS.UIManager:ShowFollowerWindowSmart()
    if not PatronSystemNS.FollowerWindow then
        PatronSystemNS.Logger:Error("FollowerWindow не загружен!")
        return
    end

    local chosenId = nil
    local progress = PatronSystemNS.DataManager and PatronSystemNS.DataManager:GetPlayerProgress()

    -- 1) Пытаемся использовать последний выбор
    local last = PatronSystemNS.FollowerWindow.lastFollowerID
    if progress and progress.followers and last and progress.followers[tostring(last)] then
        chosenId = last
    end

    -- 2) Иначе берём первого доступного из БД
    if not chosenId and progress and progress.followers then
        for fid, fdata in pairs(progress.followers) do
            if fdata and (fdata.isDiscovered or fdata.isActive) then
                chosenId = tonumber(fid)
                break
            end
        end
    end

    -- 3) Показываем окно (nil допустим: окно отрисует плейсхолдер)
    PatronSystemNS.FollowerWindow:Show(chosenId)
    self:RegisterWindow(PatronSystemNS.Config.WindowType.FOLLOWER, PatronSystemNS.FollowerWindow)
end

function PatronSystemNS.UIManager:ShowFollowerWindow(followerID)
    if not PatronSystemNS.FollowerWindow then
        PatronSystemNS.Logger:Error("FollowerWindow не загружен!")
        return
    end

    -- ИСПРАВЛЕНО: Упрощенная логика выбора ID
    if not followerID then
        -- Если ID не задан — берём последний сохраненный в окне или первый доступный
        followerID = PatronSystemNS.FollowerWindow.lastFollowerID
        
        if not followerID then
            -- Если нет сохраненного, получаем первый доступный
            local prog = PatronSystemNS.DataManager and PatronSystemNS.DataManager:GetPlayerProgress()
            local unlocked = {}
            if prog and type(prog.followers)=="table" then
                for k, v in pairs(prog.followers) do
                    if type(v)=="table" and (v.isDiscovered==true or v.isActive==true) then
                        table.insert(unlocked, tonumber(k) or k)
                    end
                end
                -- ИСПРАВЛЕНО: Числовая сортировка
                table.sort(unlocked, function(a,b) return tonumber(a) < tonumber(b) end)
            end
            if not unlocked[1] then
			  self:ShowMessage("Система последователей недоступна на этом этапе.", "info")
			  return
			end
			followerID = unlocked[1]
        end
        
        PatronSystemNS.Logger:UI("FollowerID выбран по приоритету: " .. tostring(followerID))
    else
        PatronSystemNS.Logger:UI("Открытие FollowerWindow для фолловера " .. followerID)
    end

    -- показываем окно (Show() сам разберется с выбором фолловера)
    PatronSystemNS.FollowerWindow:Show(followerID)

    -- регистрируем окно
    self:RegisterWindow(PatronSystemNS.Config.WindowType.FOLLOWER, PatronSystemNS.FollowerWindow)

    -- Подгрузим актуальные данные говорящего (FOLLOWER)
    PatronSystemNS.DataManager:GetOrRequestSpeakerData(
        followerID,
        PatronSystemNS.Config.SpeakerType.FOLLOWER,
        function(data)
            PatronSystemNS.Logger:UI("Данные фолловера получены, отправляем событие")
            self:TriggerEvent("SpeakerDataReceived", data)
        end
    )

    -- НОВОЕ: Запрашиваем обновление SmallTalk при открытии окна для фолловера
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RefreshSmallTalk", {
        speakerId = followerID,
        speakerType = PatronSystemNS.Config.SpeakerType.FOLLOWER
    })
end

function PatronSystemNS.UIManager:GetMaxFrameLevel()
    local max = 0
    for _, w in pairs(self.openWindows or {}) do
        local f = w.GetFrame and w:GetFrame()
        if f then
            local lvl = f:GetFrameLevel() or 0
            if lvl > max then max = lvl end
        end
    end
    return max
end

function PatronSystemNS.UIManager:IsTop(windowType)
    local window = self.openWindows and self.openWindows[windowType]
    if not window or not window.GetFrame then return false end
    local f = window:GetFrame()
    if not f then return false end
    local top = self:GetMaxFrameLevel()
    -- небольшой допуск на случай равенства уровней
    return (f:GetFrameLevel() or 0) >= top
end

-- НОВОЕ: Методы для новых окон
function PatronSystemNS.UIManager:ShowBlessingWindow()
    if not PatronSystemNS.BlessingWindow then
        PatronSystemNS.Logger:Error("BlessingWindow не загружен!")
        return
    end
    
    PatronSystemNS.Logger:UI("Показ окна благословений")
    
    PatronSystemNS.BlessingWindow:Show()
    self:RegisterWindow(PatronSystemNS.Config.WindowType.BLESSING, PatronSystemNS.BlessingWindow)
end

function PatronSystemNS.UIManager:ShowShopWindow()
    if not PatronSystemNS.ShopWindow then
        PatronSystemNS.Logger:Error("ShopWindow не загружен!")
        return
    end
    
    PatronSystemNS.Logger:UI("Показ окна магазина")
    
    PatronSystemNS.ShopWindow:Show()
    self:RegisterWindow(PatronSystemNS.Config.WindowType.SHOP, PatronSystemNS.ShopWindow)
end

function PatronSystemNS.UIManager:ShowMainSelectionWindow()
    if not PatronSystemNS.MainWindow then
        PatronSystemNS.Logger:Error("MainWindow не загружен!")
        return
    end
    
    PatronSystemNS.Logger:UI("Показ главного окна выбора разделов")
    
    PatronSystemNS.MainWindow:Show()
    self:RegisterWindow(PatronSystemNS.Config.WindowType.MAIN, PatronSystemNS.MainWindow)
end

-- НОВОЕ: Единый метод регистрации окон
function PatronSystemNS.UIManager:RegisterWindow(windowType, window)
    self.openWindows[windowType] = window
    
    -- Автоматически устанавливаем правильный слой
    self:SetWindowLayer(windowType, window)
    
    -- Настраиваем обработчик клика для поднятия окна
    local frame = window:GetFrame()
    if frame then
        frame:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				PatronSystemNS.UIManager:BringWindowToFront(windowType)
			end
		end)
    end
    
    PatronSystemNS.Logger:UI("Зарегистрировано окно с правильным слоем: " .. windowType)
end


function PatronSystemNS.UIManager:HideCurrentWindow()
    if self.currentWindow and self.currentWindow.Hide then
        PatronSystemNS.Logger:UI("Скрытие текущего окна")
        self.currentWindow:Hide()
        
        -- Завершаем диалог если он активен
        if PatronSystemNS.DialogueEngine:IsInDialogue() then
            PatronSystemNS.DialogueEngine:EndDialogue()
        end
    end
end

function PatronSystemNS.UIManager:ToggleMainWindow(speakerType, speakerID)
    -- Если указаны параметры - показываем конкретное окно (обратная совместимость)
    if speakerType and speakerID then
        if self.currentWindow and self.currentWindow:IsShown() then
            self:HideCurrentWindow()
        else
            self:ShowMainWindow(speakerType, speakerID)
        end
    else
        -- Без параметров - показываем главное окно выбора
        if PatronSystemNS.MainWindow and PatronSystemNS.MainWindow:IsShown() then
            PatronSystemNS.MainWindow:Hide()
        else
            self:ShowMainSelectionWindow()
        end
    end
end

function PatronSystemNS.UIManager:CloseAllWindows()
    PatronSystemNS.Logger:UI("Закрытие всех окон")
    
    for windowType, window in pairs(self.openWindows) do
        if window and window.Hide then
            window:Hide()
        end
    end
    
    self.openWindows = {}
    self.currentWindow = nil
    
    -- Завершаем диалог если активен
    if PatronSystemNS.DialogueEngine:IsInDialogue() then
        PatronSystemNS.DialogueEngine:EndDialogue()
    end
end

--[[==========================================================================
  РЕФАКТОРИНГ: ОБРАБОТКА СОБЫТИЙ ЧЕРЕЗ СИСТЕМУ СОБЫТИЙ
============================================================================]]

-- НОВОЕ: Современная обработка через события вместо прямых вызовов
function PatronSystemNS.UIManager:OnSpeakerDataReceived(speakerData)
    PatronSystemNS.Logger:UI("Получены данные о говорящем: " .. (speakerData.Name or "Неизвестно"))
    
    self.currentSpeaker = speakerData
    
    -- ИСПРАВЛЕНИЕ: Проверяем PatronWindow напрямую, игнорируем currentWindow
    if speakerData.SpeakerType == PatronSystemNS.Config.SpeakerType.PATRON then
        if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() then
            PatronSystemNS.Logger:UI("Обновляем данные в PatronWindow")
            PatronSystemNS.PatronWindow:UpdateSpeakerData(speakerData)
        else
            PatronSystemNS.Logger:UI("PatronWindow не открыт, данные не переданы")
        end
    elseif speakerData.SpeakerType == PatronSystemNS.Config.SpeakerType.FOLLOWER then
        if PatronSystemNS.FollowerWindow and PatronSystemNS.FollowerWindow:IsShown() then
            PatronSystemNS.Logger:UI("Обновляем данные в FollowerWindow")
            PatronSystemNS.FollowerWindow:UpdateSpeakerData(speakerData)
        else
            PatronSystemNS.Logger:UI("FollowerWindow не открыт, данные не переданы")
        end
    end
end

function PatronSystemNS.UIManager:OnDialogueUpdated(dialogueData)
    PatronSystemNS.Logger:UI("Обновление диалога: " .. (dialogueData.text or "пустой"))
    
    -- Проверяем, какое окно открыто и передаем диалог в соответствующее
    if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() then
        PatronSystemNS.Logger:UI("Передаем диалог в PatronWindow")
        PatronSystemNS.PatronWindow:UpdateDialogue(dialogueData)
    elseif PatronSystemNS.FollowerWindow and PatronSystemNS.FollowerWindow:IsShown() then
        PatronSystemNS.Logger:UI("Передаем диалог в FollowerWindow")
        PatronSystemNS.FollowerWindow:UpdateDialogue(dialogueData)
    else
        PatronSystemNS.Logger:Warn("Ни PatronWindow, ни FollowerWindow не открыты для отображения диалога")
    end
end

function PatronSystemNS.UIManager:OnDialogueEnded()
    PatronSystemNS.Logger:UI("Диалог завершен")
    
    -- Проверяем, какое окно открыто и уведомляем о завершении диалога
    if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() then
        PatronSystemNS.Logger:UI("Уведомляем PatronWindow о завершении диалога")
        PatronSystemNS.PatronWindow:OnDialogueEnded()
    elseif PatronSystemNS.FollowerWindow and PatronSystemNS.FollowerWindow:IsShown() then
        PatronSystemNS.Logger:UI("Уведомляем FollowerWindow о завершении диалога")
        PatronSystemNS.FollowerWindow:OnDialogueEnded()
    else
        PatronSystemNS.Logger:UI("Ни PatronWindow, ни FollowerWindow не открыты для завершения диалога")
    end
end

-- УСТАРЕВШИЕ МЕТОДЫ: Для обратной совместимости (будут убраны в ЭТАПЕ 3)
function PatronSystemNS.UIManager:UpdateDialogue(dialogueData)
    PatronSystemNS.Logger:Warn("DEPRECATED: UpdateDialogue() используйте событие DialogueUpdated")
    self:OnDialogueUpdated(dialogueData)
end

--=== УТИЛИТЫ ДЛЯ СТАРТА КОР-ДИАЛОГОВ ПАТРОНА ===--

-- Маппинг "кор-веток" под действия: X70001 / X80001 / X90001
-- Интерпретация X как ID патрона (1..N), финальный ID: patronId*10000 + SUFFIX
local function PS_GetPatronCoreNodeId(patronId, actionId)
    local suffixByAction = {
        PRAY      = 7001,  -- X70001 -> 1*10000+7001 = 17001, 2*10000+7001 = 27001 и т.д.
        TRADE     = 8001,  -- X80001 -> 18001 / 28001 / 38001 ...
        FOLLOWER  = 9001,  -- X90001 -> 19001 / 29001 / 39001 ...
    }
    local pid = tonumber(patronId)
    local suffix = suffixByAction[actionId]
    if not (pid and suffix) then return nil end
    return pid * 10000 + suffix
end

-- Унифицированный старт диалога с нужного узла для патрона
local function PS_StartPatronDialogueAt(nodeId, speakerId)
    local DE = PatronSystemNS.DialogueEngine
    DE.currentSpeakerID = speakerId
    DE.currentSpeakerType = PatronSystemNS.Config.SpeakerType.PATRON
    DE.dialogueHistory = {}
    -- Сервер принимает RequestContinueDialogue от произвольного узла
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestContinueDialogue", nodeId)
end

--[[==========================================================================
  РЕФАКТОРИНГ: СТАНДАРТИЗИРОВАННАЯ ОБРАБОТКА ДЕЙСТВИЙ
============================================================================]]
function PatronSystemNS.UIManager:HandleAction(actionID, speakerID, speakerType)
    PatronSystemNS.Logger:UI("Обработка действия: " .. actionID .. " для " .. speakerID .. " (" .. speakerType .. ")")
    
	
    -- РЕФАКТОРИНГ: Стандартизированная логика действий
    local actionHandlers = {
        TALK = function()
            PatronSystemNS.DialogueEngine:StartDialogue(speakerID, speakerType)
        end,
        
        EXIT_DIALOGUE = function()
            PatronSystemNS.DialogueEngine:EndDialogue()
        end,
        
        -- Для будущих окон используем стандартизированную логику
        TRADE = function()
            if speakerType ~= PatronSystemNS.Config.SpeakerType.PATRON then
                self:ShowMessage("Торговать можно только с покровителями", "error")
                return
            end
            local nodeId = PS_GetPatronCoreNodeId(speakerID, "TRADE")
            if not nodeId then
                self:ShowMessage("Не удалось определить стартовый узел торговли", "error")
                return
            end
            PS_StartPatronDialogueAt(nodeId, speakerID)
        end,
        
        FOLLOWER = function()
            if speakerType ~= PatronSystemNS.Config.SpeakerType.PATRON then
                self:ShowMessage("Раздел последователей доступен у покровителей", "error")
                return
            end
            local nodeId = PS_GetPatronCoreNodeId(speakerID, "FOLLOWER")
            if not nodeId then
                self:ShowMessage("Не удалось определить стартовый узел последователей", "error")
                return
            end
            PS_StartPatronDialogueAt(nodeId, speakerID)
        end,
        
        PRAY = function()
            if speakerType ~= PatronSystemNS.Config.SpeakerType.PATRON then
                self:ShowMessage("Молиться можно только покровителям", "error")
                return
            end
            local nodeId = PS_GetPatronCoreNodeId(speakerID, "PRAY")
            if not nodeId then
                self:ShowMessage("Не удалось определить стартовый узел молитвы", "error")
                return
            end
            PS_StartPatronDialogueAt(nodeId, speakerID)
        end,
        
        EQUIP = function()
            self:ShowMessage("Экипировка будет реализована в следующих этапах", "info")
        end
    }
    
    local handler = actionHandlers[actionID]
    if handler then
        local success, err = pcall(handler)
        if not success then
            PatronSystemNS.Logger:Error("Ошибка при выполнении действия " .. actionID .. ": " .. tostring(err))
            self:ShowMessage("Ошибка при выполнении действия", "error")
        end
    else
        PatronSystemNS.Logger:UI("Действие " .. actionID .. " не реализовано")
        self:ShowMessage("Действие не реализовано: " .. actionID, "warning")
    end
end

--[[==========================================================================
  НОВОЕ: ОБРАБОТКА ВЫБОРА РАЗДЕЛОВ ИЗ MAINWINDOW
============================================================================]]
function PatronSystemNS.UIManager:OnMainWindowSectionSelected(sectionId)
    PatronSystemNS.Logger:UI("Выбран раздел из главного окна: " .. sectionId)
    
    if sectionId == "patrons" then
        self:ShowPatronWindow(1)
    elseif sectionId == "followers" then
        if PatronSystemNS.FollowerWindow and PatronSystemNS.FollowerWindow:IsShown() then
        -- Окно уже открыто, просто поднимаем на передний план
			self:BringWindowToFront(PatronSystemNS.Config.WindowType.FOLLOWER)
		else
			-- Окно закрыто, открываем с сохраненным выбором
			self:ShowFollowerWindow()
		end
    elseif sectionId == "blessings" then
        self:ShowBlessingWindow()
    elseif sectionId == "shop" then
        self:ShowShopWindow()
    end
end

--[[==========================================================================
  СИСТЕМА СООБЩЕНИЙ (БЕЗ ИЗМЕНЕНИЙ)
============================================================================]]
function PatronSystemNS.UIManager:CreateMessageFrame()
    self.messageFrame = CreateFrame("Frame", "PatronSystemMessageFrame", UIParent)
    self.messageFrame:SetSize(400, 100)
    self.messageFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    self.messageFrame:SetFrameStrata("TOOLTIP")
    self.messageFrame:Hide()
    
    -- Фон сообщения
    self.messageFrame.background = self.messageFrame:CreateTexture(nil, "BACKGROUND")
    self.messageFrame.background:SetAllPoints()
    self.messageFrame.background:SetColorTexture(0, 0, 0, 0.8)
    
    -- Текст сообщения
    self.messageFrame.text = self.messageFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.messageFrame.text:SetPoint("CENTER")
    self.messageFrame.text:SetJustifyH("CENTER")
    self.messageFrame.text:SetWordWrap(true)
    self.messageFrame.text:SetWidth(380)
    
    PatronSystemNS.Logger:UI("Создан фрейм сообщений")
end

function PatronSystemNS.UIManager:ShowMessage(message, messageType)
    if not self.messageFrame then return end
    
    messageType = messageType or "info"
    
    PatronSystemNS.Logger:UI("Показ сообщения (" .. messageType .. "): " .. message)
    
    -- Устанавливаем цвет в зависимости от типа
    local color = PatronSystemNS.Config:GetColor(messageType)
    self.messageFrame.text:SetTextColor(color.r, color.g, color.b, color.a)
    self.messageFrame.text:SetText(message)
    
    -- Показываем сообщение
    self.messageFrame:Show()
    
    -- Автоматически скрываем через 3 секунды
    C_Timer.After(3, function()
        if self.messageFrame then
            self.messageFrame:Hide()
        end
    end)
end

--[[==========================================================================
  НОВОЕ: СИСТЕМА УПРАВЛЕНИЯ СЛОЯМИ ОКОН
============================================================================]]
-- Система управления слоями окон
PatronSystemNS.UIManager.windowLayers = {
    BACKGROUND = "BACKGROUND",
    LOW = "LOW", 
    MEDIUM = "MEDIUM",
    HIGH = "HIGH",
    DIALOG = "DIALOG",
    FULLSCREEN_DIALOG = "FULLSCREEN_DIALOG",
    TOOLTIP = "TOOLTIP"
}

PatronSystemNS.UIManager.windowLayerMap = {}

-- Приоритеты окон (от нижнего к верхнему)
PatronSystemNS.UIManager.windowPriorities = {
    [PatronSystemNS.Config.WindowType.MAIN] = 1,        -- MainWindow - самый нижний
    [PatronSystemNS.Config.WindowType.PATRON] = 2,      -- PatronWindow
    [PatronSystemNS.Config.WindowType.BLESSING] = 3,    -- BlessingWindow  
    [PatronSystemNS.Config.WindowType.SHOP] = 4,        -- ShopWindow - самый верхний
    [PatronSystemNS.Config.WindowType.DEBUG] = 5        -- Debug окна поверх всех
}

-- Установка правильного слоя окна
function PatronSystemNS.UIManager:SetWindowLayer(windowType, window)
    if not window or not window.GetFrame then
        PatronSystemNS.Logger:Error("Неверное окно для установки слоя: " .. tostring(windowType))
        return
    end

    local frame = window:GetFrame()
    if not frame then return end

    -- Страта по умолчанию для всех «обычных» окон аддона
    self.NORMAL_STRATA = self.NORMAL_STRATA or "HIGH"

    -- Базовые уровни (внутри одной страты). Подстрой под свои типы при желании.
    local WT = PatronSystemNS.Config and PatronSystemNS.Config.WindowType or {}
    self.baseLevels = self.baseLevels or {
        [WT.MAIN]     = 100,
        [WT.PATRON]   = 200,
        [WT.FOLLOWER] = 200,
        [WT.BLESSING] = 300,
        [WT.SHOP]     = 400,
        [WT.DEBUG]    = 450,
    }

    local base = self.baseLevels[windowType] or 200

    -- ВАЖНО: всегда одна страта (HIGH), чтобы не перебивать Blizzard Settings (DIALOG/FS_DIALOG)
    frame:SetFrameStrata(self.NORMAL_STRATA)
    frame:SetFrameLevel(base)
    frame:SetToplevel(true) -- позволяет окну иметь собственный стек клавиатуры/мыши

    self.windowLayerMap = self.windowLayerMap or {}
    self.windowLayerMap[windowType] = {
        strata   = self.NORMAL_STRATA,
        level    = base,
        priority = base,
    }

    PatronSystemNS.Logger:UI(("Установлен слой для %s: strata=%s level=%d")
        :format(tostring(windowType), self.NORMAL_STRATA, base))
end

-- Поднятие окна наверх при клике
function PatronSystemNS.UIManager:BringWindowToFront(windowType)
    local window = self.openWindows and self.openWindows[windowType]
    if not window or not window.GetFrame then return end
    local frame = window:GetFrame()
    if not frame then return end

    -- уже наверху? ничего не делаем
    if self:IsTop(windowType) then
        PatronSystemNS.Logger:UI(("Окно уже наверху: %s — подъём не требуется"):format(tostring(windowType)))
        return
    end

    -- берем текущий максимум и ставим на +1
    local currentMax = self:GetMaxFrameLevel()
    self.zCounter = math.max(self.zCounter or 400, currentMax) + 1

    -- перенормализация, если надо
    if self.zCounter > 9000 then
        local frames = {}
        for _, w in pairs(self.openWindows or {}) do
            local f = w.GetFrame and w:GetFrame()
            if f then table.insert(frames, f) end
        end
        table.sort(frames, function(a, b) return (a:GetFrameLevel() or 0) < (b:GetFrameLevel() or 0) end)
        local lvl = 300
        for _, f in ipairs(frames) do
            lvl = lvl + 1
            f:SetFrameLevel(lvl)
        end
        self.zCounter = lvl + 1
    end

    frame:SetFrameStrata(self.NORMAL_STRATA or "HIGH")
    frame:SetFrameLevel(self.zCounter)
    frame:SetToplevel(true)

    PatronSystemNS.Logger:UI(("Поднято окно наверх: %s (level=%d)"):format(tostring(windowType), self.zCounter))
end

function PatronSystemNS.UIManager:UpdateExistingWindowLayers()
    PatronSystemNS.Logger:UI("Обновление слоев существующих окон...")
    
    local windowsToUpdate = {
        {type = PatronSystemNS.Config.WindowType.MAIN, window = PatronSystemNS.MainWindow},
        {type = PatronSystemNS.Config.WindowType.PATRON, window = PatronSystemNS.PatronWindow},
        {type = PatronSystemNS.Config.WindowType.FOLLOWER, window = PatronSystemNS.FollowerWindow},
        {type = PatronSystemNS.Config.WindowType.BLESSING, window = PatronSystemNS.BlessingWindow},
        {type = PatronSystemNS.Config.WindowType.SHOP, window = PatronSystemNS.ShopWindow}
    }
    
    for _, windowData in ipairs(windowsToUpdate) do
        if windowData.window and windowData.window.GetFrame then
            self:SetWindowLayer(windowData.type, windowData.window)
            self.openWindows[windowData.type] = windowData.window
        end
    end
    
    PatronSystemNS.Logger:UI("Обновление слоев завершено")
end

function PatronSystemNS.UIManager:DebugWindowLayers()
    print("|cff00ff00[Window Layers Debug]|r")
    
    for windowType, layerInfo in pairs(self.windowLayerMap) do
        local window = self.openWindows[windowType]
        local isShown = window and window:IsShown() and "✓" or "✗"
        
        print("  " .. windowType .. ": " .. layerInfo.strata .. 
              " (level: " .. layerInfo.level .. 
              ", priority: " .. layerInfo.priority .. 
              ", shown: " .. isShown .. ")")
    end
end


--[[==========================================================================
  ОБРАБОТКА КОМАНД (УПРОЩЕННАЯ)
============================================================================]]
function PatronSystemNS.UIManager:HandleSlashCommand(command)
    PatronSystemNS.Logger:UI("Обработка команды: /" .. (command or ""))
    
    if not command or command == "" then
        -- ИСПРАВЛЕНО: Без параметров открываем MainWindow (как было)
        self:ToggleMainWindow()
        return
    end
    
    local args = {}
    for word in command:gmatch("%S+") do
        table.insert(args, word)
    end
    
    local mainCommand = args[1]:lower()
    
    local commandHandlers = {
        debug = function() 
            PatronSystemNS.Logger:ToggleDebug() 
            -- НОВОЕ: Переключаем также debug режим для UI элементов
            PatronSystemNS.debugMode = not PatronSystemNS.debugMode
            PatronSystemNS.Logger:Info("Debug mode " .. (PatronSystemNS.debugMode and "enabled" or "disabled"))
        end,
        test = function() PatronSystemNS.DialogueEngine:TestConnection() end,
        testdata = function()
            local patronID = tonumber(args[2]) or 1
            PatronSystemNS.DataManager:GetOrRequestSpeakerData(
                patronID,
                PatronSystemNS.Config.SpeakerType.PATRON,
                function(data)
                    print("|cff00ff00[Test]|r Callback получил данные: " .. (data.Name or "NO NAME"))
                end
            )
        end,
        testcache = function()
            local stats = PatronSystemNS.DataManager:GetCacheStats()
            local message = "Кэш: speakers=" .. stats.speakers .. 
                           ", dialogues=" .. stats.dialogues .. 
                           ", blessings=" .. stats.blessings ..
                           ", pending=" .. stats.pending
            print("|cff00ff00[Test]|r " .. message)
        end,
        patron = function()
            local patronID = tonumber(args[2]) or 1
            self:ShowMainWindow(PatronSystemNS.Config.SpeakerType.PATRON, patronID)
        end,
        patrons = function()
            -- НОВОЕ: Команда для "умного" открытия покровителей
            self:ShowPatronWindowSmart()
        end,
        follower = function()
            local followerID = tonumber(args[2]) or 101
            self:ShowMainWindow(PatronSystemNS.Config.SpeakerType.FOLLOWER, followerID)
        end,
        blessings = function()
            self:ShowBlessingWindow()
        end,
        shop = function()
            self:ShowShopWindow()
        end,
        main = function()
            self:ShowMainSelectionWindow()
        end,
        cache = function()
            if args[2] == "clear" then
                PatronSystemNS.DataManager:ClearCache()
                self:ShowMessage("Кэш очищен", "success")
            elseif args[2] == "stats" then
                local stats = PatronSystemNS.DataManager:GetCacheStats()
                local message = "Кэш: speakers=" .. stats.speakers .. ", dialogues=" .. stats.dialogues .. ", blessings=" .. stats.blessings
                self:ShowMessage(message, "info")
            else
                self:ShowMessage("Использование: /patron cache [clear|stats]", "info")
            end
        end,
        layers = function()
            self:DebugWindowLayers()
        end,
		
		testdb = function()
			AIO.Handle(PatronSystemNS.ADDON_PREFIX, "TestEvent", "Тест БД от клиента")
		end,

		testprayer = function()
			local patronId = tonumber(args[2]) or 1
			AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestPrayer", patronId)
		end,
		
		initplayer = function()
			PatronSystemNS.UIManager:RequestPlayerInit()
		end,

		resetprogress = function()
			PatronSystemNS.UIManager:ResetProgress()
		end,

		teststate = function()
			local stateType = args[2] or "default" -- default, test, advanced
			PatronSystemNS.UIManager:SetTestState(stateType)
		end,

		showprogress = function()
			local progress = PatronSystemNS.DataManager:GetPlayerProgress()
			if progress then
				local message = string.format("Прогресс: Души=%d, Страдания=%d, Покровителей=%d", 
					progress.souls or 0, 
					progress.suffering or 0, 
					progress.patrons and table.getn(progress.patrons) or 0)
				PatronSystemNS.UIManager:ShowMessage(message, "info")
			else
				PatronSystemNS.UIManager:ShowMessage("Прогресс не загружен", "warning")
			end
		end,
		
        fixlayers = function()
            self:UpdateExistingWindowLayers()
            self:ShowMessage("Слои окон обновлены", "success")
        end,
        close = function() self:CloseAllWindows() end,
        help = function() self:ShowHelp() end
    }
    
    local handler = commandHandlers[mainCommand]
    if handler then
        local success, err = pcall(handler)
        if not success then
            PatronSystemNS.Logger:Error("Ошибка команды " .. mainCommand .. ": " .. tostring(err))
            self:ShowMessage("Ошибка выполнения команды", "error")
        end
    else
        -- Проверяем если это число (ID покровителя)
        local speakerID = tonumber(mainCommand)
        if speakerID then
            self:ShowMainWindow(PatronSystemNS.Config.SpeakerType.PATRON, speakerID)
        else
            self:ShowMessage("Неизвестная команда: " .. mainCommand .. ". Используйте /patron help", "error")
        end
    end
end

function PatronSystemNS.UIManager:ShowHelp()
    local helpText = [[
Команды Patron System (НОВЫЕ ОКНА):
/patron - открыть/закрыть главное окно
/patron [1-3] - выбрать покровителя
/patron patron [ID] - окно покровителя
/patron follower [ID] - окно последователя
/patron blessings - окно благословений
/patron shop - окно магазина
/patron main - главное окно выбора
/patron debug - переключить отладку
/patron test - тест связи с сервером
/patron testdata [ID] - тест DataManager
/patron testcache - статистика кэша
/patron cache clear - очистить кэш
/patron cache stats - статистика кэша
/patron close - закрыть все окна
/patron help - эта справка
]]
    
    self:ShowMessage(helpText, "info")
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.UIManager:GetCurrentSpeaker()
    return self.currentSpeaker
end

function PatronSystemNS.UIManager:IsWindowOpen()
    return self.currentWindow and self.currentWindow:IsShown()
end

function PatronSystemNS.UIManager:IsPatronWindowOpen()
    local window = self.openWindows[PatronSystemNS.Config.WindowType.PATRON]
    return window and window:IsShown()
end

function PatronSystemNS.UIManager:GetOpenWindow(windowType)
    return self.openWindows[windowType]
end

function PatronSystemNS.UIManager:IsWindowOfTypeOpen(windowType)
    local window = self.openWindows[windowType]
    return window and window:IsShown()
end

-- Запросить инициализацию игрока
function PatronSystemNS.UIManager:RequestPlayerInit()
    PatronSystemNS.Logger:UI("Запрос инициализации игрока")
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestPlayerInit")
end

-- Сбросить прогресс (для тестирования)
function PatronSystemNS.UIManager:ResetProgress()
    PatronSystemNS.Logger:UI("Сброс прогресса игрока")
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "ResetPlayerProgress")
end

-- Установить тестовое состояние
function PatronSystemNS.UIManager:SetTestState(stateType)
    stateType = stateType or "default"
    PatronSystemNS.Logger:UI("Установка тестового состояния: " .. stateType)
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "SetTestPlayerState", stateType)
end

print("|cff00ff00[PatronSystem]|r UIManager загружен (ЭТАП 2 РЕФАКТОРИНГА + НОВЫЕ ОКНА)")