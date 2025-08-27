--[[============================================================================
  PATRON SYSTEM — BLESSING WINDOW (patched working base + SLOT BORDERS)
  Добавлено: рамка (border) на ЗАПОЛНЁННЫЕ слоты панели, в стиле иконок из вкладок.
  Минимальные правки поверх «patched working base».
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

local function GetAIO() return _G.AIO or AIO end

-- ---------------------------------------------------------------------------
-- ТУЛТИПЫ
-- ---------------------------------------------------------------------------
local function ShowBlessingTooltip(owner, data)
  if not data then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(data.name or "", 1, 1, 1)
  local desc = data.description
  if desc and desc ~= "" then GameTooltip:AddLine(desc, 0, 1, 0, true) end
  GameTooltip:Show()
end
local function HideTooltip() GameTooltip_Hide() end

-- ---------------------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНОЕ: РАМКА ДЛЯ СЛОТА ПАНЕЛИ
-- ---------------------------------------------------------------------------
local function EnsureSlotBorder(slot)
  if slot.__border then return slot.__border end
  local border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
  border:SetPoint("TOPLEFT", -2, 2)
  border:SetPoint("BOTTOMRIGHT", 2, -2)
  border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
  local c = NS.Config and NS.Config.GetColor and NS.Config:GetColor("dialogBorder") or { r=1,g=1,b=1,a=1 }
  border:SetBackdropBorderColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
  border:Hide()
  slot.__border = border
  return border
end

-- Показывать/скрывать рамку в зависимости от заполненности слота
local function UpdateSlotBorder(slot)
  local b = EnsureSlotBorder(slot)
  if slot.__blessing then b:Show() else b:Hide() end
end

-- ---------------------------------------------------------------------------
-- ОКНО
-- ---------------------------------------------------------------------------
NS.BlessingWindow = BW:New("BlessingWindow", {
  windowType = NS.Config.WindowType.BLESSING,
  hooks = {
    onInit = function(self)
      if self.elements and self.elements.title then self.elements.title:SetText("Благословения") end
      
      -- Создаем кнопку-замок для блокировки перетаскивания
      self:CreateLockButton()

      local tabs = {
        { id = "Defensive", title = "Defensive" },
        { id = "Offensive", title = "Offensive" },
        { id = "Support",   title = "Support"   },
      }
      self.categoryTabs = self:CreateTabsBar(self.frame, tabs, { height=30, onChange=function(id) self:SelectCategory(id) end })

      self.elements.descText = self:CreateText(self.frame, {
        template="GameFontHighlightSmall",
        width=self.frame:GetWidth()-20,
        justify="LEFT",
        point={ self.categoryTabs.frame, "TOPLEFT", "BOTTOMLEFT", 0, -10 },
        text="",
        colorKey="dialogText",
      })

      self.cardGrid = self:CreateCardGrid(self.frame, { top=110, bottom=110, cellW=72, cellH=72, cols=6, gapX=8, gapY=8 })

      -- Панель на 10 слотов
      self.activeBar = self:CreateSlotBar(self.frame, 10, {
        size=48, gap=6, cols=10, plusText="+",
        onEnter=function(_, slot) if slot.__blessing then ShowBlessingTooltip(slot, slot.__blessing) end end,
        onLeave=function() HideTooltip() end,
      })
      self.activeBar.frame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 16)

      -- Слоты: хайлайт, клики, бордер
      for i, slot in ipairs(self.activeBar.slots) do
        local idx = i
        slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        slot:GetHighlightTexture():SetBlendMode("ADD")
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        EnsureSlotBorder(slot)     -- создаём рамку один раз
        UpdateSlotBorder(slot)     -- скрыта по умолчанию (пустой слот)

        slot:HookScript("OnEnter", function() if slot.__blessing then EnsureSlotBorder(slot):Show() end end)
        slot:HookScript("OnLeave", function() UpdateSlotBorder(slot) end)

        slot:HookScript("OnClick", function(_, button)
          if button == "RightButton" then self:RemoveBlessingFromSlot(idx) end
        end)
      end

      self.activeBlessings = {}
    end,
  }
})

-- ---------------------------------------------------------------------------
-- ПУБЛИЧНЫЕ МЕТОДЫ
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:Show(payload)
  BW.prototype.Show(self, payload)
  if not self.currentCategory then self.currentCategory = "Defensive" end
  self:LoadPanelState()
  self:SelectCategory(self.currentCategory)
  if NS.UIManager then NS.UIManager:ShowMessage("Окно благословений открыто", "success") end
end
function NS.BlessingWindow:Hide()   BW.prototype.Hide(self)   end
function NS.BlessingWindow:Toggle(p) BW.prototype.Toggle(self, p) end

-- ---------------------------------------------------------------------------
-- СИНХРОНИЗАЦИЯ СЕРВЕР/КЭШ
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:UpdateBlessingPanelOnServer(blessingId, isInPanel, panelSlot)
  local AIO = GetAIO(); if not AIO then return end
  AIO.Handle(NS.ADDON_PREFIX, "UpdateBlessingPanel", { 
    blessingId = blessingId, 
    isInPanel = not not isInPanel,
    panelSlot = panelSlot or 0
  })
end
function NS.BlessingWindow:UpdateLocalBlessingState(blessingId, isInPanel, panelSlot)
  local dm = NS.DataManager; local data = dm and dm:GetData()
  if data and data.blessings and data.blessings[tostring(blessingId)] then
    data.blessings[tostring(blessingId)].isInPanel = not not isInPanel
    if panelSlot then
      data.blessings[tostring(blessingId)].panelSlot = panelSlot
    end
  end
  
  -- Обновляем QuickBlessingWindow если оно открыто
  if NS.QuickBlessingWindow and NS.QuickBlessingWindow.RefreshData and NS.QuickBlessingWindow:IsShown() then
    NS.QuickBlessingWindow:RefreshData()
  end
  
  -- Обновляем состояние кнопок панели управления
  if PatronSystemNS.ControlPanel and PatronSystemNS.ControlPanel.UpdateAvailability then
    PatronSystemNS.ControlPanel.UpdateAvailability()
  end
end

-- ---------------------------------------------------------------------------
-- ПАНЕЛЬ (10 СЛОТОВ)
-- ---------------------------------------------------------------------------
local function FirstFreeSlot(self)
  for i, slot in ipairs(self.activeBar.slots or {}) do if not slot.__blessing then return i end end
end

function NS.BlessingWindow:AddBlessingToSlot(blessing, card)
  if not (self.activeBar and self.activeBar.slots) then return end
  for _, s in ipairs(self.activeBar.slots) do if s.__blessing and s.__blessing.id == blessing.id then return end end

  local idx = FirstFreeSlot(self); if not idx then if NS.UIManager then NS.UIManager:ShowMessage("Панель заполнена (10/10)", "warning") end return end
  local slot = self.activeBar.slots[idx]
  if not slot.icon then slot.icon = slot:CreateTexture(nil, "ARTWORK"); slot.icon:SetAllPoints(); slot.icon:SetTexCoord(0.07,0.93,0.07,0.93) end
  slot.icon:SetTexture(blessing.icon); slot.icon:Show()
  if slot.__fs then slot.__fs:SetText("") end

  slot.__blessing = blessing; self.activeBlessings[idx] = blessing; slot:SetActive(true)
  UpdateSlotBorder(slot)  -- ПОКАЗЫВАЕМ РАМКУ НА ЗАПОЛНЁННОМ СЛОТЕ

  if card then
    card.__selected = true
    if not card.__overlay then local ov = card:CreateTexture(nil, "OVERLAY"); ov:SetAllPoints(card); ov:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); ov:SetBlendMode("ADD"); card.__overlay = ov end
    card.__overlay:Show()
    card:Enable(); card:EnableMouse(true); card:RegisterForClicks("LeftButtonUp","RightButtonUp")
  end

  self:UpdateBlessingPanelOnServer(blessing.id, true, idx)
  self:UpdateLocalBlessingState(blessing.id, true, idx)
