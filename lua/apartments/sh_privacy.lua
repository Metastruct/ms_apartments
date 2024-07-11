module("ms", package.seeall)

local Tag = "apartments_privacy"
local NetTag = "apartment"

if SERVER then
    _M.Apartments.Entered = _M.Apartments.Entered or {}
    local apartments_entered = ms.Apartments.Entered

    local function GetApartment(ply)
        local length = apartments_entered[ply] and #apartments_entered[ply]
        return length and length > 0 and apartments_entered[ply][length] or nil
    end

    local function CanHear(speaker, listener)
        return GetApartment(speaker) == GetApartment(listener)
    end

    hook.Add("ApartmentEnter", Tag, function(ply, trigger, room)
        if not ply:IsPlayer() then return end
        local index = tonumber(trigger.place:match("%d%d"))
        apartments_entered[ply] = apartments_entered[ply] or {}
        table.insert(apartments_entered[ply], index)
        ply:SetNetData(NetTag, index)
    end)

    hook.Add("ApartmentLeave", Tag, function(ply, trigger, room)
        if not ply:IsPlayer() or not apartments_entered[ply] then return end
        local index = tonumber(trigger.place:match("%d%d"))

        -- Avoid race conditions from overlapping triggers
        local entered = apartments_entered[ply]
        table.RemoveByValue(entered, index)
        if #entered > 0 then
            ply:SetNetData(NetTag, entered[#entered])
        else
            ply:SetNetData(NetTag, nil)
        end
    end)

    hook.Add("PlayerCanSeePlayersChat", Tag, function(_, _, listener, speaker, is_local)
        if is_local and not CanHear(listener, speaker) then
            return false
        end
    end)

    hook.Add("PlayerCanHearPlayersVoice", Tag, function(listener, talker)
        if not CanHear(listener, talker) then
            return false
        end
    end)

    hook.Add("ChatsoundsCanPlayerHear", Tag, function(speaker, text, listener, _, is_local)
        if not CanHear(listener, speaker) then
            return false
        end
    end)

    util.OnInitialize(
        function()
            ms.Apartments = ms.Apartments or {}
            ms.Apartments.Entered = ms.Apartments.Entered or {}
            apartments_entered = ms.Apartments.Entered
        end
    )
else
    local function CanHear(speaker, listener)
        return speaker:GetNetData(NetTag) ~= listener:GetNetData(NetTag)
    end
        
    -- TODO, hook Easychat
    -- https://github.com/Earu/EasyChat/blob/master/lua/easychat/modules/client/local_ui.lua
    -- https://github.com/Earu/EasyChat/blob/master/lua/easychat/modules/client/voice_hud.lua
end
