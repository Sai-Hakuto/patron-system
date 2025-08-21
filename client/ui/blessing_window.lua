--[[==========================================================================
  PATRON SYSTEM - BLESSING WINDOW MOCKUP
  Мокап окна благословений по дизайну пользователя (без логики)
============================================================================]]

-- Заполняем BlessingWindow в уже созданном неймспейсе
PatronSystemNS.BlessingWindow = {
    -- Состояние окна
    frame = nil,
    elements = {},
    initialized = false,
    
    -- Специфические свойства окна благословений
    currentCategory = "Defensive",
    categoryButtons = {},
    blessingCards = {},
    activeSlots = {}
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.BlessingWindow:Initialize()
    if self.initialized then return end
    
    PatronSystemNS.Logger:Info("BlessingWindow мокап инициализация")
    
    self:CreateFrame()
    self:CreateElements()
    
    self.initialized = true
    PatronSystemNS.Logger:Info("BlessingWindow мокап инициализирован")
end

--[[==========================================================================
  СОЗДАНИЕ ОСНОВНОГО ФРЕЙМА
============================================================================]]
function PatronSystemNS.BlessingWindow:CreateFrame()
    local config = PatronSystemNS.Config:GetWindowConfig(PatronSystemNS.Config.WindowType.BLESSING)
    
    self.frame = CreateFrame("Frame", "BlessingWindowFrame", UIParent, "BackdropTemplate")
    self.frame:SetSize(600, 450) -- Увеличиваем размер под новый дизайн
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 100, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame:SetFrameStrata("DIALOG")
    self.frame:Hide()
    
    -- Фон и границы
    self.frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    
    local bgColor = PatronSystemNS.Config:GetColor("windowBackground")
    self.frame:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    PatronSystemNS.Logger:UI("Создан основной фрейм BlessingWindow мокапа")
end

--[[==========================================================================
  СОЗДАНИЕ ЭЛЕМЕНТОВ UI
============================================================================]]
function PatronSystemNS.BlessingWindow:CreateElements()
    -- Заголовок окна
    self.elements.title = self.frame:CreateFontString("BlessingWindow_Title", "OVERLAY", "GameFontNormalLarge")
    self.elements.title:SetPoint("TOP", self.frame, "TOP", 0, -15)
    self.elements.title:SetText("Благословения")
    PatronSystemNS.Config:ApplyColorToText(self.elements.title, "speakerName")
    
    -- Кнопка закрытия
    self.elements.closeButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
    self.elements.closeButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -5, -5)
    self.elements.closeButton:SetScript("OnClick", function()
        self:Hide()
    end)
    
    -- Панель вкладок категорий (горизонтально сверху)
    self:CreateCategoryTabs()
    
    -- Область описания выбранной категории
    self:CreateDescriptionArea()
    
    -- Область карточек благословений
    self:CreateBlessingCardsArea()
    
    -- Панель активных благословений (снизу)
    self:CreateActiveBlessingsPanel()
    
    PatronSystemNS.Logger:UI("Созданы элементы BlessingWindow мокапа")
end

function PatronSystemNS.BlessingWindow:CreateCategoryTabs()
    -- Панель для вкладок категорий (горизонтально)
    local tabPanel = CreateFrame("Frame", nil, self.frame)
    tabPanel:SetSize(self.frame:GetWidth() - 30, 35)
    tabPanel:SetPoint("TOP", self.elements.title, "BOTTOM", 0, -10)
    
    self.elements.tabPanel = tabPanel
    
    -- Данные о категориях
    local categories = {
        {id = "Defensive", name = "Defensive", color = "patronVoid"},
        {id = "Offensive", name = "Offensive", color = "patronEluna"},
        {id = "Support", name = "Support", color = "patronDragon"}
    }
    
    local tabWidth = (self.frame:GetWidth() - 60) / #categories
    
    for i, category in ipairs(categories) do
        local btn = CreateFrame("Button", "BlessingCategoryTab" .. i, tabPanel, "UIPanelButtonTemplate")
        btn:SetSize(tabWidth, 30)
        btn:SetPoint("LEFT", tabPanel, "LEFT", (i-1) * tabWidth, 0)
        btn:SetText(category.name)
        btn.categoryID = category.id
        btn.categoryData = category
        
        -- Цветовая схема кнопки
        local categoryColor = PatronSystemNS.Config:GetColor(category.color)
        
        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(categoryColor.r * 0.5, categoryColor.g * 0.5, categoryColor.b * 0.5, 0.8)
        end)
        
        btn:SetScript("OnLeave", function()
            if self.currentCategory ~= category.id then
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            end
        end)
        
        btn:SetScript("OnClick", function()
            self:SelectCategory(category.id, category)
        end)
        
        table.insert(self.categoryButtons, btn)
    end
    
    -- Выбираем первую категорию по умолчанию
    self:SelectCategory("Defensive", categories[1])
