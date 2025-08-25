--[[============================================================================
  PATRON SYSTEM — BLESSING WINDOW (stable final)
  Требования:
  • Панель снизу на 12 слотов.
  • Иконки/карточки со стилем «спеллов»: highlight, hover, тултипы.
  • ЛКМ по карточке → добавить в панель (в первый свободный слот).
  • ПКМ по карточке или по слоту → удалить из панели.
  • Без disable карточек — чтобы ПКМ всегда работал сразу после добавления.
  • Синхронизация с сервером (AIO.Handle) и локальным кэшем (DataManager).
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

local function GetAIO() return _G.AIO or AIO end

-- ---------------------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНЫЕ ТУЛТИПЫ
-- ---------------------------------------------------------------------------
local function ShowBlessingTooltip(owner, b)
  if not b then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(b.name or "Blessing", 1, 1, 1)
  if b.description and b.description ~= "" then
    GameTooltip:AddLine(b.description, 0.9, 0.9, 0.9, true)
  end
  if b.blessing_type then
    GameTooltip:AddLine(("Тип: %s"):format(tostring(b.blessing_type)), 0.6, 0.8, 1)
  end
  GameTooltip:Show()
end

local function ShowEmptySlotTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("Свободный слот", 1, 1, 1)
  GameTooltip:AddLine("ЛКМ по карточке сверху — добавить.
ПКМ по слоту — удалить.", 0.9, 0.9, 0.9, true)
  GameTooltip:Show()
end

local function HideTooltip()
  GameTooltip_Hide()
end

-- ---------------------------------------------------------------------------
-- ОПРЕДЕЛЕНИЕ ОКНА
-- ---------------------------------------------------------------------------
NS.BlessingWindow = BW:New("BlessingWindow", {
  windowType = NS.Config.WindowType.BLESSING,
  hooks = {
    onInit = function(self)
      if self.elements and self.elements.title then
        self.elements.title:SetText("Благословения")
      end

      -- Вкладки категорий
      local tabs = {
        { id="Defensive", title="Defensive" },
        { id="Offensive", title="Offensive" },
        { id="Support",   title="Support"   },
      }
      self.categoryTabs = self:CreateTabsBar(self.frame, tabs, {
        height = 30,
        onChange = function(id) self:SelectCategory(id) end,
      })

      -- Подпись под вкладками
      self.elements.descText = self:CreateText(self.frame, {
        template = "GameFontHighlightSmall",
        width    = self.frame:GetWidth() - 20,
        justify  = "LEFT",
        point    = { self.categoryTabs.frame, "TOPLEFT", "BOTTOMLEFT", 0, -10 },
        text     = "",
        colorKey = "dialogText",
      })

      -- Сетка карточек благословений
      self.cardGrid = self:CreateCardGrid(self.frame, {
        top    = 110,
        bottom = 110,
        cellW  = 72,
        cellH  = 72,
        cols   = 6,
        gapX   = 8,
        gapY   = 8,
      })

      -- Панель активных благословений — 12 слотов
      self.activeBar = self:CreateSlotBar(self.frame, 12, {
        size = 48,
        gap  = 6,
        cols = 12,
        plusText = "+",
        onEnter = function(i, slot)
          if slot.__blessing then ShowBlessingTooltip(slot, slot.__blessing) else ShowEmptySlotTooltip(slot) end
        end,
        onLeave = function() HideTooltip() end,
      })
      self.activeBar.frame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 16)

      self.activeBlessings = {}

      -- Обработчики слотов
      for i, slot in ipairs(self.activeBar.slots) do
        local idx = i
        slot:SetHighlightTexture("Interface\\Buttons\ButtonHilight-Square")
        slot:GetHighlightTexture():SetBlendMode("ADD")
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:HookScript("OnClick", function(_, button)
          if button == "RightButton" then
            self:RemoveBlessingFromSlot(idx)
          end
        end)
      end
    end,
  }
})

-- ---------------------------------------------------------------------------
-- ПУБЛИЧНЫЕ МЕТОДЫ ОКНА
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:Show(payload)
  BW.prototype.Show(self, payload)
  if not self.currentCategory then self.currentCategory = "Defensive" end
  self:LoadPanelState()
  self:SelectCategory(self.currentCategory)
  if NS.UIManager then NS.UIManager:ShowMessage("Окно благословений открыто", "success") end
end

function NS.BlessingWindow:Hide()
  BW.prototype.Hide(self)
end

function NS.BlessingWindow:Toggle(payload)
  BW.prototype.Toggle(self, payload)
end

-- ---------------------------------------------------------------------------
-- СИНХРОНИЗАЦИЯ C БД / КЭШЕМ
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:UpdateBlessingPanelOnServer(blessingId, isInPanel)
  local AIO = GetAIO(); if not AIO then return end
  AIO.Handle(NS.ADDON_PREFIX, "UpdateBlessingPanel", { blessingId = blessingId, isInPanel = not not isInPanel })
end

function NS.BlessingWindow:UpdateLocalBlessingState(blessingId, isInPanel)
  local dm = NS.DataManager; local data = dm and dm:GetData()
  if data and data.blessings and data.blessings[tostring(blessingId)] then
    data.blessings[tostring(blessingId)].isInPanel = not not isInPanel
  end
end

-- ---------------------------------------------------------------------------
-- ЗАГРУЗКА СОСТОЯНИЯ ПАНЕЛИ (12 слотов)
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:LoadPanelState()
  -- очистка без синхронизации
  if self.activeBar and self.activeBar.slots then
    for i in ipairs(self.activeBar.slots) do self:RemoveBlessingFromSlotSilent(i) end
  end
  local dm = NS.DataManager; local data = dm and dm:GetData(); if not (data and data.blessings) then return end
  for id, b in pairs(data.blessings) do
    if b.isDiscovered and b.isInPanel then
      local blessing = { id = tonumber(b.blessing_id) or tonumber(id), name=b.name, description=b.description, icon=b.icon, blessing_type=b.blessing_type }
      self:AddBlessingToSlotSilent(blessing)
    end
  end
end

-- ---------------------------------------------------------------------------
-- ПАНЕЛЬ: ДОБАВЛЕНИЕ / УДАЛЕНИЕ
-- ---------------------------------------------------------------------------
local function FirstFreeSlot(self)
  for i, slot in ipairs(self.activeBar.slots or {}) do if not slot.__blessing then return i end end
end

function NS.BlessingWindow:AddBlessingToSlot(blessing, card)
  if not (self.activeBar and self.activeBar.slots) then return end
  -- защита от дублей
  for _, s in ipairs(self.activeBar.slots) do
    if s.__blessing and s.__blessing.id == blessing.id then return end
  end
  local idx = FirstFreeSlot(self); if not idx then if NS.UIManager then NS.UIManager:ShowMessage("Панель заполнена (12/12)", "warning") end return end
  local slot = self.activeBar.slots[idx]
  if not slot.icon then slot.icon = slot:CreateTexture(nil, "ARTWORK"); slot.icon:SetAllPoints(); slot.icon:SetTexCoord(0.07,0.93,0.07,0.93) end
  slot.icon:SetTexture(blessing.icon); slot.icon:Show()
  if slot.__fs then slot.__fs:SetText("") end
  slot.__blessing = blessing; self.activeBlessings[idx] = blessing; slot:SetActive(true)

  -- ВАЖНО: карточку НЕ отключаем — чтобы ПКМ работал сразу
  if card then
    card.__selected = true
    if not card.__overlay then
      local ov = card:CreateTexture(nil, "OVERLAY")
      ov:SetAllPoints(card)
      ov:SetTexture("Interface\\Buttons\ButtonHilight-Square")
      ov:SetBlendMode("ADD")
      card.__overlay = ov
    end
    card.__overlay:Show()
    card:Enable(); card:EnableMouse(true); card:RegisterForClicks("LeftButtonUp","RightButtonUp")
  end

  self:UpdateBlessingPanelOnServer(blessing.id, true)
  self:UpdateLocalBlessingState(blessing.id, true)
end

function NS.BlessingWindow:AddBlessingToSlotSilent(blessing)
  if not (self.activeBar and self.activeBar.slots) then return end
  local idx = FirstFreeSlot(self); if not idx then return end
  local slot = self.activeBar.slots[idx]
  if not slot.icon then slot.icon = slot:CreateTexture(nil, "ARTWORK"); slot.icon:SetAllPoints(); slot.icon:SetTexCoord(0.07,0.93,0.07,0.93) end
  slot.icon:SetTexture(blessing.icon); slot.icon:Show()
  if slot.__fs then slot.__fs:SetText("") end
  slot.__blessing = blessing; self.activeBlessings[idx] = blessing; slot:SetActive(true)
end

function NS.BlessingWindow:RemoveBlessingFromSlot(index)
  if not (self.activeBar and self.activeBar.slots and self.activeBar.slots[index]) then return end
  local slot = self.activeBar.slots[index]; if not slot.__blessing then return end
  local b = slot.__blessing
  if slot.icon then slot.icon:Hide() end; if slot.__fs then slot.__fs:SetText("+") end
  slot.__blessing = nil; self.activeBlessings[index] = nil; slot:SetActive(false); HideTooltip()

  -- снять выделение и восстановить кликабельность карточки в гриде
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

  self:UpdateBlessingPanelOnServer(b.id, false)
  self:UpdateLocalBlessingState(b.id, false)
end

function NS.BlessingWindow:RemoveBlessingFromSlotSilent(index)
  if not (self.activeBar and self.activeBar.slots and self.activeBar.slots[index]) then return end
  local slot = self.activeBar.slots[index]; if not slot.__blessing then return end
  if slot.icon then slot.icon:Hide() end; if slot.__fs then slot.__fs:SetText("+") end
  slot.__blessing = nil; self.activeBlessings[index] = nil; slot:SetActive(false); HideTooltip()
end

function NS.BlessingWindow:RemoveBlessingById(blessingId)
  for idx, b in pairs(self.activeBlessings) do if b and b.id == blessingId then self:RemoveBlessingFromSlot(idx); return end end
end

-- ---------------------------------------------------------------------------
-- РЕНДЕРИНГ КАТЕГОРИЙ И КАРТОЧЕК
-- ---------------------------------------------------------------------------
function NS.BlessingWindow:GetBlessingsForCategory(category)
  local dm = NS.DataManager; local data = dm and dm:GetData(); local out = {}
  if data and data.blessings then
    for _, v in pairs(data.blessings) do
      if v.isDiscovered and v.blessing_type == category then
        table.insert(out, {
          id = tonumber(v.blessing_id) or tonumber(v.id) or 0,
          name = v.name, description = v.description, icon = v.icon, blessing_type = v.blessing_type,
          isInPanel = not not v.isInPanel,
        })
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
      -- чистая иконка «как у спелла»
      card:SetBackdrop(nil)
      card:SetNormalTexture(b.icon)
      card:SetPushedTexture(b.icon)
      card:SetHighlightTexture("Interface\\Buttons\ButtonHilight-Square")
      card:GetHighlightTexture():SetBlendMode("ADD")

      local icon = card:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(); icon:SetTexCoord(0.07,0.93,0.07,0.93); icon:SetTexture(b.icon)

      card.__data = b
      card:Enable(); card:EnableMouse(true); card:RegisterForClicks("LeftButtonUp","RightButtonUp")

      card:SetScript("OnEnter", function(btn) ShowBlessingTooltip(btn, b) end)
      card:SetScript("OnLeave", HideTooltip)

      card:SetScript("OnClick", function(_, button)
        if card.__selected then
          if button == "RightButton" then self:RemoveBlessingById(b.id) end
          return
        end
        if button == "LeftButton" then self:AddBlessingToSlot(b, card)
        elseif button == "RightButton" then self:RemoveBlessingById(b.id) end
      end)

      -- если уже в панели — подсветка и запрет дубля (но без Disable)
      for _, active in pairs(self.activeBlessings or {}) do
        if active and active.id == b.id then
          card.__selected = true
          if not card.__overlay then
            local ov = card:CreateTexture(nil, "OVERLAY")
            ov:SetAllPoints(card)
            ov:SetTexture("Interface\\Buttons\ButtonHilight-Square")
            ov:SetBlendMode("ADD")
            card.__overlay = ov
          end
          card.__overlay:Show()
          break
        end
      end
    end)
  end
end

function NS.BlessingWindow:SelectCategory(categoryID)
  self.currentCategory = categoryID
  if self.categoryTabs and self.categoryTabs.setActive then self.categoryTabs.setActive(categoryID) end
  local descriptions = {
    Defensive = "Defensive blessings provide protection and survivability bonuses.",
    Offensive = "Offensive blessings enhance your damage output.",
    Support   = "Support blessings offer utility and group benefits.",
  }
  if self.elements.descText then self.elements.descText:SetText(descriptions[categoryID] or "") end
  self:RenderCategory(categoryID)
end

print("|cff00ff00[PatronSystem]|r BlessingWindow загружен (stable final)")
