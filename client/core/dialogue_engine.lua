--[[==========================================================================
  PATRON SYSTEM - DIALOGUE ENGINE
  Универсальная система диалогов с сохранением состояния
============================================================================]]

-- Заполняем DialogueEngine в уже созданном неймспейсе
PatronSystemNS.DialogueEngine = {
    -- Состояние диалогов
    currentDialogue = nil,
    isInDialogueMode = false,
    currentSpeakerID = nil,
    currentSpeakerType = nil,
    dialogueHistory = {}, -- История диалогов для отката
    
    -- Флаги инициализации
    initialized = false
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.DialogueEngine:Initialize()
    if self.initialized then return end
    
    PatronSystemNS.Logger:Info("DialogueEngine инициализирован")
    self.initialized = true
    
    -- Регистрируем AIO обработчики
    --self:RegisterAIOHandlers()
end

--[[==========================================================================
  ОСНОВНЫЕ ФУНКЦИИ ДИАЛОГОВ
============================================================================]]
function PatronSystemNS.DialogueEngine:StartDialogue(speakerID, speakerType)
    PatronSystemNS.Logger:Dialogue("Начало диалога с " .. speakerID .. " (" .. speakerType .. ")")
    
    self.currentSpeakerID = speakerID
    self.currentSpeakerType = speakerType
    self.dialogueHistory = {}
    
    -- ИСПРАВЛЕНИЕ: Очищаем клиентский кэш диалогов для получения свежего серверного состояния
    local cacheKey = speakerType .. "_" .. speakerID
    if PatronSystemNS.DataManager.dialogueStateCache then
        PatronSystemNS.DataManager.dialogueStateCache[cacheKey] = nil
        PatronSystemNS.Logger:Dialogue("Очищен клиентский кэш диалога: " .. cacheKey)
    end
    
    -- ИСПРАВЛЕНИЕ: Всегда используем серверный StartDialogue для правильного MajorNode handling
    PatronSystemNS.Logger:Dialogue("Запрашиваем начальный диалог с сервера (игнорируем кэш)")
    self:RequestInitialDialogue(speakerID, speakerType)
end

function PatronSystemNS.DialogueEngine:ContinueDialogue(answerNodeID)
    if not self.currentSpeakerID or not self.currentSpeakerType then
        PatronSystemNS.Logger:Error("Попытка продолжить диалог без активного говорящего")
        return
    end
    
    PatronSystemNS.Logger:Dialogue("Продолжение диалога: выбран ответ " .. answerNodeID)
    
    -- Сохраняем текущий диалог в историю
    if self.currentDialogue then
        table.insert(self.dialogueHistory, self.currentDialogue)
    end
    
    -- ИСПРАВЛЕНИЕ: используем старое API для совместимости
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestNextDialogue", answerNodeID)
end

function PatronSystemNS.DialogueEngine:AdvanceDialogue()
    if not self.currentDialogue or not self.currentDialogue.id then
        PatronSystemNS.Logger:Error("Нет активного диалога для продвижения")
        return
    end
    
    PatronSystemNS.Logger:Dialogue("Продвижение диалога с узла " .. self.currentDialogue.id)
    
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestContinueDialogue", {
        nodeID = self.currentDialogue.id,
        speakerID = self.currentSpeakerID,
        speakerType = self.currentSpeakerType
    })
end

function PatronSystemNS.DialogueEngine:EndDialogue()
    PatronSystemNS.Logger:Dialogue("Завершение диалога")
    
    -- Запоминаем ID покровителя перед очисткой состояния
    local speakerId = self.currentSpeakerID
    
    self.isInDialogueMode = false
    self.currentDialogue = nil
    self.dialogueHistory = {}
    
    -- Уведомляем UI о завершении диалога
    if PatronSystemNS.UIManager then
        PatronSystemNS.UIManager:OnDialogueEnded()
    end
    
    -- НОВОЕ: Запрашиваем обновление SmallTalk после завершения диалога
    if speakerId and self.currentSpeakerType then
        PatronSystemNS.Logger:Dialogue("Запрашиваем обновление SmallTalk после завершения диалога")
        AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RefreshSmallTalk", {
            speakerId = speakerId,
            speakerType = self.currentSpeakerType
        })
    end
end

-- УДАЛЕНО: RestoreDialogueState больше не используется
-- Теперь всегда используем StartDialogue для корректного MajorNode handling

--[[==========================================================================
  СЕТЕВЫЕ ЗАПРОСЫ
============================================================================]]
function PatronSystemNS.DialogueEngine:RequestInitialDialogue(speakerID, speakerType)
    PatronSystemNS.Logger:AIO("Запрос начального диалога: " .. speakerID .. " (" .. speakerType .. ")")
    
    -- ИСПРАВЛЕНИЕ: Используем старое API для совместимости
    if speakerType == PatronSystemNS.Config.SpeakerType.PATRON then
        AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestInitialDialogue", speakerID)
    else
        AIO.Handle(PatronSystemNS.ADDON_PREFIX, "RequestInitialDialogue", {
            speakerID = speakerID,
            speakerType = speakerType
        })
    end
end

