--[[==========================================================================
  PATRON SYSTEM - BASE WINDOW (v2)
  Универсальный каркас и фабрика UI для всех окон системы
===========================================================================]]

local NS = PatronSystemNS

NS.BaseWindow = {
  prototype = {}
}
NS.BaseWindow.prototype.__index = NS.BaseWindow.prototype

-- Общие настройки визуальных состояний баннеров
NS.UIStyle = NS.UIStyle or {
  BASE_MULT   = 0.30,   -- затемнение фона в обычном состоянии
  HOVER_MULT  = 0.60,   -- осветление при наведении
  FLASH_ALPHA = 0.80,   -- альфа белой вспышки при клике
  FLASH_TIME  = 0.10,   -- длительность вспышки
}

-- Палитра для качества предметов (1..5)
NS.QualityColors = NS.QualityColors or {
  [1] = {1.00, 1.00, 1.00}, -- common (white)
  [2] = {0.12, 1.00, 0.00}, -- uncommon (green)
  [3] = {0.00, 0.44, 0.87}, -- rare (blue)
  [4] = {0.64, 0.21, 0.93}, -- epic (purple)
  [5] = {1.00, 0.50, 0.00}, -- legendary (orange)
}

NS.CurrencyIcons = NS.CurrencyIcons or {
  Money = "Interface\\MoneyFrame\\UI-GoldIcon",
  Souls = "Interface\\MoneyFrame\\UI-GoldIcon",
  Suffering = "Interface\\MoneyFrame\\UI-GoldIcon",
  Draconic = "Interface\\MoneyFrame\\UI-GoldIcon",
}

--- Creates a new BaseWindow object.
function NS.BaseWindow:New(name, opts)
  local o = setmetatable({}, self.prototype)
  o.name        = name or "BaseWindow"
  o.windowType  = opts and opts.windowType or NS.Config.WindowType.DEBUG
  o.layout      = opts and opts.layout or {}
  o.hooks       = opts and opts.hooks or {}
  o.frame       = nil
  o.elements    = {}
  o.initialized = false
  o.currentData = nil        -- любые данные (speaker, follower, patron и т.п.)
  o.isLocked    = false      -- состояние блокировки перетаскивания
  o.state = {
    inDialogue = false,
    replyButtons = {},
    selectorButtons = {},
  }
  return o
end

--- Initializes the window by creating its frame and core elements.
function NS.BaseWindow.prototype:Initialize()
  if self.initialized then return end
  self:CreateFrame()
  self:CreateCore()
  if self.hooks.onInit then pcall(self.hooks.onInit, self) end
  self.initialized = true
end

--- Shows the window, initializing it if necessary.
function NS.BaseWindow.prototype:Show(payload)
  if not self.initialized then self:Initialize() end
  if self.hooks.onBeforeShow then pcall(self.hooks.onBeforeShow, self, payload) end

  if NS.UIManager and NS.UIManager.SetWindowLayer then
    NS.UIManager:SetWindowLayer(self.windowType, self)
  end

  self.frame:Show()
  if self.hooks.onAfterShow then pcall(self.hooks.onAfterShow, self, payload) end
end

--- Hides the window and ends any active dialogue.
function NS.BaseWindow.prototype:Hide()
  self.frame:Hide()
  if self.state.inDialogue and NS.DialogueEngine then
    NS.DialogueEngine:EndDialogue()
  end
  if self.hooks.onHide then pcall(self.hooks.onHide, self) end
end

--- Toggles the window's visibility.
function NS.BaseWindow.prototype:Toggle(payload)
  if self:IsShown() then self:Hide() else self:Show(payload) end
end

--- Checks if the window is currently visible.
function NS.BaseWindow.prototype:IsShown()
  return self.frame and self.frame:IsShown()
end

--- Returns the main frame of the window.
function NS.BaseWindow.prototype:GetFrame()
  return self.frame
end

--- Creates the main window frame and sets its properties.
function NS.BaseWindow.prototype:CreateFrame()
  local cfg = NS.Config:GetUIConfig("speakerWindow") or {}
  self.frame = CreateFrame("Frame", self.name.."Frame", UIParent, "BackdropTemplate")
  self.frame:SetSize(cfg.width or 550, cfg.height or 500)
  self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  self.frame:SetMovable(true); self.frame:EnableMouse(true)
  self.frame:RegisterForDrag("LeftButton")
  self.frame:SetScript("OnDragStart", self.frame.StartMoving)
  self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
  self.frame:SetFrameStrata("HIGH")
  self.frame:Hide()

  self.frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true, tileSize = 32, edgeSize = 16,
    insets   = { left=5, right=5, top=5, bottom=5 }
  })
  local bg = NS.Config:GetColor("windowBackground")
  self.frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
end

--- Creates core elements like the title and close button.
function NS.BaseWindow.prototype:CreateCore()
  -- Заголовок
  self.elements.title = self.frame:CreateFontString(self.name.."_Title", "OVERLAY", "GameFontNormalLarge")
  self.elements.title:SetPoint("TOP", self.frame, "TOP", 0, -10)
  NS.Config:ApplyColorToText(self.elements.title, "speakerName")

  -- Закрыть
  self.elements.closeButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
  self.elements.closeButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -5, -5)
  self.elements.closeButton:SetScript("OnClick", function() self:Hide() end)
