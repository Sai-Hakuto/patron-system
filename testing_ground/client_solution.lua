-- BlessingUI.lua
print("|cffFFFF00[BlessingUI] Клиентский файл загружен.|r")
local AIO = AIO or require("AIO")

------------------------------------------------------------
-- РЕГИСТР ОБРАБОТЧИКОВ ОТ СЕРВЕРА → В КЛИЕНТ (логи и уведомления)
------------------------------------------------------------
local BlessingsClient = AIO.AddHandlers("blessings", {})

-- Простой приемник сообщений/логов с сервера.
-- level: "INFO" | "WARN" | "ERROR"
function BlessingsClient.ClientLog(level, msg)
    local prefix = "|cff33ff99[Blessings/Srv]|r "
    level = tostring(level or "INFO")
    msg   = tostring(msg or "")
    if level == "ERROR" then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "|cffff3333[ERROR]|r " .. msg)
        UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
    elseif level == "WARN" then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "|cffffcc00[WARN]|r " .. msg)
        UIErrorsFrame:AddMessage(msg, 1.0, 0.6, 0.0, 1.0)
    else
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
    end
end

-- Короткий тост — просто алиас на ClientLog(INFO)
function BlessingsClient.Toast(msg)
    BlessingsClient.ClientLog("INFO", msg)
end

------------------------------------------------------------
-- КОНФИГ БЛЕССОВ (ID должны совпадать с сервером)
------------------------------------------------------------
-- type: "buff" (на себя), "single" (по цели), "aoe"
local BlessingsConfig = {
    { id = 1101,   name = "Благословение Силы",      icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",   type = "buff"  },
    { id = 1102, name = "Благословение Стойкости", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",   type = "buff"  },
    { id = 1201,  name = "Благословение Атаки",     icon = "Interface\\Icons\\Ability_GhoulFrenzy",        type = "single"},
    { id = 2001,     name = "Ливень (тест AoE)",       icon = "Interface\\Icons\\Spell_Frost_IceStorm",       type = "aoe"   },
}

------------------------------------------------------------
-- UI: главный фрейм и кнопка-переключатель
------------------------------------------------------------
local blessingMainFrame = CreateFrame("Frame", "BlessingUIMainFrame", UIParent)
local mainFrameWidth, mainFrameHeight = 260, 120
blessingMainFrame:SetSize(mainFrameWidth, mainFrameHeight)
blessingMainFrame:SetPoint("CENTER")
blessingMainFrame:SetMovable(true)
blessingMainFrame:EnableMouse(true)
blessingMainFrame:RegisterForDrag("LeftButton")
blessingMainFrame:SetScript("OnDragStart", blessingMainFrame.StartMoving)
blessingMainFrame:SetScript("OnDragStop", blessingMainFrame.StopMovingOrSizing)
blessingMainFrame:Hide()

local bg = blessingMainFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(true)
bg:SetColorTexture(0.08, 0.08, 0.1, 0.85)

local title = blessingMainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -10)
title:SetText("Благословения")

-- Портрет игрока
local playerPortrait = blessingMainFrame:CreateTexture("BlessingUIPortraitTexture", "ARTWORK")
playerPortrait:SetSize(36, 36)
playerPortrait:SetPoint("TOPLEFT", 10, -42)

local owner = blessingMainFrame  -- твой главный фрейм панели

local function ApplyOverrides()
  if InCombatLockdown() then
    print("|cffff5555[Patron] Нельзя менять бинды в бою|r")
    return
  end
  ClearOverrideBindings(owner)
  SetOverrideBindingClick(owner, true, "SHIFT-1", "BlessingButton1", "LeftButton")
  SetOverrideBindingClick(owner, true, "SHIFT-2", "BlessingButton2", "LeftButton")
  SetOverrideBindingClick(owner, true, "SHIFT-3", "BlessingButton3", "LeftButton")
  SetOverrideBindingClick(owner, true, "SHIFT-4", "BlessingButton4", "LeftButton")
end

local function ClearOverrides()
  ClearOverrideBindings(owner)
end

-- включаем/выключаем при показе/скрытии панели
blessingMainFrame:SetScript("OnShow", ApplyOverrides)
blessingMainFrame:SetScript("OnHide", ClearOverrides)

-- если окно открыто и бой закончился — повторно навесим бинды
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")
evt:SetScript("OnEvent", function()
  if blessingMainFrame:IsShown() then ApplyOverrides() end
end)

local function UpdatePlayerPortrait()
    if playerPortrait then
        -- Встроенный API: кладем портрет игрока в нашу текстуру
        SetPortraitTexture(playerPortrait, "player")
    end
end

-- Кнопка-переключатель панели
local toggleButton = CreateFrame("Button", "BlessingToggleButton", UIParent, "UIPanelButtonTemplate")
toggleButton:SetSize(40, 40)
toggleButton:SetPoint("TOP", UIParent, "TOP", 0, -50)
toggleButton:RegisterForDrag("LeftButton")
toggleButton:SetMovable(true)
toggleButton:EnableMouse(true)
toggleButton:SetScript("OnDragStart", toggleButton.StartMoving)
toggleButton:SetScript("OnDragStop", toggleButton.StopMovingOrSizing)
toggleButton:SetNormalTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
toggleButton:SetPushedTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
toggleButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
toggleButton:GetHighlightTexture():SetBlendMode("ADD")
toggleButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Панель Благословений")
    GameTooltip:Show()
end)
toggleButton:SetScript("OnLeave", GameTooltip_Hide)
toggleButton:SetScript("OnClick", function()
    local shown = blessingMainFrame:IsShown()
    print("|cff33FF33[BlessingUI] Click toggle → " .. (shown and "Hide" or "Show") .. "|r")
    if shown then blessingMainFrame:Hide() else blessingMainFrame:Show() end
end)

------------------------------------------------------------
-- Кнопки благословений
------------------------------------------------------------
local function PopulateBlessingPanel()
    print("[BlessingUI] PopulateBlessingPanel()")
    local buttonSize, padding = 36, 10
    local startX = 10 + 36 + 10   -- слева + ширина портрета + зазор
    local startY = -42

    for i, cfg in ipairs(BlessingsConfig) do
        local btn = CreateFrame("Button", "BlessingButton"..i, blessingMainFrame)
        btn:SetSize(buttonSize, buttonSize)
        btn:SetPoint("TOPLEFT", startX + (i - 1) * (buttonSize + padding), startY)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")

        btn:SetNormalTexture(cfg.icon)
        btn:SetPushedTexture(cfg.icon)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        btn:GetHighlightTexture():SetBlendMode("ADD")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(cfg.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)

        btn:SetScript("OnClick", function()
            -- Клиентский лог нажатия:
            print(("|cff00ff00[BlessingUI] Click: %s (%s)|r"):format(cfg.id, cfg.type))

            -- Вызов серверного метода. Можно передать доп. опции, например bp0/bp1/bp2.
            if AIO and AIO.Handle then
                AIO.Handle("blessings", "RequestBlessing", {
                    blessingID = cfg.id,
                    -- пример передаваемых модификаторов (если нужно):
                    -- bp0 = 0, bp1 = 0, bp2 = 0,
                })
            else
                print("|cffff3333[BlessingUI] AIO.Handle недоступен!|r")
            end
        end)
    end
end

------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ ПО ЛОГИНУ
------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        UpdatePlayerPortrait()
        PopulateBlessingPanel()
        print("|cffadd8e6[BlessingUI] Инициализация завершена.|r")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
