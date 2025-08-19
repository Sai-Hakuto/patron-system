
--[[==========================================================================
  PATRON SYSTEM - NAMESPACE INITIALIZATION
  Инициализация глобального неймспейса (должен загружаться первым)
============================================================================]]

-- Создаем глобальный неймспейс для всего аддона
PatronSystemNS = PatronSystemNS or {}

-- Базовые константы
PatronSystemNS.ADDON_PREFIX = "PatronSystem"
PatronSystemNS.VERSION = "2.1.0"

-- Инициализируем флаг debug режима (по умолчанию выключен)
PatronSystemNS.debugMode = false

-- Инициализируем пустые объекты для модулей (будут заполнены позже)
PatronSystemNS.Config = {}
PatronSystemNS.Logger = {}
PatronSystemNS.DataManager = {}
PatronSystemNS.DialogueEngine = {}
PatronSystemNS.UIManager = {}
PatronSystemNS.BaseWindow = {}
PatronSystemNS.PatronWindow = {}

print("|cff00ff00[PatronSystem]|r Неймспейс инициализирован")