end

--- Creates and returns the left and right main content panels.
function NS.BaseWindow.prototype:CreateLeftRightPanels()
  local lp = NS.Config:GetUIConfig("leftPanel") or {}
  local rp = NS.Config:GetUIConfig("rightPanel") or {}

  local left = CreateFrame("Frame", nil, self.frame)
  left:SetSize(lp.width or 200, lp.height or 320)
  left:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 15, -65)
  self.elements.leftPanel = left

  local right = CreateFrame("Frame", nil, self.frame)
  right:SetSize(rp.width or 320, rp.height or 240)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
  self.elements.rightPanel = right

  return left, right
end

--- Creates a portrait frame and texture.
function NS.BaseWindow.prototype:CreatePortrait(parent, opts)
  opts = opts or {}
  local w,h = opts.width or 160, opts.height or 200
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(w, h); frame:SetPoint("TOP", parent, "TOP", -18, -4)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}
  })
  frame:SetBackdropColor(0.1,0.1,0.1,0.8)
  frame:SetBackdropBorderColor(0.3,0.3,0.3,1)

  local tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

  return frame, tex
end

--- Creates a generic text element based on a configuration table.
function NS.BaseWindow.prototype:CreateText(parent, cfg)
  cfg = cfg or {}
  local fs = parent:CreateFontString(nil, "OVERLAY", cfg.template or "GameFontNormal")
  if cfg.width then fs:SetWidth(cfg.width) end
  if cfg.justify then fs:SetJustifyH(cfg.justify) end
  if cfg.colorKey and NS.Config then NS.Config:ApplyColorToText(fs, cfg.colorKey) end
  local p = cfg.point
  if p then fs:SetPoint(p[2], p[1], p[3], p[4] or 0, p[5] or 0) end
  if cfg.text then fs:SetText(cfg.text) end
  return fs
end

--- Creates the specific info text element for alignment/rank.
function NS.BaseWindow.prototype:CreateInfoText(parent)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f:SetWidth(180); f:SetJustifyH("LEFT")
  NS.Config:ApplyColorToText(f, "alignment")
  return f
end

--- Attaches a standard visual and interactive behavior to a banner-style button.
function NS.BaseWindow.AttachBannerBehavior(banner, colorKey, titleText, onClick)
  local C  = NS.Config:GetColor(colorKey)
  local S  = NS.UIStyle

  -- (1) гарантируем кликабельность
  if banner.EnableMouse then banner:EnableMouse(true) end
  if banner.RegisterForClicks then banner:RegisterForClicks("AnyUp") end

  local function setBase()
    banner:SetBackdropColor(C.r*S.BASE_MULT, C.g*S.BASE_MULT, C.b*S.BASE_MULT, 0.8)
    banner:SetBackdropBorderColor(C.r, C.g, C.b, 1)
    if banner.title       then banner.title:SetTextColor(C.r, C.g, C.b, 1) end
    if banner.description then banner.description:SetTextColor(0.8, 0.8, 0.8, 1) end
  end

  local function setHover()
    banner:SetBackdropColor(C.r*S.HOVER_MULT, C.g*S.HOVER_MULT, C.b*S.HOVER_MULT, 1.0)
    banner:SetBackdropBorderColor(1, 1, 1, 1)
    if banner.title       then banner.title:SetTextColor(1, 1, 1, 1) end
    if banner.description then banner.description:SetTextColor(1, 1, 1, 1) end
  end

  setBase()

  banner:SetScript("OnEnter", function()
    setHover()
    if NS.Logger then NS.Logger:UI("Наведение на банер: " .. tostring(titleText)) end
  end)

  banner:SetScript("OnLeave", function()
    setBase()
  end)

  banner:SetScript("OnClick", function()
    -- (2) сначала короткая «вспышка»
    banner:SetBackdropColor(1, 1, 1, S.FLASH_ALPHA)
    if banner.title       then banner.title:SetTextColor(0, 0, 0, 1) end
    if banner.description then banner.description:SetTextColor(0, 0, 0, 1) end

    if NS.Logger then NS.Logger:UI("Клик по банеру: " .. tostring(titleText)) end

    C_Timer.After(S.FLASH_TIME, function()
      setBase()
      -- (3) затем уже действие (открытие окна)
      if onClick then onClick() end
    end)
  end)
end


--- Creates a grid of action buttons.
function NS.BaseWindow.prototype:CreateActionButtons(parent, actions, grid)
  grid = grid or {cols=2, spacingX=8, spacingY=28, width=120, height=24}
  local anchor = grid.anchor or { frame = parent, point = "TOPLEFT", relPoint = "TOPLEFT", x = 0, y = 0 }
  local pitchY = grid.pitchY or grid.spacingY

  local created = {}
  for i, a in ipairs(actions or {}) do
    local row = math.floor((i-1)/grid.cols)
    local col = (i-1) % grid.cols
    local btn = CreateFrame("Button", self.name.."_Action"..i, parent, "UIPanelButtonTemplate")
    btn:SetSize(grid.width, grid.height)
    btn:SetPoint(
      anchor.point, anchor.frame, anchor.relPoint,
      anchor.x + col*(grid.width + grid.spacingX),
      anchor.y - row * pitchY
    )
    btn:SetText(a.text or a.id)
    btn:SetScript("OnClick", function() if a.onClick then a.onClick(a.id, btn) end end)
    table.insert(created, btn)
  end
  return created
