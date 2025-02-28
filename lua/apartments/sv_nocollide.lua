module('ms', package.seeall)
local Tag = 'apartment_collide'

local dbg = function(...)
	if not DEBUG then return end
	Msg('[' .. Tag .. '] ')
	print(...)
end

local function ApartmentEnter(ent, trigger, room)
	dbg('IN', ent, 'owner=', room and room.tenant)
	if not ent:IsPlayer() then return end
	if hook.Run('CanPlayerNoCollideWithTeammates', ent, true, ent:GetNoCollideWithTeammates()) == false then return end
	if room.nocollide == false then return end
	ent:SetNoCollideWithTeammates(true)
end

hook.Add('ApartmentEnter', Tag, ApartmentEnter)

local function ApartmentLeave(ent, trigger, room)
	dbg('OUT', ent, 'owner=', room and room.tenant)
	if not ent:IsPlayer() then return end
	if not ent:GetNoCollideWithTeammates() then return end
	if hook.Run('CanPlayerNoCollideWithTeammates', ent, false, true) == false then return end
	ent:SetNoCollideWithTeammates(false)

	timer.Simple(0.4, function()
		if not ent:IsValid() then return end
		ent:UnStuck()
	end)
end

hook.Add('ApartmentLeave', Tag, ApartmentLeave)

function Apartments.SetNoCollide(num, set)
	set = set == nil and true or set
	local room = isnumber(num) and Apartments.GetRooms()[num] or num
	room.nocollide = set

	for ply, _ in pairs(room.trigger:GetPlayers()) do
		if set then
			ApartmentEnter(ply, room.trigger, room)
		else
			ApartmentLeave(ply, room.trigger, room)
		end
	end
end