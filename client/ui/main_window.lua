--[[==========================================================================
  PATRON SYSTEM - MAIN WINDOW MODULE (на базе BaseWindow v2)
  Главное окно выбора разделов системы (Patrons/Followers/Blessings/Shop)
============================================================================]]

local NS = PatronSystemNS
local BW = NS.BaseWindow

-- Создаём объект окна на базе BaseWindow
NS.MainWindow = BW:New("MainWindow", {
  windowType = NS.Config.WindowType.MAIN or NS.Config.WindowType.DEFAULT,
  hooks = {
    onInit = function(self)
      -- Заголовок
      if self.elements.title then
        self.elements.title:SetText("Система Покровителей")
      end
      
      -- Создаем кнопку-замок для блокировки перетаскивания
      self:CreateLockButton()
      
      -- Специфические свойства главного окна
      self.bannerButtons = {}
      self.currentSection = nil
      
      -- Создаем уникальные элементы MainWindow
      self:CreateMainWindowElements()
    end
  }
})

--[[==========================================================================
  ПЕРЕОПРЕДЕЛЕНИЕ МЕТОДОВ BASEWINDOW
============================================================================]]

--- Переопределяем создание фрейма для специфичных настроек главного окна
function NS.MainWindow:CreateFrame()
  -- Вызываем базовый метод для создания стандартного фрейма
  BW.prototype.CreateFrame(self)
  
  -- Настраиваем размер для главного окна
  local config = NS.Config:GetUIConfig("mainWindow")
  self.frame:SetSize(config.width or 500, config.height or 400)
  
  NS.Logger:UI("Создан специализированный фрейм MainWindow")
end

--[[==========================================================================
  УНИКАЛЬНЫЕ ЭЛЕМЕНТЫ ГЛАВНОГО ОКНА
============================================================================]]
function NS.MainWindow:CreateMainWindowElements()
    -- Левая панель (Name + Info)
    self:CreateLeftPanel()
    
    -- Правые банеры разделов
    self:CreateSectionBanners()
    
    NS.Logger:UI("Созданы уникальные элементы MainWindow")
end

function NS.MainWindow:CreateLeftPanel()
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
    
    local bgColor = NS.Config:GetColor("panelBackground")
    leftPanel:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    
    self.elements.leftPanel = leftPanel
    
    -- Заголовок "Name"
    self.elements.nameTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.elements.nameTitle:SetPoint("TOP", leftPanel, "TOP", 0, -15)
    self.elements.nameTitle:SetText("Name")
    NS.Config:ApplyColorToText(self.elements.nameTitle, "speakerName")
    
    -- Имя игрока (заглушка)
    self.elements.playerName = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.elements.playerName:SetPoint("TOP", self.elements.nameTitle, "BOTTOM", 0, -10)
    self.elements.playerName:SetText(UnitName("player") or "Player")
    
    -- Информация о ресурсах
    self.elements.infoTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.elements.infoTitle:SetPoint("TOP", self.elements.playerName, "BOTTOM", 0, -20)
    self.elements.infoTitle:SetText("Info plus money,\nsouls and\nsuffering points")
    self.elements.infoTitle:SetJustifyH("LEFT")
    NS.Config:ApplyColorToText(self.elements.infoTitle, "dialogText")
    
    -- ЗАГЛУШКА: Ресурсы игрока
    self.elements.resources = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.elements.resources:SetPoint("TOP", self.elements.infoTitle, "BOTTOM", 0, -10)
    self.elements.resources:SetText("Money: 1000g\nSouls: 50\nSuffering: 25")
    self.elements.resources:SetJustifyH("LEFT")
    NS.Config:ApplyColorToText(self.elements.resources, "itemLegendary")
end

function NS.MainWindow:CreateSectionBanners()
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

function NS.MainWindow:CreateSectionBanner(sectionData, x, y, width, height)
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
    local sectionColor = NS.Config:GetColor(sectionData.color)
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
	
	NS.BaseWindow.AttachBannerBehavior(
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
  ПЕРЕОПРЕДЕЛЕНИЕ МЕТОДОВ BASEWINDOW ДЛЯ ГЛАВНОГО ОКНА
============================================================================]]
function NS.MainWindow:Show(payload)
    NS.Logger:UI("Показ главного окна MainWindow")
    
    -- Вызываем базовый метод Show
    BW.prototype.Show(self, payload)
    
    -- Обновляем информацию о игроке
    self:UpdatePlayerInfo()
end

function NS.MainWindow:Hide()
    NS.Logger:UI("Скрытие главного окна MainWindow")
    BW.prototype.Hide(self)
end

function NS.MainWindow:Toggle(payload)
    BW.prototype.Toggle(self, payload)
end

function NS.MainWindow:UpdatePlayerInfo()
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
function NS.MainWindow:OnSectionSelected(sectionId, action)
    NS.Logger:UI("Выбран раздел: " .. sectionId .. " (действие: " .. action .. ")")
    
    self.currentSection = sectionId
    
    if action == "OPEN_PATRONS" then
        -- ИСПРАВЛЕНО: Используем "умное" открытие покровителей
        NS.Logger:UI("Открытие окна покровителей (умная логика)")
        
        -- НЕ скрываем главное окно, оставляем открытым
        NS.UIManager:ShowPatronWindowSmart()  -- НОВАЯ ФУНКЦИЯ!
        
    elseif action == "OPEN_FOLLOWERS" then
        -- Открытие окна фолловеров
        NS.Logger:UI("Открытие окна фолловеров")
        NS.UIManager:ShowFollowerWindowSmart()
        
    elseif action == "OPEN_BLESSINGS" then
        NS.Logger:UI("Открытие окна благословений")
        NS.UIManager:ShowBlessingWindowSmart()
        
    elseif action == "OPEN_SHOP" then
        NS.Logger:UI("Открытие окна магазина")
        NS.UIManager:ShowShopWindow()
        
    elseif action == "STUB" then
        -- ЗАГЛУШКИ для нереализованных разделов
        local messages = {
            followers = "Система последователей будет реализована в следующих обновлениях"
        }
        
        local message = messages[sectionId] or "Этот раздел пока не реализован"
        
        if NS.UIManager then
            NS.UIManager:ShowMessage(message, "info")
        end
    end
end

--[[==========================================================================
  УТИЛИТАРНЫЕ ФУНКЦИИ (BaseWindow наследуется автоматически)
============================================================================]]
-- GetFrame, IsShown теперь наследуются от BaseWindow

function NS.MainWindow:GetCurrentSection()
    return self.currentSection
end

function NS.MainWindow:SetInfoText(text)
    if self.elements.infoText then
        self.elements.infoText:SetText(text)
    end
end

-- Метод для динамического обновления баннеров (если понадобится)
function NS.MainWindow:UpdateSectionBanner(sectionId, data)
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

-- Алиас для обратной совместимости
PatronSystemNS.MainWindow = NS.MainWindow

print("|cff00ff00[PatronSystem]|r MainWindow загружен (BaseWindow v2). Обновлен для новых окон")