end

--- Ensures the left panel is tall enough to fit the action buttons.
function NS.BaseWindow.prototype:EnsureLeftPanelHeightForActions(rows, grid)
  if not self.elements.leftPanel then return end
  local lp   = self.elements.leftPanel
  local pH   = (self.elements.portraitFrame and self.elements.portraitFrame:GetHeight()) or 0
  local infoH= (self.elements.infoText and self.elements.infoText:GetStringHeight()) or 0
  local topPad        = 0
  local infoGap       = 10   -- от портрета до infoText
  local actionsTopGap = 20   -- от infoText до первой строки кнопок

  local pitchY = grid.pitchY or grid.spacingY or 30
  local btnH   = grid.height or 24
  local actionsH = (rows > 0) and (btnH + (rows-1)*pitchY) or 0

  local need = topPad + pH + infoGap + infoH + actionsTopGap + actionsH + 10
  if lp:GetHeight() < need then
    lp:SetHeight(need)
  end
end

--- Creates the main dialogue text container.
function NS.BaseWindow.prototype:CreateDialogueContainer(parent, cfg)
  cfg = cfg or NS.Config:GetUIConfig("dialogContainer") or {}
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  c:SetSize(cfg.width or 320, cfg.minHeight or 90)

  -- NEW: respect custom anchor if provided
  local p = cfg.point
  if type(p) == "table" then
    local rel, point, relPoint, x, y = p[1], p[2] or "TOPLEFT", p[3] or "TOPLEFT", p[4] or 0, p[5] or -15
    c:SetPoint(point, rel or parent, relPoint, x, y)
  else
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -15)
  end

  c:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}
  })
  local bg = NS.Config:GetColor("dialogBackground")
  local br = NS.Config:GetColor("dialogBorder")
  c:SetBackdropColor(bg.r,bg.g,bg.b,bg.a)
  c:SetBackdropBorderColor(br.r,br.g,br.b,br.a)

  -- text
  local t = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -10)
  t:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 10)
  t:SetJustifyH("LEFT")
  t:SetWordWrap(true)
  self.elements.dialogText = t
  NS.Config:ApplyColorToText(self.elements.dialogText, "dialogText")

  self.elements.dialogContainer = c
  return c, t
end

--- Creates the container and placeholder buttons for dialogue replies.
function NS.BaseWindow.prototype:CreateReplyContainer(parent, cfg)
  cfg = cfg or NS.Config:GetUIConfig("replyButtons") or {}
  local rc = CreateFrame("Frame", nil, parent)
  rc:SetSize(cfg.width or 320, 90)
  rc:SetPoint("TOPLEFT", self.elements.dialogContainer, "BOTTOMLEFT", 0, -15)
  self.elements.replyContainer = rc

  -- Заготовим N кнопок, но прятать по умолчанию
  self.state.replyButtons = self.state.replyButtons or {}
  local maxCount = cfg.maxCount or 4
  for i=1, maxCount do
    local b = CreateFrame("Button", self.name.."_Reply"..i, rc, "UIPanelButtonTemplate")
    b:SetSize(cfg.width or 320, cfg.height or 24)
    b:SetPoint("TOPLEFT", rc, "TOPLEFT", 0, -5 - (i-1)*((cfg.height or 24) + (cfg.spacing or 4)))
    b:SetText("["..i.."] Ответ "..i)
    b:Hide()
    self.state.replyButtons[i] = b
  end

  -- Exit
  local exit = CreateFrame("Button", self.name.."_Exit", rc, "UIPanelButtonTemplate")
  exit:SetSize(cfg.width or 320, cfg.height or 24)
  exit:SetPoint("TOPLEFT", rc, "TOPLEFT", 0, -5 - (maxCount) * ((cfg.height or 24) + (cfg.spacing or 4)))
  exit:SetText("Выход из диалога")
  exit:Hide()
  exit:SetScript("OnClick", function()
    if NS.DialogueEngine then NS.DialogueEngine:EndDialogue() end
  end)
  self.elements.exitDialogueButton = exit

  return rc
end

--- Sets the text of the dialogue box and adjusts its size.
function NS.BaseWindow.prototype:SetDialogText(text)
  if not (self.elements and self.elements.dialogText) then
    local right = self.elements and self.elements.rightPanel
    if not right then
      local _, r = self:CreateLeftRightPanels()
      right = r
    end

    local cfg = NS.Config:GetUIConfig("dialogContainer") or {}
    -- NEW: if there is a description, anchor under it
    if self.elements and self.elements.descText then
      cfg = {
        width = cfg.width, minHeight = cfg.minHeight, maxHeight = cfg.maxHeight,
        point = { self.elements.descText, "BOTTOMLEFT", "BOTTOMLEFT", 0, -15 }
      }
    end

    local c, t = self:CreateDialogueContainer(right, cfg)
    self.elements.dialogContainer = c
    self.elements.dialogText = t
    if not self.elements.replyContainer then
      self:CreateReplyContainer(self.frame, NS.Config:GetUIConfig("replyButtons"))
    end
  end

  self.elements.dialogText:SetText(text or "")
  self:AdjustDialogContainerSize(text or "")
