module("ms", package.seeall)

local Tag = "apartments_privacy"
local NetTag = "apartment"

local META = FindMetaTable("Player")

if SERVER then
	_M.Apartments.Entered = _M.Apartments.Entered or {}
	local apartments_entered = ms.Apartments.Entered

	function META:GetApartment()
		local length = apartments_entered[self] and #apartments_entered[self]
		return length and length > 0 and apartments_entered[self][length] or nil
	end
else
	function META:GetApartment()
		return self:GetNetData(NetTag)
	end
end

local function CanHear(speaker, listener)
	local speaker_apartment, listener_apartment = speaker:GetApartment(), listener:GetApartment()
	if speaker_apartment == listener_apartment then
		return true
	end

	-- Allow to hear through open entrance
	local door = speaker_apartment and Apartments.GetRooms()[speaker_apartment].entrance
		or listener_apartment and Apartments.GetRooms()[listener_apartment].entrance
	if IsValid(door)
		and door:GetInternalVariable("m_eDoorState") ~= 0
		and door:GetPos():Distance(speaker:GetPos()) < 512
	then
		return true
	end 
end

if SERVER then
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
			apartments_entered[ply] = nil
		end
	end)

	hook.Add("PlayerCanSeePlayersChat", Tag, function(_, _, listener, speaker, is_local)
		if is_local and not CanHear(speaker, listener) then
			return false
		end
	end)

	hook.Add("PlayerCanHearPlayersVoice", Tag, function(listener, talker)
		if not CanHear(talker, listener) then
			return false
		end
	end)

	hook.Add("ChatsoundsCanPlayerHear", Tag, function(speaker, text, listener, _, is_local)
		if not CanHear(speaker, listener) then
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
	-- TODO, hook Easychat
	-- https://github.com/Earu/EasyChat/blob/master/lua/easychat/modules/client/local_ui.lua
	-- https://github.com/Earu/EasyChat/blob/master/lua/easychat/modules/client/voice_hud.lua
end