end

function NS.BlessingWindow:AddBlessingToSlotSilent(blessing, targetSlot)
  if not (self.activeBar and self.activeBar.slots) then return end
  local idx = targetSlot or FirstFreeSlot(self); if not idx then return end
  local slot = self.activeBar.slots[idx]
  if not slot.icon then slot.icon = slot:CreateTexture(nil, "ARTWORK"); slot.icon:SetAllPoints(); slot.icon:SetTexCoord(0.07,0.93,0.07,0.93) end
  slot.icon:SetTexture(blessing.icon); slot.icon:Show()
  if slot.__fs then slot.__fs:SetText("") end
  slot.__blessing = blessing; self.activeBlessings[idx] = blessing; slot:SetActive(true)
  UpdateSlotBorder(slot) -- показать рамку
end

function NS.BlessingWindow:RemoveBlessingFromSlot(index)
  if not (self.activeBar and self.activeBar.slots and self.activeBar.slots[index]) then return end
  local slot = self.activeBar.slots[index]; if not slot.__blessing then return end
  local b = slot.__blessing

  if slot.icon then slot.icon:Hide() end; if slot.__fs then slot.__fs:SetText("+") end
  slot.__blessing = nil; self.activeBlessings[index] = nil; slot:SetActive(false)
  UpdateSlotBorder(slot) -- скрыть рамку
  HideTooltip()

  if self.cardGrid and self.cardGrid.cards then
    for _, card in ipairs(self.cardGrid.cards) do
      if card.__data and card.__data.id == b.id then
        card.__selected = nil
        if card.__overlay then card.__overlay:Hide() end
        card:Enable(); card:EnableMouse(true); card:RegisterForClicks("LeftButtonUp","RightButtonUp")
        break
      end
    end
  end

  self:UpdateBlessingPanelOnServer(b.id, false, 0)
  self:UpdateLocalBlessingState(b.id, false, 0)
