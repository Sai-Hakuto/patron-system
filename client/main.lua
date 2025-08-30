--[[==========================================================================
  PATRON SYSTEM - MAIN INITIALIZATION (ЭТАП 4 РЕФАКТОРИНГА)
  Централизованные AIO обработчики + чистая система событий
============================================================================]]

local AIO = AIO
local SafeCall = PatronSystemNS.SafeCall
if not AIO then
    print("|cffff0000[PatronSystem ERROR]|r AIO library is not available")
    return
end
if AIO.AddAddon() then return end

--[[==========================================================================
  ПРОВЕРКА ЗАГРУЗКИ МОДУЛЕЙ
============================================================================]]
local function ValidateModules()
    local requiredModules = {
        "Config", "Logger", "DialogueEngine", "UIManager", 
        "DataManager", "BaseWindow", "PatronWindow", "FollowerWindow"
    }
    
    local missingModules = {}
    for _, moduleName in ipairs(requiredModules) do
        if not PatronSystemNS[moduleName] then
            table.insert(missingModules, moduleName)
        end
    end
    
    if #missingModules > 0 then
        print("|cffff0000[PatronSystem ERROR]|r Не загружены модули: " .. table.concat(missingModules, ", "))
        return false
    end
    
    return true
end

--[[==========================================================================
  ЭТАП 4: ЦЕНТРАЛИЗОВАННАЯ СИСТЕМА СОБЫТИЙ
============================================================================]]

-- Центральный диспетчер событий для всей системы
local EventDispatcher = {
    listeners = {}
}

function EventDispatcher:RegisterListener(eventName, module, callback)
    if not self.listeners[eventName] then
        self.listeners[eventName] = {}
    end
    
    table.insert(self.listeners[eventName], {
        module = module,
        callback = callback
    })
    
    PatronSystemNS.Logger:Info("Зарегистрирован слушатель " .. module .. " для события " .. eventName)
end

