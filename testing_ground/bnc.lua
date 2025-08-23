print("|cffFFFF00[BlessingUI] 1. Файл загружен.|r")
local AIO = AIO or require("AIO")

-- Custom opcode for spell requests
local SPELL_REQ_OPCODE = 0x35F0

-- Serialize configuration matching server expectations
local function serializeConfig(pkt, cfg)
    cfg = cfg or {}
    pkt:WriteUByte(cfg.triggered and 1 or 0)
    pkt:WriteInt32(cfg.bp0 or 0)
    pkt:WriteInt32(cfg.bp1 or 0)
    pkt:WriteInt32(cfg.bp2 or 0)
    pkt:WriteULong(cfg.castItem or 0)
    pkt:WriteGUID(cfg.originalCaster or 0)
    pkt:WriteUInt32(cfg.mainSpell or 0)
    pkt:WriteFloat(cfg.radius or 0)
    pkt:WriteUInt32(cfg.durationMs or 0)
    pkt:WriteUInt32(cfg.tickMs or 0)
end

-- Build and send spell packet
local function sendSpell(reqType, visualSpellId, targetGUID, cfg)
    local pkt = CreatePacket(SPELL_REQ_OPCODE)
    pkt:WriteUByte(reqType or 0)
    pkt:WriteULong(visualSpellId or 0)
    pkt:WriteGUID(targetGUID or 0)
    serializeConfig(pkt, cfg)
    SendPacket(pkt)
end

-- Public wrappers
function CastBuff(spellId, guid)
    sendSpell(0, spellId, guid, nil)
end

function CastSingle(spellId, guid, cfg)
    sendSpell(1, spellId, guid, cfg)
end

function CastAOE(aoeSpellId, guid, cfg)
    sendSpell(2, aoeSpellId, guid, cfg)
end

