module("ms", package.seeall)
local tag = "ms_apartments"

util.AddNetworkString(tag)

--[[
	use something like this later when needed

	local ACTIVE_LANDMARK = ""
	for _, name in pairs({"apartments", "apartments2", ...}) do
		if landmark.get(name) then
			ACTIVE_LANDMARK = name
			break
		end
	end
]]

local ACTIVE_LANDMARK = "apartments"

local ROOM_COUNTS = {
	["apartments"] = 12,
}

local TRIGGER_OFFSETS = { -- landmark pos + offset for the position we want
	["apartments"] = { -- this is just ordered from rooms 1 to 12
		Vector(434.849579, -583.250977, -116.000000),
		Vector(434.849579, -1411.250977, -116.000000),
		Vector(-445.150421, -583.250977, -116.000000),
		Vector(-445.150421, -1411.250977, -116.000000),
		Vector(434.849579, -583.250977, 76.000000),
		Vector(434.849579, -1411.250977, 76.000000),
		Vector(-445.150421, -583.250977, 76.000000),
		Vector(-445.150421, -1411.250977, 76.000000),
		Vector(434.849579, -583.250977, 244.000000),
		Vector(434.849579, -1411.250977, 244.000000),
		Vector(-445.150421, -583.250977, 244.000000),
		Vector(-445.150421, -1411.250977, 244.000000)
	}
}

local ROOM_SEARCH = { -- entrance search bounds, at what index is our entrance at by the end
	["apartments"] = { bounds = Vector(370, 370, 5), index = 1 }
}

local Apartments = Apartments or { NUM_ROOMS = ROOM_COUNTS[ACTIVE_LANDMARK] }
_M.Apartments = Apartments

local rooms, tenants, triggers, entrances
if Apartments.GetRooms then
	rooms = table.Copy(Apartments.GetRooms())
	tenants = table.Copy(Apartments.GetTenants())
	triggers = table.Copy(Apartments.GetTriggers())
	entrances = table.Copy(Apartments.GetEntrances())
else
	rooms = {}
	tenants = {}
	triggers = {}
	entrances = {}
end

local entrance_last_knocked = {}
local knocks_accumulated = {}

local PASSAGE_GUESTS = 1
local PASSAGE_FRIENDS = 2
local PASSAGE_ALL = 3

local TRANSFER_TRANSFER = 1
local TRANSFER_WILL = 2

local SV_NET_UPDATE_BOTH = 1
local SV_NET_UPDATE_ROOMS = 2
local SV_NET_UPDATE_ENTRANCES = 3

local CL_NET_RENT = 4
local CL_NET_INVITE = 5
local CL_NET_PASSAGE = 6
local CL_NET_TRANSFER = 7
local CL_NET_BLACKLIST = 8

function Apartments.log_event(log_type, ...)
	if not metalog or not metalog[log_type] then return end

	metalog[log_type]("Apartments", nil, ...)
end

local log_event = Apartments.log_event

