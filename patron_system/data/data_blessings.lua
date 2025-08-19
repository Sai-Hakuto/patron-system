-- File: my_eluna_scripts/patron_system/data/data_blessings.lua
-- Contains static data for Blessings, with custom effect definitions.

local Blessings = {
    -- Blessing for The Void (PatronID 1) - Blessing of Stamina
    [1001] = {
        BlessingID = 1001,
        PatronID = 1,
        Name = "Благословение Стойкости (Пустота)",
        Description = "Повышает вашу выносливость и живучесть!",
        BlessingType = "Defensive",
        Cooldown = 60, -- seconds
        NeededRank = 0,
        RequiresTarget = false, -- Does not require a target
        Cost = {
            Items = { {ItemID = 500000, Amount = 1} } -- ItemID 500000: Placeholder Item
        },
        Effect = {
            Type = "APPLY_AURA",
            AnimationSpellID = 48743, -- Visual spell for stamina buff
            AuraSpellID = 48743,      -- The actual spell ID for the buff effect
            Duration = 300            -- Aura duration in seconds (5 minutes)
        }
    },
    -- Blessing for Dragon Lord (PatronID 2) - Blessing of Speed
    [2001] = {
        BlessingID = 2001,
        PatronID = 2,
        Name = "Благословение Скорости (Повелитель Драконов)",
        Description = "Придает вам неимоверную скорость!",
        BlessingType = "Support",
        Cooldown = 60,
        NeededRank = 0,
        RequiresTarget = false,
        Cost = {
            Items = { {ItemID = 500000, Amount = 1} }
        },
        Effect = {
            Type = "APPLY_AURA",
            AnimationSpellID = 132959, -- Visual spell for speed buff
            AuraSpellID = 132959,      -- The actual spell ID for the buff effect
            Duration = 300            -- Aura duration in seconds (5 minutes)
        }
    },
    -- Blessing for Eluna (PatronID 3) - Blessing of Attack
    [3001] = {
        BlessingID = 3001,
        PatronID = 3,
        Name = "Благословение Атаки (Элуна)",
        Description = "Призывает мощный удар по врагу!",
        BlessingType = "Offensive",
        Cooldown = 10,
        NeededRank = 0,
        RequiresTarget = true, -- Requires a target to cast
        Cost = {
            Items = { {ItemID = 500000, Amount = 1} }
        },
        Effect = {
            Type = "DAMAGE",
            AnimationSpellID = 133,         -- Generic spell ID for visual/animation
            Amount = 500,                   -- Base damage amount
            School = "Shadow",              -- Damage school (Physical, Holy, Fire, Nature, Frost, Shadow, Arcane)
            CanCrit = true,                 -- Can this damage crit?
            DamageModifier = "SPELL_POWER"  -- Scales damage with Spell Power (NONE, ATTACK_POWER, SPELL_POWER)
        }
    }
}

return Blessings