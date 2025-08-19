--[[==========================================================================
  PATRON SYSTEM - MAIN WINDOW MODULE
  Главное окно выбора разделов системы (Patrons/Followers/Blessings/Shop)
============================================================================]]

-- Заполняем MainWindow в уже созданном неймспейсе
PatronSystemNS.MainWindow = {
    -- Состояние окна
    frame = nil,
    elements = {},
    initialized = false,
    
    -- Специфические свойства главного окна
    bannerButtons = {},
    currentSection = nil
}

--[[==========================================================================
  ИНИЦИАЛИЗАЦИЯ
============================================================================]]
function PatronSystemNS.MainWindow:Initialize()
    if self.initialized then return end
    
    PatronSystemNS.Logger:Info("MainWindow инициализация...")
    
    self:CreateFrame()
    self:CreateElements()
    
    self.initialized = true
    PatronSystemNS.Logger:Info("MainWindow инициализирован")
end

--[[==========================================================================
  СОЗДАНИЕ ОСНОВНОГО ФРЕЙМА
============================================================================]]
function PatronSystemNS.MainWindow:CreateFrame()
    local config = PatronSystemNS.Config:GetUIConfig("mainWindow")
    
    self.frame = CreateFrame("Frame", "PatronMainWindowFrame", UIParent, "BackdropTemplate")
    self.frame:SetSize(config.width or 500, config.height or 400)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
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
    
    PatronSystemNS.Logger:UI("Создан основной фрейм MainWindow")
end

--[[==========================================================================
  СОЗДАНИЕ ЭЛЕМЕНТОВ UI
============================================================================]]
function PatronSystemNS.MainWindow:CreateElements()
    -- Заголовок окна
    self.elements.title = self.frame:CreateFontString("MainWindow_Title", "OVERLAY", "GameFontNormalLarge")
    self.elements.title:SetPoint("TOP", self.frame, "TOP", 0, -15)
    self.elements.title:SetText("Система Покровителей")
    PatronSystemNS.Config:ApplyColorToText(self.elements.title, "speakerName")
    
    -- Кнопка закрытия
    self.elements.closeButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
    self.elements.closeButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -5, -5)
    self.elements.closeButton:SetScript("OnClick", function()
        self:Hide()
    end)
    
    -- Левая панель (Name + Info)
    self:CreateLeftPanel()
    
    -- Правые банеры разделов
    self:CreateSectionBanners()
    
    PatronSystemNS.Logger:UI("Созданы элементы MainWindow")
end

function PatronSystemNS.MainWindow:CreateLeftPanel()
    -- Левая панель для персональной информации
    local leftPanel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    leftPanel:SetSize(150, 300)
    leftPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 15, -50)
    
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    
    local bgColor = PatronSystemNS.Config:GetColor("panelBackground")
    leftPanel:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    self.elements.leftPanel = leftPanel
    
    -- Заголовок "Name"
    self.elements.nameTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.elements.nameTitle:SetPoint("TOP", leftPanel, "TOP", 0, -15)
    self.elements.nameTitle:SetText("Name")
    PatronSystemNS.Config:ApplyColorToText(self.elements.nameTitle, "speakerName")
    
    -- Имя игрока (заглушка)
    self.elements.playerName = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.elements.playerName:SetPoint("TOP", self.elements.nameTitle, "BOTTOM", 0, -10)
    self.elements.playerName:SetText(UnitName("player") or "Player")
    
    -- Информация о ресурсах
    self.elements.infoTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.elements.infoTitle:SetPoint("TOP", self.elements.playerName, "BOTTOM", 0, -20)
    self.elements.infoTitle:SetText("Info plus money,\nsouls and\nsuffering points")
    self.elements.infoTitle:SetJustifyH("LEFT")
    PatronSystemNS.Config:ApplyColorToText(self.elements.infoTitle, "dialogText")
    
    -- ЗАГЛУШКА: Ресурсы игрока
    self.elements.resources = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.elements.resources:SetPoint("TOP", self.elements.infoTitle, "BOTTOM", 0, -10)
    self.elements.resources:SetText("Money: 1000g\nSouls: 50\nSuffering: 25")
    self.elements.resources:SetJustifyH("LEFT")
    PatronSystemNS.Config:ApplyColorToText(self.elements.resources, "itemLegendary")
end

function PatronSystemNS.MainWindow:CreateSectionBanners()
    -- Конфигурация баннеров - ОБНОВЛЕНО: растягиваем до конца окна
    local bannerConfig = {
        width = 300, -- Увеличена ширина для растягивания до края
        height = 60,
        spacing = 15,
        startX = 180,
        startY = -50
    }
    
    -- ОБНОВЛЕННЫЕ данные о разделах с новыми действиями
    local sections = {
        {
            id = "patrons",
            title = "Patrons",
            description = "Взаимодействие с покровителями",
            color = "patronVoid",
            action = "OPEN_PATRONS"
        },
        {
            id = "followers", 
            title = "Followers",
            description = "Управление последователями",
            color = "patronDragon",
            action = "OPEN_FOLLOWERS"
        },
        {
            id = "blessings",
            title = "Blessings", 
            description = "Система благословений",
            color = "patronEluna",
            action = "OPEN_BLESSINGS"  -- НОВОЕ: Реальное действие
        },
        {
            id = "shop",
            title = "Shop",
            description = "Магазин предметов и услуг",
            color = "itemLegendary",
            action = "OPEN_SHOP"  -- НОВОЕ: Реальное действие
        }
    }
    
    -- Создаем баннеры вертикально (без изменений)
    for i, section in ipairs(sections) do
        local banner = self:CreateSectionBanner(
            section,
            bannerConfig.startX,
            bannerConfig.startY - (i - 1) * (bannerConfig.height + bannerConfig.spacing),
            bannerConfig.width,
            bannerConfig.height
        )
        
        table.insert(self.bannerButtons, banner)
    end