local function net_broadcast_table(id, tbl)
	net.Start(tag)
	net.WriteUInt(id, 32)

	local payload = util.Compress(util.TableToJSON(tbl))
	net.WriteUInt(#payload, 32)
	net.WriteData(payload)

	net.Broadcast()
end

local function is_valid_room(room_number)
	return room_number and rooms[room_number]
end

local function is_valid_client_request(ply, id, room_number, state)
	local room = rooms[room_number]

	if id == CL_NET_RENT and state == 1 and tenants[ply:SteamID64()] then
		return false
	end

	if id ~= CL_NET_RENT and not room.tenant then
		return false
	end

	if room.tenant and room.tenant ~= ply:SteamID64() then
		return false
	end

	return true
end

local function get_room_entrance(room_number)
	local trigger_pos = landmark.get(ACTIVE_LANDMARK) + TRIGGER_OFFSETS[ACTIVE_LANDMARK][room_number]
	local box_bounds = ROOM_SEARCH[ACTIVE_LANDMARK].bounds
	local mins, maxs = trigger_pos - box_bounds, trigger_pos + box_bounds
	local near = ents.FindInBox(mins, maxs)

	local cmp_vec = Vector()
	trigger_pos.z = 0

	local doors = {}
	for _, ent in pairs(near) do
		if ent:GetClass() == "prop_door_rotating" then
			cmp_vec:Set(ent:GetPos())
			cmp_vec.z = 0

			doors[#doors + 1] = { ent, trigger_pos:DistToSqr(cmp_vec) }
		end
	end

	table.sort(doors, function(a, b) return a[2] > b[2] end)

	-- relies on the map
	local result_index = ROOM_SEARCH[ACTIVE_LANDMARK].index
	return doors[result_index][1]
end

local function should_entity_be_in_room(ent, room)
	if not room.tenant then return true end

	local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
	if not IsValid(owner) or owner.Unrestricted then
		return true
	end

	if room.blacklist and room.blacklist[owner:SteamID64()] then
		return false
	end

	if room.guests[owner:UserID()] then
		return true
	end

	local tenant = player.GetBySteamID64(room.tenant)
	if tenant and owner == tenant then
		return true
	end

	return false
end

local function should_player_be_in_room(ply, room)
	if room.tenant and not ply.Unrestricted then
		local tenant = player.GetBySteamID64(room.tenant)
		if tenant and ply == tenant then
			return true
		end

		if room.blacklist and room.blacklist[ply:SteamID64()] then
			return false
		end

		if room.guests[ply:UserID()] then
			return true
		end

		if room.passage == PASSAGE_ALL then
			return true
		end

		if room.passage == PASSAGE_FRIENDS and tenant and tenant.IsFriend and tenant:IsFriend(ply) then
			return true
		end
	else
		return true
	end

	return false
end

local function knock_on_entrance(entrance)
	for i = 1, 3 do
		timer.Simple(i * .25, entrance.EmitSound, entrance, "physics/wood/wood_box_impact_soft1.wav", 80)
	end
end

function Apartments.GetRooms()
	return rooms
end

function Apartments.GetTenants()
	return tenants
end

function Apartments.GetEntrances()
	return entrances
end

function Apartments.GetTriggers()
	return triggers
end

function Apartments.SetTenant(room_number, tenant)
	if not is_valid_room(room_number) or not tenant:IsPlayer() then return end
	if tenants[tenant:SteamID64()] then return end

	local room = rooms[room_number]
	tenants[tenant:SteamID64()] = room_number
	room.tenant = tenant:SteamID64()
	room.passage = PASSAGE_ALL
	room.guests = {}
	room.blacklist = {}

	room._grace = nil
	room._willed_to = nil

	hook.Run("ApartmentStateChanged", room)

	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
	log_event("info", tenant:Nick(), "rented", room.name)

	tenant:ChatPrint("You now own " .. room.name .. ".\nNote that passage is public by default!")
end

function Apartments.TransferTenant(room_number, new_tenant)
	if not is_valid_room(room_number) or not new_tenant:IsPlayer() then return end
	if tenants[new_tenant:SteamID64()] then return end

	local room = rooms[room_number]
	local old_tenant = room.tenant
	if not old_tenant then return end

	tenants[old_tenant] = nil
	room._willed_to = nil
	room._grace = nil

	tenants[new_tenant:SteamID64()] = room_number
	room.tenant = new_tenant:SteamID64()

	hook.Run("ApartmentStateChanged", room)

	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
	log_event("info", new_tenant:Nick(), "received", room.name, "by transfer from", old_tenant)

	new_tenant:ChatPrint("You've been transferred ownership of " .. room.name .. "!")

	local old_tenant_ply = player.GetBySteamID64(old_tenant)
	if old_tenant_ply then
		old_tenant_ply:ChatPrint("You've lost ownership of " .. room.name .. "!")
	end
end

function Apartments.EvictTenant(tenant)
	local tenant_sid64 = tenant.IsPlayer and tenant:IsPlayer() and tenant:SteamID64() or tenant
	if not tenants[tenant_sid64] then return end

	local room = rooms[tenants[tenant_sid64]]
	tenants[tenant_sid64] = nil
	room.tenant = nil
	room.passage = PASSAGE_GUESTS
	room.guests = {}
	room.blacklist = {}

	room._grace = nil
	room._willed_to = nil

	hook.Run("ApartmentStateChanged", room)

	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
	log_event("info", tenant.Nick and tenant:Nick() or tenant, "evicted from", room.name)
end

function Apartments.GetTenant(room_number)
	if not is_valid_room(room_number) then return end

	return rooms[room_number].tenant
end

function Apartments.Invite(room_number, guest)
	if not is_valid_room(room_number) or not guest:IsPlayer() then return end

	local room = rooms[room_number]
	local tenant = player.GetBySteamID64(room.tenant)

	room.guests[guest:UserID()] = true
	guest:ChatPrint(tenant:Nick() .. " has invited you to " .. room.name .. "!")

	hook.Run("ApartmentStateChanged", room)

	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)

	tenant:ChatPrint("Invite sent to " .. guest:Nick())
	log_event("info", guest:Nick(), "was invited to", room.name)
end

function Apartments.RevokeInvitation(room_number, guest)
	if not is_valid_room(room_number) or not guest:IsPlayer() then return end

	local room = rooms[room_number]
	local tenant = player.GetBySteamID64(room.tenant)
	local guest_uid = guest:UserID()

	if room.guests[guest_uid] then
		room.guests[guest_uid] = nil

		if room.trigger.pllist[guest_uid] and room.passage ~= PASSAGE_ALL
		and not (room.passage == PASSAGE_FRIENDS and tenant.IsFriend and tenant:IsFriend(guest)) then
			guest:SetPos(landmark.get("apartments") or Vector())
			guest:ChatPrint("You've been kicked out!")
		end

		hook.Run("ApartmentStateChanged", room)

		net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
		log_event("info", "invite revoked for", guest:Nick(), "from", room.name)
	end
end

function Apartments.SetBlacklist(room_number, target, state)
	if not is_valid_room(room_number) or not target:IsPlayer() then return end

	local room = rooms[room_number]
	room.blacklist = room.blacklist or {}

	local target_sid64 = target:SteamID64()
	if target_sid64 == room.tenant then return end

	local tenant = player.GetBySteamID64(room.tenant)

	if tobool(state) then
		if target.Unrestricted then
			if tenant then tenant:ChatPrint("You can't blacklist that player.") end
			return
		end

		room.blacklist[target_sid64] = true
		room.guests[target:UserID()] = nil

		if room.trigger and room.trigger.pllist[target:UserID()] then
			target:SetPos(landmark.get("apartments") or Vector())
			target:ChatPrint("You've been blacklisted from " .. room.name .. "!")
		end

		if tenant then tenant:ChatPrint(target:Nick() .. " has been blacklisted from " .. room.name .. ".") end
		log_event("info", target:Nick(), "was blacklisted from", room.name)
	else
		if not room.blacklist[target_sid64] then return end
		room.blacklist[target_sid64] = nil

		if tenant then tenant:ChatPrint(target:Nick() .. " is no longer blacklisted from " .. room.name .. ".") end
		log_event("info", target:Nick(), "was unblacklisted from", room.name)
	end

	hook.Run("ApartmentStateChanged", room)
	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
end

function Apartments.GetInvited(room_number, guest)
	if not is_valid_room(room_number) or guest and not guest:IsPlayer() then return end

	if not guest then
		return rooms[room_number].guests
	end

	return rooms[room_number].guests[guest:UserID()]
end

function Apartments.SetPassage(room_number, state)
	if not is_valid_room(room_number) then return end

	local room = rooms[room_number]
	room.passage = state

	local tenant = player.GetBySteamID64(room.tenant)

	if state < PASSAGE_ALL then
		for ply in pairs(room.trigger:GetPlayers()) do
			if ply == tenant then continue end

			local is_guest = room.guests[ply:UserID()]

			if state == PASSAGE_GUESTS and not is_guest then
				ply:SetPos(landmark.get("apartments") or Vector())
			elseif state == PASSAGE_FRIENDS and not is_guest and tenant.IsFriend and not tenant:IsFriend(ply) then
				ply:SetPos(landmark.get("apartments") or Vector())
			end
		end
	end

	hook.Run("ApartmentStateChanged", room)

	net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)

	local state_print = ({"'Guests Only'", "'Guests & Friends'", "'Everyone'"})[state] or "INVALID??"

	tenant:ChatPrint("Passage set to " .. state_print .. ".")
	log_event("info", "passage set to", state_print, "for", room.name)
