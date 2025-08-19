--[[==========================================================================
  PATRON SYSTEM - MAIN INITIALIZATION (ЭТАП 4 РЕФАКТОРИНГА)
  Централизованные AIO обработчики + чистая система событий
============================================================================]]

local AIO = AIO or require("AIO")
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
        local success, err = pcall(listener.callback, ...)
        if not success then
            PatronSystemNS.Logger:Error("Ошибка в " .. listener.module .. " при обработке " .. eventName .. ": " .. tostring(err))
        end
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
				PatronSystemNS.Logger:Info("Кэш игрока обновлен: souls=" .. (data.progressData.souls or 0) .. ", suffering=" .. (data.progressData.suffering or 0))
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
			PatronSystemNS.Logger:AIO("SmallTalk обновлен для покровителя: " .. (data.patronId or "неизвестно"))
			
			-- Обновляем данные в UIManager если он отображает этого покровителя
			if PatronSystemNS.UIManager.currentSpeaker and 
			   PatronSystemNS.UIManager.currentSpeaker.PatronID == data.patronId then
				
				-- Обновляем текущую SmallTalk фразу
				PatronSystemNS.UIManager.currentSpeaker.smallTalk = data.smallTalk
				PatronSystemNS.UIManager.currentSpeaker.availableSmallTalks = data.availableSmallTalks
				
				-- Если окно открыто и НЕ в режиме диалога - показываем новую фразу
				if PatronSystemNS.PatronWindow and PatronSystemNS.PatronWindow:IsShown() and 
				   not PatronSystemNS.PatronWindow.isInDialogueMode then
					
					PatronSystemNS.PatronWindow.elements.dialogText:SetText(data.smallTalk)
					PatronSystemNS.PatronWindow:AdjustDialogContainerSize(data.smallTalk)
					
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
        PatronSystemNS.Logger:Info("SmallTalk refresh event processed for patron: " .. (data.patronId or "unknown"))
    end)
    
    PatronSystemNS.Logger:Info("Слушатели модулей зарегистрированы (ИСПРАВЛЕНИЕ)Этап 5")
end

--[[==========================================================================
  СОЗДАНИЕ ГЛАВНОГО UI
============================================================================]]
local function CreateMainUI()
    -- Создаем главную кнопку с защитой от ошибок
    PatronSystemNS.Logger:Debug("Создание главной кнопки...")
    
    local mainButton = CreateFrame("Button", "PatronMainButton", UIParent, "UIPanelButtonTemplate")
    mainButton:SetSize(120, 24)
    mainButton:SetText("Покровители")
    mainButton:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    
    mainButton:SetScript("OnClick", function() 
        PatronSystemNS.Logger:Debug("=== КНОПКА НАЖАТА ===")
        
        local success, err = pcall(function()
            PatronSystemNS.Logger:Info("Нажата главная кнопка 'Покровители'")
            
            -- ИСПРАВЛЕНИЕ: Проверяем существование UIManager и метода
            if not PatronSystemNS.UIManager then
                PatronSystemNS.Logger:Error("UIManager не загружен!")
                print("|cffff0000[ERROR]|r UIManager не загружен!")
                return
            end
            
            if not PatronSystemNS.UIManager.ToggleMainWindow then
                PatronSystemNS.Logger:Error("Метод ToggleMainWindow не найден!")
                print("|cffff0000[ERROR]|r Метод ToggleMainWindow не найден!")
                return
            end
            
            -- Обычный вызов если всё в порядке
            PatronSystemNS.UIManager:ToggleMainWindow()
        end)
        
        if not success then
            print("|cffff0000[ERROR]|r Ошибка в OnClick: " .. tostring(err))
            PatronSystemNS.Logger:Error("Ошибка в OnClick: " .. tostring(err))
        else
            PatronSystemNS.Logger:Debug("OnClick выполнен успешно")
        end
    end)
    
    PatronSystemNS.Logger:Debug("Главная кнопка создана с улучшенной защитой")
    
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
	
	if PatronSystemNS.PatronWindow.Initialize then
        PatronSystemNS.PatronWindow:Initialize()
    end
    
    if PatronSystemNS.FollowerWindow.Initialize then
        PatronSystemNS.FollowerWindow:Initialize()
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