function EventDispatcher:TriggerEvent(eventName, ...)
    local listeners = self.listeners[eventName]
    if not listeners then 
        PatronSystemNS.Logger:Debug("Нет слушателей для события: " .. eventName)
        return 
    end
    
    PatronSystemNS.Logger:Debug("Событие: " .. eventName .. " (" .. #listeners .. " слушателей)")
    
    for _, listener in ipairs(listeners) do
        SafeCall(listener.callback, ...)
    end
end



--[[==========================================================================
  ЭТАП 4: ЕДИНСТВЕННАЯ ТОЧКА AIO ОБРАБОТЧИКОВ
============================================================================]]
local function RegisterAIOHandlers()
    AIO.AddHandlers(PatronSystemNS.ADDON_PREFIX, {
        
        -- ДАННЫЕ ПОКРОВИТЕЛЕЙ
        UpdatePatronData = function(_, data)
            PatronSystemNS.Logger:AIO("Получены данные покровителя: " .. (data.Name or "Неизвестно"))
            
            -- Добавляем недостающие поля для совместимости
            data.SpeakerID = data.PatronID
            data.SpeakerType = PatronSystemNS.Config.SpeakerType.PATRON
            
            -- ЭТАП 4: Централизованная обработка через события
            EventDispatcher:TriggerEvent("DataReceived", data)
            EventDispatcher:TriggerEvent("SpeakerDataReceived", data)
        end,
        
        -- ДАННЫЕ ГОВОРЯЩИХ (универсальный обработчик)
        UpdateSpeakerData = function(_, data)
            PatronSystemNS.Logger:AIO("Получены данные говорящего: " .. (data.Name or "Неизвестно"))
            
            -- ЭТАП 4: Централизованная обработка через события
            EventDispatcher:TriggerEvent("DataReceived", data)
            EventDispatcher:TriggerEvent("SpeakerDataReceived", data)
        end,
        
        -- ДИАЛОГИ
        UpdateDialogue = function(_, data)
            PatronSystemNS.Logger:AIO("Получен диалог: " .. (data.text or "пустой"))
            
            -- ЭТАП 4: Централизованная обработка через события
            EventDispatcher:TriggerEvent("DialogueReceived", data)
            EventDispatcher:TriggerEvent("DialogueUpdated", data)
        end,
        
        -- РЕЗУЛЬТАТЫ ДЕЙСТВИЙ
        ActionsExecuted = function(_, data)
            PatronSystemNS.Logger:AIO("Результат действий: " .. (data.message or ""))

            if data.progressData then
                PatronSystemNS.DataManager:UpdatePlayerProgressCache(data.progressData)
            end

            if data.success then
                -- ЭТАП 4: События вместо прямых вызовов
                EventDispatcher:TriggerEvent("ActionsCompleted", data)
                EventDispatcher:TriggerEvent("DialogueEnded", data)
            else
                -- ЭТАП 4: События для ошибок
                EventDispatcher:TriggerEvent("ActionsFailed", data)
            end
        end,
        
        -- СОСТОЯНИЕ ДИАЛОГОВ
        DialogueStateLoaded = function(_, data)
            if data.nodeID then
                PatronSystemNS.Logger:AIO("Восстановлено состояние диалога: " .. data.nodeID)
                
                -- ЭТАП 4: События для состояния диалогов
                EventDispatcher:TriggerEvent("DialogueStateLoaded", data)
            end
        end,
		
		BlessingResult = function(_, data)
			PatronSystemNS.Logger:AIO("Результат благословения: " .. tostring(data.success))
			if data.success then
				PatronSystemNS.UIManager:ShowMessage(data.message, "success")
			else
				PatronSystemNS.UIManager:ShowMessage(data.message, "error")
			end
		end,

		PrayerResult = function(_, data)
			PatronSystemNS.Logger:AIO("Результат молитвы: " .. tostring(data.success))
			if data.success then
				PatronSystemNS.UIManager:ShowMessage(data.message, "success")
			else
				PatronSystemNS.UIManager:ShowMessage(data.message, "error")
			end
		end,
		
		PlayerInitialized = function(_, data)
			PatronSystemNS.Logger:AIO("Инициализация игрока: " .. tostring(data.isNewPlayer and "новый" or "существующий"))
			
			if data.error then
				PatronSystemNS.Logger:Error("Ошибка инициализации: " .. (data.message or "неизвестная ошибка"))
				PatronSystemNS.UIManager:ShowMessage("Ошибка загрузки данных игрока", "error")
				return
			end
			
			-- Сохраняем прогресс в DataManager
			if data.progressData then
				PatronSystemNS.DataManager:UpdatePlayerProgressCache(data.progressData)
				
				-- Логируем данные благословений
				local blessingCount = 0
				local blessingIds = {}
				if data.progressData.blessings then
					for id, blessing in pairs(data.progressData.blessings) do
						blessingCount = blessingCount + 1
						table.insert(blessingIds, id)
					end
				end
				
				PatronSystemNS.Logger:Info("Кэш игрока обновлен: souls=" .. (data.progressData.souls or 0) .. 
					", suffering=" .. (data.progressData.suffering or 0) .. 
					", blessings=" .. blessingCount .. 
					" [" .. table.concat(blessingIds, ", ") .. "]")
			else
				PatronSystemNS.Logger:Error("Данные прогресса отсутствуют в PlayerInitialized")
			end
			
			-- Показываем приветственное сообщение
			PatronSystemNS.UIManager:ShowMessage(data.message, data.isNewPlayer and "success" or "info")
			
			-- Если новый игрок, можем показать туториал
			if data.isNewPlayer then
				PatronSystemNS.Logger:Info("Новый игрок инициализирован")
				-- TODO: Показать туториал или подсказки для новых игроков
			end
			
			-- Триггерим событие для других систем
			EventDispatcher:TriggerEvent("PlayerInitialized", data)
		end,
		
                -- НОВОЕ: Обработчик обновления SmallTalk
                SmallTalkRefreshed = function(_, data)
                        PatronSystemNS.Logger:AIO("SmallTalk обновлен: " .. (data.speakerId or "неизвестно") ..
                            " (" .. (data.speakerType or "unknown") .. ")")

                        local eventId = tonumber(data.speakerId)
                        local cacheKey = data.speakerType .. "_" .. data.speakerId
                        local cachedData = PatronSystemNS.DataManager:GetFromCache(
                                PatronSystemNS.DataManager.speakerCache,
                                cacheKey
                        ) or {}

                        cachedData.smallTalk = data.smallTalk
                        cachedData.availableSmallTalks = data.availableSmallTalks
                        PatronSystemNS.DataManager:SetToCache(
                                PatronSystemNS.DataManager.speakerCache,
                                cacheKey,
                                cachedData
                        )

                        if data.speakerType == PatronSystemNS.Config.SpeakerType.PATRON then
                                if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() and
                                   not (PatronSystemNS.PatronWindow.state and PatronSystemNS.PatronWindow.state.inDialogue) and
                                   PatronSystemNS.PatronWindow.currentPatronID == eventId then

                                        PatronSystemNS.PatronWindow.currentSpeakerData = PatronSystemNS.PatronWindow.currentSpeakerData or {}
                                        PatronSystemNS.PatronWindow.currentSpeakerData.smallTalk = data.smallTalk
                                        PatronSystemNS.PatronWindow.elements.dialogText:SetText(data.smallTalk)
                                        PatronSystemNS.PatronWindow:AdjustDialogContainerSize(data.smallTalk)

                                        PatronSystemNS.Logger:Info("SmallTalk обновлен в окне: " .. string.sub(data.smallTalk, 1, 30) .. "...")
                                end
                        elseif data.speakerType == PatronSystemNS.Config.SpeakerType.FOLLOWER then
                                if PatronSystemNS.FollowerWindow and PatronSystemNS.FollowerWindow:IsShown() and
                                   not (PatronSystemNS.FollowerWindow.state and PatronSystemNS.FollowerWindow.state.inDialogue) and
                                   PatronSystemNS.FollowerWindow.currentFollowerID == eventId then

                                        PatronSystemNS.FollowerWindow.currentSpeakerData = PatronSystemNS.FollowerWindow.currentSpeakerData or {}
                                        PatronSystemNS.FollowerWindow.currentSpeakerData.smallTalk = data.smallTalk
                                        PatronSystemNS.FollowerWindow.elements.dialogText:SetText(data.smallTalk)
                                        PatronSystemNS.FollowerWindow:AdjustDialogContainerSize(data.smallTalk)

                                        PatronSystemNS.Logger:Info("SmallTalk обновлен в окне: " .. string.sub(data.smallTalk, 1, 30) .. "...")
                                end

                        end

                        -- Триггерим событие для других систем
                        EventDispatcher:TriggerEvent("SmallTalkRefreshed", data)
                end,
		
		PurchaseResult = function(_, data)
			PatronSystemNS.Logger:AIO("Результат покупки: " .. tostring(data.success))
			
			-- Передаем результат в ShopWindow
			if PatronSystemNS.ShopWindow and PatronSystemNS.ShopWindow.OnPurchaseResult then
				PatronSystemNS.ShopWindow:OnPurchaseResult(data.success, data.message, data)
			end
			
			-- Обновляем отображение валют если покупка успешна
			if data.success and data.newBalance and PatronSystemNS.DataManager then
				-- Обновляем кэш ресурсов игрока
				local progress = PatronSystemNS.DataManager:GetPlayerProgress()
				if progress then
					-- Здесь можно обновить отображение валют в UI
					PatronSystemNS.Logger:Info("Обновлен баланс после покупки")
				end
			end
		end,
		
		-- НОВОЕ: Обработчик обновления данных после разблокировки благословений
		DataUpdated = function(_, data)
			PatronSystemNS.Logger:AIO("Получено обновление данных после изменений")
			
			-- Обновляем кэш в DataManager
			if PatronSystemNS.DataManager and data then
				PatronSystemNS.DataManager:UpdatePlayerProgressCache(data)
				PatronSystemNS.Logger:Info("Кэш данных обновлен")
			end
			
			-- Триггерим событие для обновления UI
			EventDispatcher:TriggerEvent("DataUpdated", data)
		end,
		
		-- НОВОЕ: Ответ на обновление панели благословений
		BlessingPanelUpdated = function(_, data)
			PatronSystemNS.Logger:AIO("Панель благословений обновлена: " .. tostring(data.success))
			
			if data.success then
				PatronSystemNS.Logger:Info("Благословение " .. data.blessingId .. " " .. 
					(data.isInPanel and "добавлено в панель" or "убрано из панели"))
			end
		end,
		
		-- НОВОЕ: Обновление кулдаунов благословений
		UpdateCooldowns = function(_, cooldownData)
			-- Подсчитываем количество кулдаунов
			local cooldownCount = 0
			for _ in pairs(cooldownData or {}) do
				cooldownCount = cooldownCount + 1
			end
			
			PatronSystemNS.Logger:AIO("Получены данные кулдаунов, количество: " .. cooldownCount)
			
			-- Обновляем кулдауны в QuickBlessingWindow
			if PatronSystemNS.QuickBlessingWindow and PatronSystemNS.QuickBlessingWindow.UpdateCooldowns then
				PatronSystemNS.QuickBlessingWindow:UpdateCooldowns(cooldownData)
			end
		end,
		
		-- НОВОЕ: Обработчик ошибок благословений с подробной информацией
		BlessingError = function(_, errorData)
			PatronSystemNS.Logger:AIO("Ошибка благословения: " .. tostring(errorData.errorType))
			
			-- Показываем сообщение пользователю
			if errorData.message then
				PatronSystemNS.UIManager:ShowMessage(errorData.message, "error")
			end
			
			-- Триггерим событие для других систем
			EventDispatcher:TriggerEvent("BlessingError", errorData)
		end,
		
		-- ЛЕГКИЕ ОБНОВЛЕНИЯ РЕСУРСОВ (оптимизация производительности)
		ResourcesUpdated = function(_, data)
			PatronSystemNS.Logger:Debug("Получено обновление ресурсов: souls=" .. tostring(data.souls) .. ", suffering=" .. tostring(data.suffering))
			
			-- Обновляем кэш в DataManager
			local progressCache = PatronSystemNS.DataManager.playerProgressCache
			if progressCache then
				progressCache.souls = data.souls
				progressCache.suffering = data.suffering
				
				-- НЕ триггерим DataUpdated чтобы не сбрасывать кулдауны
				-- Вместо этого триггерим специальное событие только для ресурсов
				EventDispatcher:TriggerEvent("ResourcesOnlyUpdated", {souls = data.souls, suffering = data.suffering})
				
				-- Обновляем только главное окно (не затрагивая панель благословений)
				if PatronSystemNS.MainWindow and PatronSystemNS.MainWindow:IsShown() then
					PatronSystemNS.MainWindow:UpdatePlayerInfo()
				end
			end
		end,
		
		-- ОБРАБОТЧИКИ ПОКУПОК ЗА РЕСУРСЫ
		PurchaseError = function(_, data)
			PatronSystemNS.Logger:AIO("Ошибка покупки: " .. tostring(data.errorType))
			
			-- Показываем сообщение пользователю
			if data.message then
				PatronSystemNS.UIManager:ShowMessage(data.message, "error")
			end
			
			-- Триггерим событие для других систем
			EventDispatcher:TriggerEvent("PurchaseError", data)
		end,
		
		PurchaseSuccess = function(_, data)
			PatronSystemNS.Logger:AIO("Покупка успешна: " .. tostring(data.itemId))
			
			-- Показываем сообщение об успехе
			if data.message then
				PatronSystemNS.UIManager:ShowMessage(data.message, "success")
			end
			
			-- Триггерим событие для других систем
			EventDispatcher:TriggerEvent("PurchaseSuccess", data)
		end,
        
        -- ТЕСТОВЫЕ ОТВЕТЫ
        TestResponse = function(_, message)
            PatronSystemNS.Logger:AIO("Тестовый ответ от сервера: " .. tostring(message))
            
            -- ЭТАП 4: События для тестирования
            EventDispatcher:TriggerEvent("TestResponse", message)
        end
    })
    
    PatronSystemNS.Logger:Info("AIO обработчики зарегистрированы (ЭТАП 4 - ЦЕНТРАЛИЗОВАННО)")
end

--[[==========================================================================
  ЭТАП 4: РЕГИСТРАЦИЯ СЛУШАТЕЛЕЙ МОДУЛЕЙ
============================================================================]]
local function RegisterModuleListeners()
    
    -- DataManager слушает события данных
    EventDispatcher:RegisterListener("DataReceived", "DataManager", function(data)
        PatronSystemNS.DataManager:OnDataReceived(data)
    end)
    
    -- DialogueEngine слушает события диалогов
    EventDispatcher:RegisterListener("DialogueReceived", "DialogueEngine", function(data)
        PatronSystemNS.DialogueEngine:OnDialogueReceived(data)
    end)
    
    -- УДАЛЕНО: RestoreDialogueState больше не используется
    -- Теперь всегда используем StartDialogue для корректной обработки MajorNode
    
    -- ИСПРАВЛЕНИЕ: UIManager слушает события UI
    EventDispatcher:RegisterListener("SpeakerDataReceived", "UIManager", function(data)
        PatronSystemNS.UIManager:OnSpeakerDataReceived(data)
    end)
    
    EventDispatcher:RegisterListener("DialogueUpdated", "UIManager", function(data)
        PatronSystemNS.UIManager:OnDialogueUpdated(data)
    end)
    
    EventDispatcher:RegisterListener("DialogueEnded", "UIManager", function()
        PatronSystemNS.UIManager:OnDialogueEnded()
    end)
    
    EventDispatcher:RegisterListener("ActionsCompleted", "UIManager", function(data)
        PatronSystemNS.UIManager:ShowMessage(data.message or "Действие выполнено", "success")
        -- Завершаем диалог при успехе
        EventDispatcher:TriggerEvent("DialogueEnded", data)
    end)
    
    EventDispatcher:RegisterListener("ActionsFailed", "UIManager", function(data)
        PatronSystemNS.UIManager:ShowMessage(data.message or "Ошибка выполнения", "error")
    end)
    
    -- Тестовые слушатели
    EventDispatcher:RegisterListener("TestResponse", "TestLogger", function(message)
        print("|cff00ff00[PatronSystem Test]|r " .. tostring(message))
    end)
    
    -- НОВОЕ: Слушатель для SmallTalkRefreshed
    EventDispatcher:RegisterListener("SmallTalkRefreshed", "SmallTalkHandler", function(data)
        local t = data.patronId and "patron" or (data.followerId and "follower" or "unknown")
        PatronSystemNS.Logger:Info("SmallTalk refresh event processed for " .. t .. ": " .. (data.patronId or data.followerId or "unknown"))
    end)
    
    -- НОВОЕ: Слушатель для обновления данных благословений
    EventDispatcher:RegisterListener("DataUpdated", "BlessingWindow", function(data)
        PatronSystemNS.Logger:Info("Обновление данных получено - обновляем окно благословений")
        
        -- Обновляем окно благословений если оно открыто
        if PatronSystemNS.BlessingWindow and PatronSystemNS.BlessingWindow:IsShown() then
            PatronSystemNS.BlessingWindow:RefreshData()
            
            -- При обновлении данных с сервера - перезагружаем состояние панели
            PatronSystemNS.BlessingWindow:LoadPanelState()
            PatronSystemNS.Logger:Info("Окно благословений и панель обновлены")
        end
        
        -- Обновляем панель управления
        if PatronSystemNS.ControlPanel and PatronSystemNS.ControlPanel.UpdateAvailability then
            PatronSystemNS.ControlPanel.UpdateAvailability()
            PatronSystemNS.Logger:Info("Панель управления обновлена")
        end
        
        -- Обновляем быструю панель благословений
        if PatronSystemNS.QuickBlessingWindow and PatronSystemNS.QuickBlessingWindow.RefreshData then
            PatronSystemNS.QuickBlessingWindow:RefreshData()
            PatronSystemNS.Logger:Info("Быстрая панель благословений обновлена")
        end
        
        -- Обновляем главное окно с ресурсами
        if PatronSystemNS.MainWindow and PatronSystemNS.MainWindow:IsShown() then
            PatronSystemNS.MainWindow:UpdatePlayerInfo()
            PatronSystemNS.Logger:Info("Главное окно обновлено (ресурсы)")
        end
    end)
    
    -- Слушатель для инициализации игрока - обновляем панель
    EventDispatcher:RegisterListener("PlayerInitialized", "ControlPanel", function(data)
        PatronSystemNS.Logger:Info("Игрок инициализирован - обновляем панель управления")
        
        -- Небольшая задержка чтобы данные успели загрузиться
        C_Timer.After(1, function()
            if PatronSystemNS.ControlPanel and PatronSystemNS.ControlPanel.UpdateAvailability then
                PatronSystemNS.ControlPanel.UpdateAvailability()
                PatronSystemNS.Logger:Info("Панель управления обновлена после инициализации")
            end
            
            -- Обновляем MainWindow если оно открыто
            if PatronSystemNS.MainWindow and PatronSystemNS.MainWindow:IsShown() then
                PatronSystemNS.MainWindow:UpdatePlayerInfo()
                PatronSystemNS.Logger:Info("Главное окно обновлено после инициализации")
            end
        end)
    end)
    
    PatronSystemNS.Logger:Info("Слушатели модулей зарегистрированы (ИСПРАВЛЕНИЕ)Этап 5")
end

--[[==========================================================================
  ФУНКЦИИ ПРОВЕРКИ ДОСТУПНОСТИ КНОПОК
============================================================================]]
local function CheckFollowersAvailability()
    -- Проверяем есть ли у игрока доступ к фолловерам в кэше
    local progress = PatronSystemNS.DataManager:GetPlayerProgress()
    if not progress then 
        PatronSystemNS.Logger:Debug("CheckFollowersAvailability: нет данных прогресса")
        return false 
    end
    
    -- Проверяем наличие фолловеров (можно проверить конкретное поле или флаг)
    local hasFollowers = progress.followersUnlocked or (progress.followers and next(progress.followers) ~= nil)
    PatronSystemNS.Logger:Debug("CheckFollowersAvailability: " .. (hasFollowers and "доступны" or "недоступны"))
    return hasFollowers
end

local function CheckBlessingPanelAvailability()
    -- Проверяем есть ли у игрока благословения с флагом isInPanel (camelCase как в blessing_window)
    local progress = PatronSystemNS.DataManager:GetPlayerProgress()
    if not progress or not progress.blessings then 
        PatronSystemNS.Logger:Debug("CheckBlessingPanelAvailability: нет данных прогресса или благословений")
        return false 
    end
    
    -- Проверяем наличие благословений с флагом isInPanel = true
    for blessingId, blessing in pairs(progress.blessings) do
        if blessing.isInPanel and blessing.isDiscovered then
            PatronSystemNS.Logger:Debug("CheckBlessingPanelAvailability: найдено благословение в панели: " .. tostring(blessingId))
            return true
        end
    end
    
    PatronSystemNS.Logger:Debug("CheckBlessingPanelAvailability: не найдено активных благословений в панели")
    return false
end

--[[==========================================================================
  СОЗДАНИЕ ГЛАВНОГО UI
============================================================================]]
local function CreateMainUI()
    -- Создаем компактную панель управления с квадратными кнопками
    PatronSystemNS.Logger:Debug("Создание компактной панели управления...")
    
    -- Главная панель
    local mainPanel = CreateFrame("Frame", "PatronControlPanel", UIParent, "BackdropTemplate")
    mainPanel:SetSize(200, 70) -- увеличена ширина и высота для заголовка
    mainPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    mainPanel:SetMovable(true)
    mainPanel:EnableMouse(true)
    mainPanel:RegisterForDrag("LeftButton")
    mainPanel:SetScript("OnDragStart", mainPanel.StartMoving)
    mainPanel:SetScript("OnDragStop", mainPanel.StopMovingOrSizing)
    
    -- Фон панели (непрозрачный как в client_solution)
    local bg = mainPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.95) -- почти непрозрачный темный фон
    
    -- Заголовок панели
    local title = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mainPanel, "TOP", 0, -8)
    title:SetText("Patron System")
    title:SetTextColor(0.8, 0.8, 0.9, 1)
    
    -- Конфигурация кнопок
    local buttonConfig = {
        {
            id = "main",
            text = "M",
            tooltip = "Главное окно покровителей",
            color = PatronSystemNS.Config:GetColor("patronVoid"),
            onClick = function()
                PatronSystemNS.Logger:Info("Нажата кнопка Main Window")
                if PatronSystemNS.UIManager and PatronSystemNS.UIManager.ToggleMainWindow then
                    PatronSystemNS.UIManager:ToggleMainWindow()
                else
                    PatronSystemNS.Logger:Error("UIManager или ToggleMainWindow не доступны!")
                end
            end
        },
        {
            id = "followers",
            text = "F",
            tooltip = "Управление фолловерами",
            color = PatronSystemNS.Config:GetColor("patronDragon"),
            checkAvailability = CheckFollowersAvailability,
            onClick = function()
                PatronSystemNS.Logger:Info("Нажата кнопка Followers")
                if CheckFollowersAvailability() then
                    PatronSystemNS.UIManager:ShowMessage("Панель фолловеров будет реализована позже", "info")
                else
                    PatronSystemNS.UIManager:ShowMessage("Невозможно открыть панель фолловеров - они не открыты", "error")
                end
            end
        },
        {
            id = "blessings",
            text = "B",
            tooltip = "Быстрая панель благословений",
            color = PatronSystemNS.Config:GetColor("patronEluna"),
            checkAvailability = CheckBlessingPanelAvailability,
            onClick = function()
                PatronSystemNS.Logger:Info("Нажата кнопка Blessings")
                if CheckBlessingPanelAvailability() then
                    -- Открываем быструю панель благословений
                    if PatronSystemNS.QuickBlessingWindow then
                        PatronSystemNS.QuickBlessingWindow:Toggle()
                    else
                        PatronSystemNS.Logger:Error("QuickBlessingWindow не загружен!")
                        PatronSystemNS.UIManager:ShowMessage("Ошибка загрузки панели благословений", "error")
                    end
                else
                    PatronSystemNS.UIManager:ShowMessage("Невозможно открыть панель благословений - нет активных благословений", "error")
                end
            end
        }
    }
    
    -- Создание кнопок
    local buttonSize = 40
    local spacing = 12 -- увеличенный интервал между кнопками
    local startX = (mainPanel:GetWidth() - (3 * buttonSize + 2 * spacing)) / 2
    
    for i, config in ipairs(buttonConfig) do
        local button = CreateFrame("Button", "PatronControlButton_" .. config.id, mainPanel, "BackdropTemplate")
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", startX + (i - 1) * (buttonSize + spacing), -26) -- сдвинуты ниже для заголовка
        
        -- Фон кнопки в стиле баннеров
        button:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        
        -- Применяем цвета в стиле баннеров
        local C = config.color
        local S = PatronSystemNS.UIStyle or { BASE_MULT = 0.30, HOVER_MULT = 0.60, FLASH_ALPHA = 0.80, FLASH_TIME = 0.10 }
        
        -- Текст кнопки
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        text:SetText(config.text)
        button.title = text
        
        -- Проверяем доступность кнопки (кнопка [M] всегда доступна)
        local isAvailable = true
        if config.checkAvailability then
            isAvailable = config.checkAvailability()
        end
        
        -- Функция для установки базового цвета
        local function setBaseColor()
            if isAvailable then
                button:SetBackdropColor(C.r * S.BASE_MULT, C.g * S.BASE_MULT, C.b * S.BASE_MULT, 0.8)
                button:SetBackdropBorderColor(C.r, C.g, C.b, 1)
                text:SetTextColor(C.r, C.g, C.b, 1)
            else
                -- Заблокированный вид - серый и тусклый
                button:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
                button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                text:SetTextColor(0.5, 0.5, 0.5, 0.8)
            end
        end
        
        -- Функция обновления доступности (будет вызываться при изменении данных)
        button.UpdateAvailability = function()
            if config.checkAvailability then
                isAvailable = config.checkAvailability()
            end
            setBaseColor()
        end
        
        -- ИСПРАВЛЕНИЕ: Принудительно устанавливаем цвет в следующем фрейме
        -- чтобы избежать проблем с инициализацией цветовой схемы
        C_Timer.After(0.1, function()
            setBaseColor()
        end)
        
        -- Тултип с информацией о блокировке
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(config.tooltip)
            if not isAvailable then
                GameTooltip:AddLine("Недоступно", 1, 0.3, 0.3) -- красный текст для заблокированных
            end
            GameTooltip:Show()
            
            -- Цвет при наведении только для доступных кнопок
            if isAvailable then
                button:SetBackdropColor(C.r * S.HOVER_MULT, C.g * S.HOVER_MULT, C.b * S.HOVER_MULT, 1.0)
                button:SetBackdropBorderColor(1, 1, 1, 1)
                text:SetTextColor(1, 1, 1, 1)
            end
        end)
        
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            -- Возврат к базовому цвету
            setBaseColor()
        end)
        
        button:SetScript("OnClick", function()
            -- Обновляем статус доступности перед кликом
            if config.checkAvailability then
                isAvailable = config.checkAvailability()
            end
            
            if not isAvailable then
                -- Для заблокированных кнопок - никаких эффектов, только выполняем onClick
                if config.onClick then config.onClick() end
                return
            end
            
            -- Эффект вспышки только для доступных кнопок
            button:SetBackdropColor(1, 1, 1, S.FLASH_ALPHA)
            text:SetTextColor(0, 0, 0, 1)
            
            C_Timer.After(S.FLASH_TIME, function()
                setBaseColor()
                if config.onClick then config.onClick() end
            end)
        end)
    end
    
    -- Сохраняем панель для возможности обновления
    PatronSystemNS.ControlPanel = {
        frame = mainPanel,
        buttons = {},
        UpdateAvailability = function()
            for _, btn in pairs(PatronSystemNS.ControlPanel.buttons) do
                if btn.UpdateAvailability then
                    btn.UpdateAvailability()
                end
            end
        end
    }
    
    -- Сохраняем кнопки для обновления
    for i, config in ipairs(buttonConfig) do
        local buttonName = "PatronControlButton_" .. config.id
        local btn = _G[buttonName]
        if btn then
            PatronSystemNS.ControlPanel.buttons[config.id] = btn
        end
    end
    
    -- ИСПРАВЛЕНИЕ: Дополнительное обновление цветов после создания всех кнопок
    C_Timer.After(0.2, function()
        PatronSystemNS.Logger:Debug("Обновление цветов панели управления...")
        if PatronSystemNS.ControlPanel and PatronSystemNS.ControlPanel.UpdateAvailability then
            PatronSystemNS.ControlPanel.UpdateAvailability()
        end
    end)
    
    PatronSystemNS.Logger:Debug("Компактная панель управления создана")
    
    -- Регистрация слеш-команд
    PatronSystemNS.Logger:Debug("Регистрация слеш-команд...")
    
    SLASH_PATRON1 = "/patron"
    SLASH_PATRON2 = "/покровители"
    
    SlashCmdList["PATRON"] = function(msg)
        PatronSystemNS.Logger:Debug("=== СЛЕШ-КОМАНДА ПОЛУЧЕНА ===")
        PatronSystemNS.Logger:Debug("Аргумент: '" .. tostring(msg) .. "'")
        
        local success, err = pcall(function()
            PatronSystemNS.UIManager:HandleSlashCommand(msg)
        end)
        
        if not success then
            print("|cffff0000[ERROR]|r Ошибка в слеш-команде: " .. tostring(err))
        else
            PatronSystemNS.Logger:Debug("Слеш-команда выполнена успешно")
        end
    end
    
    -- Команда для фолловеров
    SLASH_FOLLOWER1 = "/follower"
    SLASH_FOLLOWER2 = "/фолловеры"
    
    SlashCmdList["FOLLOWER"] = function(msg)
        PatronSystemNS.Logger:Debug("=== КОМАНДА ФОЛЛОВЕРОВ ПОЛУЧЕНА ===")
        PatronSystemNS.Logger:Debug("Аргумент: '" .. tostring(msg) .. "'")
        
        local success, err = pcall(function()
            if msg and msg ~= "" then
                local followerID = tonumber(msg)
                if followerID then
                    PatronSystemNS.UIManager:ShowFollowerWindow(followerID)
                else
                    PatronSystemNS.UIManager:ShowFollowerWindow()
                end
            else
                PatronSystemNS.UIManager:ShowFollowerWindow()
            end
        end)
        
        if not success then
            print("|cffff0000[FOLLOWER ERROR]|r Ошибка в команде фолловера: " .. tostring(err))
        else
            PatronSystemNS.Logger:Debug("Команда фолловера выполнена успешно")
        end
    end
    
    -- Тестовая команда
    SLASH_PATRONTEST1 = "/patrontest"
    SlashCmdList["PATRONTEST"] = function(msg)
        PatronSystemNS.Logger:Debug("=== ТЕСТОВАЯ КОМАНДА ===")
        
        local success, err = pcall(function()
            if msg and msg ~= "" then
                local patronID = tonumber(msg)
                if patronID then
                    PatronSystemNS.UIManager:ShowPatronWindow(patronID)
                else
                    print("|cff00ff00[TEST]|r Не удалось парсить: " .. msg)
                end
            else
                PatronSystemNS.UIManager:ToggleMainWindow()
            end
        end)
        
        if not success then
            print("|cffff0000[TEST ERROR]|r " .. tostring(err))
        end
    end
    
    PatronSystemNS.Logger:Info("Главный UI создан (ЭТАП 4)")
