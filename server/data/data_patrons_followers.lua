-- File: my_eluna_scripts/patron_system/data/data_patrons_followers.lua
-- Contains static data for Patrons and Followers.

local Patrons = {
  [1] = {
    PatronID = 1,
    Name = "Пустота (The Void)",
    NpcEntryID = 70001, -- Placeholder NPC Entry ID
    Aligment = "Хаотично-Тёмный",
    Description = "Стоическая, мистическая и жуткая тёмная сущность, что помогает в обмен на души убитых существ.",
    PassiveEffects = {
      { Type = "PROC_ON_KILL", Chance = 0.25, Effect = { Type="AURA", AuraSpellID=45472, Duration=10 } } -- Placeholder Aura SpellID (Spirit Tap)
    }
  },
  [2] = {
    PatronID = 2,
    Name = "Повелитель Драконов (Dragon Lord)",
    NpcEntryID = 70002, -- Placeholder NPC Entry ID
    Aligment = "Оппортунистически-Нейтральный",
    Description = "Всезнающий и альтруистичный, но не бескорытный. Предоставит силу и предметы в обмен на звонкую монету и ценные товары.",
    PassiveEffects = {
      { Type = "DISCOUNT_VENDOR", Value = 0.10 },
      { Type = "BONUS_GOLD_LOOT", Value = 0.05 }
    }
  },
  [3] = {
    PatronID = 3,
    Name = "Элуна (Контрафактная)",
    NpcEntryID = 70003, -- Placeholder NPC Entry ID
    Aligment = "Притворно-Светлый, Истинно-Злой",
    Description = "Милая леди света с прогнившей и злой натурой. Ищет боль и страдания в мире под высокими, претенциозными и якобы оправданными предлогами. Газлайтит вас, внушая сомнительные мысли о мире, и просто играет с вами.",
    PassiveEffects = {
      { Type = "PERIODIC_CHALLENGE", Cooldown = 3600, ChallengePoolID = 1 } -- ChallengePoolID links to a table of possible challenges
    }
  }
}

local Followers = {
  [101] = {
    FollowerID = 101,
    PatronID = 1, -- Bound to The Void
    FollowerName = "Алайя",
    NpcEntryID = 70101, -- Placeholder NPC Entry ID
    Aligment = "Нейтральный",
    Description = "Странствующая душа, что дана в услужение от Пустоты. Слабоэмоциональная, любопытствующая девушка в поисках себя после тысячелетий в закромах у тьмы.",
    PassiveEffects = {
      { Type = "STAT_MODIFIER", Stat = "SPIRIT", Value = 75 }
    }
  },
  [102] = {
    FollowerID = 102,
    PatronID = 2, -- Bound to Dragon Lord
    FollowerName = "Арле'Кино",
    NpcEntryID = 70102, -- Placeholder NPC Entry ID
    Aligment = "Хаотично-Нейтральный",
    Description = "Бойкая, юморная и крайне неудачливая душа торговки, бывшая последовательница Повелителя Драконов. Воскрешена им в услужение игроку.",
    PassiveEffects = {
      { Type = "PROC_ON_LOOT", Chance = 0.05, Effect = { Type="GET_ITEM", ItemID=9263, Amount=1 } } -- ItemID 9263: Strange Trinket (placeholder)
    }
  },
  [103] = {
    FollowerID = 103,
    PatronID = 3, -- Bound to Eluna
    FollowerName = "Узан Дул",
    NpcEntryID = 70103, -- Placeholder NPC Entry ID
    Aligment = "Нейтрально-Злой",
    Description = "Эльф из другого мира. Воскрешен в Азероте в качестве прислужника для игрока. В поисках силы, чтобы сломать духовные цепи, связывающие его с этим миром и его госпожой.",
    PassiveEffects = {
      { Type = "STAT_MODIFIER", Stat = "HASTE_RATING", PercentValue = 0.03 } -- Haste rating percentage
    }
  }
}

return { Patrons = Patrons, Followers = Followers }