end

function Apartments.GetPassage(room_number)
	if not is_valid_room(room_number) then return end

	return rooms[room_number].passage
end

function Apartments.RecoverEntrances()
	local count = 0

	for room_number = 1, Apartments.NUM_ROOMS do
		local room = rooms[room_number]
		if IsValid(room.entrance) then continue end

		local entrance = get_room_entrance(room_number)
		if not IsValid(entrance) then
			log_event("error", "FAILED TO RECOVER ENTRANCE FOR", room.name)

			return
		end

		entrances[entrance:EntIndex()] = room_number
		room.entrance = entrance

		count = count + 1
	end

	if count > 0 then
		net_broadcast_table(SV_NET_UPDATE_ENTRANCES, entrances)
		log_event("info", "recovered", count, "entrances")
	end
end

timer.Create(tag .. "_recover_entrances", 5 * 60, 0, Apartments.RecoverEntrances)

net.Receive(tag, function(_, ply)
	local id = net.ReadUInt(32)
	local room_number = net.ReadUInt(32)
	local state = net.ReadUInt(32)

	local room = rooms[room_number]

	if not is_valid_room(room_number) or not is_valid_client_request(ply, id, room_number, state) then
		log_event("warn", "caught bad request from", ply:Nick())

		return
	end

	if id == CL_NET_RENT then
		if tobool(state) then
			Apartments.SetTenant(room_number, ply)
		else
			Apartments.EvictTenant(ply)
		end

		return
	end

	if id == CL_NET_INVITE then
		local guest = Player(net.ReadUInt(32))

		if tobool(state) then
			Apartments.Invite(room_number, guest)
		else
			Apartments.RevokeInvitation(room_number, guest)
		end

		return
	end

	if id == CL_NET_PASSAGE then
		Apartments.SetPassage(room_number, state)

		return
	end

	if id == CL_NET_BLACKLIST then
		local target = Player(net.ReadUInt(32))
		if not target:IsPlayer() then return end

		Apartments.SetBlacklist(room_number, target, state)

		return
	end

	if id == CL_NET_TRANSFER then
		local new_tenant = net.ReadPlayer()
		if not new_tenant:IsPlayer() then return end

		if state == TRANSFER_TRANSFER then
			Apartments.TransferTenant(room_number, new_tenant)
		elseif state == TRANSFER_WILL then
			if room._willed_to ~= new_tenant then
				room._willed_to = new_tenant
				ply:ChatPrint("You've willed your room to " .. new_tenant:Nick())
				new_tenant:ChatPrint(ply:Nick() .. " has willed " .. room.name .. " to you!")

				log_event("info", ply, "willed their apartment to", new_tenant)
			else
				room._willed_to = nil
				ply:ChatPrint("Will undone.")
				new_tenant:ChatPrint(room.name .. " is no longer willed to you.")

				log_event("info", ply, "undid will for", room.name)
			end
		end
	end
end)