end

function NS.BlessingWindow:RemoveBlessingFromSlotSilent(index)
  if not (self.activeBar and self.activeBar.slots and self.activeBar.slots[index]) then return end
  local slot = self.activeBar.slots[index]; if not slot.__blessing then return end
  if slot.icon then slot.icon:Hide() end; if slot.__fs then slot.__fs:SetText("+") end
  slot.__blessing = nil; self.activeBlessings[index] = nil; slot:SetActive(false)
  UpdateSlotBorder(slot) -- скрыть рамку
  HideTooltip()
end

function NS.BlessingWindow:RemoveBlessingById(blessingId)
  for idx, b in pairs(self.activeBlessings) do if b and b.id == blessingId then self:RemoveBlessingFromSlot(idx); return end end
end

-- ---------------------------------------------------------------------------
-- КАТЕГОРИИ/КАРТОЧКИ
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:SelectCategory(categoryID)
  self.currentCategory = categoryID
  if self.categoryTabs and self.categoryTabs.setActive then self.categoryTabs.setActive(categoryID) end
  local descriptions = {
    Defensive = "Defensive blessings provide protection and survivability bonuses.",
    Offensive = "Offensive blessings enhance your damage output.",
    Support   = "Support blessings offer utility and group benefits.",
  }
  if self.elements.descText then self.elements.descText:SetText(descriptions[categoryID] or "") end
  self:RenderCategory(self.currentCategory)
end

function NS.BlessingWindow:GetBlessingsForCategory(category)
  local dm = NS.DataManager; local data = dm and dm:GetData(); local out = {}
  if data and data.blessings then
    for _, v in pairs(data.blessings) do
      if v.isDiscovered and v.blessing_type == category then
        table.insert(out, { id=tonumber(v.blessing_id) or tonumber(v.id) or 0, name=v.name, description=v.description, icon=v.icon, blessing_type=v.blessing_type, isInPanel=not not v.isInPanel })
      end
    end
  end
  table.sort(out, function(a,b) return (a.id or 0) < (b.id or 0) end)
  return out
