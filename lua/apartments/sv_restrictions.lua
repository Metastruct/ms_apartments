module("ms", package.seeall)
local tag = "ms_apartments"

Apartments.session_blacklist = Apartments.session_blacklist or {}
local session_blacklist = Apartments.session_blacklist

function Apartments.TempBan(ply)
	local ply_sid64 = ply.IsPlayer and ply:IsPlayer() and ply:SteamID64() or ply
	session_blacklist[ply_sid64] = true

	ply = player.GetBySteamID64(ply_sid64)
	if ply then
		ply:Spawn()
		ply:ChatPrint("You've been temporarily banned from entering the apartments!")
	end

	Apartments.log_event("info", "temporarily banned", ply_sid64, "from apartments")
end

function Apartments.Unban(ply)
	local ply_sid64 = ply.IsPlayer and ply:IsPlayer() and ply:SteamID64() or ply
	session_blacklist[ply_sid64] = nil

	Apartments.log_event("info", "unbanned", ply_sid64, "from apartments")
end

function Apartments.TriggerIn(ent, is_ply)
	if not is_ply then return end

	if session_blacklist[ent:SteamID64()] then
		ent:Spawn()
		ent:ChatPrint("You've been temporarily banned from entering the apartments!")

		return
	end

	ent:SetAllowBuild(false, tag)
end

function Apartments.TriggerOut(ent, is_ply)
	if not is_ply then return end

	ent:SetAllowBuild(true, tag)
end

hook.Add("ApartmentEnter", tag .. "_building", function(ent, trigger, room)
	if not IsValid(ent) or not ent:IsPlayer() then return end

	timer.Simple(0, function() -- just in case
		if not trigger.pllist[ent:UserID()] then return end

		if ent:CanBuild() and not room.tenant == ent:SteamID64() and not room.guests[ent:UserID()] then
			ent:SetAllowBuild(false, tag)
		end

		if not ent:CanBuild() and room.tenant == ent:SteamID64() or room.guests[ent:UserID()] then
			ent:SetAllowBuild(true, tag)
		end
	end)
end)

hook.Add("ApartmentLeave", tag .. "_building", function(ent, trigger, room)
	if not IsValid(ent) or not ent:IsPlayer() then return end

	local apt_trigger = GetTrigger("apartments")
	if ent:CanBuild() and apt_trigger.pllist[ent:UserID()] then
		ent:SetAllowBuild(false, tag)
	end
end)

hook.Add("ApartmentStateChanged", tag, function(room)
	if not IsValid(room.trigger) then return end

	for ply, uid in pairs(room.trigger:GetPlayers()) do
		if room.tenant == ply:SteamID64() then
			ply:SetAllowBuild(true, tag)
			continue
		end

		if room.guests[uid] and not ply:CanBuild() then
			ply:SetAllowBuild(true, tag)
			continue
		end

		if not room.guests[uid] and ply:CanBuild() then
			ply:SetAllowBuild(false, tag)
		end
	end
end)