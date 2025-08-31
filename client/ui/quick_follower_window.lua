--[[============================================================================
  PATRON SYSTEM — QUICK FOLLOWER WINDOW
  Быстрая панель фолловеров
  Показывает до трёх открытых фолловеров
============================================================================]]--

local NS = PatronSystemNS
local BW = NS.BaseWindow

NS.QuickFollowerWindow = BW:New("QuickFollowerWindow", {
    windowType = NS.Config.WindowType.DEBUG,
    hooks = {
        onInit = function(self)
            self.followers = {}
            self.buttons = {}
            self.commandButtons = {}
            self.currentlyShowingCommandsFor = nil -- ID фолловера, для которого показаны команды
            self.frame:SetScript("OnHide", function() 
                self:HideCommandButtons() 
                self.currentlyShowingCommandsFor = nil
            end)
        end,
    }
})

function NS.QuickFollowerWindow:CreateFrame()
    BW.prototype.CreateFrame(self)
    if self.frame then
        self.frame:SetSize(400, 120) -- Увеличиваем ширину для горизонтальной компоновки
        self.frame:SetBackdrop(nil)
        local bg = self.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(true)
        bg:SetColorTexture(0.08, 0.08, 0.1, 0.85)
        self.elements.background = bg
    end
end

function NS.QuickFollowerWindow:CreateCore()
    BW.prototype.CreateCore(self)
    if self.elements.title then
        self.elements.title:SetText("Followers")
    end
    self:CreateLockButton()
end

function NS.QuickFollowerWindow:Show(payload)
    BW.prototype.Show(self, payload)
    self:RefreshData()
end

function NS.QuickFollowerWindow:RefreshData()
    self:LoadActiveFollowers()
    self:CreateFollowerButtons()
    self:AdjustWindowSize()
end

function NS.QuickFollowerWindow:LoadActiveFollowers()
    if not self.followers then self.followers = {} end
    wipe(self.followers)
    local progress = NS.DataManager and NS.DataManager:GetPlayerProgress()
    local followers = progress and progress.followers
    if not followers then return end
    for id, info in pairs(followers) do
        if info.isDiscovered then
            local idNum = tonumber(id)
            local speaker = NS.Config:GetSpeakerByID(idNum, NS.Config.SpeakerType.FOLLOWER)
            table.insert(self.followers, {
                id = idNum,
                name = (speaker and speaker.name) or ("Follower " .. tostring(idNum)),
                isActive = info.isActive
            })
            if #self.followers >= 3 then break end
        end
    end
    table.sort(self.followers, function(a, b) return (a.id or 0) < (b.id or 0) end)
end

function NS.QuickFollowerWindow:CreateFollowerButtons()
    for _, btn in ipairs(self.buttons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(self.buttons)
    self:HideCommandButtons()

    local width, height = 110, 50 -- Уменьшаем ширину для горизонтальной компоновки
    local spacing = 10
    local startX = 20
    local startY = -40

    for i, fol in ipairs(self.followers) do
        local banner = CreateFrame("Button", "QuickFollower_Banner" .. i, self.frame, "BackdropTemplate")
        banner:SetSize(width, height)
        -- ГОРИЗОНТАЛЬНАЯ компоновка
        banner:SetPoint("TOPLEFT", self.frame, "TOPLEFT", startX + (i - 1) * (width + spacing), startY)

        -- Устанавливаем backdrop для стиля банера как в Main_Window
        banner:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })

        banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        banner.title:SetPoint("CENTER", banner, "CENTER", 0, 0)
        banner.title:SetText(fol.name)

        -- Сохраняем ID фолловера для логики повторного нажатия
        banner.followerData = fol

        NS.BaseWindow.AttachBannerBehavior(banner, "patronDragon", fol.name, function()
            self:OnFollowerBannerClick(banner, fol)
        end)

        table.insert(self.buttons, banner)
    end
end