function PatronSystemNS.DialogueEngine:SaveDialogueState()
    if not self.currentDialogue or not self.currentSpeakerID then
        return
    end
    
    PatronSystemNS.Logger:Data("Сохранение состояния диалога: " .. self.currentDialogue.id)
    
    -- Используем DataManager для сохранения
    PatronSystemNS.DataManager:SaveDialogueState(
        self.currentSpeakerID,
        self.currentSpeakerType,
        self.currentDialogue.id
    )
end

--[[==========================================================================
  ОБРАБОТЧИКИ AIO (вызываются из main.lua)
============================================================================]]
function PatronSystemNS.DialogueEngine:OnDialogueReceived(data)
    PatronSystemNS.Logger:AIO("Получен диалог: " .. (data.text or "пустой"))
    
    self.currentDialogue = data
    self.isInDialogueMode = true
    
    -- ИСПРАВЛЕНИЕ: Сохраняем состояние только для MajorNode (сервер уже обрабатывает это)
    if data.id and data.isMajorNode then
        PatronSystemNS.Logger:Dialogue("Сохраняем MajorNode в клиентский кэш: " .. data.id)
        self:SaveDialogueState()
    elseif data.id then
        PatronSystemNS.Logger:Dialogue("Узел " .. data.id .. " не является MajorNode, не сохраняем в кэш")
    end
    
    -- ИСПРАВЛЕНИЕ: Используем систему событий вместо прямого вызова
    if PatronSystemNS.UIManager then
        -- БЫЛО: PatronSystemNS.UIManager:UpdateDialogue(data)
        -- СТАЛО: Используем систему событий
        PatronSystemNS.UIManager:TriggerEvent("DialogueUpdated", data)
    end
end

--[[==========================================================================
  РЕГИСТРАЦИЯ AIO ОБРАБОТЧИКОВ (не используется - обработчики в main.lua)
============================================================================]]
function PatronSystemNS.DialogueEngine:RegisterAIOHandlers()
    AIO.AddHandlers(PatronSystemNS.ADDON_PREFIX, {
        -- Получен новый диалог
        UpdateDialogue = function(_, data)
            PatronSystemNS.Logger:AIO("Получен диалог: " .. (data.text or "пустой"))
            
            PatronSystemNS.DialogueEngine.currentDialogue = data
            PatronSystemNS.DialogueEngine.isInDialogueMode = true
            
            -- Автоматически сохраняем состояние
            if data.id then
                PatronSystemNS.DialogueEngine:SaveDialogueState()
            end
            
            -- Обновляем UI
            if PatronSystemNS.UIManager then
                PatronSystemNS.UIManager:UpdateDialogue(data)
            end
        end,
        
        -- Выполнены действия диалога
        ActionsExecuted = function(_, data)
            PatronSystemNS.Logger:AIO("Результат выполнения действий: " .. (data.message or "неизвестно"))
            
            if data.success then
                -- Действия выполнены успешно - завершаем диалог
                PatronSystemNS.DialogueEngine:EndDialogue()
                
                -- Показываем сообщение пользователю
                if PatronSystemNS.UIManager then
                    PatronSystemNS.UIManager:ShowMessage(data.message, "success")
                end
            else
                -- Ошибка при выполнении действий
                PatronSystemNS.Logger:Error("Ошибка выполнения действий: " .. data.message)
                
                if PatronSystemNS.UIManager then
                    PatronSystemNS.UIManager:ShowMessage(data.message, "error")
                end
            end
        end,
        
        -- Тестовый ответ от сервера
        TestResponse = function(_, message)
            PatronSystemNS.Logger:AIO("Тестовый ответ от сервера: " .. tostring(message))
        end
    })
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.DialogueEngine:GetCurrentSpeaker()
    return {
        id = self.currentSpeakerID,
        type = self.currentSpeakerType
    }
end

function PatronSystemNS.DialogueEngine:IsInDialogue()
    return self.isInDialogueMode
end

function PatronSystemNS.DialogueEngine:GetCurrentDialogue()
    return self.currentDialogue
end

function PatronSystemNS.DialogueEngine:CanGoBack()
    return #self.dialogueHistory > 0
end

function PatronSystemNS.DialogueEngine:GoBack()
    if #self.dialogueHistory == 0 then
        PatronSystemNS.Logger:Warn("Нет истории диалогов для возврата")
        return
    end
    
    local previousDialogue = table.remove(self.dialogueHistory)
    self.currentDialogue = previousDialogue
    self.isInDialogueMode = true
    
    PatronSystemNS.Logger:Dialogue("Возврат к диалогу " .. previousDialogue.id)
    
    -- Обновляем UI
    if PatronSystemNS.UIManager then
        PatronSystemNS.UIManager:UpdateDialogue(previousDialogue)
    end
end

function PatronSystemNS.DialogueEngine:TestConnection()
    PatronSystemNS.Logger:AIO("Отправка тестового запроса на сервер")
    AIO.Handle(PatronSystemNS.ADDON_PREFIX, "TestEvent", "Тест связи от DialogueEngine")
end

print("|cff00ff00[PatronSystem]|r DialogueEngine загружен")