end

function NS.BlessingWindow:RenderCategory(category)
  if not self.cardGrid then return end
  self.cardGrid:Clear()
  local blessings = self:GetBlessingsForCategory(category)

  for _, data in ipairs(blessings) do
    self.cardGrid:AddCard(data, function(card, b)
      card:SetNormalTexture(b.icon)
      card:SetPushedTexture(b.icon)
      do local nt = card:GetNormalTexture(); if nt then nt:ClearAllPoints(); nt:SetAllPoints(); nt:SetTexCoord(0.07,0.93,0.07,0.93) end end
      do local pt = card:GetPushedTexture(); if pt then pt:ClearAllPoints(); pt:SetAllPoints(); pt:SetTexCoord(0.07,0.93,0.07,0.93) end end
      card:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
      card:GetHighlightTexture():SetBlendMode("ADD")

      -- Базовая иконка внутри кнопки

      -- Тултип и клики
      card:SetScript("OnEnter", function(btn) ShowBlessingTooltip(btn, b) end)
      card:SetScript("OnLeave", HideTooltip)
      card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

      card.__data = b
      card:SetScript("OnClick", function(_, button)
        if card.__selected then
          if button == "RightButton" then NS.BlessingWindow:RemoveBlessingById(b.id) end
          return
        end
        if button == "LeftButton" then NS.BlessingWindow:AddBlessingToSlot(b, card)
        elseif button == "RightButton" then NS.BlessingWindow:RemoveBlessingById(b.id) end
      end)

      -- Уже в панели — подсветка, но клики не блокируем
      for _, active in pairs(self.activeBlessings or {}) do
        if active and active.id == b.id then
          card.__selected = true
          if not card.__overlay then
            local ov = card:CreateTexture(nil, "OVERLAY"); ov:SetAllPoints(card); ov:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); ov:SetBlendMode("ADD"); card.__overlay = ov
          end
          card.__overlay:Show()
          break
        end
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- СОСТОЯНИЕ ПАНЕЛИ ПРИ ОТКРЫТИИ
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:LoadPanelState()
  if self.activeBar and self.activeBar.slots then
    for i in ipairs(self.activeBar.slots) do self:RemoveBlessingFromSlotSilent(i) end
  end
  local dm = NS.DataManager; local data = dm and dm:GetData(); if not (data and data.blessings) then return end
  
  -- Собираем блессинги в панели с их позициями
  local panelBlessings = {}
  for blessingId, b in pairs(data.blessings) do
    if b.isInPanel and b.isDiscovered then
      local blessing = { id=tonumber(blessingId), name=b.name, description=b.description, icon=b.icon, blessing_type=b.blessing_type }
      local slot = b.panelSlot or 0
      if slot > 0 and slot <= 10 then
        panelBlessings[slot] = blessing
      else
        -- Если позиция некорректная, добавляем в конец
        for i = 1, 10 do
          if not panelBlessings[i] then
            panelBlessings[i] = blessing
            break
          end
        end
      end
    end
  end
  
  -- Размещаем блессинги в правильных позициях
  for slot, blessing in pairs(panelBlessings) do
    self:AddBlessingToSlotSilent(blessing, slot)
  end
  
  -- Обновляем QuickBlessingWindow если оно открыто
  if NS.QuickBlessingWindow and NS.QuickBlessingWindow.RefreshData and NS.QuickBlessingWindow:IsShown() then
    NS.QuickBlessingWindow:RefreshData()
  end
  
  -- Обновляем состояние кнопок панели управления
  if PatronSystemNS.ControlPanel and PatronSystemNS.ControlPanel.UpdateAvailability then
    PatronSystemNS.ControlPanel.UpdateAvailability()
  end
end

print("|cff00ff00[PatronSystem]|r BlessingWindow loaded (slot borders)")
