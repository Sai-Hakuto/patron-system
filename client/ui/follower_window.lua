--[[===========================================================================
  PATRON SYSTEM - FOLLOWER WINDOW (на базе BaseWindow v2)
  Практически копия PatronWindow, но для фолловеров и только по открытым
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

NS.FollowerWindowState = NS.FollowerWindowState or { lastFollowerID = nil }
local GLB = NS.FollowerWindowState

-- Небольшой helper для римских цифр ранга
local function Roman(n)
  local t = { "I","II","III","IV","V","VI","VII","VIII","IX","X" }
  n = tonumber(n or 1) or 1
  if n < 1 then n = 1 end
  if n > #t then n = #t end
  return t[n]
end

-- Попытка получить портрет по CharacterData/ключу эмоции
local function ResolvePortraitByFollowerID(self, followerID)
  -- 1) через CharacterData: DefaultPortrait -> ключ -> путь
  local CD = NS.Characters or {}
  local char = CD[followerID]
  local key = char and char.DefaultPortrait
  if key then
    local map = (NS.PatronWindow and NS.PatronWindow.characterPortraitPaths) or self.characterPortraitPaths or {}
    if map[key] then return map[key] end
  end
  -- 2) локальный фолбэк
  return "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior.png"
end

-- Создаём объект окна на базе BaseWindow
NS.FollowerWindow = BW:New("FollowerWindow", {
  windowType = NS.Config.WindowType and NS.Config.WindowType.FOLLOWER or nil,

  hooks = {
    onInit = function(self)
      -- Заголовок
      self.elements.title:SetText("Система Последователей")

      -- ===== СЕЛЕКТОР (табы) ТОЛЬКО ПО ОТКРЫТЫМ ФОЛЛОВЕРАМ =====
      local items = {}
      
      -- Левая / правая панели
      local left, right = self:CreateLeftRightPanels()

      -- Портрет
      local portraitFrame, portraitTex = self:CreatePortrait(left, { width = 160, height = 200 })
      self.elements.portraitFrame = portraitFrame
      self.elements.portrait      = portraitTex
      local startId = self.lastFollowerID -- может быть nil
		portraitTex:SetTexture(ResolvePortraitByFollowerID(self, startId))
      -- Информация под портретом (Алаймент + Ранг)
      local info = self:CreateInfoText(left)
      info:SetPoint("TOP", portraitTex, "BOTTOM", 0, -10)
      info:SetText("Алаймент: Неизвестно\nРанг: I")
      self.elements.infoText = info

      -- Кнопки действий (как у покровителя, но набор follower из Config)
      local aCfg = NS.Config:GetUIConfig("actionButtons") or {}
      local actions = {}
      for _, act in ipairs(NS.Config:GetActionsByType(NS.Config.SpeakerType.FOLLOWER) or {}) do
        table.insert(actions, {
          id = act.id,
          text = act.text,
          onClick = function(id) self:HandleAction(id) end
        })
      end
      if #actions == 0 then
        -- безопасный фолбэк
        actions = {
          { id = "TALK",         text = "Говорить" },
          { id = "EXIT_DIALOGUE",text = "Выход"    },
        }
      end
      self.state.actionButtons = self:CreateActionButtons(left, actions, {
        cols     = 2,
        spacingX = aCfg.spacingX or 10,
        spacingY = aCfg.spacingY or 35,
        pitchY   = aCfg.spacingY or 35,
        width    = aCfg.width   or 120,
        height   = aCfg.height  or 24,
        anchor   = { frame = self.elements.infoText, point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -20 }
      })

      -- Подтянуть высоту левой панели под количество рядов кнопок (чтобы всё влезло)
      local rows = math.ceil(#actions / 2)
      self:EnsureLeftPanelHeightForActions(rows, {
        pitchY = aCfg.spacingY or 35,
        spacingY = aCfg.spacingY or 35,
        height = aCfg.height or 24
      })

      -- Правая панель: Описание, Диалог, Ответы
      local pad = 10

      local desc = self:CreateText(right, {
        template = "GameFontHighlightSmall",
        width    = right:GetWidth() - pad*2,
        justify  = "LEFT",
        point    = { right, "TOPLEFT", "TOPLEFT", pad, 0 },
        text     = "Выберите открытого последователя, чтобы начать взаимодействие."
      })
      self.elements.descText = desc

      local dc = NS.Config:GetUIConfig("dialogContainer") or {}
      local dialogContainer, dialogText = self:CreateDialogueContainer(right, {
        width     = (dc.width and (dc.width - pad*2)) or (right:GetWidth() - pad*2),
        minHeight = dc.minHeight,
        maxHeight = dc.maxHeight,
        point     = { self.elements.descText, "BOTTOMLEFT", "BOTTOMLEFT", 0, -15 },
      })
      self.elements.dialogContainer = dialogContainer
      self.elements.dialogText      = dialogText
      dialogText:SetText("Нажмите «Говорить», чтобы начать диалог с последователем.")

      -- Контейнер ответов
      self.replies = self:CreateReplyContainer(self.elements.rightPanel, NS.Config:GetUIConfig("replyButtons"))

      -- Инициализация состояния
      self.currentFollowerID = nil
      self.lastFollowerID    = nil

      -- Локальная карта портретов на случай отсутствия общей (необязательно)
      self.characterPortraitPaths = self.characterPortraitPaths or {
        shadow_warrior_default   = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior.png",
        arlekino_default         = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino.png",
        moon_priestess_default   = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess.png",
      }

      -- построим панель табов согласно текущему кэшу прогресса
      self:BuildFollowerSelectors()

      -- стартовая автоподгонка
      local initText = self.elements.dialogText and self.elements.dialogText:GetText() or ""
      self:AutoSizeWindow(initText, 0, false)
    end
  }
})

-- Возвращает список ID открытых фолловеров (isDiscovered/isActive)
function NS.FollowerWindow:GetUnlockedFollowerIDs()
  local ids = {}
  local progress = NS.DataManager and NS.DataManager:GetPlayerProgress()
  local map = progress and progress.followers or nil
  if not map or type(map) ~= "table" then return ids end

  for k, v in pairs(map) do
    local opened = (type(v)=="table") and ((v.isDiscovered==true) or (v.isActive==true))
    if opened then table.insert(ids, tonumber(k) or k) end
  end
  
  -- ИСПРАВЛЕНО: Числовая сортировка вместо алфавитной
  table.sort(ids, function(a,b) return tonumber(a) < tonumber(b) end)
  return ids
end

-- Строим верхний селектор из имён открытых фолловеров
function NS.FollowerWindow:BuildFollowerSelectors()
  self:ClearSelectorBar()

  local unlocked = self:GetUnlockedFollowerIDs()
  if #unlocked == 0 then
    self:ShowBanner("Система последователей недоступна.\nОткройте последователей через диалоги покровителей.")
    return
  end
  self:HideBanner()

  local items = {}
  for _, fid in ipairs(unlocked) do
    local sp = NS.Config:GetSpeakerByID(fid, NS.Config.SpeakerType.FOLLOWER)
    local name = (sp and sp.name) or (NS.Characters[fid] and NS.Characters[fid].Name) or ("Follower "..tostring(fid))
    table.insert(items, { id=fid, text=name, onClick=function(id) self:SelectFollower(id) end })
  end

  local panel, buttons, setActive = self:CreateSelectorBar(self.frame, items, { spacing = 0, height = 24 })
  self.elements.followerSelectorPanel = panel
  self.state.selectorButtons = buttons or {}
  self.state.selectorSetActive = setActive

  -- ИСПРАВЛЕНО: Убрана вся логика выбора фолловера отсюда
  -- Только создаем кнопки, выбор делается в Show()
end

-- Подсветка активного таба используя BaseWindow setActive
function NS.FollowerWindow:UpdateFollowerButtonHighlight(selectedId)
  NS.Logger:UI("UpdateFollowerButtonHighlight called with " .. tostring(selectedId))
  
  -- ИСПРАВЛЕНО: Упрощенная логика подсветки
  if self.state.selectorSetActive then
    self.state.selectorSetActive(selectedId)
  else
    NS.Logger:UI("selectorSetActive not available, falling back to manual highlight")
    -- Fallback - ручная подсветка
    for _, btn in ipairs(self.state.selectorButtons or {}) do
      local selected = (btn.__id == selectedId)

      -- визуально "прижимаем" кнопку выбранного фолловера
      if selected then 
        btn:LockHighlight() 
      else 
        btn:UnlockHighlight() 
      end

      -- белый текст у выбранной, нормальный у остальных
      if btn.__fs then
        if selected then
          btn.__fs:SetTextColor(1, 1, 1)          -- выбранный = белый
        else
          btn.__fs:SetTextColor(0.82, 0.82, 0.82) -- обычный спокойный цвет
        end
      end

      -- держим исходный текст (без префиксов >>>)
      if btn.__text then 
        btn:SetText(btn.__text) 
      end
    end
  end
end

-- Выбор фолловера (запрос данных + перерисовка)
function NS.FollowerWindow:SelectFollower(followerID)
  NS.Logger:UI("FollowerWindow:SelectFollower called with " .. tostring(followerID) .. ", current=" .. tostring(self.currentFollowerID))
  
  -- ИСПРАВЛЕНО: Всегда обновляем подсветку ПЕРВЫМ ДЕЛОМ
  self:UpdateFollowerButtonHighlight(followerID)

  -- Всегда загружаем данные, даже если выбран тот же фолловер
  if followerID == self.currentFollowerID then
    NS.Logger:UI("Same follower selected again; reloading data")
  end

  -- ИСПРАВЛЕНО: Сохраняем выбор ТОЛЬКО здесь
  self.currentFollowerID = followerID
  self.lastFollowerID = followerID
  NS.Logger:UI("Updated follower selection to " .. tostring(followerID))

  -- Портрет по умолчанию
  if self.elements.portrait then
    self.elements.portrait:SetTexture(ResolvePortraitByFollowerID(self, followerID))
  end

  -- Вытащим данные говорящего (FOLLOWER)
  if NS.DataManager then
    NS.DataManager:GetOrRequestSpeakerData(followerID, NS.Config.SpeakerType.FOLLOWER, function(data)
      if NS.UIManager then NS.UIManager:TriggerEvent("SpeakerDataReceived", data) end
    end)
  end
end

-- Обработка кликов по action-кнопкам
function NS.FollowerWindow:HandleAction(actionID)
  if not self.currentFollowerID then
    NS.Logger:Error("Нет активного фолловера для выполнения действия")
    return
  end

  -- Унифицированный TALK/EXIT через UIManager
  if NS.UIManager and NS.UIManager.HandleAction and (actionID == "TALK" or actionID == "EXIT_DIALOGUE") then
    NS.UIManager:HandleAction(actionID, self.currentFollowerID, NS.Config.SpeakerType.FOLLOWER)
    return
  end

  -- Простые плейсхолдеры для остальных (пока нет серверной логики)
  if actionID == "EQUIP" then
    NS.UIManager:ShowMessage("Экипировка последователя скоро будет доступна.", "info")
  elseif actionID == "TRAIN" then
    NS.UIManager:ShowMessage("Обучение последователя скоро будет доступно.", "info")
  elseif actionID == "DISMISS" then
    NS.UIManager:ShowMessage("Отпуск последователя скоро будет доступен.", "warning")
  else
    NS.UIManager:ShowMessage("Неизвестное действие: "..tostring(actionID), "error")
  end
end

function NS.FollowerWindow:ClearSelectorBar()
  -- убрать старые кнопки
  if self.state and self.state.selectorButtons then
    for i = #self.state.selectorButtons, 1, -1 do
      local btn = self.state.selectorButtons[i]
      if btn then
        btn:Hide()
        btn:SetParent(nil)
      end
      self.state.selectorButtons[i] = nil
    end
  end
  -- убрать старую панель
  if self.elements and self.elements.followerSelectorPanel then
    self.elements.followerSelectorPanel:Hide()
    self.elements.followerSelectorPanel:SetParent(nil)
    self.elements.followerSelectorPanel = nil
  end
end

-- Обновление карточки фолловера (данные с сервера/кэша)
function NS.FollowerWindow:UpdateSpeakerData(speakerData)
  NS.Logger:UI("Обновление данных фолловера: " .. (speakerData.Name or "Неизвестно"))

  local followerID = speakerData.FollowerID or speakerData.SpeakerID
  self.currentFollowerID = followerID or self.currentFollowerID
  if self.currentFollowerID then self.lastFollowerID = self.currentFollowerID end

  -- Заголовок — имя фолловера
  if self.elements.title then
    self.elements.title:SetText(speakerData.Name or (NS.Config:GetSpeakerByID(self.currentFollowerID, NS.Config.SpeakerType.FOLLOWER) or {}).name or "Последователь")
  end

  -- Портрет (по умолчанию от персонажа; портрет узла диалога ставится в UpdateDialogue)
  if self.elements.portrait and followerID then
    self.elements.portrait:SetTexture(ResolvePortraitByFollowerID(self, followerID))
  end

  -- Инфо под портретом (Алаймент + Ранг)
  if self.elements.infoText then
    -- возможные поля с сервера: Alignment или Aligment
    local alignment = speakerData.Alignment or speakerData.Aligment or "Неизвестно"
    -- ранжирование: по Level (если есть), иначе по relationshipPoints ~= 0 (минимальный суррогат)
    local rankLevel = speakerData.Level or (speakerData.relationshipPoints and (math.max(1, math.min(10, math.floor((speakerData.relationshipPoints or 0)/100)+1)))) or 1
    self.elements.infoText:SetText(("Алаймент: %s\nРанг: %s"):format(alignment, Roman(rankLevel)))
  end

  -- Описание и «малая реплика»
  if self.elements.descText then
    self.elements.descText:SetText(speakerData.Description or "Описание недоступно")
  end
  if self.elements.dialogText and speakerData.smallTalk and not self.state.inDialogue then
    self:SetDialogText(speakerData.smallTalk)
  end

  -- Перерасчёт размеров
  local t = (self.elements.dialogText and self.elements.dialogText:GetText()) or ""
  self:AutoSizeWindow(t, self:GetVisibleReplyCount(), self.elements.exitDialogueButton and self.elements.exitDialogueButton:IsShown())

  -- Подсветка выбранного таба
  if followerID then self:UpdateFollowerButtonHighlight(followerID) end
end

-- Диалоговые обновления
function NS.FollowerWindow:UpdateDialogue(d)
  self.state.inDialogue = true

  -- Портрет из узла (если указан ключ эмоции/портрета)
  if d.portrait and d.speakerId and self.elements.portrait then
    local key = d.portrait
    local map = (NS.PatronWindow and NS.PatronWindow.characterPortraitPaths) or self.characterPortraitPaths or {}
    if map[key] then self.elements.portrait:SetTexture(map[key]) end
  end

  local text = d.text or ""
  self:SetDialogText(text)

  -- Ответы / Продолжить / Выход
  if d.answers and #d.answers > 0 then
    self:ShowAnswerButtons(d.answers)
    self:AutoSizeWindow(text, self:GetVisibleReplyCount(), false)
  elseif d.hasNextNode then
    self:ShowContinueButton(d.id)
    self:AutoSizeWindow(text, 1, true)
  else
    self:HideAllReplyButtons()
    if self.elements.exitDialogueButton then
      self.elements.exitDialogueButton:ClearAllPoints()
      self.elements.exitDialogueButton:SetPoint("TOPLEFT", self.elements.replyContainer, "TOPLEFT", 0, -5)
      self.elements.exitDialogueButton:Show()
    end
    self:AutoSizeWindow(text, 0, true)
  end

  -- Расставим контейнер ответов под диалоговым боксом
  if self.elements.replyContainer and self.elements.dialogContainer then
    self.elements.replyContainer:ClearAllPoints()
    self.elements.replyContainer:SetPoint("TOPLEFT", self.elements.dialogContainer, "BOTTOMLEFT", 0, -15)
  end
end

function NS.FollowerWindow:OnDialogueEnded()
  NS.Logger:UI("Диалог завершён в FollowerWindow")
  self.state.inDialogue = false
  self:HideAllReplyButtons()

  local text
  if NS.UIManager and NS.UIManager.currentSpeaker and NS.UIManager.currentSpeaker.smallTalk then
    text = NS.UIManager.currentSpeaker.smallTalk
  else
    text = "Готов к вашим указаниям."
  end

  self:SetDialogText(text)
  self:AutoSizeWindow(text, 0, false)
end

-- Переопределяем Show: строим селектор и выбираем фолловера
function NS.FollowerWindow:Show(followerID)
  BW.prototype.Show(self, followerID)
  self:BuildFollowerSelectors()

  local unlocked = self:GetUnlockedFollowerIDs()
  if #unlocked == 0 then
    return -- баннер уже показан
  end

  -- ИСПРАВЛЕНО: Единственное место логики выбора
  -- Приоритет: параметр -> сохраненный в окне -> первый доступный
  local target = followerID or self.lastFollowerID or unlocked[1]
  
  -- Проверяем что цель действительно доступна
  local isTargetValid = false
  for _, id in ipairs(unlocked) do
    if id == target then
      isTargetValid = true
      break
    end
  end
  
  -- Если цель недоступна, берем первый доступный
  if not isTargetValid then
    target = unlocked[1]
  end

  if target then
    -- Сбрасываем текущий ID, чтобы запросить свежие данные даже при повторном выборе
    self.currentFollowerID = nil
    self:SelectFollower(target)
  end
end

print("|cff00ff00[PatronSystem]|r FollowerWindow (полная версия) загружен")