end

--- Hides all reply buttons and the exit dialogue button.
function NS.BaseWindow.prototype:HideAllReplyButtons()
  for _,b in ipairs(self.state.replyButtons) do if b then b:Hide() end end
  if self.elements.exitDialogueButton then self.elements.exitDialogueButton:Hide() end
end

--- Configures and shows buttons for player answers.
function NS.BaseWindow.prototype:ShowAnswerButtons(answers)
  self:HideAllReplyButtons()
  local count = math.min(#answers, #self.state.replyButtons)
  for i=1, count do
    local a = answers[i]
    local b = self.state.replyButtons[i]
    b:SetText("["..i.."] "..(a.text or ("Ответ "..i)))
    b.answerID = a.id
    b:SetScript("OnClick", function()
      if NS.DialogueEngine then NS.DialogueEngine:ContinueDialogue(a.id) end
    end)
    b:Show()
  end
  self:PositionExitBelowReplies(count)
end

--- Configures and shows a single "Continue" button.
function NS.BaseWindow.prototype:ShowContinueButton(dialogueID)
  self:HideAllReplyButtons()
  if #self.state.replyButtons > 0 then
    local b = self.state.replyButtons[1]
    b:SetText("[1] Продолжить...")
    b.answerID = dialogueID
    b:SetScript("OnClick", function()
      if NS.DialogueEngine then NS.DialogueEngine:AdvanceDialogue() end
    end)
    b:Show()
    self:PositionExitBelowReplies(1)
  end
end

--- Repositions the "Exit Dialogue" button below the visible reply buttons.
function NS.BaseWindow.prototype:PositionExitBelowReplies(visibleReplies)
  local cfg = NS.Config:GetUIConfig("replyButtons") or {}
  local y = -5 - (visibleReplies) * ((cfg.height or 24) + (cfg.spacing or 4))
  self.elements.exitDialogueButton:ClearAllPoints()
  self.elements.exitDialogueButton:SetPoint("TOPLEFT", self.elements.replyContainer, "TOPLEFT", 0, y)
  self.elements.exitDialogueButton:Show()
end

--- Adjusts the dialogue container's height based on the text content.
function NS.BaseWindow.prototype:AdjustDialogContainerSize(text)
  if not self.elements.dialogContainer or not text or text == "" then return end
  local cfg = NS.Config:GetUIConfig("dialogContainer") or {}
  local containerWidth = self.elements.dialogContainer:GetWidth()
  local padding = 20
  local test = self.elements.dialogContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  test:SetWidth(containerWidth - padding)
  test:SetWordWrap(true)
  test:SetJustifyH("LEFT")
  test:SetText(text)
  local h = test:GetStringHeight()
  test:Hide()

  local newH = math.max(cfg.minHeight or 90, math.min(cfg.maxHeight or 240, h + padding))
  self.elements.dialogContainer:SetHeight(newH)

  -- Перепозиционируем контейнер ответов
  if self.elements.replyContainer then
    self.elements.replyContainer:ClearAllPoints()
    self.elements.replyContainer:SetPoint("TOPLEFT", self.elements.dialogContainer, "BOTTOMLEFT", 0, -15)
  end
  return newH
end

--- Re-anchors the dialogue container to be positioned below the description text.
function NS.BaseWindow.prototype:ReanchorDialogUnderDescription(descHeight)
  if not (self.elements.rightPanel and self.elements.dialogContainer) then return end
  local between = 15
  local h = descHeight
  if not h then
    if self.elements.descText then
      local pad = 10
      self.elements.descText:SetWidth(self.elements.rightPanel:GetWidth() - pad*2) -- было: GetWidth()
      h = self.elements.descText:GetStringHeight() or 0
    else
      h = 0
    end
  end
  self.elements.dialogContainer:ClearAllPoints()
  self.elements.dialogContainer:SetPoint("TOPLEFT", self.elements.rightPanel, "TOPLEFT", 0, -(h + between))
end

--- Automatically resizes the entire window to fit its dynamic content.
function NS.BaseWindow.prototype:AutoSizeWindow(dialogText, visibleReplies, withExit)
  local baseCfg = NS.Config:GetUIConfig("speakerWindow") or {}
  local baseH   = baseCfg.height or 500
  local between = 15

  -- 1) Диалог
  local dH = self:AdjustDialogContainerSize(dialogText or "")

  -- 2) Ответы
  local replies = visibleReplies or 0
  local rCfg = NS.Config:GetUIConfig("replyButtons") or {}
  local repliesBlock = (replies * ((rCfg.height or 24) + (rCfg.spacing or 4))) + (withExit and ((rCfg.height or 24) + 10) or 0)

  -- 3) Описание
  local descH = 0
  if self.elements.descText then
    descH = self.elements.descText:GetStringHeight() or 0
  end
  self:ReanchorDialogUnderDescription(descH)

  -- 4) Высота правой панели = описание + отступ + диалог + отступ + ответы
  local rightMinH = (NS.Config:GetUIConfig("rightPanel") or {}).height or 240
  local rightH = math.max(descH + between + (dH or 0) + between + repliesBlock, rightMinH)
  if self.elements.rightPanel then self.elements.rightPanel:SetHeight(rightH) end

  -- 5) Высота левой панели уже подправляется EnsureLeftPanelHeightForActions(...)
  local leftH = (self.elements.leftPanel and self.elements.leftPanel:GetHeight()) or 320

  -- 6) Итоговая высота окна
  local contentH = math.max(leftH, rightH)
  self.frame:SetHeight(contentH + 65 + 20) -- top + bottom padding

  if self.hooks.onResize then pcall(self.hooks.onResize, self, self.frame:GetWidth(), self.frame:GetHeight()) end
