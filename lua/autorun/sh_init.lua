module("ms", package.seeall)
local tag = "ms_apartments"

local Apartments = Apartments or {}
_M.Apartments = Apartments

Apartments.NUM_ROOMS = 12
Apartments.List = Apartments.List or {}
Apartments.Tenants = Apartments.Tenants or {}
Apartments.Entrances = Apartments.Entrances or {}

-- includes
if SERVER then
	util.AddNetworkString(tag)

	AddCSLuaFile("apartments/cl_apartments.lua")
	AddCSLuaFile("apartments/cl_skybox.lua")

	include("apartments/sv_apartments.lua")
end

if CLIENT then
	include("apartments/cl_apartments.lua")
	include("apartments/cl_skybox.lua")
end

-- room list setup
if SERVER then
	local box_bounds = Vector(370, 370, 5)
	local function get_entrance(trigger_pos, room_n)
		local mins, maxs = trigger_pos - box_bounds, trigger_pos + box_bounds
		local near = ents.FindInBox(mins, maxs)

		local cmp_vec = Vector()
		trigger_pos.z = 0

		local doors = {}
		for _, ent in pairs(near) do
			if ent:GetClass() ~= "prop_door_rotating" then continue end

			cmp_vec:Set(ent:GetPos())
			cmp_vec.z = 0

			doors[#doors + 1] = {ent, trigger_pos:DistToSqr(cmp_vec)}
		end

		table.sort(doors, function(a, b) return a[2] > b[2] end)

		return doors[1][1]
	end

	local function setup_list()
		for room_n = 1, Apartments.NUM_ROOMS do
			local as_two_digits = string.format("%02d", room_n)

			local trigger_name = "trigger_apartment_" .. as_two_digits
			local trigger = GetTrigger(trigger_name)

			local entrance = get_entrance(trigger:GetPos(), room_n)

			Apartments.Entrances[entrance] = room_n
			Apartments.Triggers[trigger] = room_n

			Apartments.List[room_n] = {
				name = "Apt. Room " .. as_two_digits,
				entrance = entrance,
				trigger = trigger,
				invitees = {},
--				tenant
			}
		end
	end

	hook.Add("InitPostEntity", tag, setup_list)
end

if CLIENT then
	local function setup_list()
		for room_n = 1, Apartments.NUM_ROOMS do
			Apartments.List[room_n] = {
				name = "Apt. Room " .. string.format("%02d", room_n),
				invitees = {},
--				tenant
			}
		end
	end

	hook.Add("InitPostEntity", tag, setup_list)
end