-- Новая логика обработки клика по банеру фолловера
function NS.QuickFollowerWindow:OnFollowerBannerClick(banner, follower)
    -- Если это повторное нажатие на тот же банер - скрыть команды
    if self.currentlyShowingCommandsFor == follower.name then
        self:HideCommandButtons()
        self.currentlyShowingCommandsFor = nil
        return
    end
    
    -- Иначе показать команды для нового фолловера
    self:ShowCommandButtons(banner, follower)
    self.currentlyShowingCommandsFor = follower.name
end

function NS.QuickFollowerWindow:ShowCommandButtons(banner, follower)
    self:HideCommandButtons()
    local commands = {
        follower.isActive and "Отпустить" or "Призвать",
        "Атакуем все цели!",
        "Переходим в оборону!",
        "Охраняем эту позицию!",
        "Вернись к своей роли!"
    }
    
    local width, height = 150, 28
    local spacing = 5
    
    for i, text in ipairs(commands) do
        -- СОЗДАЕМ КНОПКИ КАК ДОЧЕРНИЕ UIParent, А НЕ self.frame!
        local btn = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        btn:SetSize(width, height)
        btn:SetFrameStrata("FULLSCREEN_DIALOG") -- Поверх всех окон
        
        -- Позиционируем относительно банера, но кнопка не в контейнере панели
        btn:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -5 - (i - 1) * (height + spacing))
        
        -- Устанавливаем backdrop как у банеров
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        
        btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.title:SetPoint("CENTER", btn, "CENTER")
        btn.title:SetText(text)
        
        -- Используем AttachBannerBehavior для единообразного стиля и поведения
        NS.BaseWindow.AttachBannerBehavior(btn, "patronDragon", text, function()
            self:ExecuteCommand(follower, i, text)
        end)
        
        table.insert(self.commandButtons, btn)
    end
    
    -- НЕ ИЗМЕНЯЕМ высоту окна - кнопки теперь вне контейнера
end

function NS.QuickFollowerWindow:ExecuteCommand(follower, commandIndex, commandText)
    -- Здесь будет логика выполнения команд фолловера
    NS.Logger:Info("QuickFollowerWindow: выполнение команды '" .. commandText .. "' для фолловера " .. follower.name)
    
    -- Пример заглушек для команд
    if commandIndex == 1 then
        -- Призвать/Отпустить
        if follower.isActive then
            NS.UIManager:ShowMessage("Отпускаем фолловера " .. follower.name, "info")
        else
            NS.UIManager:ShowMessage("Призываем фолловера " .. follower.name, "info")
        end
    elseif commandIndex == 2 then
        -- Атакуем все цели
        NS.UIManager:ShowMessage(follower.name .. " переходит в режим атаки всех целей", "info")
    elseif commandIndex == 3 then
        -- Переходим в оборону
        NS.UIManager:ShowMessage(follower.name .. " переходит в режим обороны", "info")
    elseif commandIndex == 4 then
        -- Охраняем эту позицию
        NS.UIManager:ShowMessage(follower.name .. " охраняет текущую позицию", "info")
    elseif commandIndex == 5 then
        -- Вернись к своей роли
        NS.UIManager:ShowMessage(follower.name .. " возвращается к своей роли", "info")
    end
    
    -- Скрываем команды после выполнения
    self:HideCommandButtons()
    self.currentlyShowingCommandsFor = nil
end

function NS.QuickFollowerWindow:HideCommandButtons()
    for _, btn in ipairs(self.commandButtons or {}) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(self.commandButtons)
    
    -- Не нужно сбрасывать высоту - окно не растягивается
end

function NS.QuickFollowerWindow:AdjustWindowSize()
    -- Для горизонтальной компоновки ширина зависит от количества фолловеров
    local followerCount = #self.followers
    local bannerWidth = 110
    local spacing = 10
    local baseWidth = 40 -- отступы по краям
    local totalWidth = baseWidth + (followerCount * bannerWidth) + ((followerCount - 1) * spacing)
    
    -- Минимальная ширина
    totalWidth = math.max(totalWidth, 260)
    
    self.frame:SetSize(totalWidth, 120)
end

print("|cff00ff00[PatronSystem]|r QuickFollowerWindow загружен")

