--[[===========================================================================
  PATRON SYSTEM - PATRON WINDOW (на базе BaseWindow v2)
  Тонкое окно: только данные/обработчики. Вся верстка — в BaseWindow.
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

-- Создаём объект окна на базе BaseWindow
NS.PatronWindow = BW:New("PatronWindow", {
  windowType = NS.Config.WindowType and NS.Config.WindowType.PATRON or nil,
  hooks = {
    onInit = function(self)
      -- Заголовок
      self.elements.title:SetText("Система Покровителей")

      -- Горизонтальный селектор покровителей
      local patrons = NS.Config:GetSpeakersByType(NS.Config.SpeakerType.PATRON) or {}
      local selectorItems = {}
      for _, p in ipairs(patrons) do
        table.insert(selectorItems, {
          id = p.id,
          text = p.name or ("#" .. tostring(p.id)),
          onClick = function(id) self:SwitchToPatron(id) end
        })
      end
      local panel, buttons = self:CreateSelectorBar(self.frame, selectorItems, {
        orientation = "horizontal",
        spacing = 0
      })
      self.elements.patronSelectorPanel = panel
      self.state.selectorButtons = buttons
	  self:UpdatePatronButtonHighlight(patronID)

      -- Левая/правая панель
      local left, right = self:CreateLeftRightPanels()

      -- Портрет в левой панели
      local portraitFrame, portraitTex = self:CreatePortrait(left, { width = 160, height = 200 })
      self.elements.portraitFrame = portraitFrame
      self.elements.portrait = portraitTex
      portraitTex:SetTexture("Interface\\AddOns\\PatronSystem\\media\\portraits\\void2.png")

      -- Информационная панель под портретом
      local info = self:CreateInfoText(left)
      info:SetPoint("TOP", portraitTex, "BOTTOM", 0, -10)
      info:SetText("Алаймент: Неизвестно\nРанг: Неизвестно")
      self.elements.infoText = info

      -- Кнопки действий 2×N
      local aCfg = NS.Config:GetUIConfig("actionButtons") or {}
      local actions = {}
      for _, act in ipairs(NS.Config:GetActionsByType(NS.Config.SpeakerType.PATRON) or {}) do
        table.insert(actions, {
          id = act.id,
          text = act.text,
          onClick = function(id) self:HandleAction(id) end
        })
      end
      self.state.actionButtons = self:CreateActionButtons(left, actions, {
	  cols     = 2,
	  spacingX = aCfg.spacingX or 10,
	  spacingY = aCfg.spacingY or 35,  -- как в конфиге
	  pitchY   = aCfg.spacingY or 35,  -- «полный шаг» между рядами
	  width    = aCfg.width or 120,
	  height   = aCfg.height or 24,
	  anchor   = { frame = self.elements.infoText, point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -20 }
	})
	
	local rows = math.ceil(#actions / 2)
	self:EnsureLeftPanelHeightForActions(rows, {
	  pitchY = aCfg.spacingY or 35,
	  spacingY = aCfg.spacingY or 35,
	  height = aCfg.height or 24
	})
	
	local initText = self.elements.dialogText and self.elements.dialogText:GetText() or ""
	self:AutoSizeWindow(initText, 0, false)

      -- Правая панель: описание, диалог, ответы
      local pad = 10

		local desc = self:CreateText(right, {
		  template = "GameFontHighlightSmall",
		  width    = right:GetWidth() - pad*2,   -- было: right:GetWidth()
		  justify  = "LEFT",
		  point    = { right, "TOPLEFT", "TOPLEFT", pad, 0 }, -- было x=0
		  text     = "Выберите покровителя для просмотра информации."
		})
		self.elements.descText = desc

		local dc = NS.Config:GetUIConfig("dialogContainer") or {}
		local dialogContainer, dialogText = self:CreateDialogueContainer(right, {
		  width     = (dc.width and (dc.width - pad*2)) or (right:GetWidth() - pad*2),
		  minHeight = dc.minHeight,
		  maxHeight = dc.maxHeight,
		  -- якорим под описанием; паддинг уже учтён через descText
		  point     = { self.elements.descText, "BOTTOMLEFT", "BOTTOMLEFT", 0, -15 },
		})
		self.elements.dialogContainer = dialogContainer
		self.elements.dialogText      = dialogText
		dialogText:SetText("Выберите действие 'Говорить' для начала диалога.")

      self.replies = self:CreateReplyContainer(self.elements.rightPanel, NS.Config:GetUIConfig("replyButtons"))

      -- начальные поля
      self.currentPatronID = nil
      self.lastPatronID = 1

      -- ===== (опционально) ТАБЛИЦЫ ПОРТРЕТОВ =====
      -- если используешь ключи эмоций/портретов — скопируй сюда из старой версии:
      -- self.patronPortraitPaths = { [1]="...", [2]="...", [3]="..." }
      -- self.characterPortraitPaths = { void_default="...", dragon_angry="...", ... }
      -- ============================================
    end
  }
})

-- ===== ПОРТРЕТЫ (минимальный фолбэк, можешь заменить на свои таблицы) =====
NS.PatronWindow.patronPortraitPaths = NS.PatronWindow.patronPortraitPaths or {
  [1] = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void2.png",
  [2] = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon2.png",
  [3] = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna2.png"
}

-- Централизованная система портретов персонажей
NS.PatronWindow.characterPortraitPaths = NS.PatronWindow.characterPortraitPaths or {
    -- ПОКРОВИТЕЛИ
    void_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void2.png",
    void_angry = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void_angry.png",
    void_curious = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void_curious.png", 
    void_pleased = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void_pleased.png",
    void_threatening = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void_threatening.png",
    void_amused = "Interface\\AddOns\\PatronSystem\\media\\portraits\\void_amused.png",
    
    dragon_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon2.png",
    dragon_angry = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon_angry.png",
    dragon_happy = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon_happy.png",
    dragon_greedy = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon_greedy.png",
    dragon_calculating = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon_calculating.png",
    dragon_disappointed = "Interface\\AddOns\\PatronSystem\\media\\portraits\\dragon_disappointed.png",
    
    eluna_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna2.png",
    eluna_sad = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna_sad.png",
    eluna_caring = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna_caring.png",
    eluna_disappointed = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna_disappointed.png",
    eluna_loving = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna_loving.png",
    eluna_worried = "Interface\\AddOns\\PatronSystem\\media\\portraits\\eluna_worried.png",
    
    -- ФОЛЛОВЕРЫ
    -- Алайя (101) - душа-девушка от Пустоты
    shadow_warrior_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior.png",
    shadow_warrior_determined = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior_determined.png",
    shadow_warrior_worried = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior_worried.png",
    shadow_warrior_angry = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior_angry.png",
    shadow_warrior_bow = "Interface\\AddOns\\PatronSystem\\media\\portraits\\shadow_warrior_bow.png",
    
    -- Арле'Кино (102) - бывшая торговка от Дракона
    arlekino_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino.png",
    arlekino_scheming = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino_scheming.png",
    arlekino_pleased = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino_pleased.png",
    arlekino_gold_eyes = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino_gold_eyes.png",
    arlekino_smirk = "Interface\\AddOns\\PatronSystem\\media\\portraits\\arlekino_smirk.png",
    
    -- УДАЛЕНО: moon_priestess портреты больше не используются для фолловеров
    -- Оставляем для других НПЦ в будущем
    moon_priestess_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess.png",
    moon_priestess_praying = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess_praying.png",
    moon_priestess_concerned = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess_concerned.png",
    moon_priestess_blessed = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess_blessed.png",
    moon_priestess_wise = "Interface\\AddOns\\PatronSystem\\media\\portraits\\moon_priestess_wise.png",
    
    -- ВРАГИ
    inquisitor_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\inquisitor.png",
    inquisitor_righteous = "Interface\\AddOns\\PatronSystem\\media\\portraits\\inquisitor_righteous.png",
    inquisitor_angry = "Interface\\AddOns\\PatronSystem\\media\\portraits\\inquisitor_angry.png",
    inquisitor_disgusted = "Interface\\AddOns\\PatronSystem\\media\\portraits\\inquisitor_disgusted.png",
    inquisitor_threatening = "Interface\\AddOns\\PatronSystem\\media\\portraits\\inquisitor_threatening.png",
    
    chaos_demon_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\chaos_demon.png",
    chaos_demon_laughing = "Interface\\AddOns\\PatronSystem\\media\\portraits\\chaos_demon_laughing.png",
    chaos_demon_furious = "Interface\\AddOns\\PatronSystem\\media\\portraits\\chaos_demon_furious.png",
    chaos_demon_mocking = "Interface\\AddOns\\PatronSystem\\media\\portraits\\chaos_demon_mocking.png",
    chaos_demon_menacing = "Interface\\AddOns\\PatronSystem\\media\\portraits\\chaos_demon_menacing.png",
    
    -- НПЦ
    mysterious_trader_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\mysterious_trader.png",
    mysterious_trader_welcoming = "Interface\\AddOns\\PatronSystem\\media\\portraits\\mysterious_trader_welcoming.png",
    mysterious_trader_suspicious = "Interface\\AddOns\\PatronSystem\\media\\portraits\\mysterious_trader_suspicious.png",
    mysterious_trader_intrigued = "Interface\\AddOns\\PatronSystem\\media\\portraits\\mysterious_trader_intrigued.png",
    
    oracle_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\oracle.png",
    oracle_prophetic = "Interface\\AddOns\\PatronSystem\\media\\portraits\\oracle_prophetic.png",
    oracle_sad = "Interface\\AddOns\\PatronSystem\\media\\portraits\\oracle_sad.png",
    oracle_mysterious = "Interface\\AddOns\\PatronSystem\\media\\portraits\\oracle_mysterious.png",
    oracle_knowing = "Interface\\AddOns\\PatronSystem\\media\\portraits\\oracle_knowing.png",
    
    -- ОСОБЫЕ
    past_voice_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\past_voice.png",
    past_voice_nostalgic = "Interface\\AddOns\\PatronSystem\\media\\portraits\\past_voice_nostalgic.png",
    past_voice_warning = "Interface\\AddOns\\PatronSystem\\media\\portraits\\past_voice_warning.png",
    past_voice_fading = "Interface\\AddOns\\PatronSystem\\media\\portraits\\past_voice_fading.png",
    
    future_vision_default = "Interface\\AddOns\\PatronSystem\\media\\portraits\\future_vision.png",
    future_vision_ominous = "Interface\\AddOns\\PatronSystem\\media\\portraits\\future_vision_ominous.png",
    future_vision_hopeful = "Interface\\AddOns\\PatronSystem\\media\\portraits\\future_vision_hopeful.png",
    future_vision_unclear = "Interface\\AddOns\\PatronSystem\\media\\portraits\\future_vision_unclear.png"
}
-- ========================================================================

function PatronSystemNS.PatronWindow:UpdatePatronButtonHighlight(selectedId)
  local list = self.patronSelectorButtons or self.state.selectorButtons or {}
  for _, btn in ipairs(list) do
    local selected = (btn.__id == selectedId)

    -- визуально "прижимаем" кнопку выбранного патрона
    if selected then btn:LockHighlight() else btn:UnlockHighlight() end

    -- белый текст у выбранной, нормальный у остальных
    if btn.__fs then
      if selected then
        btn.__fs:SetTextColor(1, 1, 1)          -- выбранный = белый
      else
        btn.__fs:SetTextColor(0.82, 0.82, 0.82) -- обычный спокойный цвет
      end
    end

    -- держим исходный текст (без префиксов >>>)
    if btn.__text then btn:SetText(btn.__text) end
  end
end

function NS.PatronWindow:SwitchToPatron(patronID)
  if patronID == self.currentPatronID then return end
  self.currentPatronID = patronID
  self.lastPatronID    = patronID
  self:UpdatePatronButtonHighlight(patronID)
  if self.state.inDialogue and NS.DialogueEngine then
    NS.DialogueEngine:EndDialogue()
  end
  -- Координация — оставляем по твоей логике:
  if NS.UIManager and NS.UIManager.ShowPatronWindow then
    NS.UIManager:ShowPatronWindow(patronID)
  end
  local text = (self.elements.dialogText and self.elements.dialogText:GetText()) or ""
  self:AutoSizeWindow(text, self:GetVisibleReplyCount(), self.elements.exitDialogueButton and self.elements.exitDialogueButton:IsShown())
end

function NS.PatronWindow:HandleAction(actionID)
  if not self.currentPatronID then
    NS.Logger:Error("Нет активного покровителя для выполнения действия")
    return
  end
  if NS.UIManager and NS.UIManager.HandleAction then
    NS.UIManager:HandleAction(actionID, self.currentPatronID, NS.Config.SpeakerType.PATRON)
  end
end

-- Обновление карточки покровителя (данные с сервера/кэша)
function NS.PatronWindow:UpdateSpeakerData(speakerData)
  NS.Logger:UI("Обновление данных покровителя: " .. (speakerData.Name or "Неизвестно"))

  local patronID = speakerData.PatronID or speakerData.SpeakerID
  self.currentPatronID = patronID or self.currentPatronID
  if self.currentPatronID then self.lastPatronID = self.currentPatronID end

  -- Заголовок
  if self.elements.title then
    self.elements.title:SetText(speakerData.Name or "Система Покровителей")
  end

  -- Портрет
  if self.elements.portrait and patronID then
    local path = self.patronPortraitPaths and self.patronPortraitPaths[patronID]
    if path then
      self.elements.portrait:SetTexture(path)
    end
  end

  -- Инфо
  if self.elements.infoText then
    local infoText = "Алаймент: " .. (speakerData.Alignment or "Неизвестно") .. "\n" .. "Ранг: I"
    self.elements.infoText:SetText(infoText)
  end

  -- Описание
  if self.elements.descText then
    self.elements.descText:SetText(speakerData.Description or "Описание недоступно")
  end
  
  local t = (self.elements.dialogText and self.elements.dialogText:GetText()) or ""
  self:AutoSizeWindow(t, self:GetVisibleReplyCount(), self.elements.exitDialogueButton and self.elements.exitDialogueButton:IsShown())


  -- smallTalk, если не в диалоге
  if self.elements.dialogText and speakerData.smallTalk and not self.state.inDialogue then
    self:SetDialogText(speakerData.smallTalk)
    self:AutoSizeWindow(speakerData.smallTalk, 0, false)
  end

  -- Подсветка выбранного
  if patronID then self:UpdatePatronButtonHighlight(patronID) end
end

-- Диалог
function NS.PatronWindow:UpdateDialogue(d)
  self.state.inDialogue = true

  -- Портрет из узла диалога (если задан ключ)
  if d.portrait and d.speakerId and self.elements.portrait then
    local key = d.portrait
    local map = self.characterPortraitPaths or {}
    if map[key] then
      self.elements.portrait:SetTexture(map[key])
    end
  end

  -- Текст
  local text = d.text or ""
  self:SetDialogText(text)

  -- Кнопки ответов/продолжения
  self:HideAllReplyButtons()
  if d.answers and #d.answers > 0 then
    self:ShowAnswerButtons(d.answers)
  elseif d.hasNextNode then
    self:ShowContinueButton(d.id)
    self:AutoSizeWindow(text, 1, true)
  else
    -- Только выход
    self:HideAllReplyButtons()
    -- Поставим Exit как единственную кнопку
    if self.elements.exitDialogueButton then
      self.elements.exitDialogueButton:ClearAllPoints()
      self.elements.exitDialogueButton:SetPoint("TOPLEFT", self.elements.replyContainer, "TOPLEFT", 0, -5)
      self.elements.exitDialogueButton:Show()
    end
    self:AutoSizeWindow(text, 0, true)
  end
end

function NS.PatronWindow:OnDialogueEnded()
  NS.Logger:UI("Диалог завершен в PatronWindow")
  self.state.inDialogue = false
  self:HideAllReplyButtons()

  local text
  if NS.UIManager and NS.UIManager.currentSpeaker and NS.UIManager.currentSpeaker.smallTalk then
    text = NS.UIManager.currentSpeaker.smallTalk
  else
    text = "Выберите действие для взаимодействия с покровителем."
  end

  self:SetDialogText(text)

  -- replyContainer снова под диалогом (на случай сторонней правки)
  if self.elements.replyContainer and self.elements.dialogContainer then
    self.elements.replyContainer:ClearAllPoints()
    self.elements.replyContainer:SetPoint("TOPLEFT", self.elements.dialogContainer, "BOTTOMLEFT", 0, -15)
  end

  self:AutoSizeWindow(text, 0, false)
end

-- Переопределяем Show, чтобы подхватывать lastPatronID
function NS.PatronWindow:Show(patronID)
  BW.prototype.Show(self, patronID)
  patronID = patronID or self.lastPatronID or 1
  self.currentPatronID = patronID
  self.lastPatronID    = patronID
  self:UpdatePatronButtonHighlight(patronID)
end

print("|cff00ff00[PatronSystem]|r PatronWindow рефакторинг на BaseWindow загружен")
