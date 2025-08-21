--[[==========================================================================
  PATRON SYSTEM - BLESSING WINDOW (on BaseWindow)
  Переписанный мокап окна благословений с использованием BaseWindow
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

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
      self.activeBar = self:CreateSlotBar(self.frame, {
        count = 6,
        title = "Active Blessings:",
        bottom = 15,
      })

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

  if NS.UIManager then
    NS.UIManager:ShowMessage("Категория " .. categoryID .. " выбрана (мокап)", "info")
  end
end

print("|cff00ff00[PatronSystem]|r BlessingWindow загружен")