end

function PatronSystemNS.MainWindow:CreateSectionBanner(sectionData, x, y, width, height)
    -- Создаем кнопку-баннер
    local banner = CreateFrame("Button", "MainWindow_Banner_" .. sectionData.id, self.frame, "BackdropTemplate")
    banner:SetSize(width, height)
    banner:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    
    -- Фон баннера
    banner:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    
    -- Цвет фона в зависимости от раздела
    local sectionColor = PatronSystemNS.Config:GetColor(sectionData.color)
    banner:SetBackdropColor(sectionColor.r * 0.3, sectionColor.g * 0.3, sectionColor.b * 0.3, 0.8)
    banner:SetBackdropBorderColor(sectionColor.r, sectionColor.g, sectionColor.b, 1)
    
    -- Заголовок
    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner.title:SetPoint("CENTER", banner, "CENTER", 0, 5)
    banner.title:SetText(sectionData.title)
    banner.title:SetTextColor(sectionColor.r, sectionColor.g, sectionColor.b, 1)
    
    -- Описание (меньшим шрифтом)
    banner.description = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.description:SetPoint("CENTER", banner, "CENTER", 0, -15)
    banner.description:SetText(sectionData.description)
    banner.description:SetTextColor(0.8, 0.8, 0.8, 1)
	
	PatronSystemNS.BaseWindow.AttachBannerBehavior(
	  banner,
	  sectionData.color,
	  sectionData.title,
	  function() self:OnSectionSelected(sectionData.id, sectionData.action) end
	)
    
    -- Сохраняем данные раздела
    banner.sectionData = sectionData
    
    return banner
end

--[[==========================================================================
  ОСНОВНЫЕ МЕТОДЫ ОКНА
============================================================================]]
function PatronSystemNS.MainWindow:Show()
    if not self.initialized then
        self:Initialize()
    end
    
    PatronSystemNS.Logger:UI("Показ главного окна MainWindow")
    
    self.frame:Show()
    
    -- Обновляем информацию о игроке
    self:UpdatePlayerInfo()
end

function PatronSystemNS.MainWindow:Hide()
    PatronSystemNS.Logger:UI("Скрытие главного окна MainWindow")
    
    if self.frame then
        self.frame:Hide()
    end
end

function PatronSystemNS.MainWindow:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function PatronSystemNS.MainWindow:UpdatePlayerInfo()
    if not self.elements.playerName then return end
    
    -- Обновляем имя игрока
    self.elements.playerName:SetText(UnitName("player") or "Player")
    
    -- ЗАГЛУШКА: Здесь должна быть логика получения ресурсов игрока
    if self.elements.resources then
        self.elements.resources:SetText("Money: " .. GetMoney() .. "c\nSouls: [STUB]\nSuffering: [STUB]")
    end
end

--[[==========================================================================
  ОБРАБОТКА СОБЫТИЙ
============================================================================]]
function PatronSystemNS.MainWindow:OnSectionSelected(sectionId, action)
    PatronSystemNS.Logger:UI("Выбран раздел: " .. sectionId .. " (действие: " .. action .. ")")
    
    self.currentSection = sectionId
    
    if action == "OPEN_PATRONS" then
        -- ИСПРАВЛЕНО: Используем "умное" открытие покровителей
        PatronSystemNS.Logger:UI("Открытие окна покровителей (умная логика)")
        
        -- НЕ скрываем главное окно, оставляем открытым
        PatronSystemNS.UIManager:ShowPatronWindowSmart()  -- НОВАЯ ФУНКЦИЯ!
        
    elseif action == "OPEN_FOLLOWERS" then
        -- Открытие окна фолловеров
        PatronSystemNS.Logger:UI("Открытие окна фолловеров")
        PatronSystemNS.UIManager:ShowFollowerWindowSmart()
        
    elseif action == "OPEN_BLESSINGS" then
        PatronSystemNS.Logger:UI("Открытие окна благословений")
        PatronSystemNS.UIManager:ShowBlessingWindow()
        
    elseif action == "OPEN_SHOP" then
        PatronSystemNS.Logger:UI("Открытие окна магазина")
        PatronSystemNS.UIManager:ShowShopWindow()
        
    elseif action == "STUB" then
        -- ЗАГЛУШКИ для нереализованных разделов
        local messages = {
            followers = "Система последователей будет реализована в следующих обновлениях"
        }
        
        local message = messages[sectionId] or "Этот раздел пока не реализован"
        
        if PatronSystemNS.UIManager then
            PatronSystemNS.UIManager:ShowMessage(message, "info")
        end
    end
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ
============================================================================]]
function PatronSystemNS.MainWindow:GetFrame()
    return self.frame
end

function PatronSystemNS.MainWindow:IsShown()
    return self.frame and self.frame:IsShown()
end

function PatronSystemNS.MainWindow:GetCurrentSection()
    return self.currentSection
end

function PatronSystemNS.MainWindow:SetInfoText(text)
    if self.elements.infoText then
        self.elements.infoText:SetText(text)
    end
end

-- Метод для динамического обновления баннеров (если понадобится)
function PatronSystemNS.MainWindow:UpdateSectionBanner(sectionId, data)
    for _, banner in ipairs(self.bannerButtons) do
        if banner.sectionData.id == sectionId then
            if data.title then
                banner.title:SetText(data.title)
            end
            if data.description then
                banner.description:SetText(data.description)
            end
            break
        end
    end
end

print("|cff00ff00[PatronSystem]|r MainWindow загружен. Обновлен для новых окон")