-- Defensive Combat Logic Script for Helper NPCs with Spells for All

-- Define helper scanning radius for detecting nearby enemies
local SCAN_RADIUS = 20 -- Radius within which the helper searches for enemies attacking the owner

-- Define attack behaviors with spells for each NPC based on its ID
local npcCombatLogic = {
    [9400000] = function(helper, enemy) -- Olaf: Melee + Spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 330669) -- Example: Corruption (spell ID 172)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Perform melee attack
        end
    end,
    [9400001] = function(helper, enemy) -- Kam'il: Melee + Spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 845) -- Example: Corruption (spell ID 172)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Perform melee attack
        end
    end,
    [9400002] = function(helper, enemy) -- Elden: Healer + Melee
        local owner = helper:GetOwner()
        if owner and owner:GetHealthPct() < 50 then
            helper:CastSpell(owner, 2061) -- Example: Heal (spell ID 2061)
        elseif helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 337429) -- Example: swipe (spell ID 337429)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Default melee attack
        end
    end,
    [9400003] = function(helper, enemy) -- Fyrakk: Fire-based attacker
        if helper:GetDistance(enemy) <= 30 then
            helper:CastSpell(enemy, 133) -- Example: Fireball (spell ID 133)
        elseif helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 2120) -- Example: Flamestrike (spell ID 2120)
        end
    end,
    [9400004] = function(helper, enemy) -- Jamone: Healer + Melee
        local owner = helper:GetOwner()
        if owner and owner:GetHealthPct() < 50 then
            helper:CastSpell(owner, 2061) -- Example: Heal (spell ID 2061)
        elseif helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 337429) -- Example: swipe (spell ID 337429)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Default melee attack
        end
    end,
    [9400005] = function(helper, enemy) -- A new NPC type with melee and spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 369842) -- Example: Lightning Bolt (spell ID 403)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Perform melee attack
        end
    end,
    [9400006] = function(helper, enemy) -- Another NPC type with melee and spell
        if helper:GetDistance(enemy) <= 10 then
            helper:CastSpell(enemy, 348) -- Example: Immolate (spell ID 348)
        elseif helper:GetDistance(enemy) <= 5 then
            helper:Attack(enemy, true) -- Perform melee attack
        end
    end
}

-- Function to make helpers engage enemies attacking their owner
local function HandleDefensiveCombat(helper)
    local owner = helper:GetOwner()
    if not owner then
        return -- Ensure the helper does nothing if it has no owner
    end

    -- Scan for nearby enemies attacking the owner
    local enemies = owner:GetCreaturesInRange(SCAN_RADIUS)
    for _, enemy in ipairs(enemies) do
        if enemy:IsInCombat() and enemy:GetVictim() == owner then -- Check if the enemy is attacking the owner
            local npcID = helper:GetEntry()
            local combatLogic = npcCombatLogic[npcID]

            if combatLogic then
                combatLogic(helper, enemy) -- Execute NPC-specific combat logic
            else
                helper:Attack(enemy, true) -- Default melee attack
            end
            return -- Attack the first valid enemy found
        end
    end

    -- No targets found, helper continues to idle near the player
end

-- Event: Periodically check for defensive combat
local function RunDefensiveCombatChecks()
    for _, player in ipairs(GetPlayersInWorld()) do
        local npcs = player:GetCreaturesInRange(50) -- Get nearby NPCs within 50 yards
        for _, npc in ipairs(npcs) do
            if npc:GetOwnerGUID() == player:GetGUID() then
                HandleDefensiveCombat(npc) -- Trigger defensive combat logic
            end
        end
    end
end

-- Run defensive combat logic every 2 seconds
CreateLuaEvent(RunDefensiveCombatChecks, 2000, 0)
