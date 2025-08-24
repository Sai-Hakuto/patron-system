-- File: my_eluna_scripts/patron_system/data/data_blessings.lua
-- Contains static data for Blessings, with custom effect definitions.

local Blessings = {
  [1001] = { -- BUFF
    name = "Благословение Силы Патрона 1",
    description = "Придает вам неимоверную силу!",
	blessing_type = "Support",
	icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
	blessing_id = 1001,
    spell_id = 48743,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 60,
    cost_item_id = 500000, cost_amount = 0,
  },
  
  [1101] = { -- BUFF
    name = "Благословение Силы Патрона 2",
    description = "Придает вам неимоверную силу!",
	blessing_type = "Support",
	icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
	blessing_id = 1101,
    spell_id = 48743,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 60,
    cost_item_id = 500000, cost_amount = 0,
  },
  
  [1201] = { -- BUFF
    name = "Благословение Силы Патрона 3",
    description = "Придает вам неимоверную силу!",
	blessing_type = "Support",
	icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
	blessing_id = 1201,
    spell_id = 48743,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 60,
    cost_item_id = 500000, cost_amount = 0,
  },

  [1002] = { -- BUFF
    name = "Благословение Стойкости Патрона 1",
    description = "Повышает вашу выносливость и живучесть!",
	blessing_type = "Defensive",
	icon = "Interface\\Icons\\Ability_Warrior_Devastate",
	blessing_id = 1002,
    spell_id = 132959,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 20,
    cost_item_id = 500000, cost_amount = 0,
  },
  
  [1102] = { -- BUFF
    name = "Благословение Стойкости Патрона 2",
    description = "Повышает вашу выносливость и живучесть!",
	blessing_type = "Defensive",
	icon = "Interface\\Icons\\Ability_Warrior_Devastate",
	blessing_id = 1102,
    spell_id = 132959,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 20,
    cost_item_id = 500000, cost_amount = 0,
  },
  
  [1202] = { -- BUFF
    name = "Благословение Стойкости Патрона 3",
    description = "Повышает вашу выносливость и живучесть!",
	blessing_type = "Defensive",
	icon = "Interface\\Icons\\Ability_Warrior_Devastate",
	blessing_id = 1202,
    spell_id = 132959,
    is_offensive = false, requires_target = false, is_aoe = false,
    cooldown_seconds = 20,
    cost_item_id = 500000, cost_amount = 0,
  },

  [3001] = { -- SINGLE
    name = "Благословение Атаки",
    description = "Призывает мощный удар по врагу!",
	blessing_type = "Offensive",
	icon = "Interface\\Icons\\Spell_Nature_Swiftness",
	blessing_id = 3001,
    spell_id = 133,  -- визуал (опционально)
    is_offensive = true, requires_target = true, is_aoe = false,
    cooldown_seconds = 10, range = 40.0,
    cost_item_id = 500000, cost_amount = 0,
    -- эффект урона — в какой слот bp подставлять рассчитанное значение
    effect = 25, effect2 = nil, effect3 = nil,
    dmg_effect = "effect",
    currencyK = 2.9,
  },

  [3501] = { -- AOE
    name = "Благословение Ливня",
    description = "Призывает мощный удар по площади на последней позиции врага",
	blessing_type = "Offensive",
	icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
	blessing_id = 3501,
    spell_id = 190356,          -- визуал на землю
    spell_tick_id = 228599,     -- тик-спелл
    is_offensive = true, is_aoe = true, requires_target = true,
    radius = 8.0, tick_ms = 500, duration_ms = 14000,
    cooldown_seconds = 12, range = 40.0,
    cost_item_id = 500000, cost_amount = 0,
    effect = 25, effect2 = nil, effect3 = nil,  -- базовая «искра»
    dmg_effect = "effect",
    currencyK = 2.9,
    aoe_cap_targets = 8,
  }
}

return Blessings