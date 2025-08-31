local AIO = AIO or require("AIO")
require("convos")
require("combat")

local HireHandlers = AIO.AddHandlers("hire", {})

local HELPER_COST = 10   -- cost in copper (5 gold)
local HELPER_NPC_IDS = {9400000, 9400001, 9400002, 9400003, 9400004, 9400005}

local helperWeapons = {
    [9400000] = {6905, 228891},
    [9400001] = {6905, 228891},
    [9400002] = {6905, 228891},
    [9400003] = {6905, 228891},
    [9400004] = {6905, 228891},
    [9400005] = {6905, 228891}
}

local transmogEffects = {
    back = {
        { name = "Jetpack", spellID = 256205 },
        { name = "Backpack", spellID = 472705 },
        { name = "Plague Pack", spellID = 250088 },
        { name = "Fire Wings", spellID = 466487 },
        { name = "Pumpkin Helm", spellID = 393900 }
    },
    aura = {
        { name = "Ghostly Aura", spellID = 474318 },
        { name = "Lightning Fists", spellID = 1216575 },
        { name = "Deathknight", spellID = 473545 },
        { name = "Pirate", spellID = 430467 },
        { name = "Captain", spellID = 439264 }
    }
}

local mountSpells = {
    [9400000] = 1214940,
    [9400001] = 1214940,
    [9400002] = 1214940,
    [9400003] = 1214940,
    [9400004] = 1214940,
    [9400005] = 1214940,
}

local helperNameMap = {
    olaf = 1,
    ["kam'il"] = 2,
    elden = 3,
    fyrakk = 4,
    jamone = 5,
    thane = 6
}

local function ApplyTransmogEffect(npc, effectSpellID)
    if npc and effectSpellID then
        npc:CastSpell(npc, effectSpellID, true)
    end
end

local function EquipHelperItem(creature, helperID, itemID)
    local validItems = helperWeapons[helperID]
    if not validItems then return false end

    for _, validItem in ipairs(validItems) do
        if validItem == itemID then
            creature:SetEquipmentSlots(itemID, 0, 0)
            return true
        end
    end

    return false
end

function GetNPCByHelperID(player, fullHelperID)
    local npcList = player:GetCreaturesInRange(50)
    for _, npc in ipairs(npcList) do
        if npc:GetEntry() == fullHelperID and npc:GetOwnerGUID() == player:GetGUID() then
            return npc
        end
    end
    return nil
end

function HireHandlers.HireHelper(player, data)
    local helperIndex = data.helperIndex
    local itemID = data.itemID
    local backSpellID = data.backSpellID
    local auraSpellID = data.auraSpellID
	

    if not HELPER_NPC_IDS[helperIndex] then return end
    local helperID = HELPER_NPC_IDS[helperIndex]
    local existingHelper = GetNPCByHelperID(player, helperID)

    if existingHelper then existingHelper:DespawnOrUnsummon() end
    if player:GetCoinage() < HELPER_COST then return end

    player:ModifyMoney(-HELPER_COST)
    local x, y, z, o = player:GetLocation()
    local newNPC = player:SpawnCreature(helperID, x, y, z, o, 8, 0)

    if not newNPC then return end

    newNPC:SetOwnerGUID(player:GetGUID())
    newNPC:SetLevel(player:GetLevel())
    newNPC:SetFaction(player:GetFaction())
    newNPC:SetReactState(1)
    newNPC:MoveFollow(player, 1.0, 2.0)

    if itemID then EquipHelperItem(newNPC, helperID, itemID) end
    if backSpellID then ApplyTransmogEffect(newNPC, backSpellID) end
    --if auraSpellID then ApplyTransmogEffect(newNPC, auraSpellID) end
end

function HireHandlers.DismissHelper(player, helperIndex)
    local fullHelperID = HELPER_NPC_IDS[helperIndex]
    local npc = GetNPCByHelperID(player, fullHelperID)
    if npc then npc:DespawnOrUnsummon() end
end

local function OnPlayerChat(event, player, msg)
    local lowerMsg = string.lower(msg)
    local helperName, orderStr = string.match(lowerMsg, "^(%a+)%s+(.+)$")

    if helperName and orderStr then
        local order = string.gsub(orderStr, "%s+", "")
        local hIndex = helperNameMap[helperName]

        if hIndex then
            local fullHelperID = HELPER_NPC_IDS[hIndex]
            local npc = GetNPCByHelperID(player, fullHelperID)
            if not npc then return true end

            if order == "attack" then
                local targetUnit = player:GetSelection()
                if targetUnit and targetUnit:IsInWorld() then
                    -- Prevent helpers from attacking the hirer
                    if targetUnit:GetGUID() == player:GetGUID() then
                        player:SendBroadcastMessage(helperName .. " refuses to attack you!")
                        return true
                    end

                    -- Prevent attacking friendly faction members, including faction 35
                    if targetUnit:GetFaction() == player:GetFaction() or targetUnit:GetFaction() == 35 then
                        player:SendBroadcastMessage(helperName .. " refuses to attack a friendly unit!")
                        return true
                    end

                    -- Proceed with the attack if all checks pass
                    npc:AttackStart(targetUnit)
                    player:SendBroadcastMessage(helperName .. " is attacking your selected target!")
                else
                    player:SendBroadcastMessage("No target selected!")
                end
            elseif order == "defend" then
                npc:SetReactState(1)
            elseif order == "return" then
                npc:MoveFollow(player, 1.0, 2.0)
            elseif order == "mountup" then
                local mountSpell = mountSpells[fullHelperID]
                if mountSpell then npc:CastSpell(npc, mountSpell, true) end
            end
            return true
        end
    end
    return false
end

RegisterPlayerEvent(18, OnPlayerChat)