end

function PatronSystemNS.BlessingWindow:CreateDescriptionArea()
    -- Область для описания выбранной категории
    local descArea = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    descArea:SetSize(self.frame:GetWidth() - 30, 40)
    descArea:SetPoint("TOP", self.elements.tabPanel, "BOTTOM", 0, -5)
    
    descArea:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    
    local bgColor = PatronSystemNS.Config:GetColor("panelBackground")
    descArea:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    self.elements.descArea = descArea
    
    -- Текст описания
    self.elements.descText = descArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.elements.descText:SetPoint("LEFT", descArea, "LEFT", 10, 0)
    self.elements.descText:SetPoint("RIGHT", descArea, "RIGHT", -10, 0)
    self.elements.descText:SetJustifyH("LEFT")
    self.elements.descText:SetWordWrap(true)
    self.elements.descText:SetText("Defensive blessings provide protection and survivability bonuses to help you survive in dangerous situations.")
    PatronSystemNS.Config:ApplyColorToText(self.elements.descText, "dialogText")
end

function PatronSystemNS.BlessingWindow:CreateBlessingCardsArea()
    -- Область для карточек благословений
    local cardsArea = CreateFrame("ScrollFrame", nil, self.frame, "BackdropTemplate")
    cardsArea:SetSize(self.frame:GetWidth() - 30, 220)
    cardsArea:SetPoint("TOP", self.elements.descArea, "BOTTOM", 0, -5)
    
    cardsArea:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    
    local bgColor = PatronSystemNS.Config:GetColor("panelBackground")
    cardsArea:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    self.elements.cardsArea = cardsArea
    
    -- Контент для скролла
    local cardsContent = CreateFrame("Frame", nil, cardsArea)
    cardsContent:SetSize(cardsArea:GetWidth() - 20, cardsArea:GetHeight())
    cardsArea:SetScrollChild(cardsContent)
    self.elements.cardsContent = cardsContent
    
    -- Создаем мокап карточек благословений
    self:CreateMockupBlessingCards()
end

function PatronSystemNS.BlessingWindow:CreateMockupBlessingCards()
    -- Мокап данные благословений для демонстрации
    local mockupBlessings = {
        {name = "Shield Blessing", icon = "Interface\\ICONS\\spell_holy_devotion", desc = "Increases armor by 20%"},
        {name = "Resist Curse", icon = "Interface\\ICONS\\spell_holy_removecurse", desc = "Immunity to curses"},
        {name = "Divine Protection", icon = "Interface\\ICONS\\spell_holy_divineprotection", desc = "Reduces damage by 15%"},
        {name = "Health Boost", icon = "Interface\\ICONS\\spell_holy_heal", desc = "Increases max health"},
        {name = "Mana Shield", icon = "Interface\\ICONS\\spell_frost_frostarmor", desc = "Absorbs damage with mana"},
        {name = "Stone Skin", icon = "Interface\\ICONS\\spell_earth_stoneskin", desc = "Physical damage resistance"},
        {name = "Holy Ward", icon = "Interface\\ICONS\\spell_holy_sanctuary", desc = "Protection from evil"},
        {name = "Barrier", icon = "Interface\\ICONS\\spell_holy_powerwordbarrier", desc = "Temporary damage immunity"}
    }
    
    local cardWidth = 100
    local cardHeight = 80
    local cardsPerRow = 5
    local spacing = 10
    
    for i, blessing in ipairs(mockupBlessings) do
        local card = self:CreateBlessingCard(blessing, i)
        
        -- Вычисляем позицию карточки (сетка 5x2)
        local row = math.floor((i - 1) / cardsPerRow)
        local col = (i - 1) % cardsPerRow
        
        card:SetPoint("TOPLEFT", self.elements.cardsContent, "TOPLEFT", 
                     10 + col * (cardWidth + spacing), 
                     -10 - row * (cardHeight + spacing))
                     
        table.insert(self.blessingCards, card)
    end
end