end

--- Gets the number of currently visible reply buttons.
function NS.BaseWindow.prototype:GetVisibleReplyCount()
  local n = 0
  for _, b in ipairs(self.state.replyButtons or {}) do
    if b and b:IsShown() then n = n + 1 end
  end
  return n
end

--- Shows a banner overlay, typically for "no data" or loading states.
function NS.BaseWindow.prototype:ShowBanner(text)
  if not self.elements.banner then
    local f = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    f:SetAllPoints(self.frame)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    local tx = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tx:SetPoint("CENTER", f, "CENTER", 0, 0)
    tx:SetJustifyH("CENTER"); tx:SetWordWrap(true); tx:SetWidth(self.frame:GetWidth() - 60)
    NS.Config:ApplyColorToText(tx, "warning")
    self.elements.banner = f
    self.elements.bannerText = tx
  end
  self.elements.bannerText:SetText(text or "Контент пока недоступен.")
  self:SetContentVisible(false)
  self.elements.banner:Show()
end

--- Hides the banner overlay.
function NS.BaseWindow.prototype:HideBanner()
  if self.elements.banner then self.elements.banner:Hide() end
  self:SetContentVisible(true)
end

--- Sets the visibility of the main content panels.
function NS.BaseWindow.prototype:SetContentVisible(visible)
  for _,k in ipairs({"leftPanel","rightPanel","followerSelectorPanel","patronSelectorPanel"}) do
    if self.elements[k] then self.elements[k]:SetShown(visible) end
  end
end

--- Формат валюты в строку с иконкой.
function NS.BaseWindow.prototype:FormatCurrency(amount, currencyKey, iconPath, iconSize)
  amount     = tonumber(amount) or 0
  currencyKey = currencyKey or "Money"
  local icon = iconPath or NS.CurrencyIcons[currencyKey]
  local sz   = iconSize or 14
  if icon then
    return ("|T%s:%d:%d:0:0|t %s"):format(icon, sz, sz, tostring(amount))
  else
    return ("%s %s"):format(currencyKey, tostring(amount))
  end
end

--- Помощник: бордер по качеству
function NS.BaseWindow.prototype:SetQualityBorder(frame, quality)
  local c = NS.QualityColors[quality or 1] or NS.QualityColors[1]
  if frame.SetBackdropBorderColor then
    frame:SetBackdropBorderColor(c[0] or c[1], c[2] or c[1], c[3] or c[1], 1)
  elseif frame.SetVertexColor then
    frame:SetVertexColor(c[1], c[2], c[3], 1)
  end
end

--- Универсальный тултип (OnEnter/OnLeave). lines: { {text, r,g,b, wrap}, ... }
function NS.BaseWindow.prototype:AttachTooltip(frame, linesBuilder)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 6, 0)
    local lines = type(linesBuilder) == "function" and linesBuilder(self) or linesBuilder
    if lines and #lines > 0 then
      local i = 1
      for _, ln in ipairs(lines) do
        local t, r,g,b, wrap = ln[1] or "", ln[2] or 1, ln[3] or 1, ln[4] or 1, ln[5]
        if i == 1 then GameTooltip:SetText(t, r,g,b, wrap) else GameTooltip:AddLine(t, r,g,b, wrap) end
        i = i + 1
      end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Creates a horizontal bar of slot frames for items or selections.
