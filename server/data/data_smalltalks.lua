-- File: my_eluna_scripts/patron_system/data/data_smalltalks.lua
-- Contains dynamic data for Small Talks/Flavor Text from Patrons and Followers with conditional availability.
--
-- НОВАЯ СТРУКТУРА:
-- - Базовые фразы (всегда доступны)
-- - Условные фразы (доступны при выполнении условий)
-- - Поддержка приоритетов (более специфичные фразы показываются чаще)

local SmallTalks = {
  [1] = { -- The Void
    -- Базовые фразы (всегда доступны)
    {
      Replica = "Тишина. Она тоже ответ.",
      Priority = 1
    },
    {
      Replica = "Ты... чувствуешь их угасающие эхо? Славно.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "Твоя душа становится темнее. Отлично.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SOULS", Amount = 10 }
      }
    },
    {
      Replica = "Страдания... они питают пустоту. Продолжай.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SUFFERING", Amount = 5 }
      }
    },
    {
      Replica = "Ты прошел через боль и остался. Впечатляет.",
      Priority = 3,
      Conditions = {
        { Type = "HAS_EVENT", PatronID = 1, EventName = "first_dialogue_completed" }
      }
    },
    {
      Replica = "Деньги? В пустоте они бесполезны. Но твоя преданность... это ценно.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_MONEY", Amount = 10000 }
      }
    }
  },
  
  [2] = { -- Dragon Lord
    -- Базовые фразы
    {
      Replica = "А, это ты. Надеюсь, твой кошелек сегодня тяжелее, чем вчера.",
      Priority = 1
    },
    {
      Replica = "Время - деньги. Так что не будем тратить ни то, ни другое.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "Хм, у тебя появились средства. Возможно, ты не так бесполезен.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_MONEY", Amount = 5000 }
      }
    },
    {
      Replica = "Богатство притягивает богатство. Ты начинаешь понимать.",
      Priority = 3,
      Conditions = {
        { Type = "HAS_MONEY", Amount = 50000 }
      }
    },
    {
      Replica = "Души? Интересная валюта. Но золото надежнее.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SOULS", Amount = 5 }
      }
    },
    {
      Replica = "Страдания делают нас сильнее. И богаче, если знать как их использовать.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SUFFERING", Amount = 3 }
      }
    },
    {
      Replica = "Ты доказал свою полезность. Продолжай в том же духе.",
      Priority = 3,
      Conditions = {
        { Type = "MIN_RELATIONSHIP", PatronID = 2, Points = 50 }
      }
    }
  },
  
  [3] = { -- Eluna
    -- Базовые фразы
    {
      Replica = "Здравствуй, милое дитя. Мир так несправедлив, не правда ли? Но мы это исправим.",
      Priority = 1
    },
    {
      Replica = "Я видела твой сон. Ты был так напуган.. Это хорошо, страх очищает.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "Твои страдания не напрасны, дитя. Они делают тебя чище.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SUFFERING", Amount = 8 }
      }
    },
    {
      Replica = "Я чувствую, как твоя душа светлеет. Это правильный путь.",
      Priority = 3,
      Conditions = {
        { Type = "HAS_SOULS", Amount = 15 }
      }
    },
    {
      Replica = "Деньги - лишь инструмент. Но в твоих руках они могут творить добро.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_MONEY", Amount = 20000 }
      }
    },
    {
      Replica = "Ты растешь, моё дитя. Я вижу в тебе потенциал истинного праведника.",
      Priority = 3,
      Conditions = {
        { Type = "MIN_RELATIONSHIP", PatronID = 3, Points = 75 }
      }
    },
    {
      Replica = "Каждый твой шаг ведет к свету. Не останавливайся.",
      Priority = 3,
      Conditions = {
        { Type = "HAS_EVENT", PatronID = 3, EventName = "purification_ritual_completed" }
      }
    }
  },
  
  [101] = { -- Alaya
    -- Базовые фразы
    {
      Replica = "...Этот мир... такой... яркий.",
      Priority = 1
    },
    {
      Replica = "Я видела рождение звезд. И их смерть. Это одно и то же.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "Ты... развиваешься. Интересно наблюдать.",
      Priority = 2,
      Conditions = {
        { Type = "MIN_LEVEL", Level = 20 }
      }
    }
  },
  
  [102] = { -- Arle'Kino
    -- Базовые фразы
    {
      Replica = "Ну что, партнер, сегодня разбогатеем или опять впросак попадем? Ставлю на второе!",
      Priority = 1
    },
    {
      Replica = "Эх, была бы у меня лавка, я бы тебе такую скидку сделала! Но у меня нет лавки. И скидки тоже нет.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "О, у тебя есть деньги! Теперь мы можем говорить на равных!",
      Priority = 2,
      Conditions = {
        { Type = "HAS_MONEY", Amount = 1000 }
      }
    }
  },
  
  [103] = { -- Uzan Dul
    -- Базовые фразы
    {
      Replica = "Еще один день в этом чужом мире. Еще один шаг к свободе.",
      Priority = 1
    },
    {
      Replica = "Не обращай на меня внимания. Я просто... наблюдаю.",
      Priority = 1
    },
    
    -- Условные фразы
    {
      Replica = "Ты тоже чувствуешь себя чужим здесь? Понимаю.",
      Priority = 2,
      Conditions = {
        { Type = "HAS_SUFFERING", Amount = 10 }
      }
    }
  },
}

return SmallTalks