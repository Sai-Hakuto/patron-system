--[[==========================================================================
  PATRON SYSTEM - CONFIG
  Файл конфигурации, содержащий основные настройки аддона: типы окон,
  цвета, данные о персонажах и доступные действия.
--============================================================================]]
local NS = PatronSystemNS

NS.Config = {
    -- Типы говорящих
    SpeakerType = {
        PATRON   = "patron",
        FOLLOWER = "follower",
    },

    -- Типы окон
    WindowType = {
        MAIN     = "main",
        PATRON   = "patron",
        FOLLOWER = "follower",
        BLESSING = "blessing",
        SHOP     = "shop",
        DEBUG    = "debug",
    },

    DEBUG_MODE = true,

    -- Настройки UI элементов
    UI = {
        mainWindow = { width = 500, height = 400, title = "Система Покровителей" },
        speakerWindow = { width = 550, height = 400, title = "Покровитель" },
        leftPanel  = { width = 200, height = 320 },
        rightPanel = { width = 320, height = 240 },
        dialogContainer = { width = 320, minHeight = 60, maxHeight = 140, textPadding = 20 },
        actionButtons = { width = 85, height = 24, spacingX = 5, spacingY = 29 },
        replyButtons = { width = 300, height = 24, spacing = 5, maxCount = 3 },
    },

    -- Цветовая палитра
    Colors = {
        dialogText       = {r=1,   g=0.82, b=0,    a=1},
        panelBackground = {r=0.1, g=0.1, b=0.1, a=0.8},
        windowBackground = {r=0,   g=0,    b=0,    a=1},
        dialogBackground = {r=0,   g=0,    b=0,    a=0.6},
        dialogBorder     = {r=0.7, g=0.7,  b=0.7,  a=0.8},
        itemLegendary = {r=0.9, g=0.5, b=0.9, a=1},
        speakerName = {r=0.9, g=0.7, b=1,   a=1},
        alignment   = {r=0.7, g=0.9, b=1,   a=1},
        success = {r=0,   g=1,   b=0,   a=1},
        error   = {r=1,   g=0,   b=0,   a=1},
        warning = {r=1,   g=1,   b=0,   a=1},
        info    = {r=0.5, g=0.5, b=1,   a=1},
        patronVoid   = {r=0.5, g=0.3, b=0.8, a=1},
        patronDragon = {r=0.8, g=0.6, b=0.2, a=1},
        patronEluna  = {r=0.9, g=0.9, b=0.9, a=1},
    },

    -- Списки доступных персонажей
    AvailableSpeakers = {
        patrons = {
          { id=1,  name="Пустота",            type="patron",   color="patronVoid"   },
          { id=2,  name="Повелитель Драконов", type="patron",   color="patronDragon" },
          { id=3,  name="Элуна",               type="patron",   color="patronEluna"  },
        },
        followers = {
          { id=101, name="Алайя",       type="follower", patronID=1, color="patronVoid"   },
          { id=102, name="Арле'Кино",   type="follower", patronID=2, color="patronDragon" },
          { id=103, name="Узан Дул",    type="follower", patronID=3, color="patronEluna"  },
        },
    },

    -- Списки доступных действий для каждого типа персонажа
    Actions = {
        patron = {
          { id="TALK",  text="Converse",  icon="Interface\\GossipFrame\\GossipGossipIcon" },
          { id="TRADE", text="Trade", icon="Interface\\GossipFrame\\VendorGossipIcon" },
          { id="PRAY",  text="Pray",  icon="Interface\\PaperDollInfoFrame\\UI-GearManager-Undo" },
          { id="FOLLOWER",  text="Follower",  icon="Interface\\GossipFrame\\BinderGossipIcon" },
        },
        follower = {
          { id="TALK",    text="Говорить",   icon="Interface\\GossipFrame\\GossipGossipIcon" },
          { id="EQUIP",   text="Экипировка", icon="Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest" },
          { id="TRAIN",   text="Обучение",   icon="Interface\\GossipFrame\\TrainerGossipIcon" },
          { id="DISMISS", text="Отпустить",  icon="Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
        },
    },
}

--- Возвращает настройки UI для указанной секции.
function NS.Config:GetUIConfig(section) return (self.UI and self.UI[section]) or {} end
--- Возвращает таблицу RGBA для указанного имени цвета.
function NS.Config:GetColor(colorName) return (self.Colors and self.Colors[colorName]) or {r=1,g=1,b=1,a=1} end
--- Применяет цвет к текстовому элементу.
function NS.Config:ApplyColorToText(fontString, colorName)
    local c = self:GetColor(colorName)
    if fontString and c then fontString:SetTextColor(c.r, c.g, c.b, c.a) end
end
--- Возвращает список говорящих указанного типа.
function NS.Config:GetSpeakersByType(speakerType)
    if speakerType == self.SpeakerType.PATRON   then return self.AvailableSpeakers.patrons
    elseif speakerType == self.SpeakerType.FOLLOWER then return self.AvailableSpeakers.followers
    else return {} end
end
--- Находит говорящего по ID и типу.
function NS.Config:GetSpeakerByID(speakerID, speakerType)
    for _, s in ipairs(self:GetSpeakersByType(speakerType)) do
        if s.id == speakerID then return s end
    end
    return nil
end
--- Возвращает список действий для указанного типа говорящего.
function NS.Config:GetActionsByType(speakerType)
    if speakerType == self.SpeakerType.PATRON   then return self.Actions.patron
    elseif speakerType == self.SpeakerType.FOLLOWER then return self.Actions.follower
    else return {} end
end

NS.Logger:Info("Config загружен")