--- Each slot is a clickable frame with "+" text by default.
--- opts: { size=40, gap=6, plusText="+", colorKey, onClick(index, frame), hoverColor, activeColor }
function NS.BaseWindow.prototype:CreateSlotBar(parent, slotCount, opts, rows, cols)
  opts = opts or {}
  slotCount = slotCount or 6
  rows = rows or 1
  cols = cols or slotCount
  local maxSlots = math.min(slotCount, rows * cols)

  local size    = opts.size or 40
  local gap     = opts.gap or 6
  local plusTxt = opts.plusText or "+"

  local C = NS.Config:GetColor(opts.colorKey or "info")
  local S = NS.UIStyle

  local baseColor   = opts.baseColor   or { C.r * S.BASE_MULT,  C.g * S.BASE_MULT,  C.b * S.BASE_MULT,  0.8 }
  local hoverColor  = opts.hoverColor  or { C.r * S.HOVER_MULT, C.g * S.HOVER_MULT, C.b * S.HOVER_MULT, 1.0 }
  local activeColor = opts.activeColor or { C.r, C.g, C.b, 1.0 }

  local bar = CreateFrame("Frame", self.name.."_SlotBar", parent)
  bar:SetSize(cols * size + (cols-1) * gap, rows * size + (rows-1) * gap)

  local slots = {}
  local positions = {}

  local function applyColor(slot, col, tcol)
    slot:SetBackdropColor(col[1], col[2], col[3], col[4])
    slot:SetBackdropBorderColor(C.r, C.g, C.b, 1)
    local tc = tcol or {C.r, C.g, C.b}
    if slot.__fs then slot.__fs:SetTextColor(tc[1], tc[2], tc[3], 1) end
  end

  for i=1, maxSlots do
    local s = CreateFrame("Button", self.name.."_Slot"..i, bar, "BackdropTemplate")
    s:SetSize(size, size)

    local colIdx = (i-1) % cols
    local rowIdx = math.floor((i-1) / cols)
    local x = colIdx * (size + gap)
    local y = -rowIdx * (size + gap)
    s:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)

    s:SetBackdrop({
      bgFile="Interface\\Buttons\\WHITE8x8",
      edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
      tile=false, edgeSize=12,
      insets={left=3,right=3,top=3,bottom=3},
    })

    local fs = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    fs:SetPoint("CENTER")
    fs:SetText(plusTxt)
    s.__fs = fs

    applyColor(s, baseColor)

    s:EnableMouse(true)
    s.__active = false

    s:SetScript("OnEnter", function()
      applyColor(s, hoverColor, {1,1,1})
      if opts.onEnter then opts.onEnter(i, s) end
    end)
    s:SetScript("OnLeave", function()
      if s.__active then
        applyColor(s, activeColor, {1,1,1})
      else
        applyColor(s, baseColor)
      end
      if opts.onLeave then opts.onLeave(i, s) end
    end)
    s:SetScript("OnClick", function()
      if opts.toggleActive ~= false then
        s.__active = not s.__active
        applyColor(s, s.__active and activeColor or baseColor, s.__active and {1,1,1} or {C.r, C.g, C.b})
      end
      if opts.onClick then opts.onClick(i, s) end
    end)
    function s:SetActive(state)
      self.__active = state and true or false
      applyColor(self, self.__active and activeColor or baseColor, self.__active and {1,1,1} or {C.r, C.g, C.b})
    end

    slots[i] = s
    positions[i] = { x = x, y = y }
  end

  return { frame = bar, slots = slots, count = maxSlots, positions = positions }
end

-- ------------------------------- ВКЛАДКИ ----------------------------------