end

--[[==========================================================================
  ЭТАП 4: РАСШИРЕННЫЕ ТЕСТОВЫЕ КОМАНДЫ
============================================================================]]
local function CreateTestCommands()
    -- Команды для тестирования централизованной системы событий
    
    -- Добавляем новые команды в UIManager через события
    EventDispatcher:RegisterListener("TestCommand", "TestHandler", function(command, args)
        if command == "events" then
            -- Показать все зарегистрированные события
            print("|cff00ff00[Events Test]|r Зарегистрированные события:")
            for eventName, listeners in pairs(EventDispatcher.listeners) do
                print("  " .. eventName .. " (" .. #listeners .. " слушателей)")
            end
            
        elseif command == "trigger" then
            -- Триггер тестового события
            local eventName = args[2] or "TestEvent"
            print("|cff00ff00[Events Test]|r Триггер события: " .. eventName)
            EventDispatcher:TriggerEvent(eventName, "test data")
            
        elseif command == "modules" then
            -- Проверка состояния модулей
            print("|cff00ff00[Modules Test]|r Состояние модулей:")
            for moduleName, module in pairs(PatronSystemNS) do
                if type(module) == "table" and module.initialized ~= nil then
                    print("  " .. moduleName .. ": " .. (module.initialized and "✓" or "✗"))
                end
            end
        end
    end)
    
    PatronSystemNS.Logger:Info("Тестовые команды для ЭТАПА 4 созданы")
end

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ СИСТЕМЫ (ЭТАП 4)
============================================================================]]
local function Initialize()
    PatronSystemNS.Logger:Info("=== Начало инициализации Patron System v" .. PatronSystemNS.VERSION .. " (ЭТАП 4 РЕФАКТОРИНГА) ===")
    
    -- 1. Проверяем модули
    if not ValidateModules() then
        PatronSystemNS.Logger:Error("КРИТИЧЕСКАЯ ОШИБКА: Не все модули загружены!")
        return false
    end
    
    -- 2. Инициализируем модули в правильном порядке
    PatronSystemNS.Logger:Info("Инициализация модулей...")
    
    if PatronSystemNS.Logger.Initialize then
        PatronSystemNS.Logger:Initialize()
    end
    
    if PatronSystemNS.DataManager.Initialize then
        PatronSystemNS.DataManager:Initialize()
    end
    
    if PatronSystemNS.DialogueEngine.Initialize then
        PatronSystemNS.DialogueEngine:Initialize()
    end
    
    if PatronSystemNS.UIManager.Initialize then
        PatronSystemNS.UIManager:Initialize()
    end
    
    if PatronSystemNS.BaseWindow.Initialize then
        PatronSystemNS.BaseWindow:Initialize()
    end
    
    if PatronSystemNS.PatronWindow.Initialize then
        PatronSystemNS.PatronWindow:Initialize()
    end
    
    if PatronSystemNS.FollowerWindow.Initialize then
        PatronSystemNS.FollowerWindow:Initialize()
    end
    
    -- Инициализируем все остальные окна для сохранения позиций
    if PatronSystemNS.BlessingWindow and PatronSystemNS.BlessingWindow.Initialize then
        PatronSystemNS.BlessingWindow:Initialize()
    end
    
    if PatronSystemNS.MainWindow and PatronSystemNS.MainWindow.Initialize then
        PatronSystemNS.MainWindow:Initialize()
    end
    
    if PatronSystemNS.QuickBlessingWindow and PatronSystemNS.QuickBlessingWindow.Initialize then
        PatronSystemNS.QuickBlessingWindow:Initialize()
        PatronSystemNS.Logger:Info("QuickBlessingWindow инициализирован")
    else
        PatronSystemNS.Logger:Info("QuickBlessingWindow готов к использованию")
    end

    
    -- 3. ЭТАП 4: Регистрируем централизованную систему событий
    PatronSystemNS.Logger:Info("Регистрация централизованной системы событий...")
    RegisterModuleListeners()
    
    -- 4. ЭТАП 4: Регистрируем AIO обработчики централизованно
    PatronSystemNS.Logger:Info("Регистрация централизованных AIO обработчиков...")
    RegisterAIOHandlers()
    
    -- 5. Создаем UI
    CreateMainUI()
    
    -- 6. ЭТАП 4: Создаем расширенные тестовые команды
    CreateTestCommands()
    
    -- 7. Тестируем связь с сервером
    PatronSystemNS.Logger:Info("Отправка тестового запроса на сервер...")
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "TestEvent", "Запуск клиента v" .. PatronSystemNS.VERSION .. " (ЭТАП 4)")
    
    PatronSystemNS.Logger:Info("=== Patron System успешно инициализирован! (ЭТАП 4 РЕФАКТОРИНГА) ===")
    PatronSystemNS.Logger:Info("Команды: /patron [debug|test|testdata|testcache|events|trigger|modules|1-3|help]")
    PatronSystemNS.Logger:Info("НОВЫЕ команды ЭТАП 4:")
    PatronSystemNS.Logger:Info("  /patron events - список зарегистрированных событий")
    PatronSystemNS.Logger:Info("  /patron trigger [event] - триггер тестового события")
    PatronSystemNS.Logger:Info("  /patron modules - состояние модулей")
    
	C_Timer.After(2, function() -- Ждем 2 секунды после загрузки аддона
		PatronSystemNS.Logger:Info("Запуск автоматической инициализации игрока...")
		PatronSystemNS.UIManager:RequestPlayerInit()
	end)
	
    return true
end

--[[==========================================================================
  ЗАПУСК С ОБРАБОТКОЙ ОШИБОК
============================================================================]]
local initSuccess, initError = pcall(Initialize)

if not initSuccess then
    print("|cffff0000[PatronSystem FATAL ERROR]|r " .. tostring(initError))
    print("|cffff0000[PatronSystem FATAL ERROR]|r Проверьте TOC файл и порядок загрузки модулей!")
    
    -- В случае критической ошибки создаем минимальный UI для отладки
    local errorButton = CreateFrame("Button", "PatronErrorButton", UIParent, "UIPanelButtonTemplate")
    errorButton:SetSize(150, 24)
    errorButton:SetText("PatronSystem [ОШИБКА]")
    errorButton:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    errorButton:SetScript("OnClick", function()
        print("|cffff0000[PatronSystem]|r Система не инициализирована из-за ошибки:")
        print("|cffff0000[PatronSystem]|r " .. tostring(initError))
    end)
else
    PatronSystemNS.Logger:Info("Система готова к работе! (ЭТАП 4 РЕФАКТОРИНГА ЗАВЕРШЕН)")
    
    -- ЭТАП 4: Экспортируем EventDispatcher для отладки
    PatronSystemNS.EventDispatcher = EventDispatcher

end