hook.Add("PlayerFullyConnected", tag, function(ply)
	net.Start(tag)
	net.WriteUInt(SV_NET_UPDATE_BOTH, 32)

	local rooms_payload = util.Compress(util.TableToJSON(rooms))
	net.WriteUInt(#rooms_payload, 32)
	net.WriteData(rooms_payload)

	local entrances_payload = util.Compress(util.TableToJSON(entrances))
	net.WriteUInt(#entrances_payload, 32)
	net.WriteData(entrances_payload)

	net.Send(ply)

	local room_number = tenants[ply:SteamID64()]
	if room_number then
		local room = rooms[room_number]
		room._grace = nil

		log_event("info", room.name, "restored from grace")
	end
end)

hook.Add("PlayerDisconnected", tag, function(ply)
	local ply_sid64 = ply:SteamID64()
	local room_number = tenants[ply_sid64]
	if room_number then
		local room = rooms[room_number]
		room._grace = true

		log_event("info", room.name, "entering grace for 5 minutes")

		timer.Simple(60 * 5, function()
			if room._grace then
				room._grace = nil

				if IsValid(room._willed_to) then
					Apartments.TransferTenant(room_number, room._willed_to)
					room._willed_to = nil

					return
				end

				log_event("info", "grace expired for", room.name)
				Apartments.EvictTenant(ply_sid64)
			end
		end)
	end
end)

hook.Add("TriggerPreInclude", tag, function(place, TRIGGER)
	local place_match = string.match(place, "trigger_apartment_%d%d")
	if not place_match then return end

	local room_number = tonumber(place:match("%d%d"))

	function TRIGGER:Init()
		self:EnablePlayerCounting()
		self:EnablePlayerList()
		self:EnableEntityList()
		self:EnablePlayerInforming()
	end

	function TRIGGER:In(ent, is_player)
		local room = Apartments.GetRooms()[room_number]

		timer.Simple(0, function()
			if not is_player and not should_entity_be_in_room(ent, room) then
				if not ent:IsVehicle() and ent.Dissolve then ent:Dissolve() end
				SafeRemoveEntityDelayed(ent, 3)

				return
			end

			if is_player and not should_player_be_in_room(ent, room) then
				ent:SetPos(landmark.get("apartments") or Vector())
				ent:ChatPrint("You can't enter " .. room.name .. "!")

				return
			end

			hook.Run("ApartmentEnter", ent, self, room)
		end)
	end

	function TRIGGER:Out(ent, is_player)
		if is_player then
			local room = Apartments.GetRooms()[room_number]
			hook.Run("ApartmentLeave", ent, self, room)
		end
	end

	return true -- overrides any includes, suppress missing logic warnings
end)

hook.Add("InitPostEntity", tag, function()
	rooms = {}
	tenants = {}
	triggers = {}
	entrances = {}

	for room_number = 1, Apartments.NUM_ROOMS do
		local as_two_digits = string.format("%02d", room_number)

		local entrance = get_room_entrance(room_number)

		local trigger_name = "trigger_apartment_" .. as_two_digits
		local trigger = GetTrigger(trigger_name)

		entrances[entrance:EntIndex()] = room_number
		triggers[trigger] = room_number

		rooms[room_number] = {
			name = "Apt. Room " .. as_two_digits,
			entrance = entrance,
			trigger = trigger,
			passage = PASSAGE_GUESTS,
			guests = {},
			blacklist = {},
			-- tenant
		}
	end
end)

hook.Add("PostCleanupMap", tag, function()
	entrances = {}
	triggers = {}

	for room_number = 1, Apartments.NUM_ROOMS do
		local room = rooms[room_number]
		local as_two_digits = string.format("%02d", room_number)

		local entrance = get_room_entrance(room_number)

		local trigger_name = "trigger_apartment_" .. as_two_digits
		local trigger = GetTrigger(trigger_name)

		room.trigger = trigger
		room.entrance = entrance

		entrances[entrance:EntIndex()] = room_number
		triggers[trigger] = room_number
	end

	net_broadcast_table(SV_NET_UPDATE_ENTRANCES, entrances)
end)

hook.Add("PlayerUse", tag .. "_knocking", function(ply, ent)
	local room_number = entrances[ent:EntIndex()]
	if not room_number then return end

	local room = rooms[room_number]
	if not room.tenant then return end

	local tenant = player.GetBySteamID64(room.tenant)
	if ply.Unrestricted or tenant == ply then return end

	if room.blacklist and room.blacklist[ply:SteamID64()] then return false end

	if room.passage == PASSAGE_ALL then return end

	local is_guest = room.guests[ply:UserID()]
	if room.passage == PASSAGE_GUESTS and is_guest then return end
	if (room.passage == PASSAGE_FRIENDS and is_guest) or (tenant and tenant.IsFriend and tenant:IsFriend(ply)) then return end

	if not entrance_last_knocked[ply] then entrance_last_knocked[ply] = CurTime() - 20 end
	if entrance_last_knocked[ply] + 20 > CurTime() then return false end

	if not knocks_accumulated[ply] then
		knocks_accumulated[ply] = 1

		timer.Simple(900, function() -- 15 minutes
			knocks_accumulated[ply] = nil
		end)
	else
		knocks_accumulated[ply] = knocks_accumulated[ply] + 1
	end

	entrance_last_knocked[ply] = CurTime()

	if knocks_accumulated[ply] >= 4 then
		ply:ChatPrint("You're knocking too much! Please wait a while.")

		return false
	end

	knock_on_entrance(ent)

	if room.trigger.pllist[tenant:UserID()] then
		tenant:ChatPrint(ply:Nick(), "is at your door!")
	end

	return false
end)