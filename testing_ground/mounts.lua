local HELPER_NPC_IDS = {9400000, 9400001, 9400002, 9400003, 9400004} -- Valid helper creature IDs
local MountedHelpers = {}

-- Function to initialize and verify NPCs
local function GetNPC(player, helperID)
    local npcList = player:GetCreaturesInRange(50) -- Adjust the range as needed
    for _, npc in ipairs(npcList) do
        if npc:GetEntry() == helperID and npc:GetOwnerGUID() == player:GetGUID() then
            return npc
        end
    end
    return nil
end

-- Function to command helpers to mount up
local function MountHelpers(player)
    for _, helperID in ipairs(HELPER_NPC_IDS) do
        local npc = GetNPC(player, helperID)
        if npc and npc:IsAlive() and not npc:IsMounted() then
            npc:Mount(447413) -- Fixed mount spell ID
            MountedHelpers[helperID] = true
            print("[DEBUG] Helper with ID", helperID, "mounted successfully.")
        end
    end
end

-- Function to command helpers to dismount
local function DismountHelpers(player)
    for _, helperID in ipairs(HELPER_NPC_IDS) do
        local npc = GetNPC(player, helperID)
        if npc and npc:IsAlive() and npc:IsMounted() then
            npc:Dismount()
            MountedHelpers[helperID] = false
            print("[DEBUG] Helper with ID", helperID, "dismounted successfully.")
        end
    end
end

-- Function to check player's aura and synchronize helper mounts
local function SyncHelperMounts(player)
    if player:HasAura(32, 6, 100) then -- Checks the mount-related aura
        MountHelpers(player)
    else
        DismountHelpers(player)
    end
end

-- Function to periodically check the player's mount state
local function CheckPlayerMountState(event, player)
    SyncHelperMounts(player)
end

-- Register the event to synchronize mounts periodically
RegisterPlayerEvent(27, CheckPlayerMountState) -- Replace 27 with the appropriate periodic event ID