function PatronSystemNS.BlessingWindow:CreateBlessingCard(blessing, index)
    -- Создаем карточку благословения
    local card = CreateFrame("Button", "BlessingCard" .. index, self.elements.cardsContent, "BackdropTemplate")
    card:SetSize(100, 80)
    
    -- Красивый фон карточки
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    
    card:SetBackdropColor(0.1, 0.1, 0.2, 0.8)
    card:SetBackdropBorderColor(0.3, 0.3, 0.5, 1)
    
    -- Иконка благословения
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", card, "TOP", 0, -8)
    icon:SetTexture(blessing.icon)
    card.icon = icon
    
    -- Название благословения
    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    name:SetWidth(card:GetWidth() - 6)
    name:SetWordWrap(true)
    name:SetJustifyH("CENTER")
    name:SetText(blessing.name)
    card.nameText = name
    
    -- Hover эффекты
    card:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1.0)
        self:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
        
        -- Tooltip
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(blessing.name)
        GameTooltip:AddLine(blessing.desc, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    
    card:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.2, 0.8)
        self:SetBackdropBorderColor(0.3, 0.3, 0.5, 1)
        GameTooltip:Hide()
    end)
    
    -- Клик (пока просто сообщение)
    card:SetScript("OnClick", function()
        PatronSystemNS.Logger:UI("Clicked blessing: " .. blessing.name)
        if PatronSystemNS.UIManager then
            PatronSystemNS.UIManager:ShowMessage("Выбрано благословение: " .. blessing.name .. " (мокап)", "info")
        end
    end)
    
    -- Сохраняем данные благословения
    card.blessingData = blessing
    
    return card
end

function PatronSystemNS.BlessingWindow:CreateActiveBlessingsPanel()
    -- Панель активных благословений внизу
    local activePanel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    activePanel:SetSize(self.frame:GetWidth() - 30, 80)
    activePanel:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 15)
    
    activePanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    
    local bgColor = PatronSystemNS.Config:GetColor("panelBackground")
    activePanel:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    self.elements.activePanel = activePanel
    
    -- Заголовок "Active Blessings"
    self.elements.activeBlessingsTitle = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.elements.activeBlessingsTitle:SetPoint("TOPLEFT", activePanel, "TOPLEFT", 10, -8)
    self.elements.activeBlessingsTitle:SetText("Active Blessings:")
    PatronSystemNS.Config:ApplyColorToText(self.elements.activeBlessingsTitle, "speakerName")
    
    -- Создаем слоты для активных благословений (6 слотов в ряд)
    for i = 1, 6 do
        local slot = CreateFrame("Frame", "ActiveBlessingSlot" .. i, activePanel, "BackdropTemplate")
        slot:SetSize(50, 50)
        slot:SetPoint("TOPLEFT", self.elements.activeBlessingsTitle, "BOTTOMLEFT", 
                     10 + (i-1) * 55, -10)
        
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-Quickslot2",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 50,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        
        slot:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        slot:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        
        -- Плюсик для пустого слота
        local plusText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        plusText:SetPoint("CENTER", slot, "CENTER")
        plusText:SetText("+")
        plusText:SetTextColor(0.6, 0.6, 0.6, 1)
        slot.plusText = plusText
        
        -- Hover эффект для слота
        slot:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        end)
        
        slot:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end)
        
        slot.slotID = i
        table.insert(self.activeSlots, slot)
    end
end

--[[==========================================================================
  ОСНОВНЫЕ МЕТОДЫ ОКНА
============================================================================]]
function PatronSystemNS.BlessingWindow:Show()
    if not self.initialized then
        self:Initialize()
    end
    
    PatronSystemNS.Logger:UI("Показ окна BlessingWindow (мокап)")
    
    self.frame:Show()
    
    -- Сообщение что это мокап
    if PatronSystemNS.UIManager then
        PatronSystemNS.UIManager:ShowMessage("Окно благословений - визуальный мокап готов!", "success")
    end
end

function PatronSystemNS.BlessingWindow:Hide()
    PatronSystemNS.Logger:UI("Скрытие окна BlessingWindow (мокап)")
    
    if self.frame then
        self.frame:Hide()
    end
end

function PatronSystemNS.BlessingWindow:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function PatronSystemNS.BlessingWindow:SelectCategory(categoryID, categoryData)
    PatronSystemNS.Logger:UI("Выбрана категория благословений: " .. categoryID)
    
    self.currentCategory = categoryID
    
    -- Обновляем подсветку кнопок категорий
    for _, btn in ipairs(self.categoryButtons) do
        if btn.categoryID == categoryID then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
    
    -- Обновляем описание категории
    local descriptions = {
        Defensive = "Defensive blessings provide protection and survivability bonuses to help you survive in dangerous situations.",
        Offensive = "Offensive blessings enhance your damage output and combat effectiveness against your enemies.", 
        Support = "Support blessings offer utility effects like movement speed, resource regeneration, and group benefits."
    }
    
    if self.elements.descText then
        self.elements.descText:SetText(descriptions[categoryID] or "Category description not available.")
    end
    
    -- В будущем здесь будет обновление карточек для выбранной категории
    if PatronSystemNS.UIManager then
        PatronSystemNS.UIManager:ShowMessage("Категория " .. categoryID .. " выбрана (мокап)", "info")
    end
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.BlessingWindow:GetFrame()
    return self.frame
end

function PatronSystemNS.BlessingWindow:IsShown()
    return self.frame and self.frame:IsShown()
end

print("|cff00ff00[PatronSystem]|r BlessingWindow мокап загружен")