--- Горизонтальные вкладки (как кнопки). tabs = { {id="WEAPON", title="Оружие"}, ... }
--- opts: { onChange = function(tabId) end, height=24, spacing=6 }
function NS.BaseWindow.prototype:CreateTabsBar(parent, tabs, opts)
  opts = opts or {}
  local height  = opts.height or 24
  local spacing = opts.spacing or 6

  local bar = CreateFrame("Frame", self.name.."_Tabs", parent)
  bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -36)
  bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -36)
  bar:SetHeight(height)

  local buttons, activeId = {}, nil
  local function setActive(id)
    activeId = id
    for _, b in ipairs(buttons) do
      local isActive = (b.__id == id)
      -- Унифицированные цвета как в PatronWindow/FollowerWindow
      if b.__fs then
        if isActive then
          b.__fs:SetTextColor(1, 1, 1)          -- выбранный = белый
        else
          b.__fs:SetTextColor(0.82, 0.82, 0.82) -- обычный спокойный цвет
        end
      end
      -- визуально "прижимаем" кнопку выбранного элемента
      if isActive then b:LockHighlight() else b:UnlockHighlight() end
      -- держим исходный текст
      if b.__text then b:SetText(b.__text) end
    end
  end

  local totalW = bar:GetWidth() or (self.frame:GetWidth() - 20)
  local btnW = math.floor((totalW - spacing*(#tabs-1)) / #tabs)

  for i, t in ipairs(tabs) do
    -- Используем "UIPanelButtonTemplate" — он одинаков везде
    local btn = CreateFrame("Button", self.name.."_Tab"..i, bar, "UIPanelButtonTemplate")
    btn:SetSize(btnW, height)
    if i == 1 then
      btn:SetPoint("LEFT", bar, "LEFT", 0, 0)
    else
      btn:SetPoint("LEFT", buttons[i-1], "RIGHT", spacing, 0)
    end
    btn:SetText(t.title or tostring(t.id))
    btn.__id = t.id
    btn.__text = t.title or tostring(t.id)  -- для совместимости с FollowerWindow
    btn.__fs = btn:GetFontString()          -- для совместимости с FollowerWindow
    btn:SetScript("OnClick", function()
      if activeId ~= t.id then
        setActive(t.id)
        if opts.onChange then opts.onChange(t.id) end
      end
    end)
    table.insert(buttons, btn)
  end

  -- по умолчанию ничего не активируем - пусть окна сами решают

  return {
    frame     = bar,
    buttons   = buttons,
    setActive = setActive,
    getActive = function() return activeId end,
  }
end

-- ------------------------------- КАРТОЧКИ ---------------------------------

--- Сетка карточек с прокруткой. Возвращает объект grid с методами.
--- opts: { cols=5, cellW=100, cellH=86, gapX=8, gapY=8, top=66, bottom=10, right=10, left=10 }
function NS.BaseWindow.prototype:CreateCardGrid(parent, opts)
  opts = opts or {}
  local cols   = opts.cols   or 5
  local cellW  = opts.cellW  or 100
  local cellH  = opts.cellH  or 86
  local gapX   = opts.gapX   or 8
  local gapY   = opts.gapY   or 8
  local left   = opts.left   or 10
  local right  = opts.right  or 10
  local top    = opts.top    or 66   -- ниже зоны вкладок
  local bottom = opts.bottom or 10

  local scroll = CreateFrame("ScrollFrame", self.name.."_CardsScroll", parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right-22, bottom)
  scroll.ScrollBar:Hide()

  local content = CreateFrame("Frame", self.name.."_CardsContent", scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  local grid = { scroll=scroll, content=content, cards={} }

  function grid:Clear()
    for _, c in ipairs(self.cards) do c:Hide(); c:SetParent(nil) end
    wipe(self.cards)
    self.content:SetSize(1,1)
  end

  --- Добавить карточку. renderFn(cardFrame, data) должен наполнить UI.
  function grid:AddCard(data, renderFn)
    local idx = #self.cards + 1
    local row = math.floor((idx-1) / cols)
    local col = (idx-1) % cols

    local card = CreateFrame("Button", self.content:GetName().."_Card"..idx, self.content, "BackdropTemplate")
    card:SetSize(cellW, cellH)
    card:SetPoint("TOPLEFT", self.content, "TOPLEFT", col*(cellW+gapX), -row*(cellH+gapY))
    card:SetBackdrop({
      bgFile="Interface\\Buttons\\WHITE8x8",
      edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
      tile=false, edgeSize=12,
      insets={left=3,right=3,top=3,bottom=3},
    })
    card:SetBackdropColor(0,0,0,0.2)

    renderFn(card, data)
    table.insert(self.cards, card)

    -- подгоняем размер контейнера
    local rowsCount = math.ceil(#self.cards / cols)
    local fullH = rowsCount*cellH + (rowsCount-1)*gapY
    local fullW = cols*cellW + (cols-1)*gapX
    self.content:SetSize(fullW, fullH)
    scroll.ScrollBar:SetShown(content:GetHeight() > scroll:GetHeight())
    return card
  end

  return grid
end

-- ------------------------------ МОДАЛЬНОЕ ОКНО -----------------------------

--- Компактный модал подтверждения с селектором количества.
--- opts: { title, render = function(frame, state) end, primary={text,onClick}, secondary={text,onClick} }
function NS.BaseWindow.prototype:ShowConfirmDialog(opts)
  local parent = self.frame or UIParent
  local dlg = CreateFrame("Frame", self.name.."_Modal", parent, "BackdropTemplate")
  dlg:SetFrameStrata("FULLSCREEN_DIALOG")
  dlg:SetPoint("CENTER", parent, "CENTER", 0, 10)
  dlg:SetSize(320, 200)
  dlg:SetBackdrop({
    bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=false, edgeSize=24, insets={left=6,right=6,top=6,bottom=6},
  })

  local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", dlg, "TOP", 0, -12)
  title:SetText(opts.title or "Подтверждение")

  local body = CreateFrame("Frame", nil, dlg)
  body:SetPoint("TOPLEFT", 12, -34)
  body:SetPoint("BOTTOMRIGHT", -12, 44)

  local state = { totalText=nil, setTotal = function(_, txt) if state.totalText then state.totalText:SetText(txt or "") end end }

  if type(opts.render) == "function" then
    pcall(opts.render, body, state)
  end

  local cancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
  cancel:SetSize(96, 24)
  cancel:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 12, 12)
  cancel:SetText((opts.secondary and opts.secondary.text) or "Отмена")
  cancel:SetScript("OnClick", function() if opts.secondary and opts.secondary.onClick then opts.secondary.onClick() end dlg:Hide(); dlg:SetParent(nil) end)

  local ok = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
  ok:SetSize(96, 24)
  ok:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 12)
  ok:SetText((opts.primary and opts.primary.text) or "OK")
  ok:SetScript("OnClick", function() if opts.primary and opts.primary.onClick then opts.primary.onClick(ok, dlg) end end)

  return dlg, ok, cancel, state
end

-- --------------------------- ВИЗУАЛЬНЫЙ ФИДБЕК -----------------------------

--- Лёгкая вспышка на фрейме (покупка/успех).
function NS.BaseWindow.prototype:PlayPurchaseFlash(frame)
  if not frame or frame.__flashAG then
    if frame and frame.__flashAG then frame.__flashAG:Play() end
    return
  end
  local ag = frame:CreateAnimationGroup()
  local a1 = ag:CreateAnimation("Alpha")
  a1:SetFromAlpha(1); a1:SetToAlpha(0.2); a1:SetDuration(0.08)
  local a2 = ag:CreateAnimation("Alpha")
  a2:SetFromAlpha(0.2); a2:SetToAlpha(1); a2:SetDuration(0.12)
  frame.__flashAG = ag
  ag:Play()
end

--- Creates a horizontal or vertical bar of selector buttons using TabsBar with proper colors.
function NS.BaseWindow.prototype:CreateSelectorBar(parent, items, opts)
  -- items: { {id, text, onClick}, ... } → tabs: { {id, title}, ... }
  local tabs = {}
  for _, it in ipairs(items or {}) do table.insert(tabs, { id=it.id, title=it.text }) end
  local t = self:CreateTabsBar(parent, tabs, { onChange=function(id)
    for _, it in ipairs(items) do if it.id==id and it.onClick then it.onClick(id) end end
  end, height=(opts and opts.height) or 24, spacing=(opts and opts.spacing) or 6 })
  -- Возвращаем полный объект с методом setActive для совместимости
  return t.frame, t.buttons, t.setActive
end

-- ------------------------------ БЛОКИРОВКА ПЕРЕТАСКИВАНИЯ -----------------------------

--- Создает кнопку-замок для блокировки перетаскивания окна.
--- По умолчанию размещается в правом верхнем углу слева от кнопки закрытия.
--- Пример использования: self:CreateLockButton() -- с настройками по умолчанию
--- opts: { size=16, position={point, x, y}, textures={unlocked, locked} }
function NS.BaseWindow.prototype:CreateLockButton(opts)
  opts = opts or {}
  local size = opts.size or 16
  -- По умолчанию размещаем замок слева от крестика закрытия (крестик обычно 16x16)
  local pos = opts.position or {"TOPRIGHT", -28, -8}  -- -28 чтобы быть слева от крестика
  local textures = opts.textures or {
    unlocked = "Interface\\Buttons\\LockButton-Unlocked-Up",
    locked = "Interface\\Buttons\\LockButton-Locked-Up"
  }
  
  local lockButton = CreateFrame("Button", (self.name or "Window") .. "_LockButton", self.frame)
  lockButton:SetSize(size, size)
  lockButton:SetPoint(pos[1], self.frame, pos[1], pos[2] or 0, pos[3] or 0)
  
  lockButton:SetNormalTexture(textures.unlocked)
  lockButton:SetPushedTexture(textures.unlocked)
  lockButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  
  -- Тултип
  lockButton:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:SetText((self.isLocked and "Разблокировать перетаскивание") or "Заблокировать перетаскивание")
    GameTooltip:Show()
  end)
  lockButton:SetScript("OnLeave", GameTooltip_Hide)
  
  -- Обработчик клика
  lockButton:SetScript("OnClick", function()
    if self.ToggleDragLock then
      self:ToggleDragLock()
    else
      -- Простая реализация для окон, не наследующих BaseWindow
      self.isLocked = not self.isLocked
      if self.frame then
        if self.isLocked then
          self.frame:SetMovable(false)
        else
          self.frame:SetMovable(true)
        end
      end
      -- Обновляем текстуру замка
      if self.isLocked then
        lockButton:SetNormalTexture(textures.locked)
        lockButton:SetPushedTexture(textures.locked)
      else
        lockButton:SetNormalTexture(textures.unlocked)
        lockButton:SetPushedTexture(textures.unlocked)
      end
    end
  end)
  
  self.elements.lockButton = lockButton
  self.lockButtonTextures = textures
  
  -- Устанавливаем начальное состояние
  if self.UpdateLockButton then
    self:UpdateLockButton()
  end
  
  return lockButton
end

--- Переключает блокировку перетаскивания окна.
function NS.BaseWindow.prototype:ToggleDragLock()
  self.isLocked = not self.isLocked
  
  if self.isLocked then
    -- Блокируем только перетаскивание, но оставляем мышь активной для других элементов
    self.frame:SetMovable(false)
    self.frame:RegisterForDrag()  -- убираем drag события
    if NS.Logger then
      NS.Logger:UI(self.name .. ": перетаскивание заблокировано")
    end
  else
    -- Разблокируем перетаскивание
    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")  -- восстанавливаем drag события
    if NS.Logger then
      NS.Logger:UI(self.name .. ": перетаскивание разблокировано")
    end
  end
  
  self:UpdateLockButton()
  
  -- Вызываем хук если есть
  if self.hooks.onLockToggle then
    pcall(self.hooks.onLockToggle, self, self.isLocked)
  end
end

--- Обновляет внешний вид кнопки-замка в зависимости от состояния блокировки.
function NS.BaseWindow.prototype:UpdateLockButton()
  if not (self.elements.lockButton and self.lockButtonTextures) then return end
  
  local texture = self.isLocked and self.lockButtonTextures.locked or self.lockButtonTextures.unlocked
  self.elements.lockButton:SetNormalTexture(texture)
  self.elements.lockButton:SetPushedTexture(texture)
end

--- Устанавливает состояние блокировки программно.
function NS.BaseWindow.prototype:SetDragLocked(locked)
  if self.isLocked == locked then return end
  self:ToggleDragLock()
end

--- Возвращает текущее состояние блокировки.
function NS.BaseWindow.prototype:IsDragLocked()
  return self.isLocked
end