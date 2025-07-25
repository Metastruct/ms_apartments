if not MetAchievements then return end

local tag = "MetAchievements"
local id = "apartments_rent"

resource.AddFile("materials/metachievements/" .. id .. "/s1/icon.png")

MetAchievements.RegisterAchievement(id, {
    title = "Antisocial",
    description = "You joined a multiplayer server only to hole up in a private room.",
})

hook.Add("ApartmentEnter", ("%s_%s"):format(tag, id), function(ent, trigger, room)
    if not ent:IsPlayer() or MetAchievements.HasAchievement(ent, id) then return end

    local tenant = player.GetBySteamID64(room.tenant)
    if not tenant and not ent._aptinfogiven then
        ent:ChatPrint("NOTE: You may rent a room by pressing your reload key (default: R) on an apartment door.")
        ent._aptinfogiven = true

        return
    end

    if ent == tenant then
        MetAchievements.UnlockAchievement(ent, id)
    end
end)