--[[==========================================================================
  PATRON SYSTEM - BLESSING WINDOW (on BaseWindow)
  Переписанный мокап окна благословений с использованием BaseWindow
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

local testBlessings = {
  Defensive = {
    { id = 1, name = "Iron Skin",  icon = "Interface\\Icons\\Spell_Shield_Strength",    type = "Defensive" },
    { id = 2, name = "Stone Ward", icon = "Interface\\Icons\\Ability_Warrior_ShieldWall", type = "Defensive" },
  },
  Offensive = {
    { id = 3, name = "Power Strike", icon = "Interface\\Icons\\Ability_Warrior_Devastate",  type = "Offensive" },
    { id = 4, name = "Flame Wrath",  icon = "Interface\\Icons\\Spell_Fire_Immolation",      type = "Offensive" },
  },
  Support = {
    { id = 5, name = "Swift Wind", icon = "Interface\\Icons\\Spell_Nature_Swiftness",   type = "Support" },
    { id = 6, name = "Insight",    icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", type = "Support" },
  },
}

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

      -- Стартовая категория
      self:SelectCategory("Defensive")
    end,
  }
})

function NS.BlessingWindow:Show(payload)
  BW.prototype.Show(self, payload)
  NS.Logger:UI("Показ окна BlessingWindow (мокап)")
  if NS.UIManager then
    NS.UIManager:ShowMessage("Окно благословений - визуальный мокап готов!", "success")
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
  end
end

function NS.BlessingWindow:RenderCategory(category)
  if not self.cardGrid then return end
  self.cardGrid:Clear()
  for _, blessing in ipairs(testBlessings[category] or {}) do
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
    end)
  end
end

function NS.BlessingWindow:SelectCategory(categoryID)
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

  self:RenderCategory(categoryID)

  if NS.UIManager then
    NS.UIManager:ShowMessage("Категория " .. categoryID .. " выбрана (мокап)", "info")
  end
end

print("|cff00ff00[PatronSystem]|r BlessingWindow загружен")

