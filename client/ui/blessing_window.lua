--[[==========================================================================
  PATRON SYSTEM - BLESSING WINDOW (on BaseWindow)
  Переписанный мокап окна благословений с использованием BaseWindow
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

-- Реальные данные благословений получаются из DataManager

NS.BlessingWindow = BW:New("BlessingWindow", {
  windowType = NS.Config.WindowType.BLESSING,
  hooks = {
    onInit = function(self)
      -- Заголовок
      if self.elements and self.elements.title then
        self.elements.title:SetText("Благословения")
      end

      -- ================== СЕЛЕКТОР КАТЕГОРИЙ ==================
      local tabs = {
        { id = "Defensive", title = "Defensive" },
        { id = "Offensive", title = "Offensive" },
        { id = "Support",   title = "Support"   },
      }

      self.categoryTabs = self:CreateTabsBar(self.frame, tabs, {
        height   = 30,
        onChange = function(id) self:SelectCategory(id) end,
      })

      -- Описание выбранной категории
      self.elements.descText = self:CreateText(self.frame, {
        template = "GameFontHighlightSmall",
        width    = self.frame:GetWidth() - 20,
        justify  = "LEFT",
        point    = { self.categoryTabs.frame, "TOPLEFT", "BOTTOMLEFT", 0, -10 },
        text     = "",
        colorKey = "dialogText",
      })

      -- ================== СЕТКА КАРТОЧЕК БЛАГОСЛОВЕНИЙ ==================
      self.cardGrid = self:CreateCardGrid(self.frame, {
        top    = 110,
        bottom = 80,
      })

      -- ================== ПАНЕЛЬ АКТИВНЫХ БЛАГОСЛОВЕНИЙ ==================
      self.activeBar = self:CreateSlotBar(self.frame, 6, {
        title = "Active Blessings:",
      })
      self.activeBar.frame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 15)

      self.activeBlessings = {}

      for i, slot in ipairs(self.activeBar.slots) do
        local idx = i
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:HookScript("OnClick", function(_, button)
          if button == "RightButton" then
            self:RemoveBlessingFromSlot(idx)
          end
        end)
      end
    end,

    onAfterShow = function(self)
      self:SelectCategory(self.categoryTabs.getActive() or "Defensive")
    end,
  }
})

function NS.BlessingWindow:Show(payload)
  BW.prototype.Show(self, payload)
  
  print("|cffff0000[DEBUG]|r BlessingWindow:Show called")
  
  -- Обновляем данные при показе окна
  self:RefreshData()
  
  print("|cffff0000[DEBUG]|r BlessingWindow:Show completed")
  
  NS.Logger:UI("Показ окна BlessingWindow")
  if NS.UIManager then
    NS.UIManager:ShowMessage("Окно благословений открыто", "success")
  end
end

function NS.BlessingWindow:RefreshData()
  print("|cffff0000[DEBUG]|r RefreshData called, currentCategory=" .. tostring(self.currentCategory))
  
  -- Перерендериваем текущую категорию с новыми данными
  if self.currentCategory then
    self:SelectCategory(self.currentCategory)
  else
    print("|cffff0000[DEBUG]|r No currentCategory, selecting default")
    self:SelectCategory("Defensive")
  end
  
  -- Перезагружаем состояние панели
  self:LoadPanelState()
  
  print("|cffff0000[DEBUG]|r RefreshData completed")
end

function NS.BlessingWindow:UpdateBlessingPanelOnServer(blessingId, isInPanel)
  local AIO = AIO or require("AIO")
  if not AIO then return end
  
  AIO.Handle(NS.ADDON_PREFIX, "UpdateBlessingPanel", {
    blessingId = blessingId,
    isInPanel = isInPanel
  })
  
  NS.Logger:UI("Отправка обновления панели на сервер: blessing=" .. blessingId .. ", inPanel=" .. tostring(isInPanel))
end

function NS.BlessingWindow:LoadPanelState()
  -- Очищаем текущую панель без синхронизации с сервером
  if self.activeBar and self.activeBar.slots then
    for i, slot in ipairs(self.activeBar.slots) do
      if slot.__blessing then
        self:RemoveBlessingFromSlotSilent(i)
      end
    end
  end
  
  -- Загружаем благословения с isInPanel = true
  if NS.DataManager and NS.DataManager.GetData then
    local data = NS.DataManager.GetData()
    if data and data.blessings then
      for blessingId, blessingData in pairs(data.blessings) do
        if blessingData.isInPanel and blessingData.isDiscovered then
          local blessing = {
            id = blessingData.blessing_id,
            name = blessingData.name,
            description = blessingData.description,
            icon = blessingData.icon,
            blessing_type = blessingData.blessing_type
          }
          -- Добавляем в панель без отправки на сервер (уже там)
          self:AddBlessingToSlotSilent(blessing)
        end
      end
    end
  end
end

function NS.BlessingWindow:AddBlessingToSlotSilent(blessing)
  -- Версия AddBlessingToSlot без синхронизации с сервером
  if not self.activeBar or not self.activeBar.slots then return end
  for i, slot in ipairs(self.activeBar.slots) do
    if not slot.__blessing then
      if not slot.icon then
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      end
      slot.icon:SetTexture(blessing.icon)
      slot.icon:Show()
      if slot.__fs then slot.__fs:SetText("") end
      slot.__blessing = blessing
      self.activeBlessings[i] = blessing
      slot:SetActive(true)
      break
    end
  end
end

function NS.BlessingWindow:RemoveBlessingFromSlotSilent(index)
  -- Версия RemoveBlessingFromSlot без синхронизации с сервером
  if not self.activeBar or not self.activeBar.slots or not self.activeBar.slots[index] then return end
  local slot = self.activeBar.slots[index]
  if slot.__blessing then
    local blessing = slot.__blessing
    if slot.icon then slot.icon:Hide() end
    if slot.__fs then slot.__fs:SetText("+") end
    slot.__blessing = nil
    self.activeBlessings[index] = nil
    slot:SetActive(false)

    if self.cardGrid and self.cardGrid.cards then
      for _, card in ipairs(self.cardGrid.cards) do
        if card.__data == blessing then
          card:Enable()
          if card.__overlay then card.__overlay:Hide() end
          break
        end
      end
    end
  end
end

function NS.BlessingWindow:Hide()
  NS.Logger:UI("Скрытие окна BlessingWindow (мокап)")
  BW.prototype.Hide(self)
end

function NS.BlessingWindow:Toggle(payload)
  BW.prototype.Toggle(self, payload)
end

function NS.BlessingWindow:AddBlessingToSlot(blessing, card)
  if not self.activeBar or not self.activeBar.slots then return end
  for i, slot in ipairs(self.activeBar.slots) do
    if not slot.__blessing then
      if not slot.icon then
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      end
      slot.icon:SetTexture(blessing.icon)
      slot.icon:Show()
      if slot.__fs then slot.__fs:SetText("") end
      slot.__blessing = blessing
      self.activeBlessings[i] = blessing
      slot:SetActive(true)

      if card then
        card:Disable()
        if not card.__overlay then
          local overlay = card:CreateTexture(nil, "OVERLAY")
          overlay:SetAllPoints(card)
          overlay:SetColorTexture(1, 1, 1, 0.3)
          card.__overlay = overlay
        end
        card.__overlay:Show()
      end
      
      -- Синхронизируем с сервером
      self:UpdateBlessingPanelOnServer(blessing.id, true)

      break
    end
  end
end

function NS.BlessingWindow:RemoveBlessingFromSlot(index)
  if not self.activeBar or not self.activeBar.slots or not self.activeBar.slots[index] then return end
  local slot = self.activeBar.slots[index]
  if slot.__blessing then
    local blessing = slot.__blessing
    if slot.icon then slot.icon:Hide() end
    if slot.__fs then slot.__fs:SetText("+") end
    slot.__blessing = nil
    self.activeBlessings[index] = nil
    slot:SetActive(false)

    if self.cardGrid and self.cardGrid.cards then
      for _, card in ipairs(self.cardGrid.cards) do
        if card.__data == blessing then
          card:Enable()
          if card.__overlay then card.__overlay:Hide() end
          break
        end
      end
    end
    
    -- Синхронизируем с сервером
    self:UpdateBlessingPanelOnServer(blessing.id, false)
  end
end

function NS.BlessingWindow:GetBlessingsForCategory(category)
  print("|cffff0000[DEBUG]|r GetBlessingsForCategory called with: " .. tostring(category))
  
  local blessings = {}
  
  -- Получаем данные из DataManager
  print("|cffff0000[DEBUG]|r DataManager exists: " .. tostring(NS.DataManager ~= nil))
  print("|cffff0000[DEBUG]|r GetData exists: " .. tostring(NS.DataManager and NS.DataManager.GetData ~= nil))
  
  if NS.DataManager and NS.DataManager.GetData then
    local success, data = pcall(NS.DataManager.GetData, NS.DataManager)
    print("|cffff0000[DEBUG]|r GetData success: " .. tostring(success))
    if not success then
      print("|cffff0000[DEBUG ERROR]|r GetData failed: " .. tostring(data))
      return blessings
    end
    print("|cffff0000[DEBUG]|r Got data: " .. tostring(data ~= nil))
    
    if data then
      print("|cffff0000[DEBUG]|r data.blessings exists: " .. tostring(data.blessings ~= nil))
      
      if data.blessings then
        local totalCount = 0
        local discoveredCount = 0
        local categoryCount = 0
        
        for blessingId, blessingData in pairs(data.blessings) do
          totalCount = totalCount + 1
          print("|cffff0000[DEBUG]|r Processing blessing " .. blessingId .. 
            ", discovered=" .. tostring(blessingData.isDiscovered) ..
            ", type=" .. tostring(blessingData.blessing_type))
          
          if blessingData.isDiscovered then
            discoveredCount = discoveredCount + 1
            
            if blessingData.blessing_type == category then
              categoryCount = categoryCount + 1
              table.insert(blessings, {
                id = blessingData.blessing_id,
                name = blessingData.name,
                description = blessingData.description,
                icon = blessingData.icon,
                blessing_type = blessingData.blessing_type,
                isInPanel = blessingData.isInPanel
              })
            end
          end
        end
        
        print("|cffff0000[DEBUG]|r Blessing stats: total=" .. totalCount .. 
          ", discovered=" .. discoveredCount .. 
          ", category(" .. category .. ")=" .. categoryCount)
      else
        print("|cffff0000[DEBUG]|r No blessings in data")
      end
    else
      print("|cffff0000[DEBUG]|r No data from DataManager")
    end
  else
    print("|cffff0000[DEBUG]|r DataManager or GetData not available")
  end
  
  -- Сортируем по ID для стабильности
  table.sort(blessings, function(a, b) return a.id < b.id end)
  
  return blessings
end

function NS.BlessingWindow:RenderCategory(category)
  print("|cffff0000[DEBUG]|r RenderCategory called with: " .. tostring(category))
  print("|cffff0000[DEBUG]|r cardGrid exists: " .. tostring(self.cardGrid ~= nil))
  
  if not self.cardGrid then 
    print("|cffff0000[DEBUG]|r No cardGrid, exiting")
    return 
  end
  
  self.cardGrid:Clear()
  
  -- Получаем данные благословений из DataManager
  print("|cffff0000[DEBUG]|r About to call GetBlessingsForCategory")
  local blessings = self:GetBlessingsForCategory(category)
  print("|cffff0000[DEBUG]|r Got " .. #blessings .. " blessings")
  
  for _, blessing in ipairs(blessings) do
    self.cardGrid:AddCard(blessing, function(card, data)
      card:SetBackdrop(nil)
      local icon = card:CreateTexture(nil, "ARTWORK")
      icon:SetAllPoints(card)
      icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      icon:SetTexture(data.icon)
      local fs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("BOTTOM", card, "BOTTOM", 0, 6)
      fs:SetText(data.name)
      card.__data = data
      card:SetScript("OnClick", function() self:AddBlessingToSlot(data, card) end)

      for _, active in pairs(self.activeBlessings or {}) do
        if active and active.id == data.id then
          card:Disable()
          if not card.__overlay then
            local overlay = card:CreateTexture(nil, "OVERLAY")
            overlay:SetAllPoints(card)
            overlay:SetColorTexture(1, 1, 1, 0.3)
            card.__overlay = overlay
          end
          card.__overlay:Show()
          break
        end
      end
    end)
  end
end

function NS.BlessingWindow:SelectCategory(categoryID)
  print("|cffff0000[DEBUG]|r SelectCategory called with: " .. tostring(categoryID))
  
  self.currentCategory = categoryID
  if self.categoryTabs and self.categoryTabs.setActive then
    self.categoryTabs.setActive(categoryID)
  end

  local descriptions = {
    Defensive = "Defensive blessings provide protection and survivability bonuses to help you survive in dangerous situations.",
    Offensive = "Offensive blessings enhance your damage output and combat effectiveness against your enemies.",
    Support   = "Support blessings offer utility effects like movement speed, resource regeneration, and group benefits.",
  }
  if self.elements.descText then
    self.elements.descText:SetText(descriptions[categoryID] or "Category description not available.")
  end

  print("|cffff0000[DEBUG]|r About to call RenderCategory")
  self:RenderCategory(categoryID)
  print("|cffff0000[DEBUG]|r RenderCategory completed")

  if NS.UIManager then
    NS.UIManager:ShowMessage("Категория " .. categoryID .. " выбрана", "info")
  end
end

print("|cff00ff00[PatronSystem]|r BlessingWindow загружен")

