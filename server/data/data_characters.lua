--[[==========================================================================
  PATRON SYSTEM - CHARACTER DATABASE
  Централизованная база всех персонажей системы
  
  СТРУКТУРА:
  - ID персонажа -> данные персонажа
  - Имена, портреты, эмоции
  - Поддержка многих типов персонажей
============================================================================]]

local CharacterData = {
    --[[=========================================================================
      ПОКРОВИТЕЛИ (ID: 1-10)
    ===========================================================================]]
    
    [1] = { -- Пустота
        Name = "Пустота",
        Type = "PATRON",
        DefaultPortrait = "void_default",
        Emotions = {
            default = "void_default",
            angry = "void_angry", 
            curious = "void_curious",
            pleased = "void_pleased",
            threatening = "void_threatening",
            amused = "void_amused"
        }
    },
    
    [2] = { -- Дракон Лорд
        Name = "Дракон Лорд",
        Type = "PATRON", 
        DefaultPortrait = "dragon_default",
        Emotions = {
            default = "dragon_default",
            angry = "dragon_angry",
            happy = "dragon_happy", 
            greedy = "dragon_greedy",
            calculating = "dragon_calculating",
            disappointed = "dragon_disappointed"
        }
    },
    
    [3] = { -- Элуна
        Name = "Элуна",
        Type = "PATRON",
        DefaultPortrait = "eluna_default", 
        Emotions = {
            default = "eluna_default",
            sad = "eluna_sad",
            caring = "eluna_caring",
            disappointed = "eluna_disappointed",
            loving = "eluna_loving",
            worried = "eluna_worried"
        }
    },
    
    --[[=========================================================================
      ФОЛЛОВЕРЫ (ID: 101-200)
    ===========================================================================]]
    
    [101] = { -- Алайя (душа-девушка от Пустоты)
        Name = "Алайя",  -- ИСПРАВЛЕНО: используем имя из data_patrons_followers.lua
        Type = "FOLLOWER",
        Patron = 1, -- Служит Пустоте
        DefaultPortrait = "shadow_warrior_default",
        Emotions = {
            default = "shadow_warrior_default",
            determined = "shadow_warrior_determined",
            worried = "shadow_warrior_worried", 
            angry = "shadow_warrior_angry",
            respectful = "shadow_warrior_bow"
        }
    },
    
    [102] = { -- Арле'Кино (Дракон-торговец)
        Name = "Арле'Кино", 
        Type = "FOLLOWER",
        Patron = 2, -- Служит Дракону
        DefaultPortrait = "arlekino_default",
        Emotions = {
            default = "arlekino_default",
            scheming = "arlekino_scheming",
            pleased = "arlekino_pleased",
            calculating = "arlekino_gold_eyes",
            amused = "arlekino_smirk"
        }
    },
    
    [103] = { -- Узан Дул (эльф-мужчина из другого мира)
        Name = "Узан Дул",  -- ИСПРАВЛЕНО: используем имя из data_patrons_followers.lua
        Type = "FOLLOWER", 
        Patron = 3, -- Служит Элуне
        DefaultPortrait = "mysterious_trader_default",  -- ИСПРАВЛЕНО: мужской портрет
        Emotions = {
            default = "mysterious_trader_default",
            suspicious = "mysterious_trader_suspicious",
            intrigued = "mysterious_trader_intrigued",
            welcoming = "mysterious_trader_welcoming"
        }
    },
    
    --[[=========================================================================
      ВРАГИ И АНТАГОНИСТЫ (ID: 201-300)  
    ===========================================================================]]
    
    [201] = { -- Инквизитор Света
        Name = "Инквизитор Света",
        Type = "ENEMY",
        Faction = "LIGHT",
        DefaultPortrait = "inquisitor_default", 
        Emotions = {
            default = "inquisitor_default",
            righteous = "inquisitor_righteous",
            angry = "inquisitor_angry",
            disgusted = "inquisitor_disgusted",
            threatening = "inquisitor_threatening"
        }
    },
    
    [202] = { -- Демон Хаоса
        Name = "Демон Хаоса", 
        Type = "ENEMY",
        Faction = "CHAOS",
        DefaultPortrait = "chaos_demon_default",
        Emotions = {
            default = "chaos_demon_default",
            laughing = "chaos_demon_laughing",
            furious = "chaos_demon_furious", 
            mocking = "chaos_demon_mocking",
            menacing = "chaos_demon_menacing"
        }
    },
    
    --[[=========================================================================
      НЕЙТРАЛЬНЫЕ НПЦ (ID: 301-400)
    ===========================================================================]]
    
    [301] = { -- Таинственный Торговец
        Name = "Таинственный Торговец",
        Type = "NPC",
        Faction = "NEUTRAL",
        DefaultPortrait = "mysterious_trader_default",
        Emotions = {
            default = "mysterious_trader_default",
            welcoming = "mysterious_trader_welcoming",
            suspicious = "mysterious_trader_suspicious",
            intrigued = "mysterious_trader_intrigued"
        }
    },
    
    [302] = { -- Оракул
        Name = "Оракул",
        Type = "NPC", 
        Faction = "NEUTRAL",
        DefaultPortrait = "oracle_default",
        Emotions = {
            default = "oracle_default",
            prophetic = "oracle_prophetic",
            sad = "oracle_sad",
            mysterious = "oracle_mysterious",
            knowing = "oracle_knowing"
        }
    },
    
    --[[=========================================================================
      ОСОБЫЕ ПЕРСОНАЖИ (ID: 401-500)
    ===========================================================================]]
    
    [401] = { -- Голос из Прошлого
        Name = "Голос из Прошлого",
        Type = "SPECIAL",
        DefaultPortrait = "past_voice_default",
        Emotions = {
            default = "past_voice_default",
            nostalgic = "past_voice_nostalgic",
            warning = "past_voice_warning",
            fading = "past_voice_fading"
        }
    },
    
    [402] = { -- Видение Будущего  
        Name = "Видение Будущего",
        Type = "SPECIAL",
        DefaultPortrait = "future_vision_default",
        Emotions = {
            default = "future_vision_default",
            ominous = "future_vision_ominous",
            hopeful = "future_vision_hopeful", 
            unclear = "future_vision_unclear"
        }
    }
}

--[[=========================================================================
  API ФУНКЦИИ
===========================================================================]]

-- Получить данные персонажа
function GetCharacterData(characterID)
    return CharacterData[characterID]
end

-- Получить портрет персонажа с эмоцией
function GetCharacterPortrait(characterID, emotion)
    local character = CharacterData[characterID]
    if not character then
        return nil
    end
    
    if emotion and character.Emotions and character.Emotions[emotion] then
        return character.Emotions[emotion]
    end
    
    return character.DefaultPortrait
end

-- Получить все персонажи определенного типа
function GetCharactersByType(characterType)
    local result = {}
    for id, character in pairs(CharacterData) do
        if character.Type == characterType then
            result[id] = character
        end
    end
    return result
end

-- Получить всех фолловеров покровителя  
function GetPatronFollowers(patronID)
    local result = {}
    for id, character in pairs(CharacterData) do
        if character.Type == "FOLLOWER" and character.Patron == patronID then
            result[id] = character
        end
    end
    return result
end

-- Проверить, существует ли персонаж
function CharacterExists(characterID)
    return CharacterData[characterID] ~= nil
end

-- Получить имя персонажа
function GetCharacterName(characterID)
    local character = CharacterData[characterID]
    return character and character.Name or "Неизвестный"
end

-- Экспорт данных (для других модулей)
return CharacterData