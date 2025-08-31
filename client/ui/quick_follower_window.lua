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
            self.frame:SetScript("OnHide", function() self:HideCommandButtons() end)
        end,
    }
})

function NS.QuickFollowerWindow:CreateFrame()
    BW.prototype.CreateFrame(self)
    if self.frame then
        self.frame:SetSize(260, 180)
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
            local speaker = NS.Config:GetSpeakerByID(id, NS.Config.SpeakerType.FOLLOWER)
            table.insert(self.followers, {
                id = tonumber(id),
                name = (speaker and speaker.name) or ("Follower " .. tostring(id)),
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

    local width, height = 220, 40
    local spacing = 10
    local startY = -40

    for i, fol in ipairs(self.followers) do
        local banner = CreateFrame("Button", "QuickFollower_Banner" .. i, self.frame, "BackdropTemplate")
        banner:SetSize(width, height)
        banner:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 20, startY - (i - 1) * (height + spacing))

        banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        banner.title:SetPoint("CENTER", banner, "CENTER", 0, 0)
        banner.title:SetText(fol.name)

        NS.BaseWindow.AttachBannerBehavior(banner, "patronDragon", fol.name, function()
            self:ShowCommandButtons(banner, fol)
        end)

        table.insert(self.buttons, banner)
    end
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
    local width, height = banner:GetWidth(), 24
    local spacing = 5
    for i, text in ipairs(commands) do
        local btn = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
        btn:SetSize(width, height)
        btn:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, - (i - 1) * (height + spacing))
        btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.title:SetPoint("CENTER", btn, "CENTER")
        btn.title:SetText(text)
        NS.BaseWindow.AttachBannerBehavior(btn, "patronDragon", text, function()
            self:HideCommandButtons()
        end)
        table.insert(self.commandButtons, btn)
    end
end

function NS.QuickFollowerWindow:HideCommandButtons()
    for _, btn in ipairs(self.commandButtons or {}) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(self.commandButtons)
end

function NS.QuickFollowerWindow:AdjustWindowSize()
    local height = 20 + (#self.followers * 50)
    self.frame:SetSize(260, height)
end

print("|cff00ff00[PatronSystem]|r QuickFollowerWindow загружен")