-- 1. Конфигурация наших благословений
-- Я добавил примерные spell_id, которые теоретически могут дать нужный эффект
-- В РЕАЛЬНОЙ СИТУАЦИИ НУЖНО ЗАМЕНИТЬ НА ПРАВИЛЬНЫЕ SPELL ID ИЗ ВАШЕЙ БД СЕРВЕРА!
local BlessingsConfig = {
    { id = "blessing_power",   name = "Благословение Силы",      icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",   spell_to_cast_id = 132959 },
    { id = "blessing_stamina", name = "Благословение Стойкости", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",   spell_to_cast_id = 48743 },
    { id = "blessing_attack",  name = "Благословение Атаки",     icon = "Interface\\Icons\\Ability_GhoulFrenzy",        spell_to_cast_id = 133 },
    { id = "blessing_aoe",     name = "Ливень (тест AoE)",       icon = "Interface\\Icons\\Spell_Frost_IceStorm",       spell_to_cast_id = 190356 },
}
print("[BlessingUI] 2. Конфигурация создана.")


----------------------------------------------------
-- ГЛАВНЫЙ ФРЕЙМ АДДОНА (аналог 'frame' из Welcome Addon)
----------------------------------------------------
local blessingMainFrame = CreateFrame("Frame", "BlessingUIMainFrame", UIParent)
-- Задаем размеры главного фрейма. Вы можете настроить их здесь.
local mainFrameWidth = 220
local mainFrameHeight = 110
blessingMainFrame:SetSize(mainFrameWidth, mainFrameHeight)
blessingMainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) -- Размещаем по центру экрана
blessingMainFrame:SetMovable(true)
blessingMainFrame:EnableMouse(true)
blessingMainFrame:RegisterForDrag("LeftButton")
blessingMainFrame:SetScript("OnDragStart", blessingMainFrame.StartMoving)
blessingMainFrame:SetScript("OnDragStop", blessingMainFrame.StopMovingOrSizing)
blessingMainFrame:Hide() -- Изначально скрываем фрейм

print("[BlessingUI] 3. Главный фрейм 'blessingMainFrame' создан.")

-- Добавляем фоновую текстуру для главного фрейма (можно использовать кастомную или простую)
local bgTex = blessingMainFrame:CreateTexture(nil, "BACKGROUND")
bgTex:SetAllPoints(true)
bgTex:SetColorTexture(0.1, 0.1, 0.1, 0.8) -- Темный полупрозрачный фон


----------------------------------------------------
-- СОДЕРЖИМОЕ ПАНЕЛИ БЛАГОСЛОВЕНИЙ (внутри главного фрейма)
----------------------------------------------------

-- Заголовок панели (необязательно, но полезно)
local title = blessingMainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", blessingMainFrame, "TOP", 0, -10)
title:SetText("Благословения")
title:SetTextColor(1, 0.82, 0) -- Золотистый цвет

-- Texture Frame для иконки игрока
local playerPortraitTexture = blessingMainFrame:CreateTexture("BlessingUIPortraitTexture", "ARTWORK")
playerPortraitTexture:SetSize(30, 30)
-- Позиционируем относительно blessingMainFrame
playerPortraitTexture:SetPoint("TOPLEFT", blessingMainFrame, "TOPLEFT", 10, -50)
-- Временная заливка для отладки
playerPortraitTexture:SetColorTexture(1, 0, 0, 0.5)
print("[BlessingUI] PLAYER PORTRAIT TEXTURE создан.")

-- Функция для динамического создания кнопок внутри blessingMainFrame (теперь это родитель)
local function PopulateBlessingPanel()
    print("[BlessingUI] 5. Начинаем заполнение панели (PopulateBlessingPanel)...")
    local buttonSize = 36
    local padding = 10
    -- Начальная позиция для кнопок, учитывая портрет игрока и заголовок
    local startX = padding + 30 + padding -- Padding + размер портрета + padding между портретом и кнопками
    local startY = -50 -- Y-позиция (под заголовком)

    for i, blessingInfo in ipairs(BlessingsConfig) do
        local btn = CreateFrame("Button", "BlessingButton" .. i, blessingMainFrame) -- Родитель теперь blessingMainFrame
        btn:SetSize(buttonSize, buttonSize)
        btn:SetPoint("TOPLEFT", blessingMainFrame, "TOPLEFT", startX, startY)
        
        -- Улучшим внешний вид кнопок (опционально, можно использовать UIPanelButtonTemplate)
        btn:SetNormalTexture(blessingInfo.icon) -- Иконка как нормальная текстура
        btn:SetPushedTexture(blessingInfo.icon)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        btn:GetHighlightTexture():SetBlendMode("ADD")

        local tex = btn:CreateTexture(nil, "ARTWORK") -- Дополнительная текстура для самой иконки, если нужно
        tex:SetAllPoints()
        tex:SetTexture(blessingInfo.icon) -- Задаем иконку благословения
        
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(blessingInfo.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- === ИЗМЕНЯЕМ ТОЛЬКО OnClick ===
        btn:SetScript("OnClick", function()
            local target = UnitGUID("target")
            if blessingInfo.id == "blessing_attack" then
                CastSingle(blessingInfo.spell_to_cast_id, target)
            elseif blessingInfo.id == "blessing_aoe" then
                CastAOE(blessingInfo.spell_to_cast_id, target, {mainSpell = 116, radius = 8.0, durationMs = 4000, tickMs = 500})
            else
                CastBuff(blessingInfo.spell_to_cast_id, UnitGUID("player"))
            end
        end)
        
        startX = startX + buttonSize + padding
    end
    print("[BlessingUI] 6. Заполнение панели завершено.")
end

----------------------------------------------------
-- КНОПКА-ПЕРЕКЛЮЧАТЕЛЬ ДЛЯ ВСЕГО АДДОНА
----------------------------------------------------
local toggleButton = CreateFrame("Button", "BlessingToggleButton", UIParent, "UIPanelButtonTemplate")
toggleButton:SetSize(40, 40) -- Размер кнопки, можно настроить
toggleButton:SetPoint("TOP", UIParent, "TOP", 0, -50) -- Начальная позиция, можно перетаскивать
toggleButton:RegisterForDrag("LeftButton")
toggleButton:SetMovable(true)
toggleButton:EnableMouse(true)
toggleButton:SetScript("OnDragStart", toggleButton.StartMoving)
toggleButton:SetScript("OnDragStop", toggleButton.StopMovingOrSizing)

-- Иконка для кнопки переключателя (можно использовать иконку благословений)
toggleButton:SetNormalTexture("Interface\\Icons\\Spell_Holy_WordFortitude") -- Пример: иконка стойкости
toggleButton:SetPushedTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
toggleButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
toggleButton:GetHighlightTexture():SetBlendMode("ADD")

-- Тултип для кнопки
toggleButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Панель Благословений")
    GameTooltip:Show()
end)
toggleButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)



-- Логика переключения видимости главного фрейма
toggleButton:SetScript("OnClick", function()
    print("|cff33FF33[BlessingUI] КЛИК! Показываем/скрываем панель благословений.|r")
    if blessingMainFrame:IsShown() then
		AIO.Handle("blessings", "RemoveBlessing", { blessingID = "blessing_power" })
        blessingMainFrame:Hide()
    else
        blessingMainFrame:Show()
    end
end)
print("[BlessingUI] 7. Кнопка-переключатель видимости создана.")

----------------------------------------------------
-- ИНТЕГРАЦИЯ ИКОНКИ ИГРОКА И СОБЫТИЙ
----------------------------------------------------
local function UpdatePlayerPortrait()
    local portraitPath = UnitPortait("player")
    if playerPortraitTexture then
        if portraitPath and portraitPath ~= "" then
            playerPortraitTexture:SetTexture(portraitPath)
            playerPortraitTexture:SetColorTexture(1,1,1) -- Сброс цвета, если текстура загружена
        else
            playerPortraitTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            playerPortraitTexture:SetColorTexture(0, 0, 1, 0.5) -- Синий, если портрет не нашелся
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        PopulateBlessingPanel() -- Заполняем панель при логине, когда все фреймы готовы
        UpdatePlayerPortrait()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

print("|cffadd8e6[BlessingUI] Инициализация завершена.|r")